import SwiftUI

struct ServerListView: View {
    @EnvironmentObject var viewModel: VPNViewModel
    @State private var showImportSheet = false
    @State private var importText = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.darkBackground.ignoresSafeArea()

                if viewModel.configStore.configs.isEmpty {
                    emptyState
                } else {
                    serverList
                }
            }
            .navigationTitle("Servers")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            viewModel.isImporting = true
                        } label: {
                            Label("Import File", systemImage: "doc.badge.plus")
                        }

                        Button {
                            showImportSheet = true
                        } label: {
                            Label("Paste Config", systemImage: "doc.on.clipboard")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
            .fileImporter(
                isPresented: $viewModel.isImporting,
                allowedContentTypes: [.init(filenameExtension: "conf")!],
                allowsMultipleSelection: true
            ) { result in
                if case .success(let urls) = result {
                    for url in urls {
                        viewModel.importConfig(from: url)
                    }
                }
            }
            .sheet(isPresented: $showImportSheet) {
                ImportConfigSheet(configText: $importText) { text, name in
                    viewModel.importConfig(from: text, name: name)
                    showImportSheet = false
                    importText = ""
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "server.rack")
                .font(.system(size: 48))
                .foregroundStyle(Color.subtleGray)

            Text("No Servers")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)

            Text("Import an AmneziaWG configuration\nfile to add a server")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)

            Button {
                viewModel.isImporting = true
            } label: {
                Label("Import Config", systemImage: "doc.badge.plus")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.accentGreen)
                    .clipShape(Capsule())
            }
            .padding(.top, 8)
        }
    }

    private var serverList: some View {
        List {
            ForEach(viewModel.configStore.configs) { config in
                ServerRow(
                    config: config,
                    isSelected: config.id == viewModel.configStore.selectedConfigId,
                    isConnected: viewModel.connectionState == .connected && config.id == viewModel.configStore.selectedConfigId
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.selectConfig(config.id)
                    }
                }
                .listRowBackground(Color.cardBackground)
                .listRowSeparatorTint(.white.opacity(0.06))
            }
            .onDelete(perform: viewModel.deleteConfig)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}

struct ServerRow: View {
    let config: AmneziaWGConfig
    let isSelected: Bool
    let isConnected: Bool

    var body: some View {
        HStack(spacing: 14) {
            let location = ServerLocation.inferLocation(from: config.peer.endpoint)

            Text(location.flag)
                .font(.title2)

            VStack(alignment: .leading, spacing: 3) {
                Text(config.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)

                Text(config.peer.endpointHost + ":" + config.peer.endpointPort)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
            }

            Spacer()

            if isConnected {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.accentGreen)
                        .frame(width: 6, height: 6)
                    Text("Active")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color.accentGreen)
                }
            } else if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentGreen)
            }
        }
        .padding(.vertical, 4)
    }
}

struct ImportConfigSheet: View {
    @Binding var configText: String
    @State private var configName = ""
    let onImport: (String, String?) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.darkBackground.ignoresSafeArea()

                VStack(spacing: 20) {
                    TextField("Config Name (optional)", text: $configName)
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal)

                    TextEditor(text: $configText)
                        .font(.system(.caption, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .background(Color.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                        .overlay(alignment: .topLeading) {
                            if configText.isEmpty {
                                Text("Paste AmneziaWG config here...")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.3))
                                    .padding(.horizontal, 22)
                                    .padding(.top, 10)
                                    .allowsHitTesting(false)
                            }
                        }
                }
                .padding(.top)
            }
            .navigationTitle("Paste Config")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        onImport(configText, configName.isEmpty ? nil : configName)
                    }
                    .disabled(configText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.large])
    }
}
