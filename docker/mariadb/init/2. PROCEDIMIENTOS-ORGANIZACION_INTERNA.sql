USE `PICADE`;

/* ------------------------------------------------------------------------------------------------------ */
/* CREACION DE VISTAS Y PROCEDIMIENTOS DE ALMACENADO PARA LA BASE DE DATOS*/
/* ------------------------------------------------------------------------------------------------------ */

/* ======================================================================================================
   1. VIEW: Vista_Organizacion
   ======================================================================================================
   OBJETIVO GENERAL
   ----------------
   Exponer una vista "plana" con la jerarquía organizacional corporativa completa:
       Gerencia (Nieto) -> Subdirección (Padre) -> Dirección (Abuelo)
   
   Sirve para evitar la repetición de triples JOINs en cada consulta del backend y frontend.

   CASOS DE USO (¿DÓNDE SE CONSUME?)
   ---------------------------------
   1. Catálogo de Usuarios: Para mostrar a qué área pertenece un empleado.
   2. Reportes de Capacitación: Para agrupar estadísticas por Dirección o Subdirección.
   3. Pantallas de Administración: CRUDs de mantenimiento de catálogos.

   DECISIONES DE DISEÑO Y ARQUITECTURA
   -----------------------------------
   A) ESTRATEGIA DE JOIN:
      - INNER JOIN. Se asume integridad referencial estricta: Una Gerencia siempre pertenece a una
        Subdirección y esta a una Dirección.

   B) NORMALIZACIÓN DE NULOS:
      - Las columnas `Clave` pueden venir como NULL dependiendo de la carga histórica de datos.
      - La vista las devuelve tal cual (raw data). Si la UI requiere un texto por defecto (ej: "S/C"),
        debe aplicarse en la capa de presentación o en el SELECT final usando COALESCE.

   C) ESTATUS JERÁRQUICO:
      - El campo `Activo_Gerencia` refleja el estatus del nivel hoja (Gerencia).
      - Nota: No se expone el estatus de los padres aquí para mantener la vista ligera, pero quien
        la consuma debe saber que una Gerencia Activa podría pertenecer a una Dirección Inactiva
        (aunque los SPs de CRUD intentan prevenir esa inconsistencia).

   DICCIONARIO DE DATOS (CAMPOS DEVUELTOS)
   ---------------------------------------
   [Nivel Gerencia]
   - Id_Gerencia:       ID único (PK) de Cat_Gerencias_Activos.
   - Clave_Gerencia:    Clave interna (ej: 'GER-RH'). Puede ser NULL.
   - Nombre_Gerencia:   Nombre oficial.
   
   [Nivel Subdirección]
   - Clave_Subdireccion: Clave interna.
   - Nombre_Subdireccion: Nombre oficial.
   
   [Nivel Dirección]
   - Clave_Direccion:   Clave interna (ej: 'DCAS').
   - Nombre_Direccion:  Nombre oficial corporativo.
   
   [Metadatos]
   - Activo_Gerencia:   1 = Activo, 0 = Inactivo (Borrado Lógico).
   ====================================================================================================== */

-- DROP VIEW IF EXISTS `PICADE`.`Vista_Organizacion`;

CREATE OR REPLACE
    ALGORITHM = UNDEFINED 
    SQL SECURITY DEFINER
VIEW `PICADE`.`Vista_Organizacion` AS
    SELECT 
		`Geren`.`Id_CatGeren` AS `Id_Gerencia`, 
		`Geren`.`Clave` AS `Clave_Gerencia`, 
		`Geren`.`Nombre` AS `Nombre_Gerencia`, 
		`Subdirec`.`Clave` AS `Clave_Subdireccion`, 
		`Subdirec`.`Nombre` AS `Nombre_Subdireccion`, 
		`Direc`.`Clave` AS `Clave_Direccion`, 
		`Direc`.`Nombre` AS `Nombre_Direccion`, 
		`Geren`.`Activo` AS `Activo_Gerencia`
FROM
	`Cat_Gerencias_Activos` AS `Geren`
	INNER JOIN `Cat_Subdirecciones` AS `Subdirec` ON `Geren`.`Fk_Id_CatSubDirec` = `Subdirec`.`Id_CatSubDirec`
	INNER JOIN	`Cat_Direcciones` AS `Direc` ON `Subdirec`.`Fk_Id_CatDirecc` = `Direc`.`Id_CatDirecc`;

/* ============================================================================================
   PROCEDIMIENTO: SP_RegistrarOrganizacion
   ============================================================================================
   OBJETIVO
   --------
   Resolver o registrar una jerarquía completa de organización:
      Dirección -> Subdirección -> Gerencia
   en una sola operación, pensada para FORMULARIO donde TODO es obligatorio
   (Clave y Nombre en los 3 niveles).

   QUÉ HACE (CONTRATO DE NEGOCIO)
   ------------------------------
   Para cada nivel (Dirección, Subdirección, Gerencia) este SP aplica la MISMA regla:

   1) Busca primero por CLAVE (regla principal) dentro de su “padre” cuando aplica.
      - Si existe: valida que el NOMBRE coincida.
      - Si no coincide: ERROR controlado (conflicto Clave <-> Nombre).

   2) Si no existe por CLAVE, busca por NOMBRE dentro de su “padre” cuando aplica.
      - Si existe: valida que la CLAVE coincida.
      - Si no coincide: ERROR controlado (conflicto Nombre <-> Clave).

   3) Si NO existe por CLAVE ni por NOMBRE:
      - Crea el registro (INSERT).

   4) Si existe y está Activo = 0:
      - Reactiva (UPDATE Activo=1).

   ACCIONES DEVUELTAS
   ------------------
   El SP devuelve una acción por nivel:
      Accion_Direccion    = 'CREADA' | 'REUSADA' | 'REACTIVADA'
      Accion_Subdireccion = 'CREADA' | 'REUSADA' | 'REACTIVADA'
      Accion_Gerencia     = 'CREADA' | 'REUSADA' | 'REACTIVADA'

   SEGURIDAD / INTEGRIDAD
   ----------------------
   - Usa TRANSACTION: si algo falla, ROLLBACK y RESIGNAL (no quedan datos a medias).
   - Resolución determinística.
   - Blindaje ante concurrencia/doble-submit:
       * Los SELECT de búsqueda usan FOR UPDATE para serializar la lectura cuando hay fila.
       * Las constraints UNIQUE son el candado final contra duplicados.

   RESULTADO
   ---------
   Retorna:
   - Id_Direccion, Id_Subdireccion, Id_Gerencia
   - Accion_* por cada nivel
   - Id_Nueva_Direccion      SOLO si Accion_Direccion='CREADA', si no NULL
   - Id_Nueva_Subdireccion   SOLO si Accion_Subdireccion='CREADA', si no NULL
   - Id_Nueva_Gerencia       SOLO si Accion_Gerencia='CREADA', si no NULL
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS SP_RegistrarOrganizacion$$
CREATE PROCEDURE SP_RegistrarOrganizacion(
    IN _Clave_Gerencia        VARCHAR(50),   /* Clave de Gerencia (OBLIGATORIO en formulario) */
    IN _Nombre_Gerencia       VARCHAR(255),  /* Nombre de Gerencia (OBLIGATORIO) */
    IN _Clave_Subdireccion    VARCHAR(50),   /* Clave de Subdirección (OBLIGATORIO) */
    IN _Nombre_Subdireccion   VARCHAR(255),  /* Nombre de Subdirección (OBLIGATORIO) */
    IN _Clave_Direccion       VARCHAR(50),   /* Clave de Dirección (OBLIGATORIO) */
    IN _Nombre_Direccion      VARCHAR(255)   /* Nombre de Dirección (OBLIGATORIO) */
)
BEGIN
    /* ----------------------------------------------------------------------------------------
       VARIABLES INTERNAS
       ---------------------------------------------------------------------------------------- */
    DECLARE v_Id_Direccion    INT DEFAULT NULL;
    DECLARE v_Id_Subdireccion INT DEFAULT NULL;
    DECLARE v_Id_Gerencia     INT DEFAULT NULL;

    /* Buffers para validación cruzada cuando el registro ya existe */
    DECLARE v_Clave  VARCHAR(50);
    DECLARE v_Nombre VARCHAR(255);
    DECLARE v_Activo TINYINT(1);

    /* Acciones por nivel */
    DECLARE v_Accion_Direccion    VARCHAR(20) DEFAULT NULL;
    DECLARE v_Accion_Subdireccion VARCHAR(20) DEFAULT NULL;
    DECLARE v_Accion_Gerencia     VARCHAR(20) DEFAULT NULL;

    /* ----------------------------------------------------------------------------------------
       MANEJO DE ERRORES
       ---------------------------------------------------------------------------------------- */
    DECLARE EXIT HANDLER FOR 1062
    BEGIN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'ERROR: Registro Duplicado por concurrencia o restricción UNIQUE. Refresca y reintenta; si ya existe se reutilizará/reactivará.';
    END;
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    /* ----------------------------------------------------------------------------------------
       NORMALIZACIÓN BÁSICA
       ---------------------------------------------------------------------------------------- */
    SET _Clave_Direccion     = NULLIF(TRIM(_Clave_Direccion), '');
    SET _Nombre_Direccion    = NULLIF(TRIM(_Nombre_Direccion), '');
    SET _Clave_Subdireccion  = NULLIF(TRIM(_Clave_Subdireccion), '');
    SET _Nombre_Subdireccion = NULLIF(TRIM(_Nombre_Subdireccion), '');
    SET _Clave_Gerencia      = NULLIF(TRIM(_Clave_Gerencia), '');
    SET _Nombre_Gerencia     = NULLIF(TRIM(_Nombre_Gerencia), '');

    /* ----------------------------------------------------------------------------------------
       VALIDACIONES DE NEGOCIO (FORMULARIO: TODO OBLIGATORIO)
       ---------------------------------------------------------------------------------------- */
    IF _Clave_Direccion IS NULL OR _Nombre_Direccion IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Dirección incompleta (Clave y Nombre obligatorios).';
    END IF;

    IF _Clave_Subdireccion IS NULL OR _Nombre_Subdireccion IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Subdirección incompleta (Clave y Nombre obligatorios).';
    END IF;

    IF _Clave_Gerencia IS NULL OR _Nombre_Gerencia IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Gerencia incompleta (Clave y Nombre obligatorios).';
    END IF;

    /* ----------------------------------------------------------------------------------------
       INICIO TRANSACCIÓN
       ---------------------------------------------------------------------------------------- */
    START TRANSACTION;

    /* ========================================================================================
       1) RESOLVER / CREAR DIRECCIÓN (ABUELO)
       ======================================================================================== */

    /* 1A) Buscar por CLAVE (regla principal) */
    SET v_Id_Direccion = NULL;
    SELECT Id_CatDirecc, Clave, Nombre, Activo
      INTO v_Id_Direccion, v_Clave, v_Nombre, v_Activo
    FROM Cat_Direcciones
    WHERE Clave = _Clave_Direccion
    LIMIT 1
    FOR UPDATE;

    IF v_Id_Direccion IS NOT NULL THEN
        /* Si existe por Clave, validar que el Nombre coincida */
        IF v_Nombre <> _Nombre_Direccion THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Conflicto Dirección. La Clave existe pero el Nombre no coincide.';
        END IF;

        IF v_Activo = 0 THEN
            UPDATE Cat_Direcciones 
            SET Activo = 1, updated_at = NOW() 
            WHERE Id_CatDirecc = v_Id_Direccion;
            SET v_Accion_Direccion = 'REACTIVADA';
        ELSE
            SET v_Accion_Direccion = 'REUSADA';
        END IF;

    ELSE
        /* 1B) Buscar por NOMBRE (regla secundaria) */
        SELECT Id_CatDirecc, Clave, Nombre, Activo
          INTO v_Id_Direccion, v_Clave, v_Nombre, v_Activo
        FROM Cat_Direcciones
        WHERE Nombre = _Nombre_Direccion
        LIMIT 1
        FOR UPDATE;

        IF v_Id_Direccion IS NOT NULL THEN
            /* Si existe por Nombre, validar que la Clave coincida */
            IF v_Clave <> _Clave_Direccion THEN
                SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Conflicto Dirección. El Nombre existe pero la Clave no coincide.';
            END IF;

            IF v_Activo = 0 THEN
                UPDATE Cat_Direcciones 
                SET Activo = 1, updated_at = NOW() 
                WHERE Id_CatDirecc = v_Id_Direccion;
                SET v_Accion_Direccion = 'REACTIVADA';
            ELSE
                SET v_Accion_Direccion = 'REUSADA';
            END IF;

        ELSE
            /* 1C) Crear */
            INSERT INTO Cat_Direcciones (Clave, Nombre)
            VALUES (_Clave_Direccion, _Nombre_Direccion);

            SET v_Id_Direccion = LAST_INSERT_ID();
            SET v_Accion_Direccion = 'CREADA';
        END IF;
    END IF;

    /* ========================================================================================
       2) RESOLVER / CREAR SUBDIRECCIÓN (dentro de la Dirección resuelta)
       ======================================================================================== */

    /* 2A) Buscar por CLAVE dentro de la Dirección */
    SET v_Id_Subdireccion = NULL;
    SELECT Id_CatSubDirec, Clave, Nombre, Activo
      INTO v_Id_Subdireccion, v_Clave, v_Nombre, v_Activo
    FROM Cat_Subdirecciones
    WHERE Clave = _Clave_Subdireccion
      AND Fk_Id_CatDirecc = v_Id_Direccion
    LIMIT 1
    FOR UPDATE;

    IF v_Id_Subdireccion IS NOT NULL THEN
        /* Validar consistencia */
        IF v_Nombre <> _Nombre_Subdireccion THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Conflicto Subdirección. La Clave existe pero el Nombre no coincide (en esa Dirección).';
        END IF;

        IF v_Activo = 0 THEN
            UPDATE Cat_Subdirecciones 
            SET Activo = 1, updated_at = NOW() 
            WHERE Id_CatSubDirec = v_Id_Subdireccion;
            SET v_Accion_Subdireccion = 'REACTIVADA';
        ELSE
            SET v_Accion_Subdireccion = 'REUSADA';
        END IF;

    ELSE
        /* 2B) Buscar por NOMBRE dentro de la Dirección */
        SELECT Id_CatSubDirec, Clave, Nombre, Activo
          INTO v_Id_Subdireccion, v_Clave, v_Nombre, v_Activo
        FROM Cat_Subdirecciones
        WHERE Nombre = _Nombre_Subdireccion
          AND Fk_Id_CatDirecc = v_Id_Direccion
        LIMIT 1
        FOR UPDATE;

        IF v_Id_Subdireccion IS NOT NULL THEN
            /* Validar consistencia */
            IF v_Clave <> _Clave_Subdireccion THEN
                SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Conflicto Subdirección. El Nombre existe pero la Clave no coincide (en esa Dirección).';
            END IF;

            IF v_Activo = 0 THEN
                UPDATE Cat_Subdirecciones 
                SET Activo = 1, updated_at = NOW() 
                WHERE Id_CatSubDirec = v_Id_Subdireccion;
                SET v_Accion_Subdireccion = 'REACTIVADA';
            ELSE
                SET v_Accion_Subdireccion = 'REUSADA';
            END IF;

        ELSE
            /* 2C) Crear */
            INSERT INTO Cat_Subdirecciones (Fk_Id_CatDirecc, Clave, Nombre)
            VALUES (v_Id_Direccion, _Clave_Subdireccion, _Nombre_Subdireccion);

            SET v_Id_Subdireccion = LAST_INSERT_ID();
            SET v_Accion_Subdireccion = 'CREADA';
        END IF;
    END IF;

    /* ========================================================================================
       3) RESOLVER / CREAR GERENCIA (dentro de la Subdirección resuelta)
       ======================================================================================== */

    /* 3A) Buscar por CLAVE dentro de la Subdirección */
    SET v_Id_Gerencia = NULL;
    SELECT Id_CatGeren, Clave, Nombre, Activo
      INTO v_Id_Gerencia, v_Clave, v_Nombre, v_Activo
    FROM Cat_Gerencias_Activos
    WHERE Clave = _Clave_Gerencia
      AND Fk_Id_CatSubDirec = v_Id_Subdireccion
    LIMIT 1
    FOR UPDATE;

    IF v_Id_Gerencia IS NOT NULL THEN
        /* Validar consistencia */
        IF v_Nombre <> _Nombre_Gerencia THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Conflicto Gerencia. La Clave existe pero el Nombre no coincide (en esa Subdirección).';
        END IF;

        IF v_Activo = 0 THEN
            UPDATE Cat_Gerencias_Activos 
            SET Activo = 1, updated_at = NOW() 
            WHERE Id_CatGeren = v_Id_Gerencia;
            SET v_Accion_Gerencia = 'REACTIVADA';
        ELSE
            SET v_Accion_Gerencia = 'REUSADA';
        END IF;

    ELSE
        /* 3B) Buscar por NOMBRE dentro de la Subdirección */
        SELECT Id_CatGeren, Clave, Nombre, Activo
          INTO v_Id_Gerencia, v_Clave, v_Nombre, v_Activo
        FROM Cat_Gerencias_Activos
        WHERE Nombre = _Nombre_Gerencia
          AND Fk_Id_CatSubDirec = v_Id_Subdireccion
        LIMIT 1
        FOR UPDATE;

        IF v_Id_Gerencia IS NOT NULL THEN
            /* Validar consistencia */
            IF v_Clave <> _Clave_Gerencia THEN
                SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Conflicto Gerencia. El Nombre existe pero la Clave no coincide (en esa Subdirección).';
            END IF;

            IF v_Activo = 0 THEN
                UPDATE Cat_Gerencias_Activos 
                SET Activo = 1, updated_at = NOW() 
                WHERE Id_CatGeren = v_Id_Gerencia;
                SET v_Accion_Gerencia = 'REACTIVADA';
            ELSE
                SET v_Accion_Gerencia = 'REUSADA';
            END IF;

        ELSE
            /* 3C) Crear */
            INSERT INTO Cat_Gerencias_Activos (Fk_Id_CatSubDirec, Clave, Nombre)
            VALUES (v_Id_Subdireccion, _Clave_Gerencia, _Nombre_Gerencia);

            SET v_Id_Gerencia = LAST_INSERT_ID();
            SET v_Accion_Gerencia = 'CREADA';
        END IF;
    END IF;

    /* ----------------------------------------------------------------------------------------
       CONFIRMAR TRANSACCIÓN Y RESPUESTA
       ---------------------------------------------------------------------------------------- */
    COMMIT;

    SELECT 
        'Registro Exitoso' AS Mensaje,

        v_Id_Direccion    AS Id_Direccion,
        v_Id_Subdireccion AS Id_Subdireccion,
        v_Id_Gerencia     AS Id_Gerencia,

        v_Accion_Direccion    AS Accion_Direccion,
        v_Accion_Subdireccion AS Accion_Subdireccion,
        v_Accion_Gerencia     AS Accion_Gerencia,

        CASE 
            WHEN v_Accion_Direccion = 'CREADA' THEN v_Id_Direccion 
            ELSE NULL 
        END AS Id_Nueva_Direccion,
        
        CASE 
            WHEN v_Accion_Subdireccion = 'CREADA' THEN v_Id_Subdireccion 
            ELSE NULL 
        END AS Id_Nueva_Subdireccion,
        
        CASE 
            WHEN v_Accion_Gerencia = 'CREADA' THEN v_Id_Gerencia 
            ELSE NULL 
        END AS Id_Nueva_Gerencia;

END$$

DELIMITER ;

/* ============================================================================================
   SECCIÓN: CONSULTAS ESPECÍFICAS (PARA EDICIÓN / DETALLE)
   ============================================================================================
   Estas rutinas son clave para la UX. No solo devuelven el dato pedido, sino todo el 
   contexto jerárquico necesario para que el formulario de edición se autocomplete.
   ============================================================================================ */

/* ============================================================================================
   PROCEDIMIENTO: SP_ConsultarDireccionEspecifica
   ============================================================================================
   ¿CUÁNDO SE USA?
   --------------
   Cuando el usuario abre la pantalla "Editar Dirección" o un modal de detalle.

   ¿QUÉ RESUELVE?
   --------------
   Devuelve el registro de la Dirección por Id, incluyendo su estatus (Activo/Inactivo),
   para que el frontend pueda:
   - Precargar inputs (Clave / Nombre)
   - Mostrar el estatus actual
   - Decidir si habilita acciones (reactivar / desactivar)

   NOTA DE DISEÑO
   --------------
   - NO filtramos por Activo=1 aquí, porque para edición/admin necesitas poder
     consultar también direcciones inactivas.
   - Validamos Id y existencia para devolver errores controlados.
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS SP_ConsultarDireccionEspecifica$$
CREATE PROCEDURE SP_ConsultarDireccionEspecifica(
    IN _Id_CatDirecc INT
)
BEGIN
    /* ------------------------------------------------------------
       VALIDACIÓN 1: Id válido
       - Evita llamadas con NULL, 0, negativos, etc.
       ------------------------------------------------------------ */
    IF _Id_CatDirecc IS NULL OR _Id_CatDirecc <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Id_CatDirecc inválido.';
    END IF;

    /* ------------------------------------------------------------
       VALIDACIÓN 2: La Dirección existe
       - Si no existe, no tiene sentido cargar el formulario
       ------------------------------------------------------------ */
    IF NOT EXISTS (SELECT 1 FROM Cat_Direcciones WHERE Id_CatDirecc = _Id_CatDirecc) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: La Dirección no existe.';
    END IF;

    /* ------------------------------------------------------------
       CONSULTA PRINCIPAL
       - Trae la dirección exacta
       - LIMIT 1 por seguridad
       ------------------------------------------------------------ */
    SELECT
        Id_CatDirecc,
        Clave,
        Nombre,
        Activo,
        created_at,
        updated_at
    FROM Cat_Direcciones
    WHERE Id_CatDirecc = _Id_CatDirecc
    LIMIT 1;
END$$

DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_ConsultarSubDireccionEspecifica
   ============================================================================================
   ¿CUÁNDO SE USA?
   --------------
   Cuando el usuario abre la pantalla "Editar Subdirección".

   ¿QUÉ RESUELVE?
   --------------
   Para editar una Subdirección, el frontend normalmente necesita:
   - Datos de la Subdirección (Clave, Nombre, Activo)
   - La Dirección a la que pertenece (para preseleccionar el -- DROPdown de Dirección)
   - Datos de esa Dirección (Nombre/Clave) para mostrar contexto visual.

   NOTA DE DISEÑO
   --------------
   - NO filtramos por Activo=1 porque un admin puede necesitar editar una subdirección inactiva.
   - El JOIN asegura que traemos la data del Padre en un solo viaje a la BD.
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS SP_ConsultarSubDireccionEspecifica$$
CREATE PROCEDURE SP_ConsultarSubDireccionEspecifica(
    IN _Id_CatSubDirec INT
)
BEGIN
    /* ------------------------------------------------------------
       VALIDACIÓN 1: Id válido
       ------------------------------------------------------------ */
    IF _Id_CatSubDirec IS NULL OR _Id_CatSubDirec <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Id_CatSubDirec inválido.';
    END IF;

    /* ------------------------------------------------------------
       VALIDACIÓN 2: La Subdirección existe
       ------------------------------------------------------------ */
    IF NOT EXISTS (
		SELECT 1 
        FROM Cat_Subdirecciones 
        WHERE Id_CatSubDirec = _Id_CatSubDirec
			) THEN
				SIGNAL SQLSTATE '45000'
				SET MESSAGE_TEXT = 'ERROR: La Subdirección no existe.';
    END IF;

    /* ------------------------------------------------------------
       CONSULTA PRINCIPAL
       - Trae Subdirección + Dirección padre
       - Esto permite precargar el -- DROPdown de Dirección en el frontend
       ------------------------------------------------------------ */
    SELECT
        /* Datos de la Subdirección (Hijo) */
        Subd.Id_CatSubDirec,
        Subd.Clave          AS Clave_Subdireccion,
        Subd.Nombre         AS Nombre_Subdireccion,
        
        /* Datos de la Dirección (Padre) para el -- DROPdown */
        Subd.Fk_Id_CatDirecc AS Id_Direccion,
        Direc.Clave          AS Clave_Direccion,
        Direc.Nombre         AS Nombre_Direccion,
        
        Subd.Activo         AS Activo_Subdireccion,
        Subd.created_at     AS Created_at_SubDireccion,
        Subd.updated_at     AS Updated_at_SubDireccion

    FROM Cat_Subdirecciones Subd
    JOIN Cat_Direcciones Direc ON Direc.Id_CatDirecc = Subd.Fk_Id_CatDirecc
    WHERE Subd.Id_CatSubDirec = _Id_CatSubDirec
    LIMIT 1;
END$$

DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_ConsultarGerenciaEspecifica
   ============================================================================================
   ¿CUÁNDO SE USA?
   --------------
   Cuando el usuario abre la pantalla "Editar Gerencia".

   ¿QUÉ RESUELVE?
   --------------
   Para que tu formulario sea rápido e inteligente, necesitas reconstruir la jerarquía completa:
   - La Gerencia actual (Clave, Nombre, Activo)
   - La Subdirección actual a la que pertenece
   - La Dirección actual a la que pertenece esa Subdirección

   Con esta info tu frontend puede:
   - Precargar inputs: Clave_Gerencia y Nombre_Gerencia
   - Preseleccionar -- DROPdown Dirección con Id_Direccion actual
   - Cargar y Preseleccionar -- DROPdown Subdirección con Id_Subdireccion actual

   ¿POR QUÉ JOIN Y NO VISTA?
   -------------------------
   Un SP con parámetros es más rápido y seguro que filtrar una Vista enorme con un WHERE.
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS SP_ConsultarGerenciaEspecifica$$
CREATE PROCEDURE SP_ConsultarGerenciaEspecifica(
    IN _Id_CatGeren INT
)
BEGIN
    /* ------------------------------------------------------------
       VALIDACIÓN 1: Id válido
       ------------------------------------------------------------ */
    IF _Id_CatGeren IS NULL OR _Id_CatGeren <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Id_CatGeren inválido.';
    END IF;

    /* ------------------------------------------------------------
       VALIDACIÓN 2: La Gerencia existe
       ------------------------------------------------------------ */
    IF NOT EXISTS (
		SELECT 1 
        FROM Cat_Gerencias_Activos 
        WHERE Id_CatGeren = _Id_CatGeren
			) THEN
			SIGNAL SQLSTATE '45000'
				SET MESSAGE_TEXT = 'ERROR: La Gerencia no existe.';
    END IF;

    /* ------------------------------------------------------------
       CONSULTA PRINCIPAL
       - Trae Gerencia + Subdirección + Dirección
       - Reconstruye la ruta completa (Abuelo -> Padre -> Nieto)
       ------------------------------------------------------------ */
    SELECT
        /* Datos de la Gerencia (Nieto) */
        Geren.Id_CatGeren,
        Geren.Clave          AS Clave_Gerencia,
        Geren.Nombre         AS Nombre_Gerencia,

        /* Datos de la Subdirección (Padre) */
        Geren.Fk_Id_CatSubDirec AS Id_Subdireccion,
        Subd.Clave              AS Clave_Subdireccion,
        Subd.Nombre             AS Nombre_Subdireccion,

        /* Datos de la Dirección (Abuelo) */
        Subd.Fk_Id_CatDirecc    AS Id_Direccion,
        Direc.Clave             AS Clave_Direccion,
        Direc.Nombre            AS Nombre_Direccion,
        
        Geren.Activo         AS Activo_Gerencia,
        Geren.created_at     AS Created_at_Gerencia,
        Geren.updated_at     AS Updated_at_Gerencia
        
    FROM Cat_Gerencias_Activos Geren
    JOIN Cat_Subdirecciones Subd ON Subd.Id_CatSubDirec = Geren.Fk_Id_CatSubDirec
    JOIN Cat_Direcciones Direc   ON Direc.Id_CatDirecc = Subd.Fk_Id_CatDirecc
    WHERE Geren.Id_CatGeren = _Id_CatGeren
    LIMIT 1;
END$$

DELIMITER ;

/* ============================================================================================
   SECCIÓN: LISTADOS PARA -- DROPDOWNS (SOLO ACTIVOS)
   ============================================================================================
   Estas rutinas alimentan los selectores en los formularios.
   REGLA DE ORO: 
   - Solo devuelven registros con Activo = 1.
   - Aplican "Candado Jerárquico": No puedes listar hijos si el padre está inactivo.
   ============================================================================================ */

/* ============================================================================================
   PROCEDIMIENTO: SP_ListarDireccionesActivas
   ============================================================================================
   ¿CUÁNDO SE USA?
   --------------
   - Para llenar el -- DROPdown inicial de Direcciones en formularios en cascada.
   - Ejemplo: “Registrar/Editar Subdirección”, “Registrar/Editar Gerencia”.

   ¿QUÉ RESUELVE?
   --------------
   - Devuelve SOLO Direcciones activas (Activo = 1).
   - Ordenados por Nombre para que el usuario encuentre rápido.

   CONTRATO PARA UI (REGLA CLAVE)
   ------------------------------
   - “Activo = 1” significa: el registro es seleccionable/usable en UI.
   - Una Dirección inactiva NO debe aparecer en -- DROPdowns normales.
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS SP_ListarDireccionesActivas$$
CREATE PROCEDURE SP_ListarDireccionesActivas()
BEGIN
    SELECT
        Id_CatDirecc,
        Clave,
        Nombre
    FROM Cat_Direcciones
    WHERE Activo = 1
    ORDER BY Nombre ASC;
END$$

DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_ListarSubdireccionesPorDireccion   (VERSIÓN PRO: CONTRATO DE -- DROPDOWN “ACTIVOS”)
   ============================================================================================
   ¿CUÁNDO SE USA?
   --------------
   - Para llenar el -- DROPdown de Subdirecciones cuando:
       a) Se selecciona una Dirección en UI
       b) Se abre un formulario y hay que precargar las subdirecciones de la Dirección actual

   OBJETIVO
   --------
   - Devolver SOLO Subdirecciones activas (Activo=1) de una Dirección seleccionada.
   - Ordenados por Nombre.

   MEJORA “PRO” QUE ARREGLA (BLINDAJE)
   ----------------------------------
   Antes:
   - Solo validabas existencia.
   
   Ahora (contrato estricto):
   - Un -- DROPdown “normal” SOLO permite seleccionar padres activos.
   - Si la Dirección está inactiva => NO se lista y se responde error claro.

   ¿POR QUÉ ERROR (SIGNAL) Y NO LISTA VACÍA?
   -----------------------------------------
   - Porque lista vacía es ambigua: “¿no hay subdirecciones o la dirección está bloqueada?”
   - Con error, el frontend puede mostrar: “Dirección inactiva, refresca”.

   VALIDACIONES
   ------------
   1) _Id_CatDirecc válido (>0)
   2) Dirección existe
   3) Dirección Activo=1  (candado de contrato)
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS SP_ListarSubdireccionesPorDireccion$$
CREATE PROCEDURE SP_ListarSubdireccionesPorDireccion(
    IN _Id_CatDirecc INT
)
BEGIN
    /* ----------------------------------------------------------------------------------------
       PASO 0) Validación básica de input
       - Evita llamadas “chuecas” (null, 0, negativos) desde UI o requests directos.
    ---------------------------------------------------------------------------------------- */
    IF _Id_CatDirecc IS NULL OR _Id_CatDirecc <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Id_CatDirecc inválido.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 1) Validar existencia de la Dirección
       - Si no existe, regresamos error explícito.
    ---------------------------------------------------------------------------------------- */
    IF NOT EXISTS (SELECT 1 FROM Cat_Direcciones WHERE Id_CatDirecc = _Id_CatDirecc) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: La Dirección no existe.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 2) Candado PRO: Dirección debe estar ACTIVA
       - Este es el cambio importante.
       - Refuerza el contrato de -- DROPdown: “solo se listan hijos de padres activos”.
       - Protege contra UI con cache viejo.
    ---------------------------------------------------------------------------------------- */
    IF NOT EXISTS (SELECT 1 FROM Cat_Direcciones WHERE Id_CatDirecc = _Id_CatDirecc AND Activo = 1) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: La Dirección está inactiva. No se pueden listar Subdirecciones.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 3) Listar Subdirecciones activas de la Dirección
       - Nota: también filtramos Activo=1 de la Subdirección porque es -- DROPdown normal.
    ---------------------------------------------------------------------------------------- */
    SELECT
        Id_CatSubDirec,
        Clave,
        Nombre
    FROM Cat_Subdirecciones
    WHERE Fk_Id_CatDirecc = _Id_CatDirecc
      AND Activo = 1
    ORDER BY Nombre ASC;
END$$

DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_ListarGerenciasPorSubdireccion   (VERSIÓN PRO: CANDADO JERÁRQUICO)
   ============================================================================================
   ¿CUÁNDO SE USA?
   --------------
   - Para llenar el -- DROPdown de Gerencias cuando:
       a) Se selecciona una Subdirección en UI
       b) Se abre un formulario que requiere precargar gerencias

   OBJETIVO
   --------
   - Devolver SOLO Gerencias activas (Activo=1) de una Subdirección seleccionada.
   - Ordenados por Nombre.

   MEJORA “PRO” QUE ARREGLA (IMPORTANTE)
   -------------------------------------
   Ahora:
   - Candado jerárquico: Subdirección y su Dirección padre deben estar activos.
   - Si no cumplen, se devuelve error explícito.

   ¿POR QUÉ VALIDAR DIRECCIÓN TAMBIÉN?
   -----------------------------------
   Porque tu jerarquía real es:
       Gerencia -> Subdirección -> Dirección

   Si la Dirección está inactiva, aunque la Subdirección estuviera activa (caso raro pero posible),
   en cascada normal NO debería ser seleccionable. Esto mantiene consistencia.

   VALIDACIONES
   ------------
   1) _Id_CatSubDirec válido (>0)
   2) Subdirección existe
   3) Candado jerárquico:
      - Subdirección Activo=1
      - Dirección padre Activo=1
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS SP_ListarGerenciasPorSubdireccion$$
CREATE PROCEDURE SP_ListarGerenciasPorSubdireccion(
    IN _Id_CatSubDirec INT
)
BEGIN
    /* ----------------------------------------------------------------------------------------
       PASO 0) Validación básica de input
    ---------------------------------------------------------------------------------------- */
    IF _Id_CatSubDirec IS NULL OR _Id_CatSubDirec <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Id_CatSubDirec inválido.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 1) Validar existencia de la Subdirección
    ---------------------------------------------------------------------------------------- */
    IF NOT EXISTS (SELECT 1 FROM Cat_Subdirecciones WHERE Id_CatSubDirec = _Id_CatSubDirec) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: La Subdirección no existe.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 2) Candado PRO jerárquico: Subdirección y Dirección deben estar ACTIVAS
       - Lógica: Buscamos la Subdirección por Id.
       - Subimos a la Dirección padre (Fk_Id_CatDirecc).
       - Exigimos: S.Activo = 1 AND D.Activo = 1
    ---------------------------------------------------------------------------------------- */
    IF NOT EXISTS (
        SELECT 1
        FROM Cat_Direcciones D
        JOIN Cat_Subdirecciones S ON S.Fk_Id_CatDirecc = D.Id_CatDirecc
        WHERE S.Id_CatSubDirec = _Id_CatSubDirec
          AND S.Activo = 1
          AND D.Activo = 1
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: La Subdirección o su Dirección están inactivas. No se pueden listar Gerencias.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 3) Listar Gerencias activas
    ---------------------------------------------------------------------------------------- */
    SELECT
        Id_CatGeren,
        Clave,
        Nombre
    FROM Cat_Gerencias_Activos
    WHERE Fk_Id_CatSubDirec = _Id_CatSubDirec
      AND Activo = 1
    ORDER BY Nombre ASC;
END$$

DELIMITER ;

/* ============================================================================================
   SECCIÓN: LISTADOS PARA ADMINISTRACIÓN (TABLAS CRUD)
   ============================================================================================
   Estas rutinas son consumidas exclusivamente por los Paneles de Control (Grid/Tabla de Mantenimiento).
   Su objetivo es dar visibilidad total sobre el catálogo para auditoría, gestión y corrección.
   ============================================================================================ */

/* ============================================================================================
   PROCEDIMIENTO: SP_ListarDireccionesAdmin
   ============================================================================================
   ¿CUÁNDO SE USA?
   --------------
   - Pantallas administrativas (CRUD admin) donde necesitas ver:
       * Activos e Inactivos
       * Para poder reactivar/desactivar y depurar catálogos.

   SEGURIDAD (IMPORTANTE)
   ----------------------
   - Este SP debería consumirse solo por usuarios con rol admin.
     (Ej: Cat_Roles / permisos en backend).

   QUÉ DEVUELVE
   ------------
   - Todas las direcciones (Activo=1 y Activo=0).
   - Incluye campo Activo para que la UI pinte el estatus (ej: rojo para inactivos).
   - Orden recomendado:
       * Activos primero (para tener a la mano lo operativo).
       * Luego por Nombre para fácil búsqueda.
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS SP_ListarDireccionesAdmin$$
CREATE PROCEDURE SP_ListarDireccionesAdmin()
BEGIN
    SELECT
        Id_CatDirecc,
        Clave,
        Nombre,
        Activo,
        created_at,
        updated_at
    FROM Cat_Direcciones
    ORDER BY
        Activo DESC,    -- primero activos (1), luego inactivos (0)
        Nombre ASC;
END$$

DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_ListarSubdireccionesAdminPorDireccion
   ============================================================================================
   ¿CUÁNDO SE USA?
   --------------
   - Pantalla administrativa de Subdirecciones, filtrando por Dirección “padre”.
   - Flujo típico:
       1) Admin elige una Dirección (puede estar activa o inactiva).
       2) UI lista TODAS las Subdirecciones de esa Dirección.

   ¿POR QUÉ ES DIFERENTE AL SP NORMAL?
   -----------------------------------
   - SP_ListarSubdireccionesPorDireccion (normal) exige Dirección Activa=1 porque es -- DROPdown 
     de usuario final (operativo).
   - En ADMIN no quieres bloquearte si la Dirección está inactiva:
       * Necesitas poder ver sus subdirecciones para reactivarlas, corregir errores, etc.

   VALIDACIONES
   ------------
   1) _Id_CatDirecc válido (>0)
   2) Dirección existe (aunque esté inactiva)
      - Si no existe, es error real (no hay nada que listar).

   QUÉ DEVUELVE
   ------------
   - Todas las subdirecciones de la dirección (Activo=1 y Activo=0).
   - Incluye Activo + timestamps para auditoría visual.
   - Orden:
       * Activos primero
       * Luego por Nombre
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS SP_ListarSubdireccionesAdminPorDireccion$$
CREATE PROCEDURE SP_ListarSubdireccionesAdminPorDireccion(
    IN _Id_CatDirecc INT
)
BEGIN
    /* ----------------------------------------------------------------------------------------
       PASO 0) Validación básica de input
    ---------------------------------------------------------------------------------------- */
    IF _Id_CatDirecc IS NULL OR _Id_CatDirecc <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Id_CatDirecc inválido.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 1) Validar existencia de Dirección (admin permite inactivos, pero NO inexistentes)
    ---------------------------------------------------------------------------------------- */
    IF NOT EXISTS (SELECT 1 FROM Cat_Direcciones WHERE Id_CatDirecc = _Id_CatDirecc) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: La Dirección no existe.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 2) Listar TODAS las Subdirecciones (activas e inactivas)
    ---------------------------------------------------------------------------------------- */
    SELECT
        Id_CatSubDirec,
        Clave,
        Nombre,
        Fk_Id_CatDirecc,
        Activo,
        created_at,
        updated_at
    FROM Cat_Subdirecciones
    WHERE Fk_Id_CatDirecc = _Id_CatDirecc
    ORDER BY
        Activo DESC,
        Nombre ASC;
END$$

DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_ListarGerenciasAdminPorSubdireccion
   ============================================================================================
   ¿CUÁNDO SE USA?
   --------------
   - Pantalla administrativa de Gerencias, filtrando por Subdirección “padre”.
   - Flujo típico:
       1) Admin elige una Subdirección (puede estar activa o inactiva).
       2) UI lista TODAS las Gerencias de esa Subdirección.

   ¿POR QUÉ ES DIFERENTE AL SP NORMAL?
   -----------------------------------
   - SP_ListarGerenciasPorSubdireccion (normal) exige Subdirección Activa=1 y Dirección Activa=1
     (candado jerárquico) porque es -- DROPdown de selección operativa.
   - En ADMIN no quieres bloquearte por jerarquía inactiva:
       * Necesitas listar para mantenimiento: reactivar, corregir, depurar, etc.

   VALIDACIONES
   ------------
   1) _Id_CatSubDirec válido (>0)
   2) Subdirección existe (aunque esté inactiva)
      - Si no existe, es error real (no hay nada que listar).

   QUÉ DEVUELVE
   ------------
   - Todas las gerencias de la subdirección (Activo=1 y Activo=0).
   - Incluye Activo + timestamps.
   - Orden:
       * Activos primero
       * Luego por Nombre
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS SP_ListarGerenciasAdminPorSubdireccion$$
CREATE PROCEDURE SP_ListarGerenciasAdminPorSubdireccion(
    IN _Id_CatSubDirec INT
)
BEGIN
    /* ----------------------------------------------------------------------------------------
       PASO 0) Validación básica de input
    ---------------------------------------------------------------------------------------- */
    IF _Id_CatSubDirec IS NULL OR _Id_CatSubDirec <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Id_CatSubDirec inválido.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 1) Validar existencia de Subdirección (admin permite inactivos, pero NO inexistentes)
    ---------------------------------------------------------------------------------------- */
    IF NOT EXISTS (SELECT 1 FROM Cat_Subdirecciones WHERE Id_CatSubDirec = _Id_CatSubDirec) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: La Subdirección no existe.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 2) Listar TODAS las Gerencias (activas e inactivas)
    ---------------------------------------------------------------------------------------- */
    SELECT
        Id_CatGeren,
        Clave,
        Nombre,
        Fk_Id_CatSubDirec,
        Activo,
        created_at,
        updated_at
    FROM Cat_Gerencias_Activos
    WHERE Fk_Id_CatSubDirec = _Id_CatSubDirec
    ORDER BY
        Activo DESC,
        Nombre ASC;
END$$

DELIMITER ;

/* ====================================================================================================
   PROCEDIMIENTO: SP_ListarGerenciasAdminParaFiltro
   ====================================================================================================
   
   1. FICHA TÉCNICA (TECHNICAL DATASHEET)
   --------------------------------------
   - Nombre: SP_ListarGerenciasParaFiltro
   - Tipo: Consulta de Catálogo Completo (Full Catalog Lookup)
   - Patrón de Diseño: "Raw Data Delivery" (Entrega de Datos Crudos)
   - Nivel de Aislamiento: Read Committed
   - Autor: Arquitectura de Datos PICADE (Forensic Division)
   - Versión: 3.0 (Platinum Standard - Frontend Flexible)
   
   2. VISIÓN DE NEGOCIO (BUSINESS GOAL)
   ------------------------------------
   Este procedimiento alimenta el Dropdown de "Filtrar por Gerencia" en el Dashboard de Matrices.
   
   [CORRECCIÓN DE LÓGICA DE NEGOCIO - SOPORTE HISTÓRICO]:
   A diferencia de un formulario de registro (donde solo permitimos lo activo), un REPORTE
   es una ventana al pasado.
   Si el usuario consulta el año 2022, debe poder filtrar por Gerencias que existían en ese entonces,
   incluso si hoy (2026) ya fueron dadas de baja o reestructuradas.
   
   Por lo tanto, este SP devuelve **EL CATÁLOGO COMPLETO** (Activos + Inactivos).

   3. ESTRATEGIA TÉCNICA: "UI AGNOSTIC DATA"
   -----------------------------------------
   Se eliminó la concatenación en base de datos. Se entregan las columnas separadas (`Clave`, `Nombre`)
   para delegar el control visual al Frontend (Laravel/Vue).
   
   Esto permite al desarrollador Frontend:
     - Aplicar estilos diferenciados (ej: Clave en <span class="badge">).
     - Colorear distintamente las gerencias inactivas (ej: texto gris o tachado).
     - Implementar búsquedas avanzadas por columnas separadas.

   4. SEGURIDAD Y ORDENAMIENTO
   ---------------------------
   - Se incluye la columna `Activo` para que el Frontend sepa distinguir visualmente el estado.
   - Ordenamiento prioritario: Primero las Activas (uso común), luego las Inactivas (uso histórico).
   ==================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ListarGerenciasAdminParaFiltro`$$

CREATE PROCEDURE `SP_ListarGerenciasAdminParaFiltro`()
BEGIN
    /* ============================================================================================
       BLOQUE ÚNICO: PROYECCIÓN DE CATÁLOGO HISTÓRICO
       ============================================================================================ */
    SELECT 
        /* IDENTIFICADOR ÚNICO (Value del Select) */
        `Id_CatGeren`,
        
        /* DATOS CRUDOS (Para renderizado flexible en UI) */
        `Clave`,
        `Nombre`,
        
        /* METADATO DE ESTADO (UI Hint)
           Permite al Frontend pintar de gris o añadir "(Extinta)" a las gerencias inactivas. */
        `Activo`

    FROM `PICADE`.`Cat_Gerencias_Activos`
    
    /* SIN WHERE: 
       Traemos todo el historial para permitir filtrado en reportes de años anteriores. */
    
    /* ORDENAMIENTO DE USABILIDAD:
       1. Activo DESC: Las gerencias vigentes aparecen primero en la lista (acceso rápido).
       2. Nombre ASC: Búsqueda alfabética secundaria. */
    ORDER BY `Activo` DESC, `Nombre` ASC;

