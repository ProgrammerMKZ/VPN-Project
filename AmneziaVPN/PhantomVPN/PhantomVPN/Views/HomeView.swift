import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    @EnvironmentObject var viewModel: VPNViewModel
    @State private var pulseAnimation = false

    private let mono = Font.custom("Courier New", size: 13)
    private let monoSmall = Font.custom("Courier New", size: 11)
    private let monoTitle = Font.custom("Courier New", size: 18)

    var body: some View {
        NavigationStack {
            ZStack {
                Color.darkBackground.ignoresSafeArea()

                VStack(spacing: 32) {
                    Spacer()

                    connectionOrb

                    statusLabel

                    if viewModel.connectionState == .connected {
                        statsCard
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    Spacer()

                    selectedServerCard

                    connectButton
                        .padding(.bottom, 16)
                }
                .padding(.horizontal, 24)
            }
            .navigationTitle("PHANTOMVPN")
            .iOSNavigationBarInline()
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        viewModel.isImporting = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.black.opacity(0.7))
                    }
                }
            }
            .fileImporter(
                isPresented: $viewModel.isImporting,
                allowedContentTypes: [UTType(filenameExtension: "conf")].compactMap { $0 },
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    viewModel.importConfig(from: url)
                }
            }
        }
    }

    private var connectionOrb: some View {
        ZStack {
            if viewModel.connectionState == .connected {
                Circle()
                    .fill(Color.black.opacity(0.08))
                    .frame(width: 200, height: 200)
                    .scaleEffect(pulseAnimation ? 1.2 : 1.0)
                    .opacity(pulseAnimation ? 0.0 : 0.6)
                    .onAppear { pulseAnimation = true }
                    .onDisappear { pulseAnimation = false }
                    .animation(
                        .easeInOut(duration: 2.0).repeatForever(autoreverses: false),
                        value: pulseAnimation
                    )
            }

            Circle()
                .fill(orbFill)
                .frame(width: 160, height: 160)
                .overlay(
                    Circle().stroke(Color.black, lineWidth: 1)
                )

            Image(systemName: orbIcon)
                .font(.system(size: 56, weight: .ultraLight, design: .monospaced))
                .foregroundStyle(orbIconColor)
        }
    }

    private var orbFill: Color {
        switch viewModel.connectionState {
        case .connected:
            Color.black
        case .connecting, .reasserting:
            Color(white: 0.35)
        default:
            Color(white: 0.92)
        }
    }

    private var orbIconColor: Color {
        switch viewModel.connectionState {
        case .connected, .connecting, .reasserting:
            .white
        default:
            .black
        }
    }

    private var orbIcon: String {
        switch viewModel.connectionState {
        case .connected: "lock.shield.fill"
        case .connecting, .reasserting: "arrow.triangle.2.circlepath"
        case .disconnecting: "xmark.shield"
        default: "shield.slash"
        }
    }

    private var statusLabel: some View {
        VStack(spacing: 6) {
            Text(viewModel.connectionState.displayText)
                .font(monoTitle)
                .foregroundStyle(.black)
                .textCase(.uppercase)

            if viewModel.connectionState == .connected, let config = viewModel.selectedConfig {
                Text(config.peer.endpointHost.uppercased())
                    .font(monoSmall)
                    .foregroundStyle(.black.opacity(0.4))
            }
        }
    }

    private var statsCard: some View {
        HStack(spacing: 24) {
            statItem(title: "DURATION", value: viewModel.stats.formattedDuration)
            Rectangle().fill(Color.black.opacity(0.15)).frame(width: 1, height: 32)
            statItem(title: "DOWNLOAD", value: viewModel.stats.formattedBytesReceived)
            Rectangle().fill(Color.black.opacity(0.15)).frame(width: 1, height: 32)
            statItem(title: "UPLOAD", value: viewModel.stats.formattedBytesSent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color.cardBackground)
        .clipShape(Rectangle())
        .overlay(
            Rectangle().stroke(Color.black, lineWidth: 1)
        )
    }

    private func statItem(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(monoSmall)
                .foregroundStyle(.black.opacity(0.4))
            Text(value.uppercased())
                .font(mono)
                .foregroundStyle(.black)
        }
    }

    private var selectedServerCard: some View {
        Group {
            if let config = viewModel.selectedConfig {
                HStack(spacing: 14) {
                    let location = ServerLocation.inferLocation(from: config.peer.endpoint)
                    Text(location.flag)
                        .font(.title)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(config.name.uppercased())
                            .font(mono)
                            .foregroundStyle(.black)
                        Text(config.peer.endpointHost.uppercased())
                            .font(monoSmall)
                            .foregroundStyle(.black.opacity(0.4))
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.black.opacity(0.3))
                }
                .padding(16)
                .background(Color.cardBackground)
                .clipShape(Rectangle())
                .overlay(
                    Rectangle().stroke(Color.black, lineWidth: 1)
                )
            } else {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.black.opacity(0.4))
                    Text("IMPORT A CONFIG TO GET STARTED")
                        .font(monoSmall)
                        .foregroundStyle(.black.opacity(0.5))
                }
                .padding(16)
                .frame(maxWidth: .infinity)
                .background(Color.cardBackground)
                .clipShape(Rectangle())
                .overlay(
                    Rectangle().stroke(Color.black, lineWidth: 1)
                )
            }
        }
    }

    private var connectButton: some View {
        Button {
            viewModel.toggleConnection()
        } label: {
            HStack(spacing: 10) {
                if viewModel.connectionState.isTransitioning {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: viewModel.connectionState.isActive ? "stop.fill" : "power")
                }

                Text(buttonTitle)
                    .font(Font.custom("Courier New", size: 15))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(buttonColor)
            .clipShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.connectionState.isTransitioning)
        .opacity(viewModel.hasConfigs ? 1.0 : 0.5)
    }

    private var buttonTitle: String {
        switch viewModel.connectionState {
        case .connected: "DISCONNECT"
        case .connecting: "CONNECTING..."
        case .disconnecting: "DISCONNECTING..."
        case .reasserting: "RECONNECTING..."
        default: "CONNECT"
        }
    }

    private var buttonColor: Color {
        if viewModel.connectionState.isActive {
            Color(white: 0.25)
        } else {
            Color.black
        }
    }
}
