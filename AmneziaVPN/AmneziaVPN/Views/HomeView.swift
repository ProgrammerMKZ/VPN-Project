import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    @EnvironmentObject var viewModel: VPNViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            divider

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    statusBlock
                    divider
                    nodeBlock
                    divider

                    if viewModel.connectionState == .connected {
                        sessionBlock
                        divider
                    }

                    Spacer(minLength: 24)

                    connectButton
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                }
            }
        }
        .background(Color.white)
        .fileImporter(
            isPresented: $viewModel.isImporting,
            allowedContentTypes: [.init(filenameExtension: "conf")!],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                viewModel.importConfig(from: url)
            }
        }
    }

    private var header: some View {
        HStack {
            Text("PHANTOM VPN")
                .font(MaurtenFont.monoLabel)
                .foregroundStyle(.black)

            Spacer()

            Button {
                viewModel.isImporting = true
            } label: {
                Text("+ IMPORT")
                    .font(MaurtenFont.monoSmall)
                    .foregroundStyle(.black)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private var statusBlock: some View {
        VStack(spacing: 0) {
            HStack {
                Text("STATUS")
                    .font(MaurtenFont.monoLarge)
                    .foregroundStyle(.black)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 16)

            specRow(label: "STATE", value: viewModel.connectionState.displayText)
            specRow(label: "PROTOCOL", value: "AMNEZIAWG")

            if viewModel.connectionState == .connected {
                specRow(label: "DURATION", value: viewModel.stats.formattedDuration)
            }
        }
    }

    private var nodeBlock: some View {
        VStack(spacing: 0) {
            if let config = viewModel.selectedConfig {
                let location = ServerLocation.inferLocation(from: config.peer.endpoint)
                specRow(label: "NODE ASSIGNED", value: config.name.uppercased())
                specRow(label: "LOCATION", value: location.name)
                specRow(label: "ENDPOINT", value: config.peer.endpointHost.uppercased())
                specRow(label: "PORT", value: config.peer.endpointPort)
            } else {
                HStack {
                    Text("NO NODE ASSIGNED")
                        .font(MaurtenFont.mono)
                        .foregroundStyle(.black.opacity(0.4))
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
        }
    }

    private var sessionBlock: some View {
        VStack(spacing: 0) {
            HStack {
                Text("SESSION DATA")
                    .font(MaurtenFont.monoLabel)
                    .foregroundStyle(.black)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 8)

            specRow(label: "BYTES RECV", value: viewModel.stats.formattedBytesReceived.uppercased())
            specRow(label: "BYTES SENT", value: viewModel.stats.formattedBytesSent.uppercased())
            specRow(label: "ELAPSED", value: viewModel.stats.formattedDuration)
        }
    }

    private func specRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(MaurtenFont.mono)
                .foregroundStyle(.black.opacity(0.5))
            Spacer()
            Text(value)
                .font(MaurtenFont.mono)
                .foregroundStyle(.black)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
    }

    private var connectButton: some View {
        Button(action: viewModel.toggleConnection) {
            HStack(spacing: 8) {
                if viewModel.connectionState.isTransitioning {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.7)
                }
                Text(buttonTitle)
                    .font(MaurtenFont.monoButton)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Color.black)
            .clipShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.hasConfigs || viewModel.connectionState.isTransitioning)
        .opacity(viewModel.hasConfigs ? 1.0 : 0.3)
    }

    private var buttonTitle: String {
        switch viewModel.connectionState {
        case .connected: return "DISCONNECT"
        case .connecting: return "CONNECTING"
        case .disconnecting: return "TERMINATING"
        case .reasserting: return "REASSERTING"
        default: return "CONNECT"
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.black)
            .frame(height: 1)
            .frame(maxWidth: .infinity)
    }
}
