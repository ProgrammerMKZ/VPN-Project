variable "hcloud_token" {
  description = "Hetzner Cloud API token (create at https://console.hetzner.cloud → Security → API Tokens)"
  type        = string
  sensitive   = true
}

variable "project_name" {
  description = "Project name used as prefix for resource naming"
  type        = string
  default     = "amnezia-vpn"
}

variable "server_count" {
  description = "Number of VPN servers to deploy"
  type        = number
  default     = 1

  validation {
    condition     = var.server_count >= 1
    error_message = "At least one server is required."
  }
}

variable "server_type" {
  description = <<EOT
Hetzner server type. Common choices:
  cx22  — €3.79/mo, 2 vCPU Intel,   4 GB RAM, 20 TB traffic  (light, ~50 users)
  cpx21 — €7.05/mo, 3 vCPU AMD,     4 GB RAM, 20 TB traffic  (sweet spot, ~250 users)
  cpx31 — €13.10/mo, 4 vCPU AMD,    8 GB RAM, 20 TB traffic  (heavy, ~1000 users)
  cax21 — €6.49/mo, 4 vCPU ARM,     8 GB RAM, 20 TB traffic  (ARM, cheaper)
EOT
  type    = string
  default = "cpx21"
}

variable "server_image" {
  description = "OS image for the server"
  type        = string
  default     = "ubuntu-22.04"
}

variable "location" {
  description = <<EOT
Hetzner datacenter location:
  fsn1 — Falkenstein, Germany   (cheapest, EU)
  nbg1 — Nuremberg, Germany
  hel1 — Helsinki, Finland      (closest to old eu-north-1)
  ash  — Ashburn, Virginia, USA
  hil  — Hillsboro, Oregon, USA
  sin  — Singapore
EOT
  type    = string
  default = "fsn1"
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key to install on the servers (e.g. ~/.ssh/id_ed25519.pub)"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "admin_cidr_blocks" {
  description = "CIDR blocks allowed SSH access. Use [\"YOUR_IP/32\"] to lock it down to your IP."
  type        = list(string)

  validation {
    condition     = length(var.admin_cidr_blocks) > 0
    error_message = "At least one admin CIDR block is required for SSH access."
  }
}

variable "vpn_port" {
  description = "UDP port for AmneziaWG (443 blends with HTTPS)"
  type        = number
  default     = 443
}

variable "vpn_subnet" {
  description = "Internal VPN tunnel subnet"
  type        = string
  default     = "10.8.0.0/24"
}

variable "clients_per_server" {
  description = "Number of VPN client configs to generate per server (used by scripts, not Terraform)"
  type        = number
  default     = 50
}

variable "dns_servers" {
  description = "DNS servers for VPN clients"
  type        = string
  default     = "1.1.1.1, 1.0.0.1"
}

# AmneziaWG obfuscation parameters
variable "awg_jc" {
  description = "Junk packet count (Jc)"
  type        = number
  default     = 4
}

variable "awg_jmin" {
  description = "Junk packet minimum size (Jmin)"
  type        = number
  default     = 40
}

variable "awg_jmax" {
  description = "Junk packet maximum size (Jmax)"
  type        = number
  default     = 70
}

variable "awg_s1" {
  description = "Init packet junk size (S1)"
  type        = number
  default     = 0
}

variable "awg_s2" {
  description = "Response packet junk size (S2)"
  type        = number
  default     = 0
}

variable "awg_h1" {
  description = "Init packet header obfuscation (H1)"
  type        = number
  default     = 1
}

variable "awg_h2" {
  description = "Response packet header obfuscation (H2)"
  type        = number
  default     = 2
}

variable "awg_h3" {
  description = "Under-load packet header obfuscation (H3)"
  type        = number
  default     = 3
}

variable "awg_h4" {
  description = "Transport packet header obfuscation (H4)"
  type        = number
  default     = 4
}
