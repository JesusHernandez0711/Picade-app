#!/bin/bash

# 1. Definir rutas y nombre de archivo con fecha (Ej: PICADE_2023-10-27_10-30-00.sql)
FECHA=$(date +"%Y-%m-%d_%H-%M-%S")
ARCHIVO="PICADE_BD_$FECHA.sql"

RUTA_ORIGEN="$HOME/Proyectos/Picade-app/docker/mariadb/Backups"
RUTA_COPIA="$HOME/Proyectos/Picade-app/Backups"

# 2. Entrar al contenedor y generar el respaldo (Usando mariadb-dump nativo)
echo "🔄 Generando respaldo de la base de datos..."

sudo docker exec PICADE_DB mariadb-dump -u root -pROOT_PICADE_USER_ADMIN \
    --routines --events --triggers --add-drop-table --databases PICADE > "$RUTA_ORIGEN/$ARCHIVO"

# 3. Verificar si se creó correctamente
if [ -f "$RUTA_ORIGEN/$ARCHIVO" ]; then
    echo "✅ Respaldo creado exitosamente en: docker/mariadb/Backups/$ARCHIVO"
    
    # 4. Crear la copia en la segunda carpeta
    cp "$RUTA_ORIGEN/$ARCHIVO" "$RUTA_COPIA/$ARCHIVO"
    
    if [ -f "$RUTA_COPIA/$ARCHIVO" ]; then
        echo "✅ Copia de seguridad guardada en: Picade-app/Backups/$ARCHIVO"
    else
        echo "⚠️ Error al copiar el archivo a la carpeta externa."
    fi
else
    echo "❌ Error: No se pudo generar el respaldo."
fi