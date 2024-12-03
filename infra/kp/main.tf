# Configure AWS Provider
provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "The AWS region"
  type        = string
  default     = "ap-southeast-1"
}


variable "key_pair_name" {
  description = "Key Pair name"
  type        = string
  default     = "awskp"
}

# Generate RSA key pair
resource "tls_private_key" "key_pair" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Create AWS key pair
resource "aws_key_pair" "key_pair" {
  key_name   = var.key_pair_name
  public_key = tls_private_key.key_pair.public_key_openssh
}

# Output the private key to a file (Note: Store this securely!)
resource "local_file" "private_key" {
  content  = tls_private_key.key_pair.private_key_pem
  filename = "${var.key_pair_name}.pem"

  # Set file permissions to be restricted
  file_permission = "0600"
}

# Outputs
output "key_pair_name" {
  description = "Name of the key pair"
  value       = aws_key_pair.key_pair.key_name
}

output "private_key_path" {
  description = "Path to the private key file"
  value       = local_file.private_key.filename
}
