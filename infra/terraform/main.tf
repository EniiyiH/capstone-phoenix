# infra/terraform/main.tf
terraform {
  required_version = ">= 1.5"

  backend "s3" {
    bucket         = "phoenix-capstone-tfstate-eniiyi"
    key            = "phoenix/terraform.tfstate"
    region         = "us-east-1"
    use_lockfile = "true"
    encrypt        = true
  }

  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region = var.aws_region
}
