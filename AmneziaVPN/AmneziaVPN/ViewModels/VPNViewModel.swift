import Foundation
import Combine
import SwiftUI

@MainActor
final class VPNViewModel: ObservableObject {
    @Published var connectionState: ConnectionState = .disconnected
    @Published var stats: ConnectionStats = ConnectionStats()
    @Published var showError: Bool = false
    @Published var errorMessage: String = ""
    @Published var isImporting: Bool = false

    private let vpnManager = VPNManager.shared
    let configStore = ConfigStore.shared
    private var cancellables = Set<AnyCancellable>()

    init() {
        vpnManager.$state
            .receive(on: DispatchQueue.main)
            .assign(to: &$connectionState)

        vpnManager.$stats
            .receive(on: DispatchQueue.main)
            .assign(to: &$stats)
    }

    var selectedConfig: AmneziaWGConfig? {
        configStore.selectedConfig
    }

    var hasConfigs: Bool {
        !configStore.configs.isEmpty
    }

    func toggleConnection() {
        guard let config = selectedConfig else {
            errorMessage = "No server configuration selected"
            showError = true
            return
        }

        Task {
            do {
                try await vpnManager.toggle(with: config)
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    func importConfig(from url: URL) {
        do {
            let config = try ConfigParser.parseFile(at: url)
            configStore.add(config)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    func importConfig(from text: String, name: String? = nil) {
        do {
            let config = try ConfigParser.parse(text, name: name)
            configStore.add(config)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    func selectConfig(_ id: UUID) {
        configStore.select(id)
    }

    func deleteConfig(at offsets: IndexSet) {
        if connectionState.isActive {
            vpnManager.disconnect()
        }
        configStore.remove(at: offsets)
    }

    func deleteConfig(id: UUID) {
        if connectionState.isActive {
            vpnManager.disconnect()
        }
        configStore.remove(id: id)
    }
}
