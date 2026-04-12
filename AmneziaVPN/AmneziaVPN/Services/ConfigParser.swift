import Foundation

enum ConfigParserError: LocalizedError {
    case invalidFormat
    case missingInterface
    case missingPeer
    case missingRequiredField(String)
    case invalidFile

    var errorDescription: String? {
        switch self {
        case .invalidFormat: return "Invalid configuration format"
        case .missingInterface: return "Missing [Interface] section"
        case .missingPeer: return "Missing [Peer] section"
        case .missingRequiredField(let field): return "Missing required field: \(field)"
        case .invalidFile: return "Could not read configuration file"
        }
    }
}

final class ConfigParser {

    static func parse(_ content: String, name: String? = nil) throws -> AmneziaWGConfig {
        let lines = content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }

        var currentSection = ""
        var interfaceDict: [String: String] = [:]
        var peerDict: [String: String] = [:]

        for line in lines {
            if line.hasPrefix("[") && line.hasSuffix("]") {
                currentSection = String(line.dropFirst().dropLast()).lowercased()
                continue
            }

            guard let eqIndex = line.firstIndex(of: "=") else { continue }
            let key = line[line.startIndex..<eqIndex].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: eqIndex)...].trimmingCharacters(in: .whitespaces)

            switch currentSection {
            case "interface":
                interfaceDict[key.lowercased()] = value
            case "peer":
                peerDict[key.lowercased()] = value
            default:
                break
            }
        }

        guard !interfaceDict.isEmpty else { throw ConfigParserError.missingInterface }
        guard !peerDict.isEmpty else { throw ConfigParserError.missingPeer }

        guard let privateKey = interfaceDict["privatekey"] else {
            throw ConfigParserError.missingRequiredField("PrivateKey")
        }
        guard let address = interfaceDict["address"] else {
            throw ConfigParserError.missingRequiredField("Address")
        }
        guard let publicKey = peerDict["publickey"] else {
            throw ConfigParserError.missingRequiredField("PublicKey")
        }
        guard let endpoint = peerDict["endpoint"] else {
            throw ConfigParserError.missingRequiredField("Endpoint")
        }

        let interfaceConfig = InterfaceConfig(
            privateKey: privateKey,
            address: address,
            dns: interfaceDict["dns"] ?? "1.1.1.1, 1.0.0.1",
            jc: Int(interfaceDict["jc"] ?? "") ?? 4,
            jmin: Int(interfaceDict["jmin"] ?? "") ?? 40,
            jmax: Int(interfaceDict["jmax"] ?? "") ?? 70,
            s1: Int(interfaceDict["s1"] ?? "") ?? 0,
            s2: Int(interfaceDict["s2"] ?? "") ?? 0,
            h1: Int(interfaceDict["h1"] ?? "") ?? 1,
            h2: Int(interfaceDict["h2"] ?? "") ?? 2,
            h3: Int(interfaceDict["h3"] ?? "") ?? 3,
            h4: Int(interfaceDict["h4"] ?? "") ?? 4
        )

        let peerConfig = PeerConfig(
            publicKey: publicKey,
            endpoint: endpoint,
            allowedIPs: peerDict["allowedips"] ?? "0.0.0.0/0",
            persistentKeepalive: Int(peerDict["persistentkeepalive"] ?? "") ?? 25,
            presharedKey: peerDict["presharedkey"]
        )

        let configName = name ?? "AmneziaWG-\(endpoint.components(separatedBy: ":").first ?? "server")"

        return AmneziaWGConfig(
            name: configName,
            interface: interfaceConfig,
            peer: peerConfig
        )
    }

    static func parseFile(at url: URL, name: String? = nil) throws -> AmneziaWGConfig {
        guard url.startAccessingSecurityScopedResource() else {
            throw ConfigParserError.invalidFile
        }
        defer { url.stopAccessingSecurityScopedResource() }

        let content = try String(contentsOf: url, encoding: .utf8)
        let fileName = name ?? url.deletingPathExtension().lastPathComponent
        return try parse(content, name: fileName)
    }

    static func serialize(_ config: AmneziaWGConfig) -> String {
        var lines: [String] = []

        lines.append("[Interface]")
        lines.append("PrivateKey = \(config.interface.privateKey)")
        lines.append("Address = \(config.interface.address)")
        lines.append("DNS = \(config.interface.dns)")
        lines.append("Jc = \(config.interface.jc)")
        lines.append("Jmin = \(config.interface.jmin)")
        lines.append("Jmax = \(config.interface.jmax)")
        lines.append("S1 = \(config.interface.s1)")
        lines.append("S2 = \(config.interface.s2)")
        lines.append("H1 = \(config.interface.h1)")
        lines.append("H2 = \(config.interface.h2)")
        lines.append("H3 = \(config.interface.h3)")
        lines.append("H4 = \(config.interface.h4)")
        lines.append("")
        lines.append("[Peer]")
        lines.append("PublicKey = \(config.peer.publicKey)")
        lines.append("Endpoint = \(config.peer.endpoint)")
        lines.append("AllowedIPs = \(config.peer.allowedIPs)")
        lines.append("PersistentKeepalive = \(config.peer.persistentKeepalive)")
        if let psk = config.peer.presharedKey {
            lines.append("PresharedKey = \(psk)")
        }

        return lines.joined(separator: "\n") + "\n"
    }
}
