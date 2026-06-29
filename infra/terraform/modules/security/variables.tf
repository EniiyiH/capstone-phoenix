
variable "vpc_id" {
  description = "VPC to attach the security group to"
  type        = string
}

variable "my_ip" {
  description = "Your public IP in CIDR form, e.g. 1.2.3.4/32"
  type        = string
}

variable "project_name" {
  type    = string
  default = "phoenix-capstone"
}
