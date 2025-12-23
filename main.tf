# --- 1. Seguridad y Acceso (SSH Key Dinámica) ---
resource "tls_private_key" "pk" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "generated_key" {
  key_name   = "${var.server_name}-key"
  public_key = tls_private_key.pk.public_key_openssh
}

# Guardamos la llave privada localmente para que te puedas conectar
resource "local_file" "ssh_key" {
  content  = tls_private_key.pk.private_key_pem
  filename = "${path.module}/private_key.pem"
  file_permission = "0400"
}

# --- 2. Almacenamiento (S3 para Backups) ---
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "backups" {
  bucket = "mc-bedrock-backups-${random_id.bucket_suffix.hex}"
  force_destroy = true # Permite borrar el bucket aunque tenga datos (útil para pruebas)
}

resource "aws_s3_bucket_public_access_block" "backups_security" {
  bucket = aws_s3_bucket.backups.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- 3. IAM (Permisos para la EC2) ---
resource "aws_iam_role" "ec2_role" {
  name = "${var.server_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "s3_access" {
  name = "s3_access_policy"
  role = aws_iam_role.ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Effect   = "Allow"
        Resource = [
          aws_s3_bucket.backups.arn,
          "${aws_s3_bucket.backups.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.server_name}-profile"
  role = aws_iam_role.ec2_role.name
}

# --- 4. Networking (Security Group) ---
resource "aws_security_group" "mc_sg" {
  name        = "${var.server_name}-sg"
  description = "Security Group para Minecraft Bedrock"

  # Puerto de juego (UDP)
  ingress {
    from_port   = 19132
    to_port     = 19132
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH (TCP)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.whitelist_ip]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- 5. Cómputo (EC2 Spot + Graviton) ---
# Buscar la última AMI de Amazon Linux 2023 ARM64
data "aws_ami" "amazon_linux_arm" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-arm64"]
  }
}

resource "aws_instance" "server" {
  ami           = data.aws_ami.amazon_linux_arm.id
  instance_type = "t4g.small" # Instancia ARM eficiente
  key_name      = aws_key_pair.generated_key.key_name
  
  vpc_security_group_ids = [aws_security_group.mc_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  # Estrategia de Costos: Spot Instances
  instance_market_options {
    market_type = "spot"
    spot_options {
      max_price = "0.02" # Precio máximo dispuesto a pagar
      spot_instance_type = "one-time"
    }
  }

  # Inyección del script de User Data
  user_data = templatefile("${path.module}/scripts/user_data.sh", {
    s3_bucket_name = aws_s3_bucket.backups.id
  })

  user_data_replace_on_change = true

  tags = {
    Name = var.server_name
  }
}
