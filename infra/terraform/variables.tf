
variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "my_ip" {
  description = "public IP in CIDR form, e.g. 1.2.3.4/32"
  type        = string
}
