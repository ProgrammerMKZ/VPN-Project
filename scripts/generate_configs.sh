#!/usr/bin/env bash
#
# Generate AmneziaWG client and server configs, upload to S3.
# Usage: ./generate_configs.sh --clients-per-server N [--server-count M] [--region REGION]
#
set -euo pipefail

# ---------- Defaults ----------
CLIENTS_PER_SERVER=""
SERVER_COUNT=1
AWS_REGION="eu-north-1"
PROJECT_NAME="amnezia-vpn"
VPN_PORT=443
VPN_SUBNET="10.8.0.0/24"
DNS_SERVERS="1.1.1.1, 1.0.0.1"
CONFIG_BUCKET=""
PARALLEL_UPLOADS=10

# AmneziaWG obfuscation defaults
AWG_JC=4; AWG_JMIN=40; AWG_JMAX=70
AWG_S1=0; AWG_S2=0
AWG_H1=1; AWG_H2=2; AWG_H3=3; AWG_H4=4

# ---------- Parse arguments ----------
usage() {
  cat <<EOF
Usage: $(basename "$0") --clients-per-server N [OPTIONS]

Required:
  --clients-per-server N   Number of client configs to generate per server

Options:
  --server-count M         Number of servers (default: 1)
  --region REGION          AWS region (default: eu-north-1)
  --project NAME           Project name prefix (default: amnezia-vpn)
  --bucket BUCKET          S3 config bucket (auto-detected from Terraform if empty)
  --vpn-port PORT          VPN listen port (default: 443)
  --vpn-subnet CIDR        VPN tunnel subnet (default: 10.8.0.0/24)
  --dns SERVERS            DNS servers for clients (default: 1.1.1.1, 1.0.0.1)
  --parallel N             Parallel S3 uploads (default: 10)
  -h, --help               Show this help
EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --clients-per-server) CLIENTS_PER_SERVER="$2"; shift 2 ;;
    --server-count)       SERVER_COUNT="$2"; shift 2 ;;
    --region)             AWS_REGION="$2"; shift 2 ;;
    --project)            PROJECT_NAME="$2"; shift 2 ;;
    --bucket)             CONFIG_BUCKET="$2"; shift 2 ;;
    --vpn-port)           VPN_PORT="$2"; shift 2 ;;
    --vpn-subnet)         VPN_SUBNET="$2"; shift 2 ;;
    --dns)                DNS_SERVERS="$2"; shift 2 ;;
    --parallel)           PARALLEL_UPLOADS="$2"; shift 2 ;;
    -h|--help)            usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

if [[ -z "$CLIENTS_PER_SERVER" ]]; then
  echo "ERROR: --clients-per-server is required"
  usage
fi

# ---------- Auto-detect bucket from Terraform ----------
if [[ -z "$CONFIG_BUCKET" ]]; then
  CONFIG_BUCKET=$(cd "$(dirname "$0")/../terraform" && terraform output -raw config_bucket_name 2>/dev/null || true)
  if [[ -z "$CONFIG_BUCKET" ]]; then
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    CONFIG_BUCKET="${PROJECT_NAME}-configs-${ACCOUNT_ID}"
  fi
fi

echo "=== AmneziaWG Config Generator ==="
echo "Servers:           $SERVER_COUNT"
echo "Clients per server: $CLIENTS_PER_SERVER"
echo "Config bucket:     $CONFIG_BUCKET"
echo "Region:            $AWS_REGION"
echo "VPN subnet:        $VPN_SUBNET"
echo ""

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

VPN_BASE=$(echo "$VPN_SUBNET" | cut -d'/' -f1)
VPN_MASK=$(echo "$VPN_SUBNET" | cut -d'/' -f2)
IFS='.' read -r O1 O2 O3 O4 <<< "$VPN_BASE"

