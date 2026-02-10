-- Asegúrate de estar usando la base de datos correcta
USE `PICADE`;

/* ------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------- */

LOAD DATA INFILE '/var/lib/mysql-files/PAISES-FINAL.csv'
INTO TABLE `Pais`
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ';'
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(`Codigo`,
@Var_Nombre)
SET
	-- Codigo = NULLIF(@vCodigo, ''), -- ¡AQUI ESTA EL ARREGLO!
	`Nombre` = TRIM(@Var_Nombre), -- Limpiamos espacios
	`Activo` =1, 
	`created_at` =NOW(), 
	`updated_at` =NOW();

-- SHOW TABLE STATUS LIKE 'Pais';

-- SELECT * FROM `Pais` /*LIMIT 0, 3000*/;
/* ------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------- */

LOAD DATA INFILE '/var/lib/mysql-files/ESTADOS-FINAL.csv'
INTO TABLE `Estado`
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ';'
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(`Codigo`, 
@Var_Nombre,
`Fk_Id_Pais`)
SET 
	`Nombre` = TRIM(@Var_Nombre), -- Limpiamos espacios
	`Activo` =1,
    `created_at` =NOW(),
    `updated_at` =NOW();
    
-- SHOW TABLE STATUS LIKE 'Estado';

ALTER TABLE `Estado` AUTO_INCREMENT = 1;

-- SHOW TABLE STATUS LIKE 'Estado';

-- SELECT * FROM `Estado` /*LIMIT 0, 3000*/;
/* ------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------- */

LOAD DATA INFILE '/var/lib/mysql-files/MUNICIPIO-FINAL.csv'
INTO TABLE `Municipio`
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ';'
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(`Codigo`,
@Var_Nombre,
`Fk_Id_Estado`)
SET 
	`Nombre` = TRIM(@Var_Nombre), -- Limpiamos espacios
	`Codigo` = NULLIF(@vCodigo, ''),
	`Activo` =1,
    `created_at` =NOW(),
    `updated_at` =NOW();
    
-- SHOW TABLE STATUS LIKE 'Municipio';

ALTER TABLE `Municipio` AUTO_INCREMENT = 1;

-- SHOW TABLE STATUS LIKE 'Municipio';

-- SELECT * FROM `Municipio` /*LIMIT 0, 3000*/;
/* ------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------- */

LOAD DATA INFILE '/var/lib/mysql-files/CATALOGO-CENTROS-TRABAJO-FINAL.csv'
INTO TABLE `Cat_Centros_Trabajo`
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ';'
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(
@Var_Codigo,
@Var_Nombre,
@Var_Direccion_Fisica,
@Fk_Id_Municipio_CatCT)
SET
	`Codigo` = NULLIF(TRIM(@Var_Codigo), ''), -- Dejamos el código vacio explícitamente
	`Nombre` = TRIM(@Var_Nombre), -- Limpiamos espacios
	`Direccion_Fisica` = NULLIF(TRIM(@Var_Direccion_Fisica), ''),
    `Fk_Id_Municipio_CatCT` = NULLIF(@Fk_Id_Municipio_CatCT, ''),
    `Activo` = 1,
    `created_at` = NOW(),
    `updated_at` = NOW();

-- SHOW TABLE STATUS LIKE 'Cat_Centros_Trabajo';

ALTER TABLE `Cat_Centros_Trabajo` AUTO_INCREMENT = 1;

-- SHOW TABLE STATUS LIKE 'Cat_Centros_Trabajo';

-- SELECT * FROM `Cat_Centros_Trabajo` /*LIMIT 0, 3000*/;
/* ------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------- */

LOAD DATA INFILE '/var/lib/mysql-files/CATALOGO-DEPARTAMENTOS-TRABAJO-FINAL.csv'
INTO TABLE `Cat_Departamentos`
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ';'
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(`Codigo`,
@Var_Nombre,
@Var_Direccion_Fisica,
@Fk_Id_Municipio_CatDep)
SET
	`Nombre` = TRIM(@Var_Nombre), -- Limpiamos espacios
	`Direccion_Fisica` = NULLIF(@Var_Direccion_Fisica, ''),
    `Fk_Id_Municipio_CatDep` = NULLIF(@Fk_Id_Municipio_CatDep, ''),
    `Activo` = 1,
    `created_at` = NOW(),
    `updated_at` = NOW();

