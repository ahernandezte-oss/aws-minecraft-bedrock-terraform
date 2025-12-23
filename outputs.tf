output "server_ip" {
  description = "IP Pública del servidor Minecraft"
  value       = aws_instance.server.public_ip
}

output "ssh_connection_string" {
  description = "Comando para conectarse por SSH"
  value       = "ssh -i private_key.pem ec2-user@${aws_instance.server.public_ip}"
}

output "s3_bucket_name" {
  description = "Bucket donde se guardan los backups"
  value       = aws_s3_bucket.backups.id
}
