USE `PICADE`;

/* ------------------------------------------------------------------------------------------------------ */
/* CREACION DE VISTAS Y PROCEDIMIENTOS DE ALMACENADO PARA LA BASE DE DATOS*/
/* ------------------------------------------------------------------------------------------------------ */

/* ======================================================================================================
   1. VIEW: Vista_Centros_Trabajo
   ======================================================================================================
   OBJETIVO GENERAL
   ----------------
   Consolidar la información operativa de los Centros de Trabajo (CT) con su información geográfica,
   implementando un patrón de **Reutilización de Vistas** (DRY - Don't Repeat Yourself).

   ARQUITECTURA MODULAR
   --------------------
   En lugar de repetir los JOINs a Municipio, Estado y País, esta vista hace un JOIN directo
   con `Vista_Direcciones`.
   
   Ventajas:
   1. Mantenibilidad: Si cambia la lógica de cómo se muestra una dirección (ej: formato del país),
      se actualiza `Vista_Direcciones` y automáticamente se refleja aquí.
   2. Legibilidad: El código SQL es mucho más limpio y semántico.

   DECISIÓN CRÍTICA DE SEGURIDAD (LEFT JOIN)
   -----------------------------------------
   Esta vista utiliza **LEFT JOIN** para unir `Cat_Centros_Trabajo` con `Vista_Direcciones`.
   
   ¿Por qué LEFT JOIN y no INNER JOIN?
   -----------------------------------
   - Integridad de Visualización (Safety Net): En procesos de migración de datos o cargas masivas históricas,
     es posible que existan Centros de Trabajo con `Fk_Id_Municipio_CatCT` en NULL o apuntando a un ID inexistente.
   - Si usáramos INNER JOIN, esos registros "sucios" desaparecerían de la vista, creando "registros fantasmas"
     que el administrador no podría ver ni corregir.
   - Con LEFT JOIN, garantizamos que el Admin vea TODOS los CTs. Los que tengan error de ubicación
     mostrarán NULL en los campos geográficos, alertando visualmente que requieren corrección.

   DICCIONARIO DE DATOS (CAMPOS DEVUELTOS)
   ---------------------------------------
   [Entidad Principal: Centro de Trabajo]
   - Id_CentroTrabajo:          ID único (PK).
   - Codigo_CT:                 Clave interna del centro (ej: 'CT-101').
   - Nombre_CT:                 Nombre oficial.
   - Descripcion_Direccion_CT:  Texto libre (Calle, Número, CP) para referencia humana.
   
   [Datos Geográficos - Heredados de Vista_Direcciones]
   - Codigo_Municipio, Nombre_Municipio
   - Codigo_Estado, Nombre_Estado
   - Codigo_Pais, Nombre_Pais
   
   [Metadatos]
   - Estatus_CT:                1 = Operativo, 0 = Baja Lógica.
   ====================================================================================================== */

-- DROP VIEW IF EXISTS `PICADE`.`Vista_Centros_Trabajo`;

CREATE OR REPLACE
    ALGORITHM = UNDEFINED 
    SQL SECURITY DEFINER
VIEW `PICADE`.`Vista_Centros_Trabajo` AS
    SELECT 
        /* Datos Propios del Centro de Trabajo */
        `CT`.`Id_CatCT`             AS `Id_CentroTrabajo`,
        `CT`.`Codigo`               AS `Codigo_CT`,
        `CT`.`Nombre`               AS `Nombre_CT`,
        `CT`.`Direccion_Fisica`     AS `Descripcion_Direccion_CT`,
        
        /* Datos Geográficos Reutilizados (Modularidad) */
        `Ubi`.`Codigo_Municipio`    AS `Codigo_Municipio`,
        -- `Ubi`.`Nombre_Municipio`    AS `Nombre_Municipio`,
        `Ubi`.`Codigo_Estado`       AS `Codigo_Estado`,
        -- `Ubi`.`Nombre_Estado`       AS `Nombre_Estado`,
        `Ubi`.`Codigo_Pais`         AS `Codigo_Pais`,
        -- `Ubi`.`Nombre_Pais`         AS `Nombre_Pais`,
        
        /* Estatus */
        `CT`.`Activo`               AS `Estatus_CT`
    FROM
        `PICADE`.`Cat_Centros_Trabajo` `CT`
        /* LEFT JOIN Estratégico: Permite visualizar CTs con errores de ubicación para su corrección */
        LEFT JOIN `PICADE`.`Vista_Direcciones` `Ubi` 
            ON `CT`.`Fk_Id_Municipio_CatCT` = `Ubi`.`Id_Municipio`;

