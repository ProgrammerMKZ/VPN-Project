#!/usr/bin/env bash
#
# Generate AmneziaWG client + server-peer configs for Hetzner deployment.
# Reads server metadata from terraform-hetzner state, fetches each server's
# public key over SSH, writes everything into ./configs/server-N/ locally.
#
# Usage: ./generate_configs.sh --clients-per-server N [OPTIONS]
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
STATE_FILE="$ROOT_DIR/state/servers.json"
CONFIGS_DIR="$ROOT_DIR/configs"

CLIENTS_PER_SERVER=""
SSH_KEY=""
SSH_USER="root"
OUTPUT_DIR="$CONFIGS_DIR"

usage() {
  cat <<EOF
Usage: $(basename "$0") --clients-per-server N [OPTIONS]

Required:
  --clients-per-server N   Number of client configs to generate per server

Options:
  --ssh-key PATH           SSH private key (default: ~/.ssh/id_ed25519)
  --ssh-user USER          SSH username (default: root)
  --output-dir DIR         Where to write client configs (default: ./configs)
  -h, --help               Show this help

Reads server list from: $STATE_FILE  (created by terraform apply)
EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --clients-per-server) CLIENTS_PER_SERVER="$2"; shift 2 ;;
    --ssh-key)            SSH_KEY="$2"; shift 2 ;;
    --ssh-user)           SSH_USER="$2"; shift 2 ;;
    --output-dir)         OUTPUT_DIR="$2"; shift 2 ;;
    -h|--help)            usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

[[ -z "$CLIENTS_PER_SERVER" ]] && { echo "ERROR: --clients-per-server is required"; usage; }
[[ -z "$SSH_KEY" ]] && SSH_KEY="$HOME/.ssh/id_ed25519"
[[ ! -f "$STATE_FILE" ]] && { echo "ERROR: $STATE_FILE not found. Run 'terraform apply' first."; exit 1; }
command -v jq >/dev/null || { echo "ERROR: jq is required (brew install jq)"; exit 1; }
command -v wg >/dev/null || command -v awg >/dev/null || {
  echo "ERROR: 'wg' or 'awg' tool required to generate keys (brew install wireguard-tools)"
  exit 1
}

KEYGEN=$(command -v awg || command -v wg)

# ---------- Load global config from state ----------
PROJECT_NAME=$(jq -r '.project_name' "$STATE_FILE")
VPN_PORT=$(jq -r '.vpn_port' "$STATE_FILE")
VPN_SUBNET=$(jq -r '.vpn_subnet' "$STATE_FILE")
DNS_SERVERS=$(jq -r '.dns_servers' "$STATE_FILE")

AWG_JC=$(jq -r '.awg.Jc' "$STATE_FILE")
AWG_JMIN=$(jq -r '.awg.Jmin' "$STATE_FILE")
AWG_JMAX=$(jq -r '.awg.Jmax' "$STATE_FILE")
AWG_S1=$(jq -r '.awg.S1' "$STATE_FILE")
AWG_S2=$(jq -r '.awg.S2' "$STATE_FILE")
AWG_H1=$(jq -r '.awg.H1' "$STATE_FILE")
AWG_H2=$(jq -r '.awg.H2' "$STATE_FILE")
AWG_H3=$(jq -r '.awg.H3' "$STATE_FILE")
AWG_H4=$(jq -r '.awg.H4' "$STATE_FILE")

SERVER_COUNT=$(jq '.servers | length' "$STATE_FILE")

echo "=== AmneziaWG Config Generator (Hetzner) ==="
echo "Project:           $PROJECT_NAME"
echo "Servers:           $SERVER_COUNT"
echo "Clients/server:    $CLIENTS_PER_SERVER"
echo "Output:            $OUTPUT_DIR"
echo ""

mkdir -p "$OUTPUT_DIR"

# ---------- IP arithmetic helpers ----------
ip_to_int() { IFS='.' read -r a b c d <<< "$1"; echo $(( (a << 24) + (b << 16) + (c << 8) + d )); }
int_to_ip() { echo "$(( ($1 >> 24) & 255 )).$(( ($1 >> 16) & 255 )).$(( ($1 >> 8) & 255 )).$(( $1 & 255 ))"; }

VPN_BASE=$(echo "$VPN_SUBNET" | cut -d'/' -f1)
VPN_MASK=$(echo "$VPN_SUBNET" | cut -d'/' -f2)
BASE_INT=$(ip_to_int "$VPN_BASE")