-- SHOW TABLE STATUS LIKE 'Cat_Departamentos';

ALTER TABLE `Cat_Departamentos` AUTO_INCREMENT = 1;

-- SHOW TABLE STATUS LIKE 'Cat_Departamentos';

-- SELECT * FROM `Cat_Departamentos`/*LIMIT 0, 3000*/;
/* ------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------- */

LOAD DATA INFILE '/var/lib/mysql-files/CATALOGO-DIRECCIONES-FINAL.csv'
INTO TABLE `Cat_Direcciones`
CHARACTER SET latin1
FIELDS TERMINATED BY ';'
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(@Var_Clave,
@Var_Nombre)
SET
    `Clave` = NULLIF(TRIM(@Var_Clave), ''),                 -- IMPORTANTE: evita duplicados '' por UNIQUE
	`Nombre` = TRIM(@Var_Nombre), -- Limpiamos espacios
    `Activo` = 1,
    `created_at` = NOW(),
    `updated_at` = NOW();

-- SHOW TABLE STATUS LIKE 'Cat_Direcciones';

ALTER TABLE `Cat_Direcciones` AUTO_INCREMENT = 1;

-- SHOW TABLE STATUS LIKE 'Cat_Direcciones';

-- SELECT * FROM `Cat_Direcciones`/*LIMIT 0, 3000*/;
/* ------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------- */

LOAD DATA INFILE '/var/lib/mysql-files/CATALOGO-SUBDIRECCIONES-FINAL.csv'
INTO TABLE `Cat_Subdirecciones`
CHARACTER SET latin1
FIELDS TERMINATED BY ';'
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(`Fk_Id_CatDirecc`, 
@Var_Clave,
@Var_Nombre)
SET
    `Clave` = NULLIF(TRIM(@Var_Clave), ''),                 -- IMPORTANTE: evita duplicados '' por UNIQUE
	`Nombre` = TRIM(@Var_Nombre), -- Limpiamos espacios
    `Activo` = 1,
    `created_at` = NOW(),
    `updated_at` = NOW();

-- SHOW TABLE STATUS LIKE 'Cat_Subdirecciones';

ALTER TABLE `Cat_Subdirecciones` AUTO_INCREMENT = 1;

-- SHOW TABLE STATUS LIKE 'Cat_Subdirecciones';

-- SELECT * FROM `Cat_Subdirecciones`/*LIMIT 0, 3000*/;
/* ------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------- */

-- Nota: tu CSV trae Id_Gerencias y Activo.
-- Si la tabla está VACÍA, puedes cargar el Id para conservar exactamente esos IDs.
LOAD DATA INFILE '/var/lib/mysql-files/CATALOGO-GERENCIAS-ACTIVOS-FINAL.csv'
INTO TABLE `Cat_Gerencias_Activos`
CHARACTER SET latin1
FIELDS TERMINATED BY ';'
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(`Fk_Id_CatSubDirec`,
@Var_Clave,
@Var_Nombre)
SET
    `Clave` = NULLIF(TRIM(@Var_Clave), ''),                 -- IMPORTANTE: evita duplicados '' por UNIQUE
	`Nombre` = TRIM(@Var_Nombre), -- Limpiamos espacios
    `Activo` = 1,
    `created_at` = NOW(),
    `updated_at` = NOW();

-- SHOW TABLE STATUS LIKE 'Cat_Gerencias_Activos';

ALTER TABLE `Cat_Gerencias_Activos` AUTO_INCREMENT = 1;

-- SHOW TABLE STATUS LIKE 'Cat_Gerencias_Activos';

-- SELECT * FROM `Cat_Gerencias_Activos`/*LIMIT 0, 3000*/;
/* ------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------- */

LOAD DATA INFILE '/var/lib/mysql-files/CATALOGO-REGIMENES-TRABAJO-FINAL.csv'
INTO TABLE `Cat_Regimenes_Trabajo`
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ';'
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(
@Var_Codigo,
@Var_Nombre,      -- Leemos en variable temporal
@Var_Descripcion  -- Leemos en variable temporal
)
SET
	`Codigo` = NULLIF(TRIM(@Var_Codigo), ''), -- Dejamos el código vacio explícitamente
    `Nombre` = TRIM(@Var_Nombre), -- Limpiamos espacios
    `Descripcion` = NULLIF(TRIM(@Var_Descripcion), ''),
    `Activo` = 1,
    `created_at` = NOW(),
    `updated_at` = NOW();