/* ============================================================================================
   PROCEDIMIENTO: SP_RegistrarCentroTrabajo
   ============================================================================================
   OBJETIVO
   --------
   Registrar un nuevo Centro de Trabajo (CT) en el catálogo, asegurando la consistencia total 
   de los datos y manejando escenarios complejos de duplicidad y concurrencia.

   REGLAS DE NEGOCIO (EL CONTRATO)
   -------------------------------
   1. INTEGRIDAD DEL PADRE (MUNICIPIO):
      - El Centro de Trabajo DEBE pertenecer a un Municipio válido y ACTIVO.
      - Se aplica un bloqueo de lectura (FOR UPDATE) al Municipio para asegurar que
        nadie lo desactive justo en el milisegundo en que estamos registrando el CT.

   2. IDENTIDAD PRIMARIA (CÓDIGO ÚNICO GLOBAL):
      - Regla: El campo 'Codigo' es único en toda la tabla (Constraint `Uk_Codigo_CatCT`).
      - Validación: Buscamos si el código ya existe.
      - Resolución:
         * Si existe y (Nombre + Municipio) coinciden -> REUTILIZAR/REACTIVAR.
         * Si existe y los datos NO coinciden -> ERROR (Conflicto: Código ya usado por otro CT).

   3. IDENTIDAD SECUNDARIA (NOMBRE + MUNICIPIO):
      - Regla: No pueden existir dos CTs con el mismo Nombre en el mismo Municipio
        (Constraint `Uk_Nombre_Municipio_CT`).
      - Validación: Si el código es nuevo, buscamos por Nombre + Municipio.
      - Resolución:
         * Si encontramos coincidencia -> ERROR (Conflicto: Ya existe ese lugar físico, 
           pero intentaste registrarlo con un Código diferente al que ya tiene).

   4. MANEJO DE CONCURRENCIA (RACE CONDITIONS - ERROR 1062):
      - Problema: Dos usuarios envían el mismo registro al mismo tiempo. 
        Ambos pasan los SELECT iniciales (porque no existe aún). Ambos hacen INSERT.
        Uno gana, el otro falla con error 1062 (Duplicate Key).
      - Solución (Re-Resolve):
        El SP atrapa el error 1062, hace rollback silencioso, busca el registro que acaba
        de crear el otro usuario y lo devuelve como "REUSADA" o "REACTIVADA".
        El usuario final nunca ve un error técnico.

   RESULTADO
   ---------
   Retorna:
     - Mensaje (Feedback para el usuario)
     - Id_CatCT (El ID del registro, sea nuevo o reutilizado)
     - Accion ('CREADA', 'REACTIVADA', 'REUSADA')
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_RegistrarCentroTrabajo`$$
CREATE PROCEDURE `SP_RegistrarCentroTrabajo`(
    IN _Codigo           VARCHAR(50),
    IN _Nombre           VARCHAR(255),
    IN _Direccion_Fisica VARCHAR(255),
    IN _Id_Municipio     INT
)
SP: BEGIN
    /* ----------------------------------------------------------------------------------------
       VARIABLES DE TRABAJO
       ---------------------------------------------------------------------------------------- */
    /* Para almacenar datos del registro encontrado (si existe) */
    DECLARE v_Id_CT         INT DEFAULT NULL;
    DECLARE v_Codigo        VARCHAR(50) DEFAULT NULL;
    DECLARE v_Nombre        VARCHAR(255) DEFAULT NULL;
    DECLARE v_Id_Mun        INT DEFAULT NULL;
    DECLARE v_Activo        TINYINT(1) DEFAULT NULL;

    /* Para validación del Municipio (Padre) */
    DECLARE v_Mun_Existe    INT DEFAULT NULL;
    DECLARE v_Mun_Activo    TINYINT(1) DEFAULT NULL;

    /* Bandera para detectar error de concurrencia (1062) */
    DECLARE v_Dup           TINYINT(1) DEFAULT 0;

    /* ----------------------------------------------------------------------------------------
       HANDLERS (MANEJO DE ERRORES)
       ---------------------------------------------------------------------------------------- */
    /* 1. Handler para Duplicados (1062):
          Evita que el SP aborte. Marca la bandera v_Dup para que podamos manejarlo. */
    DECLARE CONTINUE HANDLER FOR 1062
    BEGIN
        SET v_Dup = 1;
    END;

    /* 2. Handler Genérico (SQLEXCEPTION):
          Para cualquier otro error (ej: conexión, disco lleno), hacemos Rollback y salimos. */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    /* ----------------------------------------------------------------------------------------
       NORMALIZACIÓN Y LIMPIEZA DE DATOS
       ---------------------------------------------------------------------------------------- */
    SET _Codigo           = NULLIF(TRIM(_Codigo), '');
    SET _Nombre           = NULLIF(TRIM(_Nombre), '');
    SET _Direccion_Fisica = NULLIF(TRIM(_Direccion_Fisica), '');
    
    /* Si envían 0 o negativo como ID, lo tratamos como NULL */
    IF _Id_Municipio <= 0 THEN SET _Id_Municipio = NULL; END IF;

    /* ----------------------------------------------------------------------------------------
       VALIDACIONES DE ENTRADA (OBLIGATORIOS)
       ---------------------------------------------------------------------------------------- */
    IF _Codigo IS NULL OR _Nombre IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Código y Nombre del Centro de Trabajo son obligatorios.';
    END IF;

    IF _Id_Municipio IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Debe seleccionar un Municipio válido.';
    END IF;

    /* ========================================================================================
       INICIO DE LA TRANSACCIÓN
       ======================================================================================== */
    START TRANSACTION;

    /* ----------------------------------------------------------------------------------------
       PASO 1) VALIDAR INTEGRIDAD DEL PADRE (MUNICIPIO)
       - Usamos FOR UPDATE para bloquear la fila del municipio.
       - Esto asegura que nadie lo desactive o elimine mientras nosotros registramos al hijo.
       ---------------------------------------------------------------------------------------- */
    SET v_Mun_Existe = NULL;
    
    SELECT 1, `Activo` 
      INTO v_Mun_Existe, v_Mun_Activo
    FROM `Municipio`
    WHERE `Id_Municipio` = _Id_Municipio
    LIMIT 1
    FOR UPDATE;

    IF v_Mun_Existe IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: El Municipio seleccionado no existe.';
    END IF;

    IF v_Mun_Activo = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: El Municipio seleccionado está INACTIVO. No se pueden registrar Centros de Trabajo en él.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 2) RESOLVER POR CÓDIGO (REGLA PRIMARIA - GLOBAL UNIQUE)
       - Buscamos si el Código ya existe en el sistema.
       - Si existe, verificamos consistencia con Nombre y Municipio.
       ---------------------------------------------------------------------------------------- */
    SET v_Id_CT = NULL, v_Nombre = NULL, v_Id_Mun = NULL, v_Activo = NULL;

    SELECT `Id_CatCT`, `Nombre`, `Fk_Id_Municipio_CatCT`, `Activo`
      INTO v_Id_CT, v_Nombre, v_Id_Mun, v_Activo
    FROM `Cat_Centros_Trabajo`
    WHERE `Codigo` = _Codigo
    LIMIT 1
    FOR UPDATE;

    IF v_Id_CT IS NOT NULL THEN
        /* 2.1) Validar Consistencia de Nombre */
        IF v_Nombre <> _Nombre THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Conflicto de Datos. El Código ya existe pero pertenece a un Centro con diferente Nombre.';
        END IF;

        /* 2.2) Validar Consistencia de Municipio (usamos <=> para comparar NULLs de forma segura) */
        IF NOT (v_Id_Mun <=> _Id_Municipio) THEN
             SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Conflicto de Datos. El Código ya existe pero está asignado a un Municipio diferente.';
        END IF;

        /* 2.3) Autosanación: Reactivar si estaba borrado, o Reusar si está activo */
        IF v_Activo = 0 THEN
            UPDATE `Cat_Centros_Trabajo` 
            SET `Activo` = 1, 
                `Direccion_Fisica` = COALESCE(_Direccion_Fisica, `Direccion_Fisica`), /* Actualiza dirección solo si enviaron una nueva */
                `updated_at` = NOW() 
            WHERE `Id_CatCT` = v_Id_CT;
            
            COMMIT; 
            SELECT 'Centro de Trabajo reactivado exitosamente' AS Mensaje, v_Id_CT AS Id_CatCT, 'REACTIVADA' AS Accion; 
            LEAVE SP;
        ELSE
            COMMIT; 
            SELECT 'El Centro de Trabajo ya existe y está activo.' AS Mensaje, v_Id_CT AS Id_CatCT, 'REUSADA' AS Accion; 
            LEAVE SP;
        END IF;
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 3) RESOLVER POR NOMBRE + MUNICIPIO (REGLA SECUNDARIA)
       - Si llegamos aquí, el Código es NUEVO.
       - Ahora verificamos: ¿Ya existe un CT con ese Nombre en ese Municipio?
       ---------------------------------------------------------------------------------------- */
    SET v_Id_CT = NULL, v_Codigo = NULL, v_Activo = NULL;

    SELECT `Id_CatCT`, `Codigo`, `Activo`
      INTO v_Id_CT, v_Codigo, v_Activo
    FROM `Cat_Centros_Trabajo`
    WHERE `Nombre` = _Nombre
      AND `Fk_Id_Municipio_CatCT` = _Id_Municipio /* Comparación estricta porque Id_Mun es obligatorio aquí */
    LIMIT 1
    FOR UPDATE;

    IF v_Id_CT IS NOT NULL THEN
        /* Conflicto Lógico: El lugar ya existe (Nombre+Mun), pero el usuario mandó un código diferente. */
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Conflicto de Datos. Ya existe un Centro de Trabajo con ese Nombre en este Municipio, pero tiene un Código diferente.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 4) INSERTAR (CREACIÓN)
       - Si pasamos las validaciones, procedemos al INSERT.
       - No incluimos 'Activo' (la tabla pone 1 por default).
       - No incluimos 'created_at' (la tabla pone timestamp por default).
       ---------------------------------------------------------------------------------------- */
    SET v_Dup = 0;

    INSERT INTO `Cat_Centros_Trabajo` 
        (`Codigo`, `Nombre`, `Direccion_Fisica`, `Fk_Id_Municipio_CatCT`)
    VALUES 
        (_Codigo, _Nombre, _Direccion_Fisica, _Id_Municipio);

    /* Si v_Dup sigue en 0, el insert fue exitoso */
    IF v_Dup = 0 THEN
        COMMIT; 
        SELECT 'Centro de Trabajo registrado exitosamente' AS Mensaje, 
               LAST_INSERT_ID() AS Id_CatCT, 
               'CREADA' AS Accion; 
        LEAVE SP;
    END IF;

    /* ========================================================================================
       PASO 5) RE-RESOLVE (MANEJO AVANZADO DE CONCURRENCIA - ERROR 1062)
       - Si llegamos aquí, v_Dup = 1.
       - Significa que entre nuestros SELECTs y nuestro INSERT, alguien más insertó el registro.
       - Estrategia: ROLLBACK para limpiar y buscar al ganador.
       ======================================================================================== */
    ROLLBACK;
    
    START TRANSACTION;

    /* 5.1) Intento de Recuperación: Buscar por Código (lo más probable en race condition) */
    SET v_Id_CT = NULL, v_Activo = NULL, v_Nombre = NULL;

    SELECT `Id_CatCT`, `Activo`, `Nombre`
      INTO v_Id_CT, v_Activo, v_Nombre
    FROM `Cat_Centros_Trabajo`
    WHERE `Codigo` = _Codigo
    LIMIT 1
    FOR UPDATE;

    IF v_Id_CT IS NOT NULL THEN
        /* Verificación paranoica: asegurarnos que sea el mismo dato lógico */
        IF v_Nombre <> _Nombre THEN
             SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR CRÍTICO: Concurrencia detectada con conflicto de datos (Código duplicado con diferente nombre).';
        END IF;

        /* Reactivar si es necesario */
        IF v_Activo = 0 THEN
            UPDATE `Cat_Centros_Trabajo` SET `Activo` = 1, `updated_at` = NOW() WHERE `Id_CatCT` = v_Id_CT;
            COMMIT; 
            SELECT 'Centro de Trabajo reactivado (re-resuelto)' AS Mensaje, v_Id_CT AS Id_CatCT, 'REACTIVADA' AS Accion; 
            LEAVE SP;
        END IF;

        /* Reusar */
        COMMIT; 
        SELECT 'Centro de Trabajo ya existía (reusado por concurrencia)' AS Mensaje, v_Id_CT AS Id_CatCT, 'REUSADA' AS Accion; 
        LEAVE SP;
    END IF;

    /* 5.2) Si no lo encontramos tras el fallo 1062, es un error fatal de sistema */
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA: Fallo de concurrencia no recuperable (1062 sin registro visible).';

