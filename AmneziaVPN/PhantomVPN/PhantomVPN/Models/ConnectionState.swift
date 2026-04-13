import Foundation

enum ConnectionState: String, Equatable {
    case disconnected
    case connecting
    case connected
    case disconnecting
    case reasserting
    case invalid

    var displayText: String {
        switch self {
        case .disconnected: return "INACTIVE"
        case .connecting: return "CONNECTING"
        case .connected: return "SESSION ACTIVE"
        case .disconnecting: return "TERMINATING"
        case .reasserting: return "REASSERTING"
        case .invalid: return "NOT CONFIGURED"
        }
    }

    var isActive: Bool {
        self == .connected || self == .connecting || self == .reasserting
    }

    var isTransitioning: Bool {
        self == .connecting || self == .disconnecting || self == .reasserting
    }
}

struct ConnectionStats {
    var connectedSince: Date?
    var bytesReceived: UInt64 = 0
    var bytesSent: UInt64 = 0

    var duration: TimeInterval {
        guard let since = connectedSince else { return 0 }
        return Date().timeIntervalSince(since)
    }

    var formattedDuration: String {
        let total = Int(duration)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    var formattedBytesReceived: String {
        ByteCountFormatter.string(fromByteCount: Int64(bytesReceived), countStyle: .binary)
    }

    var formattedBytesSent: String {
        ByteCountFormatter.string(fromByteCount: Int64(bytesSent), countStyle: .binary)
    }
}
