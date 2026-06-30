# Find the latest Ubuntu 22.04 AMI dynamically

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]  # Canonical's official AWS account

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Upload your public SSH key to AWS so it gets injected into instances at boot

resource "aws_key_pair" "deployer" {
  key_name   = var.key_name
  public_key = file("~/.ssh/phoenix-capstone.pub")
}

resource "aws_instance" "control_plane" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  key_name               = aws_key_pair.deployer.key_name
  vpc_security_group_ids = [var.security_group_id]

  tags = {
    Name = "${var.project_name}-control-plane"
    Role = "control-plane"
  }
}

resource "aws_instance" "worker_1" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  key_name               = aws_key_pair.deployer.key_name
  vpc_security_group_ids = [var.security_group_id]

  tags = {
    Name = "${var.project_name}-worker-1"
    Role = "worker"
  }
}

resource "aws_instance" "worker_2" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  key_name               = aws_key_pair.deployer.key_name
  vpc_security_group_ids = [var.security_group_id]

  tags = {
    Name = "${var.project_name}-worker-2"
    Role = "worker"
  }
}
