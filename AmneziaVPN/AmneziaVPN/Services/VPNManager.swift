import Foundation
import NetworkExtension
import Combine

final class VPNManager: ObservableObject {
    @Published private(set) var state: ConnectionState = .disconnected
    @Published private(set) var stats: ConnectionStats = ConnectionStats()

    static let shared = VPNManager()

    private var manager: NETunnelProviderManager?
    private var statusObserver: NSObjectProtocol?
    private var statsTimer: Timer?

    private let tunnelBundleId = "com.amneziavpn.app.tunnel"

    init() {
        observeStatusChanges()
        Task { await loadManager() }
    }

    deinit {
        if let observer = statusObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        statsTimer?.invalidate()
    }

    @MainActor
    func loadManager() async {
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            if let existing = managers.first {
                manager = existing
            } else {
                manager = NETunnelProviderManager()
            }
            updateState()
        } catch {
            print("VPNManager load error: \(error)")
        }
    }

    @MainActor
    func connect(with config: AmneziaWGConfig) async throws {
        let manager = self.manager ?? NETunnelProviderManager()
        self.manager = manager

        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = tunnelBundleId
        proto.serverAddress = config.peer.endpoint

        let configData = try JSONEncoder().encode(config)
        proto.providerConfiguration = [
            "config": configData.base64EncodedString()
        ]

        manager.protocolConfiguration = proto
        manager.localizedDescription = "AmneziaVPN"
        manager.isEnabled = true

        try await manager.saveToPreferences()
        try await manager.loadFromPreferences()

        let session = manager.connection as! NETunnelProviderSession
        try session.startTunnel()

        stats = ConnectionStats(connectedSince: Date())
        startStatsTimer()
    }

    @MainActor
    func disconnect() {
        manager?.connection.stopVPNTunnel()
        statsTimer?.invalidate()
    }

    @MainActor
    func toggle(with config: AmneziaWGConfig) async throws {
        if state.isActive {
            disconnect()
        } else {
            try await connect(with: config)
        }
    }

    private func observeStatusChanges() {
        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.updateState()
        }
    }

    private func updateState() {
        guard let connection = manager?.connection else {
            state = .disconnected
            return
        }

        switch connection.status {
        case .invalid: state = .invalid
        case .disconnected: state = .disconnected
        case .connecting: state = .connecting
        case .connected: state = .connected
        case .reasserting: state = .reasserting
        case .disconnecting: state = .disconnecting
        @unknown default: state = .disconnected
        }

        if state == .connected && stats.connectedSince == nil {
            stats.connectedSince = connection.connectedDate
            startStatsTimer()
        }

        if state == .disconnected {
            stats = ConnectionStats()
            statsTimer?.invalidate()
        }
    }

    private func startStatsTimer() {
        statsTimer?.invalidate()
        statsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.pollStats()
        }
    }

    private func pollStats() {
        guard let session = manager?.connection as? NETunnelProviderSession else { return }

        do {
            try session.sendProviderMessage("stats".data(using: .utf8)!) { [weak self] response in
                guard let data = response,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: UInt64] else { return }

                DispatchQueue.main.async {
                    self?.stats.bytesReceived = json["rx"] ?? 0
                    self?.stats.bytesSent = json["tx"] ?? 0
                }
            }
        } catch {
            // Stats polling is best-effort
        }
    }
}
