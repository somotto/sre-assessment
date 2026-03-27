output "vm1_public_ip" {
  description = "Public IP of VM1 (gateway) — use this for SSH and Ansible"
  value       = aws_instance.vm1.public_ip
}

output "vm1_private_ip" {
  description = "Private IP of VM1"
  value       = aws_instance.vm1.private_ip
}

output "vm2_private_ip" {
  description = "Private IP of VM2 (app server) — only reachable from VM1"
  value       = aws_instance.vm2.private_ip
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}