END$$

DELIMITER ;

/* ============================================================================================
   SECCIÓN: CONSULTAS ESPECÍFICAS (PARA EDICIÓN / DETALLE)
   ============================================================================================
   Estas rutinas son clave para la UX. No solo devuelven el dato pedido, sino todo el 
   contexto jerárquico necesario para que el formulario de edición se autocomplete.
   ============================================================================================ */
   
/* ============================================================================================
   PROCEDIMIENTO: SP_ConsultarCentroTrabajoEspecifico
   ============================================================================================
   OBJETIVO DE NEGOCIO
   -------------------
   Recuperar la "Hoja de Vida" completa de un Centro de Trabajo (CT) para su visualización 
   detallada o para precargar el formulario de "Editar Centro de Trabajo".

   ¿QUÉ PROBLEMA RESUELVE? (EL RETO DEL DROPDOWN EN CASCADA)
   ---------------------------------------------------------
   En la base de datos, el CT solo conoce a su padre inmediato: el Municipio (`Fk_Id_Municipio_CatCT`).
   Sin embargo, en la pantalla de edición, el usuario ve tres selectores:
      [ País ] -> [ Estado ] -> [ Municipio ]
   
   Si solo devolvemos el ID del Municipio, el frontend no sabe qué País ni qué Estado 
   seleccionar automáticamente. Este SP reconstruye esa cadena genealógica hacia atrás:
      CT -> Municipio (Hijo) -> Estado (Padre) -> País (Abuelo).

   ESTRATEGIA DE INTEGRIDAD DE DATOS (LEFT JOIN)
   ---------------------------------------------
   Se utilizan `LEFT JOIN` en lugar de `INNER JOIN` para la cadena geográfica.
   
   ¿Por qué?
   - Robustez ante Datos Migrados: Si se cargó un CT desde Excel con un Municipio erróneo 
     o nulo (NULL), un INNER JOIN ocultaría el registro, haciendo imposible editarlo para corregirlo.
   - Con LEFT JOIN, recuperamos los datos del CT incluso si su ubicación está rota. 
     Esto permite abrir la pantalla de edición y asignar la ubicación correcta.

   DATOS RETORNADOS
   ----------------
   1. Identidad del CT: ID, Código, Nombre, Dirección Física, Estatus.
   2. Contexto Geográfico: 
      - IDs para el valor de los <select> (Id_Pais, Id_Estado, Id_Municipio).
      - Nombres para etiquetas visuales o validación.
   3. Auditoría: Fechas de creación y actualización.

   VALIDACIONES
   ------------
   - El ID debe ser válido (>0).
   - El registro debe existir.
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ConsultarCentroTrabajoEspecifico`$$
CREATE PROCEDURE `SP_ConsultarCentroTrabajoEspecifico`(
    IN _Id_CatCT INT
)
BEGIN
    /* ----------------------------------------------------------------------------------------
       1. VALIDACIÓN DE ENTRADA (DEFENSIVE PROGRAMMING)
       Evitamos ejecutar consultas si el ID no tiene sentido.
       ---------------------------------------------------------------------------------------- */
    IF _Id_CatCT IS NULL OR _Id_CatCT <= 0 THEN
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'ERROR DE SISTEMA: El ID del Centro de Trabajo es inválido.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       2. VALIDACIÓN DE EXISTENCIA
       Verificamos rápido si el registro existe antes de hacer los JOINS costosos.
       ---------------------------------------------------------------------------------------- */
    IF NOT EXISTS (SELECT 1 FROM `Cat_Centros_Trabajo` WHERE `Id_CatCT` = _Id_CatCT) THEN
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'ERROR DE NEGOCIO: El Centro de Trabajo solicitado no existe o fue eliminado.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       3. CONSULTA PRINCIPAL (RECONSTRUCCIÓN JERÁRQUICA)
       ---------------------------------------------------------------------------------------- */
    SELECT 
        /* --- DATOS PROPIOS DEL CENTRO DE TRABAJO --- */
        `CT`.`Id_CatCT`,
        `CT`.`Codigo`           AS `Codigo_CT`,
        `CT`.`Nombre`           AS `Nombre_CT`,
        `CT`.`Direccion_Fisica`,


        /* --- NIVEL 1: MUNICIPIO (Padre directo) --- */
        `Mun`.`Id_Municipio`,
        `Mun`.`Codigo`          AS `Codigo_Municipio`,
        `Mun`.`Nombre`          AS `Nombre_Municipio`,
        `Mun`.`Activo`          AS `Estatus_Municipio`,

        /* --- NIVEL 2: ESTADO (Abuelo - Derivado del Municipio) --- */
        `Edo`.`Id_Estado`,      /* Vital para pre-seleccionar el Dropdown de Estado */
        `Edo`.`Codigo`          AS `Codigo_Estado`,
        `Edo`.`Nombre`          AS `Nombre_Estado`,

        /* --- NIVEL 3: PAÍS (Bisabuelo - Derivado del Estado) --- */
        `Pais`.`Id_Pais`,       /* Vital para pre-seleccionar el Dropdown de País */
        `Pais`.`Codigo`         AS `Codigo_Pais`,
        `Pais`.`Nombre`         AS `Nombre_Pais`,

        `CT`.`Activo`           AS `Estatus_CT`,
        `CT`.`created_at`,
        `CT`.`updated_at`
        
    FROM `Cat_Centros_Trabajo` `CT`
    
    /* LEFT JOIN 1: Intentamos obtener el Municipio */
    LEFT JOIN `Municipio` `Mun` 
        ON `CT`.`Fk_Id_Municipio_CatCT` = `Mun`.`Id_Municipio`
    
    /* LEFT JOIN 2: Si tenemos Municipio, intentamos obtener su Estado */
    LEFT JOIN `Estado` `Edo`    
        ON `Mun`.`Fk_Id_Estado` = `Edo`.`Id_Estado`
    
    /* LEFT JOIN 3: Si tenemos Estado, intentamos obtener su País */
    LEFT JOIN `Pais` `Pais`     
        ON `Edo`.`Fk_Id_Pais` = `Pais`.`Id_Pais`

    WHERE `CT`.`Id_CatCT` = _Id_CatCT
    LIMIT 1;

