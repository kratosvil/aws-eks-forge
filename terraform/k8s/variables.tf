variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project tag applied to all resources"
  type        = string
  default     = "aws-eks-forge"
}

variable "image_tag_blue" {
  description = "Image tag deployed to blue slot"
  type        = string
  default     = "v1"
}

variable "image_tag_green" {
  description = "Image tag deployed to green slot"
  type        = string
  default     = "v1"
}

variable "blue_weight" {
  description = "Traffic weight for blue deployment (0-100)"
  type        = number
  default     = 100
}

variable "green_weight" {
  description = "Traffic weight for green deployment (0-100)"
  type        = number
  default     = 0
}

variable "blue_replicas" {
  description = "Number of replicas for blue slot (active)"
  type        = number
  default     = 2
}

variable "green_replicas" {
  description = "Number of replicas for green slot (0 = standby, scale up before switch)"
  type        = number
  default     = 0
}
