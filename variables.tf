variable "aws_region" {
  description = "Región de AWS donde se desplegará el servidor"
  default     = "us-east-1"
}

variable "server_name" {
  description = "Nombre del servidor para etiquetas"
  default     = "mc-bedrock-prod"
}

variable "whitelist_ip" {
  description = "Tu IP pública para acceso SSH (seguridad). Pon 0.0.0.0/0 para abrirlo a todos (riesgoso)"
  default     = "0.0.0.0/0" 
}
