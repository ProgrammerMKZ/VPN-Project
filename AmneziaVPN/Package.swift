// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AmneziaVPN",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(name: "AmneziaVPN", targets: ["AmneziaVPN"]),
        .library(name: "PacketTunnel", targets: ["PacketTunnel"]),
    ],
    targets: [
        .target(
            name: "AmneziaVPN",
            path: "AmneziaVPN",
            resources: [.process("Resources")]
        ),
        .target(
            name: "PacketTunnel",
            path: "PacketTunnel"
        ),
    ]
)
