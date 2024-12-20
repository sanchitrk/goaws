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



# S3 Bucket for CodePipeline artifacts
# Required for storing build artificats must exist or could be created outside
resource "aws_s3_bucket" "artifacts" {
  bucket = "${var.stack_name}-${var.stack_env}-${var.aws_region}-codepipeline-${data.aws_caller_identity.current.account_id}"

  force_destroy = true # Enable if you want to delete the bucket even if it contains objects

  tags = {
    Name        = "${var.stack_name}-codepipeline-bucket"
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
resource "aws_s3_bucket_server_side_encryption_configuration" "codepipeline_bucket_encryption" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block public access
# Dont want to make the S3 public with all the built source codes yakes!
resource "aws_s3_bucket_public_access_block" "codepipeline_bucket_public_access_block" {
  bucket = aws_s3_bucket.artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Output the bucket name
output "codepipeline_bucket_name" {
  value = aws_s3_bucket.artifacts.id
}

output "codepipeline_bucket_arn" {
  value = aws_s3_bucket.artifacts.arn
}


variable "github_repo" {
  description = "GitHub repository name (e.g., username/repo)"
  type        = string
  default     = "sanchitrk/goaws" # Update this with your repository
}

variable "github_branch" {
  description = "GitHub branch to track"
  type        = string
  default     = "main"
}

variable "github_token" {
  description = "GitHub personal access token"
  type        = string
  sensitive   = true
}

resource "aws_iam_role" "codebuild_role" {
  name = "${var.stack_name}-codebuild-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "codebuild.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Environment = "${var.stack_env}"
    ManagedBy   = "terraform"
  }
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


# AWS IAM role for code pipeline for this stack.
resource "aws_iam_role" "codepipeline_role" {
  name = "${var.stack_name}-codepipeline-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "codepipeline.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Environment = "${var.stack_env}"
    ManagedBy   = "terraform"
  }
}

# AWS IAM role for codebuild for the stack
resource "aws_iam_role_policy" "codebuild_policy" {
  name = "${var.stack_name}-codebuild-policy"
  role = aws_iam_role.codebuild_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject"
        ]
        Resource = [
          aws_s3_bucket.artifacts.arn,
          "${aws_s3_bucket.artifacts.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

# Now that we have policy created - attach to specific roles
resource "aws_iam_role_policy_attachment" "codedeploy_policy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole"
  role       = aws_iam_role.codedeploy_role.name
}


resource "aws_iam_role_policy" "codepipeline_policy" {
  name = "${var.stack_name}-codepipeline-policy"
  role = aws_iam_role.codepipeline_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:GetBucketVersioning",
          "s3:PutObject"
        ]
        Resource = [
          aws_s3_bucket.artifacts.arn,
          "${aws_s3_bucket.artifacts.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "codestar-connections:UseConnection"
        ]
        Resource = [aws_codestarconnections_connection.github.arn]
      },
      {
        Effect = "Allow"
        Action = [
          "codebuild:BatchGetBuilds",
          "codebuild:StartBuild"
        ]
        Resource = [aws_codebuild_project.app.arn]
      },
      {
        Effect = "Allow"
        Action = [
          "codedeploy:CreateDeployment",
          "codedeploy:GetDeployment",
          "codedeploy:GetApplication",
          "codedeploy:GetApplicationRevision",
          "codedeploy:RegisterApplicationRevision",
          "codedeploy:GetDeploymentConfig",
          "codedeploy:GetDeploymentGroup"
        ]
        Resource = "*"
      }
    ]
  })
}

# AWS codebuild project specifies build configuration
resource "aws_codebuild_project" "app" {
  name         = "${var.stack_name}-${var.stack_env}-build"
  description  = "Build project for ${var.stack_name} ${var.stack_env} application"
  service_role = aws_iam_role.codebuild_role.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:7.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"

    environment_variable {
      name  = "GH_TOKEN"
      value = var.github_token
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspec.yml"
  }
}

