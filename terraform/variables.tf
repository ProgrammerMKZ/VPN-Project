variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "eu-north-1"
}

variable "project_name" {
  description = "Project name used as prefix for resource naming"
  type        = string
  default     = "amnezia-vpn"
}

variable "server_count" {
  description = "Number of VPN servers to deploy (start with 1, increase later)"
  type        = number
  default     = 1

  validation {
    condition     = var.server_count >= 1
    error_message = "At least one server is required."
  }
}

variable "instance_type" {
  description = "EC2 instance type for VPN servers"
  type        = string
  default     = "t3.medium"
}

variable "ami_id" {
  description = "AMI ID for the VPN server (Ubuntu 22.04 LTS). Leave empty to auto-select latest."
  type        = string
  default     = ""
}

variable "ssh_key_name" {
  description = "Name of the EC2 key pair for SSH access"
  type        = string
}

variable "admin_cidr_blocks" {
  description = "CIDR blocks allowed SSH access to VPN servers"
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

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "vpn_subnet" {
  description = "Internal VPN tunnel subnet"
  type        = string
  default     = "10.8.0.0/24"
}

variable "clients_per_server" {
  description = "Number of VPN client configs to generate per server"
  type        = number
  default     = 50
}

variable "ip_rotation_schedule" {
  description = "Cron expression for IP rotation (default: every 24h at 3 AM UTC)"
  type        = string
  default     = "cron(0 3 * * ? *)"
}

variable "config_bucket_name" {
  description = "S3 bucket name for client configs. Leave empty to auto-generate."
  type        = string
  default     = ""
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

variable "dns_servers" {
  description = "DNS servers for VPN clients"
  type        = string
  default     = "1.1.1.1, 1.0.0.1"
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
