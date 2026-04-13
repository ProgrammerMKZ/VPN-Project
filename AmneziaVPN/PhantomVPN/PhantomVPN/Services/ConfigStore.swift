import Foundation
import Combine
import SwiftUI

@MainActor
final class ConfigStore: ObservableObject {
    @Published private(set) var configs: [AmneziaWGConfig] = []
    @Published var selectedConfigId: UUID?

    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    static let shared = ConfigStore()

    private var storageURL: URL {
        let appGroup = "group.com.phantomVPN.PhantomVPN"
        if let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroup) {
            return containerURL.appendingPathComponent("configs.json")
        }
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("configs.json")
    }

    var selectedConfig: AmneziaWGConfig? {
        configs.first { $0.id == selectedConfigId }
    }

    init() {
        load()
    }

    func add(_ config: AmneziaWGConfig) {
        configs.append(config)
        if selectedConfigId == nil {
            selectedConfigId = config.id
        }
        save()
    }

    func remove(at offsets: IndexSet) {
        let removedIds = offsets.map { configs[$0].id }
        configs.remove(atOffsets: offsets)
        if let selectedId = selectedConfigId, removedIds.contains(selectedId) {
            selectedConfigId = configs.first?.id
        }
        save()
    }

    func remove(id: UUID) {
        configs.removeAll { $0.id == id }
        if selectedConfigId == id {
            selectedConfigId = configs.first?.id
        }
        save()
    }

    func select(_ id: UUID) {
        selectedConfigId = id
    }

    func update(_ config: AmneziaWGConfig) {
        guard let index = configs.firstIndex(where: { $0.id == config.id }) else { return }
        configs[index] = config
        save()
    }

    private func save() {
        do {
            let data = try encoder.encode(configs)
            try data.write(to: storageURL, options: .atomic)
            syncToAppGroup()
        } catch {
            print("ConfigStore save error: \(error)")
        }
    }

    private func load() {
        do {
            let data = try Data(contentsOf: storageURL)
            configs = try decoder.decode([AmneziaWGConfig].self, from: data)
            if selectedConfigId == nil {
                selectedConfigId = configs.first?.id
            }
        } catch {
            configs = []
        }
    }

    private func syncToAppGroup() {
        guard let selected = selectedConfig else { return }
        let appGroup = "group.com.phantomVPN.PhantomVPN"
        guard let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else { return }

        let activeConfigURL = containerURL.appendingPathComponent("active_config.json")
        do {
            let data = try encoder.encode(selected)
            try data.write(to: activeConfigURL, options: .atomic)
        } catch {
            print("ConfigStore sync error: \(error)")
        }
    }
}
