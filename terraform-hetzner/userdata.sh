#!/bin/bash
set -euo pipefail

exec > >(tee /var/log/userdata.log) 2>&1
echo "=== AmneziaWG Server Bootstrap (server-${server_index}) ==="

export DEBIAN_FRONTEND=noninteractive
SERVER_INDEX="${server_index}"
VPN_PORT="${vpn_port}"
VPN_SUBNET="${vpn_subnet}"

AWG_JC="${awg_jc}"
AWG_JMIN="${awg_jmin}"
AWG_JMAX="${awg_jmax}"
AWG_S1="${awg_s1}"
AWG_S2="${awg_s2}"
AWG_H1="${awg_h1}"
AWG_H2="${awg_h2}"
AWG_H3="${awg_h3}"
AWG_H4="${awg_h4}"

# ---------- Install AmneziaWG ----------
apt-get update -y
apt-get install -y software-properties-common jq curl

add-apt-repository -y ppa:amnezia/ppa
apt-get update -y
apt-get install -y amneziawg-dkms amneziawg-tools

# ---------- Generate server keys ----------
SERVER_PRIVATE_KEY=$(awg genkey)
SERVER_PUBLIC_KEY=$(echo "$SERVER_PRIVATE_KEY" | awg pubkey)

# ---------- Determine public IP and primary interface ----------
SERVER_PUBLIC_IP=$(curl -s --max-time 5 https://ipv4.icanhazip.com || curl -s --max-time 5 https://api.ipify.org)
PRIMARY_IFACE_NAME=$(ip -o link show | awk -F': ' '{print $2}' | grep -E '^(eth|ens|enp)' | head -1)

# ---------- Persist server metadata locally ----------
# Scripts read this via SSH instead of using SSM/Parameter Store.
mkdir -p /etc/amnezia/state
cat > /etc/amnezia/state/server.json <<EOF
{
  "server_index": $SERVER_INDEX,
  "public_ip": "$SERVER_PUBLIC_IP",
  "public_key": "$SERVER_PUBLIC_KEY",
  "listen_port": $VPN_PORT,
  "primary_iface": "$PRIMARY_IFACE_NAME"
}
EOF
chmod 600 /etc/amnezia/state/server.json

# Keep private key only on the server itself, never expose it
echo "$SERVER_PRIVATE_KEY" > /etc/amnezia/state/server.key
chmod 600 /etc/amnezia/state/server.key

# ---------- Create AmneziaWG config ----------
mkdir -p /etc/amnezia/amneziawg

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
net.ipv6.conf.all.forwarding = 1
EOF
sysctl --system

# ---------- Start AmneziaWG ----------
systemctl enable awg-quick@awg0
systemctl start awg-quick@awg0

# ---------- Hardening: fail2ban for SSH ----------
apt-get install -y fail2ban
systemctl enable --now fail2ban

# Mark bootstrap done
touch /etc/amnezia/state/bootstrap_complete

echo "=== AmneziaWG server-${server_index} bootstrap complete ==="
echo "Public IP:  $SERVER_PUBLIC_IP"
echo "Public key: $SERVER_PUBLIC_KEY"
echo "VPN port:   $VPN_PORT"