END$$

DELIMITER ;

/* ============================================================================================
   SECCIÓN: LISTADOS PARA DROPDOWNS (SOLO REGISTROS ACTIVOS)
   ============================================================================================
   Estas rutinas son consumidas por los formularios de captura (Frontend).
   Su objetivo es ofrecer al usuario solo las opciones válidas y vigentes.
   ============================================================================================ */

/* ============================================================================================
   PROCEDIMIENTO: SP_ListarCTActivos
   ============================================================================================
   OBJETIVO
   --------
   Obtener la lista simple de Centros de Trabajo disponibles para ser asignados.
   
   CASOS DE USO
   ------------
   1. Formulario de "Alta de Empleado": Para seleccionar dónde trabaja.
   2. Formulario de "Programación de Curso": Para seleccionar dónde se impartirá.
   3. Filtros de Reportes Operativos.

   REGLAS DE NEGOCIO (EL CONTRATO)
   -------------------------------
   1. FILTRO DE ESTATUS: Solo se devuelven registros con `Activo = 1`.
      - Los CTs dados de baja (borrado lógico) quedan ocultos para el usuario operativo.
   2. ORDENAMIENTO: Alfabético por Nombre, para facilitar la búsqueda visual en listas largas.
   3. LIGEREZA: Solo devuelve ID, Código y Nombre. No hace JOINs complejos porque 
      el dropdown no necesita saber la dirección exacta, solo identificar el lugar.

   RETORNO
   -------
   - Id_CatCT (Value del Option)
   - Codigo (Texto auxiliar)
   - Nombre (Label del Option)
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ListarCTActivos`$$
CREATE PROCEDURE `SP_ListarCTActivos`()
BEGIN
    SELECT 
        `Id_CatCT`, 
        `Codigo`, 
        `Nombre` 
    FROM `Cat_Centros_Trabajo` 
    WHERE `Activo` = 1 
    ORDER BY `Nombre` ASC;
END$$

DELIMITER ;

/* ============================================================================================
   SECCIÓN: LISTADOS PARA ADMINISTRACIÓN (TABLAS CRUD)
   ============================================================================================
   Estas rutinas son consumidas por los Paneles de Control (Grid/Tabla de Mantenimiento).
   Su objetivo es dar visibilidad total sobre el catálogo para auditoría y gestión.
   ============================================================================================ */

