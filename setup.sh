#!/bin/bash
# Script de Automatización Total para Picade-app
# Uso: ./setup.sh

# Definir rutas para no repetir
PROJECT_PATH=~/Proyectos/Picade-app
CSV_PATH=./docker/mariadb/csv
INIT_SQL_PATH=./docker/mariadb/init

# Detener el script si ocurre un error grave (opcional)
# set -e 

echo "🚀 --- INICIANDO PROTOCOLO DE REINICIO PICADE ---"

# 1. Moverse a la carpeta del proyecto
cd "$PROJECT_PATH" || { echo "❌ No se encontró la carpeta del proyecto"; exit 1; }

# 2. Docker: Destruir y Reconstruir (Limpieza profunda)
echo "🐳 Reiniciando Contenedores..."
sudo docker compose down
sudo docker compose build --no-cache
sudo docker compose up -d

echo "⏳ Esperando 30 segundos a que la Base de Datos arranque..."
sleep 30

# 3. Instalación de Dependencias
echo "📦 Instalando dependencias (Composer y NPM)..."
sudo docker exec -it PICADE_APP composer install
sudo docker exec -it PICADE_APP npm install

# 4. Permisos de carpeta
echo "🔑 Asignando permisos al usuario..."
sudo chown -R $USER:$USER .

# 5, 6 y 7. Carga de Archivos CSV al Contenedor
echo "📂 Copiando y preparando archivos CSV..."
sudo docker cp "$CSV_PATH/." PICADE_DB:/var/lib/mysql-files/
sudo docker exec -u root PICADE_DB chmod -R 777 /var/lib/mysql-files/

# [IMPORTANTE] Corrección de formato Windows (CRLF) a Linux (LF)
# Esto asegura que los CSV funcionen aunque vengan de Windows
sudo docker exec PICADE_DB sh -c "sed -i 's/\r$//' /var/lib/mysql-files/*.csv"

# 8. Limpieza de Caché Laravel
echo "🧹 Limpiando caché de Laravel..."
sudo docker exec -it PICADE_APP php artisan config:clear
sudo docker exec -it PICADE_APP php artisan cache:clear
sudo docker exec -it PICADE_APP php artisan route:clear

# 9. Base de Datos: Destrucción y Creación
echo "💥 Recreando Base de Datos (DROP & CREATE)..."
sudo docker exec -it PICADE_DB mariadb -u root -pROOT_PICADE_USER_ADMIN -e "DROP DATABASE IF EXISTS PICADE; CREATE DATABASE PICADE;"

# 10 y 11. Claves y Migraciones Base
echo "🔑 Generando Key y Estructura base..."
sudo docker exec -it PICADE_APP php artisan key:generate
# Usamos --force para producción y || true para que no falle si ya existen tablas
sudo docker exec -it PICADE_APP php artisan migrate --force || true

# 12 y 13. Carga Masiva de SQL (Estructura, Datos y Procedimientos)
echo "📥 Inyectando SQLs (Esto puede tardar unos segundos)..."

# Lista ordenada de archivos a ejecutar
SQL_FILES=(
    "0_PICADE-FINAL-09-02-26.sql"
    "01_CargarMasivaCSV.sql"
    "1. PROCEDIMIENTOS-GESTION_GEOGRAFICA.sql"
    "2. PROCEDIMIENTOS-ORGANIZACION_INTERNA.sql"
    "3. PROCEDIMIENTOS_CENTROS_DE_TRABAJO.sql"
    "4. PROCEDIMIENTOS_DEPARTAMENTOS.sql"
    "5. PROCEDIMIENTOS-CASES.sql"
    "6. PROCEDIMIENTOS-REGIMEN_TRABAJO.sql"
    "7. PROCEDIMIENTOS-PUESTOS_TRABAJO.sql"
    "8. PROCEDIMIENTOS-REGION_OPERATIVA.sql"
    "9. PROCEDIMIENTOS-ROL_USER.sql"
    "10. PROCEDIMIENTOS-USUARIO_INFOPERSONAL.sql"
    "11_PROCEDIMIENTOS_TIPOS_INSTRUCCIONES.sql"
    "12_PROCEDIMIENTOS_TEMAS_CAPACITACION.sql"
    "13_PROCEDIMIENTOS_ESTATUS_CAPACITACION.sql"
    "14_PROCEDIMIENTOS_MODALIDAD_CAPACITACION.sql"
    "15_PROCEDIMIENTOS_ESTATUS_PARTICIPANTE.sql"
    "16. PROCEDIMIENTOS_CAPACITACIONES.sql"
    "17. PROCEDIMIENTOS_PARTICIPANTES_DE_CAPACITACIONES.sql"
)

# Bucle para ejecutar cada archivo en orden
for file in "${SQL_FILES[@]}"; do
    echo "   -> Ejecutando: $file"
    # Redirigimos la entrada del archivo hacia el comando docker
    sudo docker exec -i PICADE_DB mariadb -u root -pROOT_PICADE_USER_ADMIN PICADE < "$INIT_SQL_PATH/$file"
done

# 14. Link de Almacenamiento
echo "🔗 Creando Storage Link..."
sudo docker exec -it PICADE_APP php artisan storage:link

echo "✅ ¡SISTEMA REINICIADO Y LISTO! 🚀"
echo "   Accede a: http://localhost:8000"