# Convert base IP to a 32-bit integer for proper arithmetic
ip_to_int() { IFS='.' read -r a b c d <<< "$1"; echo $(( (a << 24) + (b << 16) + (c << 8) + d )); }
int_to_ip() { echo "$(( ($1 >> 24) & 255 )).$(( ($1 >> 16) & 255 )).$(( ($1 >> 8) & 255 )).$(( $1 & 255 ))"; }

BASE_INT=$(ip_to_int "$VPN_BASE")
HOST_BITS=$((32 - VPN_MASK))
MAX_HOSTS=$(( (1 << HOST_BITS) - 2 ))  # subtract network + broadcast

# server takes offset 1, clients take 2..N+1
if (( CLIENTS_PER_SERVER + 1 > MAX_HOSTS )); then
  echo "ERROR: $CLIENTS_PER_SERVER clients + 1 server exceeds /$VPN_MASK capacity ($MAX_HOSTS usable hosts)"
  exit 1
fi

for SERVER_IDX in $(seq 0 $((SERVER_COUNT - 1))); do
  echo "--- Server $SERVER_IDX ---"

  SERVER_DIR="$TMPDIR/server-$SERVER_IDX"
  mkdir -p "$SERVER_DIR"/{keys,configs}

  # Fetch server keys from SSM
  SERVER_PUBLIC_KEY=$(aws ssm get-parameter \
    --region "$AWS_REGION" \
    --name "/$PROJECT_NAME/server/$SERVER_IDX/public_key" \
    --query 'Parameter.Value' --output text)

  SERVER_PUBLIC_IP=$(aws ssm get-parameter \
    --region "$AWS_REGION" \
    --name "/$PROJECT_NAME/server/$SERVER_IDX/public_ip" \
    --query 'Parameter.Value' --output text)

  LISTEN_PORT=$(aws ssm get-parameter \
    --region "$AWS_REGION" \
    --name "/$PROJECT_NAME/server/$SERVER_IDX/listen_port" \
    --query 'Parameter.Value' --output text 2>/dev/null || echo "$VPN_PORT")

  SERVER_VPN_IP=$(int_to_ip $((BASE_INT + 1)))

  # Server peer config accumulator
  SERVER_PEERS_FILE="$SERVER_DIR/server_peers.conf"
  : > "$SERVER_PEERS_FILE"

  for CLIENT_IDX in $(seq 1 "$CLIENTS_PER_SERVER"); do
    CLIENT_IP=$(int_to_ip $((BASE_INT + CLIENT_IDX + 1)))

    # Generate key pair + PSK
    CLIENT_PRIVATE_KEY=$(awg genkey 2>/dev/null || wg genkey)
    CLIENT_PUBLIC_KEY=$(echo "$CLIENT_PRIVATE_KEY" | { awg pubkey 2>/dev/null || wg pubkey; })
    CLIENT_PSK=$(awg genpsk 2>/dev/null || wg genpsk)

    # Save keys
    echo "$CLIENT_PRIVATE_KEY" > "$SERVER_DIR/keys/client${CLIENT_IDX}_private.key"
    echo "$CLIENT_PUBLIC_KEY"  > "$SERVER_DIR/keys/client${CLIENT_IDX}_public.key"
    echo "$CLIENT_PSK"         > "$SERVER_DIR/keys/client${CLIENT_IDX}_psk.key"

    # Client config
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
Endpoint = $SERVER_PUBLIC_IP:$LISTEN_PORT
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
PresharedKey = $CLIENT_PSK
EOF

    # Append to server peers
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

  # Upload to S3 using sync for parallel transfers
  echo "  Uploading keys and configs to s3://$CONFIG_BUCKET/server-$SERVER_IDX/ ..."
  aws s3 sync "$SERVER_DIR/" "s3://$CONFIG_BUCKET/server-$SERVER_IDX/" \
    --region "$AWS_REGION" \
    --sse aws:kms \
    --no-progress

  echo "  Upload complete for server $SERVER_IDX"
done

echo ""
echo "=== Config generation complete ==="
echo "Bucket: s3://$CONFIG_BUCKET"
echo "Next step: run add_peers_to_servers.sh to register peers on the servers"
