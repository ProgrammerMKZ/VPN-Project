output "server_ids" {
  description = "Hetzner server IDs"
  value       = hcloud_server.vpn[*].id
}

output "server_ipv4" {
  description = "Public IPv4 addresses of VPN servers"
  value       = hcloud_server.vpn[*].ipv4_address
}

output "server_ipv6" {
  description = "Public IPv6 addresses of VPN servers"
  value       = hcloud_server.vpn[*].ipv6_address
}

output "server_names" {
  description = "Hetzner server names"
  value       = hcloud_server.vpn[*].name
}

output "ssh_commands" {
  description = "Ready-to-paste SSH commands for each server"
  value = [
    for srv in hcloud_server.vpn :
    "ssh root@${srv.ipv4_address}"
  ]
}

output "monthly_cost_estimate_eur" {
  description = "Approximate monthly cost in EUR (server only, excludes traffic overage)"
  value = {
    per_server     = var.server_type
    server_count   = var.server_count
    note           = "See https://www.hetzner.com/cloud for exact pricing. 20 TB/mo traffic included per server."
  }
}