/* ============================================================================================
   PROCEDIMIENTO: SP_ListarCTAdmin
   ============================================================================================
   OBJETIVO
   --------
   Obtener el inventario completo de Centros de Trabajo, con todos sus detalles y estatus.

   CASOS DE USO
   ------------
   - Pantalla principal del Módulo "Administrar Centros de Trabajo".
   - Permite al Admin ver qué CTs existen, cuáles están inactivos, y detectar errores de captura.

   ARQUITECTURA (USO DE VISTAS)
   ----------------------------
   Este SP se apoya en `Vista_Centros_Trabajo`.
   
   ¿Por qué usar la Vista?
   1. UBICACIÓN LEGIBLE: La vista ya hizo el trabajo duro de unir (JOIN) el CT con 
      Municipio -> Estado -> País. El Admin ve "Villahermosa, Tabasco" en lugar de "ID: 45".
   2. TOLERANCIA A FALLOS: La vista usa LEFT JOIN. Si un CT tiene mal la ubicación, 
      aparecerá en la lista con campos vacíos, permitiendo al Admin identificarlo y corregirlo.
      (Si usáramos INNER JOIN aquí, los registros dañados desaparecerían y serían "fantasmas").

   ORDENAMIENTO ESTRATÉGICO
   ------------------------
   1. Por Estatus (DESC): Los Activos (1) aparecen primero. Los Inactivos (0) al final.
   2. Por Nombre (ASC): Orden alfabético secundario.

   RETORNO
   -------
   Devuelve todas las columnas definidas en `Vista_Centros_Trabajo`:
   - Identidad (ID, Código, Nombre)
   - Dirección (Calle, Num)
   - Ubicación (Mun, Edo, Pais)
   - Metadatos (Estatus, Fechas)
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ListarCTAdmin`$$
CREATE PROCEDURE `SP_ListarCTAdmin`()
BEGIN
    SELECT * FROM `Vista_Centros_Trabajo` 
    ORDER BY `Estatus_CT` DESC, `Nombre_CT` ASC;
END$$

DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_EditarCentroTrabajo
   ============================================================================================
   
   OBJETIVO DE NEGOCIO
   -------------------
   Modificar la información de un Centro de Trabajo (CT), permitiendo cambios en su identidad
   (Código, Nombre) y, crucialmente, su REUBICACIÓN GEOGRÁFICA completa.

   ESCENARIOS DE USO (UX)
   ----------------------
   1. Corrección Simple: Corregir un error ortográfico en el Nombre.
   2. Reingeniería de Claves: Cambiar el Código Administrativo.
   3. Mudanza Local: Cambiar de Municipio dentro del mismo Estado.
   4. Mudanza Internacional/Nacional: Cambiar de País o Estado.
      - El usuario selecciona: País (ej: USA) -> Estado (ej: Texas) -> Municipio (ej: Houston).
      - El sistema debe validar que esa cadena jerárquica sea válida y activa.

   ARQUITECTURA DE SEGURIDAD Y CONCURRENCIA
   ----------------------------------------
   1. BLOQUEO PESIMISTA (Pessimistic Locking):
      - `SELECT ... FOR UPDATE` sobre el CT a editar.
      - "Congela" la fila para evitar que otro admin la borre o edite simultáneamente.

   2. VALIDACIÓN ATÓMICA DE JERARQUÍA GEOGRÁFICA:
      - Aunque solo guardamos `Id_Municipio`, recibimos `Id_Pais` e `Id_Estado`.
      - Hacemos un JOIN validador para asegurar que:
        a) El Municipio pertenece a ese Estado.
        b) El Estado pertenece a ese País.
        c) Los tres niveles están ACTIVOS (1).
      - Esto protege contra inyecciones de datos incoherentes desde el frontend.

   3. INTEGRIDAD DE DUPLICADOS (Excluyendo al propio registro):
      - Verificamos unicidad Global del Código.
      - Verificamos unicidad Local (Nombre + Municipio).
      - Siempre agregamos `AND Id_CatCT <> _Id_CatCT` para no chocar con nosotros mismos.

   4. MANEJO DE COLISIONES (Error 1062 - Race Condition):
      - Si dos usuarios intentan asignar el mismo Código al mismo tiempo:
        * Usuario A gana.
        * Usuario B choca en el UPDATE (Error 1062).
        * El SP captura el error y devuelve una respuesta controlada ("CONFLICTO") indicando
          qué campo causó el problema y quién ganó.

   5. DETECCIÓN DE "SIN CAMBIOS" (Idempotencia):
      - Si los datos nuevos son idénticos a los actuales, retornamos éxito inmediato sin
        tocar la base de datos (ahorro de I/O y Logs).

   RESULTADO
   ---------
   Retorna tabla con:
     - Mensaje: Feedback para usuario.
     - Accion: 'ACTUALIZADA', 'SIN_CAMBIOS', 'CONFLICTO'.
     - Datos de contexto (IDs anteriores y nuevos).
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_EditarCentroTrabajo`$$
CREATE PROCEDURE `SP_EditarCentroTrabajo`(
    IN _Id_CatCT             INT,           -- ID del registro a editar (PK)
    IN _Nuevo_Codigo         VARCHAR(50),   -- Nuevo Código
    IN _Nuevo_Nombre         VARCHAR(255),  -- Nuevo Nombre
    IN _Nueva_Direccion      VARCHAR(255),  -- Nueva Dirección Física
    IN _Nuevo_Id_Pais        INT,           -- Nuevo País (Contexto para validación)
    IN _Nuevo_Id_Estado      INT,           -- Nuevo Estado (Contexto para validación)
    IN _Nuevo_Id_Municipio   INT            -- Nuevo Municipio (Dato real a guardar)
)
SP: BEGIN
    /* ========================================================================================
       PARTE 0) VARIABLES DE ESTADO
       ======================================================================================== */
    /* Snapshot de los datos actuales (para comparar "Sin Cambios") */
    DECLARE v_Codigo_Act    VARCHAR(50)  DEFAULT NULL;
    DECLARE v_Nombre_Act    VARCHAR(255) DEFAULT NULL;
    DECLARE v_Dir_Act       VARCHAR(255) DEFAULT NULL;
    DECLARE v_Mun_Act       INT          DEFAULT NULL;

    /* Variables auxiliares de validación */
    DECLARE v_Existe        INT          DEFAULT NULL;
    DECLARE v_DupId         INT          DEFAULT NULL;

    /* Bandera para detectar choque 1062 en UPDATE */
    DECLARE v_Dup           TINYINT(1)   DEFAULT 0;

    /* Datos para respuesta de conflicto controlado */
    DECLARE v_Id_Conflicto    INT          DEFAULT NULL;
    DECLARE v_Campo_Conflicto VARCHAR(20)  DEFAULT NULL;

    /* ========================================================================================
       PARTE 1) HANDLERS (CONTROL DE ERRORES)
       ======================================================================================== */
    
    /* 1062 (Duplicate entry):
       No abortamos. Marcamos bandera para manejarlo al final y dar feedback útil. */
    DECLARE CONTINUE HANDLER FOR 1062
    BEGIN
        SET v_Dup = 1;
    END;

    /* SQLEXCEPTION:
       Cualquier otro error técnico (conexión, sintaxis, disco) provoca Rollback total. */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    /* ========================================================================================
       PARTE 2) NORMALIZACIÓN DE INPUTS
       ======================================================================================== */
    SET _Nuevo_Codigo    = NULLIF(TRIM(_Nuevo_Codigo), '');
    SET _Nuevo_Nombre    = NULLIF(TRIM(_Nuevo_Nombre), '');
    SET _Nueva_Direccion = NULLIF(TRIM(_Nueva_Direccion), '');

    /* Protección contra IDs inválidos */
    IF _Nuevo_Id_Pais <= 0      THEN SET _Nuevo_Id_Pais = NULL;      END IF;
    IF _Nuevo_Id_Estado <= 0    THEN SET _Nuevo_Id_Estado = NULL;    END IF;
    IF _Nuevo_Id_Municipio <= 0 THEN SET _Nuevo_Id_Municipio = NULL; END IF;

    /* ========================================================================================
       PARTE 3) VALIDACIONES BÁSICAS (FAIL FAST)
       ======================================================================================== */
    IF _Id_CatCT IS NULL OR _Id_CatCT <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA: ID de Centro de Trabajo inválido.';
    END IF;

    IF _Nuevo_Codigo IS NULL OR _Nuevo_Nombre IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN: Código y Nombre son obligatorios.';
    END IF;

    /* Validación estricta de la cadena geográfica */
    IF _Nuevo_Id_Pais IS NULL OR _Nuevo_Id_Estado IS NULL OR _Nuevo_Id_Municipio IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN: Debe seleccionar la ubicación completa (País, Estado y Municipio).';
    END IF;

    /* ========================================================================================
       PARTE 4) INICIO DE TRANSACCIÓN
       ======================================================================================== */
    START TRANSACTION;

    /* ----------------------------------------------------------------------------------------
       PASO 1: LEER Y BLOQUEAR EL REGISTRO ACTUAL
       ----------------------------------------------------------------------------------------
       - FOR UPDATE: Bloqueamos la fila del CT. Nadie más puede editarla.
       - Obtenemos los valores actuales para detectar si hubo cambios reales.
       ---------------------------------------------------------------------------------------- */
    SET v_Codigo_Act = NULL, v_Nombre_Act = NULL, v_Dir_Act = NULL, v_Mun_Act = NULL;

    SELECT `Codigo`, `Nombre`, `Direccion_Fisica`, `Fk_Id_Municipio_CatCT`
      INTO v_Codigo_Act, v_Nombre_Act, v_Dir_Act, v_Mun_Act
    FROM `Cat_Centros_Trabajo`
    WHERE `Id_CatCT` = _Id_CatCT
    LIMIT 1
    FOR UPDATE;

    IF v_Codigo_Act IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE CONCURRENCIA: El Centro de Trabajo no existe (pudo ser eliminado por otro usuario).';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 2: VALIDACIÓN ATÓMICA DE JERARQUÍA GEOGRÁFICA (JOIN ÚNICO)
       ----------------------------------------------------------------------------------------
       - Objetivo: Asegurar que el Municipio seleccionado pertenezca al Estado seleccionado, 
         y este al País seleccionado. Y que TODOS estén ACTIVOS.
       - Bloqueo: Bloqueamos la fila del Municipio destino (`FOR UPDATE`) para evitar que se 
         desactive mientras guardamos.
       - Optimización: Usamos `STRAIGHT_JOIN` para forzar el orden de validación (País->Edo->Mun).
       ---------------------------------------------------------------------------------------- */
    SET v_Existe = NULL;

    SELECT 1 INTO v_Existe
    FROM `Pais` P
    STRAIGHT_JOIN `Estado` E ON E.`Fk_Id_Pais` = P.`Id_Pais`
    STRAIGHT_JOIN `Municipio` M ON M.`Fk_Id_Estado` = E.`Id_Estado`
    WHERE P.`Id_Pais` = _Nuevo_Id_Pais       AND P.`Activo` = 1
      AND E.`Id_Estado` = _Nuevo_Id_Estado   AND E.`Activo` = 1
      AND M.`Id_Municipio` = _Nuevo_Id_Municipio AND M.`Activo` = 1
    LIMIT 1
    FOR UPDATE;

    IF v_Existe IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE INTEGRIDAD: La ubicación seleccionada es inconsistente (Municipio no pertenece al Estado/País) o contiene elementos inactivos.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 3: DETECCIÓN DE "SIN CAMBIOS"
       ----------------------------------------------------------------------------------------
       - Comparamos valores actuales vs nuevos.
       - Usamos `<=>` (Spaceship operator) para comparar NULLs en Dirección Física y Municipio.
       - Si todo es igual, salimos rápido.
       ---------------------------------------------------------------------------------------- */
    IF v_Codigo_Act = _Nuevo_Codigo 
       AND v_Nombre_Act = _Nuevo_Nombre 
       AND (v_Dir_Act <=> _Nueva_Direccion)
       AND (v_Mun_Act <=> _Nuevo_Id_Municipio) THEN
       
       COMMIT; -- Liberamos locks
       SELECT 'No se detectaron cambios en la información.' AS Mensaje, 
              'SIN_CAMBIOS' AS Accion, 
              _Id_CatCT AS Id_CatCT;
       LEAVE SP;
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 4: PRE-CHECK DE DUPLICADOS (INTEGRIDAD REFERENCIAL)
       ---------------------------------------------------------------------------------------- */
    
    /* 4.1 Conflicto Global de CÓDIGO */
    SET v_DupId = NULL;
    
    SELECT `Id_CatCT` INTO v_DupId
    FROM `Cat_Centros_Trabajo`
    WHERE `Codigo` = _Nuevo_Codigo
      AND `Id_CatCT` <> _Id_CatCT -- Importante: Excluirme a mí mismo
    LIMIT 1
    FOR UPDATE; -- Bloqueamos al posible conflictivo

    IF v_DupId IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE DUPLICIDAD: El Código ingresado ya está en uso por OTRO Centro de Trabajo.';
    END IF;

    /* 4.2 Conflicto Local de NOMBRE + MUNICIPIO */
    SET v_DupId = NULL;

    SELECT `Id_CatCT` INTO v_DupId
    FROM `Cat_Centros_Trabajo`
    WHERE `Nombre` = _Nuevo_Nombre
      AND `Fk_Id_Municipio_CatCT` = _Nuevo_Id_Municipio
      AND `Id_CatCT` <> _Id_CatCT -- Importante: Excluirme a mí mismo
    LIMIT 1
    FOR UPDATE; -- Bloqueamos al posible conflictivo

    IF v_DupId IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE DUPLICIDAD: Ya existe OTRO Centro de Trabajo con el mismo Nombre en el Municipio seleccionado.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 5: EJECUCIÓN DEL UPDATE (CRÍTICO)
       ----------------------------------------------------------------------------------------
       - Aquí es donde podría ocurrir el Error 1062 si hay una "Race Condition" perfecta.
       - Reseteamos v_Dup a 0 antes del intento.
       ---------------------------------------------------------------------------------------- */
    SET v_Dup = 0;

    UPDATE `Cat_Centros_Trabajo`
    SET `Codigo` = _Nuevo_Codigo,
        `Nombre` = _Nuevo_Nombre,
        `Direccion_Fisica` = _Nueva_Direccion,
        `Fk_Id_Municipio_CatCT` = _Nuevo_Id_Municipio
        -- updated_at se actualiza solo
    WHERE `Id_CatCT` = _Id_CatCT;

    /* ----------------------------------------------------------------------------------------
       PASO 6: MANEJO DE COLISIÓN (SI HUBO ERROR 1062)
       ----------------------------------------------------------------------------------------
       - Si v_Dup = 1, el Handler se disparó.
       - Hacemos ROLLBACK.
       - Identificamos la causa (Código o Nombre) para decirselo al usuario.
       ---------------------------------------------------------------------------------------- */
    IF v_Dup = 1 THEN
        ROLLBACK;

        SET v_Id_Conflicto = NULL;
        SET v_Campo_Conflicto = NULL;

        /* 6.1 Revisar si fue por CÓDIGO */
        SELECT `Id_CatCT` INTO v_Id_Conflicto
        FROM `Cat_Centros_Trabajo`
        WHERE `Codigo` = _Nuevo_Codigo AND `Id_CatCT` <> _Id_CatCT
        LIMIT 1;

        IF v_Id_Conflicto IS NOT NULL THEN
            SET v_Campo_Conflicto = 'CODIGO';
        ELSE
            /* 6.2 Si no fue código, fue por NOMBRE+MUNICIPIO */
            SELECT `Id_CatCT` INTO v_Id_Conflicto
            FROM `Cat_Centros_Trabajo`
            WHERE `Nombre` = _Nuevo_Nombre 
              AND `Fk_Id_Municipio_CatCT` = _Nuevo_Id_Municipio
              AND `Id_CatCT` <> _Id_CatCT
            LIMIT 1;
            
            IF v_Id_Conflicto IS NOT NULL THEN
                SET v_Campo_Conflicto = 'NOMBRE_UBICACION';
            END IF;
        END IF;

        SELECT 'Error de Concurrencia: Otro usuario guardó un registro idéntico mientras usted editaba.' AS Mensaje,
               'CONFLICTO' AS Accion,
               v_Campo_Conflicto AS Campo,
               v_Id_Conflicto AS Id_Conflicto;
        LEAVE SP;
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 7: CONFIRMACIÓN EXITOSA
       ---------------------------------------------------------------------------------------- */
    COMMIT;

    SELECT 'Centro de Trabajo actualizado correctamente' AS Mensaje,
           'ACTUALIZADA' AS Accion,
           _Id_CatCT AS Id_CatCT,
			v_Mun_Act AS Id_Municipio_Anterior,
            _Nuevo_Id_Municipio AS Id_Municipio_Nuevo;

