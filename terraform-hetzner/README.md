# PhantomVPN — Hetzner Deployment

This is the Hetzner Cloud variant of the infrastructure. It replaces AWS
(EC2, EIP, S3, Lambda, SSM) with the bare minimum needed to run AmneziaWG:
just servers, a firewall, and SSH.

## Why Hetzner

| | AWS (`terraform/`) | Hetzner (`terraform-hetzner/`) |
|---|---|---|
| 1 server, idle | ~$35/mo | **~€7/mo** |
| 1,000 users (50 GB/mo each, 50 TB egress) | ~$4,400/mo | **~€28/mo** (4x cpx21, 80 TB included) |
| Egress price | $0.09/GB after 0 included | **€1.00/TB after 20 TB/server included** |
| Server provisioning | 1-2 min | 30 sec |
| IP rotation | Lambda + EventBridge (managed) | bash script + cron |
| Config storage | S3 + KMS | local files + SSH |

## Cost Math at 1,000 Users

Assuming 50 GB/user/month = 50 TB/month total egress:

| Setup | Servers | Compute | Traffic Overage | **Total** |
|---|---|---|---|---|
| **2x cpx21** (40 TB included) | €14 | — | 10 TB × €1 = €10 | **€24/mo** |
| **3x cpx21** (60 TB included) | €21 | — | 0 (covered) | **€21/mo** |
| **4x cpx31** (80 TB, 8 GB RAM) | €52 | — | 0 (covered) | **€52/mo** |

Compare to AWS at the same scale: **$2,500-$4,500/month**.

## Prerequisites

```bash
# 1. Hetzner Cloud account → create a project → Security → API Tokens → New (Read & Write)
export HCLOUD_TOKEN="your-token-here"

# 2. Tools
brew install terraform jq hcloud
brew install wireguard-tools   # provides wg / awg key generation locally

# 3. SSH key (any existing key works)
test -f ~/.ssh/id_ed25519.pub || ssh-keygen -t ed25519
```

## Deploy

```bash
cd terraform-hetzner

cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: set hcloud_token, admin_cidr_blocks, server_count, server_type

terraform init
terraform apply
```

Terraform writes a state summary to `../state/servers.json` that the helper
scripts read. After apply finishes, the servers run `userdata.sh` for ~2-3
minutes to install AmneziaWG.

## Generate Client Configs

From the project root:

```bash
./scripts-hetzner/generate_configs.sh --clients-per-server 50
```

This:
1. Reads server IPs from `state/servers.json`
2. SSHes to each server, fetches the AmneziaWG public key
3. Generates N client keypairs locally
4. Writes per-client `.conf` files to `configs/server-N/configs/clientM.conf`
5. Builds a `server_peers.conf` per server

## Register Peers on Servers

```bash
./scripts-hetzner/add_peers_to_servers.sh
```

This SSHes to each server, appends the generated peers to
`/etc/amnezia/amneziawg/awg0.conf`, and live-reloads the tunnel using
`awg syncconf` (no dropped connections).

## Distribute Configs

The `.conf` files in `configs/server-*/configs/` are the AmneziaWG client
configurations. Hand them to your iOS app via the existing Import flow
(`PhantomVPN > Servers > + > Import File`).

## IP Rotation (Optional)

```bash
export HCLOUD_TOKEN="your-token-here"
./scripts-hetzner/rotate_ips.sh --dry-run    # preview
./scripts-hetzner/rotate_ips.sh              # execute
```

Rotation does:
1. Allocate a new Hetzner Primary IPv4 in the same datacenter
2. Power off the server, swap the primary IP, power back on (~30 seconds of downtime per server)
3. Update `state/servers.json` with the new IP
4. Free the old primary IP

After rotation, regenerate and redistribute client configs:

```bash
./scripts-hetzner/generate_configs.sh --clients-per-server 50
./scripts-hetzner/add_peers_to_servers.sh
```

To run on a schedule, add to crontab on any machine that has the repo + `HCLOUD_TOKEN`:

```cron
0 3 * * * cd /path/to/VPN-Project && HCLOUD_TOKEN=xxx ./scripts-hetzner/rotate_ips.sh >> /var/log/vpn-rotate.log 2>&1
```

## Server Types — Pick Your Tier

| Type | vCPU | RAM | Traffic | Price | Good For |
|---|---|---|---|---|---|
| `cx22` | 2 Intel | 4 GB | 20 TB | €3.79/mo | <50 active users |
| `cpx21` | 3 AMD | 4 GB | 20 TB | €7.05/mo | **~250 active users (recommended)** |
| `cpx31` | 4 AMD | 8 GB | 20 TB | €13.10/mo | ~1,000 active users single-server |
| `cax21` | 4 ARM | 8 GB | 20 TB | €6.49/mo | ARM-friendly, cheaper than cpx31 |

WireGuard's bottleneck is almost always bandwidth, not CPU. Scale by
increasing `server_count` rather than `server_type` once you exceed
20 TB/month per server.

## Locations

| Code | City | Notes |
|---|---|---|
| `fsn1` | Falkenstein, DE | Cheapest, default |
| `nbg1` | Nuremberg, DE | Same price as fsn1 |
| `hel1` | Helsinki, FI | Closest to old AWS `eu-north-1` |
| `ash` | Ashburn, VA, USA | US East |
| `hil` | Hillsboro, OR, USA | US West |
| `sin` | Singapore | Asia |

## Tearing Down

```bash
cd terraform-hetzner
terraform destroy
rm -rf ../state ../configs
```

## What Got Dropped From the AWS Version

- **S3** — configs live locally in `configs/` (gitignored)
- **SSM Parameter Store** — server keys/IPs live in `/etc/amnezia/state/server.json` on each server, fetched via SSH
- **Lambda** — IP rotation moves to a local bash script using the `hcloud` CLI
- **EventBridge** — replaced by cron if you want scheduled rotation
- **VPC / subnets / route tables** — Hetzner gives every server a public IP; no VPC needed
- **IAM** — Hetzner uses a single API token

This setup is intentionally simpler. There's nothing magical AWS provides
for a VPN workload that justifies the 100x cost difference.