resource "aws_codedeploy_app" "app" {
  name = "${var.stack_name}-${var.stack_env}"
}

resource "aws_codedeploy_deployment_group" "app" {
  app_name              = aws_codedeploy_app.app.name
  deployment_group_name = "${var.stack_name}-${var.stack_env}-deployment-group"
  service_role_arn      = aws_iam_role.codedeploy_role.arn

  deployment_style {
    deployment_option = "WITHOUT_TRAFFIC_CONTROL"
    deployment_type   = "IN_PLACE"
  }

  ec2_tag_set {
    ec2_tag_filter {
      key   = "Name"
      type  = "KEY_AND_VALUE"
      value = "${var.stack_name}-${var.stack_env}-instance"
    }
  }
}

resource "aws_codepipeline" "pipeline" {
  name     = "${var.stack_name}-${var.stack_env}-pipeline"
  role_arn = aws_iam_role.codepipeline_role.arn

  artifact_store {
    location = aws_s3_bucket.artifacts.id
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        ConnectionArn    = aws_codestarconnections_connection.github.arn
        FullRepositoryId = var.github_repo
        BranchName       = var.github_branch
      }
    }
  }

  stage {
    name = "Build"

    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["source_output"]
      version          = "1"
      output_artifacts = ["build_output"]

      configuration = {
        ProjectName = aws_codebuild_project.app.name
      }
    }
  }

  stage {
    name = "Deploy"

    action {
      name            = "Deploy"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "CodeDeploy"
      input_artifacts = ["build_output"]
      version         = "1"

      configuration = {
        ApplicationName     = aws_codedeploy_app.app.name
        DeploymentGroupName = aws_codedeploy_deployment_group.app.deployment_group_name
      }
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


resource "aws_security_group" "ec2" {
  name = "${var.stack_name}-${var.stack_env}-sg"

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

resource "aws_iam_role_policy_attachment" "ec2_policy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole"
  role       = aws_iam_role.ec2_role.name
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.stack_name}-${var.stack_env}-ec2-profile"
  role = aws_iam_role.ec2_role.name

  tags = {
    Environment = var.stack_env
    ManagedBy   = "terraform"
  }
}

resource "aws_instance" "app" {
  ami                    = "ami-047126e50991d067b"
  instance_type          = "t2.micro"
  subnet_id              = tolist(data.aws_subnets.defaults.ids)[0]
  vpc_security_group_ids = [aws_security_group.ec2.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name
  key_name               = var.key_pair_name

  tags = {
    Name = "${var.stack_name}-${var.stack_env}-instance"
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
          aws_s3_bucket.artifacts.arn,
          "${aws_s3_bucket.artifacts.arn}/*"
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

# AWS codestar connection - might have to authenticate in console for permissions.
resource "aws_codestarconnections_connection" "github" {
  name          = "${var.github_repo}-${var.github_branch}"
  provider_type = "GitHub"
}

resource "aws_codepipeline_webhook" "github_webhook" {
  name            = "${var.stack_name}-${var.stack_env}-webhook"
  authentication  = "GITHUB_HMAC"

  target_action   = "Source"
  target_pipeline = aws_codepipeline.pipeline.name

  authentication_configuration {
    secret_token = var.github_token
  }

  filter {
    json_path    = "$.ref"
    match_equals = "refs/heads/{Branch}"
  }

  tags = {
    Environment = var.stack_env
    ManagedBy   = "terraform"
  }
}

resource "github_repository_webhook" "github_webhook" {
  repository = split("/", var.github_repo)[1]
  
  configuration {
    url          = aws_codepipeline_webhook.github_webhook.url
    content_type = "json"
    insecure_ssl = false
    secret       = var.github_token

  }

  events = ["push"]
}


terraform {
  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
  }
}


provider "github" {
  token = var.github_token
  owner = split("/", var.github_repo)[0]
}

