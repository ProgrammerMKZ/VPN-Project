import SwiftUI
import UniformTypeIdentifiers

struct ServerListView: View {
    @EnvironmentObject var viewModel: VPNViewModel
    @State private var showImportSheet = false
    @State private var importText = ""

    private let mono = Font.custom("Courier New", size: 13)
    private let monoSmall = Font.custom("Courier New", size: 11)

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
            .navigationTitle("SERVERS")
            .iOSNavigationBarLarge()
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Menu {
                        Button {
                            viewModel.isImporting = true
                        } label: {
                            Label("IMPORT FILE", systemImage: "doc.badge.plus")
                        }

                        Button {
                            showImportSheet = true
                        } label: {
                            Label("PASTE CONFIG", systemImage: "doc.on.clipboard")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.black.opacity(0.7))
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

            Text("NO SERVERS")
                .font(Font.custom("Courier New", size: 17))
                .foregroundStyle(.black)

            Text("IMPORT AN AMNEZIAWG CONFIGURATION\nFILE TO ADD A SERVER")
                .font(monoSmall)
                .foregroundStyle(.black.opacity(0.4))
                .multilineTextAlignment(.center)

            Button {
                viewModel.isImporting = true
            } label: {
                Label("IMPORT CONFIG", systemImage: "doc.badge.plus")
                    .font(mono)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.black)
                    .clipShape(Rectangle())
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
                .listRowSeparatorTint(.black.opacity(0.12))
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

    private let mono = Font.custom("Courier New", size: 13)
    private let monoSmall = Font.custom("Courier New", size: 11)

    var body: some View {
        HStack(spacing: 14) {
            let location = ServerLocation.inferLocation(from: config.peer.endpoint)

            Text(location.flag)
                .font(.title2)

            VStack(alignment: .leading, spacing: 3) {
                Text(config.name.uppercased())
                    .font(mono)
                    .foregroundStyle(.black)

                Text((config.peer.endpointHost + ":" + config.peer.endpointPort).uppercased())
                    .font(monoSmall)
                    .foregroundStyle(.black.opacity(0.4))
            }

            Spacer()

            if isConnected {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.black)
                        .frame(width: 6, height: 6)
                    Text("ACTIVE")
                        .font(monoSmall)
                        .foregroundStyle(.black)
                }
            } else if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.black)
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

    private let mono = Font.custom("Courier New", size: 13)

    var body: some View {
        NavigationStack {
            ZStack {
                Color.darkBackground.ignoresSafeArea()

                VStack(spacing: 20) {
                    TextField("CONFIG NAME (OPTIONAL)", text: $configName)
                        .font(mono)
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal)

                    TextEditor(text: $configText)
                        .font(.system(.caption, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .foregroundStyle(.black)
                        .background(Color.cardBackground)
                        .clipShape(Rectangle())
                        .overlay(
                            Rectangle().stroke(Color.black, lineWidth: 1)
                        )
                        .padding(.horizontal)
                        .overlay(alignment: .topLeading) {
                            if configText.isEmpty {
                                Text("PASTE AMNEZIAWG CONFIG HERE...")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.black.opacity(0.3))
                                    .padding(.horizontal, 22)
                                    .padding(.top, 10)
                                    .allowsHitTesting(false)
                            }
                        }
                }
                .padding(.top)
            }
            .navigationTitle("PASTE CONFIG")
            .iOSNavigationBarInline()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("CANCEL") { dismiss() }
                        .font(mono)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("IMPORT") {
                        onImport(configText, configName.isEmpty ? nil : configName)
                    }
                    .font(mono)
                    .disabled(configText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .iOSPresentationDetentsLarge()
    }
}
