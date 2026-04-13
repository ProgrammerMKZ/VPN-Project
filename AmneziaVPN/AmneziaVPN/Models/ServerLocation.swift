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
        guard let ms = latency else { return "---" }
        return "\(ms) MS"
    }

    static func inferLocation(from endpoint: String) -> (name: String, code: String) {
        let host = endpoint.components(separatedBy: ":").first ?? endpoint

        let regionMap: [(prefix: String, name: String, code: String)] = [
            ("eu-north", "STOCKHOLM", "SE"),
            ("eu-west-1", "IRELAND", "IE"),
            ("eu-west-2", "LONDON", "GB"),
            ("eu-central", "FRANKFURT", "DE"),
            ("us-east-1", "VIRGINIA", "US"),
            ("us-east-2", "OHIO", "US"),
            ("us-west-1", "CALIFORNIA", "US"),
            ("us-west-2", "OREGON", "US"),
            ("ap-northeast-1", "TOKYO", "JP"),
            ("ap-southeast-1", "SINGAPORE", "SG"),
        ]

        for region in regionMap {
            if host.contains(region.prefix) {
                return (region.name, region.code)
            }
        }

        return ("NODE \(host.prefix(12).uppercased())", "--")
    }
}