-- SHOW TABLE STATUS LIKE 'Cat_Regimenes_Trabajo';

ALTER TABLE `Cat_Regimenes_Trabajo` AUTO_INCREMENT = 1;

-- SHOW TABLE STATUS LIKE 'Cat_Regimenes_Trabajo';

-- SELECT * FROM `Cat_Regimenes_Trabajo` /*LIMIT 0, 3000*/;
/* ------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------- */

LOAD DATA INFILE '/var/lib/mysql-files/CATALOGO-REGIONES-FINAL.csv'
INTO TABLE `Cat_Regiones_Trabajo`
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ';'
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(
@Var_Codigo,
@Var_Nombre,      -- Leemos en variable temporal
@Var_Descripcion  -- Leemos en variable temporal
)
SET
	`Codigo` = NULLIF(TRIM(@Var_Codigo), ''), -- Dejamos el código vacio explícitamente
    `Nombre`      = TRIM(@Var_Nombre), -- Limpiamos espacios
    `Descripcion` = NULLIF(TRIM(@Var_Descripcion), ''),
    `Activo` = 1,
    `created_at` = NOW(),
    `updated_at` = NOW();

-- SHOW TABLE STATUS LIKE 'Cat_Regiones_Trabajo';

-- SELECT * FROM `Cat_Regiones_Trabajo` /*LIMIT 0, 3000*/;

/* ------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------- */

LOAD DATA INFILE '/var/lib/mysql-files/CATALOGO-PUESTOS-TRABAJO-FINAL.csv'
INTO TABLE `Cat_Puestos_Trabajo`
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ';'
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(
@Var_Codigo,
@Var_Nombre,      -- Leemos en variable temporal
@Var_Descripcion  -- Leemos en variable temporal
)
SET
	`Codigo` = NULLIF(TRIM(@Var_Codigo), ''), -- Dejamos el código vacio explícitamente
    `Nombre`      = TRIM(@Var_Nombre), -- Limpiamos espacios
    `Descripcion` = NULLIF(TRIM(@Var_Descripcion), ''),
    `Activo` = 1,
    `created_at` = NOW(),
    `updated_at` = NOW();

-- SHOW TABLE STATUS LIKE 'Cat_Puestos_Trabajo';

ALTER TABLE `Cat_Puestos_Trabajo` AUTO_INCREMENT = 1;

-- SHOW TABLE STATUS LIKE 'Cat_Puestos_Trabajo';

-- SELECT * FROM `Cat_Puestos_Trabajo`/*LIMIT 0, 3000*/;
/* ------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------- */

LOAD DATA INFILE '/var/lib/mysql-files/INFO-PERSONAL-FINAL.csv'
INTO TABLE `Info_Personal`
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ';'
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(@Var_Nombre,
@Var_Apellido_Paterno,
@Var_Apellido_Materno,
-- @CURP,
-- @RFC,
@Var_Fecha_Nacimiento,  -- <--- 1. Interceptamos con variable
@Var_Fecha_Ingreso,     -- <--- 1. Interceptamos con variable
@Fk_Id_CatRegimen,
@Fk_Id_CatPuesto,
@Fk_Id_CatCT,
@Fk_Id_CatDep,
@Fk_Id_CatRegion,
@Fk_Id_CatGeren,
@Var_Nivel,
@Var_Clasificacion)
SET
	`Nombre` = TRIM(@Var_Nombre), -- Limpiamos espacios
   	`Apellido_Paterno` = TRIM(@Var_Apellido_Paterno), -- Limpiamos espacios
	`Apellido_Materno` = TRIM(@Var_Apellido_Materno), -- Limpiamos espacios    
    
