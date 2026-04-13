import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var viewModel: VPNViewModel
    @State private var selectedDetailConfig: AmneziaWGConfig?

    var body: some View {
        VStack(spacing: 0) {
            header
            divider

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    if let config = viewModel.selectedConfig {
                        activeConfigSection(config)
                    }

                    connectionSection
                    aboutSection
                }
            }
        }
        .background(Color.white)
        .sheet(item: $selectedDetailConfig) { config in
            ConfigDetailView(config: config)
        }
    }

    private var header: some View {
        HStack {
            Text("CONFIGURATION")
                .font(MaurtenFont.monoLabel)
                .foregroundStyle(.black)
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private func activeConfigSection(_ config: AmneziaWGConfig) -> some View {
        VStack(spacing: 0) {
            sectionTitle("ACTIVE NODE")
            specRow(label: "SERVER", value: config.peer.endpointHost.uppercased())
            specRow(label: "VPN ADDRESS", value: config.interface.address.uppercased())
            specRow(label: "DNS", value: config.interface.dns)
            specRow(label: "PORT", value: config.peer.endpointPort)

            Button {
                selectedDetailConfig = config
            } label: {
                HStack {
                    Text("VIEW FULL CONFIG")
                        .font(MaurtenFont.mono)
                        .foregroundStyle(.black)
                    Spacer()
                    Text(">")
                        .font(MaurtenFont.mono)
                        .foregroundStyle(.black.opacity(0.3))
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            divider
        }
    }

    private var connectionSection: some View {
        VStack(spacing: 0) {
            sectionTitle("PROTOCOL PARAMETERS")
            specRow(label: "PROTOCOL", value: "AMNEZIAWG")
            specRow(label: "OBFUSCATION", value: "ENABLED")
            specRow(label: "KILL SWITCH", value: "SYSTEM")
            specRow(label: "AUTO-CONNECT", value: "OFF")
            divider
        }
    }

    private var aboutSection: some View {
        VStack(spacing: 0) {
            sectionTitle("SYSTEM")
            specRow(label: "VERSION", value: appVersion.uppercased())
            specRow(label: "PRIVACY", value: "NO LOGS")
            specRow(label: "LICENSE", value: "OPEN SOURCE")
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(MaurtenFont.monoLabel)
                .foregroundStyle(.black)
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 8)
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

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.black)
            .frame(height: 1)
            .frame(maxWidth: .infinity)
    }
}

struct ConfigDetailView: View {
    let config: AmneziaWGConfig
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            detailHeader
            detailDivider

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    sectionTitle("INTERFACE")
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
                    detailDivider

                    sectionTitle("PEER")
                    detailRow("ENDPOINT", config.peer.endpoint)
                    detailRow("ALLOWED IPS", config.peer.allowedIPs)
                    detailRow("KEEPALIVE", "\(config.peer.persistentKeepalive)S")
                    detailRow("PSK", config.peer.presharedKey != nil ? "KEY ISSUED" : "NONE")
                }
            }
        }
        .background(Color.white)
    }

    private var detailHeader: some View {
        HStack {
            Text(config.name.uppercased())
                .font(MaurtenFont.monoLabel)
                .foregroundStyle(.black)

            Spacer()

            Button {
                dismiss()
            } label: {
                Text("DONE")
                    .font(MaurtenFont.monoSmall)
                    .foregroundStyle(.black)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private func sectionTitle(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(MaurtenFont.monoLabel)
                .foregroundStyle(.black)
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 8)
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(MaurtenFont.mono)
                .foregroundStyle(.black.opacity(0.5))
            Spacer()
            Text(value.uppercased())
                .font(MaurtenFont.mono)
                .foregroundStyle(.black)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 6)
    }

    private var detailDivider: some View {
        Rectangle()
            .fill(Color.black)
            .frame(height: 1)
            .frame(maxWidth: .infinity)
    }
}
