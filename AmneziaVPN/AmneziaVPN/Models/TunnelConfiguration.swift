import Foundation

struct AmneziaWGConfig: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var interface: InterfaceConfig
    var peer: PeerConfig
    var dateAdded: Date

    init(id: UUID = UUID(), name: String, interface: InterfaceConfig, peer: PeerConfig, dateAdded: Date = Date()) {
        self.id = id
        self.name = name
        self.interface = interface
        self.peer = peer
        self.dateAdded = dateAdded
    }
}

struct InterfaceConfig: Codable, Hashable {
    var privateKey: String
    var address: String
    var dns: String
    var jc: Int
    var jmin: Int
    var jmax: Int
    var s1: Int
    var s2: Int
    var h1: Int
    var h2: Int
    var h3: Int
    var h4: Int

    var addressWithoutMask: String {
        address.components(separatedBy: "/").first ?? address
    }

    var subnetMask: String {
        address.components(separatedBy: "/").last ?? "24"
    }
}

struct PeerConfig: Codable, Hashable {
    var publicKey: String
    var endpoint: String
    var allowedIPs: String
    var persistentKeepalive: Int
    var presharedKey: String?

    var endpointHost: String {
        endpoint.components(separatedBy: ":").first ?? endpoint
    }

    var endpointPort: String {
        endpoint.components(separatedBy: ":").last ?? "443"
    }
}
