import NetworkExtension
import Foundation

class PacketTunnelProvider: NEPacketTunnelProvider {

    private var config: AmneziaWGConfig?
    private var bytesReceived: UInt64 = 0
    private var bytesSent: UInt64 = 0

    override func startTunnel(options: [String: NSObject]? = nil) async throws {
        guard let proto = protocolConfiguration as? NETunnelProviderProtocol,
              let providerConfig = proto.providerConfiguration,
              let configBase64 = providerConfig["config"] as? String,
              let configData = Data(base64Encoded: configBase64) else {
            throw NEVPNError(.configurationInvalid)
        }

        let tunnelConfig = try JSONDecoder().decode(AmneziaWGConfig.self, from: configData)
        self.config = tunnelConfig

        let settings = buildTunnelSettings(from: tunnelConfig)
        try await setTunnelNetworkSettings(settings)

        startHandlingPackets()
    }

    override func stopTunnel(with reason: NEProviderStopReason) async {
        config = nil
    }

    override func handleAppMessage(_ messageData: Data) async -> Data? {
        guard let message = String(data: messageData, encoding: .utf8) else { return nil }

        if message == "stats" {
            let stats: [String: UInt64] = ["rx": bytesReceived, "tx": bytesSent]
            return try? JSONSerialization.data(withJSONObject: stats)
        }

        return nil
    }

    override func sleep() async {
        // Pause tunnel activity during device sleep
    }

    override func wake() {
        // Resume tunnel activity on wake
    }

    private func buildTunnelSettings(from config: AmneziaWGConfig) -> NEPacketTunnelNetworkSettings {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: config.peer.endpointHost)

        let ipv4 = NEIPv4Settings(
            addresses: [config.interface.addressWithoutMask],
            subnetMasks: [subnetMaskFromCIDR(config.interface.subnetMask)]
        )
        ipv4.includedRoutes = [NEIPv4Route.default()]
        settings.ipv4Settings = ipv4

        let dnsServers = config.interface.dns
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        settings.dnsSettings = NEDNSSettings(servers: dnsServers)

        settings.mtu = NSNumber(value: 1280)

        return settings
    }

    private func subnetMaskFromCIDR(_ cidr: String) -> String {
        guard let bits = Int(cidr), bits >= 0, bits <= 32 else { return "255.255.255.0" }
        let mask = bits == 0 ? 0 : UInt32.max << (32 - bits)
        return [
            (mask >> 24) & 0xFF,
            (mask >> 16) & 0xFF,
            (mask >> 8) & 0xFF,
            mask & 0xFF
        ].map { String($0) }.joined(separator: ".")
    }

    private func startHandlingPackets() {
        packetFlow.readPackets { [weak self] packets, protocols in
            guard let self else { return }
            for (i, packet) in packets.enumerated() {
                self.bytesSent += UInt64(packet.count)
                self.processOutboundPacket(packet, protocolFamily: protocols[i])
            }
            self.startHandlingPackets()
        }
    }

    private func processOutboundPacket(_ packet: Data, protocolFamily: NSNumber) {
        // In production, this is where the AmneziaWG userspace implementation
        // encrypts packets with the obfuscation parameters (Jc, Jmin, Jmax, S1, S2, H1-H4)
        // and sends them to the peer endpoint via UDP.
        //
        // Integration point: link against the AmneziaWG-Go library or
        // the amneziawg-apple framework to handle the actual crypto + obfuscation.
    }

    private func deliverInboundPacket(_ packet: Data, protocolFamily: NSNumber) {
        bytesReceived += UInt64(packet.count)
        packetFlow.writePackets([packet], withProtocols: [protocolFamily])
    }
}