END$$

DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_RegistrarDireccion  (VERSIÓN PRO: 1062 => RE-RESOLVE)
   ============================================================================================
   OBJETIVO
   --------
   Registrar una Dirección (Clave + Nombre) con blindaje fuerte contra duplicados y carreras
   (concurrencia), devolviendo una respuesta “limpia” para el frontend:

   - Si la Dirección NO existe -> INSERT -> Accion = 'CREADA'
   - Si existe pero Activo=0 -> UPDATE Activo=1 -> Accion = 'REACTIVADA'
   - Si ya existía (por doble submit / carrera) -> NO error -> Accion='REUSADA'
   - Si hay conflicto real (mismo código con otro nombre, o viceversa) -> ERROR controlado.

   ¿CUÁNDO SE USA?
   --------------
   - Formulario "Alta de Dirección" (catálogo).
   - Casos típicos de concurrencia:
       * El usuario da doble clic a “Guardar”
       * La red está lenta y re-envía el paquete
       * Dos usuarios registran lo mismo casi al mismo tiempo

   REGLAS DE NEGOCIO (CONTRATO)
   ---------------------------
   Reglas determinísticas (SIN “OR ... LIMIT 1” ambiguo):

   1) Primero se resuelve por CLAVE (regla principal):
      - Si existe:
          a) Si NOMBRE no coincide -> ERROR (conflicto)
          b) Si Activo=0 -> REACTIVA (UPDATE Activo=1)
          c) Si Activo=1 -> ERROR (duplicado real, no es “carrera”)
      - Si no existe -> continúa

   2) Si no existe por CLAVE, se resuelve por NOMBRE:
      - Si existe:
          a) Si CLAVE no coincide -> ERROR (conflicto)
          b) Si Activo=0 -> REACTIVA
          c) Si Activo=1 -> ERROR (duplicado real)
      - Si no existe -> continúa

   3) Si NO existe por CLAVE ni por NOMBRE:
      - INTENTA INSERT.
      - Aquí es donde puede ocurrir la carrera (1062) si alguien insertó “en el mismo instante”.

   CONCURRENCIA (POR QUÉ EXISTE EL RE-RESOLVE)
   ------------------------------------------
   Importante: `SELECT ... FOR UPDATE` solo bloquea SI EXISTE una fila.
   Si NO hay fila (aún no existe la Dirección), no hay nada que bloquear.
   Entonces, dos transacciones pueden llegar al `INSERT` al mismo tiempo:

     Tx A: no encuentra fila -> INSERT -> OK
     Tx B: no encuentra fila -> INSERT -> 1062 (UNIQUE lo frena)

   En la versión simple, Tx B regresaría error.
   En esta versión PRO, Tx B:
      - Detecta 1062 (bandera v_Dup=1)
      - Hace ROLLBACK
      - Re-consulta el registro ya creado (por Tx A)
      - Devolvemos REUSADA (o REACTIVADA si estaba inactivo)

   SEGURIDAD / INTEGRIDAD
   ----------------------
   - UNIQUE en tabla sigue siendo la última línea de defensa:
       Cat_Direcciones.Clave UNIQUE
       Cat_Direcciones.Nombre UNIQUE
   - TRANSACTION + HANDLERS:
       * 1062 => NO aborta inmediato, marca bandera y permite “re-resolver”
       * Cualquier otro error => ROLLBACK y RESIGNAL (error real)
   - SELECT ... FOR UPDATE:
       * Serializa cuando la fila ya existe (evita cambios concurrentes inconsistentes)
       * Permite reactivar de forma segura

   RESULTADO
   ---------
   Retorna:
     - Mensaje (texto para UX)
     - Id_CatDirecc
     - Accion: 'CREADA' | 'REACTIVADA' | 'REUSADA'

============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS SP_RegistrarDireccion$$
CREATE PROCEDURE SP_RegistrarDireccion(
    IN _Clave VARCHAR(50),
    IN _Nombre VARCHAR(255)
)
SP: BEGIN
    /* ----------------------------------------------------------------------------------------
       VARIABLES DE TRABAJO
       - v_* guardan el registro encontrado (si existe).
       - v_Dup es una BANDERA para detectar que ocurrió 1062 durante el INSERT.
         (OJO: al ser CONTINUE HANDLER, si no revisas v_Dup, te puedes ir a COMMIT sin insertar.)
       ---------------------------------------------------------------------------------------- */
    DECLARE v_Id_Direccion INT DEFAULT NULL;
    DECLARE v_Clave        VARCHAR(50) DEFAULT NULL;
    DECLARE v_Nombre       VARCHAR(255) DEFAULT NULL;
    DECLARE v_Activo       TINYINT(1) DEFAULT NULL;

    DECLARE v_Dup TINYINT(1) DEFAULT 0;

    /* ----------------------------------------------------------------------------------------
       HANDLERS
       - 1062 (Duplicate entry): no aborta de golpe; solo marca bandera.
         Esto es CLAVE para poder hacer "re-resolve" sin mostrar error al usuario.
       - SQLEXCEPTION: cualquier otro error sí aborta (rollback + resignal).
       ---------------------------------------------------------------------------------------- */
    DECLARE CONTINUE HANDLER FOR 1062
    BEGIN
        SET v_Dup = 1;
    END;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    /* ----------------------------------------------------------------------------------------
       NORMALIZACIÓN DE INPUTS
       - TRIM: evita que "DIR " y "DIR" se comporten como cosas diferentes
       - NULLIF: convierte '' en NULL para validar obligatorios de forma limpia
       ---------------------------------------------------------------------------------------- */
    SET _Clave = NULLIF(TRIM(_Clave), '');
    SET _Nombre = NULLIF(TRIM(_Nombre), '');

    /* ----------------------------------------------------------------------------------------
       VALIDACIONES BÁSICAS
       ---------------------------------------------------------------------------------------- */
    IF _Clave IS NULL OR _Nombre IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Clave y Nombre de la Dirección son obligatorios.';
    END IF;

    /* ========================================================================================
       TRANSACCIÓN PRINCIPAL (INTENTO NORMAL)
       - Aquí resolvemos por CLAVE -> por NOMBRE -> INSERT
       ======================================================================================== */
    START TRANSACTION;

    /* ----------------------------------------------------------------------------------------
       PASO 1: BUSCAR POR CLAVE (REGLA PRINCIPAL)
       - FOR UPDATE:
         Si la fila existe, la bloquea para evitar carreras en reactivación/cambios simultáneos.
       - Limpieza de variables:
         Evita que queden valores viejos si el SELECT no retorna fila.
       ---------------------------------------------------------------------------------------- */
    SET v_Id_Direccion = NULL; 
    SET v_Clave = NULL; 
    SET v_Nombre = NULL; 
    SET v_Activo = NULL;

    SELECT Id_CatDirecc, Clave, Nombre, Activo
      INTO v_Id_Direccion, v_Clave, v_Nombre, v_Activo
    FROM Cat_Direcciones
    WHERE Clave = _Clave
    LIMIT 1
    FOR UPDATE;

    IF v_Id_Direccion IS NOT NULL THEN
        /* Conflicto fuerte: misma clave pero otro nombre => datos inconsistentes */
        IF v_Nombre <> _Nombre THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'ERROR: Conflicto Dirección. La Clave ya existe pero el Nombre no coincide.';
        END IF;

        /* Si existe pero está inactivo => reactivación segura (borrado lógico) */
        IF v_Activo = 0 THEN
            UPDATE Cat_Direcciones
            SET Activo = 1,
                updated_at = NOW()
            WHERE Id_CatDirecc = v_Id_Direccion;

            COMMIT;
            SELECT 'Dirección reactivada exitosamente' AS Mensaje,
                   v_Id_Direccion AS Id_CatDirecc,
                   'REACTIVADA' AS Accion;
            LEAVE SP;
        END IF;

        /* Si existe y está activo => duplicado REAL (no es concurrencia) */
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Ya existe una Dirección ACTIVA con esa Clave.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 2: BUSCAR POR NOMBRE (REGLA SECUNDARIA)
       - Misma lógica que la clave, pero al revés.
       ---------------------------------------------------------------------------------------- */
    SET v_Id_Direccion = NULL; 
    SET v_Clave = NULL; 
    SET v_Nombre = NULL; 
    SET v_Activo = NULL;

    SELECT Id_CatDirecc, Clave, Nombre, Activo
      INTO v_Id_Direccion, v_Clave, v_Nombre, v_Activo
    FROM Cat_Direcciones
    WHERE Nombre = _Nombre
    LIMIT 1
    FOR UPDATE;

    IF v_Id_Direccion IS NOT NULL THEN
        /* Conflicto fuerte: mismo nombre pero otra clave => datos inconsistentes */
        IF v_Clave <> _Clave THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'ERROR: Conflicto Dirección. El Nombre ya existe pero la Clave no coincide.';
        END IF;

        IF v_Activo = 0 THEN
            UPDATE Cat_Direcciones
            SET Activo = 1,
                updated_at = NOW()
            WHERE Id_CatDirecc = v_Id_Direccion;

            COMMIT;
            SELECT 'Dirección reactivada exitosamente' AS Mensaje,
                   v_Id_Direccion AS Id_CatDirecc,
                   'REACTIVADA' AS Accion;
            LEAVE SP;
        END IF;

        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Ya existe una Dirección ACTIVA con ese Nombre.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 3: INSERT (CREACIÓN REAL)
       - Este es el único punto donde la concurrencia puede provocar 1062:
         porque NO había fila para bloquear con FOR UPDATE.
       - v_Dup se reinicia antes del INSERT para que sea confiable.
       ---------------------------------------------------------------------------------------- */
    SET v_Dup = 0;

    INSERT INTO Cat_Direcciones (Clave, Nombre)
    VALUES (_Clave, _Nombre);

    /* Si NO hubo 1062, v_Dup sigue en 0 => Insert exitoso */
    IF v_Dup = 0 THEN
        COMMIT;
        SELECT 'Dirección registrada exitosamente' AS Mensaje,
               LAST_INSERT_ID() AS Id_CatDirecc,
               'CREADA' AS Accion;
        LEAVE SP;
    END IF;

    /* ========================================================================================
       SI LLEGAMOS AQUÍ:
       - v_Dup = 1 => el INSERT falló con 1062
       - Eso significa: “alguien ya insertó antes” (carrera/doble-submit)
       => RE-RESOLVE: localizar el registro y devolverlo como REUSADA/REACTIVADA
       ======================================================================================== */

    /* IMPORTANTE: revertimos el intento para salir “limpios” y sin locks */
    ROLLBACK;

    /* ----------------------------------------------------------------------------------------
       TRANSACCIÓN DE RE-RESOLVE
       - Nueva transacción para:
         1) Evitar quedarnos con locks/estado del intento anterior
         2) Poder usar FOR UPDATE sobre la fila real encontrada
       ---------------------------------------------------------------------------------------- */
    START TRANSACTION;

    /* ----------------------------------------------------------------------------------------
       RE-RESOLVE A) Localizar por CLAVE
       - Si aparece: validamos coherencia con el Nombre solicitado.
       - Si está inactivo: lo reactivamos y devolvemos REACTIVADA.
       - Si está activo: devolvemos REUSADA (UX limpia).
       ---------------------------------------------------------------------------------------- */
    SET v_Id_Direccion = NULL; 
    SET v_Clave = NULL; 
    SET v_Nombre = NULL; 
    SET v_Activo = NULL;

    SELECT Id_CatDirecc, Clave, Nombre, Activo
      INTO v_Id_Direccion, v_Clave, v_Nombre, v_Activo
    FROM Cat_Direcciones
    WHERE Clave = _Clave
    LIMIT 1
    FOR UPDATE;

    IF v_Id_Direccion IS NOT NULL THEN
        IF v_Nombre <> _Nombre THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'ERROR: Concurrencia detectada pero hay conflicto: Clave existe con otro Nombre.';
        END IF;

        IF v_Activo = 0 THEN
            UPDATE Cat_Direcciones
            SET Activo = 1,
                updated_at = NOW()
            WHERE Id_CatDirecc = v_Id_Direccion;

            COMMIT;
            SELECT 'Dirección reactivada (re-resuelto por concurrencia)' AS Mensaje,
                   v_Id_Direccion AS Id_CatDirecc,
                   'REACTIVADA' AS Accion;
            LEAVE SP;
        END IF;

        COMMIT;
        SELECT 'Dirección ya existía (reusado por concurrencia)' AS Mensaje,
               v_Id_Direccion AS Id_CatDirecc,
               'REUSADA' AS Accion;
        LEAVE SP;
    END IF;

    /* ----------------------------------------------------------------------------------------
       RE-RESOLVE B) Si no apareció por clave (muy raro), buscamos por NOMBRE
       - Misma lógica, pero validando coherencia de la Clave.
       ---------------------------------------------------------------------------------------- */
    SET v_Id_Direccion = NULL; 
    SET v_Clave = NULL; 
    SET v_Nombre = NULL; 
    SET v_Activo = NULL;

    SELECT Id_CatDirecc, Clave, Nombre, Activo
      INTO v_Id_Direccion, v_Clave, v_Nombre, v_Activo
    FROM Cat_Direcciones
    WHERE Nombre = _Nombre
    LIMIT 1
    FOR UPDATE;

    IF v_Id_Direccion IS NOT NULL THEN
        IF v_Clave <> _Clave THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'ERROR: Concurrencia detectada pero hay conflicto: Nombre existe con otra Clave.';
        END IF;

        IF v_Activo = 0 THEN
            UPDATE Cat_Direcciones
            SET Activo = 1,
                updated_at = NOW()
            WHERE Id_CatDirecc = v_Id_Direccion;

            COMMIT;
            SELECT 'Dirección reactivada (re-resuelto por concurrencia)' AS Mensaje,
                   v_Id_Direccion AS Id_CatDirecc,
                   'REACTIVADA' AS Accion;
            LEAVE SP;
        END IF;

        COMMIT;
        SELECT 'Dirección ya existía (reusado por concurrencia)' AS Mensaje,
               v_Id_Direccion AS Id_CatDirecc,
               'REUSADA' AS Accion;
        LEAVE SP;
    END IF;

    /* ----------------------------------------------------------------------------------------
       RE-RESOLVE C) Caso extremadamente raro
       - Hubo 1062 pero no localizamos la fila.
       - En InnoDB normal esto “no debería pasar”.
       - Devolvemos error controlado para que el frontend reintente.
       ---------------------------------------------------------------------------------------- */
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ERROR: Concurrencia detectada (1062) pero no se pudo localizar el registro. Reintenta.';

END$$

DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_EditarDireccion  (VERSIÓN PRO “REAL”: Lock determinístico + SIN CAMBIOS + 1062 controlado)
   ============================================================================================

   OBJETIVO
   --------
   Editar Clave y Nombre de una Dirección, con:
   - Validaciones previas entendibles (mensajes claros)
   - “SIN_CAMBIOS” (si el usuario no cambió nada, no hacemos UPDATE)
   - Blindaje contra duplicados (Clave única / Nombre único)
   - Manejo “PRO” de concurrencia: 1062 => respuesta controlada “CONFLICTO”
   - Lock determinístico de filas para minimizar deadlocks en escenarios de “intercambio” (swap)

   ESCENARIO CLÁSICO DE DEADLOCK (POR QUÉ AQUÍ SÍ IMPORTA “LOCK DETERMINÍSTICO”)
   ----------------------------------------------------------------------------
   Caso:
   - Usuario A edita Dirección #1 (FIN) y lo quiere cambiar a Clave='RH'
   - Usuario B edita Dirección #2 (RH) y lo quiere cambiar a Clave='FIN'
   Sin lock determinístico, podría ocurrir:
   - A bloquea Dirección #1 (FOR UPDATE)
   - B bloquea Dirección #2 (FOR UPDATE)
   - A intenta bloquear Dirección #2 (para validar duplicado por clave)
   - B intenta bloquear Dirección #1 (para validar duplicado por clave)
   => DEADLOCK.

   SOLUCIÓN
   --------
   En vez de “bloquear primero la dirección a editar y luego el posible conflicto” en orden variable,
   hacemos un lock determinístico de TODAS las filas relevantes (máximo 3):
      - La Dirección que se edita (_Id_CatDirecc)
      - La Dirección que ya tenga la nueva Clave (si existe)
      - La Dirección que ya tenga el nuevo Nombre (si existe)
   Y las bloqueamos SIEMPRE en orden ascendente de Id.

   REGLAS (CONTRATO DE NEGOCIO)
   ----------------------------
   1) La Dirección a editar DEBE existir.
   2) _Nuevo_Clave y _Nuevo_Nombre son obligatorios.
   3) No puede existir OTRA Dirección con:
      - la misma Clave
      - el mismo Nombre
      (excluimos el mismo Id_CatDirecc para permitir guardar sin cambios)
   4) Si no cambió nada => Accion = 'SIN_CAMBIOS'
   5) Si en UPDATE ocurre 1062 => Accion = 'CONFLICTO' (controlado)

   SOBRE LOS RESETEOS A NULL ANTES DE SELECT ... INTO
   -------------------------------------------------
   En MySQL, si un SELECT ... INTO no encuentra filas:
   - NO asigna nada y la variable conserva el valor anterior.
   Por eso antes de cada SELECT ... INTO hacemos SET var = NULL.

   RESULTADO
   ---------
   ÉXITO:
      - Mensaje
      - Accion = 'ACTUALIZADA'
      - Id_CatDirecc

   SIN CAMBIOS:
      - Mensaje
      - Accion = 'SIN_CAMBIOS'
      - Id_CatDirecc

   CONFLICTO (1062):
      - Mensaje
      - Accion = 'CONFLICTO'
      - Campo = 'CLAVE' | 'NOMBRE'
      - Id_Conflicto
      - Id_Direccion_Que_Intentabas_Editar
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS SP_EditarDireccion$$
CREATE PROCEDURE SP_EditarDireccion(
    IN _Id_CatDirecc INT,
    IN _Nuevo_Clave VARCHAR(50),
    IN _Nuevo_Nombre VARCHAR(255)
)
SP: BEGIN
    /* ========================================================================================
       PARTE 0) VARIABLES
       ======================================================================================== */

    /* Valores actuales de la dirección (para “SIN_CAMBIOS”) */
    DECLARE v_Clave_Actual  VARCHAR(50)  DEFAULT NULL;
    DECLARE v_Nombre_Actual VARCHAR(255) DEFAULT NULL;

    /* Posibles filas “en conflicto” (por clave o por nombre) */
    DECLARE v_Id_Direc_DupClave INT DEFAULT NULL;
    DECLARE v_Id_Direc_DupNombre INT DEFAULT NULL;

    /* Auxiliar genérico para validar existencia en locks */
    DECLARE v_Existe INT DEFAULT NULL;

    /* Auxiliar para pre-checks finales (duplicidad) */
    DECLARE v_DupId INT DEFAULT NULL;

    /* Bandera de choque 1062 en UPDATE */
    DECLARE v_Dup TINYINT(1) DEFAULT 0;

    /* Para respuesta de conflicto controlado */
    DECLARE v_Id_Conflicto INT DEFAULT NULL;
    DECLARE v_Campo_Conflicto VARCHAR(20) DEFAULT NULL;

    /* Para lock determinístico (3 ids máximo) */
    DECLARE v_L1 INT DEFAULT NULL;
    DECLARE v_L2 INT DEFAULT NULL;
    DECLARE v_L3 INT DEFAULT NULL;
    DECLARE v_Min INT DEFAULT NULL;

    /* ========================================================================================
       PARTE 1) HANDLERS
       ======================================================================================== */

    /* 1062 (Duplicate entry):
       - No abortamos el SP de golpe.
       - Marcamos v_Dup=1 para devolver “CONFLICTO” controlado.
    */
    DECLARE CONTINUE HANDLER FOR 1062
    BEGIN
        SET v_Dup = 1;
    END;

    /* Cualquier otro error SQL:
       - rollback + relanzar el error real
    */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    /* ========================================================================================
       PARTE 2) NORMALIZACIÓN
       ======================================================================================== */
    SET _Nuevo_Clave = NULLIF(TRIM(_Nuevo_Clave), '');
    SET _Nuevo_Nombre = NULLIF(TRIM(_Nuevo_Nombre), '');

    /* ========================================================================================
       PARTE 3) VALIDACIONES BÁSICAS
       ======================================================================================== */
    IF _Id_CatDirecc IS NULL OR _Id_CatDirecc <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Id_CatDirecc inválido.';
    END IF;

    IF _Nuevo_Clave IS NULL OR _Nuevo_Nombre IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Clave y Nombre son obligatorios.';
    END IF;

    /* ========================================================================================
       PARTE 4) TRANSACCIÓN PRINCIPAL
       ======================================================================================== */
    START TRANSACTION;

    /* ----------------------------------------------------------------------------------------
       PASO 1) Lectura inicial de la Dirección a editar (SIN bloquear todavía)
       ----------------------------------------------------------------------------------------
       - Aquí solo verificamos que exista y obtenemos valores actuales.
       - OJO: aún NO bloqueamos para poder hacer lock determinístico después.
       - Si alguien cambia algo en microsegundos, lo corregimos en PASO 4 (re-lectura con lock).
    ---------------------------------------------------------------------------------------- */
    SET v_Clave_Actual = NULL;
    SET v_Nombre_Actual = NULL;

    SELECT Clave, Nombre
      INTO v_Clave_Actual, v_Nombre_Actual
    FROM Cat_Direcciones
    WHERE Id_CatDirecc = _Id_CatDirecc
    LIMIT 1;

    IF v_Clave_Actual IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: La Dirección no existe.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 2) Descubrir “posibles conflictos” (SIN bloquear todavía)
       ----------------------------------------------------------------------------------------
       - Buscamos qué fila (si existe) YA tiene la nueva Clave o el nuevo Nombre.
       - Esto nos permite saber QUÉ filas hay que bloquear en orden determinístico.
       - NO usamos FOR UPDATE aquí, justamente para NO inducir locks en orden variable.
    ---------------------------------------------------------------------------------------- */
    SET v_Id_Direc_DupClave = NULL;

    SELECT Id_CatDirecc
      INTO v_Id_Direc_DupClave
    FROM Cat_Direcciones
    WHERE Clave = _Nuevo_Clave
      AND Id_CatDirecc <> _Id_CatDirecc
    LIMIT 1;

    SET v_Id_Direc_DupNombre = NULL;

    SELECT Id_CatDirecc
      INTO v_Id_Direc_DupNombre
    FROM Cat_Direcciones
    WHERE Nombre = _Nuevo_Nombre
      AND Id_CatDirecc <> _Id_CatDirecc
    LIMIT 1;

    /* ----------------------------------------------------------------------------------------
       PASO 3) LOCK DETERMINÍSTICO de filas relevantes (hasta 3)
       ----------------------------------------------------------------------------------------
       - Construimos la lista (Id a editar, Id por clave, Id por nombre)
       - Quitamos NULLs y duplicados
       - Bloqueamos SIEMPRE en orden ascendente:
           lock #1: el menor Id
           lock #2: el siguiente
           lock #3: el siguiente
       - Cada lock se hace con SELECT ... FOR UPDATE que NO devuelve result sets “extra”.
    ---------------------------------------------------------------------------------------- */
    SET v_L1 = _Id_CatDirecc;
    SET v_L2 = v_Id_Direc_DupClave;
    SET v_L3 = v_Id_Direc_DupNombre;

    /* Remover duplicados obvios */
    IF v_L2 = v_L1 THEN SET v_L2 = NULL; END IF;
    IF v_L3 = v_L1 THEN SET v_L3 = NULL; END IF;
    IF v_L3 IS NOT NULL AND v_L2 IS NOT NULL AND v_L3 = v_L2 THEN SET v_L3 = NULL; END IF;

    /* 3.1) Lock del menor */
    SET v_Min = NULL;
    IF v_L1 IS NOT NULL THEN SET v_Min = v_L1; END IF;
    IF v_L2 IS NOT NULL AND (v_Min IS NULL OR v_L2 < v_Min) THEN SET v_Min = v_L2; END IF;
    IF v_L3 IS NOT NULL AND (v_Min IS NULL OR v_L3 < v_Min) THEN SET v_Min = v_L3; END IF;

    IF v_Min IS NOT NULL THEN
        SET v_Existe = NULL;

        SELECT 1 INTO v_Existe
        FROM Cat_Direcciones
        WHERE Id_CatDirecc = v_Min
        LIMIT 1
        FOR UPDATE;

        IF v_Existe IS NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Inconsistencia: fila a bloquear ya no existe (lock #1).';
        END IF;

        /* “Consumimos” el id bloqueado */
        IF v_L1 = v_Min THEN SET v_L1 = NULL; END IF;
        IF v_L2 = v_Min THEN SET v_L2 = NULL; END IF;
        IF v_L3 = v_Min THEN SET v_L3 = NULL; END IF;
    END IF;

    /* 3.2) Lock del siguiente menor */
    SET v_Min = NULL;
    IF v_L1 IS NOT NULL THEN SET v_Min = v_L1; END IF;
    IF v_L2 IS NOT NULL AND (v_Min IS NULL OR v_L2 < v_Min) THEN SET v_Min = v_L2; END IF;
    IF v_L3 IS NOT NULL AND (v_Min IS NULL OR v_L3 < v_Min) THEN SET v_Min = v_L3; END IF;

    IF v_Min IS NOT NULL THEN
        SET v_Existe = NULL;

        SELECT 1 INTO v_Existe
        FROM Cat_Direcciones
        WHERE Id_CatDirecc = v_Min
        LIMIT 1
        FOR UPDATE;

        IF v_Existe IS NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Inconsistencia: fila a bloquear ya no existe (lock #2).';
        END IF;

        IF v_L1 = v_Min THEN SET v_L1 = NULL; END IF;
        IF v_L2 = v_Min THEN SET v_L2 = NULL; END IF;
        IF v_L3 = v_Min THEN SET v_L3 = NULL; END IF;
    END IF;

    /* 3.3) Lock del último (si existe) */
    SET v_Min = NULL;
    IF v_L1 IS NOT NULL THEN SET v_Min = v_L1; END IF;
    IF v_L2 IS NOT NULL AND (v_Min IS NULL OR v_L2 < v_Min) THEN SET v_Min = v_L2; END IF;
    IF v_L3 IS NOT NULL AND (v_Min IS NULL OR v_L3 < v_Min) THEN SET v_Min = v_L3; END IF;

    IF v_Min IS NOT NULL THEN
        SET v_Existe = NULL;

        SELECT 1 INTO v_Existe
        FROM Cat_Direcciones
        WHERE Id_CatDirecc = v_Min
        LIMIT 1
        FOR UPDATE;

        IF v_Existe IS NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Inconsistencia: fila a bloquear ya no existe (lock #3).';
        END IF;
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 4) Re-lectura de la Dirección objetivo YA con lock (consistencia)
       ----------------------------------------------------------------------------------------
       - Ahora sí, ya tenemos un punto estable:
         la fila _Id_CatDirecc está bloqueada dentro de esta transacción.
       - Actualizamos “actuales” por si cambiaron entre PASO 1 y PASO 3.
    ---------------------------------------------------------------------------------------- */
    SET v_Clave_Actual = NULL;
    SET v_Nombre_Actual = NULL;

    SELECT Clave, Nombre
      INTO v_Clave_Actual, v_Nombre_Actual
    FROM Cat_Direcciones
    WHERE Id_CatDirecc = _Id_CatDirecc
    LIMIT 1
    FOR UPDATE;

    IF v_Clave_Actual IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: La Dirección no existe (desapareció durante la edición).';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 5) SIN CAMBIOS (salida temprana)
       ----------------------------------------------------------------------------------------
       - Si el usuario no cambió ni Clave ni Nombre:
         devolvemos “SIN_CAMBIOS” y liberamos locks rápido (COMMIT).
    ---------------------------------------------------------------------------------------- */
    IF v_Clave_Actual = _Nuevo_Clave
       AND v_Nombre_Actual = _Nuevo_Nombre THEN

        COMMIT;

        SELECT 'Sin cambios: La Dirección ya tiene esa Clave y ese Nombre.' AS Mensaje,
               'SIN_CAMBIOS' AS Accion,
               _Id_CatDirecc AS Id_CatDirecc;
        LEAVE SP;
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 6) Pre-check duplicidad por CLAVE (otro Id)
       ----------------------------------------------------------------------------------------
       - Aquí ya estamos bajo locks determinísticos, así reducimos deadlocks.
       - Excluimos el mismo Id_CatDirecc (edición del propio registro).
    ---------------------------------------------------------------------------------------- */
    SET v_DupId = NULL;

    SELECT Id_CatDirecc
      INTO v_DupId
    FROM Cat_Direcciones
    WHERE Clave = _Nuevo_Clave
      AND Id_CatDirecc <> _Id_CatDirecc
    ORDER BY Id_CatDirecc
    LIMIT 1
    FOR UPDATE;

    IF v_DupId IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Ya existe OTRA Dirección con esa CLAVE.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 7) Pre-check duplicidad por NOMBRE (otro Id)
    ---------------------------------------------------------------------------------------- */
    SET v_DupId = NULL;

    SELECT Id_CatDirecc
      INTO v_DupId
    FROM Cat_Direcciones
    WHERE Nombre = _Nuevo_Nombre
      AND Id_CatDirecc <> _Id_CatDirecc
    ORDER BY Id_CatDirecc
    LIMIT 1
    FOR UPDATE;

    IF v_DupId IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Ya existe OTRA Dirección con ese NOMBRE.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 8) UPDATE FINAL (aquí puede aparecer 1062 por carrera)
       ----------------------------------------------------------------------------------------
       - Reseteamos v_Dup = 0 justo antes del UPDATE.
       - Si alguien “se coló” entre nuestros checks y el update (concurrencia real),
         el UNIQUE dispara 1062 y nuestro handler marca v_Dup=1.
    ---------------------------------------------------------------------------------------- */
    SET v_Dup = 0;

    UPDATE Cat_Direcciones
    SET Clave = _Nuevo_Clave,
        Nombre = _Nuevo_Nombre,
        updated_at = NOW()
    WHERE Id_CatDirecc = _Id_CatDirecc;

    /* ----------------------------------------------------------------------------------------
       PASO 9) Si hubo 1062 => CONFLICTO CONTROLADO
       ----------------------------------------------------------------------------------------
       - ROLLBACK: no guardamos nada.
       - Re-consultamos quién causó el choque:
           * primero por Clave
           * si no, por Nombre
       - Devolvemos datos para UI (mensaje + Id_Conflicto).
    ---------------------------------------------------------------------------------------- */
    IF v_Dup = 1 THEN
        ROLLBACK;

        SET v_Id_Conflicto = NULL;
        SET v_Campo_Conflicto = NULL;

        /* 9.1) Conflicto por Clave */
        SELECT Id_CatDirecc
          INTO v_Id_Conflicto
        FROM Cat_Direcciones
        WHERE Clave = _Nuevo_Clave
          AND Id_CatDirecc <> _Id_CatDirecc
        ORDER BY Id_CatDirecc
        LIMIT 1;

        IF v_Id_Conflicto IS NOT NULL THEN
            SET v_Campo_Conflicto = 'CLAVE';
        ELSE
            /* 9.2) Conflicto por Nombre */
            SELECT Id_CatDirecc
              INTO v_Id_Conflicto
            FROM Cat_Direcciones
            WHERE Nombre = _Nuevo_Nombre
              AND Id_CatDirecc <> _Id_CatDirecc
            ORDER BY Id_CatDirecc
            LIMIT 1;

            IF v_Id_Conflicto IS NOT NULL THEN
                SET v_Campo_Conflicto = 'NOMBRE';
            END IF;
        END IF;

        SELECT 'No se guardó: otro usuario se adelantó. Refresca y vuelve a intentar.' AS Mensaje,
               'CONFLICTO' AS Accion,
               v_Campo_Conflicto AS Campo,
               v_Id_Conflicto AS Id_Conflicto,
               _Id_CatDirecc AS Id_Direccion_Que_Intentabas_Editar;
        LEAVE SP;
    END IF;

    /* ----------------------------------------------------------------------------------------
       ÉXITO
    ---------------------------------------------------------------------------------------- */
    COMMIT;

    SELECT 'Dirección actualizada correctamente' AS Mensaje,
           'ACTUALIZADA' AS Accion,
           _Id_CatDirecc AS Id_CatDirecc;

END$$

DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_CambiarEstatusDireccion
   ============================================================================================
   OBJETIVO
   --------
   Activar/Desactivar (borrado lógico) una Dirección:
      Cat_Direcciones.Activo (1 = activo, 0 = inactivo)

   REGLA CRÍTICA (INTEGRIDAD JERÁRQUICA)
   ------------------------------------
   - NO se permite DESACTIVAR una Dirección si tiene:
       * SUBDIRECCIONES ACTIVAS bajo esa dirección.
   
   Esto evita inconsistencia de datos:
      Direccion.Activo=0 (Padre muerto)
      Subdireccion.Activo=1 (Hijo vivo) -> ¡Huérfano lógico!

   CONCURRENCIA
   ------------
   - SELECT ... FOR UPDATE sobre Dirección para:
       * Validar existencia
       * Evitar cambios simultáneos contradictorios (ej: alguien más la borra mientras tú la desactivas)
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS SP_CambiarEstatusDireccion$$
CREATE PROCEDURE SP_CambiarEstatusDireccion(
    IN _Id_CatDirecc INT,
    IN _Nuevo_Estatus TINYINT -- 1 = Activo, 0 = Inactivo
)
BEGIN
    /* ----------------------------------------------------------------------------------------
       VARIABLES
       ---------------------------------------------------------------------------------------- */
    DECLARE v_Existe INT DEFAULT NULL;
    DECLARE v_Activo_Actual TINYINT(1) DEFAULT NULL;
    DECLARE v_Tmp INT DEFAULT NULL;

    /* ----------------------------------------------------------------------------------------
       HANDLER GENERAL
       - Si cualquier SQL falla: ROLLBACK y relanza error real
       ---------------------------------------------------------------------------------------- */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    /* ----------------------------------------------------------------------------------------
       VALIDACIONES DE PARÁMETROS
       ---------------------------------------------------------------------------------------- */
    IF _Id_CatDirecc IS NULL OR _Id_CatDirecc <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Id_CatDirecc inválido.';
    END IF;

    IF _Nuevo_Estatus NOT IN (0,1) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Estatus inválido (solo 0 o 1).';
    END IF;

    START TRANSACTION;

    /* ----------------------------------------------------------------------------------------
       1) VALIDAR EXISTENCIA DE LA DIRECCIÓN Y BLOQUEAR SU FILA
       ---------------------------------------------------------------------------------------- */
    SELECT 1, Activo
      INTO v_Existe, v_Activo_Actual
    FROM Cat_Direcciones
    WHERE Id_CatDirecc = _Id_CatDirecc
    LIMIT 1
    FOR UPDATE;

    IF v_Existe IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: La Dirección no existe.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       2) "SIN CAMBIOS" (IDEMPOTENCIA)
       - Si la dirección ya estaba en ese estatus, no hacemos nada y devolvemos mensaje claro.
       ---------------------------------------------------------------------------------------- */
    IF v_Activo_Actual = _Nuevo_Estatus THEN
        COMMIT;
        SELECT CASE 
            WHEN _Nuevo_Estatus = 1 THEN 'Sin cambios: La Dirección ya estaba Activa.'
            ELSE 'Sin cambios: La Dirección ya estaba Inactiva.'
        END AS Mensaje,
        v_Activo_Actual AS Activo_Anterior,
        _Nuevo_Estatus AS Activo_Nuevo;
    ELSE
        /* ------------------------------------------------------------------------------------
           3) SI INTENTA DESACTIVAR (Nuevo_Estatus=0):
              BLOQUEAR SI HAY HIJOS ACTIVOS
           ------------------------------------------------------------------------------------ */
        IF _Nuevo_Estatus = 0 THEN

            /* 3A) Candado: Subdirecciones activas */
            SET v_Tmp = NULL;
            SELECT Id_CatSubDirec
              INTO v_Tmp
            FROM Cat_Subdirecciones
            WHERE Fk_Id_CatDirecc = _Id_CatDirecc
              AND Activo = 1
            LIMIT 1;

            IF v_Tmp IS NOT NULL THEN
                SIGNAL SQLSTATE '45000' 
                    SET MESSAGE_TEXT = 'BLOQUEADO: No se puede desactivar la Dirección porque tiene SUBDIRECCIONES ACTIVAS. Desactiva primero las Subdirecciones.';
            END IF;

            /* 3B) Candado extra: Gerencias activas bajo la dirección (Validación de profundidad)
               Esto protege contra inconsistencias profundas (Dirección -> Gerencia) aunque la
               Subdirección intermedia estuviera en un estado raro. */
            SET v_Tmp = NULL;
            SELECT Geren.Id_CatGeren
              INTO v_Tmp
            FROM Cat_Gerencias_Activos Geren
            JOIN Cat_Subdirecciones Subd ON Subd.Id_CatSubDirec = Geren.Fk_Id_CatSubDirec
            WHERE Subd.Fk_Id_CatDirecc = _Id_CatDirecc
              AND Geren.Activo = 1
            LIMIT 1;

            IF v_Tmp IS NOT NULL THEN
                SIGNAL SQLSTATE '45000' 
                    SET MESSAGE_TEXT = 'BLOQUEADO: No se puede desactivar la Dirección porque existen GERENCIAS ACTIVAS bajo ella. Desactiva primero Gerencias/Subdirecciones.';
            END IF;
        END IF;

        /* ------------------------------------------------------------------------------------
           4) APLICAR CAMBIO DE ESTATUS
           ------------------------------------------------------------------------------------ */
        UPDATE Cat_Direcciones
        SET Activo = _Nuevo_Estatus,
            updated_at = NOW()
        WHERE Id_CatDirecc = _Id_CatDirecc;

        COMMIT;

        /* ------------------------------------------------------------------------------------
           5) RESPUESTA PARA FRONTEND
           ------------------------------------------------------------------------------------ */
        SELECT CASE 
            WHEN _Nuevo_Estatus = 1 THEN 'Dirección Reactivada'
            ELSE 'Dirección Desactivada (Oculta)'
        END AS Mensaje,
        v_Activo_Actual AS Activo_Anterior,
        _Nuevo_Estatus AS Activo_Nuevo;
    END IF;

END$$

DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_EliminarDireccionFisica
   ============================================================================================
   OBJETIVO
   --------
   Eliminar físicamente (DELETE) una Dirección de la base de datos.
   Solo se permite si la Dirección está totalmente "limpia" (sin Subdirecciones asociadas).

   ¿CUÁNDO SE USA?
   --------------
   - Limpieza controlada de catálogo (Administración avanzada).
   - Corrección de errores de captura (ej: se creó una Dirección por error y no tiene uso).
   - NO es el borrado lógico (Estatus), esto destruye el registro.

   CANDADO DE SEGURIDAD (INTEGRIDAD REFERENCIAL)
   --------------------------------------------
   - Si existe al menos una Subdirección con Fk_Id_CatDirecc = _Id_CatDirecc, 
     se BLOQUEA el DELETE.
   - Esto evita:
      - Romper la jerarquía Dirección -> Subdirección -> Gerencia.
      - Errores de integridad referencial a nivel de base de datos (Error 1451).
      - Dejar registros huérfanos.

   VALIDACIONES
   ------------
   - La Dirección debe existir.
   - No debe tener hijos (Subdirecciones).
   - Se usa un HANDLER para capturar errores de FK por si existen otras dependencias 
     no contempladas (ej: tablas de relación futuras).

   RESPUESTA
   ---------
   - Mensaje de confirmación si se eliminó exitosamente.
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS SP_EliminarDireccionFisica$$
CREATE PROCEDURE SP_EliminarDireccionFisica(
    IN _Id_CatDirecc INT
)
BEGIN
    /* ----------------------------------------------------------------------------------------
       HANDLERS DE ERROR
       ---------------------------------------------------------------------------------------- */
    
    /* Handler para Foreign Keys (Error 1451 de MySQL)
       Atrapa el intento de borrar algo que la BD protege por constraint */
    DECLARE EXIT HANDLER FOR 1451
    BEGIN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'ERROR: No se puede eliminar la Dirección porque está referenciada por otros registros (FK).';
    END;

    /* Handler general para cualquier otra excepción SQL */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    /* ----------------------------------------------------------------------------------------
       VALIDACIONES BÁSICAS
       ---------------------------------------------------------------------------------------- */
    
    /* Validación de ID */
    IF _Id_CatDirecc IS NULL OR _Id_CatDirecc <= 0 THEN
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'ERROR: Id_CatDirecc inválido.';
    END IF;

    /* Validación de Existencia */
    IF NOT EXISTS(SELECT 1 FROM Cat_Direcciones WHERE Id_CatDirecc = _Id_CatDirecc) THEN
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'ERROR: La Dirección no existe.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       CANDADO DE NEGOCIO: REVISAR DEPENDENCIAS (HIJOS)
       - Buscamos manualmente si existen Subdirecciones antes de intentar el DELETE.
       - Esto permite dar un mensaje mucho más claro que el error genérico de MySQL.
       ---------------------------------------------------------------------------------------- */
    IF EXISTS(SELECT 1 FROM Cat_Subdirecciones WHERE Fk_Id_CatDirecc = _Id_CatDirecc) THEN
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'ERROR CRÍTICO: No se puede eliminar la Dirección porque tiene SUBDIRECCIONES asociadas. Elimine primero las subdirecciones.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       TRANSACCIÓN DE BORRADO
       ---------------------------------------------------------------------------------------- */
    START TRANSACTION;

    DELETE FROM Cat_Direcciones
    WHERE Id_CatDirecc = _Id_CatDirecc;

    COMMIT;

    SELECT 'Dirección eliminada permanentemente' AS Mensaje;
END$$

DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_RegistrarSubdireccion  (VERSIÓN PRO: 1062 => RE-RESOLVE)
   ============================================================================================
   OBJETIVO
   --------
   Registrar una nueva Subdirección dentro de una Dirección específica (seleccionada por -- DROPdown),
   con blindaje fuerte contra duplicados y con manejo PRO de concurrencia (doble submit).

   ¿CUÁNDO SE USA?
   --------------
   - Formulario “Alta de Subdirección”.
   - El usuario captura:
        * Clave (ej: 'SGRH')
        * Nombre (ej: 'SUBDIRECCIÓN DE RECURSOS HUMANOS')
     y selecciona una Dirección ACTIVA del -- DROPdown:
        * _Fk_Id_CatDirecc (Id_Direccion)

   REGLAS (CONTRATO DE NEGOCIO)
   ----------------------------
   En la Dirección _Fk_Id_CatDirecc se aplica la MISMA regla determinística que en Estado:

   1) Buscar primero por CLAVE dentro de la Dirección (regla principal).
      - Si existe:
          a) El NOMBRE debe coincidir, si no => ERROR (conflicto Clave <-> Nombre).
          b) Si Activo=0 => REACTIVAR (UPDATE Activo=1) y devolver 'REACTIVADA'.
          c) Si Activo=1 => ERROR (ya existe activo).

   2) Si no existe por CLAVE, buscar por NOMBRE dentro de la Dirección.
      - Si existe:
          a) La CLAVE debe coincidir, si no => ERROR (conflicto Nombre <-> Clave).
          b) Si Activo=0 => REACTIVAR y devolver 'REACTIVADA'.
          c) Si Activo=1 => ERROR (ya existe activo).

   3) Si no existe por ninguno => INSERT y devolver 'CREADA'.

   CONCURRENCIA (EL PROBLEMA REAL)
   -------------------------------
   Caso típico:
   - Usuario A y Usuario B intentan registrar la misma Subdirección (misma Clave o mismo Nombre)
     en la MISMA Dirección casi al mismo tiempo.
   - Los SELECT ... FOR UPDATE NO bloquean nada si “no hay fila todavía”.
   - Ambos intentan INSERT.
   - Uno gana y el otro pierde con error 1062 (violación de UNIQUE).

   SOLUCIÓN PRO: 1062 => “RE-RESOLVE”
   ---------------------------------
   En vez de devolver un error feo al segundo:
   - Detectamos el 1062 (handler).
   - Hacemos ROLLBACK del intento.
   - Abrimos una nueva transacción y “localizamos” el registro ganador.
   - Devolvemos:
        Accion='REUSADA'  (ya existía y se reutiliza)
     o Accion='REACTIVADA' (si estaba inactivo y se reactivó).

   IMPORTANTE: ¿POR QUÉ SE RESETEAN VARIABLES A NULL ANTES DE CADA SELECT INTO?
   ----------------------------------------------------------------------------
   En MySQL, si un SELECT ... INTO no encuentra filas:
   - NO asigna nada (las variables se quedan con el valor anterior).
   Por eso SIEMPRE hacemos:
      SET v_Id_Subdireccion = NULL; ...
   antes del SELECT, para que “no encontrado” sea detectable como NULL.

   SEGURIDAD / INTEGRIDAD (TU ESQUEMA)
   -----------------------------------
   - Dirección tiene Activo (-- DROPdown debe ser solo activos).
   - Subdirección tiene UNIQUE compuestos:
        Uk_Subdireccion_Clave_Direccion UNIQUE (Clave, Fk_Id_CatDirecc)
        Uk_Subdireccion_Nombre_Direccion UNIQUE (Nombre, Fk_Id_CatDirecc)
   - TRANSACTION + SELECT ... FOR UPDATE:
        * Si la fila existe => la bloquea y serializa.
        * Si no existe => el candado final es el UNIQUE (y ahí entra el 1062).

   RESULTADO
   ---------
   Retorna:
     - Mensaje
     - Id_CatSubDirec
     - Id_Direccion (Fk_Id_CatDirecc)
     - Accion: 'CREADA' | 'REACTIVADA' | 'REUSADA'
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS SP_RegistrarSubdireccion$$
CREATE PROCEDURE SP_RegistrarSubdireccion(
    IN _Clave           VARCHAR(50),
    IN _Nombre          VARCHAR(255),
    IN _Fk_Id_CatDirecc INT
)
SP: BEGIN
    /* ----------------------------------------------------------------------------------------
       VARIABLES DE TRABAJO (resultado de búsquedas)
       ---------------------------------------------------------------------------------------- */
    DECLARE v_Id_Subdireccion INT DEFAULT NULL;
    DECLARE v_Clave           VARCHAR(50)  DEFAULT NULL;
    DECLARE v_Nombre          VARCHAR(255) DEFAULT NULL;
    DECLARE v_Activo          TINYINT(1)   DEFAULT NULL;

    /* Variables para validar Dirección padre con lock */
    DECLARE v_Direccion_Existe INT DEFAULT NULL;
    DECLARE v_Direccion_Activo TINYINT(1) DEFAULT NULL;

    /* Bandera de duplicado por concurrencia (error 1062) */
    DECLARE v_Dup TINYINT(1) DEFAULT 0;

    /* ----------------------------------------------------------------------------------------
       HANDLERS
       - 1062: NO salimos del SP. Marcamos bandera y el flujo continúa.
       - SQLEXCEPTION: cualquier error distinto => rollback y relanzar.
       ---------------------------------------------------------------------------------------- */
    DECLARE CONTINUE HANDLER FOR 1062
    BEGIN
        SET v_Dup = 1;
    END;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    /* ----------------------------------------------------------------------------------------
       NORMALIZACIÓN (evita duplicados por espacios o strings vacíos)
       ---------------------------------------------------------------------------------------- */
    SET _Clave  = NULLIF(TRIM(_Clave), '');
    SET _Nombre = NULLIF(TRIM(_Nombre), '');

    /* ----------------------------------------------------------------------------------------
       VALIDACIONES BÁSICAS (rápidas, antes de tocar datos)
       ---------------------------------------------------------------------------------------- */
    IF _Fk_Id_CatDirecc IS NULL OR _Fk_Id_CatDirecc <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Id_CatDirecc inválido (-- DROPdown).';
    END IF;

    IF _Clave IS NULL OR _Nombre IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Clave y Nombre de la Subdirección son obligatorios.';
    END IF;

    /* ========================================================================================
       TRANSACCIÓN PRINCIPAL (INTENTO NORMAL)
       ======================================================================================== */
    START TRANSACTION;

    /* ----------------------------------------------------------------------------------------
       PASO 0) BLOQUEAR Y VALIDAR DIRECCIÓN PADRE
       - Esto evita carreras raras donde:
           * alguien desactiva la Dirección mientras tú estás registrando una Subdirección
       - Como tu UI lista solo activos, normalmente siempre pasa.
       - Aun así, se blinda el sistema ante requests manipuladas.
       ---------------------------------------------------------------------------------------- */
    SET v_Direccion_Existe = NULL; 
    SET v_Direccion_Activo = NULL;

    SELECT 1, Activo
      INTO v_Direccion_Existe, v_Direccion_Activo
    FROM Cat_Direcciones
    WHERE Id_CatDirecc = _Fk_Id_CatDirecc
    LIMIT 1
    FOR UPDATE;

    IF v_Direccion_Existe IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: La Dirección padre no existe.';
    END IF;

    IF v_Direccion_Activo <> 1 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: La Dirección está inactiva. No puedes registrar Subdirecciones ahí.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 1) BUSCAR POR CLAVE DENTRO DE LA DIRECCIÓN (REGLA PRINCIPAL)
       - Si existe, se bloquea la fila Subdirección (FOR UPDATE).
       - Si no existe, NO hay lock (y por eso 1062 puede ocurrir en el INSERT).
       ---------------------------------------------------------------------------------------- */
    SET v_Id_Subdireccion = NULL; 
    SET v_Clave = NULL; 
    SET v_Nombre = NULL; 
    SET v_Activo = NULL;

    SELECT Id_CatSubDirec, Clave, Nombre, Activo
      INTO v_Id_Subdireccion, v_Clave, v_Nombre, v_Activo
    FROM Cat_Subdirecciones
    WHERE Clave = _Clave
      AND Fk_Id_CatDirecc = _Fk_Id_CatDirecc
    LIMIT 1
    FOR UPDATE;

    IF v_Id_Subdireccion IS NOT NULL THEN
        /* Conflicto: misma Clave pero distinto Nombre => datos inconsistentes */
        IF v_Nombre <> _Nombre THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'ERROR: Conflicto Subdirección. La Clave ya existe pero el Nombre no coincide (en esa Dirección).';
        END IF;

        /* Existe pero estaba inactivo => se reactiva */
        IF v_Activo = 0 THEN
            UPDATE Cat_Subdirecciones
            SET Activo = 1,
                updated_at = NOW()
            WHERE Id_CatSubDirec = v_Id_Subdireccion;

            COMMIT;
            SELECT 'Subdirección reactivada exitosamente' AS Mensaje,
                   v_Id_Subdireccion AS Id_CatSubDirec,
                   _Fk_Id_CatDirecc AS Id_CatDirecc,
                   'REACTIVADA' AS Accion;
            LEAVE SP;
        END IF;

        /* Existe y está activo => no se permite alta */
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Ya existe una Subdirección ACTIVA con esa Clave en la Dirección seleccionada.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 2) BUSCAR POR NOMBRE DENTRO DE LA DIRECCIÓN (SEGUNDA REGLA)
       - Si existe por Nombre, la Clave debe coincidir.
       ---------------------------------------------------------------------------------------- */
    SET v_Id_Subdireccion = NULL; 
    SET v_Clave = NULL; 
    SET v_Nombre = NULL; 
    SET v_Activo = NULL;

    SELECT Id_CatSubDirec, Clave, Nombre, Activo
      INTO v_Id_Subdireccion, v_Clave, v_Nombre, v_Activo
    FROM Cat_Subdirecciones
    WHERE Nombre = _Nombre
      AND Fk_Id_CatDirecc = _Fk_Id_CatDirecc
    LIMIT 1
    FOR UPDATE;

    IF v_Id_Subdireccion IS NOT NULL THEN
        /* Conflicto: mismo Nombre pero distinta Clave => datos inconsistentes */
        IF v_Clave <> _Clave THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'ERROR: Conflicto Subdirección. El Nombre ya existe pero la Clave no coincide (en esa Dirección).';
        END IF;

        IF v_Activo = 0 THEN
            UPDATE Cat_Subdirecciones
            SET Activo = 1,
                updated_at = NOW()
            WHERE Id_CatSubDirec = v_Id_Subdireccion;

            COMMIT;
            SELECT 'Subdirección reactivada exitosamente' AS Mensaje,
                   v_Id_Subdireccion AS Id_CatSubDirec,
                   _Fk_Id_CatDirecc AS Id_CatDirecc,
                   'REACTIVADA' AS Accion;
            LEAVE SP;
        END IF;

        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Ya existe una Subdirección ACTIVA con ese Nombre en la Dirección seleccionada.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 3) INSERT FINAL
       - Aquí es donde puede aparecer el 1062 por carrera.
       - v_Dup se reinicia antes del INSERT.
       ---------------------------------------------------------------------------------------- */
    SET v_Dup = 0;

    INSERT INTO Cat_Subdirecciones (Clave, Nombre, Fk_Id_CatDirecc)
    VALUES (_Clave, _Nombre, _Fk_Id_CatDirecc);

    /* Si el INSERT NO disparó 1062, todo bien => CREADA */
    IF v_Dup = 0 THEN
        COMMIT;
        SELECT 'Subdirección registrada exitosamente' AS Mensaje,
               LAST_INSERT_ID() AS Id_CatSubDirec,
               _Fk_Id_CatDirecc AS Id_CatDirecc,
               'CREADA' AS Accion;
        LEAVE SP;
    END IF;

    /* ========================================================================================
       SI LLEGAMOS AQUÍ: HUBO 1062 EN EL INSERT
       => ALGUIEN INSERTÓ PRIMERO (CONCURRENCIA / DOBLE SUBMIT)
       => RE-RESOLVE: localizar y devolver REUSADA/REACTIVADA (UX limpia)
       ======================================================================================== */
    ROLLBACK;

    /* Segunda transacción limpia:
       - no arrastrar locks del intento fallido
       - bloquear la fila real con FOR UPDATE si toca reactivar */
    START TRANSACTION;

    /* ----------------------------------------------------------------------------------------
       RE-RESOLVE A) Localizar por CLAVE dentro de la Dirección (más determinístico por UNIQUE)
       ---------------------------------------------------------------------------------------- */
    SET v_Id_Subdireccion = NULL; 
    SET v_Clave = NULL; 
    SET v_Nombre = NULL; 
    SET v_Activo = NULL;

    SELECT Id_CatSubDirec, Clave, Nombre, Activo
      INTO v_Id_Subdireccion, v_Clave, v_Nombre, v_Activo
    FROM Cat_Subdirecciones
    WHERE Clave = _Clave
      AND Fk_Id_CatDirecc = _Fk_Id_CatDirecc
    LIMIT 1
    FOR UPDATE;

    IF v_Id_Subdireccion IS NOT NULL THEN
        /* Si el “ganador” tiene otro Nombre => conflicto real (no es el mismo registro lógico) */
        IF v_Nombre <> _Nombre THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'ERROR: Concurrencia detectada pero hay conflicto: Clave existe con otro Nombre (en esa Dirección).';
        END IF;

        /* Si por alguna razón estaba inactivo => reactivar */
        IF v_Activo = 0 THEN
            UPDATE Cat_Subdirecciones
            SET Activo = 1,
                updated_at = NOW()
            WHERE Id_CatSubDirec = v_Id_Subdireccion;

            COMMIT;
            SELECT 'Subdirección reactivada (re-resuelto por concurrencia)' AS Mensaje,
                   v_Id_Subdireccion AS Id_CatSubDirec,
                   _Fk_Id_CatDirecc AS Id_CatDirecc,
                   'REACTIVADA' AS Accion;
            LEAVE SP;
        END IF;

        /* Ya existe activo => REUSADA (sin error al usuario) */
        COMMIT;
        SELECT 'Subdirección ya existía (reusado por concurrencia)' AS Mensaje,
               v_Id_Subdireccion AS Id_CatSubDirec,
               _Fk_Id_CatDirecc AS Id_CatDirecc,
               'REUSADA' AS Accion;
        LEAVE SP;
    END IF;

    /* ----------------------------------------------------------------------------------------
       RE-RESOLVE B) Si no aparece por Clave (raro), buscar por NOMBRE dentro de la Dirección
       ---------------------------------------------------------------------------------------- */
    SET v_Id_Subdireccion = NULL; 
    SET v_Clave = NULL; 
    SET v_Nombre = NULL; 
    SET v_Activo = NULL;

    SELECT Id_CatSubDirec, Clave, Nombre, Activo
      INTO v_Id_Subdireccion, v_Clave, v_Nombre, v_Activo
    FROM Cat_Subdirecciones
    WHERE Nombre = _Nombre
      AND Fk_Id_CatDirecc = _Fk_Id_CatDirecc
    LIMIT 1
    FOR UPDATE;

    IF v_Id_Subdireccion IS NOT NULL THEN
        IF v_Clave <> _Clave THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'ERROR: Concurrencia detectada pero hay conflicto: Nombre existe con otra Clave (en esa Dirección).';
        END IF;

        IF v_Activo = 0 THEN
            UPDATE Cat_Subdirecciones
            SET Activo = 1,
                updated_at = NOW()
            WHERE Id_CatSubDirec = v_Id_Subdireccion;

            COMMIT;
            SELECT 'Subdirección reactivada (re-resuelto por concurrencia)' AS Mensaje,
                   v_Id_Subdireccion AS Id_CatSubDirec,
                   _Fk_Id_CatDirecc AS Id_CatDirecc,
                   'REACTIVADA' AS Accion;
            LEAVE SP;
        END IF;

        COMMIT;
        SELECT 'Subdirección ya existía (reusado por concurrencia)' AS Mensaje,
               v_Id_Subdireccion AS Id_CatSubDirec,
               _Fk_Id_CatDirecc AS Id_CatDirecc,
               'REUSADA' AS Accion;
        LEAVE SP;
    END IF;

    /* Caso ultra raro: 1062 ocurrió pero no encontramos el registro */
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ERROR: Concurrencia detectada (1062) pero no se pudo localizar la Subdirección. Refresca y reintenta.';

END$$

DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_EditarSubdireccion  (VERSIÓN PRO “REAL”: Lock determinístico + SIN CAMBIOS + 1062 controlado)
   ============================================================================================

   OBJETIVO
   --------
   Editar una Subdirección existente permitiendo:
   - Cambiar Clave
   - Cambiar Nombre
   - (Opcionalmente) moverla a otra Dirección (Fk_Id_CatDirecc)

   ¿CUÁNDO SE USA?
   --------------
   - Formulario “Editar Subdirección”
   - El usuario modifica:
        * _Nuevo_Clave
        * _Nuevo_Nombre
     y elige en -- DROPdown:
        * _Nuevo_Id_Direccion (solo direcciones activas listadas por UI)

   REGLAS (CONTRATO DE NEGOCIO)
   ----------------------------
   1) La Subdirección a editar DEBE existir.
      - Se bloquea su fila con FOR UPDATE para que nadie la edite al mismo tiempo.
   2) La Dirección destino DEBE existir y estar Activa=1.
      - La UI normalmente solo lista activas, pero aquí lo exigimos en backend.
   3) Anti-duplicados en la Dirección destino:
      - NO puede existir OTRA Subdirección en la Dirección destino con la misma Clave.
        (UNIQUE compuesto: (Fk_Id_CatDirecc, Clave))
      - NO puede existir OTRA Subdirección en la Dirección destino con el mismo Nombre.
        (UNIQUE compuesto: (Fk_Id_CatDirecc, Nombre))
      - Se excluye el mismo Id_CatSubDirec para permitir “guardar sin cambios”.
   4) Si el usuario no cambió nada (Clave, Nombre y Dirección iguales) => “SIN_CAMBIOS”.
   5) Se ejecuta el UPDATE.
   6) Si por concurrencia ocurre 1062 en UPDATE => respuesta “CONFLICTO” controlada.

   PRO “DE VERDAD”: LOCK DETERMINÍSTICO DE DIRECCIONES (ANTI-DEADLOCKS)
   --------------------------------------------------------------------
   PROBLEMA:
   - Si una transacción mueve Subdirección X de Dirección A -> Dirección B
     y otra transacción mueve Subdirección Y de Dirección B -> Dirección A
     pueden terminar bloqueando direcciones en orden diferente => deadlock.
   SOLUCIÓN:
   - Bloquear direcciones SIEMPRE en el mismo orden numérico:
        Dir_Low  = min(DirActual, DirDestino)
        Dir_High = max(DirActual, DirDestino)
     y se bloquean en ese orden con FOR UPDATE.

   RESULTADO
   ---------
   ÉXITO:
      - Mensaje, Accion='ACTUALIZADA', Id_CatSubDirec, Id_Direccion...

   SIN CAMBIOS:
      - Mensaje, Accion='SIN_CAMBIOS', Id_CatSubDirec...

   CONFLICTO (1062):
      - Mensaje, Accion='CONFLICTO', Campo='CLAVE'|'NOMBRE', Id_Conflicto...
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS SP_EditarSubdireccion$$
CREATE PROCEDURE SP_EditarSubdireccion(
    IN _Id_CatSubDirec INT,
    IN _Nuevo_Clave VARCHAR(50),
    IN _Nuevo_Nombre VARCHAR(255),
    IN _Nuevo_Id_Direccion INT
)
SP: BEGIN
    /* ========================================================================================
       PARTE 0) VARIABLES
       ======================================================================================== */

    /* Datos actuales (para poder detectar “SIN CAMBIOS”) */
    DECLARE v_Clave_Actual VARCHAR(50)   DEFAULT NULL;
    DECLARE v_Nombre_Actual VARCHAR(255) DEFAULT NULL;
    DECLARE v_Id_Direccion_Actual INT    DEFAULT NULL;

    /* Auxiliares de validación / duplicidad */
    DECLARE v_Existe INT DEFAULT NULL;
    DECLARE v_DupId INT DEFAULT NULL;

    /* Bandera de choque 1062 en UPDATE */
    DECLARE v_Dup TINYINT(1) DEFAULT 0;

    /* Datos para respuesta de conflicto controlado */
    DECLARE v_Id_Conflicto INT DEFAULT NULL;
    DECLARE v_Campo_Conflicto VARCHAR(20) DEFAULT NULL;

    /* Para lock determinístico de direcciones */
    DECLARE v_Dir_Low INT DEFAULT NULL;
    DECLARE v_Dir_High INT DEFAULT NULL;

    /* ========================================================================================
       PARTE 1) HANDLERS
       ======================================================================================== */

    /* 1062 (Duplicate entry):
       - No abortamos el SP de golpe.
       - Marcamos v_Dup = 1 para regresar “CONFLICTO” controlado.
    */
    DECLARE CONTINUE HANDLER FOR 1062
    BEGIN
        SET v_Dup = 1;
    END;

    /* Cualquier otro error SQL:
       - rollback + relanzar error real
    */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    /* ========================================================================================
       PARTE 2) NORMALIZACIÓN
       ======================================================================================== */
    SET _Nuevo_Clave = NULLIF(TRIM(_Nuevo_Clave), '');
    SET _Nuevo_Nombre = NULLIF(TRIM(_Nuevo_Nombre), '');

    /* ========================================================================================
       PARTE 3) VALIDACIONES BÁSICAS
       ======================================================================================== */
    IF _Id_CatSubDirec IS NULL OR _Id_CatSubDirec <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Id_CatSubDirec inválido.';
    END IF;

    IF _Nuevo_Id_Direccion IS NULL OR _Nuevo_Id_Direccion <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Id_Direccion destino inválido.';
    END IF;

    IF _Nuevo_Clave IS NULL OR _Nuevo_Nombre IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Clave y Nombre de la Subdirección son obligatorios.';
    END IF;

    /* ========================================================================================
       PARTE 4) TRANSACCIÓN PRINCIPAL
       ======================================================================================== */
    START TRANSACTION;

    /* ----------------------------------------------------------------------------------------
       PASO 1) Bloquear la Subdirección a editar y leer sus valores actuales
       ----------------------------------------------------------------------------------------
       - FOR UPDATE bloquea la fila de la Subdirección => nadie la edita en paralelo.
       - De aquí sacamos:
           * v_Clave_Actual
           * v_Nombre_Actual
           * v_Id_Direccion_Actual (para lock determinístico entre Dirección actual y destino)
       ---------------------------------------------------------------------------------------- */
    SET v_Clave_Actual = NULL;
    SET v_Nombre_Actual = NULL;
    SET v_Id_Direccion_Actual = NULL;

    SELECT
        S.Clave,
        S.Nombre,
        S.Fk_Id_CatDirecc
    INTO
        v_Clave_Actual,
        v_Nombre_Actual,
        v_Id_Direccion_Actual
    FROM Cat_Subdirecciones S
    WHERE S.Id_CatSubDirec = _Id_CatSubDirec
    LIMIT 1
    FOR UPDATE;

    IF v_Id_Direccion_Actual IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: La Subdirección no existe.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 2) LOCK DETERMINÍSTICO DE DIRECCIONES (anti-deadlocks)
       ----------------------------------------------------------------------------------------
       - Vamos a bloquear SIEMPRE las direcciones en el mismo orden numérico:
           Dir_Low  = min(DirActual, DirDestino)
           Dir_High = max(DirActual, DirDestino)
       - Esto evita deadlocks cuando hay movimientos cruzados A<->B en paralelo.
       ---------------------------------------------------------------------------------------- */
    IF v_Id_Direccion_Actual = _Nuevo_Id_Direccion THEN
        SET v_Dir_Low  = v_Id_Direccion_Actual;
        SET v_Dir_High = v_Id_Direccion_Actual;
    ELSE
        SET v_Dir_Low  = LEAST(v_Id_Direccion_Actual, _Nuevo_Id_Direccion);
        SET v_Dir_High = GREATEST(v_Id_Direccion_Actual, _Nuevo_Id_Direccion);
    END IF;

    /* 2.1) Bloquear Dirección LOW (debe existir) */
    SET v_Existe = NULL;

    SELECT 1
      INTO v_Existe
    FROM Cat_Direcciones
    WHERE Id_CatDirecc = v_Dir_Low
    LIMIT 1
    FOR UPDATE;

    IF v_Existe IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Inconsistencia: Dirección (low) no existe.';
    END IF;

    /* 2.2) Bloquear Dirección HIGH (si es distinta) */
    IF v_Dir_High <> v_Dir_Low THEN
        SET v_Existe = NULL;

        SELECT 1
          INTO v_Existe
        FROM Cat_Direcciones
        WHERE Id_CatDirecc = v_Dir_High
        LIMIT 1
        FOR UPDATE;

        IF v_Existe IS NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Inconsistencia: Dirección (high) no existe.';
        END IF;
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 3) Validar Dirección destino ACTIVA (contrato con UI)
       ----------------------------------------------------------------------------------------
       - La UI normalmente lista solo direcciones activas.
       - Aquí lo exigimos para impedir:
           * “guardar” hacia una dirección que se desactivó mientras el usuario editaba.
       - FOR UPDATE aquí es redundante porque ya bloqueamos en PASO 2,
         pero lo dejamos por claridad del “contrato”.
       ---------------------------------------------------------------------------------------- */
    SET v_Existe = NULL;

    SELECT 1
      INTO v_Existe
    FROM Cat_Direcciones
    WHERE Id_CatDirecc = _Nuevo_Id_Direccion
      AND Activo = 1
    LIMIT 1
    FOR UPDATE;

    IF v_Existe IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: La Dirección destino no existe o está inactiva.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 4) SIN CAMBIOS (salida temprana)
       ----------------------------------------------------------------------------------------
       - Si no cambió:
           * Clave
           * Nombre
           * Dirección
         devolvemos “SIN_CAMBIOS”.
       - COMMIT inmediato => libera locks rápido (mejor concurrencia).
       ---------------------------------------------------------------------------------------- */
    IF v_Clave_Actual = _Nuevo_Clave
       AND v_Nombre_Actual = _Nuevo_Nombre
       AND v_Id_Direccion_Actual = _Nuevo_Id_Direccion THEN

        COMMIT;

        SELECT 'Sin cambios: La Subdirección ya tiene esos datos y ya pertenece a esa Dirección.' AS Mensaje,
               'SIN_CAMBIOS' AS Accion,
               _Id_CatSubDirec AS Id_CatSubDirec,
               _Nuevo_Id_Direccion AS Id_Direccion,            -- alias compatible
               v_Id_Direccion_Actual AS Id_Direccion_Anterior,
               _Nuevo_Id_Direccion AS Id_Direccion_Nueva;
        LEAVE SP;
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 5) Pre-check duplicidad por CLAVE en la Dirección destino (excluyendo el mismo Id)
       ----------------------------------------------------------------------------------------
       - Reglas:
         * Dentro de la misma Dirección destino, la Clave debe ser única.
         * Excluimos el mismo Id_CatSubDirec para permitir actualización del propio registro.
       - ORDER BY Id: lock determinístico.
       - FOR UPDATE: si encuentra duplicado, bloquea esa fila durante tu TX.
       ---------------------------------------------------------------------------------------- */
    SET v_DupId = NULL;

    SELECT Id_CatSubDirec
      INTO v_DupId
    FROM Cat_Subdirecciones
    WHERE Fk_Id_CatDirecc = _Nuevo_Id_Direccion
      AND Clave = _Nuevo_Clave
      AND Id_CatSubDirec <> _Id_CatSubDirec
    ORDER BY Id_CatSubDirec
    LIMIT 1
    FOR UPDATE;

    IF v_DupId IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Ya existe OTRA Subdirección con esa CLAVE en la Dirección destino.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 6) Pre-check duplicidad por NOMBRE en la Dirección destino (excluyendo el mismo Id)
       ---------------------------------------------------------------------------------------- */
    SET v_DupId = NULL;

    SELECT Id_CatSubDirec
      INTO v_DupId
    FROM Cat_Subdirecciones
    WHERE Fk_Id_CatDirecc = _Nuevo_Id_Direccion
      AND Nombre = _Nuevo_Nombre
      AND Id_CatSubDirec <> _Id_CatSubDirec
    ORDER BY Id_CatSubDirec
    LIMIT 1
    FOR UPDATE;

    IF v_DupId IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Ya existe OTRA Subdirección con ese NOMBRE en la Dirección destino.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 7) UPDATE FINAL (aquí puede aparecer 1062 por carrera)
       ----------------------------------------------------------------------------------------
       - Reseteamos v_Dup=0 antes del UPDATE para detectar si el handler se disparó aquí.
       ---------------------------------------------------------------------------------------- */
    SET v_Dup = 0;

    UPDATE Cat_Subdirecciones
    SET Clave = _Nuevo_Clave,
        Nombre = _Nuevo_Nombre,
        Fk_Id_CatDirecc = _Nuevo_Id_Direccion,
        updated_at = NOW()
    WHERE Id_CatSubDirec = _Id_CatSubDirec;

    /* ----------------------------------------------------------------------------------------
       PASO 8) Si hubo 1062 => CONFLICTO CONTROLADO
       ----------------------------------------------------------------------------------------
       - ROLLBACK: no guardamos nada.
       - Buscamos el Id_CatSubDirec que “ganó” el valor en la Dirección destino:
           * primero por CLAVE
           * si no, por NOMBRE
       - Devolvemos respuesta clara para UI.
       ---------------------------------------------------------------------------------------- */
    IF v_Dup = 1 THEN
        ROLLBACK;

        SET v_Id_Conflicto = NULL;
        SET v_Campo_Conflicto = NULL;

        /* 8.1) Conflicto por CLAVE */
        SELECT Id_CatSubDirec
          INTO v_Id_Conflicto
        FROM Cat_Subdirecciones
        WHERE Fk_Id_CatDirecc = _Nuevo_Id_Direccion
          AND Clave = _Nuevo_Clave
          AND Id_CatSubDirec <> _Id_CatSubDirec
        ORDER BY Id_CatSubDirec
        LIMIT 1;

        IF v_Id_Conflicto IS NOT NULL THEN
            SET v_Campo_Conflicto = 'CLAVE';
        ELSE
            /* 8.2) Conflicto por NOMBRE */
            SELECT Id_CatSubDirec
              INTO v_Id_Conflicto
            FROM Cat_Subdirecciones
            WHERE Fk_Id_CatDirecc = _Nuevo_Id_Direccion
              AND Nombre = _Nuevo_Nombre
              AND Id_CatSubDirec <> _Id_CatSubDirec
            ORDER BY Id_CatSubDirec
            LIMIT 1;

            IF v_Id_Conflicto IS NOT NULL THEN
                SET v_Campo_Conflicto = 'NOMBRE';
            END IF;
        END IF;

        SELECT 'No se guardó: otro usuario se adelantó. Refresca y vuelve a intentar.' AS Mensaje,
               'CONFLICTO' AS Accion,
               v_Campo_Conflicto AS Campo,
               v_Id_Conflicto AS Id_Conflicto,
               _Id_CatSubDirec AS Id_Subdireccion_Que_Intentabas_Editar,
               _Nuevo_Id_Direccion AS Id_Direccion_Destino,
               v_Id_Direccion_Actual AS Id_Direccion_Anterior,
               _Nuevo_Id_Direccion AS Id_Direccion_Nueva;
        LEAVE SP;
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 9) ÉXITO
       ---------------------------------------------------------------------------------------- */
    COMMIT;

    SELECT 'Subdirección actualizada correctamente' AS Mensaje,
           'ACTUALIZADA' AS Accion,
           _Id_CatSubDirec AS Id_CatSubDirec,
           _Nuevo_Id_Direccion AS Id_Direccion,            -- alias compatible
           v_Id_Direccion_Actual AS Id_Direccion_Anterior,
           _Nuevo_Id_Direccion AS Id_Direccion_Nueva;