-- 	`CURP` = NULLIF(@CURP, ''),
-- 	`RFC` = NULLIF(@RFC, ''),
    
	/* 2. Transformamos Fecha Nacimiento */
    `Fecha_Nacimiento` = CASE 
        WHEN @Var_Fecha_Nacimiento = '' OR @Var_Fecha_Nacimiento IS NULL THEN NULL 
        ELSE STR_TO_DATE(@Var_Fecha_Nacimiento, '%d/%m/%Y') 
    END,

    /* 2. Transformamos Fecha Ingreso */
    `Fecha_Ingreso` = CASE 
        WHEN @Var_Fecha_Ingreso = '' OR @Var_Fecha_Ingreso IS NULL THEN NULL 
        ELSE STR_TO_DATE(@Var_Fecha_Ingreso, '%d/%m/%Y') 
    END,

    /* Resto de campos (NULLIF para las llaves foráneas vacías) */
    `Fk_Id_CatRegimen` = NULLIF(@Fk_Id_CatRegimen, ''),
    `Fk_Id_CatPuesto` = NULLIF(@Fk_Id_CatPuesto, ''),
    `Fk_Id_CatCT` = NULLIF(@Fk_Id_CatCT, ''),
    `Fk_Id_CatDep` = NULLIF(@Fk_Id_CatDep, ''),
    `Fk_Id_CatRegion` = NULLIF(@Fk_Id_CatRegion, ''),
    `Fk_Id_CatGeren` = NULLIF(@Fk_Id_CatGeren, ''),
    
    `Nivel` = NULLIF(TRIM(@Var_Nivel), ''), 
    `Clasificacion` = NULLIF(TRIM(@Var_Clasificacion), ''),
    
    `Activo` = 1,
    `created_at` = NOW(),
    `updated_at` = NOW();

-- SHOW TABLE STATUS LIKE 'Info_Personal';

ALTER TABLE `Info_Personal` AUTO_INCREMENT = 1;

-- SHOW TABLE STATUS LIKE 'Info_Personal';

-- SELECT * FROM `Info_Personal` /*LIMIT 0, 3000*/;
/* ------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------- */

LOAD DATA INFILE '/var/lib/mysql-files/CATALOGO-ROLES-FINAL.csv'
INTO TABLE `Cat_Roles`
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ';'
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(
@Var_Codigo,
@Var_Nombre,      -- Leemos en variable temporal
@Var_Descripcion  -- Leemos en variable temporal
)
SET
	`Codigo` = NULLIF(TRIM(@Var_Codigo), ''), -- Dejamos el código vacio explícitamente
    `Nombre` = TRIM(@Var_Nombre), -- Limpiamos espacios
    `Descripcion` = NULLIF(TRIM(@Var_Descripcion), ''),
    `Activo` = 1,
    `created_at` = NOW(),
    `updated_at` = NOW();

-- SHOW TABLE STATUS LIKE 'Cat_Roles';

ALTER TABLE `Cat_Roles` AUTO_INCREMENT = 1;

-- SHOW TABLE STATUS LIKE 'Cat_Roles';

-- SELECT * FROM `Cat_Roles` /*LIMIT 0, 3000*/;
/* ------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------- */

LOAD DATA INFILE '/var/lib/mysql-files/INFO-USUARIO-FINAL.csv'
INTO TABLE `Usuarios`
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ';'
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(`Ficha`,
`Email`,
`Contraseña`,
`Fk_Id_InfoPersonal`,
`Fk_Rol`)
SET
    `Activo` = 1,
    `created_at` = NOW(),
    `updated_at` = NOW();

-- SHOW TABLE STATUS LIKE 'Usuarios';

ALTER TABLE `Usuarios` AUTO_INCREMENT = 1;

-- SHOW TABLE STATUS LIKE 'Usuarios';

-- SELECT * FROM `Usuarios` /*LIMIT 0, 3000*/;
/* ------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------- */

LOAD DATA INFILE '/var/lib/mysql-files/CATALOGO-ESTATUS-CAPACITACIONES-FINAL.csv'
INTO TABLE `Cat_Estatus_Capacitacion`
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ';'
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(
@Var_Codigo,
@Var_Nombre,      -- Leemos en variable temporal
@Var_Descripcion,  -- Leemos en variable temporal
@Es_Final
)
SET
	`Codigo` = NULLIF(TRIM(@Var_Codigo), ''), -- Dejamos el código vacio explícitamente
    `Nombre` = TRIM(@Var_Nombre), -- Limpiamos espacios
    `Descripcion` = NULLIF(TRIM(@Var_Descripcion), ''),
/* LÓGICA DE NEGOCIO: */
    /* Respetamos tu 0 o 1 del CSV. Si viniera vacío, asumimos 0 (En proceso) */
    `Es_Final`    = IF(TRIM(@Es_Final) = '' OR @Es_Final IS NULL, 0, @Es_Final),    `Activo` = 1,
    `created_at` = NOW(),
    `updated_at` = NOW();

