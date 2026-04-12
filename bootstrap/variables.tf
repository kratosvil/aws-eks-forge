variable "aws_region" {
  description = "AWS region where the backend resources will be created"
  type        = string
  default     = "us-east-1"
}

variable "state_bucket_name" {
  description = "Globally unique name for the S3 bucket that stores Terraform state"
  type        = string
}

variable "dynamodb_table_name" {
  description = "Name of the DynamoDB table used for Terraform state locking"
  type        = string
  default     = "terraform-locks"
}

variable "project" {
  description = "Project tag applied to all resources"
  type        = string
  default     = "aws-eks-forge"
}
