#!/bin/bash
set -euo pipefail

exec > >(tee /var/log/userdata.log) 2>&1
echo "=== AmneziaWG Server Bootstrap (server-${server_index}) ==="

export DEBIAN_FRONTEND=noninteractive
AWS_REGION="${aws_region}"
PROJECT="${project_name}"
SERVER_INDEX="${server_index}"
VPN_PORT="${vpn_port}"
VPN_SUBNET="${vpn_subnet}"

# AmneziaWG obfuscation parameters (passed as Terraform template variables)
AWG_JC="${awg_jc}"
AWG_JMIN="${awg_jmin}"
AWG_JMAX="${awg_jmax}"
AWG_S1="${awg_s1}"
AWG_S2="${awg_s2}"
AWG_H1="${awg_h1}"
AWG_H2="${awg_h2}"
AWG_H3="${awg_h3}"
AWG_H4="${awg_h4}"

# ---------- IMDSv2 helper ----------
imds_token() {
  curl -sS --fail -X PUT \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 300" \
    http://169.254.169.254/latest/api/token
}

imds_get() {
  local token
  token="$(imds_token)"
  curl -sS --fail -H "X-aws-ec2-metadata-token: $token" \
    "http://169.254.169.254/latest/meta-data/$1"
}

# ---------- Install AmneziaWG ----------
apt-get update -y
apt-get install -y software-properties-common awscli jq

add-apt-repository -y ppa:amnezia/ppa
apt-get update -y
apt-get install -y amneziawg-dkms amneziawg-tools

# ---------- Generate server keys ----------
SERVER_PRIVATE_KEY=$(awg genkey)
SERVER_PUBLIC_KEY=$(echo "$SERVER_PRIVATE_KEY" | awg pubkey)

# Store keys in SSM Parameter Store (private key via stdin to avoid /proc/cmdline exposure)
printf '{"Name":"/%s/server/%s/private_key","Value":"%s","Type":"SecureString","Overwrite":true}' \
  "$PROJECT" "$SERVER_INDEX" "$SERVER_PRIVATE_KEY" | \
  aws ssm put-parameter --region "$AWS_REGION" --cli-input-json file:///dev/stdin

aws ssm put-parameter \
  --region "$AWS_REGION" \
  --name "/$PROJECT/server/$SERVER_INDEX/public_key" \
  --value "$SERVER_PUBLIC_KEY" \
  --type String \
  --overwrite

aws ssm put-parameter \
  --region "$AWS_REGION" \
  --name "/$PROJECT/server/$SERVER_INDEX/listen_port" \
  --value "$VPN_PORT" \
  --type String \
  --overwrite

# Store server IP in SSM
SERVER_PUBLIC_IP=$(imds_get "public-ipv4")
aws ssm put-parameter \
  --region "$AWS_REGION" \
  --name "/$PROJECT/server/$SERVER_INDEX/public_ip" \
  --value "$SERVER_PUBLIC_IP" \
  --type String \
  --overwrite

# Store SSH host public key in SSM for host key pinning by admin scripts
SSH_HOST_PUB_KEY=$(cat /etc/ssh/ssh_host_ed25519_key.pub)
aws ssm put-parameter \
  --region "$AWS_REGION" \
  --name "/$PROJECT/server/$SERVER_INDEX/ssh_host_key" \
  --value "$SSH_HOST_PUB_KEY" \
  --type String \
  --overwrite

# ---------- Network interface for NAT ----------
PRIMARY_IFACE=$(imds_get "network/interfaces/macs/" | head -1 | tr -d '/')
PRIMARY_IFACE_NAME=$(ip -o link show | awk -F': ' '{print $2}' | grep -E '^(eth|ens|enp)' | head -1)

# ---------- Create AmneziaWG config directory and file ----------
mkdir -p /etc/amnezia/amneziawg

# Server gets first IP in the VPN subnet (e.g., 10.8.0.1)
VPN_NETWORK=$(echo "$VPN_SUBNET" | cut -d'/' -f1)
VPN_MASK=$(echo "$VPN_SUBNET" | cut -d'/' -f2)
SERVER_VPN_IP=$(echo "$VPN_NETWORK" | awk -F. '{printf "%s.%s.%s.%d", $1, $2, $3, $4+1}')

cat > /etc/amnezia/amneziawg/awg0.conf <<EOF
[Interface]
PrivateKey = $SERVER_PRIVATE_KEY
Address = $SERVER_VPN_IP/$VPN_MASK
ListenPort = $VPN_PORT
SaveConfig = false

PostUp = iptables -t nat -A POSTROUTING -o $PRIMARY_IFACE_NAME -j MASQUERADE; iptables -A FORWARD -i awg0 -j ACCEPT; iptables -A FORWARD -o awg0 -j ACCEPT
PostDown = iptables -t nat -D POSTROUTING -o $PRIMARY_IFACE_NAME -j MASQUERADE; iptables -D FORWARD -i awg0 -j ACCEPT; iptables -D FORWARD -o awg0 -j ACCEPT

Jc = $AWG_JC
Jmin = $AWG_JMIN
Jmax = $AWG_JMAX
S1 = $AWG_S1
S2 = $AWG_S2
H1 = $AWG_H1
H2 = $AWG_H2
H3 = $AWG_H3
H4 = $AWG_H4
EOF

chmod 600 /etc/amnezia/amneziawg/awg0.conf

# ---------- Enable IP forwarding ----------
cat > /etc/sysctl.d/99-amneziawg.conf <<EOF
net.ipv4.ip_forward = 1
net.ipv4.conf.all.forwarding = 1
EOF
sysctl --system

# ---------- Start AmneziaWG ----------
systemctl enable awg-quick@awg0
systemctl start awg-quick@awg0

echo "=== AmneziaWG server-${server_index} bootstrap complete ==="