END$$

DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_CambiarEstatusSubdireccion
   ============================================================================================
   OBJETIVO
   --------
   Activar/Desactivar (borrado lógico) una Subdirección:
      Cat_Subdirecciones.Activo (1 = activo, 0 = inactivo)

   REGLAS CRÍTICAS (INTEGRIDAD JERÁRQUICA)
   --------------------------------------
   A) Al DESACTIVAR una Subdirección (Activo=0):
      - NO se permite si tiene GERENCIAS ACTIVAS.
        Evita: Subdirección=0 con Gerencia=1 (Hijo Huérfano).

   B) Al ACTIVAR una Subdirección (Activo=1)  <<<<<<<<<<<< CANDADO JERÁRQUICO
      - NO se permite si su DIRECCIÓN PADRE está INACTIVA.
        Evita: Dirección=0 con Subdirección=1 (inconsistencia lógica y visual en UI).

   CONCURRENCIA / BLOQUEOS
   -----------------------
   - Bloqueamos en orden jerárquico: DIRECCIÓN -> SUBDIRECCIÓN
   - Usamos STRAIGHT_JOIN + FOR UPDATE para:
        * asegurar el orden de lectura/bloqueo
        * evitar carreras donde la Dirección cambie de estatus mientras activas la Subdirección.
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS SP_CambiarEstatusSubdireccion$$
CREATE PROCEDURE SP_CambiarEstatusSubdireccion(
    IN _Id_CatSubDirec INT,
    IN _Nuevo_Estatus TINYINT -- 1 = Activo, 0 = Inactivo
)
BEGIN
    /* ----------------------------------------------------------------------------------------
       VARIABLES
       ---------------------------------------------------------------------------------------- */
    DECLARE v_Existe INT DEFAULT NULL;

    /* Estatus actual de la Subdirección */
    DECLARE v_Activo_Actual TINYINT(1) DEFAULT NULL;

    /* Datos del padre (Dirección) para el candado jerárquico al ACTIVAR */
    DECLARE v_Id_Direccion INT DEFAULT NULL;
    DECLARE v_Direccion_Activo TINYINT(1) DEFAULT NULL;

    /* Auxiliar para candados */
    DECLARE v_Tmp INT DEFAULT NULL;

    /* ----------------------------------------------------------------------------------------
       HANDLER GENERAL
       - Si cualquier SQL falla: ROLLBACK y relanza el error real
       ---------------------------------------------------------------------------------------- */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    /* ----------------------------------------------------------------------------------------
       VALIDACIONES DE PARÁMETROS
       ---------------------------------------------------------------------------------------- */
    IF _Id_CatSubDirec IS NULL OR _Id_CatSubDirec <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Id_CatSubDirec inválido.';
    END IF;

    IF _Nuevo_Estatus NOT IN (0,1) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Estatus inválido (solo 0 o 1).';
    END IF;

    START TRANSACTION;

    /* ----------------------------------------------------------------------------------------
       1) VALIDAR EXISTENCIA Y BLOQUEAR FILAS EN ORDEN JERÁRQUICO (DIRECCIÓN -> SUBDIRECCIÓN)
       ----------------------------------------------------------------------------------------
       ¿POR QUÉ ASÍ?
       - Para el CANDADO (B) necesitamos consultar Dirección.Activo.
       - Si solo lo "lees" sin bloquear, otro proceso podría apagar la Dirección al mismo tiempo.
       - Con este SELECT ... FOR UPDATE, bloqueas AMBOS: Dirección y Subdirección (en orden).
       ---------------------------------------------------------------------------------------- */
    SELECT
        1 AS Existe,
        S.Activo AS Activo_Subdireccion,
        S.Fk_Id_CatDirecc AS Id_Direccion,
        D.Activo AS Activo_Direccion
    INTO
        v_Existe,
        v_Activo_Actual,
        v_Id_Direccion,
        v_Direccion_Activo
    FROM Cat_Direcciones D
    STRAIGHT_JOIN Cat_Subdirecciones S ON S.Fk_Id_CatDirecc = D.Id_CatDirecc
    WHERE S.Id_CatSubDirec = _Id_CatSubDirec
    LIMIT 1
    FOR UPDATE;

    IF v_Existe IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: La Subdirección no existe.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       2) "SIN CAMBIOS" (IDEMPOTENCIA)
       - Si ya está en ese estado, no hacemos nada.
       ---------------------------------------------------------------------------------------- */
    IF v_Activo_Actual = _Nuevo_Estatus THEN
        COMMIT;
        SELECT CASE
            WHEN _Nuevo_Estatus = 1 THEN 'Sin cambios: La Subdirección ya estaba Activa.'
            ELSE 'Sin cambios: La Subdirección ya estaba Inactiva.'
        END AS Mensaje,
        v_Activo_Actual AS Activo_Anterior,
        _Nuevo_Estatus AS Activo_Nuevo;
    ELSE

        /* ------------------------------------------------------------------------------------
           3) CANDADO JERÁRQUICO AL ACTIVAR (B)
           ------------------------------------------------------------------------------------
           REGLA:
           - Si quieres ACTIVAR Subdirección (Nuevo_Estatus=1),
             su Dirección padre DEBE estar ACTIVA.
           - Si la Dirección está inactiva, bloquear con mensaje claro.
           ------------------------------------------------------------------------------------ */
        IF _Nuevo_Estatus = 1 THEN
            IF v_Direccion_Activo = 0 THEN
                SIGNAL SQLSTATE '45000'
                    SET MESSAGE_TEXT = 'BLOQUEADO: No se puede ACTIVAR la Subdirección porque su DIRECCIÓN PADRE está INACTIVA. Activa primero la Dirección.';
            END IF;
        END IF;

        /* ------------------------------------------------------------------------------------
           4) SI INTENTA DESACTIVAR: BLOQUEAR SI HAY GERENCIAS ACTIVAS (regla original)
           ------------------------------------------------------------------------------------ */
        IF _Nuevo_Estatus = 0 THEN
            SET v_Tmp = NULL;
            
            SELECT Id_CatGeren
              INTO v_Tmp
            FROM Cat_Gerencias_Activos
            WHERE Fk_Id_CatSubDirec = _Id_CatSubDirec
              AND Activo = 1
            LIMIT 1;

            IF v_Tmp IS NOT NULL THEN
                SIGNAL SQLSTATE '45000'
                    SET MESSAGE_TEXT = 'BLOQUEADO: No se puede desactivar la Subdirección porque tiene GERENCIAS ACTIVAS. Desactiva primero las Gerencias.';
            END IF;
        END IF;

        /* ------------------------------------------------------------------------------------
           5) APLICAR CAMBIO DE ESTATUS
           ------------------------------------------------------------------------------------ */
        UPDATE Cat_Subdirecciones
        SET Activo = _Nuevo_Estatus,
            updated_at = NOW()
        WHERE Id_CatSubDirec = _Id_CatSubDirec;

        COMMIT;

        /* ------------------------------------------------------------------------------------
           6) RESPUESTA PARA FRONTEND
           ------------------------------------------------------------------------------------ */
        SELECT CASE
            WHEN _Nuevo_Estatus = 1 THEN 'Subdirección Reactivada'
            ELSE 'Subdirección Desactivada'
        END AS Mensaje,
        v_Activo_Actual AS Activo_Anterior,
        _Nuevo_Estatus AS Activo_Nuevo;
    END IF;

END$$

DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_EliminarSubdireccionFisica
   ============================================================================================
   OBJETIVO
   --------
   Eliminar físicamente una Subdirección, solo si NO tiene Gerencias asociadas.

   ¿CUÁNDO SE USA?
   --------------
   - Limpieza controlada de catálogo (muy raro en producción, solo Admin).
   - Correcciones cuando la Subdirección fue creada por error y aún no tiene hijos.

   CANDADO DE SEGURIDAD (INTEGRIDAD)
   ---------------------------------
   - Si existe al menos una Gerencia con Fk_Id_CatSubDirec = _Id_CatSubDirec, 
     se bloquea el DELETE inmediatamente.
   - Esto evita romper la integridad del catálogo y dejar gerencias huérfanas.

   VALIDACIONES
   ------------
   - La Subdirección debe existir.
   - No debe tener Gerencias asociadas (activas o inactivas).

   RESPUESTA
   ---------
   - Mensaje de confirmación si se elimina correctamente.
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS SP_EliminarSubdireccionFisica$$
CREATE PROCEDURE SP_EliminarSubdireccionFisica(
    IN _Id_CatSubDirec INT
)
BEGIN
    /* ----------------------------------------------------------------------------------------
       HANDLERS DE ERROR
       ---------------------------------------------------------------------------------------- */
    
    /* Handler para Foreign Keys (Error 1451 de MySQL) */
    DECLARE EXIT HANDLER FOR 1451
    BEGIN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'ERROR: No se puede eliminar la Subdirección porque está referenciada por otros registros (FK).';
    END;

    /* Handler general */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    /* ----------------------------------------------------------------------------------------
       VALIDACIONES BÁSICAS
       ---------------------------------------------------------------------------------------- */
    
    /* Validación de ID */
    IF _Id_CatSubDirec IS NULL OR _Id_CatSubDirec <= 0 THEN
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'ERROR: Id_CatSubDirec inválido.';
    END IF;

    /* Validación de Existencia */
    IF NOT EXISTS(SELECT 1 FROM Cat_Subdirecciones WHERE Id_CatSubDirec = _Id_CatSubDirec) THEN
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'ERROR: La Subdirección no existe.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       CANDADO DE NEGOCIO: REVISAR DEPENDENCIAS (HIJOS)
       - Buscamos manualmente si existen Gerencias antes de intentar el DELETE.
       ---------------------------------------------------------------------------------------- */
    IF EXISTS(SELECT 1 FROM Cat_Gerencias_Activos WHERE Fk_Id_CatSubDirec = _Id_CatSubDirec) THEN
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'ERROR CRÍTICO: No se puede eliminar la Subdirección porque tiene GERENCIAS asociadas.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       TRANSACCIÓN DE BORRADO
       ---------------------------------------------------------------------------------------- */
    START TRANSACTION;

    DELETE FROM Cat_Subdirecciones
    WHERE Id_CatSubDirec = _Id_CatSubDirec;

    COMMIT;

    SELECT 'Subdirección eliminada permanentemente' AS Mensaje;
END$$

DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_RegistrarGerencia  (VERSIÓN PRO: 1062 => RE-RESOLVE)
   ============================================================================================
   OBJETIVO
   --------
   Registrar una nueva Gerencia dentro de una Subdirección específica (seleccionada por -- DROPdown),
   con blindaje fuerte contra duplicados y con manejo PRO de concurrencia (doble-submit).

   ¿CUÁNDO SE USA?
   --------------
   - Formulario “Alta de Gerencia”.
   - El usuario captura:
        * _Codigo  (ej: 'GER-RH')  -> Clave
        * _Nombre  (ej: 'GERENCIA DE CAPITAL HUMANO')
     y selecciona por -- DROPdown:
        * _Id_Direccion_Seleccionada  (solo direcciones ACTIVO=1, usado para filtrar subdirecciones)
        * _Id_Subdireccion            (solo subdirecciones ACTIVO=1 que pertenecen a esa dirección)

   REGLAS (CONTRATO DE NEGOCIO)
   ----------------------------
   Dentro de la Subdirección _Id_Subdireccion se aplica la misma regla determinística:

   1) Buscar primero por CLAVE dentro de la Subdirección (regla principal).
      - Si existe:
          a) El NOMBRE debe coincidir, si no => ERROR (conflicto Clave <-> Nombre).
          b) Si Activo=0 => REACTIVAR (UPDATE Activo=1) y devolver 'REACTIVADA'.
          c) Si Activo=1 => ERROR (ya existe activo).

   2) Si no existe por CLAVE, buscar por NOMBRE dentro de la Subdirección.
      - Si existe:
          a) La CLAVE debe coincidir, si no => ERROR (conflicto Nombre <-> Clave).
          b) Si Activo=0 => REACTIVAR y devolver 'REACTIVADA'.
          c) Si Activo=1 => ERROR (ya existe activo).

   3) Si no existe por ninguno => INSERT y devolver 'CREADA'.

   VALIDACIÓN JERÁRQUICA (DIRECCIÓN -> SUBDIRECCIÓN)
   -------------------------------------------------
   Aunque el frontend use -- DROPdowns (y “debería” mandar combos válidos), este SP valida:
   - La Dirección (Abuelo) existe y está ACTIVA.
   - La Subdirección (Padre) existe, está ACTIVA y pertenece a esa Dirección.
   Esto blinda el backend ante:
   - Requests manipuladas.
   - Bugs del frontend.
   - Datos “viejos” en cache del navegador (usuario deja la pantalla abierta y cambia catálogo).

   CONCURRENCIA (EL PROBLEMA REAL)
   -------------------------------
   - SELECT ... FOR UPDATE solo bloquea si la fila existe.
   - Si la Gerencia no existe todavía:
        * Dos usuarios pueden pasar los SELECT sin bloquear nada.
        * Ambos intentan INSERT.
        * Uno gana, el otro cae en 1062 (por UNIQUE).
   Tu tabla Gerencias tiene UNIQUE:
      - Uk_Gerencia_Clave_Subdireccion UNIQUE (Clave, Fk_Id_CatSubDirec)
      - Uk_Gerencia_Nombre_Subdireccion UNIQUE (Nombre, Fk_Id_CatSubDirec)

   SOLUCIÓN PRO: 1062 => “RE-RESOLVE”
   ---------------------------------
   En vez de mostrar error al segundo usuario:
   - Detectamos 1062 (handler).
   - ROLLBACK del intento.
   - Nueva transacción.
   - Localizamos el registro “ganador”.
   - Devolvemos:
        Accion='REUSADA' (ya existía activa)
     o Accion='REACTIVADA' (si estaba inactivo).

   IMPORTANTE: ¿POR QUÉ SE RESETEAN VARIABLES A NULL ANTES DE CADA SELECT INTO?
   ----------------------------------------------------------------------------
   En MySQL, si un SELECT ... INTO no encuentra filas:
   - NO asigna nada (las variables se quedan con el valor anterior).
   Por eso hacemos:
      SET v_Id_Gerencia = NULL; ...
   antes del SELECT, para que “no encontrado” quede en NULL de forma confiable.

   RESULTADO
   ---------
   Retorna:
     - Mensaje
     - Id_CatGeren
     - Id_Subdireccion
     - Id_Direccion
     - Accion: 'CREADA' | 'REACTIVADA' | 'REUSADA'
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS SP_RegistrarGerencia$$
CREATE PROCEDURE SP_RegistrarGerencia(
    IN _Clave VARCHAR(50),
    IN _Nombre VARCHAR(255),
    IN _Id_Direccion_Seleccionada INT,
    IN _Id_Subdireccion INT
)
SP: BEGIN
    /* ----------------------------------------------------------------------------------------
       VARIABLES DE TRABAJO (resultado de búsquedas)
       ---------------------------------------------------------------------------------------- */
    DECLARE v_Id_Gerencia INT DEFAULT NULL;
    DECLARE v_Clave       VARCHAR(50)  DEFAULT NULL;
    DECLARE v_Nombre      VARCHAR(255) DEFAULT NULL;
    DECLARE v_Activo      TINYINT(1)   DEFAULT NULL;

    /* Variables para validar y BLOQUEAR jerarquía padre (Dirección y Subdirección) */
    DECLARE v_Direccion_Existe  INT DEFAULT NULL;
    DECLARE v_Direccion_Activo  TINYINT(1) DEFAULT NULL;

    DECLARE v_Subdireccion_Existe INT DEFAULT NULL;
    DECLARE v_Subdireccion_Activo TINYINT(1) DEFAULT NULL;
    DECLARE v_Subdireccion_Direccion INT DEFAULT NULL;

    /* Bandera de duplicado por concurrencia (error 1062) */
    DECLARE v_Dup TINYINT(1) DEFAULT 0;

    /* ----------------------------------------------------------------------------------------
       HANDLERS
       - 1062: NO salimos del SP. Marcamos bandera y el flujo continúa.
       - SQLEXCEPTION: cualquier error distinto => rollback y relanzar.
       ---------------------------------------------------------------------------------------- */
    DECLARE CONTINUE HANDLER FOR 1062
    BEGIN
        SET v_Dup = 1;
    END;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    /* ----------------------------------------------------------------------------------------
       NORMALIZACIÓN
       - TRIM evita "GERENCIA " vs "GERENCIA"
       - NULLIF convierte '' a NULL para detectar vacíos
       ---------------------------------------------------------------------------------------- */
    SET _Clave  = NULLIF(TRIM(_Clave), '');
    SET _Nombre = NULLIF(TRIM(_Nombre), '');

    /* ----------------------------------------------------------------------------------------
       VALIDACIONES BÁSICAS (rápidas, antes de tocar datos)
       ---------------------------------------------------------------------------------------- */
    IF _Clave IS NULL OR _Nombre IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Clave y Nombre de la Gerencia son obligatorios.';
    END IF;

    IF _Id_Direccion_Seleccionada IS NULL OR _Id_Direccion_Seleccionada <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Id_Direccion seleccionada inválido (-- DROPdown).';
    END IF;

    IF _Id_Subdireccion IS NULL OR _Id_Subdireccion <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Id_Subdireccion inválido (-- DROPdown).';
    END IF;

    /* ========================================================================================
       TRANSACCIÓN PRINCIPAL (INTENTO NORMAL)
       ======================================================================================== */
    START TRANSACTION;

    /* ----------------------------------------------------------------------------------------
       PASO 0) BLOQUEAR Y VALIDAR DIRECCIÓN (ABUELO)
       - Aunque el -- DROPdown mande solo activos, blindamos backend.
       - FOR UPDATE aquí evita carreras raras con cambios de estatus de la Dirección.
       ---------------------------------------------------------------------------------------- */
    SET v_Direccion_Existe = NULL; 
    SET v_Direccion_Activo = NULL;

    SELECT 1, Activo
      INTO v_Direccion_Existe, v_Direccion_Activo
    FROM Cat_Direcciones
    WHERE Id_CatDirecc = _Id_Direccion_Seleccionada
    LIMIT 1
    FOR UPDATE;

    IF v_Direccion_Existe IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: La Dirección seleccionada no existe.';
    END IF;

    IF v_Direccion_Activo <> 1 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: La Dirección seleccionada está inactiva. No puedes registrar Gerencias ahí.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 1) BLOQUEAR Y VALIDAR SUBDIRECCIÓN (PADRE) + PERTENENCIA A DIRECCIÓN
       - Este es el blindaje “Dirección -> Subdirección”:
            * Subdirección debe existir
            * Subdirección debe estar activa
            * Subdirección debe pertenecer a la Dirección seleccionada
       ---------------------------------------------------------------------------------------- */
    SET v_Subdireccion_Existe = NULL; 
    SET v_Subdireccion_Activo = NULL; 
    SET v_Subdireccion_Direccion = NULL;

    SELECT 1, Activo, Fk_Id_CatDirecc
      INTO v_Subdireccion_Existe, v_Subdireccion_Activo, v_Subdireccion_Direccion
    FROM Cat_Subdirecciones
    WHERE Id_CatSubDirec = _Id_Subdireccion
    LIMIT 1
    FOR UPDATE;

    IF v_Subdireccion_Existe IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: La Subdirección no existe.';
    END IF;

    IF v_Subdireccion_Direccion <> _Id_Direccion_Seleccionada THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: La Subdirección no pertenece a la Dirección seleccionada.';
    END IF;

    IF v_Subdireccion_Activo <> 1 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: La Subdirección está inactiva. No puedes registrar Gerencias ahí.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 2) BUSCAR POR CLAVE DENTRO DE LA SUBDIRECCIÓN (REGLA PRINCIPAL)
       - Si existe fila => FOR UPDATE la bloquea.
       - Si no existe => no hay lock; el candado final será el UNIQUE del INSERT.
       ---------------------------------------------------------------------------------------- */
    SET v_Id_Gerencia = NULL; 
    SET v_Clave = NULL; 
    SET v_Nombre = NULL; 
    SET v_Activo = NULL;

    SELECT Id_CatGeren, Clave, Nombre, Activo
      INTO v_Id_Gerencia, v_Clave, v_Nombre, v_Activo
    FROM Cat_Gerencias_Activos
    WHERE Clave = _Clave
      AND Fk_Id_CatSubDirec = _Id_Subdireccion
    LIMIT 1
    FOR UPDATE;

    IF v_Id_Gerencia IS NOT NULL THEN
        /* Conflicto: misma Clave pero distinto Nombre */
        IF v_Nombre <> _Nombre THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'ERROR: Conflicto Gerencia. La Clave ya existe pero el Nombre no coincide (en esa Subdirección).';
        END IF;

        /* Existe pero estaba inactivo => reactivar */
        IF v_Activo = 0 THEN
            UPDATE Cat_Gerencias_Activos
            SET Activo = 1,
                updated_at = NOW()
            WHERE Id_CatGeren = v_Id_Gerencia;

            COMMIT;
            SELECT 'Gerencia reactivada exitosamente' AS Mensaje,
                   v_Id_Gerencia AS Id_Gerencia,
                   _Id_Subdireccion AS Id_Subdireccion,
                   _Id_Direccion_Seleccionada AS Id_Direccion,
                   'REACTIVADA' AS Accion;
            LEAVE SP;
        END IF;

        /* Existe y está activo => alta bloqueada */
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Ya existe una Gerencia ACTIVA con esa Clave en la Subdirección seleccionada.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 3) BUSCAR POR NOMBRE DENTRO DE LA SUBDIRECCIÓN (SEGUNDA REGLA)
       ---------------------------------------------------------------------------------------- */
    SET v_Id_Gerencia = NULL; 
    SET v_Clave = NULL; 
    SET v_Nombre = NULL; 
    SET v_Activo = NULL;

    SELECT Id_CatGeren, Clave, Nombre, Activo
      INTO v_Id_Gerencia, v_Clave, v_Nombre, v_Activo
    FROM Cat_Gerencias_Activos
    WHERE Nombre = _Nombre
      AND Fk_Id_CatSubDirec = _Id_Subdireccion
    LIMIT 1
    FOR UPDATE;

    IF v_Id_Gerencia IS NOT NULL THEN
        /* Conflicto: mismo Nombre pero distinta Clave */
        IF v_Clave <> _Clave THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'ERROR: Conflicto Gerencia. El Nombre ya existe pero la Clave no coincide (en esa Subdirección).';
        END IF;

        IF v_Activo = 0 THEN
            UPDATE Cat_Gerencias_Activos
            SET Activo = 1,
                updated_at = NOW()
            WHERE Id_CatGeren = v_Id_Gerencia;

            COMMIT;
            SELECT 'Gerencia reactivada exitosamente' AS Mensaje,
                   v_Id_Gerencia AS Id_Gerencia,
                   _Id_Subdireccion AS Id_Subdireccion,
                   _Id_Direccion_Seleccionada AS Id_Direccion,
                   'REACTIVADA' AS Accion;
            LEAVE SP;
        END IF;

        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Ya existe una Gerencia ACTIVA con ese Nombre en la Subdirección seleccionada.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 4) INSERT FINAL
       - Aquí puede aparecer el 1062 por carrera (dos usuarios insertando al mismo tiempo).
       - Reiniciamos v_Dup antes del INSERT.
       ---------------------------------------------------------------------------------------- */
    SET v_Dup = 0;

    INSERT INTO Cat_Gerencias_Activos (Clave, Nombre, Fk_Id_CatSubDirec)
    VALUES (_Clave, _Nombre, _Id_Subdireccion);

    /* Si el INSERT NO disparó 1062 => CREADA */
    IF v_Dup = 0 THEN
        COMMIT;
        SELECT 'Gerencia registrada exitosamente' AS Mensaje,
               LAST_INSERT_ID() AS Id_Gerencia,
               _Id_Subdireccion AS Id_Subdireccion,
               _Id_Direccion_Seleccionada AS Id_Direccion,
               'CREADA' AS Accion;
        LEAVE SP;
    END IF;

    /* ========================================================================================
       SI LLEGAMOS AQUÍ: HUBO 1062 EN EL INSERT
       => ALGUIEN INSERTÓ PRIMERO (CONCURRENCIA / DOBLE SUBMIT)
       => RE-RESOLVE: localizar y devolver REUSADA/REACTIVADA (UX limpia)
       ======================================================================================== */
    ROLLBACK;

    /* Nueva transacción:
       - evitar quedarnos con locks del intento fallido
       - bloquear la fila real con FOR UPDATE si hay que reactivar */
    START TRANSACTION;

    /* ----------------------------------------------------------------------------------------
       RE-RESOLVE A) Localizar por CLAVE dentro de la Subdirección (más determinístico por UNIQUE)
       ---------------------------------------------------------------------------------------- */
    SET v_Id_Gerencia = NULL; 
    SET v_Clave = NULL; 
    SET v_Nombre = NULL; 
    SET v_Activo = NULL;

    SELECT Id_CatGeren, Clave, Nombre, Activo
      INTO v_Id_Gerencia, v_Clave, v_Nombre, v_Activo
    FROM Cat_Gerencias_Activos
    WHERE Clave = _Clave
      AND Fk_Id_CatSubDirec = _Id_Subdireccion
    LIMIT 1
    FOR UPDATE;

    IF v_Id_Gerencia IS NOT NULL THEN
        /* Si el “ganador” tiene otro Nombre => conflicto real */
        IF v_Nombre <> _Nombre THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'ERROR: Concurrencia detectada pero hay conflicto: Clave existe con otro Nombre (en esa Subdirección).';
        END IF;

        /* Si por alguna razón estaba inactivo => reactivar */
        IF v_Activo = 0 THEN
            UPDATE Cat_Gerencias_Activos
            SET Activo = 1,
                updated_at = NOW()
            WHERE Id_CatGeren = v_Id_Gerencia;

            COMMIT;
            SELECT 'Gerencia reactivada (re-resuelto por concurrencia)' AS Mensaje,
                   v_Id_Gerencia AS Id_Gerencia,
                   _Id_Subdireccion AS Id_Subdireccion,
                   _Id_Direccion_Seleccionada AS Id_Direccion,
                   'REACTIVADA' AS Accion;
            LEAVE SP;
        END IF;

        /* Ya existe activo => REUSADA (sin error al usuario) */
        COMMIT;
        SELECT 'Gerencia ya existía (reusado por concurrencia)' AS Mensaje,
               v_Id_Gerencia AS Id_Gerencia,
               _Id_Subdireccion AS Id_Subdireccion,
               _Id_Direccion_Seleccionada AS Id_Direccion,
               'REUSADA' AS Accion;
        LEAVE SP;
    END IF;

    /* ----------------------------------------------------------------------------------------
       RE-RESOLVE B) Si no aparece por Clave, buscar por NOMBRE dentro de la Subdirección
       ---------------------------------------------------------------------------------------- */
    SET v_Id_Gerencia = NULL; 
    SET v_Clave = NULL; 
    SET v_Nombre = NULL; 
    SET v_Activo = NULL;

    SELECT Id_CatGeren, Clave, Nombre, Activo
      INTO v_Id_Gerencia, v_Clave, v_Nombre, v_Activo
    FROM Cat_Gerencias_Activos
    WHERE Nombre = _Nombre
      AND Fk_Id_CatSubDirec = _Id_Subdireccion
    LIMIT 1
    FOR UPDATE;

    IF v_Id_Gerencia IS NOT NULL THEN
        IF v_Clave <> _Clave THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'ERROR: Concurrencia detectada pero hay conflicto: Nombre existe con otra Clave (en esa Subdirección).';
        END IF;

        IF v_Activo = 0 THEN
            UPDATE Cat_Gerencias_Activos
            SET Activo = 1,
                updated_at = NOW()
            WHERE Id_CatGeren = v_Id_Gerencia;

            COMMIT;
            SELECT 'Gerencia reactivada (re-resuelto por concurrencia)' AS Mensaje,
                   v_Id_Gerencia AS Id_Gerencia,
                   _Id_Subdireccion AS Id_Subdireccion,
                   _Id_Direccion_Seleccionada AS Id_Direccion,
                   'REACTIVADA' AS Accion;
            LEAVE SP;
        END IF;

        COMMIT;
        SELECT 'Gerencia ya existía (reusado por concurrencia)' AS Mensaje,
               v_Id_Gerencia AS Id_Gerencia,
               _Id_Subdireccion AS Id_Subdireccion,
               _Id_Direccion_Seleccionada AS Id_Direccion,
               'REUSADA' AS Accion;
        LEAVE SP;
    END IF;

    /* Caso ultra raro: 1062 ocurrió pero no encontramos la fila */
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ERROR: Concurrencia detectada (1062) pero no se pudo localizar la Gerencia. Refresca y reintenta.';

END$$

DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_EditarGerencia  (VERSIÓN PRO “REAL”: Locks determinísticos + JOIN atómico + SIN CAMBIOS + 1062)
   ============================================================================================

   CONTEXTO DE UI (CÓMO FUNCIONA TU FORMULARIO)
   --------------------------------------------
   1) El frontend precarga el registro con SP_ConsultarGerenciaEspecifica:
      - Clave, Nombre, timestamps
      - Dirección actual (Abuelo)
      - Subdirección actual (Padre)

   2) El usuario puede:
      - Cambiar Clave y/o Nombre
      - Cambiar Subdirección destino (dentro de la Dirección actual)
      - O cambiar Dirección (-- DROPdown) => recarga Subdirecciones => elegir nueva Subdirección

   IMPORTANTE (DISEÑO DE DATOS)
   ----------------------------
   - Gerencia NO tiene Fk_Id_CatDirecc.
   - La “Dirección” de una Gerencia se determina por la Subdirección:
         Gerencia.Fk_Id_CatSubDirec -> Subdirección.Fk_Id_CatDirecc
   - Entonces “cambiar Dirección” realmente significa:
         elegir una Subdirección destino que pertenezca a la Dirección elegida.

   ¿POR QUÉ ESTE SP RECIBE _Id_Direccion_Seleccionada SI YA RECIBE _Id_Subdireccion_Destino?
   -----------------------------------------------------------------------------------------
   - Porque tu UI trabaja en cascada Dirección -> Subdirección.
   - En teoría la Subdirección elegida SIEMPRE pertenece a esa Dirección.
   - PERO en backend se valida para blindar contra:
       * requests manipuladas
       * bugs del frontend
       * catálogos cambiaron mientras el usuario editaba
       * subdirecciones cacheadas

   OBJETIVO
   --------
   Editar una Gerencia existente permitiendo:
   - Cambiar Clave
   - Cambiar Nombre
   - Moverla a otra Subdirección (y posiblemente otra Dirección)

   REGLAS (CONTRATO DE NEGOCIO)
   ----------------------------
   1) La Gerencia a editar DEBE existir.
   2) La Dirección seleccionada DEBE existir y estar Activa=1.
   3) La Subdirección destino DEBE:
      - existir
      - estar Activa=1
      - pertenecer a la Dirección seleccionada
   4) Anti-duplicados dentro de la Subdirección destino:
      - NO puede existir OTRA Gerencia con la misma Clave en la Subdirección destino.
      - NO puede existir OTRA Gerencia con el mismo Nombre en la Subdirección destino.
      (se excluye el mismo Id_CatGeren)
   5) Si el usuario realmente no cambió nada => “SIN_CAMBIOS” (no “ACTUALIZADA”).
   6) Se ejecuta el UPDATE.

   CONCURRENCIA (POR QUÉ EXISTE HANDLER 1062 EN UPDATE)
   ----------------------------------------------------
   Aunque hagas pre-checks, puede pasar una carrera:
   - Usuario A y B editan al mismo tiempo hacia la misma (Clave/Nombre + Subdirección destino).
   - Ambos “ven” que no hay duplicado.
   - A guarda primero.
   - B choca con UNIQUE => MySQL lanza 1062.

   SOLUCIÓN PRO EN EDICIÓN: 1062 => CONFLICTO (NO “REUSAR”)
   --------------------------------------------------------
   En EDITAR no queremos usar el registro del otro usuario.
   Queremos avisar:
     - Accion = 'CONFLICTO'
     - Campo  = 'CLAVE' o 'NOMBRE'
     - Id_Conflicto = Id de la gerencia que ya tomó ese valor

   ¿QUÉ CAMBIA vs TU SP ACTUAL?
   ----------------------------
   A) “LOCK DETERMINÍSTICO DE DIRECCIONES”
      - Si la gerencia está en Dirección A y la mueves a Dirección B, dos usuarios cruzados
        pueden provocar deadlocks si bloquean Direcciones en diferente orden.
      - SOLUCIÓN: bloquear SIEMPRE en orden por Id:
          1) Dir LOW  (min(DirActual, DirSeleccionada))
          2) Dir HIGH (max(DirActual, DirSeleccionada))

   B) “JOIN ÚNICO DIRECCIÓN -> SUBDIRECCIÓN DESTINO”
      - En lugar de validar Dirección y Subdirección por separado, se valida TODO de un jalón.

   C) “SIN CAMBIOS”
      - Si Clave, Nombre y Subdirección destino son iguales al actual:
        - COMMIT inmediato (para liberar locks)
        - Accion = 'SIN_CAMBIOS'

   RESULTADO
   ---------
   ÉXITO:
     - Mensaje, Accion='ACTUALIZADA', Id_CatGeren, Id_Subdireccion_Anterior, Id_Subdireccion_Nueva...

   SIN CAMBIOS:
     - Mensaje, Accion='SIN_CAMBIOS', Id_CatGeren...

   CONFLICTO (1062):
     - Mensaje, Accion='CONFLICTO', Campo, Id_Conflicto...
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS SP_EditarGerencia$$
CREATE PROCEDURE SP_EditarGerencia(
    IN _Id_CatGeren INT,
    IN _Nuevo_Clave VARCHAR(50),
    IN _Nuevo_Nombre VARCHAR(255),
    IN _Id_Direccion_Seleccionada INT,
    IN _Id_Subdireccion_Destino INT
)
SP: BEGIN
    /* ========================================================================================
       PARTE 0) VARIABLES
       ======================================================================================== */

    /* Datos actuales de la gerencia (para "SIN CAMBIOS") */
    DECLARE v_Clave_Actual  VARCHAR(50)  DEFAULT NULL;
    DECLARE v_Nombre_Actual VARCHAR(255) DEFAULT NULL;

    /* “Subdirección anterior” (para respuesta y para saber si se movió o no) */
    DECLARE v_Subdireccion_Anterior INT DEFAULT NULL;

    /* Dirección actual de la gerencia (derivada de la Subdirección anterior) */
    DECLARE v_Id_Direccion_Actual INT DEFAULT NULL;

    /* Variable auxiliar genérica para existencia / validaciones */
    DECLARE v_Existe INT DEFAULT NULL;

    /* Para pre-checks de duplicados */
    DECLARE v_DupId INT DEFAULT NULL;

    /* Bandera para detectar choque 1062 en UPDATE */
    DECLARE v_Dup TINYINT(1) DEFAULT 0;

    /* Datos para respuesta de conflicto controlado */
    DECLARE v_Id_Conflicto INT DEFAULT NULL;
    DECLARE v_Campo_Conflicto VARCHAR(20) DEFAULT NULL;

    /* Para lock determinístico de direcciones */
    DECLARE v_Dir_Low INT DEFAULT NULL;
    DECLARE v_Dir_High INT DEFAULT NULL;

    /* ========================================================================================
       PARTE 1) HANDLERS (CONCURRENCIA Y ERRORES)
       ======================================================================================== */

    /* 1062 (Duplicate entry):
       - No abortamos inmediatamente, marcamos v_Dup=1 para responder “CONFLICTO” controlado.
    */
    DECLARE CONTINUE HANDLER FOR 1062
    BEGIN
        SET v_Dup = 1;
    END;

    /* Cualquier otro error SQL:
       - rollback y re-lanzar el error para que el backend lo vea tal cual.
    */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    /* ========================================================================================
       PARTE 2) NORMALIZACIÓN DE INPUTS (defensivo)
       ======================================================================================== */
    SET _Nuevo_Clave  = NULLIF(TRIM(_Nuevo_Clave), '');
    SET _Nuevo_Nombre = NULLIF(TRIM(_Nuevo_Nombre), '');

    /* ========================================================================================
       PARTE 3) VALIDACIONES BÁSICAS (antes de abrir TX)
       ======================================================================================== */
    IF _Id_CatGeren IS NULL OR _Id_CatGeren <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Id_CatGeren inválido.';
    END IF;

    IF _Nuevo_Clave IS NULL OR _Nuevo_Nombre IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Clave y Nombre de la Gerencia son obligatorios.';
    END IF;

    IF _Id_Direccion_Seleccionada IS NULL OR _Id_Direccion_Seleccionada <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Dirección seleccionada inválida.';
    END IF;

    IF _Id_Subdireccion_Destino IS NULL OR _Id_Subdireccion_Destino <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Subdirección destino inválida.';
    END IF;

    /* ========================================================================================
       PARTE 4) TRANSACCIÓN PRINCIPAL
       ======================================================================================== */
    START TRANSACTION;

    /* ----------------------------------------------------------------------------------------
       PASO 1) Bloquear la Gerencia a editar y leer su estado anterior + datos actuales
       ----------------------------------------------------------------------------------------
       - Aquí bloqueamos SOLO la fila de la Gerencia (FOR UPDATE).
       - ¿Por qué?
         * Evita que otro usuario cambie esta misma Gerencia mientras tú la editas.
         * Nos permite obtener:
             - v_Subdireccion_Anterior (para respuesta)
             - v_Clave_Actual y v_Nombre_Actual (para detectar “SIN CAMBIOS”)
       - NOTA: NO bloqueamos Subdirección/Dirección aquí para minimizar riesgo de deadlocks.
       ---------------------------------------------------------------------------------------- */
    SET v_Subdireccion_Anterior = NULL;
    SET v_Clave_Actual = NULL;
    SET v_Nombre_Actual = NULL;

    SELECT
        G.Fk_Id_CatSubDirec,
        G.Clave,
        G.Nombre
    INTO
        v_Subdireccion_Anterior,
        v_Clave_Actual,
        v_Nombre_Actual
    FROM Cat_Gerencias_Activos G
    WHERE G.Id_CatGeren = _Id_CatGeren
    LIMIT 1
    FOR UPDATE;

    IF v_Subdireccion_Anterior IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: La Gerencia no existe.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 1.1) Obtener Dirección ACTUAL de la gerencia (derivado de la Subdirección anterior)
       ----------------------------------------------------------------------------------------
       - Solo necesitamos el Id de la dirección actual para hacer lock determinístico.
       - Si la Subdirección anterior no existe por alguna inconsistencia, abortamos.
       ---------------------------------------------------------------------------------------- */
    SET v_Id_Direccion_Actual = NULL;

    SELECT S.Fk_Id_CatDirecc
      INTO v_Id_Direccion_Actual
    FROM Cat_Subdirecciones S
    WHERE S.Id_CatSubDirec = v_Subdireccion_Anterior
    LIMIT 1;

    IF v_Id_Direccion_Actual IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Inconsistencia: la Subdirección actual de la Gerencia no existe.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 2) LOCK DETERMINÍSTICO DE DIRECCIONES (anti-deadlocks)
       ----------------------------------------------------------------------------------------
       PROBLEMA QUE RESUELVE:
       - Si dos transacciones intentan mover gerencias entre Dirección A y Dirección B cruzadas,
         se puede generar DEADLOCK.
       SOLUCIÓN:
       - Bloqueamos SIEMPRE en el mismo orden:
         1) v_Dir_Low  = min(DirActual, DirSeleccionada)
         2) v_Dir_High = max(DirActual, DirSeleccionada)
       ---------------------------------------------------------------------------------------- */
    IF v_Id_Direccion_Actual = _Id_Direccion_Seleccionada THEN
        SET v_Dir_Low  = v_Id_Direccion_Actual;
        SET v_Dir_High = v_Id_Direccion_Actual;
    ELSE
        SET v_Dir_Low  = LEAST(v_Id_Direccion_Actual, _Id_Direccion_Seleccionada);
        SET v_Dir_High = GREATEST(v_Id_Direccion_Actual, _Id_Direccion_Seleccionada);
    END IF;

    /* 2.1) Bloquear Dirección LOW (debe existir) */
    SET v_Existe = NULL;

    SELECT 1 INTO v_Existe
    FROM Cat_Direcciones
    WHERE Id_CatDirecc = v_Dir_Low
    LIMIT 1
    FOR UPDATE;

    IF v_Existe IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Inconsistencia: Dirección (low) no existe.';
    END IF;

    /* 2.2) Bloquear Dirección HIGH (si es distinta) */
    IF v_Dir_High <> v_Dir_Low THEN
        SET v_Existe = NULL;

        SELECT 1 INTO v_Existe
        FROM Cat_Direcciones
        WHERE Id_CatDirecc = v_Dir_High
        LIMIT 1
        FOR UPDATE;

        IF v_Existe IS NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Inconsistencia: Dirección (high) no existe.';
        END IF;
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 3) Validación ATÓMICA (JOIN único): Dirección seleccionada + Subdirección destino
       ----------------------------------------------------------------------------------------
       Validamos TODO en un solo SELECT:
       - Dirección existe y Activo=1
       - Subdirección existe y Activo=1
       - Subdirección pertenece a la Dirección seleccionada
       Además:
       - FOR UPDATE aquí bloquea la fila de la Subdirección destino.
       ---------------------------------------------------------------------------------------- */
    SET v_Existe = NULL;

    SELECT 1 INTO v_Existe
    FROM Cat_Direcciones D
    STRAIGHT_JOIN Cat_Subdirecciones S ON S.Fk_Id_CatDirecc = D.Id_CatDirecc
    WHERE D.Id_CatDirecc = _Id_Direccion_Seleccionada
      AND D.Activo = 1
      AND S.Id_CatSubDirec = _Id_Subdireccion_Destino
      AND S.Activo = 1
    LIMIT 1
    FOR UPDATE;

    IF v_Existe IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: La Subdirección destino no pertenece a la Dirección seleccionada o alguna está inactiva.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 4) SIN CAMBIOS (salida temprana)
       ----------------------------------------------------------------------------------------
       - Si Clave, Nombre y Subdirección destino son iguales al actual:
         COMMIT inmediato para liberar locks.
       ---------------------------------------------------------------------------------------- */
    IF v_Clave_Actual = _Nuevo_Clave
       AND v_Nombre_Actual = _Nuevo_Nombre
       AND v_Subdireccion_Anterior = _Id_Subdireccion_Destino THEN

        COMMIT;

        SELECT 'Sin cambios: La Gerencia ya tiene esos datos y ya está en esa Subdirección.' AS Mensaje,
               'SIN_CAMBIOS' AS Accion,
               _Id_CatGeren AS Id_CatGeren,
               v_Subdireccion_Anterior AS Id_Subdireccion_Anterior,
               _Id_Subdireccion_Destino AS Id_Subdireccion_Nueva,
               _Id_Direccion_Seleccionada AS Id_Direccion_Seleccionada;
        LEAVE SP;
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 5) Pre-check duplicidad por CLAVE en la Subdirección destino (excluyendo el mismo Id)
       ----------------------------------------------------------------------------------------
       - FOR UPDATE: si encuentra la fila duplicada, la bloquea.
       - ORDER BY Id: lock determinístico.
       ---------------------------------------------------------------------------------------- */
    SET v_DupId = NULL;

    SELECT Id_CatGeren
      INTO v_DupId
    FROM Cat_Gerencias_Activos
    WHERE Fk_Id_CatSubDirec = _Id_Subdireccion_Destino
      AND Clave = _Nuevo_Clave
      AND Id_CatGeren <> _Id_CatGeren
    ORDER BY Id_CatGeren
    LIMIT 1
    FOR UPDATE;

    IF v_DupId IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Ya existe OTRA Gerencia con esa CLAVE en la Subdirección destino.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 6) Pre-check duplicidad por NOMBRE en la Subdirección destino
       ---------------------------------------------------------------------------------------- */
    SET v_DupId = NULL;

    SELECT Id_CatGeren
      INTO v_DupId
    FROM Cat_Gerencias_Activos
    WHERE Fk_Id_CatSubDirec = _Id_Subdireccion_Destino
      AND Nombre = _Nuevo_Nombre
      AND Id_CatGeren <> _Id_CatGeren
    ORDER BY Id_CatGeren
    LIMIT 1
    FOR UPDATE;

    IF v_DupId IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Ya existe OTRA Gerencia con ese NOMBRE en la Subdirección destino.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 7) UPDATE (aquí puede ocurrir 1062 por carrera)
       ----------------------------------------------------------------------------------------
       - Reseteamos v_Dup = 0 antes del UPDATE.
       ---------------------------------------------------------------------------------------- */
    SET v_Dup = 0;

    UPDATE Cat_Gerencias_Activos
    SET Clave = _Nuevo_Clave,
        Nombre = _Nuevo_Nombre,
        Fk_Id_CatSubDirec = _Id_Subdireccion_Destino,
        updated_at = NOW()
    WHERE Id_CatGeren = _Id_CatGeren;

    /* ----------------------------------------------------------------------------------------
       PASO 8) Si hubo 1062 => CONFLICTO CONTROLADO
       ----------------------------------------------------------------------------------------
       - Hacemos ROLLBACK.
       - Determinamos si el conflicto fue por CLAVE o NOMBRE.
       ---------------------------------------------------------------------------------------- */
    IF v_Dup = 1 THEN
        ROLLBACK;

        SET v_Id_Conflicto = NULL;
        SET v_Campo_Conflicto = NULL;

        /* 8.1) Intentar detectar conflicto por CLAVE */
        SELECT Id_CatGeren
          INTO v_Id_Conflicto
        FROM Cat_Gerencias_Activos
        WHERE Fk_Id_CatSubDirec = _Id_Subdireccion_Destino
          AND Clave = _Nuevo_Clave
          AND Id_CatGeren <> _Id_CatGeren
        ORDER BY Id_CatGeren
        LIMIT 1;

        IF v_Id_Conflicto IS NOT NULL THEN
            SET v_Campo_Conflicto = 'CLAVE';
        ELSE
            /* 8.2) Si no fue CLAVE, intentar conflicto por NOMBRE */
            SELECT Id_CatGeren
              INTO v_Id_Conflicto
            FROM Cat_Gerencias_Activos
            WHERE Fk_Id_CatSubDirec = _Id_Subdireccion_Destino
              AND Nombre = _Nuevo_Nombre
              AND Id_CatGeren <> _Id_CatGeren
            ORDER BY Id_CatGeren
            LIMIT 1;

            IF v_Id_Conflicto IS NOT NULL THEN
                SET v_Campo_Conflicto = 'NOMBRE';
            END IF;
        END IF;

        SELECT 'No se guardó: otro usuario se adelantó. Refresca y vuelve a intentar.' AS Mensaje,
               'CONFLICTO' AS Accion,
               v_Campo_Conflicto AS Campo,
               v_Id_Conflicto AS Id_Conflicto,
               _Id_CatGeren AS Id_Gerencia_Que_Intentabas_Editar,
               v_Subdireccion_Anterior AS Id_Subdireccion_Anterior,
               _Id_Subdireccion_Destino AS Id_Subdireccion_Nueva,
               _Id_Direccion_Seleccionada AS Id_Direccion_Seleccionada;
        LEAVE SP;
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 9) ÉXITO
       ---------------------------------------------------------------------------------------- */
    COMMIT;

    SELECT 'Gerencia actualizada correctamente' AS Mensaje,
           'ACTUALIZADA' AS Accion,
           _Id_CatGeren AS Id_CatGeren,
           v_Subdireccion_Anterior AS Id_Subdireccion_Anterior,
           _Id_Subdireccion_Destino AS Id_Subdireccion_Nueva,
           _Id_Direccion_Seleccionada AS Id_Direccion_Seleccionada;