END$$

DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_CambiarEstatusCentroTrabajo
   ============================================================================================

   OBJETIVO
   --------
   Activar/Desactivar (borrado lógico) un Centro de Trabajo (CT):
      Cat_Centros_Trabajo.Activo (1 = activo, 0 = inactivo)

   REGLAS CRÍTICAS (INTEGRIDAD DE NEGOCIO)
   ---------------------------------------
   A) Al DESACTIVAR un Centro de Trabajo (Activo=0):
      - NO se permite si tiene EMPLEADOS ACTIVOS (`Info_Personal`).
      - Esto evita la inconsistencia de tener personal asignado a un lugar que "ya no existe"
        operativamente.

   B) Al ACTIVAR un Centro de Trabajo (Activo=1) << CANDADO JERÁRQUICO
      - NO se permite si su MUNICIPIO (Padre) está INACTIVO.
      - Si el CT tiene asignado un municipio, y ese municipio fue dado de baja,
        el CT no puede operar.
      - Nota: Si el CT no tiene municipio asignado (NULL, datos sucios), se permite activar
        (asumiendo que se corregirá la ubicación después).

   CONCURRENCIA / BLOQUEOS
   -----------------------
   - Bloqueamos en orden: CENTRO DE TRABAJO -> MUNICIPIO
   - Usamos `LEFT JOIN` + `FOR UPDATE` para:
        * Asegurar el bloqueo de la fila del CT.
        * Si tiene municipio, bloquear también la fila del Municipio para evitar que
          alguien lo desactive mientras nosotros activamos el CT.
   - El uso de `LEFT JOIN` es vital aquí porque tus datos históricos pueden tener
     municipios nulos, y no queremos que el SP falle o no encuentre el registro en esos casos.

   RESULTADO
   ---------
   Retorna:
     - Mensaje: Feedback claro para el usuario.
     - Activo_Anterior / Activo_Nuevo: Para auditoría o actualización de UI.
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_CambiarEstatusCentroTrabajo`$$
CREATE PROCEDURE `SP_CambiarEstatusCentroTrabajo`(
    IN _Id_CatCT INT,
    IN _Nuevo_Estatus TINYINT -- 1 = Activo, 0 = Inactivo
)
BEGIN
    /* ----------------------------------------------------------------------------------------
       VARIABLES
       ---------------------------------------------------------------------------------------- */
    DECLARE v_Existe INT DEFAULT NULL;

    /* Estatus actual del Centro de Trabajo */
    DECLARE v_Activo_Actual TINYINT(1) DEFAULT NULL;

    /* Datos del padre (Municipio) para el candado jerárquico al ACTIVAR */
    DECLARE v_Id_Municipio INT DEFAULT NULL;
    DECLARE v_Municipio_Activo TINYINT(1) DEFAULT NULL;

    /* Auxiliar para búsqueda de dependencias (Hijos) */
    DECLARE v_Tmp INT DEFAULT NULL;

    /* ----------------------------------------------------------------------------------------
       HANDLER GENERAL
       - Si cualquier SQL falla: ROLLBACK y relanza el error real.
       ---------------------------------------------------------------------------------------- */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    /* ----------------------------------------------------------------------------------------
       VALIDACIONES DE PARÁMETROS
       ---------------------------------------------------------------------------------------- */
    IF _Id_CatCT IS NULL OR _Id_CatCT <= 0 THEN
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'ERROR: Id_CatCT inválido.';
    END IF;

    IF _Nuevo_Estatus NOT IN (0,1) THEN
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'ERROR: Estatus inválido (solo 0 o 1).';
    END IF;

    START TRANSACTION;

    /* ----------------------------------------------------------------------------------------
       1) VALIDAR EXISTENCIA Y BLOQUEAR FILAS (CT -> MUNICIPIO)
       ----------------------------------------------------------------------------------------
       - Usamos LEFT JOIN porque el CT podría no tener municipio (datos legacy).
       - FOR UPDATE bloquea el CT y, si existe el municipio, también lo bloquea.
       ---------------------------------------------------------------------------------------- */
    SELECT 
        1 AS Existe,
        CT.Activo AS Activo_CT,
        CT.Fk_Id_Municipio_CatCT AS Id_Municipio,
        M.Activo AS Activo_Municipio
    INTO 
        v_Existe,
        v_Activo_Actual,
        v_Id_Municipio,
        v_Municipio_Activo
    FROM `Cat_Centros_Trabajo` CT
    LEFT JOIN `Municipio` M ON CT.Fk_Id_Municipio_CatCT = M.Id_Municipio
    WHERE CT.Id_CatCT = _Id_CatCT
    LIMIT 1
    FOR UPDATE;

    IF v_Existe IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: El Centro de Trabajo no existe.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       2) "SIN CAMBIOS" (IDEMPOTENCIA)
       - Si ya está en el estatus solicitado, no tocamos la BD y retornamos rápido.
       ---------------------------------------------------------------------------------------- */
    IF v_Activo_Actual = _Nuevo_Estatus THEN
        COMMIT;
        SELECT CASE 
            WHEN _Nuevo_Estatus = 1 THEN 'Sin cambios: El Centro de Trabajo ya estaba Activo.'
            ELSE 'Sin cambios: El Centro de Trabajo ya estaba Inactivo.'
        END AS Mensaje,
        v_Activo_Actual AS Activo_Anterior,
        _Nuevo_Estatus AS Activo_Nuevo;
    ELSE

        /* ------------------------------------------------------------------------------------
           3) CANDADO JERÁRQUICO AL ACTIVAR (B)
           ------------------------------------------------------------------------------------
           REGLA:
           - Si quieres ACTIVAR el CT (Nuevo_Estatus=1), su Municipio padre DEBE estar ACTIVO.
           - Excepción: Si v_Id_Municipio es NULL (no tiene padre), permitimos activar 
             (porque no hay padre que valide).
           ------------------------------------------------------------------------------------ */
        IF _Nuevo_Estatus = 1 THEN
            -- Solo validamos si tiene un municipio asignado
            IF v_Id_Municipio IS NOT NULL THEN
                -- Si el municipio existe pero está inactivo (0)
                IF v_Municipio_Activo = 0 THEN
                    SIGNAL SQLSTATE '45000' 
                        SET MESSAGE_TEXT = 'BLOQUEADO: No se puede ACTIVAR el Centro de Trabajo porque su MUNICIPIO está INACTIVO. Active primero el Municipio.';
                END IF;
                -- Nota: Si v_Municipio_Activo es NULL pero v_Id_Municipio NO era NULL, 
                -- significa integridad rota (FK apunta a nada), pero el LEFT JOIN maneja eso.
            END IF;
        END IF;

        /* ------------------------------------------------------------------------------------
           4) SI INTENTA DESACTIVAR: BLOQUEAR SI HAY EMPLEADOS ACTIVOS (A)
           ------------------------------------------------------------------------------------ */
        IF _Nuevo_Estatus = 0 THEN
            
            /* 4A) Verificar Info_Personal (Empleados) */
            SET v_Tmp = NULL;
            
            SELECT 1
              INTO v_Tmp
            FROM `Info_Personal`
            WHERE `Fk_Id_CatCT` = _Id_CatCT
              AND `Activo` = 1 -- Solo nos importan los empleados ACTIVOS
            LIMIT 1;

            IF v_Tmp IS NOT NULL THEN
                SIGNAL SQLSTATE '45000' 
                    SET MESSAGE_TEXT = 'BLOQUEADO: No se puede desactivar el Centro de Trabajo porque tiene EMPLEADOS ACTIVOS asignados. Reasigne o desactive al personal primero.';
            END IF;

        END IF;

        /* ------------------------------------------------------------------------------------
           5) APLICAR CAMBIO DE ESTATUS
           ------------------------------------------------------------------------------------ */
        UPDATE `Cat_Centros_Trabajo`
        SET `Activo` = _Nuevo_Estatus,
            `updated_at` = NOW() -- Forzamos actualización de timestamp
        WHERE `Id_CatCT` = _Id_CatCT;

        COMMIT;

        /* ------------------------------------------------------------------------------------
           6) RESPUESTA PARA FRONTEND
           ------------------------------------------------------------------------------------ */
        SELECT CASE 
            WHEN _Nuevo_Estatus = 1 THEN 'Centro de Trabajo Reactivado Exitosamente'
            ELSE 'Centro de Trabajo Desactivado (Eliminado Lógico)'
        END AS Mensaje,
        v_Activo_Actual AS Activo_Anterior,
        _Nuevo_Estatus AS Activo_Nuevo;

    END IF;

END$$

DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_EliminarCentroTrabajoFisico
   ============================================================================================
    OBJETIVO
   --------
   Eliminar físicamente (DELETE) un Centro de Trabajo de la base de datos.
   
   ADVERTENCIA DE USO
   ------------------
   - Esta es una operación DESTRUCTIVA e IRREVERSIBLE.
   - Solo debe usarse en tareas de mantenimiento, limpieza de datos erróneos o depuración.
   - Para la operación diaria, se recomienda usar `SP_CambiarEstatusCentroTrabajo` (Baja Lógica).

   CANDADOS DE INTEGRIDAD (SEGURIDAD DE DATOS)
   -------------------------------------------
   1. VALIDACIÓN DE DEPENDENCIAS (HIJOS):
      - La tabla `Cat_Centros_Trabajo` es padre de `Info_Personal` (Empleados).
      - Antes de borrar, verificamos manualmente si existen empleados (activos o inactivos)
        ligados a este CT.
      - Si existen, bloqueamos la operación con un mensaje claro ("ERROR CRÍTICO").
      - Esto es mejor que dejar que la base de datos lance un error "Foreign Key Constraint Fail"
        que el usuario final no entendería.

   2. HANDLER DE LLAVE FORÁNEA (ÚLTIMA DEFENSA):
      - Si existieran otras tablas que referencian al CT (futuras implementaciones) y se nos
        olvidó validarlas manualmente, el `DECLARE EXIT HANDLER FOR 1451` atrapará el error
        de MySQL y devolverá un mensaje controlado, evitando que el sistema colapse.

   VALIDACIONES
   ------------
   - El ID debe ser válido.
   - El Centro de Trabajo debe existir.

   RESULTADO
   ---------
   - Retorna un mensaje de confirmación si el borrado fue exitoso.
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_EliminarCentroTrabajoFisico`$$
CREATE PROCEDURE `SP_EliminarCentroTrabajoFisico`(
    IN _Id_CatCT INT
)
BEGIN
    /* ----------------------------------------------------------------------------------------
       1. HANDLERS (MANEJO DE ERRORES TÉCNICOS)
       ---------------------------------------------------------------------------------------- */
    
    /* HANDLER 1451: Error de Integridad Referencial (Foreign Key)
       Este error salta si intentamos borrar algo que todavía está siendo usado por otra tabla
       que no revisamos manualmente. */
    DECLARE EXIT HANDLER FOR 1451 
    BEGIN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'ERROR DE INTEGRIDAD: No se puede eliminar el Centro de Trabajo porque está siendo utilizado en otros registros del sistema.';
    END;

    /* HANDLER GENERAL: Para cualquier otro error imprevisto (ej: fallo de disco) */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    /* ----------------------------------------------------------------------------------------
       2. VALIDACIONES BÁSICAS
       ---------------------------------------------------------------------------------------- */
    IF _Id_CatCT IS NULL OR _Id_CatCT <= 0 THEN
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'ERROR DE SISTEMA: Identificador de Centro de Trabajo inválido.';
    END IF;

    -- Verificar que realmente existe antes de intentar borrar
    IF NOT EXISTS(SELECT 1 FROM `Cat_Centros_Trabajo` WHERE `Id_CatCT` = _Id_CatCT) THEN
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'ERROR DE NEGOCIO: El Centro de Trabajo no existe.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       3. CANDADOS DE NEGOCIO (REVISIÓN DE DEPENDENCIAS)
       Aquí es donde protegemos la consistencia de los datos.
       ---------------------------------------------------------------------------------------- */
    
    /* CANDADO: Verificar EMPLEADOS (Info_Personal)
       Buscamos si hay al menos un empleado (activo o inactivo) asignado a este lugar. */
    IF EXISTS(
        SELECT 1 
        FROM `Info_Personal` 
        WHERE `Fk_Id_CatCT` = _Id_CatCT 
        LIMIT 1
    ) THEN
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'ERROR CRÍTICO: No se puede eliminar el Centro de Trabajo porque tiene HISTORIAL DE PERSONAL asignado. Utilice la opción de "Desactivar" en su lugar.';
    END IF;

    /* (Espacio reservado para futuras validaciones, ej: si hubiera tabla de Inventarios_CT) */

    /* ----------------------------------------------------------------------------------------
       4. TRANSACCIÓN DE BORRADO
       Si llegamos aquí, el registro está limpio y seguro para borrar.
       ---------------------------------------------------------------------------------------- */
    START TRANSACTION;

    DELETE FROM `Cat_Centros_Trabajo` 
    WHERE `Id_CatCT` = _Id_CatCT;

    COMMIT;

    /* ----------------------------------------------------------------------------------------
       5. RESPUESTA
       ---------------------------------------------------------------------------------------- */
    SELECT 'Centro de Trabajo eliminado permanentemente de la base de datos.' AS Mensaje;

END$$

DELIMITER ;
