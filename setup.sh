#!/bin/bash
echo "🚀 Iniciando Setup del Sistema PICADE y Cero Tolerancia..."

cd ~/Proyectos/Picade-app

# 1. Levantar contenedores
docker compose up -d

sudo docker exec -it PICADE_APP composer install

sudo docker exec -it PICADE_APP npm install

docker exec -u root PICADE_DB chmod -R 777 /var/lib/mysql-files/

echo "Creacion de base de datos:"
sudo docker exec -it PICADE_DB mariadb -u root -pROOT_PICADE_USER_ADMIN -e "DROP DATABASE IF EXISTS PICADE; CREATE DATABASE PICADE;"


# 2. Copiar CSVs y dar permisos
echo "📦 Cargando archivos de datos..."
sudo docker exec -it PICADE_DB ls /var/lib/mysql-files/

docker cp ./docker/mariadb/csv/. PICADE_DB:/var/lib/mysql-files/

docker exec -u root PICADE_DB chmod -R 777 /var/lib/mysql-files/

#docker cp ~/Proyectos/Picade-app/docker/mariadb/csv/. PICADE_DB:/var/lib/mysql-files/

#docker exec -u root PICADE_DB chmod -R 777 /var/lib/mysql-files/

# 3. Migraciones de Laravel
echo "🏗️ Ejecutando migraciones de Laravel..."


sudo docker exec -it PICADE_APP php artisan config:clear

sudo docker exec -it PICADE_APP php artisan key:generate

docker exec -it PICADE_APP php artisan migrate

#--force

# 4. Estructura y Carga Masiva
echo "💾 Inyectando estructura de negocio y catálogos..."

cd ~/Proyectos/Picade-app/docker/mariadb/init/

#docker exec -i PICADE_DB mariadb -u root -pROOT_PICADE_USER_ADMIN PICADE < "./docker/mariadb/init/0_PICADE-FINAL-09-02-26.sql"
#docker exec -i PICADE_DB mariadb -u root -pROOT_PICADE_USER_ADMIN PICADE < "./docker/mariadb/init/01_CargarMasivaCSV.sql"

docker exec -i PICADE_DB mariadb -u root -pROOT_PICADE_USER_ADMIN PICADE < "0_PICADE-FINAL-09-02-26.sql"

docker exec -i PICADE_DB mariadb -u root -pROOT_PICADE_USER_ADMIN PICADE < "01_CargarMasivaCSV.sql"

# 5. Procedimientos Almacenados
echo "🧠 Cargando procedimientos almacenados..."
#for f in ./docker/mariadb/init/[1-9]*.sql; do
#    docker exec -i PICADE_DB mariadb -u root -pROOT_PICADE_USER_ADMIN PICADE < "$f"
#done


docker exec -i PICADE_DB mariadb -u root -pROOT_PICADE_USER_ADMIN PICADE < "1. PROCEDIMIENTOS-GESTION_GEOGRAFICA.sql"

docker exec -i PICADE_DB mariadb -u root -pROOT_PICADE_USER_ADMIN PICADE < "2. PROCEDIMIENTOS-ORGANIZACION_INTERNA.sql"

docker exec -i PICADE_DB mariadb -u root -pROOT_PICADE_USER_ADMIN PICADE < "3. PROCEDIMIENTOS_CENTROS_DE_TRABAJO.sql"

docker exec -i PICADE_DB mariadb -u root -pROOT_PICADE_USER_ADMIN PICADE < "4. PROCEDIMIENTOS_DEPARTAMENTOS.sql"

docker exec -i PICADE_DB mariadb -u root -pROOT_PICADE_USER_ADMIN PICADE < "5. PROCEDIMIENTOS-CASES.sql"

docker exec -i PICADE_DB mariadb -u root -pROOT_PICADE_USER_ADMIN PICADE < "6. PROCEDIMIENTOS-REGIMEN_TRABAJO.sql"

docker exec -i PICADE_DB mariadb -u root -pROOT_PICADE_USER_ADMIN PICADE < "7. PROCEDIMIENTOS-PUESTOS_TRABAJO.sql"

docker exec -i PICADE_DB mariadb -u root -pROOT_PICADE_USER_ADMIN PICADE < "8. PROCEDIMIENTOS-REGION_OPERATIVA.sql"

docker exec -i PICADE_DB mariadb -u root -pROOT_PICADE_USER_ADMIN PICADE < "9. PROCEDIMIENTOS-ROL_USER.sql"

docker exec -i PICADE_DB mariadb -u root -pROOT_PICADE_USER_ADMIN PICADE < "10. PROCEDIMIENTOS-USUARIO_INFOPERSONAL.sql"

docker exec -i PICADE_DB mariadb -u root -pROOT_PICADE_USER_ADMIN PICADE < "11_PROCEDIMIENTOS_TIPOS_INSTRUCCIONES.sql"

docker exec -i PICADE_DB mariadb -u root -pROOT_PICADE_USER_ADMIN PICADE < "12_PROCEDIMIENTOS_TEMAS_CAPACITACION.sql"

docker exec -i PICADE_DB mariadb -u root -pROOT_PICADE_USER_ADMIN PICADE < "13_PROCEDIMIENTOS_ESTATUS_CAPACITACION.sql"

docker exec -i PICADE_DB mariadb -u root -pROOT_PICADE_USER_ADMIN PICADE < "14_PROCEDIMIENTOS_MODALIDAD_CAPACITACION.sql"

docker exec -i PICADE_DB mariadb -u root -pROOT_PICADE_USER_ADMIN PICADE < "15_PROCEDIMIENTOS_ESTATUS_PARTICIPANTE.sql"

docker exec -i PICADE_DB mariadb -u root -pROOT_PICADE_USER_ADMIN PICADE < "16. PROCEDIMIENTOS_CAPACITACIONES.sql"

docker exec -i PICADE_DB mariadb -u root -pROOT_PICADE_USER_ADMIN PICADE < "17. PROCEDIMIENTOS_PARTICIPANTES_DE_CAPACITACIONES.sql"


echo "✅ ¡Sistema listo! Accede a localhost en tu navegador."

sudo docker exec -it PICADE_APP npm run dev

sudo docker exec -it PICADE_APP php artisan storage:link

# Guardar todo (Estructura + Datos + SPs + Vistas) en un solo archivo
sudo docker exec PICADE_DB mariadb-dump -u root -pROOT_PICADE_USER_ADMIN --routines --events --triggers --add-drop-table --databases PICADE > respaldo_maestro_final.sql

# Borrar caché de configuración antigua
sudo docker exec -it PICADE_APP php artisan config:clear

# Borrar caché de rutas
sudo docker exec -it PICADE_APP php artisan route:clear

# Borrar caché de vistas compiladas
sudo docker exec -it PICADE_APP php artisan view:clear