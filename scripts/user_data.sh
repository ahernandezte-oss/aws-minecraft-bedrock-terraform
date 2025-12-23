#!/bin/bash

# Logs para depuración (visible en /var/log/user-data.log)
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "--- Iniciando Configuración del Servidor Minecraft ---"

# 1. Variables inyectadas por Terraform
BUCKET_NAME="${s3_bucket_name}"
MC_DIR="/home/ec2-user/minecraft_data"

# 2. Actualizar sistema e instalar dependencias
dnf update -y
dnf install -y docker cronie unzip
systemctl start docker
systemctl enable docker
usermod -aG docker ec2-user

# 3. Preparar directorios
mkdir -p $MC_DIR

# 4. Lógica de Restauración (Disaster Recovery)
# Si existe un backup en S3, lo descargamos y restauramos antes de iniciar
echo "--- Verificando backups en S3 ---"
if aws s3 ls "s3://$BUCKET_NAME/world_backup.zip"; then
    echo "Backup encontrado. Restaurando..."
    aws s3 cp "s3://$BUCKET_NAME/world_backup.zip" /tmp/world_backup.zip
    unzip -o /tmp/world_backup.zip -d $MC_DIR
    chown -R ec2-user:ec2-user $MC_DIR
    echo "Restauración completada."
else
    echo "No se encontraron backups. Iniciando mundo nuevo."
fi

# 5. Desplegar Contenedor Docker (itzg/minecraft-bedrock-server)
# Usamos 'network host' para rendimiento óptimo de UDP y baja latencia
docker run -d \
  --name mc-server \
  --restart always \
  --network host \
  -e EULA=TRUE \
  -e GAMEMODE=survival \
  -e DIFFICULTY=normal \
  -e ALLOW_CHEATS=false \
  -v $MC_DIR:/data \
  itzg/minecraft-bedrock-server:latest

# 6. Script de Backup Automático
# Crea un script local que comprime el mundo y lo sube a S3
cat <<EOF > /home/ec2-user/backup_script.sh
#!/bin/bash
cd $MC_DIR
# Zip del directorio de datos (excluyendo archivos temporales si es necesario)
zip -r /tmp/world_backup.zip . -x "*.log"
# Subida a S3
aws s3 cp /tmp/world_backup.zip s3://$BUCKET_NAME/world_backup.zip
echo "Backup subido a las \$(date)" >> /home/ec2-user/backup.log
EOF

chmod +x /home/ec2-user/backup_script.sh
chown ec2-user:ec2-user /home/ec2-user/backup_script.sh

# 7. Configurar Cronjob (Backup cada 30 minutos)
# Esto protege contra la pérdida de datos si la instancia Spot es reclamada
echo "*/30 * * * * /home/ec2-user/backup_script.sh" | crontab -

echo "--- Despliegue Completado Exitosamente ---"