END$$

DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_CambiarEstatusGerencia
   ============================================================================================
   OBJETIVO
   --------
   Activar/Desactivar (borrado lógico) una Gerencia:
      Cat_Gerencias_Activos.Activo (1 = activo, 0 = inactivo)

   REGLAS CRÍTICAS (INTEGRIDAD DE NEGOCIO)
   ---------------------------------------
   A) Al DESACTIVAR una Gerencia (Activo=0):
      - NO se permite si tiene EMPLEADOS ACTIVOS (Info_Personal).
      - NO se permite si tiene CAPACITACIONES ACTIVAS (Capacitaciones).
      Esto evita inconsistencias como "Empleado activo en una Gerencia fantasma".

   B) Al ACTIVAR una Gerencia (Activo=1)  <<<<<<<<<<<< CANDADO JERÁRQUICO (C)
      - NO se permite si su SUBDIRECCIÓN (Padre) está INACTIVA.
      - NO se permite si su DIRECCIÓN (Abuelo) está INACTIVA.
      
      Evita la inconsistencia visual y lógica:
         Dirección=0 -> Subdirección=0 -> Gerencia=1 (Rama rota).

   CONCURRENCIA / BLOQUEOS
   -----------------------
   - Bloqueamos en orden jerárquico estricto: 
        1. DIRECCIÓN (Abuelo)
        2. SUBDIRECCIÓN (Padre)
        3. GERENCIA (Hijo)
   
   - Usamos STRAIGHT_JOIN + FOR UPDATE para:
        * Asegurar que el motor de BD bloquee en ese orden exacto (evitar Deadlocks).
        * Evitar "carreras": que alguien desactive la Dirección justo en el milisegundo
          antes de que tú actives la Gerencia.
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS SP_CambiarEstatusGerencia$$
CREATE PROCEDURE SP_CambiarEstatusGerencia(
    IN _Id_CatGeren INT,
    IN _Nuevo_Estatus TINYINT /* 1 = Activo, 0 = Inactivo */
)
BEGIN
    /* ----------------------------------------------------------------------------------------
       VARIABLES
       ---------------------------------------------------------------------------------------- */
    DECLARE v_Existe INT DEFAULT NULL;

    /* Estatus actual de la Gerencia */
    DECLARE v_Activo_Actual TINYINT(1) DEFAULT NULL;

    /* Datos jerárquicos para candado al ACTIVAR */
    DECLARE v_Id_Subdireccion INT DEFAULT NULL;
    DECLARE v_Subdireccion_Activo TINYINT(1) DEFAULT NULL;

    DECLARE v_Id_Direccion INT DEFAULT NULL;
    DECLARE v_Direccion_Activo TINYINT(1) DEFAULT NULL;

    /* Auxiliar para búsqueda de dependencias */
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
    IF _Id_CatGeren IS NULL OR _Id_CatGeren <= 0 THEN
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'ERROR: Id_CatGeren inválido.';
    END IF;

    IF _Nuevo_Estatus NOT IN (0,1) THEN
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'ERROR: Estatus inválido (solo 0 o 1).';
    END IF;

    START TRANSACTION;

    /* ----------------------------------------------------------------------------------------
       1) VALIDAR EXISTENCIA Y BLOQUEAR FILAS EN ORDEN JERÁRQUICO 
          (DIRECCIÓN -> SUBDIRECCIÓN -> GERENCIA)
       ----------------------------------------------------------------------------------------
       ¿POR QUÉ ASÍ?
       - Para el candado (C) necesitamos leer el estatus del Padre y del Abuelo.
       - Si no bloqueamos toda la cadena, la integridad no está garantizada en sistemas
         de alta concurrencia.
       - FOR UPDATE congela las 3 filas involucradas en esta transacción.
       ---------------------------------------------------------------------------------------- */
    SELECT
        1 AS Existe,
        G.Activo AS Activo_Gerencia,

        G.Fk_Id_CatSubDirec AS Id_Subdireccion,
        S.Activo AS Activo_Subdireccion,

        S.Fk_Id_CatDirecc AS Id_Direccion,
        D.Activo AS Activo_Direccion
    INTO
        v_Existe,
        v_Activo_Actual,
        v_Id_Subdireccion,
        v_Subdireccion_Activo,
        v_Id_Direccion,
        v_Direccion_Activo
    FROM Cat_Direcciones D
    STRAIGHT_JOIN Cat_Subdirecciones S ON S.Fk_Id_CatDirecc = D.Id_CatDirecc
    STRAIGHT_JOIN Cat_Gerencias_Activos G ON G.Fk_Id_CatSubDirec = S.Id_CatSubDirec
    WHERE G.Id_CatGeren = _Id_CatGeren
    LIMIT 1
    FOR UPDATE;

    IF v_Existe IS NULL THEN
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'ERROR: La Gerencia no existe.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       2) "SIN CAMBIOS" (IDEMPOTENCIA)
       - Si ya está en el estatus solicitado, no tocamos la BD y retornamos rápido.
       ---------------------------------------------------------------------------------------- */
    IF v_Activo_Actual = _Nuevo_Estatus THEN
        COMMIT;
        SELECT CASE
            WHEN _Nuevo_Estatus = 1 THEN 'Sin cambios: La Gerencia ya estaba Activa.'
            ELSE 'Sin cambios: La Gerencia ya estaba Inactiva.'
        END AS Mensaje,
        v_Activo_Actual AS Activo_Anterior,
        _Nuevo_Estatus AS Activo_Nuevo;
    ELSE

        /* ------------------------------------------------------------------------------------
           3) CANDADO JERÁRQUICO AL ACTIVAR (C)
           ------------------------------------------------------------------------------------
           REGLA:
           - Si quieres ACTIVAR Gerencia (Nuevo=1), toda su línea de mando debe estar viva.
           - Si Dirección o Subdirección están muertas (0), bloqueamos.
           ------------------------------------------------------------------------------------ */
        IF _Nuevo_Estatus = 1 THEN
            
            /* Chequeo de Abuelo (Dirección) */
            IF v_Direccion_Activo = 0 THEN
                SIGNAL SQLSTATE '45000'
                    SET MESSAGE_TEXT = 'BLOQUEADO: No se puede ACTIVAR la Gerencia porque su DIRECCIÓN (Abuelo) está INACTIVA. Active primero la Dirección.';
            END IF;

            /* Chequeo de Padre (Subdirección) */
            IF v_Subdireccion_Activo = 0 THEN
                SIGNAL SQLSTATE '45000'
                    SET MESSAGE_TEXT = 'BLOQUEADO: No se puede ACTIVAR la Gerencia porque su SUBDIRECCIÓN (Padre) está INACTIVA. Active primero la Subdirección.';
            END IF;

        END IF;

        /* ------------------------------------------------------------------------------------
           4) SI INTENTA DESACTIVAR: BLOQUEAR SI HAY REFERENCIAS EN USO (HIJOS)
           - Revisamos las tablas hijas definidas en el esquema (Info_Personal, Capacitaciones).
           - Solo bloqueamos si el hijo está ACTIVO (Activo=1).
           ------------------------------------------------------------------------------------ */
        IF _Nuevo_Estatus = 0 THEN

            /* 4A) Info_Personal (Empleados activos) */
            IF EXISTS (
                SELECT 1 
                FROM Info_Personal 
                WHERE Fk_Id_CatGeren = _Id_CatGeren 
                  AND Activo = 1
                LIMIT 1
            ) THEN
                SIGNAL SQLSTATE '45000' 
                    SET MESSAGE_TEXT = 'BLOQUEADO: No se puede desactivar la Gerencia porque tiene PERSONAL ACTIVO asignado. Reasigne o desactive al personal primero.';
            END IF;

            /* 4B) Capacitaciones (Cursos programados activos) */
            IF EXISTS (
                SELECT 1 
                FROM Capacitaciones 
                WHERE Fk_Id_CatGeren = _Id_CatGeren 
                  AND Activo = 1
                LIMIT 1
            ) THEN
                SIGNAL SQLSTATE '45000' 
                    SET MESSAGE_TEXT = 'BLOQUEADO: No se puede desactivar la Gerencia porque tiene CAPACITACIONES ACTIVAS programadas. Cancele o reasigne las capacitaciones.';
            END IF;

        END IF;

        /* ------------------------------------------------------------------------------------
           5) APLICAR CAMBIO DE ESTATUS
           ------------------------------------------------------------------------------------ */
        UPDATE Cat_Gerencias_Activos
        SET Activo = _Nuevo_Estatus,
            updated_at = NOW()
        WHERE Id_CatGeren = _Id_CatGeren;

        COMMIT;

        /* ------------------------------------------------------------------------------------
           6) RESPUESTA PARA FRONTEND
           ------------------------------------------------------------------------------------ */
        SELECT CASE
            WHEN _Nuevo_Estatus = 1 THEN 'Gerencia Reactivada Exitosamente'
            ELSE 'Gerencia Desactivada (Eliminado Lógico)'
        END AS Mensaje,
        v_Activo_Actual AS Activo_Anterior,
        _Nuevo_Estatus AS Activo_Nuevo;

    END IF;

END$$

DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_EliminarGerenciaFisica
   ============================================================================================
   OBJETIVO
   --------
   Eliminar físicamente (DELETE) una Gerencia de la base de datos.

   ¿CUÁNDO SE USA?
   --------------
   - Solo en administración avanzada, limpieza de datos o corrección controlada.
   - Normalmente NO se usa en operación diaria (para eso es el borrado lógico / Estatus).

   RIESGOS / CANDADOS DE INTEGRIDAD
   -------------------------------
   - La tabla `Cat_Gerencias_Activos` es referenciada por tablas críticas como:
       * Info_Personal (Empleados)
       * Capacitaciones (Historial de cursos)
   
   - Si existe cualquier registro en esas tablas que apunte a esta Gerencia,
     el DELETE fallará (protegido por Foreign Keys).

   - Este SP incluye una "Pre-Validación" manual para avisar al usuario
     EXACTAMENTE qué dependencia está bloqueando el borrado (Personal o Capacitación),
     en lugar de solo arrojar un error SQL genérico.

   VALIDACIONES
   ------------
   - Verificar que el Id sea válido y exista.
   - Verificar que NO tenga Personal asignado.
   - Verificar que NO tenga Capacitaciones ligadas.
   - Manejo de excepciones con HANDLER para seguridad final.

   RESPUESTA
   ---------
   - Devuelve un mensaje de confirmación si se eliminó.
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS SP_EliminarGerenciaFisica$$
CREATE PROCEDURE SP_EliminarGerenciaFisica(
    IN _Id_CatGeren INT
)
BEGIN
    /* ----------------------------------------------------------------------------------------
       HANDLERS DE SEGURIDAD
       ---------------------------------------------------------------------------------------- */
    
    /* HANDLER 1451: Atrapa el error de restricción de llave foránea (FK)
       Es la "última línea de defensa" si se nos pasó alguna tabla hija en los IFs manuales. */
    DECLARE EXIT HANDLER FOR 1451
    BEGIN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'ERROR: No se puede eliminar la Gerencia porque está referenciada por otros registros (FK) en el sistema.';
    END;

    /* HANDLER General: Para cualquier otro error SQL imprevisto */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    /* ----------------------------------------------------------------------------------------
       VALIDACIONES BÁSICAS
       ---------------------------------------------------------------------------------------- */
    IF _Id_CatGeren IS NULL OR _Id_CatGeren <= 0 THEN
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'ERROR: Id_CatGeren inválido.';
    END IF;

    /* Validar existencia antes de intentar nada */
    IF NOT EXISTS(SELECT 1 FROM Cat_Gerencias_Activos WHERE Id_CatGeren = _Id_CatGeren) THEN
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'ERROR: La Gerencia no existe.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       CANDADOS DE NEGOCIO (PRE-VALIDACIÓN DE DEPENDENCIAS)
       - Buscamos dependencias específicas para dar mensajes de error útiles.
       ---------------------------------------------------------------------------------------- */

    /* 1. Verificar si hay Personal (Info_Personal) asignado a esta Gerencia */
    IF EXISTS(SELECT 1 FROM Info_Personal WHERE Fk_Id_CatGeren = _Id_CatGeren LIMIT 1) THEN
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'ERROR CRÍTICO: No se puede eliminar la Gerencia porque tiene PERSONAL (Empleados) asignados. Elimine o reasigne al personal primero.';
    END IF;

    /* 2. Verificar si hay Capacitaciones ligadas a esta Gerencia */
    IF EXISTS(SELECT 1 FROM Capacitaciones WHERE Fk_Id_CatGeren = _Id_CatGeren LIMIT 1) THEN
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'ERROR CRÍTICO: No se puede eliminar la Gerencia porque tiene CAPACITACIONES registradas en el historial.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       TRANSACCIÓN DE BORRADO
       ---------------------------------------------------------------------------------------- */
    START TRANSACTION;

    DELETE FROM Cat_Gerencias_Activos
    WHERE Id_CatGeren = _Id_CatGeren;

    COMMIT;

    /* ----------------------------------------------------------------------------------------
       RESPUESTA
       ---------------------------------------------------------------------------------------- */
    SELECT 'Gerencia Eliminada Permanentemente' AS Mensaje;

END$$

DELIMITER ;