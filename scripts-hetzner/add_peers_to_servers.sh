#!/usr/bin/env bash
#
# SSH into each Hetzner VPN server, append peer configs from local files,
# and reload AmneziaWG without dropping connections.
#
# Usage: ./add_peers_to_servers.sh [--ssh-key PATH] [--ssh-user USER]
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
STATE_FILE="$ROOT_DIR/state/servers.json"
CONFIGS_DIR="$ROOT_DIR/configs"

SSH_KEY=""
SSH_USER="root"

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  --ssh-key PATH      SSH private key (default: ~/.ssh/id_ed25519)
  --ssh-user USER     SSH username (default: root)
  --configs-dir DIR   Configs directory (default: ./configs)
  -h, --help          Show this help

Reads server list from: $STATE_FILE
EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ssh-key)     SSH_KEY="$2"; shift 2 ;;
    --ssh-user)    SSH_USER="$2"; shift 2 ;;
    --configs-dir) CONFIGS_DIR="$2"; shift 2 ;;
    -h|--help)     usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

[[ -z "$SSH_KEY" ]] && SSH_KEY="$HOME/.ssh/id_ed25519"
[[ ! -f "$STATE_FILE" ]] && { echo "ERROR: $STATE_FILE not found. Run terraform apply first."; exit 1; }
command -v jq >/dev/null || { echo "ERROR: jq required"; exit 1; }

SERVER_COUNT=$(jq '.servers | length' "$STATE_FILE")

echo "=== Adding Peers to AmneziaWG Servers (Hetzner) ==="
echo "Servers: $SERVER_COUNT"
echo ""

SSH_OPTS="-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -o LogLevel=ERROR"

for SERVER_IDX in $(seq 0 $((SERVER_COUNT - 1))); do
  echo "--- Server $SERVER_IDX ---"

  SERVER_IP=$(jq -r ".servers[$SERVER_IDX].ipv4" "$STATE_FILE")
  PEERS_FILE="$CONFIGS_DIR/server-$SERVER_IDX/server_peers.conf"

  echo "  IP: $SERVER_IP"

  if [[ ! -f "$PEERS_FILE" ]]; then
    echo "  WARNING: $PEERS_FILE not found — run generate_configs.sh first"
    continue
  fi

  PEER_COUNT=$(grep -c '^\[Peer\]' "$PEERS_FILE" || true)
  echo "  Peers to register: $PEER_COUNT"
  [[ "$PEER_COUNT" -eq 0 ]] && { echo "  No peers found, skipping"; continue; }

  scp $SSH_OPTS -i "$SSH_KEY" \
    "$PEERS_FILE" "${SSH_USER}@${SERVER_IP}:/tmp/new_peers.conf"

  ssh $SSH_OPTS -i "$SSH_KEY" "${SSH_USER}@${SERVER_IP}" <<'REMOTE_SCRIPT'
set -euo pipefail
AWG_CONF="/etc/amnezia/amneziawg/awg0.conf"

if [[ ! -f "$AWG_CONF" ]]; then
  echo "ERROR: AmneziaWG config not found at $AWG_CONF"
  exit 1
fi

FIRST_NEW_PUBKEY=$(grep -m1 'PublicKey' /tmp/new_peers.conf | awk '{print $3}')
if grep -q "$FIRST_NEW_PUBKEY" "$AWG_CONF" 2>/dev/null; then
  echo "  Peers already present, reloading anyway"
else
  cat /tmp/new_peers.conf >> "$AWG_CONF"
  echo "  Appended peers to config"
fi

# Live-reload without dropping existing tunnels
awg syncconf awg0 <(awg-quick strip awg0) 2>/dev/null || \
  systemctl restart awg-quick@awg0

echo "  AmneziaWG reloaded successfully"
rm -f /tmp/new_peers.conf
REMOTE_SCRIPT

  echo "  Server $SERVER_IDX complete"
done

echo ""
echo "=== All peers registered ==="
echo "Client configs are in: $CONFIGS_DIR/server-*/configs/client*.conf"
