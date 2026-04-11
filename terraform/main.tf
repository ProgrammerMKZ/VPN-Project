terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }

  backend "s3" {}
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = merge(var.tags, {
      Project   = var.project_name
      ManagedBy = "terraform"
    })
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id  = data.aws_caller_identity.current.account_id
  region      = data.aws_region.current.name
  name_prefix = var.project_name

  config_bucket = var.config_bucket_name != "" ? var.config_bucket_name : "${local.name_prefix}-configs-${local.account_id}"

  common_tags = {
    Service = "amnezia-vpn"
  }
}

# ---------- AMI Lookup (Ubuntu 22.04 LTS) ----------

data "aws_ami" "ubuntu" {
  count       = var.ami_id == "" ? 1 : 0
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  resolved_ami = var.ami_id != "" ? var.ami_id : data.aws_ami.ubuntu[0].id
}

# ============================================================
#  NETWORKING
# ============================================================

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${local.name_prefix}-vpc" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${local.name_prefix}-igw" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.subnet_cidr
  map_public_ip_on_launch = false

  tags = { Name = "${local.name_prefix}-public" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${local.name_prefix}-public-rt" }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# ============================================================
#  SECURITY GROUP
# ============================================================

resource "aws_security_group" "vpn" {
  name_prefix = "${local.name_prefix}-vpn-"
  description = "AmneziaWG VPN server security group"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${local.name_prefix}-vpn-sg" }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "vpn_udp" {
  security_group_id = aws_security_group.vpn.id
  description       = "AmneziaWG VPN traffic"
  from_port         = var.vpn_port
  to_port           = var.vpn_port
  ip_protocol       = "udp"
  cidr_ipv4         = "0.0.0.0/0"

  tags = { Name = "vpn-udp" }
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  for_each = toset(var.admin_cidr_blocks)

  security_group_id = aws_security_group.vpn.id
  description       = "SSH from admin CIDR"
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  cidr_ipv4         = each.value

  tags = { Name = "ssh-admin" }
}

resource "aws_vpc_security_group_egress_rule" "all_out" {
  security_group_id = aws_security_group.vpn.id
  description       = "Allow all outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"

  tags = { Name = "all-outbound" }
}

# ============================================================
#  EC2 INSTANCES (scalable via server_count)
# ============================================================

resource "aws_instance" "vpn" {
  count = var.server_count

  ami                    = local.resolved_ami
  instance_type          = var.instance_type
  key_name               = var.ssh_key_name
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.vpn.id]
  iam_instance_profile   = aws_iam_instance_profile.vpn_server.name

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    http_endpoint               = "enabled"
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 20
    encrypted             = true
    delete_on_termination = true
  }

  user_data = base64encode(templatefile("${path.module}/userdata.sh", {
    server_index  = count.index
    vpn_port      = var.vpn_port
    vpn_subnet    = var.vpn_subnet
    aws_region    = var.aws_region
    project_name  = var.project_name
    awg_jc        = var.awg_jc
    awg_jmin      = var.awg_jmin
    awg_jmax      = var.awg_jmax
    awg_s1        = var.awg_s1
    awg_s2        = var.awg_s2
    awg_h1        = var.awg_h1
    awg_h2        = var.awg_h2
    awg_h3        = var.awg_h3
    awg_h4        = var.awg_h4
  }))

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-server-${count.index}"
    ServerIndex = tostring(count.index)
  })

  lifecycle {
    ignore_changes = [ami, user_data]
  }
}

# ============================================================
#  ELASTIC IPs (one per server, scalable)
# ============================================================

resource "aws_eip" "vpn" {
  count  = var.server_count
  domain = "vpc"

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-eip-${count.index}"
    ServerIndex = tostring(count.index)
  })
}

resource "aws_eip_association" "vpn" {
  count         = var.server_count
  instance_id   = aws_instance.vpn[count.index].id
  allocation_id = aws_eip.vpn[count.index].id
}

# ============================================================
#  IAM — EC2 Instance Profile
# ============================================================

resource "aws_iam_role" "vpn_server" {
  name = "${local.name_prefix}-server-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_instance_profile" "vpn_server" {
  name = "${local.name_prefix}-server-profile"
  role = aws_iam_role.vpn_server.name
}

resource "aws_iam_role_policy" "vpn_server_ssm" {
  name = "${local.name_prefix}-server-ssm"
  role = aws_iam_role.vpn_server.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SSMParameterAccess"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:PutParameter"
        ]
        Resource = "arn:aws:ssm:${local.region}:${local.account_id}:parameter/${var.project_name}/*"
      }
    ]
  })
}

# ============================================================
#  S3 — Client Config Bucket
# ============================================================

resource "aws_s3_bucket" "configs" {
  bucket        = local.config_bucket
  force_destroy = false

  tags = { Name = "${local.name_prefix}-configs" }
}

