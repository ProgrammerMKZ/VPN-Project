terraform {
  required_version = ">= 1.5.0"

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.48"
    }
  }
}

provider "hcloud" {
  token = var.hcloud_token
}

locals {
  name_prefix = var.project_name
  common_labels = {
    service = "amnezia-vpn"
    project = var.project_name
  }
}

# ============================================================
#  SSH KEY
# ============================================================

resource "hcloud_ssh_key" "admin" {
  name       = "${local.name_prefix}-admin"
  public_key = file(var.ssh_public_key_path)
  labels     = local.common_labels
}

# ============================================================
#  FIREWALL
# ============================================================

resource "hcloud_firewall" "vpn" {
  name   = "${local.name_prefix}-firewall"
  labels = local.common_labels

  # AmneziaWG / WireGuard UDP
  rule {
    direction = "in"
    protocol  = "udp"
    port      = tostring(var.vpn_port)
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # SSH from admin CIDR(s) only
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = var.admin_cidr_blocks
  }

  # ICMP for ping/MTU discovery
  rule {
    direction  = "in"
    protocol   = "icmp"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
}

# ============================================================
#  SERVERS (scalable via server_count)
# ============================================================

resource "hcloud_server" "vpn" {
  count = var.server_count

  name        = "${local.name_prefix}-${count.index}"
  server_type = var.server_type
  image       = var.server_image
  location    = var.location

  ssh_keys     = [hcloud_ssh_key.admin.id]
  firewall_ids = [hcloud_firewall.vpn.id]

  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }

  user_data = templatefile("${path.module}/userdata.sh", {
    server_index = count.index
    vpn_port     = var.vpn_port
    vpn_subnet   = var.vpn_subnet
    awg_jc       = var.awg_jc
    awg_jmin     = var.awg_jmin
    awg_jmax     = var.awg_jmax
    awg_s1       = var.awg_s1
    awg_s2       = var.awg_s2
    awg_h1       = var.awg_h1
    awg_h2       = var.awg_h2
    awg_h3       = var.awg_h3
    awg_h4       = var.awg_h4
  })

  labels = merge(local.common_labels, {
    server_index = tostring(count.index)
  })

  lifecycle {
    ignore_changes = [user_data, image]
  }
}

# ============================================================
#  STATE FILE — record server info locally for scripts to read
# ============================================================

resource "local_file" "servers_state" {
  filename        = "${path.module}/../state/servers.json"
  file_permission = "0600"

  content = jsonencode({
    project_name = var.project_name
    vpn_port     = var.vpn_port
    vpn_subnet   = var.vpn_subnet
    dns_servers  = var.dns_servers
    awg = {
      Jc   = var.awg_jc
      Jmin = var.awg_jmin
      Jmax = var.awg_jmax
      S1   = var.awg_s1
      S2   = var.awg_s2
      H1   = var.awg_h1
      H2   = var.awg_h2
      H3   = var.awg_h3
      H4   = var.awg_h4
    }
    servers = [
      for idx, srv in hcloud_server.vpn : {
        index     = idx
        id        = srv.id
        name      = srv.name
        ipv4      = srv.ipv4_address
        ipv6      = srv.ipv6_address
        location  = srv.location
        server_type = srv.server_type
      }
    ]
  })
}
