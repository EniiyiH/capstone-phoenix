output "control_plane_public_ip"  { value = aws_instance.control_plane.public_ip }
output "control_plane_private_ip" { value = aws_instance.control_plane.private_ip }

output "worker_public_ips" {
  value = [aws_instance.worker_1.public_ip, aws_instance.worker_2.public_ip]
}

output "worker_private_ips" {
  value = [aws_instance.worker_1.private_ip, aws_instance.worker_2.private_ip]
}
