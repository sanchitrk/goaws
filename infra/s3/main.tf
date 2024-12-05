
# Starts with the provider
# resources are specific to the provider
# they are not common across the cloud provider in exact sense
provider "aws" {
  region = var.aws_region
}

# Region where we want to deploy the services
variable "aws_region" {
  description = "The AWS region"
  type        = string
  default     = "ap-southeast-1"
}

# The stack environment e.g: dev, staging, prod, etc.
variable "stack_env" {
  description = "The stack environment"
  type        = string
  default     = "staging"
}

# The deployment stack
variable "stack_name" {
  description = "The service stack name"
  type        = string
  default     = "srv"
}

data "aws_caller_identity" "current" {}


# S3 Bucket for artifacts
# Required for storing build artificats must exist or could be created outside
resource "aws_s3_bucket" "artifacts" {
  bucket = "${var.stack_name}-${var.stack_env}-${var.aws_region}-artifacts-${data.aws_caller_identity.current.account_id}"

  force_destroy = true # Enable if you want to delete the bucket even if it contains objects

  tags = {
    Name        = "${var.stack_name}-artifacts-bucket"
    Environment = var.stack_env
    ManagedBy   = "terraform"
  }
}

# Bucket versioning
resource "aws_s3_bucket_versioning" "artifacts_versioning" {
  bucket = aws_s3_bucket.artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}


# Server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts_bucket_encryption" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "artifacts_lifecycle" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    id     = "cleanup-old-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}


# Block public access
# Dont want to make the S3 public with all the built source codes yakes!
resource "aws_s3_bucket_public_access_block" "artifacts_bucket_public_access_block" {
  bucket = aws_s3_bucket.artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Output the bucket name
output "artifacts_bucket_name" {
  value = aws_s3_bucket.artifacts.id
}

# Output the bucket ARN
output "artifacts_bucket_arn" {
  value = aws_s3_bucket.artifacts.arn
}
