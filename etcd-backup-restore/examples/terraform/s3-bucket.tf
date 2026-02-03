# Terraform configuration for etcd backup S3 bucket
# Provider: AWS
# Purpose: Create S3 bucket with proper configuration for etcd backups

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region for backup bucket"
  type        = string
  default     = "us-east-1"
}

variable "bucket_name" {
  description = "Name of the S3 bucket for etcd backups"
  type        = string
  default     = "etcd-backups"
}

variable "environment" {
  description = "Environment name (production, staging, dev)"
  type        = string
  default     = "production"
}

variable "retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 30
}

variable "glacier_transition_days" {
  description = "Number of days before transitioning to Glacier"
  type        = number
  default     = 30
}

# S3 Bucket for etcd backups
resource "aws_s3_bucket" "etcd_backups" {
  bucket = var.bucket_name

  tags = {
    Name        = "etcd-backups"
    Environment = var.environment
    Purpose     = "etcd-backup-storage"
    ManagedBy   = "Terraform"
  }
}

# Enable versioning
resource "aws_s3_bucket_versioning" "etcd_backups" {
  bucket = aws_s3_bucket.etcd_backups.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Enable encryption at rest
resource "aws_s3_bucket_server_side_encryption_configuration" "etcd_backups" {
  bucket = aws_s3_bucket.etcd_backups.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Block public access
resource "aws_s3_bucket_public_access_block" "etcd_backups" {
  bucket = aws_s3_bucket.etcd_backups.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle policy
resource "aws_s3_bucket_lifecycle_configuration" "etcd_backups" {
  bucket = aws_s3_bucket.etcd_backups.id

  rule {
    id     = "etcd-backup-lifecycle"
    status = "Enabled"

    # Transition to Standard-IA after 7 days
    transition {
      days          = 7
      storage_class = "STANDARD_IA"
    }

    # Transition to Glacier after specified days
    transition {
      days          = var.glacier_transition_days
      storage_class = "GLACIER"
    }

    # Delete after retention period
    expiration {
      days = var.retention_days + var.glacier_transition_days
    }

    # Clean up old versions
    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }
}

# Enable logging
resource "aws_s3_bucket_logging" "etcd_backups" {
  bucket = aws_s3_bucket.etcd_backups.id

  target_bucket = aws_s3_bucket.etcd_backups_logs.id
  target_prefix = "access-logs/"
}

# Logging bucket
resource "aws_s3_bucket" "etcd_backups_logs" {
  bucket = "${var.bucket_name}-logs"

  tags = {
    Name        = "etcd-backups-logs"
    Environment = var.environment
    Purpose     = "etcd-backup-access-logs"
    ManagedBy   = "Terraform"
  }
}

# Logging bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "etcd_backups_logs" {
  bucket = aws_s3_bucket.etcd_backups_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Bucket policy for backup service
resource "aws_s3_bucket_policy" "etcd_backups" {
  bucket = aws_s3_bucket.etcd_backups.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowBackupServiceAccess"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.etcd_backup.arn
        }
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.etcd_backups.arn,
          "${aws_s3_bucket.etcd_backups.arn}/*"
        ]
      },
      {
        Sid    = "DenyInsecureTransport"
        Effect = "Deny"
        Principal = "*"
        Action = "s3:*"
        Resource = [
          aws_s3_bucket.etcd_backups.arn,
          "${aws_s3_bucket.etcd_backups.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

# IAM role for backup service (for IRSA - IAM Roles for Service Accounts)
resource "aws_iam_role" "etcd_backup" {
  name = "etcd-backup-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${replace(data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer, "https://", "")}"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:kube-system:etcd-backup"
            "${replace(data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = {
    Name        = "etcd-backup-role"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# IAM policy for backup operations
resource "aws_iam_role_policy" "etcd_backup" {
  name = "etcd-backup-policy"
  role = aws_iam_role.etcd_backup.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          aws_s3_bucket.etcd_backups.arn,
          "${aws_s3_bucket.etcd_backups.arn}/*"
        ]
      }
    ]
  })
}

# Data sources
data "aws_caller_identity" "current" {}

data "aws_eks_cluster" "cluster" {
  name = var.eks_cluster_name
}

variable "eks_cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

# Outputs
output "bucket_name" {
  description = "Name of the S3 bucket"
  value       = aws_s3_bucket.etcd_backups.id
}

output "bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = aws_s3_bucket.etcd_backups.arn
}

output "iam_role_arn" {
  description = "ARN of the IAM role for backup service"
  value       = aws_iam_role.etcd_backup.arn
}

output "bucket_region" {
  description = "Region of the S3 bucket"
  value       = aws_s3_bucket.etcd_backups.region
}
