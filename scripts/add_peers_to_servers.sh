#!/usr/bin/env bash
#
# SSH into each VPN server, append peer configs, and reload AmneziaWG.
# Usage: ./add_peers_to_servers.sh [--server-count N] [--ssh-key PATH]
#
set -euo pipefail

# ---------- Defaults ----------
SERVER_COUNT=1
AWS_REGION="eu-north-1"
PROJECT_NAME="amnezia-vpn"
CONFIG_BUCKET=""
SSH_KEY=""
SSH_USER="ubuntu"

# ---------- Parse arguments ----------
usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  --server-count N    Number of servers (default: 1)
  --region REGION     AWS region (default: eu-north-1)
  --project NAME      Project name prefix (default: amnezia-vpn)
  --bucket BUCKET     S3 config bucket (auto-detected if empty)
  --ssh-key PATH      Path to SSH private key
  --ssh-user USER     SSH username (default: ubuntu)
  -h, --help          Show this help
EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --server-count) SERVER_COUNT="$2"; shift 2 ;;
    --region)       AWS_REGION="$2"; shift 2 ;;
    --project)      PROJECT_NAME="$2"; shift 2 ;;
    --bucket)       CONFIG_BUCKET="$2"; shift 2 ;;
    --ssh-key)      SSH_KEY="$2"; shift 2 ;;
    --ssh-user)     SSH_USER="$2"; shift 2 ;;
    -h|--help)      usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

if [[ -z "$SSH_KEY" ]]; then
  echo "ERROR: --ssh-key is required"
  usage
fi

# ---------- Auto-detect bucket ----------
if [[ -z "$CONFIG_BUCKET" ]]; then
  CONFIG_BUCKET=$(cd "$(dirname "$0")/../terraform" && terraform output -raw config_bucket_name 2>/dev/null || true)
  if [[ -z "$CONFIG_BUCKET" ]]; then
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    CONFIG_BUCKET="${PROJECT_NAME}-configs-${ACCOUNT_ID}"
  fi
fi

echo "=== Adding Peers to AmneziaWG Servers ==="
echo "Servers: $SERVER_COUNT"
echo "Bucket:  $CONFIG_BUCKET"
echo ""

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

KNOWN_HOSTS_FILE="$TMPDIR/known_hosts"
: > "$KNOWN_HOSTS_FILE"

for SERVER_IDX in $(seq 0 $((SERVER_COUNT - 1))); do
  echo "--- Server $SERVER_IDX ---"

  # Get server IP from SSM
  SERVER_IP=$(aws ssm get-parameter \
    --region "$AWS_REGION" \
    --name "/$PROJECT_NAME/server/$SERVER_IDX/public_ip" \
    --query 'Parameter.Value' --output text)

  echo "  IP: $SERVER_IP"

  # Fetch SSH host public key from SSM (stored during bootstrap)
  SSH_HOST_KEY=$(aws ssm get-parameter \
    --region "$AWS_REGION" \
    --name "/$PROJECT_NAME/server/$SERVER_IDX/ssh_host_key" \
    --query 'Parameter.Value' --output text 2>/dev/null || true)

  if [[ -n "$SSH_HOST_KEY" ]]; then
    KEY_TYPE=$(echo "$SSH_HOST_KEY" | awk '{print $1}')
    KEY_DATA=$(echo "$SSH_HOST_KEY" | awk '{print $2}')
    echo "$SERVER_IP $KEY_TYPE $KEY_DATA" >> "$KNOWN_HOSTS_FILE"
    SSH_OPTS="-o StrictHostKeyChecking=yes -o UserKnownHostsFile=$KNOWN_HOSTS_FILE -o ConnectTimeout=10 -o LogLevel=ERROR"
    echo "  Host key pinned from SSM"
  else
    echo "  WARNING: No host key in SSM for server $SERVER_IDX — falling back to unverified connection."
    echo "           This is expected on first run before bootstrap stores the key."
    SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o LogLevel=ERROR"
  fi

  # Download server peers config from S3
  PEERS_FILE="$TMPDIR/server-${SERVER_IDX}_peers.conf"
  aws s3 cp "s3://$CONFIG_BUCKET/server-$SERVER_IDX/server_peers.conf" "$PEERS_FILE" \
    --region "$AWS_REGION" --quiet

  PEER_COUNT=$(grep -c '^\[Peer\]' "$PEERS_FILE" || echo 0)
  echo "  Peers to add: $PEER_COUNT"

  if [[ "$PEER_COUNT" -eq 0 ]]; then
    echo "  No peers found, skipping"
    continue
  fi

  # Upload peers file and apply on server
  scp $SSH_OPTS -i "$SSH_KEY" \
    "$PEERS_FILE" "${SSH_USER}@${SERVER_IP}:/tmp/new_peers.conf"

  # shellcheck disable=SC2087
  ssh $SSH_OPTS -i "$SSH_KEY" "${SSH_USER}@${SERVER_IP}" <<'REMOTE_SCRIPT'
set -euo pipefail

AWG_CONF="/etc/amnezia/amneziawg/awg0.conf"

if [[ ! -f "$AWG_CONF" ]]; then
  echo "ERROR: AmneziaWG config not found at $AWG_CONF"
  exit 1
fi

# Append new peers (skip if already present by checking first PublicKey)
FIRST_NEW_PUBKEY=$(grep -m1 'PublicKey' /tmp/new_peers.conf | awk '{print $3}')
if grep -q "$FIRST_NEW_PUBKEY" "$AWG_CONF" 2>/dev/null; then
  echo "  Peers already present in config, reloading anyway"
else
  sudo bash -c 'cat /tmp/new_peers.conf >> /etc/amnezia/amneziawg/awg0.conf'
  echo "  Appended peers to config"
fi

# Reload AmneziaWG without dropping existing connections
sudo awg syncconf awg0 <(sudo awg-quick strip awg0) 2>/dev/null || \
  sudo systemctl restart awg-quick@awg0

echo "  AmneziaWG reloaded successfully"
rm -f /tmp/new_peers.conf
REMOTE_SCRIPT

  echo "  Server $SERVER_IDX complete"
done

echo ""
echo "=== All peers registered ==="
