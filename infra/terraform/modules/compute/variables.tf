
variable "vpc_id" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "security_group_id" {
  type = string
}

variable "instance_type" {
  type    = string
  default = "t3.small"
}

variable "key_name" {
  description = "Name of the AWS EC2 Key Pair (uploaded public key)"
  type        = string
}

variable "project_name" {
  type    = string
  default = "phoenix-capstone"
}
