output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "server_instance_ids" {
  description = "EC2 instance IDs of VPN servers"
  value       = aws_instance.vpn[*].id
}

output "server_public_ips" {
  description = "Elastic IP addresses assigned to VPN servers"
  value       = aws_eip.vpn[*].public_ip
}

output "server_eip_allocation_ids" {
  description = "Allocation IDs of Elastic IPs (needed for IP rotation)"
  value       = aws_eip.vpn[*].allocation_id
}

output "config_bucket_name" {
  description = "S3 bucket name for client configurations"
  value       = aws_s3_bucket.configs.id
}

output "config_bucket_arn" {
  description = "S3 bucket ARN for client configurations"
  value       = aws_s3_bucket.configs.arn
}

output "lambda_function_name" {
  description = "Name of the IP rotation Lambda function"
  value       = aws_lambda_function.ip_rotation.function_name
}

output "lambda_function_arn" {
  description = "ARN of the IP rotation Lambda function"
  value       = aws_lambda_function.ip_rotation.arn
}

output "security_group_id" {
  description = "Security group ID for VPN servers"
  value       = aws_security_group.vpn.id
}

output "ssm_parameter_prefix" {
  description = "SSM Parameter Store prefix for this deployment"
  value       = "/${var.project_name}"
}

output "aws_account_id" {
  description = "AWS account ID used for this deployment"
  value       = local.account_id
}