-- SHOW TABLE STATUS LIKE 'Cat_Estatus_Capacitacion';

ALTER TABLE `Cat_Estatus_Capacitacion` AUTO_INCREMENT = 1;

-- SHOW TABLE STATUS LIKE 'Cat_Estatus_Capacitacion';

-- SELECT * FROM `Cat_Estatus_Capacitacion` /*LIMIT 0, 3000*/;
/* ------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------- */

LOAD DATA INFILE '/var/lib/mysql-files/CATALOGO-MODALIDAD-CAPACITACIONES-FINAL.csv'
INTO TABLE `Cat_Modalidad_Capacitacion`
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ';'
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(@Var_Codigo,
@Var_Nombre,      -- Leemos en variable temporal
@Var_Descripcion  -- Leemos en variable temporal
)
SET
	`Codigo` = NULLIF(TRIM(@Var_Codigo), ''), -- Dejamos el código vacio explícitamente
    `Nombre` = TRIM(@Var_Nombre), -- Limpiamos espacios
    `Descripcion` = NULLIF(TRIM(@Var_Descripcion), ''),
    `Activo` = 1,
    `created_at` = NOW(),
    `updated_at` = NOW();

-- SHOW TABLE STATUS LIKE 'Cat_Modalidad_Capacitacion';

-- SELECT * FROM `Cat_Modalidad_Capacitacion` /*LIMIT 0, 3000*/;
/* ------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------- */

LOAD DATA INFILE '/var/lib/mysql-files/CATALOGO-CASES-SEDES-FINAL.csv'
INTO TABLE `Cat_Cases_Sedes`
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ';'
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(
  @Var_Codigo,
  @Var_Nombre,
  @Aulas,
  @Salas,
  @Alberca,
  @CampoPracticas_Escenario,
  @Muelle_Entrenamiento_Botes,
  @BoteSalvavida_Capacidad,
  @Capacidad_Total,
  @DescripcionDireccion,
  `Fk_Id_Municipio`  -- <--- DIRECTO (Sin @, porque el CSV trae el dato seguro)
)
SET
    /* 1. CÓDIGO (No viene en CSV, se queda NULL para cumplir UNIQUE) */
	`Codigo` = NULLIF(TRIM(@Var_Codigo), ''), -- Dejamos el código vacio explícitamente
	`Nombre` = TRIM(@Var_Nombre), -- Limpiamos espacios

    /* 2. INFRAESTRUCTURA (Limpieza: Vacío '' se convierte en 0) */
    `Aulas`                        = IF(@Aulas = '', 0, @Aulas),
    `Salas`                        = IF(@Salas = '', 0, @Salas),
    `Alberca`                      = IF(@Alberca = '', 0, @Alberca),
    `CampoPracticas_Escenario`     = IF(@CampoPracticas_Escenario = '', 0, @CampoPracticas_Escenario),
    `Muelle_Entrenamiento_Botes`   = IF(@Muelle_Entrenamiento_Botes = '', 0, @Muelle_Entrenamiento_Botes),
    `BoteSalvavida_Capacidad`      = IF(@BoteSalvavida_Capacidad = '', 0, @BoteSalvavida_Capacidad),
    `Capacidad_Total`              = IF(@Capacidad_Total = '', 0, @Capacidad_Total),

    /* 3. DIRECCIÓN (Texto) */
    `DescripcionDireccion`         = NULLIF(@DescripcionDireccion, ''),

    /* 4. METADATOS */
    `Activo`     = 1,
    `created_at` = NOW(),
    `updated_at` = NOW();

/* Verificación Final 
SHOW WARNINGS; -- Útil para ver si hubo conversiones raras
*/

-- SHOW TABLE STATUS LIKE 'Cat_Cases_Sedes';

ALTER TABLE `Cat_Cases_Sedes` AUTO_INCREMENT = 1;

-- SHOW TABLE STATUS LIKE 'Cat_Cases_Sedes';

-- SELECT * FROM `Cat_Cases_Sedes` /*LIMIT 0, 3000*/;
/* ------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------- */

