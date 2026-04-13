import SwiftUI
import UniformTypeIdentifiers

struct ServerListView: View {
    @EnvironmentObject var viewModel: VPNViewModel
    @State private var showImportSheet = false
    @State private var importText = ""

    private let letterCodes = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")

    var body: some View {
        VStack(spacing: 0) {
            header
            divider

            if viewModel.configStore.configs.isEmpty {
                emptyState
            } else {
                serverList
            }
        }
        .background(Color.white)
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

    private var header: some View {
        HStack {
            Text("NODES")
                .font(MaurtenFont.monoLabel)
                .foregroundStyle(.black)

            Spacer()

            HStack(spacing: 16) {
                Button {
                    viewModel.isImporting = true
                } label: {
                    Text("+ FILE")
                        .font(MaurtenFont.monoSmall)
                        .foregroundStyle(.black)
                }
                .buttonStyle(.plain)

                Button {
                    showImportSheet = true
                } label: {
                    Text("+ PASTE")
                        .font(MaurtenFont.monoSmall)
                        .foregroundStyle(.black)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Text("NO NODES REGISTERED")
                .font(MaurtenFont.monoLabel)
                .foregroundStyle(.black)

            Text("IMPORT AN AMNEZIAWG CONFIGURATION\nFILE TO REGISTER A NODE")
                .font(MaurtenFont.monoSmall)
                .foregroundStyle(.black.opacity(0.4))
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            Button {
                viewModel.isImporting = true
            } label: {
                Text("IMPORT CONFIG")
                    .font(MaurtenFont.monoSmall)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.black)
                    .clipShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 8)

            Spacer()
        }
    }

    private var serverList: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                tableHeader
                divider

                ForEach(Array(viewModel.configStore.configs.enumerated()), id: \.element.id) { index, config in
                    let isSelected = config.id == viewModel.configStore.selectedConfigId
                    let isConnected = viewModel.connectionState == .connected && isSelected

                    serverRow(
                        index: index,
                        config: config,
                        isSelected: isSelected,
                        isConnected: isConnected
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.selectConfig(config.id)
                    }

                    divider
                }
            }
        }
    }

    private var tableHeader: some View {
        HStack(spacing: 0) {
            Text("ID")
                .frame(width: 32, alignment: .leading)
            Text("NODE")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("REGION")
                .frame(width: 80, alignment: .trailing)
            Text("STATUS")
                .frame(width: 72, alignment: .trailing)
        }
        .font(MaurtenFont.monoSmall)
        .foregroundStyle(.black.opacity(0.4))
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
    }

    private func serverRow(index: Int, config: AmneziaWGConfig, isSelected: Bool, isConnected: Bool) -> some View {
        let location = ServerLocation.inferLocation(from: config.peer.endpoint)
        let letter = index < letterCodes.count ? String(letterCodes[index]) : "\(index)"

        return HStack(spacing: 0) {
            Text(letter)
                .frame(width: 32, alignment: .leading)
                .font(MaurtenFont.monoBody)
                .foregroundStyle(.black)

            VStack(alignment: .leading, spacing: 2) {
                Text(config.name.uppercased())
                    .font(MaurtenFont.monoBody)
                    .foregroundStyle(.black)
                Text(config.peer.endpointHost.uppercased())
                    .font(MaurtenFont.monoSmall)
                    .foregroundStyle(.black.opacity(0.35))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(location.code)
                .font(MaurtenFont.mono)
                .foregroundStyle(.black.opacity(0.5))
                .frame(width: 80, alignment: .trailing)

            Text(statusText(isConnected: isConnected, isSelected: isSelected))
                .font(MaurtenFont.monoSmall)
                .foregroundStyle(.black)
                .frame(width: 72, alignment: .trailing)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(isSelected ? Color.black.opacity(0.04) : Color.white)
    }

    private func statusText(isConnected: Bool, isSelected: Bool) -> String {
        if isConnected { return "ACTIVE" }
        if isSelected { return "SELECTED" }
        return "---"
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.black)
            .frame(height: 1)
            .frame(maxWidth: .infinity)
    }
}

struct ServerRow: View {
    let config: AmneziaWGConfig
    let isSelected: Bool
    let isConnected: Bool

    var body: some View {
        let location = ServerLocation.inferLocation(from: config.peer.endpoint)

        HStack(spacing: 0) {
            Text(location.code)
                .font(MaurtenFont.mono)
                .foregroundStyle(.black.opacity(0.5))
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(config.name.uppercased())
                    .font(MaurtenFont.monoBody)
                    .foregroundStyle(.black)
                Text(config.peer.endpointHost.uppercased())
                    .font(MaurtenFont.monoSmall)
                    .foregroundStyle(.black.opacity(0.35))
            }

            Spacer()

            if isConnected {
                Text("ACTIVE")
                    .font(MaurtenFont.monoSmall)
                    .foregroundStyle(.black)
            } else if isSelected {
                Text("SELECTED")
                    .font(MaurtenFont.monoSmall)
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

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader
            sheetDivider

            VStack(alignment: .leading, spacing: 0) {
                Text("CONFIG NAME")
                    .font(MaurtenFont.monoSmall)
                    .foregroundStyle(.black.opacity(0.5))
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                TextField("", text: $configName)
                    .font(MaurtenFont.monoBody)
                    .foregroundStyle(.black)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)

                Rectangle()
                    .fill(Color.black)
                    .frame(height: 1)
                    .padding(.horizontal, 24)

                Text("CONFIGURATION DATA")
                    .font(MaurtenFont.monoSmall)
                    .foregroundStyle(.black.opacity(0.5))
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                TextEditor(text: $configText)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.black)
                    .scrollContentBackground(.hidden)
                    .background(Color.white)
                    .border(Color.black, width: 1)
                    .padding(.horizontal, 24)
                    .frame(minHeight: 200)

                Spacer()

                Button {
                    onImport(configText, configName.isEmpty ? nil : configName)
                } label: {
                    Text("IMPORT")
                        .font(MaurtenFont.monoButton)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.black)
                        .clipShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(configText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(configText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.3 : 1.0)
                .padding(24)
            }
        }
        .background(Color.white)
    }

    private var sheetHeader: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Text("CANCEL")
                    .font(MaurtenFont.monoSmall)
                    .foregroundStyle(.black)
            }
            .buttonStyle(.plain)

            Spacer()

            Text("PASTE CONFIG")
                .font(MaurtenFont.monoLabel)
                .foregroundStyle(.black)

            Spacer()

            Color.clear
                .frame(width: 60)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private var sheetDivider: some View {
        Rectangle()
            .fill(Color.black)
            .frame(height: 1)
            .frame(maxWidth: .infinity)
    }
}
