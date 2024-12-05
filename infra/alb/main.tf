
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


# The instance SSH key pair, not mandatory but having it anyway
# Ideally instance should be immutable, ssh discourages it!
variable "key_pair_name" {
  description = "The Key Pair name"
  type        = string
  default     = "awskp"
}

# The current AWS identity, pulled from aws config or environment
data "aws_caller_identity" "current" {}


data "aws_s3_bucket" "artifacts" {
  bucket = "${var.stack_name}-${var.stack_env}-${var.aws_region}-artifacts-${data.aws_caller_identity.current.account_id}"
}

# AWS IAM role for code deployment for the stack
resource "aws_iam_role" "codedeploy_role" {
  name = "${var.stack_name}-codedeploy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "codedeploy.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Environment = "${var.stack_env}"
    ManagedBy   = "terraform"
  }
}

# Now that we have policy created - attach to specific role
resource "aws_iam_role_policy_attachment" "codedeploy_policy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole"
  role       = aws_iam_role.codedeploy_role.name
}

# AWS CodeDeploy Application
# This creates a CodeDeploy application which is a name that uniquely identifies the application you want to deploy
# The application name is used to group deployments and deployment configurations
resource "aws_codedeploy_app" "app" {
  name = "${var.stack_name}-${var.stack_env}"
}

# AWS CodeDeploy Deployment Group
# A deployment group is a set of individual instances targeted for deployment
# It defines the deployment strategy and configuration for how the application will be deployed
resource "aws_codedeploy_deployment_group" "app" {
  app_name              = aws_codedeploy_app.app.name
  deployment_group_name = "${var.stack_name}-${var.stack_env}-deployment-group"
  service_role_arn      = aws_iam_role.codedeploy_role.arn

  # Deployment style configuration
  # - WITHOUT_TRAFFIC_CONTROL: No load balancer is used
  # - IN_PLACE: Updates existing instances instead of blue/green deployment
  deployment_style {
    deployment_option = "WITH_TRAFFIC_CONTROL"
    deployment_type   = "IN_PLACE"
  }


  load_balancer_info {
    target_group_info {
      name = aws_lb_target_group.app.name
    }
  }

  ec2_tag_set {
    ec2_tag_filter {
      key   = "Environment"
      type  = "KEY_AND_VALUE"
      value = var.stack_env
    }

    ec2_tag_filter {
      key   = "Application"
      type  = "KEY_AND_VALUE"
      value = aws_codedeploy_app.app.name
    }
  }
}


variable "server_port" {
  description = "The port the server will use for HTTP requests"
  type        = number
  default     = 8080
}


data "aws_vpc" "default" {
  default = true
}


data "aws_subnets" "defaults" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_security_group" "alb" {
  name = "${var.stack_name}-${var.stack_env}-alb-sg"


  lifecycle {
    create_before_destroy = true
  }



  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTP access"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Environment = "${var.stack_env}"
    ManagedBy   = "terraform"
  }
}


resource "aws_security_group" "ec2" {
  name = "${var.stack_name}-${var.stack_env}-ec2-sg"

  lifecycle {
    create_before_destroy = true
  }


  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTP access"
  }

  # Allow application access
  ingress {
    from_port   = var.server_port
    to_port     = var.server_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow application access"
  }

  # Allow SSH access for management
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow SSH access"
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Environment = "${var.stack_env}"
    ManagedBy   = "terraform"
  }
}

resource "aws_iam_role" "ec2_role" {
  name = "${var.stack_name}-${var.stack_env}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Environment = var.stack_env
    ManagedBy   = "terraform"
  }
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.stack_name}-${var.stack_env}-ec2-profile"
  role = aws_iam_role.ec2_role.name

  tags = {
    Environment = var.stack_env
    ManagedBy   = "terraform"
  }
}


# Application Load Balancer
resource "aws_lb" "app" {
  name               = "${var.stack_name}-${var.stack_env}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = data.aws_subnets.defaults.ids

  tags = {
    Environment = var.stack_env
    ManagedBy   = "terraform"
  }
}

# Target Group
resource "aws_lb_target_group" "app" {
  name     = "${var.stack_name}-${var.stack_env}-tg"
  port     = var.server_port
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/"
    port                = "traffic-port"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = {
    Environment = var.stack_env
    ManagedBy   = "terraform"
  }
}

# Listener
resource "aws_lb_listener" "app" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}