LOAD DATA INFILE '/var/lib/mysql-files/CATALOGO-TIPO-CAPACITACIONES-FINAL.csv'
INTO TABLE `Cat_Tipos_Instruccion_Cap`
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ';'
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(@Var_Nombre,      -- Leemos en variable temporal
@Var_Descripcion  -- Leemos en variable temporal
)
SET
    `Nombre`      = TRIM(@Var_Nombre), -- Limpiamos espacios
    `Descripcion` = NULLIF(TRIM(@Var_Descripcion), ''),
    `Activo` = 1,
    `created_at` = NOW(),
    `updated_at` = NOW();

-- SHOW TABLE STATUS LIKE 'Cat_Tipo_Capacitacion';

ALTER TABLE `Cat_Tipos_Instruccion_Cap` AUTO_INCREMENT = 1;

-- SHOW TABLE STATUS LIKE 'Cat_Tipo_Capacitacion';

-- SELECT * FROM `Cat_Tipo_Capacitacion` /*LIMIT 0, 3000*/;
/* ------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------- */

LOAD DATA INFILE '/var/lib/mysql-files/CATALOGO-CAPACITACIONES-FINAL.csv'
INTO TABLE `Cat_Temas_Capacitacion`
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ';'
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(@Var_Codigo,
@Var_Nombre,      -- Leemos en variable temporal
@Var_Descripcion,  -- Leemos en variable temporal
@Var_Duracion_Horas,
@Fk_Id_CatTipoInstCap)
SET
	`Codigo` = NULLIF(TRIM(@Var_Codigo), ''), -- <--- Limpiamos y convertimos vacíos a NULL
    `Nombre` = TRIM(@Var_Nombre), -- Limpiamos espacios
    `Descripcion` = NULLIF(TRIM(@Var_Descripcion), ''),
    /* LÓGICA DE CARGA */
    /* Si está vacío, se guarda NULL. Si tiene dato, se guarda el número. */
    `Duracion_Horas`   = NULLIF(TRIM(@Var_Duracion_Horas), ''),
    `Fk_Id_CatTipoInstCap` = NULLIF(@Fk_Id_CatTipoInstCap, ''),
    `Activo` = 1,
    `created_at` = NOW(),
    `updated_at` = NOW();

-- SHOW TABLE STATUS LIKE 'Cat_Capacitacion';

ALTER TABLE `Cat_Temas_Capacitacion` AUTO_INCREMENT = 1;

-- SHOW TABLE STATUS LIKE 'Cat_Capacitacion';

-- SELECT * FROM `Cat_Capacitacion` /*LIMIT 0, 3000*/;

-- ----------------------------------------------------------------------------------------------
-- ----------------------------------------------------------------------------------------------

-- Comando de carga masiva
LOAD DATA INFILE '/var/lib/mysql-files/CATALOGO-ESTATUS-PARTICIPANTE-FINAL.csv'
INTO TABLE `Cat_Estatus_Participante`
CHARACTER SET utf8mb4           -- Para que reconozca acentos y ñ
FIELDS TERMINATED BY ';'        -- Las columnas se separan por coma
OPTIONALLY ENCLOSED BY '"'      -- Por si algún texto tiene comillas
LINES TERMINATED BY '\n'      -- Salto de línea (en Windows suele ser \r\n)
IGNORE 1 ROWS                   -- Saltamos la primera fila (los encabezados)
(@Var_Codigo,
@Var_Nombre,      -- Leemos en variable temporal
@Var_Descripcion  -- Leemos en variable temporal
)
SET
	`Codigo` = NULLIF(TRIM(@Var_Codigo), ''), -- Dejamos el código vacio explícitamente
    `Nombre`      = TRIM(@Var_Nombre), -- Limpiamos espacios
    `Descripcion` = NULLIF(TRIM(@Var_Descripcion), ''),
    `Activo` = 1,                 -- Forzamos que se guarden como activos
    `created_at` = NOW(),         -- Ponemos la fecha actual
    `updated_at` = NOW();         -- Ponemos la fecha actual

-- SHOW TABLE STATUS LIKE 'Cat_Estatus_Participante';

ALTER TABLE `Cat_Estatus_Participante` AUTO_INCREMENT = 1;

-- SHOW TABLE STATUS LIKE 'Cat_Estatus_Participante';

-- SELECT * FROM `Cat_Estatus_Participante` /*LIMIT 0, 3000*/;
/* ------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------- */
