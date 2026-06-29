# infra/terraform/main.tf
terraform {
  required_version = ">= 1.5"

  backend "s3" {
    bucket         = "phoenix-capstone-tfstate-eniiyi"
    key            = "phoenix/terraform.tfstate"
    region         = "us-east-1"
    use_lockfile   = true
    encrypt        = true
  }

  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region = var.aws_region
}

module "network" {
  source             = "./modules/network"
  availability_zone  = "${var.aws_region}a"   
}

module "security" {
  source = "./modules/security"
  vpc_id = module.network.vpc_id
  my_ip  = var.my_ip
}
