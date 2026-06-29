
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "availability_zone" {
  description = "AZ for the subnet"
  type        = string
}

variable "project_name" {
  description = "Used for resource naming/tags"
  type        = string
  default     = "phoenix-capstone"
}
