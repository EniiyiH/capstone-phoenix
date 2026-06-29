
resource "aws_security_group" "nodes" {
  name        = "${var.project_name}-sg"
  description = "Firewall for k3s nodes"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.project_name}-sg" }
}

# SSH — only from your IP
resource "aws_security_group_rule" "ssh" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = [var.my_ip]
  security_group_id = aws_security_group.nodes.id
  description       = "SSH from admin IP only"
}

# HTTP — public
resource "aws_security_group_rule" "http" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.nodes.id
  description       = "HTTP, public (redirects to HTTPS)"
}

# HTTPS — public
resource "aws_security_group_rule" "https" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.nodes.id
  description       = "HTTPS, public"
}

# Kubernetes API (6443) — only from your IP, NOT 0.0.0.0/0
resource "aws_security_group_rule" "k8s_api" {
  type              = "ingress"
  from_port         = 6443
  to_port           = 6443
  protocol          = "tcp"
  cidr_blocks       = [var.my_ip]
  security_group_id = aws_security_group.nodes.id
  description       = "k8s API from admin IP only"
}

# Node-to-node: allow ALL traffic between members of this same SG

resource "aws_security_group_rule" "internal_all" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = aws_security_group.nodes.id
  security_group_id        = aws_security_group.nodes.id
  description              = "All traffic between cluster nodes"
}

# Outbound — allow everything out (pulling images, package updates, etc.)
resource "aws_security_group_rule" "egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.nodes.id
  description       = "Allow all outbound"
}
