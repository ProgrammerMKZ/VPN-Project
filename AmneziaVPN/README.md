# AmneziaVPN — iOS Client

A slick, App Store-ready iOS VPN client for **AmneziaWG** (WireGuard with DPI-resistant obfuscation). Designed to work with the AmneziaWG server infrastructure in this repo.

## Architecture

```
AmneziaVPN/
├── AmneziaVPN/              # Main iOS app
│   ├── App/                 # @main entry point
│   ├── Models/              # Data models (config, state, server)
│   ├── Views/               # SwiftUI views (Home, Servers, Settings)
│   ├── ViewModels/          # MVVM view models
│   ├── Services/            # VPN manager, config parser, keychain, store
│   ├── Extensions/          # Swift/SwiftUI helpers
│   └── Resources/           # Asset catalogs
├── PacketTunnel/            # Network Extension (Packet Tunnel Provider)
└── Package.swift            # Swift Package manifest
```

## Features

- **AmneziaWG Config Support** — Full parsing of `.conf` files including obfuscation parameters (Jc, Jmin, Jmax, S1, S2, H1–H4)
- **Network Extension** — Uses Apple's `NEPacketTunnelProvider` for system-level VPN
- **Config Import** — Import via file picker or paste raw config text
- **Server Management** — Multi-server support with one-tap switching
- **Modern UI** — Dark theme, animated connection orb, real-time stats
- **App Group Sharing** — Config synced between app and tunnel extension
- **Keychain Storage** — Sensitive keys stored securely
- **IP Rotation Ready** — Configs update seamlessly when the Lambda rotates server IPs

## Requirements

- iOS 16.0+ / macOS 13.0+
- Xcode 15+
- Apple Developer account with Network Extension entitlement
- AmneziaWG server (deployed via the Terraform configs in this repo)

## Setup

### 1. Create Xcode Project

Open Xcode and create a new project, then add the source files from this directory. You need two targets:

- **AmneziaVPN** (iOS App) — bundle ID: `com.amneziavpn.app`
- **PacketTunnel** (Network Extension) — bundle ID: `com.amneziavpn.app.tunnel`

### 2. Capabilities

Enable these capabilities on **both** targets:
- Network Extensions → Packet Tunnel
- App Groups → `group.com.amneziavpn.app`
- Keychain Sharing → `com.amneziavpn.app`

### 3. AmneziaWG Integration

The `PacketTunnelProvider` is structured as a scaffold. For production, integrate the AmneziaWG userspace implementation:

**Option A — AmneziaWG Apple Framework:**
```
https://github.com/amnezia-vpn/amneziawg-apple
```

**Option B — WireGuardKit + Amnezia patches:**
```
https://github.com/amnezia-vpn/amneziawg-go
```

The provider already parses all obfuscation params and passes them through. Wire the actual tunnel crypto in `PacketTunnelProvider.processOutboundPacket()`.

### 4. Generate Client Configs

Use the server-side scripts to generate configs:

```bash
cd scripts/
./generate_configs.sh --clients-per-server 50 --server-count 1
```

Download a client `.conf` from S3 and import it into the app.

## Config Format

The app parses standard AmneziaWG configs:

```ini
[Interface]
PrivateKey = <base64>
Address = 10.8.0.2/24
DNS = 1.1.1.1, 1.0.0.1
Jc = 4
Jmin = 40
Jmax = 70
S1 = 0
S2 = 0
H1 = 1
H2 = 2
H3 = 3
H4 = 4

[Peer]
PublicKey = <base64>
Endpoint = <server-ip>:443
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
PresharedKey = <base64>
```

## App Store Notes

- `ITSAppUsesNonExemptEncryption` is set to `false` (WireGuard uses exempt encryption)
- The app registers as a handler for `.conf` files
- No analytics or tracking — zero-log policy
- Kill switch uses iOS system-level VPN behavior (always-on)

## License

Part of the AmneziaVPN infrastructure project.
