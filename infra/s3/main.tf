# Provider and data source configuration
provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

# Variables
variable "stack_name" {
  type        = string
  description = "Name of the stack"
}

variable "stack_env" {
  type        = string
  description = "Environment (e.g., dev, prod, staging)"
}

variable "aws_region" {
  type        = string
  description = "AWS region where resources will be created"
}

# S3 Bucket for CodePipeline artifacts
resource "aws_s3_bucket" "codepipeline_bucket" {
  bucket = "${var.stack_name}-${var.stack_env}-${var.aws_region}-codepipeline-${data.aws_caller_identity.current.account_id}"

  force_destroy = true # Enable if you want to delete the bucket even if it contains objects

  tags = {
    Name        = "${var.stack_name}-codepipeline-bucket"
    Environment = var.stack_env
    ManagedBy   = "terraform"
  }
}

# Bucket versioning
resource "aws_s3_bucket_versioning" "codepipeline_bucket_versioning" {
  bucket = aws_s3_bucket.codepipeline_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "codepipeline_bucket_encryption" {
  bucket = aws_s3_bucket.codepipeline_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block public access
resource "aws_s3_bucket_public_access_block" "codepipeline_bucket_public_access_block" {
  bucket = aws_s3_bucket.codepipeline_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Output the bucket name
output "codepipeline_bucket_name" {
  value = aws_s3_bucket.codepipeline_bucket.id
}

output "codepipeline_bucket_arn" {
  value = aws_s3_bucket.codepipeline_bucket.arn
}
