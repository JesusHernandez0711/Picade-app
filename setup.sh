#!/bin/bash
echo "🚀 Iniciando Setup del Sistema PICADE y Cero Tolerancia..."

# 1. Levantar contenedores
docker compose up -d

# 2. Copiar CSVs y dar permisos
echo "📦 Cargando archivos de datos..."
docker cp ./docker/mariadb/csv/. PICADE_DB:/var/lib/mysql-files/
docker exec -u root PICADE_DB chmod -R 777 /var/lib/mysql-files/

# 3. Migraciones de Laravel
echo "🏗️ Ejecutando migraciones de Laravel..."
docker exec -it PICADE_APP php artisan migrate --force

# 4. Estructura y Carga Masiva
echo "💾 Inyectando estructura de negocio y catálogos..."
docker exec -i PICADE_DB mariadb -u root -pROOT_PICADE_USER_ADMIN PICADE < "./docker/mariadb/init/0_PICADE-FINAL-09-02-26.sql"
docker exec -i PICADE_DB mariadb -u root -pROOT_PICADE_USER_ADMIN PICADE < "./docker/mariadb/init/01_CargarMasivaCSV.sql"

# 5. Procedimientos Almacenados
echo "🧠 Cargando procedimientos almacenados..."
for f in ./docker/mariadb/init/[1-9]*.sql; do
    docker exec -i PICADE_DB mariadb -u root -pROOT_PICADE_USER_ADMIN PICADE < "$f"
done

echo "✅ ¡Sistema listo! Accede a localhost en tu navegador."
