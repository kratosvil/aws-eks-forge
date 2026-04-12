terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # No backend block — bootstrap uses local state intentionally.
  # This module creates the remote backend used by all other modules.
}

provider "aws" {
  region = var.aws_region
}
