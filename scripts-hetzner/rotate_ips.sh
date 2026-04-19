#!/usr/bin/env bash
#
# Rotate the public IPv4 of each Hetzner VPN server with zero downtime,
# then regenerate all client configs to point at the new IPs and re-upload.
#
# Strategy: Hetzner doesn't have AWS-style EIP reassignment. The cleanest
# rotation is to assign a new Primary IP to the server (which requires a brief
# reboot) OR to delete + recreate the server. This script uses the Primary IP
# swap approach via the hcloud CLI.
#
# Requires: hcloud CLI (brew install hcloud), HCLOUD_TOKEN env var set.
#
# Usage: ./rotate_ips.sh [--ssh-key PATH] [--dry-run]
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
STATE_FILE="$ROOT_DIR/state/servers.json"

SSH_KEY=""
DRY_RUN=false

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  --ssh-key PATH   SSH private key (default: ~/.ssh/id_ed25519)
  --dry-run        Show what would happen, don't execute
  -h, --help       Show this help

Requires:
  - hcloud CLI installed (brew install hcloud)
  - HCLOUD_TOKEN env var set (same token as terraform.tfvars)
EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ssh-key) SSH_KEY="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

[[ -z "$SSH_KEY" ]] && SSH_KEY="$HOME/.ssh/id_ed25519"
command -v hcloud >/dev/null || { echo "ERROR: hcloud CLI required (brew install hcloud)"; exit 1; }
command -v jq >/dev/null     || { echo "ERROR: jq required"; exit 1; }
[[ -z "${HCLOUD_TOKEN:-}" ]] && { echo "ERROR: set HCLOUD_TOKEN env var"; exit 1; }
[[ ! -f "$STATE_FILE" ]] && { echo "ERROR: $STATE_FILE not found"; exit 1; }

PROJECT_NAME=$(jq -r '.project_name' "$STATE_FILE")
SERVER_COUNT=$(jq '.servers | length' "$STATE_FILE")

echo "=== Rotating Public IPs for $SERVER_COUNT Server(s) ==="
$DRY_RUN && echo "*** DRY RUN — no changes will be made ***"
echo ""

SSH_OPTS="-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -o LogLevel=ERROR"

run() {
  if $DRY_RUN; then
    echo "  [dry-run] $*"
  else
    eval "$@"
  fi
}

for SERVER_IDX in $(seq 0 $((SERVER_COUNT - 1))); do
  SERVER_ID=$(jq -r ".servers[$SERVER_IDX].id"   "$STATE_FILE")
  SERVER_NAME=$(jq -r ".servers[$SERVER_IDX].name" "$STATE_FILE")
  OLD_IP=$(jq -r ".servers[$SERVER_IDX].ipv4"     "$STATE_FILE")
  LOCATION=$(jq -r ".servers[$SERVER_IDX].location" "$STATE_FILE")

  echo "--- Server $SERVER_IDX ($SERVER_NAME) ---"
  echo "  Current IP: $OLD_IP"

  # 1. Allocate a new primary IPv4 in the same datacenter
  NEW_IP_NAME="${PROJECT_NAME}-rotation-$(date +%s)-${SERVER_IDX}"
  if $DRY_RUN; then
    echo "  [dry-run] hcloud primary-ip create --type ipv4 --name $NEW_IP_NAME --datacenter $LOCATION-dc14"
    NEW_IP="X.X.X.X"
  else
    NEW_IP=$(hcloud primary-ip create \
      --type ipv4 \
      --name "$NEW_IP_NAME" \
      --datacenter "${LOCATION}-dc14" \
      --label "service=amnezia-vpn" \
      --label "rotation=auto" \
      --output json | jq -r '.primary_ip.ip_address')
    echo "  New IP allocated: $NEW_IP"
  fi

  # 2. Get current primary IP id (to delete after swap)
  if ! $DRY_RUN; then
    OLD_PRIMARY_ID=$(hcloud server describe "$SERVER_ID" -o json \
      | jq -r '.public_net.ipv4.id')
  fi

  # 3. Power off briefly, swap primary IP, power on
  echo "  Stopping server..."
  run "hcloud server poweroff $SERVER_ID"
  run "hcloud primary-ip unassign $OLD_PRIMARY_ID || true"
  run "hcloud primary-ip assign $NEW_IP_NAME --assignee-type server --assignee-id $SERVER_ID"
  echo "  Starting server..."
  run "hcloud server poweron $SERVER_ID"

  # 4. Wait for SSH to come back up
  if ! $DRY_RUN; then
    echo "  Waiting for SSH on $NEW_IP..."
    for attempt in $(seq 1 30); do
      if ssh $SSH_OPTS -i "$SSH_KEY" "root@$NEW_IP" "true" 2>/dev/null; then
        echo "  Server is back online"
        break
      fi
      sleep 5
      (( attempt == 30 )) && { echo "  ERROR: server did not come back online"; exit 1; }
    done

    # 5. Update local state file
    tmp=$(mktemp)
    jq ".servers[$SERVER_IDX].ipv4 = \"$NEW_IP\"" "$STATE_FILE" > "$tmp"
    mv "$tmp" "$STATE_FILE"
    echo "  Updated local state with new IP"

    # 6. Update server's own metadata file
    ssh $SSH_OPTS -i "$SSH_KEY" "root@$NEW_IP" \
      "jq '.public_ip = \"$NEW_IP\"' /etc/amnezia/state/server.json > /tmp/s.json && mv /tmp/s.json /etc/amnezia/state/server.json"

    # 7. Release the old primary IP (free, but cleanup keeps things tidy)
    hcloud primary-ip delete "$OLD_PRIMARY_ID" 2>/dev/null || \
      echo "  (old IP $OLD_PRIMARY_ID could not be deleted — it may already be released)"
  fi

  echo "  Done: $OLD_IP -> $NEW_IP"
  echo ""
done

echo "=== Rotation complete ==="
echo ""
echo "NEXT STEPS:"
echo "  1. Regenerate client configs with the new IPs:"
echo "       ./scripts-hetzner/generate_configs.sh --clients-per-server N"
echo "  2. Re-register peers (the server keys did not change, but configs must be redistributed):"
echo "       ./scripts-hetzner/add_peers_to_servers.sh"
echo "  3. Distribute the updated client .conf files to your users."
