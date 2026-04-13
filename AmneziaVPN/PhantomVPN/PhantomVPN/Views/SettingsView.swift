import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var viewModel: VPNViewModel
    @State private var showConfigDetail = false
    @State private var selectedDetailConfig: AmneziaWGConfig?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.darkBackground.ignoresSafeArea()

                List {
                    if let config = viewModel.selectedConfig {
                        activeConfigSection(config)
                    }

                    connectionSection
                    aboutSection
                }
                .iOSInsetGroupedList()
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
            .iOSNavigationBarLarge()
            .sheet(item: $selectedDetailConfig) { config in
                ConfigDetailView(config: config)
            }
        }
    }

    private func activeConfigSection(_ config: AmneziaWGConfig) -> some View {
        Section {
            settingsRow(icon: "server.rack", title: "Server", value: config.peer.endpointHost)
            settingsRow(icon: "network", title: "VPN Address", value: config.interface.address)
            settingsRow(icon: "globe", title: "DNS", value: config.interface.dns)
            settingsRow(icon: "number", title: "Port", value: config.peer.endpointPort)

            Button {
                selectedDetailConfig = config
            } label: {
                HStack {
                    Label("View Full Config", systemImage: "doc.text.magnifyingglass")
                        .foregroundStyle(.white)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
        } header: {
            Text("Active Configuration")
                .foregroundStyle(.white.opacity(0.5))
        }
        .listRowBackground(Color.cardBackground)
    }

    private var connectionSection: some View {
        Section {
            settingsRow(icon: "shield.checkered", title: "Protocol", value: "AmneziaWG")
            settingsRow(icon: "eye.slash", title: "Obfuscation", value: "Enabled")
            settingsRow(icon: "arrow.triangle.2.circlepath", title: "Kill Switch", value: "System")
            settingsRow(icon: "wifi.exclamationmark", title: "Auto-Connect", value: "Off")
        } header: {
            Text("Connection")
                .foregroundStyle(.white.opacity(0.5))
        }
        .listRowBackground(Color.cardBackground)
    }

    private var aboutSection: some View {
        Section {
            settingsRow(icon: "info.circle", title: "Version", value: appVersion)
            settingsRow(icon: "lock.shield", title: "Privacy", value: "No Logs")

            Link(destination: URL(string: "https://github.com/amnezia-vpn")!) {
                HStack {
                    Label("Source Code", systemImage: "chevron.left.forwardslash.chevron.right")
                        .foregroundStyle(.white)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
        } header: {
            Text("About")
                .foregroundStyle(.white.opacity(0.5))
        }
        .listRowBackground(Color.cardBackground)
    }

    private func settingsRow(icon: String, title: String, value: String) -> some View {
        HStack {
            Label(title, systemImage: icon)
                .foregroundStyle(.white)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

struct ConfigDetailView: View {
    let config: AmneziaWGConfig
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.darkBackground.ignoresSafeArea()

                List {
                    Section("Interface") {
                        detailRow("Address", config.interface.address)
                        detailRow("DNS", config.interface.dns)
                        detailRow("Jc", "\(config.interface.jc)")
                        detailRow("Jmin", "\(config.interface.jmin)")
                        detailRow("Jmax", "\(config.interface.jmax)")
                        detailRow("S1", "\(config.interface.s1)")
                        detailRow("S2", "\(config.interface.s2)")
                        detailRow("H1", "\(config.interface.h1)")
                        detailRow("H2", "\(config.interface.h2)")
                        detailRow("H3", "\(config.interface.h3)")
                        detailRow("H4", "\(config.interface.h4)")
                    }
                    .listRowBackground(Color.cardBackground)

                    Section("Peer") {
                        detailRow("Endpoint", config.peer.endpoint)
                        detailRow("Allowed IPs", config.peer.allowedIPs)
                        detailRow("Keepalive", "\(config.peer.persistentKeepalive)s")
                        detailRow("PSK", config.peer.presharedKey != nil ? "Set" : "None")
                    }
                    .listRowBackground(Color.cardBackground)
                }
                .iOSInsetGroupedList()
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(config.name)
            .iOSNavigationBarInline()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.white.opacity(0.6))
            Spacer()
            Text(value)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
