import Foundation

struct ServerLocation: Identifiable, Hashable {
    let id: UUID
    let name: String
    let flag: String
    let config: AmneziaWGConfig
    var latency: Int?

    init(id: UUID = UUID(), name: String, flag: String, config: AmneziaWGConfig, latency: Int? = nil) {
        self.id = id
        self.name = name
        self.flag = flag
        self.config = config
        self.latency = latency
    }

    var latencyText: String {
        guard let ms = latency else { return "—" }
        return "\(ms) ms"
    }

    static func inferLocation(from endpoint: String) -> (name: String, flag: String) {
        let host = endpoint.components(separatedBy: ":").first ?? endpoint

        let regionMap: [(prefix: String, name: String, flag: String)] = [
            ("eu-north", "Stockholm", "🇸🇪"),
            ("eu-west-1", "Ireland", "🇮🇪"),
            ("eu-west-2", "London", "🇬🇧"),
            ("eu-central", "Frankfurt", "🇩🇪"),
            ("us-east-1", "Virginia", "🇺🇸"),
            ("us-east-2", "Ohio", "🇺🇸"),
            ("us-west-1", "California", "🇺🇸"),
            ("us-west-2", "Oregon", "🇺🇸"),
            ("ap-northeast-1", "Tokyo", "🇯🇵"),
            ("ap-southeast-1", "Singapore", "🇸🇬"),
        ]

        for region in regionMap {
            if host.contains(region.prefix) {
                return (region.name, region.flag)
            }
        }

        return ("Server \(host.prefix(12))", "🌍")
    }
}