resource "aws_instance" "app1" {
  ami                    = "ami-047126e50991d067b"
  instance_type          = "t2.micro"
  subnet_id              = tolist(data.aws_subnets.defaults.ids)[0]
  vpc_security_group_ids = [aws_security_group.ec2.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name
  key_name               = var.key_pair_name

  tags = {
    Name        = "${var.stack_name}-${var.stack_env}-instance-1"
    Environment = var.stack_env
    Application = aws_codedeploy_app.app.name
  }

  # User data script to install CodeDeploy agent
  user_data = <<-EOF
              #!/bin/bash
              # Update system packages
              sudo apt-get update
              sudo apt-get install -y ruby-full wget

              # Install CodeDeploy agent
              cd /home/ubuntu
              wget https://aws-codedeploy-${var.aws_region}.s3.${var.aws_region}.amazonaws.com/latest/install
              chmod +x ./install
              sudo ./install auto
              sudo service codedeploy-agent start
              EOF
}


resource "aws_instance" "app2" {
  ami                    = "ami-047126e50991d067b"
  instance_type          = "t2.micro"
  subnet_id              = tolist(data.aws_subnets.defaults.ids)[1]
  vpc_security_group_ids = [aws_security_group.ec2.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name
  key_name               = var.key_pair_name



  tags = {
    Name        = "${var.stack_name}-${var.stack_env}-instance-2"
    Environment = var.stack_env
    Application = aws_codedeploy_app.app.name
  }

  user_data = <<-EOF
              #!/bin/bash
              # Update system packages
              sudo apt-get update
              sudo apt-get install -y ruby-full wget

              # Install CodeDeploy agent
              cd /home/ubuntu
              wget https://aws-codedeploy-${var.aws_region}.s3.${var.aws_region}.amazonaws.com/latest/install
              chmod +x ./install
              sudo ./install auto
              sudo service codedeploy-agent start
              EOF
}

# Target Group Attachments
resource "aws_lb_target_group_attachment" "app1" {
  target_group_arn = aws_lb_target_group.app.arn
  target_id        = aws_instance.app1.id
  port             = var.server_port
}

resource "aws_lb_target_group_attachment" "app2" {
  target_group_arn = aws_lb_target_group.app.arn
  target_id        = aws_instance.app2.id
  port             = var.server_port
}

resource "aws_iam_role_policy" "ec2_s3_policy" {
  name = "${var.stack_name}-${var.stack_env}-ec2-s3-policy"
  role = aws_iam_role.ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:ListBucket"
        ]
        Resource = [
          data.aws_s3_bucket.artifacts.arn,
          "${data.aws_s3_bucket.artifacts.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_codedeploy_policy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole"
  role       = aws_iam_role.ec2_role.name
}

resource "aws_iam_role_policy_attachment" "ec2_ssm_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.ec2_role.name
}


variable "github_repo" {
  description = "GitHub repository name (e.g., username/repo)"
  type        = string
  default     = "sanchitrk/goaws" # Update this with your repository
}

variable "github_thumbprint_list" {
  description = "A thumbprint of an Open ID Connector is a SHA1 hash of the public certificate of the host"
  type        = list(string)
  default     = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}


# OIDC Provider for GitHub Actions
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = var.github_thumbprint_list
}

# IAM Role for GitHub Actions
resource "aws_iam_role" "github_actions" {
  name        = "code-deploy-role-github"
  path        = "/"
  description = "Github Actions role"

  # Trust relationship policy
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRoleWithWebIdentity"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github.arn
      }
      Condition = {
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:*"
        }
      }
    }]
  })

  max_session_duration = 3600

  tags = {
    ManagedBy = "terraform"
  }
}

# IAM Policy for the GitHub Actions Role
resource "aws_iam_role_policy" "github_actions_policy" {
  name = "code-deploy-role-github-policy"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "codedeploy:Get*",
          "codedeploy:Batch*",
          "codedeploy:CreateDeployment",
          "codedeploy:RegisterApplicationRevision",
          "codedeploy:List*"
        ]
        Resource = "arn:aws:codedeploy:*:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject"
        ]
        Resource = "${data.aws_s3_bucket.artifacts.arn}/*"
      }
    ]
  })
}

# Outputs
output "github_actions_role_arn" {
  description = "ARN of the GitHub Actions IAM role"
  value       = aws_iam_role.github_actions.arn
}

output "github_actions_role_name" {
  description = "Name of the GitHub Actions IAM role"
  value       = aws_iam_role.github_actions.name
}

# Output the bucket name
output "artifacts_bucket_name" {
  value = data.aws_s3_bucket.artifacts.id
}

# Output the bucket ARN
output "artifacts_bucket_arn" {
  value = data.aws_s3_bucket.artifacts.arn
}

output "codedeploy_app_name" {
  description = "The name of the CodeDeploy application. Use this identifier when referencing the application in AWS CLI commands or other AWS services."
  value       = aws_codedeploy_app.app.name
}

output "codedeploy_app_id" {
  description = "The unique ID of the CodeDeploy application. This ID is used internally by AWS to uniquely identify the application resource."
  value       = aws_codedeploy_app.app.id
}

output "codedeploy_deployment_group_name" {
  description = "The name of the deployment group. Use this when creating deployments or updating deployment group configurations through AWS CLI or API."
  value       = aws_codedeploy_deployment_group.app.deployment_group_name
}

output "codedeploy_deployment_group_id" {
  description = "The unique ID of the deployment group. This ID is used internally by AWS and can be used to track specific deployment group resources."
  value       = aws_codedeploy_deployment_group.app.id
}

output "alb_dns_name" {
  description = "The DNS name of the load balancer"
  value       = aws_lb.app.dns_name
}

output "instance1_public_dns" {
  description = "The public DNS of the first EC2 instance"
  value       = aws_instance.app1.public_dns
}

output "instance2_public_dns" {
  description = "The public DNS of the second EC2 instance"
  value       = aws_instance.app2.public_dns
}