resource "aws_s3_bucket_versioning" "configs" {
  bucket = aws_s3_bucket.configs.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "configs" {
  bucket = aws_s3_bucket.configs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "configs" {
  bucket = aws_s3_bucket.configs.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

resource "aws_s3_bucket_public_access_block" "configs" {
  bucket = aws_s3_bucket.configs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ============================================================
#  SSM Parameters — Obfuscation Config
# ============================================================

resource "aws_ssm_parameter" "awg_obfuscation" {
  name  = "/${var.project_name}/awg/obfuscation"
  type  = "String"
  value = jsonencode({
    Jc   = var.awg_jc
    Jmin = var.awg_jmin
    Jmax = var.awg_jmax
    S1   = var.awg_s1
    S2   = var.awg_s2
    H1   = var.awg_h1
    H2   = var.awg_h2
    H3   = var.awg_h3
    H4   = var.awg_h4
  })

  tags = { Name = "${local.name_prefix}-obfuscation-params" }
}

# ============================================================
#  LAMBDA — IP Rotation
# ============================================================

data "archive_file" "ip_rotation" {
  type        = "zip"
  source_file = "${path.module}/../lambda/ip_rotation.py"
  output_path = "${path.module}/../lambda/ip_rotation.zip"
}

resource "aws_lambda_function" "ip_rotation" {
  function_name    = "${local.name_prefix}-ip-rotation"
  filename         = data.archive_file.ip_rotation.output_path
  source_code_hash = data.archive_file.ip_rotation.output_base64sha256
  handler          = "ip_rotation.lambda_handler"
  runtime          = "python3.12"
  timeout          = 300
  memory_size      = 256

  role = aws_iam_role.lambda_ip_rotation.arn

  reserved_concurrent_executions = 1

  environment {
    variables = {
      PROJECT_NAME = var.project_name
      SERVER_COUNT = tostring(var.server_count)
      CONFIG_BUCKET   = aws_s3_bucket.configs.id
      VPN_PORT        = tostring(var.vpn_port)
      VPN_SUBNET      = var.vpn_subnet
      DNS_SERVERS     = var.dns_servers
      AWG_JC          = tostring(var.awg_jc)
      AWG_JMIN        = tostring(var.awg_jmin)
      AWG_JMAX        = tostring(var.awg_jmax)
      AWG_S1          = tostring(var.awg_s1)
      AWG_S2          = tostring(var.awg_s2)
      AWG_H1          = tostring(var.awg_h1)
      AWG_H2          = tostring(var.awg_h2)
      AWG_H3          = tostring(var.awg_h3)
      AWG_H4          = tostring(var.awg_h4)
    }
  }

  tags = { Name = "${local.name_prefix}-ip-rotation" }
}

# ============================================================
#  IAM — Lambda Execution Role
# ============================================================

resource "aws_iam_role" "lambda_ip_rotation" {
  name = "${local.name_prefix}-lambda-ip-rotation"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_cloudwatch_log_group" "lambda_ip_rotation" {
  name              = "/aws/lambda/${local.name_prefix}-ip-rotation"
  retention_in_days = 14
}

resource "aws_iam_role_policy" "lambda_logs" {
  name = "${local.name_prefix}-lambda-logs"
  role = aws_iam_role.lambda_ip_rotation.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "CloudWatchLogs"
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Resource = "${aws_cloudwatch_log_group.lambda_ip_rotation.arn}:*"
    }]
  })
}

resource "aws_iam_role_policy" "lambda_ec2" {
  name = "${local.name_prefix}-lambda-ec2"
  role = aws_iam_role.lambda_ip_rotation.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EIPReadOnly"
        Effect = "Allow"
        Action = [
          "ec2:DescribeAddresses",
          "ec2:DescribeInstances"
        ]
        Resource = "*"
      },
      {
        Sid    = "EIPMutateTagged"
        Effect = "Allow"
        Action = [
          "ec2:ReleaseAddress",
          "ec2:AssociateAddress",
          "ec2:DisassociateAddress"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/Service" = "amnezia-vpn"
          }
        }
      },
      {
        Sid    = "EIPAllocateWithTag"
        Effect = "Allow"
        Action = "ec2:AllocateAddress"
        Resource = "arn:aws:ec2:${local.region}:${local.account_id}:elastic-ip/*"
        Condition = {
          StringEquals = {
            "aws:RequestTag/Service" = "amnezia-vpn"
          }
        }
      },
      {
        Sid    = "EIPCreateTagsOnAllocate"
        Effect = "Allow"
        Action = "ec2:CreateTags"
        Resource = "arn:aws:ec2:${local.region}:${local.account_id}:elastic-ip/*"
        Condition = {
          StringEquals = {
            "ec2:CreateAction" = "AllocateAddress"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_ssm" {
  name = "${local.name_prefix}-lambda-ssm"
  role = aws_iam_role.lambda_ip_rotation.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "SSMAccess"
      Effect = "Allow"
      Action = [
        "ssm:GetParameter",
        "ssm:GetParameters",
        "ssm:PutParameter"
      ]
      Resource = "arn:aws:ssm:${local.region}:${local.account_id}:parameter/${var.project_name}/*"
    }]
  })
}

resource "aws_iam_role_policy" "lambda_s3" {
  name = "${local.name_prefix}-lambda-s3"
  role = aws_iam_role.lambda_ip_rotation.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3ListBucket"
        Effect = "Allow"
        Action = ["s3:ListBucket"]
        Resource = aws_s3_bucket.configs.arn
      },
      {
        Sid    = "S3ReadWriteObjects"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = "${aws_s3_bucket.configs.arn}/*"
      }
    ]
  })
}

# ============================================================
#  EventBridge — Scheduled IP Rotation
# ============================================================

resource "aws_scheduler_schedule" "ip_rotation" {
  name       = "${local.name_prefix}-ip-rotation"
  group_name = "default"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression = var.ip_rotation_schedule

  target {
    arn      = aws_lambda_function.ip_rotation.arn
    role_arn = aws_iam_role.scheduler_ip_rotation.arn

    input = jsonencode({
      action = "rotate"
    })
  }
}

resource "aws_iam_role" "scheduler_ip_rotation" {
  name = "${local.name_prefix}-scheduler-ip-rotation"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "scheduler.amazonaws.com"
      }
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = local.account_id
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "scheduler_invoke_lambda" {
  name = "${local.name_prefix}-scheduler-invoke"
  role = aws_iam_role.scheduler_ip_rotation.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "lambda:InvokeFunction"
      Resource = aws_lambda_function.ip_rotation.arn
    }]
  })
}
