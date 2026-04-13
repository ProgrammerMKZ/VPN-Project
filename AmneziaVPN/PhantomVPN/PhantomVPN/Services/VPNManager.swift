import Foundation
import NetworkExtension
import Combine

@MainActor
final class VPNManager: ObservableObject {
    @Published private(set) var state: ConnectionState = .disconnected
    @Published private(set) var stats: ConnectionStats = ConnectionStats()

    static let shared = VPNManager()

    private var manager: NETunnelProviderManager?
    private var statusObserver: NSObjectProtocol?
    private var statsTimer: Timer?
    private var isLoaded = false

    private let tunnelBundleId = "com.phantomVPN.PhantomVPN.tunnel"

    init() {
        observeStatusChanges()
    }

    func ensureLoaded() async {
        guard !isLoaded else { return }
        isLoaded = true
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            manager = managers.first
            updateState()
        } catch {
            print("VPNManager load error: \(error)")
        }
    }

    func connect(with config: AmneziaWGConfig) async throws {
        let mgr = self.manager ?? NETunnelProviderManager()
        self.manager = mgr

        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = tunnelBundleId
        proto.serverAddress = config.peer.endpoint

        let configData = try JSONEncoder().encode(config)
        proto.providerConfiguration = [
            "config": configData.base64EncodedString()
        ]

        mgr.protocolConfiguration = proto
        mgr.localizedDescription = "PhantomVPN"
        mgr.isEnabled = true

        try await mgr.saveToPreferences()
        try await mgr.loadFromPreferences()

        let session = mgr.connection as! NETunnelProviderSession
        try session.startTunnel()

        stats = ConnectionStats(connectedSince: Date())
        startStatsTimer()
    }

    func disconnect() {
        manager?.connection.stopVPNTunnel()
        stopStatsTimer()
    }

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
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateState()
            }
        }
    }

    private func updateState() {
        guard let connection = manager?.connection else {
            if state != .disconnected {
                state = .disconnected
            }
            return
        }

        let newState: ConnectionState
        switch connection.status {
        case .invalid: newState = .invalid
        case .disconnected: newState = .disconnected
        case .connecting: newState = .connecting
        case .connected: newState = .connected
        case .reasserting: newState = .reasserting
        case .disconnecting: newState = .disconnecting
        @unknown default: newState = .disconnected
        }

        guard newState != state else { return }
        state = newState

        if state == .connected && stats.connectedSince == nil {
            stats.connectedSince = connection.connectedDate
            startStatsTimer()
        }

        if state == .disconnected {
            stats = ConnectionStats()
            stopStatsTimer()
        }
    }

    private func startStatsTimer() {
        stopStatsTimer()
        statsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollStats()
            }
        }
    }

    private func stopStatsTimer() {
        statsTimer?.invalidate()
        statsTimer = nil
    }

    private func pollStats() {
        guard state == .connected,
              let session = manager?.connection as? NETunnelProviderSession else {
            stopStatsTimer()
            return
        }

        do {
            try session.sendProviderMessage("stats".data(using: .utf8)!) { [weak self] response in
                guard let data = response,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: UInt64] else { return }

                Task { @MainActor in
                    self?.stats.bytesReceived = json["rx"] ?? 0
                    self?.stats.bytesSent = json["tx"] ?? 0
                }
            }
        } catch {
            stopStatsTimer()
        }
    }
}