HOST_BITS=$((32 - VPN_MASK))
MAX_HOSTS=$(( (1 << HOST_BITS) - 2 ))
if (( CLIENTS_PER_SERVER + 1 > MAX_HOSTS )); then
  echo "ERROR: $CLIENTS_PER_SERVER clients exceeds /$VPN_MASK capacity ($MAX_HOSTS hosts)"
  exit 1
fi

SSH_OPTS="-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -o LogLevel=ERROR"

for SERVER_IDX in $(seq 0 $((SERVER_COUNT - 1))); do
  echo "--- Server $SERVER_IDX ---"

  SERVER_IP=$(jq -r ".servers[$SERVER_IDX].ipv4" "$STATE_FILE")
  echo "  IP: $SERVER_IP"

  # ---------- Wait for bootstrap to finish ----------
  echo "  Waiting for AmneziaWG bootstrap to finish on $SERVER_IP..."
  for attempt in $(seq 1 30); do
    if ssh $SSH_OPTS -i "$SSH_KEY" "${SSH_USER}@${SERVER_IP}" "test -f /etc/amnezia/state/bootstrap_complete" 2>/dev/null; then
      echo "  Bootstrap complete"
      break
    fi
    sleep 10
    if (( attempt == 30 )); then
      echo "  ERROR: Bootstrap did not finish within 5 minutes"
      exit 1
    fi
  done

  # ---------- Fetch server's public key ----------
  SERVER_META=$(ssh $SSH_OPTS -i "$SSH_KEY" "${SSH_USER}@${SERVER_IP}" \
    "cat /etc/amnezia/state/server.json")
  SERVER_PUBLIC_KEY=$(echo "$SERVER_META" | jq -r '.public_key')
  LISTEN_PORT=$(echo "$SERVER_META"     | jq -r '.listen_port')
  echo "  Server public key: $SERVER_PUBLIC_KEY"

  SERVER_DIR="$OUTPUT_DIR/server-$SERVER_IDX"
  mkdir -p "$SERVER_DIR/keys" "$SERVER_DIR/configs"

  SERVER_PEERS_FILE="$SERVER_DIR/server_peers.conf"
  : > "$SERVER_PEERS_FILE"

  for CLIENT_IDX in $(seq 1 "$CLIENTS_PER_SERVER"); do
    CLIENT_IP=$(int_to_ip $((BASE_INT + CLIENT_IDX + 1)))

    CLIENT_PRIVATE_KEY=$($KEYGEN genkey)
    CLIENT_PUBLIC_KEY=$(echo "$CLIENT_PRIVATE_KEY" | $KEYGEN pubkey)
    CLIENT_PSK=$($KEYGEN genpsk)

    echo "$CLIENT_PRIVATE_KEY" > "$SERVER_DIR/keys/client${CLIENT_IDX}_private.key"
    echo "$CLIENT_PUBLIC_KEY"  > "$SERVER_DIR/keys/client${CLIENT_IDX}_public.key"
    echo "$CLIENT_PSK"         > "$SERVER_DIR/keys/client${CLIENT_IDX}_psk.key"
    chmod 600 "$SERVER_DIR/keys/"*

    cat > "$SERVER_DIR/configs/client${CLIENT_IDX}.conf" <<EOF
[Interface]
PrivateKey = $CLIENT_PRIVATE_KEY
Address = $CLIENT_IP/$VPN_MASK
DNS = $DNS_SERVERS
Jc = $AWG_JC
Jmin = $AWG_JMIN
Jmax = $AWG_JMAX
S1 = $AWG_S1
S2 = $AWG_S2
H1 = $AWG_H1
H2 = $AWG_H2
H3 = $AWG_H3
H4 = $AWG_H4

[Peer]
PublicKey = $SERVER_PUBLIC_KEY
Endpoint = $SERVER_IP:$LISTEN_PORT
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
PresharedKey = $CLIENT_PSK
EOF

    cat >> "$SERVER_PEERS_FILE" <<EOF

[Peer]
PublicKey = $CLIENT_PUBLIC_KEY
PresharedKey = $CLIENT_PSK
AllowedIPs = $CLIENT_IP/32
EOF

    if (( CLIENT_IDX % 25 == 0 )); then
      echo "  Generated $CLIENT_IDX / $CLIENTS_PER_SERVER clients"
    fi
  done

  echo "  Generated all $CLIENTS_PER_SERVER clients for server $SERVER_IDX"
done

echo ""
echo "=== Config generation complete ==="
echo "Output: $OUTPUT_DIR/"
echo "Next:   ./scripts-hetzner/add_peers_to_servers.sh --ssh-key $SSH_KEY"
