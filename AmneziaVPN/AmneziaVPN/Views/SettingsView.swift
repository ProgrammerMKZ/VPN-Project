import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var viewModel: VPNViewModel
    @State private var showConfigDetail = false
    @State private var selectedDetailConfig: AmneziaWGConfig?

    private let mono = Font.custom("Courier New", size: 13)
    private let monoSmall = Font.custom("Courier New", size: 11)

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
            .navigationTitle("SETTINGS")
            .iOSNavigationBarLarge()
            .sheet(item: $selectedDetailConfig) { config in
                ConfigDetailView(config: config)
            }
        }
    }

    private func activeConfigSection(_ config: AmneziaWGConfig) -> some View {
        Section {
            settingsRow(icon: "server.rack", title: "SERVER", value: config.peer.endpointHost.uppercased())
            settingsRow(icon: "network", title: "VPN ADDRESS", value: config.interface.address.uppercased())
            settingsRow(icon: "globe", title: "DNS", value: config.interface.dns.uppercased())
            settingsRow(icon: "number", title: "PORT", value: config.peer.endpointPort)

            Button {
                selectedDetailConfig = config
            } label: {
                HStack {
                    Label("VIEW FULL CONFIG", systemImage: "doc.text.magnifyingglass")
                        .font(mono)
                        .foregroundStyle(.black)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.black.opacity(0.3))
                }
            }
        } header: {
            Text("ACTIVE CONFIGURATION")
                .font(monoSmall)
                .foregroundStyle(.black.opacity(0.4))
        }
        .listRowBackground(Color.cardBackground)
    }

    private var connectionSection: some View {
        Section {
            settingsRow(icon: "shield.checkered", title: "PROTOCOL", value: "AMNEZIAWG")
            settingsRow(icon: "eye.slash", title: "OBFUSCATION", value: "ENABLED")
            settingsRow(icon: "arrow.triangle.2.circlepath", title: "KILL SWITCH", value: "SYSTEM")
            settingsRow(icon: "wifi.exclamationmark", title: "AUTO-CONNECT", value: "OFF")
        } header: {
            Text("CONNECTION")
                .font(monoSmall)
                .foregroundStyle(.black.opacity(0.4))
        }
        .listRowBackground(Color.cardBackground)
    }

    private var aboutSection: some View {
        Section {
            settingsRow(icon: "info.circle", title: "VERSION", value: appVersion.uppercased())
            settingsRow(icon: "lock.shield", title: "PRIVACY", value: "NO LOGS")

            Link(destination: URL(string: "https://github.com/amnezia-vpn")!) {
                HStack {
                    Label("SOURCE CODE", systemImage: "chevron.left.forwardslash.chevron.right")
                        .font(mono)
                        .foregroundStyle(.black)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(.black.opacity(0.3))
                }
            }
        } header: {
            Text("ABOUT")
                .font(monoSmall)
                .foregroundStyle(.black.opacity(0.4))
        }
        .listRowBackground(Color.cardBackground)
    }

    private func settingsRow(icon: String, title: String, value: String) -> some View {
        HStack {
            Label(title, systemImage: icon)
                .font(mono)
                .foregroundStyle(.black)
            Spacer()
            Text(value)
                .font(mono)
                .foregroundStyle(.black.opacity(0.4))
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

    private let mono = Font.custom("Courier New", size: 13)
    private let monoSmall = Font.custom("Courier New", size: 11)

    var body: some View {
        NavigationStack {
            ZStack {
                Color.darkBackground.ignoresSafeArea()

                List {
                    Section("INTERFACE") {
                        detailRow("ADDRESS", config.interface.address)
                        detailRow("DNS", config.interface.dns)
                        detailRow("JC", "\(config.interface.jc)")
                        detailRow("JMIN", "\(config.interface.jmin)")
                        detailRow("JMAX", "\(config.interface.jmax)")
                        detailRow("S1", "\(config.interface.s1)")
                        detailRow("S2", "\(config.interface.s2)")
                        detailRow("H1", "\(config.interface.h1)")
                        detailRow("H2", "\(config.interface.h2)")
                        detailRow("H3", "\(config.interface.h3)")
                        detailRow("H4", "\(config.interface.h4)")
                    }
                    .listRowBackground(Color.cardBackground)

                    Section("PEER") {
                        detailRow("ENDPOINT", config.peer.endpoint)
                        detailRow("ALLOWED IPS", config.peer.allowedIPs)
                        detailRow("KEEPALIVE", "\(config.peer.persistentKeepalive)S")
                        detailRow("PSK", config.peer.presharedKey != nil ? "SET" : "NONE")
                    }
                    .listRowBackground(Color.cardBackground)
                }
                .iOSInsetGroupedList()
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(config.name.uppercased())
            .iOSNavigationBarInline()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("DONE") { dismiss() }
                        .font(mono)
                }
            }
        }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(mono)
                .foregroundStyle(.black.opacity(0.5))
            Spacer()
            Text(value.uppercased())
                .font(Font.custom("Courier New", size: 12))
                .foregroundStyle(.black)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
