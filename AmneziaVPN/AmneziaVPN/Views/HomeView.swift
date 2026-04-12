import SwiftUI

struct HomeView: View {
    @EnvironmentObject var viewModel: VPNViewModel
    @State private var pulseAnimation = false

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
            .navigationTitle("AmneziaVPN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        viewModel.isImporting = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
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
    }

    private var connectionOrb: some View {
        ZStack {
            if viewModel.connectionState == .connected {
                Circle()
                    .fill(Color.accentGreen.opacity(0.15))
                    .frame(width: 200, height: 200)
                    .scaleEffect(pulseAnimation ? 1.2 : 1.0)
                    .opacity(pulseAnimation ? 0.0 : 0.6)
                    .animation(
                        .easeInOut(duration: 2.0).repeatForever(autoreverses: false),
                        value: pulseAnimation
                    )
                    .onAppear { pulseAnimation = true }
                    .onDisappear { pulseAnimation = false }
            }

            Circle()
                .fill(orbGradient)
                .frame(width: 160, height: 160)
                .shadow(color: orbShadowColor.opacity(0.4), radius: 30, y: 8)

            Image(systemName: orbIcon)
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.white)
        }
        .animation(.easeInOut(duration: 0.5), value: viewModel.connectionState)
    }

    private var orbGradient: LinearGradient {
        switch viewModel.connectionState {
        case .connected:
            return LinearGradient(
                colors: [Color.accentGreen, Color.accentGreen.opacity(0.7)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        case .connecting, .reasserting:
            return LinearGradient(
                colors: [.orange, .yellow.opacity(0.7)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        default:
            return LinearGradient(
                colors: [Color.subtleGray, Color.subtleGray.opacity(0.5)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
    }

    private var orbShadowColor: Color {
        switch viewModel.connectionState {
        case .connected: return .accentGreen
        case .connecting, .reasserting: return .orange
        default: return .clear
        }
    }

    private var orbIcon: String {
        switch viewModel.connectionState {
        case .connected: return "lock.shield.fill"
        case .connecting, .reasserting: return "arrow.triangle.2.circlepath"
        case .disconnecting: return "xmark.shield"
        default: return "shield.slash"
        }
    }

    private var statusLabel: some View {
        VStack(spacing: 6) {
            Text(viewModel.connectionState.displayText)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)

            if viewModel.connectionState == .connected, let config = viewModel.selectedConfig {
                Text(config.peer.endpointHost)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private var statsCard: some View {
        HStack(spacing: 24) {
            statItem(title: "Duration", value: viewModel.stats.formattedDuration)
            Divider().frame(height: 32).background(.white.opacity(0.1))
            statItem(title: "Download", value: viewModel.stats.formattedBytesReceived)
            Divider().frame(height: 32).background(.white.opacity(0.1))
            statItem(title: "Upload", value: viewModel.stats.formattedBytesSent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func statItem(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.4))
                .textCase(.uppercase)
            Text(value)
                .font(.subheadline.monospacedDigit().weight(.medium))
                .foregroundStyle(.white)
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
                        Text(config.name)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                        Text(config.peer.endpointHost)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.4))
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.3))
                }
                .padding(16)
                .background(Color.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            } else {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text("Import a config to get started")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                }
                .padding(16)
                .frame(maxWidth: .infinity)
                .background(Color.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private var connectButton: some View {
        Button(action: viewModel.toggleConnection) {
            HStack(spacing: 10) {
                if viewModel.connectionState.isTransitioning {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: viewModel.connectionState.isActive ? "stop.fill" : "power")
                }

                Text(buttonTitle)
                    .font(.headline)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(buttonGradient)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: buttonShadow.opacity(0.3), radius: 12, y: 6)
        }
        .disabled(!viewModel.hasConfigs || viewModel.connectionState.isTransitioning)
        .opacity(viewModel.hasConfigs ? 1.0 : 0.5)
        .animation(.easeInOut(duration: 0.3), value: viewModel.connectionState)
    }

    private var buttonTitle: String {
        switch viewModel.connectionState {
        case .connected: return "Disconnect"
        case .connecting: return "Connecting..."
        case .disconnecting: return "Disconnecting..."
        case .reasserting: return "Reconnecting..."
        default: return "Connect"
        }
    }

    private var buttonGradient: LinearGradient {
        if viewModel.connectionState.isActive {
            return LinearGradient(
                colors: [.red.opacity(0.8), .red.opacity(0.6)],
                startPoint: .leading, endPoint: .trailing
            )
        }
        return LinearGradient(
            colors: [Color.accentGreen, Color.accentGreen.opacity(0.8)],
            startPoint: .leading, endPoint: .trailing
        )
    }

    private var buttonShadow: Color {
        viewModel.connectionState.isActive ? .red : .accentGreen
    }
}
