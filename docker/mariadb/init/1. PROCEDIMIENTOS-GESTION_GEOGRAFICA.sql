USE `PICADE`;

/* ------------------------------------------------------------------------------------------------------ */
/* CREACION DE VISTAS Y PROCEDIMIENTOS DE ALMACENADO PARA LA BASE DE DATOS*/
/* ------------------------------------------------------------------------------------------------------ */

/* ======================================================================================================
   1. VIEW: Vista_Direcciones
   ======================================================================================================
   OBJETIVO GENERAL
   ----------------
   Proporcionar una representación "aplanada" y desnormalizada de la jerarquía geográfica completa:
       Municipio (Hijo) -> Estado (Padre) -> País (Abuelo)
   
   Esta vista actúa como la fuente de verdad única para cualquier consulta que requiera mostrar
   la ubicación de una entidad en el sistema.

   CASOS DE USO (¿DÓNDE SE CONSUME?)
   ---------------------------------
   1. Buscadores Globales: Permite buscar "Tabasco" y encontrar todos los municipios relacionados sin hacer JOINs manuales.
   2. Reportes: Para encabezados de reportes oficiales de PEMEX que exigen "Lugar: Municipio, Estado, País".
   3. Dropdowns en Cascada: Facilita la precarga de datos en formularios de edición (aunque los SPs específicos son preferibles para rendimiento crítico).
   4. Tablas de Administración (CRUDs): Muestra la ubicación legible en lugar de IDs numéricos.

   DECISIONES DE DISEÑO Y ARQUITECTURA
   -----------------------------------
   A) INNER JOIN vs LEFT JOIN:
      - Se utilizan INNER JOINS estrictos.
      - Razón: Por regla de negocio e integridad referencial, NO puede existir un Municipio sin Estado,
        ni un Estado sin País. Si un dato rompe esta regla, se considera corrupto y no debe aparecer
        en esta vista estándar.

   B) FILTRADO DE ESTATUS (ACTIVO/INACTIVO):
      - La vista NO filtra por `Activo = 1`. Devuelve TODO el historial.
      - Razón: Los paneles de administración necesitan ver registros inactivos para poder reactivarlos.
      - El filtrado de "Solo Activos" se delega a la cláusula WHERE de quien consuma la vista.

   C) ESTATUS EXPUESTO:
      - El campo `Estatus` corresponde al nivel más bajo (Municipio), ya que es la unidad atómica
        de ubicación.

   DICCIONARIO DE DATOS (CAMPOS DEVUELTOS)
   ---------------------------------------
   [Nivel Municipio]
   - Id_Municipio:      Llave primaria del municipio.
   - Codigo_Municipio:  Clave oficial (ej: '004').
   - Nombre_Municipio:  Nombre descriptivo (ej: 'CENTRO').
   
   [Nivel Estado]
   - Codigo_Estado:     Clave oficial (ej: 'TAB').
   - Nombre_Estado:     Nombre descriptivo (ej: 'TABASCO').
   
   [Nivel País]
   - Codigo_Pais:       Clave oficial (ej: 'MEX').
   - Nombre_Pais:       Nombre descriptivo (ej: 'MÉXICO').
   
   [Metadatos]
   - Estatus:           1 = Visible/Activo, 0 = Borrado Lógico (del Municipio).
   ====================================================================================================== */

-- DROP VIEW IF EXISTS `PICADE`.`Vista_Direcciones`;

CREATE OR REPLACE
    ALGORITHM = UNDEFINED 
    SQL SECURITY DEFINER
VIEW `PICADE`.`Vista_Direcciones` AS
    SELECT 
        `Mun`.`Id_Municipio` AS `Id_Municipio`,
        `Mun`.`Codigo` AS `Codigo_Municipio`,
        `Mun`.`Nombre` AS `Nombre_Municipio`,
        `Est`.`Codigo` AS `Codigo_Estado`,
        `Est`.`Nombre` AS `Nombre_Estado`,
        `Pais`.`Codigo` AS `Codigo_Pais`,
        `Pais`.`Nombre` AS `Nombre_Pais`,
        `Mun`.`Activo` AS `Estatus`
    FROM
        ((`PICADE`.`Municipio` `Mun`
        JOIN `PICADE`.`Estado` `Est` ON (`Mun`.`Fk_Id_Estado` = `Est`.`Id_Estado`))
        JOIN `PICADE`.`Pais` `Pais` ON (`Est`.`Fk_Id_Pais` = `Pais`.`Id_Pais`));

/* ============================================================================================
   PROCEDIMIENTO: SP_RegistrarUbicaciones
   ============================================================================================
   OBJETIVO
   --------
   Resolver o registrar una jerarquía completa de ubicaciones:
      País -> Estado -> Municipio
   en una sola operación, pensada para FORMULARIO donde TODO es obligatorio
   (Código y Nombre en los 3 niveles).

   QUÉ HACE (CONTRATO DE NEGOCIO)
   ------------------------------
   Para cada nivel (País, Estado, Municipio) este SP aplica la MISMA regla:

   1) Busca primero por CÓDIGO (regla principal) dentro de su “padre” cuando aplica.
      - Si existe: valida que el NOMBRE coincida.
      - Si no coincide: ERROR controlado (conflicto Código <-> Nombre).

   2) Si no existe por CÓDIGO, busca por NOMBRE dentro de su “padre” cuando aplica.
      - Si existe: valida que el CÓDIGO coincida.
      - Si no coincide: ERROR controlado (conflicto Nombre <-> Código).

   3) Si NO existe por CÓDIGO ni por NOMBRE:
      - Crea el registro (INSERT).

   4) Si existe y está Activo = 0:
      - Reactiva (UPDATE Activo=1).

   ACCIONES DEVUELTAS
   ------------------
   El SP devuelve una acción por nivel:
      Accion_Pais      = 'CREADA' | 'REUSADA' | 'REACTIVADA'
      Accion_Estado    = 'CREADA' | 'REUSADA' | 'REACTIVADA'
      Accion_Municipio = 'CREADA' | 'REUSADA' | 'REACTIVADA'

   - 'CREADA'      => se insertó un nuevo registro.
   - 'REUSADA'     => ya existía activa y se reutilizó (no se insertó).
   - 'REACTIVADA'  => ya existía pero estaba inactiva, se reactivó y se reutilizó.

   SEGURIDAD / INTEGRIDAD
   ----------------------
   - Usa TRANSACTION: si algo falla, ROLLBACK y RESIGNAL (no quedan datos a medias).
   - Resolución determinística (nada de "OR ... LIMIT 1").
   - Blindaje ante concurrencia/doble-submit:
       * Los SELECT de búsqueda usan FOR UPDATE para serializar la lectura cuando hay fila.
       * Las constraints UNIQUE (Código+FK, Nombre+FK) son el candado final contra duplicados.

   RESULTADO
   ---------
   Retorna:
   - Id_Pais, Id_Estado, Id_Municipio
   - Accion_* por cada nivel
   - Id_Nuevo_Pais       SOLO si Accion_Pais='CREADA', si no NULL
   - Id_Nuevo_Estado     SOLO si Accion_Estado='CREADA', si no NULL
   - Id_Nuevo_Municipio  SOLO si Accion_Municipio='CREADA', si no NULL
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS SP_RegistrarUbicaciones$$

CREATE PROCEDURE SP_RegistrarUbicaciones(
    IN _Codigo_Municipio VARCHAR(50),   /* Código del Municipio (OBLIGATORIO en formulario) */
    IN _Nombre_Municipio VARCHAR(255),  /* Nombre del Municipio (OBLIGATORIO) */
    IN _Codigo_Estado    VARCHAR(50),   /* Código del Estado (OBLIGATORIO) */
    IN _Nombre_Estado    VARCHAR(255),  /* Nombre del Estado (OBLIGATORIO) */
    IN _Codigo_Pais      VARCHAR(50),   /* Código del País (OBLIGATORIO) */
    IN _Nombre_Pais      VARCHAR(255)   /* Nombre del País (OBLIGATORIO) */
)
BEGIN
    /* ----------------------------------------------------------------------------------------
       VARIABLES INTERNAS
       ---------------------------------------------------------------------------------------- */
    DECLARE v_Id_Pais      INT DEFAULT NULL;
    DECLARE v_Id_Estado    INT DEFAULT NULL;
    DECLARE v_Id_Municipio INT DEFAULT NULL;

    /* Buffers para validación cruzada cuando el registro ya existe */
    DECLARE v_Codigo VARCHAR(50);
    DECLARE v_Nombre VARCHAR(255);
    DECLARE v_Activo TINYINT(1);

    /* Acciones por nivel */
    DECLARE v_Accion_Pais      VARCHAR(20) DEFAULT NULL;
    DECLARE v_Accion_Estado    VARCHAR(20) DEFAULT NULL;
    DECLARE v_Accion_Municipio VARCHAR(20) DEFAULT NULL;

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
    SET _Codigo_Pais      = NULLIF(TRIM(_Codigo_Pais), '');
    SET _Nombre_Pais      = NULLIF(TRIM(_Nombre_Pais), '');
    SET _Codigo_Estado    = NULLIF(TRIM(_Codigo_Estado), '');
    SET _Nombre_Estado    = NULLIF(TRIM(_Nombre_Estado), '');
    SET _Codigo_Municipio = NULLIF(TRIM(_Codigo_Municipio), '');
    SET _Nombre_Municipio = NULLIF(TRIM(_Nombre_Municipio), '');

    /* ----------------------------------------------------------------------------------------
       VALIDACIONES DE NEGOCIO (FORMULARIO: TODO OBLIGATORIO)
    ---------------------------------------------------------------------------------------- */
    IF _Codigo_Pais IS NULL OR _Nombre_Pais IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: País incompleto (Código y Nombre obligatorios).';
    END IF;

    IF _Codigo_Estado IS NULL OR _Nombre_Estado IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Estado incompleto (Código y Nombre obligatorios).';
    END IF;

    IF _Codigo_Municipio IS NULL OR _Nombre_Municipio IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Municipio incompleto (Código y Nombre obligatorios).';
    END IF;

    /* ----------------------------------------------------------------------------------------
       INICIO TRANSACCIÓN
    ---------------------------------------------------------------------------------------- */
    START TRANSACTION;

    /* ========================================================================================
       1) RESOLVER / CREAR PAÍS
       ======================================================================================== */

    /* 1A) Buscar por CÓDIGO */
    SET v_Id_Pais = NULL;
    SELECT Id_Pais, Codigo, Nombre, Activo
      INTO v_Id_Pais, v_Codigo, v_Nombre, v_Activo
    FROM Pais
    WHERE Codigo = _Codigo_Pais
    LIMIT 1
    FOR UPDATE;

    IF v_Id_Pais IS NOT NULL THEN
        IF v_Nombre <> _Nombre_Pais THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'ERROR: Conflicto País. El Código existe pero el Nombre no coincide.';
        END IF;

        IF v_Activo = 0 THEN
            UPDATE Pais
            SET Activo = 1, updated_at = NOW()
            WHERE Id_Pais = v_Id_Pais;
            SET v_Accion_Pais = 'REACTIVADA';
        ELSE
            SET v_Accion_Pais = 'REUSADA';
        END IF;

    ELSE
        /* 1B) Buscar por NOMBRE */
        SELECT Id_Pais, Codigo, Nombre, Activo
          INTO v_Id_Pais, v_Codigo, v_Nombre, v_Activo
        FROM Pais
        WHERE Nombre = _Nombre_Pais
        LIMIT 1
        FOR UPDATE;

        IF v_Id_Pais IS NOT NULL THEN
            IF v_Codigo <> _Codigo_Pais THEN
                SIGNAL SQLSTATE '45000'
                    SET MESSAGE_TEXT = 'ERROR: Conflicto País. El Nombre existe pero el Código no coincide.';
            END IF;

            IF v_Activo = 0 THEN
                UPDATE Pais
                SET Activo = 1, updated_at = NOW()
                WHERE Id_Pais = v_Id_Pais;
                SET v_Accion_Pais = 'REACTIVADA';
            ELSE
                SET v_Accion_Pais = 'REUSADA';
            END IF;

        ELSE
            /* 1C) Crear */
            INSERT INTO Pais (Codigo, Nombre)
            VALUES (_Codigo_Pais, _Nombre_Pais);

            SET v_Id_Pais = LAST_INSERT_ID();
            SET v_Accion_Pais = 'CREADA';
        END IF;
    END IF;

    /* ========================================================================================
       2) RESOLVER / CREAR ESTADO (dentro del País resuelto)
       ======================================================================================== */

    /* 2A) Buscar por CÓDIGO dentro del país */
    SET v_Id_Estado = NULL;
    SELECT Id_Estado, Codigo, Nombre, Activo
      INTO v_Id_Estado, v_Codigo, v_Nombre, v_Activo
    FROM Estado
    WHERE Codigo = _Codigo_Estado
      AND Fk_Id_Pais = v_Id_Pais
    LIMIT 1
    FOR UPDATE;

    IF v_Id_Estado IS NOT NULL THEN
        IF v_Nombre <> _Nombre_Estado THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'ERROR: Conflicto Estado. El Código existe pero el Nombre no coincide (en ese País).';
        END IF;

        IF v_Activo = 0 THEN
            UPDATE Estado
            SET Activo = 1, updated_at = NOW()
            WHERE Id_Estado = v_Id_Estado;
            SET v_Accion_Estado = 'REACTIVADA';
        ELSE
            SET v_Accion_Estado = 'REUSADA';
        END IF;

    ELSE
        /* 2B) Buscar por NOMBRE dentro del país */
        SELECT Id_Estado, Codigo, Nombre, Activo
          INTO v_Id_Estado, v_Codigo, v_Nombre, v_Activo
        FROM Estado
        WHERE Nombre = _Nombre_Estado
          AND Fk_Id_Pais = v_Id_Pais
        LIMIT 1
        FOR UPDATE;

        IF v_Id_Estado IS NOT NULL THEN
            IF v_Codigo <> _Codigo_Estado THEN
                SIGNAL SQLSTATE '45000'
                    SET MESSAGE_TEXT = 'ERROR: Conflicto Estado. El Nombre existe pero el Código no coincide (en ese País).';
            END IF;

            IF v_Activo = 0 THEN
                UPDATE Estado
                SET Activo = 1, updated_at = NOW()
                WHERE Id_Estado = v_Id_Estado;
                SET v_Accion_Estado = 'REACTIVADA';
            ELSE
                SET v_Accion_Estado = 'REUSADA';
            END IF;

        ELSE
            /* 2C) Crear */
            INSERT INTO Estado (Codigo, Nombre, Fk_Id_Pais)
            VALUES (_Codigo_Estado, _Nombre_Estado, v_Id_Pais);

            SET v_Id_Estado = LAST_INSERT_ID();
            SET v_Accion_Estado = 'CREADA';
        END IF;
    END IF;

    /* ========================================================================================
       3) RESOLVER / CREAR MUNICIPIO (dentro del Estado resuelto)
       ======================================================================================== */

    /* 3A) Buscar por CÓDIGO dentro del estado */
    SET v_Id_Municipio = NULL;
    SELECT Id_Municipio, Codigo, Nombre, Activo
      INTO v_Id_Municipio, v_Codigo, v_Nombre, v_Activo
    FROM Municipio
    WHERE Codigo = _Codigo_Municipio
      AND Fk_Id_Estado = v_Id_Estado
    LIMIT 1
    FOR UPDATE;

    IF v_Id_Municipio IS NOT NULL THEN
        IF v_Nombre <> _Nombre_Municipio THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'ERROR: Conflicto Municipio. El Código existe pero el Nombre no coincide (en ese Estado).';
        END IF;

        IF v_Activo = 0 THEN
            UPDATE Municipio
            SET Activo = 1, updated_at = NOW()
            WHERE Id_Municipio = v_Id_Municipio;
            SET v_Accion_Municipio = 'REACTIVADA';
        ELSE
            SET v_Accion_Municipio = 'REUSADA';
        END IF;

    ELSE
        /* 3B) Buscar por NOMBRE dentro del estado */
        SELECT Id_Municipio, Codigo, Nombre, Activo
          INTO v_Id_Municipio, v_Codigo, v_Nombre, v_Activo
        FROM Municipio
        WHERE Nombre = _Nombre_Municipio
          AND Fk_Id_Estado = v_Id_Estado
        LIMIT 1
        FOR UPDATE;

        IF v_Id_Municipio IS NOT NULL THEN
            IF v_Codigo <> _Codigo_Municipio THEN
                SIGNAL SQLSTATE '45000'
                    SET MESSAGE_TEXT = 'ERROR: Conflicto Municipio. El Nombre existe pero el Código no coincide (en ese Estado).';
            END IF;

            IF v_Activo = 0 THEN
                UPDATE Municipio
                SET Activo = 1, updated_at = NOW()
                WHERE Id_Municipio = v_Id_Municipio;
                SET v_Accion_Municipio = 'REACTIVADA';
            ELSE
                SET v_Accion_Municipio = 'REUSADA';
            END IF;

        ELSE
            /* 3C) Crear */
            INSERT INTO Municipio (Codigo, Nombre, Fk_Id_Estado)
            VALUES (_Codigo_Municipio, _Nombre_Municipio, v_Id_Estado);

            SET v_Id_Municipio = LAST_INSERT_ID();
            SET v_Accion_Municipio = 'CREADA';
        END IF;
    END IF;

    /* ----------------------------------------------------------------------------------------
       CONFIRMAR TRANSACCIÓN Y RESPUESTA
    ---------------------------------------------------------------------------------------- */
    COMMIT;

    SELECT
        'Registro Exitoso' AS Mensaje,

        v_Id_Pais      AS Id_Pais,
        v_Id_Estado    AS Id_Estado,
        v_Id_Municipio AS Id_Municipio,

        v_Accion_Pais      AS Accion_Pais,
        v_Accion_Estado    AS Accion_Estado,
        v_Accion_Municipio AS Accion_Municipio,

        CASE 
			WHEN v_Accion_Pais = 'CREADA' THEN v_Id_Pais 
			ELSE NULL 
		END AS Id_Nuevo_Pais,
        CASE 
			WHEN v_Accion_Estado = 'CREADA' THEN v_Id_Estado 
            ELSE NULL 
		END AS Id_Nuevo_Estado,
        CASE 
			WHEN v_Accion_Municipio = 'CREADA' THEN v_Id_Municipio 
            ELSE NULL 
		END AS Id_Nuevo_Municipio;

END$$

DELIMITER ;

/* ============================================================================================
	PROCEDIMIENTO: SP_ConsultarPaisEspecifico
   ============================================================================================
   ¿CUÁNDO SE USA?
   --------------
   Cuando el usuario abre la pantalla "Editar País" o un modal de detalle.

   ¿QUÉ RESUELVE?
   --------------
   Devuelve el registro del País por Id, incluyendo su estatus (Activo/Inactivo),
   para que el frontend pueda:
   - Precargar inputs (Código / Nombre)
   - Mostrar el estatus actual
   - Decidir si habilita acciones (reactivar / desactivar)

   NOTA DE DISEÑO
   --------------
   - NO filtramos por Activo=1 aquí, porque para edición/admin necesitas poder
     consultar también países inactivos.
   - Validamos Id y existencia para devolver errores controlados (no “null” silencioso).
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS SP_ConsultarPaisEspecifico$$

CREATE PROCEDURE SP_ConsultarPaisEspecifico(
    IN _Id_Pais INT
)
BEGIN
    /* ------------------------------------------------------------
       VALIDACIÓN 1: Id válido
       - Evita llamadas con NULL, 0, negativos, etc.
    ------------------------------------------------------------ */
    IF _Id_Pais IS NULL OR _Id_Pais <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Id_Pais inválido.';
    END IF;

    /* ------------------------------------------------------------
       VALIDACIÓN 2: El país existe
       - Si no existe, no tiene sentido cargar el formulario
    ------------------------------------------------------------ */
    IF NOT EXISTS (SELECT 1 FROM Pais WHERE Id_Pais = _Id_Pais) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: El País no existe.';
    END IF;

    /* ------------------------------------------------------------
       CONSULTA PRINCIPAL
       - Trae el país exacto
       - LIMIT 1 por seguridad
    ------------------------------------------------------------ */
    SELECT
        Id_Pais,
        Codigo,
        Nombre,
        Activo,
        created_at,
        updated_at
    FROM Pais
    WHERE Id_Pais = _Id_Pais
    LIMIT 1;
END$$

DELIMITER ;

/* ============================================================================================
   SECCIÓN: CONSULTAS ESPECÍFICAS (PARA EDICIÓN / DETALLE)
   ============================================================================================
   Estas rutinas son clave para la UX. No solo devuelven el dato pedido, sino todo el 
   contexto jerárquico necesario para que el formulario de edición se autocomplete.
   ============================================================================================ */
   
/* ============================================================================================
   PROCEDIMIENTO: SP_ConsultarEstadoEspecifico
   ============================================================================================
   ¿CUÁNDO SE USA?
   --------------
   Cuando el usuario abre la pantalla "Editar Estado".

   ¿QUÉ RESUELVE?
   --------------
   Para editar un Estado, el frontend normalmente necesita:
   - Datos del Estado (Código, Nombre, Activo)
   - El País al que pertenece (para preseleccionar el -- DROPdown de País)
   - (Opcional UI) Mostrar datos del País (Código/Nombre) como referencia

   NOTA DE DISEÑO
   --------------
   - NO filtramos por Activo=1 porque un admin puede necesitar editar/ver un estado inactivo.
   - Validamos Id y existencia para que el backend falle con un mensaje claro.
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS SP_ConsultarEstadoEspecifico$$

CREATE PROCEDURE SP_ConsultarEstadoEspecifico(
    IN _Id_Estado INT
)
BEGIN
    /* ------------------------------------------------------------
       VALIDACIÓN 1: Id válido
    ------------------------------------------------------------ */
    IF _Id_Estado IS NULL OR _Id_Estado <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Id_Estado inválido.';
    END IF;

    /* ------------------------------------------------------------
       VALIDACIÓN 2: El estado existe
    ------------------------------------------------------------ */
    IF NOT EXISTS (SELECT 1 FROM Estado WHERE Id_Estado = _Id_Estado) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: El Estado no existe.';
    END IF;

    /* ------------------------------------------------------------
       CONSULTA PRINCIPAL
       - Trae Estado + País padre
       - Esto permite precargar el -- DROPdown de País en el frontend
       - LIMIT 1 por seguridad
    ------------------------------------------------------------ */
    SELECT
        Est.Id_Estado,
        Est.Codigo      AS Codigo_Estado,
        Est.Nombre      AS Nombre_Estado,
        
        Est.Fk_Id_Pais  AS Id_Pais,
        Pais.Codigo     AS Codigo_Pais,
        Pais.Nombre     AS Nombre_Pais,
		
        Est.Activo      AS Activo_Estado,
        Est.created_at  AS created_at_estado,
        Est.updated_at  AS updated_at_estado
    FROM Estado Est
    JOIN Pais  Pais ON Pais.Id_Pais = Est.Fk_Id_Pais
    WHERE Est.Id_Estado = _Id_Estado
    LIMIT 1;
END$$

DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_ConsultarMunicipioEspecifico
   ============================================================================================
   ¿CUÁNDO SE USA?
   --------------
   Cuando el usuario abre la pantalla "Editar Municipio".

   ¿QUÉ RESUELVE?
   --------------
   Para que tu formulario sea rápido y “inteligente”, necesitas saber:
   - El Municipio actual (Código, Nombre, Activo)
   - El Estado actual al que pertenece
   - El País actual al que pertenece ese Estado

   Con esta info tu frontend puede:
   - Precargar inputs: Codigo_Municipio y Nombre_Municipio
   - Preseleccionar -- DROPdown País con Id_Pais actual
   - Preseleccionar -- DROPdown Estado con Id_Estado actual

   ¿POR QUÉ NO USAR UNA VISTA AQUÍ?
   -------------------------------
   Podrías usar una vista, pero un SP te da:
   - Validaciones más claras (si no existe el municipio, error controlado)
   - Un único contrato para el frontend
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS SP_ConsultarMunicipioEspecifico$$

CREATE PROCEDURE SP_ConsultarMunicipioEspecifico(
    IN _Id_Municipio INT
)
BEGIN
    /* ------------------------------------------------------------
       VALIDACIÓN 1: Id válido
       - Evita llamadas con NULL, 0, negativos, etc.
    ------------------------------------------------------------ */
    IF _Id_Municipio IS NULL OR _Id_Municipio <= 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ERROR: Id_Municipio inválido.';
    END IF;

    /* ------------------------------------------------------------
       VALIDACIÓN 2: El municipio existe
       - Si no existe, no tiene sentido cargar el formulario
    ------------------------------------------------------------ */
    IF NOT EXISTS (SELECT 1 FROM Municipio WHERE Id_Municipio = _Id_Municipio) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ERROR: El Municipio no existe.';
    END IF;

    /* ------------------------------------------------------------
       CONSULTA PRINCIPAL
       - Trae Municipio + Estado + País actual
       - LIMIT 1 por seguridad
    ------------------------------------------------------------ */
    SELECT
        Mun.Id_Municipio,
        Mun.Codigo  AS Codigo_Municipio,
        Mun.Nombre  AS Nombre_Municipio,
        
        Mun.Fk_Id_Estado AS Id_Estado,
        Est.Codigo  AS Codigo_Estado,
        Est.Nombre  AS Nombre_Estado,
        
        Est.Fk_Id_Pais AS Id_Pais,
        Pais.Codigo AS Codigo_Pais,
        Pais.Nombre AS Nombre_Pais,
        
        Mun.Activo  AS Activo_Municipio,
        Mun.created_at AS Created_at_Municipio,
        Mun.updated_at AS Updated_at_Municipio

    FROM Municipio Mun
    JOIN Estado Est  ON Est.Id_Estado = Mun.Fk_Id_Estado
    JOIN Pais Pais   ON Pais.Id_Pais  = Est.Fk_Id_Pais
    WHERE Mun.Id_Municipio = _Id_Municipio
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
   PROCEDIMIENTO: SP_ListarPaisesActivos
   ============================================================================================
   ¿CUÁNDO SE USA?
   --------------
   - Para llenar el dropdown inicial de Países en formularios en cascada.
   - Ejemplo: “Registrar/Editar Estado”, “Registrar/Editar Municipio”, etc.

   ¿QUÉ RESUELVE?
   --------------
   - Devuelve SOLO Países activos (Activo = 1).
   - Ordenados por Nombre para que el usuario encuentre rápido.

   CONTRATO PARA UI (REGLA CLAVE)
   ------------------------------
   - “Activo = 1” significa: el registro es seleccionable/usable en UI.
   - Un país inactivo NO debe aparecer en dropdowns normales.

   NOTA DE DISEÑO
   --------------
   - Si necesitas un dropdown administrativo que muestre también inactivos,
     crea otro SP separado (ej: SP_ListarPaisesAdmin) para no mezclar contratos.
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS SP_ListarPaisesActivos$$

CREATE PROCEDURE SP_ListarPaisesActivos()
BEGIN
    SELECT
        Id_Pais,
        Codigo,
        Nombre
    FROM Pais
    WHERE Activo = 1
    ORDER BY Nombre ASC;
END$$

DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_ListarEstadosPorPais   (VERSIÓN PRO: CONTRATO DE DROPDOWN “ACTIVOS”)
   ============================================================================================
   ¿CUÁNDO SE USA?
   --------------
   - Para llenar el dropdown de Estados cuando:
       a) Se selecciona un País en UI
       b) Se abre un formulario y hay que precargar los estados del País actual

   OBJETIVO
   --------
   - Devolver SOLO Estados activos (Activo=1) de un País seleccionado.
   - Ordenados por Nombre.

   MEJORA “PRO” QUE ARREGLA (BLINDAJE)
   ----------------------------------
   Antes:
   - Validabas que el País existiera, pero NO validabas que estuviera Activo=1.
   - Resultado: si alguien manda un request manipulado o la UI tiene cache viejo,
     el backend podría listar estados de un País inactivo.

   Ahora (contrato estricto):
   - Un dropdown “normal” SOLO permite seleccionar padres activos.
   - Si el País está inactivo => NO se lista y se responde error claro.

   ¿POR QUÉ ERROR (SIGNAL) Y NO LISTA VACÍA?
   -----------------------------------------
   - Porque lista vacía es ambigua: “¿no hay estados o el país está bloqueado?”
   - Con error, el frontend puede mostrar: “País inactivo, refresca”.

   VALIDACIONES
   ------------
   1) _Id_Pais válido (>0)
   2) País existe
   3) País Activo=1  (candado de contrato)
============================================================================================ */

DELIMITER $$
-- DROP PROCEDURE IF EXISTS SP_ListarEstadosPorPais$$

CREATE PROCEDURE SP_ListarEstadosPorPais(
    IN _Id_Pais INT
)
BEGIN
    /* ----------------------------------------------------------------------------------------
       PASO 0) Validación básica de input
       - Evita llamadas “chuecas” (null, 0, negativos) desde UI o requests directos.
    ---------------------------------------------------------------------------------------- */
    IF _Id_Pais IS NULL OR _Id_Pais <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Id_Pais inválido.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 1) Validar existencia del País
       - Si no existe, regresamos error explícito para no “simular” que no hay estados.
    ---------------------------------------------------------------------------------------- */
    IF NOT EXISTS (SELECT 1 FROM Pais WHERE Id_Pais = _Id_Pais) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: El País no existe.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 2) Candado PRO: País debe estar ACTIVO
       - Este es el cambio importante.
       - Refuerza el contrato de dropdown: “solo se listan hijos de padres activos”.
       - Protege contra:
           * requests manipuladas
           * UI con cache viejo (el país se desactivó mientras estaba abierto el formulario)
    ---------------------------------------------------------------------------------------- */
    IF NOT EXISTS (SELECT 1 FROM Pais WHERE Id_Pais = _Id_Pais AND Activo = 1) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: El País está inactivo. No se pueden listar Estados.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 3) Listar Estados activos del País
       - Nota: también filtramos Activo=1 del Estado porque es dropdown normal.
    ---------------------------------------------------------------------------------------- */
    SELECT
        Id_Estado,
        Codigo,
        Nombre
    FROM Estado
    WHERE Fk_Id_Pais = _Id_Pais
      AND Activo = 1
    ORDER BY Nombre ASC;
END$$
DELIMITER  ;

/* ============================================================================================
   PROCEDIMIENTO: SP_ListarMunicipiosPorEstado   (VERSIÓN PRO: CANDADO JERÁRQUICO)
   ============================================================================================
   ¿CUÁNDO SE USA?
   --------------
   - Para llenar el dropdown de Municipios cuando:
       a) Se selecciona un Estado en UI
       b) Se abre un formulario que requiere precargar municipios del estado actual

   OBJETIVO
   --------
   - Devolver SOLO Municipios activos (Activo=1) de un Estado seleccionado.
   - Ordenados por Nombre.

   MEJORA “PRO” QUE ARREGLA (IMPORTANTE)
   -------------------------------------
   Antes:
   - Validabas que el Estado existiera,
   - pero NO validabas que el Estado estuviera Activo=1,
   - y tampoco validabas que su País padre estuviera Activo=1.

   Resultado:
   - Un Estado inactivo (o con País inactivo) podía seguir “dando municipios” en dropdown,
     lo cual rompe el contrato de “solo seleccionables”.

   Ahora:
   - Candado jerárquico: Estado y su País deben estar activos.
   - Si no cumplen, se devuelve error explícito.

   ¿POR QUÉ VALIDAR PAÍS TAMBIÉN?
   ------------------------------
   Porque tu jerarquía real es:
       Municipio -> Estado -> País

   Si el País está inactivo, aunque el Estado estuviera activo, en cascada normal
   NO debería ser seleccionable. Esto mantiene consistencia y evita “puntos ciegos”.

   VALIDACIONES
   ------------
   1) _Id_Estado válido (>0)
   2) Estado existe
   3) Candado jerárquico:
      - Estado Activo=1
      - País padre Activo=1
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS SP_ListarMunicipiosPorEstado$$

CREATE PROCEDURE SP_ListarMunicipiosPorEstado(
    IN _Id_Estado INT
)
BEGIN
    /* ----------------------------------------------------------------------------------------
       PASO 0) Validación básica de input
    ---------------------------------------------------------------------------------------- */
    IF _Id_Estado IS NULL OR _Id_Estado <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Id_Estado inválido.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 1) Validar existencia del Estado
       - Si no existe, devolvemos error claro.
    ---------------------------------------------------------------------------------------- */
    IF NOT EXISTS (SELECT 1 FROM Estado WHERE Id_Estado = _Id_Estado) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: El Estado no existe.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 2) Candado PRO jerárquico: Estado y País deben estar ACTIVOS
       - Este es el cambio importante.
       - Protege contra:
           * requests manipuladas
           * UI con cache viejo
           * inconsistencias del contrato de cascada

       Lógica:
       - Buscamos el Estado por Id.
       - Subimos al País padre (Fk_Id_Pais).
       - Exigimos:
           E.Activo = 1
           P.Activo = 1

       Nota:
       - Usamos JOIN porque la regla es jerárquica (no basta mirar Estado solo).
    ---------------------------------------------------------------------------------------- */
    IF NOT EXISTS (
        SELECT 1
        FROM Pais P
        JOIN Estado E ON E.Fk_Id_Pais = P.Id_Pais
        WHERE E.Id_Estado = _Id_Estado
          AND E.Activo = 1
          AND P.Activo = 1
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: El Estado o su País están inactivos. No se pueden listar Municipios.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 3) Listar Municipios activos del Estado
       - También filtramos Activo=1 porque es dropdown normal.
    ---------------------------------------------------------------------------------------- */
    SELECT
        Id_Municipio,
        Codigo,
        Nombre
    FROM Municipio
    WHERE Fk_Id_Estado = _Id_Estado
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
   PROCEDIMIENTO: SP_ListarPaisesAdmin
   ============================================================================================
   ¿CUÁNDO SE USA?
   --------------
   - Pantallas administrativas (CRUD admin) donde necesitas ver:
       * Activos e Inactivos
       * Para poder reactivar/desactivar y depurar catálogos

   ¿POR QUÉ EXISTE ESTE SP?
   ------------------------
   - Para NO mezclar contratos:
       * SP_ListarPaisesActivos  => dropdowns normales (solo Activo=1)
       * SP_ListarPaisesAdmin    => administración (todos)

   SEGURIDAD (IMPORTANTE)
   ----------------------
   - Este SP debería consumirse solo por usuarios con rol admin.
     (Ej: Cat_Roles / permisos en backend)

   QUÉ DEVUELVE
   ------------
   - Todos los países (Activo=1 y Activo=0)
   - Incluye campo Activo para que la UI pinte el estatus
   - Orden recomendado:
       * Activos primero
       * Luego por Nombre para fácil búsqueda
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS SP_ListarPaisesAdmin$$

CREATE PROCEDURE SP_ListarPaisesAdmin()
BEGIN
    SELECT
        Id_Pais,
        Codigo,
        Nombre,
        Activo,
        created_at,
        updated_at
    FROM Pais
    ORDER BY
        Activo DESC,   -- primero activos (1), luego inactivos (0)
        Nombre ASC;
END$$

DELIMITER  ;

/* ============================================================================================
   PROCEDIMIENTO: SP_ListarEstadosAdminPorPais
   ============================================================================================
   ¿CUÁNDO SE USA?
   --------------
   - Pantalla administrativa de Estados, filtrando por País “padre”.
   - Ejemplo de flujo típico:
       1) Admin elige un País (puede estar activo o inactivo)
       2) UI lista TODOS los Estados de ese País (activos e inactivos)

   ¿POR QUÉ ES DIFERENTE AL SP NORMAL?
   -----------------------------------
   - SP_ListarEstadosPorPais (normal) exige País Activo=1 porque es dropdown de usuario final.
   - En ADMIN no quieres bloquearte si el país está inactivo:
       * necesitas poder ver sus estados para reactivarlos, corregir, limpiar, etc.

   VALIDACIONES
   ------------
   1) _Id_Pais válido (>0)
   2) País existe (aunque esté inactivo)
      - Si no existe, es error real (no hay nada que listar)

   QUÉ DEVUELVE
   ------------
   - Todos los estados del país (Activo=1 y Activo=0)
   - Incluye Activo + timestamps para auditoría visual
   - Orden:
       * Activos primero
       * Luego por Nombre
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS SP_ListarEstadosAdminPorPais$$
CREATE PROCEDURE SP_ListarEstadosAdminPorPais(
    IN _Id_Pais INT
)
BEGIN
    /* ----------------------------------------------------------------------------------------
       PASO 0) Validación básica de input
    ---------------------------------------------------------------------------------------- */
    IF _Id_Pais IS NULL OR _Id_Pais <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Id_Pais inválido.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 1) Validar existencia del País (admin permite inactivos, pero NO permite inexistentes)
    ---------------------------------------------------------------------------------------- */
    IF NOT EXISTS (SELECT 1 FROM Pais WHERE Id_Pais = _Id_Pais) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: El País no existe.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 2) Listar TODOS los Estados del País (activos e inactivos)
    ---------------------------------------------------------------------------------------- */
    SELECT
        Id_Estado,
        Codigo,
        Nombre,
        Fk_Id_Pais,
        Activo,
        created_at,
        updated_at
    FROM Estado
    WHERE Fk_Id_Pais = _Id_Pais
    ORDER BY
        Activo DESC,
        Nombre ASC;
END$$

DELIMITER  ;

/* ============================================================================================
   PROCEDIMIENTO: SP_ListarMunicipiosAdminPorEstado
   ============================================================================================
   ¿CUÁNDO SE USA?
   --------------
   - Pantalla administrativa de Municipios, filtrando por Estado “padre”.
   - Flujo típico:
       1) Admin elige un Estado (puede estar activo o inactivo)
       2) UI lista TODOS los Municipios de ese Estado

   ¿POR QUÉ ES DIFERENTE AL SP NORMAL?
   -----------------------------------
   - SP_ListarMunicipiosPorEstado (normal) exige Estado Activo=1 y País Activo=1 (candado jerárquico)
     porque es dropdown de selección normal.
   - En ADMIN no quieres bloquearte por jerarquía inactiva:
       * necesitas listar para mantenimiento: reactivar, corregir, depurar, etc.

   VALIDACIONES
   ------------
   1) _Id_Estado válido (>0)
   2) Estado existe (aunque esté inactivo)
      - Si no existe, es error real (no hay nada que listar)

   QUÉ DEVUELVE
   ------------
   - Todos los municipios del estado (Activo=1 y Activo=0)
   - Incluye Activo + timestamps
   - Orden:
       * Activos primero
       * Luego por Nombre
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS SP_ListarMunicipiosAdminPorEstado$$

CREATE PROCEDURE SP_ListarMunicipiosAdminPorEstado(
    IN _Id_Estado INT
)
BEGIN
    /* ----------------------------------------------------------------------------------------
       PASO 0) Validación básica de input
    ---------------------------------------------------------------------------------------- */
    IF _Id_Estado IS NULL OR _Id_Estado <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Id_Estado inválido.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 1) Validar existencia del Estado (admin permite inactivos, pero NO permite inexistentes)
    ---------------------------------------------------------------------------------------- */
    IF NOT EXISTS (SELECT 1 FROM Estado WHERE Id_Estado = _Id_Estado) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: El Estado no existe.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 2) Listar TODOS los Municipios del Estado (activos e inactivos)
    ---------------------------------------------------------------------------------------- */
    SELECT
        Id_Municipio,
        Codigo,
        Nombre,
        Fk_Id_Estado,
        Activo,
        created_at,
        updated_at
    FROM Municipio
    WHERE Fk_Id_Estado = _Id_Estado
    ORDER BY
        Activo DESC,
        Nombre ASC;
END$$

DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_RegistrarPais  (VERSIÓN PRO: 1062 => RE-RESOLVE)
   ============================================================================================
   OBJETIVO
   --------
   Registrar un País (Codigo + Nombre) con blindaje fuerte contra duplicados y carreras
   (concurrencia), devolviendo una respuesta “limpia” para el frontend:

   - Si el País NO existe -> INSERT -> Accion = 'CREADA'
   - Si el País existe pero Activo=0 -> UPDATE Activo=1 -> Accion = 'REACTIVADA'
   - Si el País ya existía (por doble submit / carrera) -> NO error -> Accion='REUSADA'
   - Si hay conflicto real (mismo código con otro nombre, o viceversa) -> ERROR controlado.

   ¿CUÁNDO SE USA?
   --------------
   - Formulario "Alta de País" (catálogo).
   - Casos típicos de concurrencia:
       * El usuario da doble clic a “Guardar”
       * La red está lenta y re-envía
       * Dos usuarios registran lo mismo casi al mismo tiempo

   REGLAS DE NEGOCIO (CONTRATO)
   ---------------------------
   Reglas determinísticas (SIN “OR ... LIMIT 1” ambiguo):

   1) Primero se resuelve por CÓDIGO (regla principal):
      - Si existe:
          a) Si NOMBRE no coincide -> ERROR (conflicto)
          b) Si Activo=0 -> REACTIVA (UPDATE Activo=1)
          c) Si Activo=1 -> ERROR (duplicado real, no es “carrera”)
      - Si no existe -> continúa

   2) Si no existe por CÓDIGO, se resuelve por NOMBRE:
      - Si existe:
          a) Si CÓDIGO no coincide -> ERROR (conflicto)
          b) Si Activo=0 -> REACTIVA
          c) Si Activo=1 -> ERROR (duplicado real)
      - Si no existe -> continúa

   3) Si NO existe por CÓDIGO ni por NOMBRE:
      - INTENTA INSERT.
      - Aquí es donde puede ocurrir la carrera (1062) si alguien insertó “en el mismo instante”.

   CONCURRENCIA (POR QUÉ EXISTE EL RE-RESOLVE)
   ------------------------------------------
   Importante: `SELECT ... FOR UPDATE` solo bloquea SI EXISTE una fila.
   Si NO hay fila (aún no existe el País), no hay nada que bloquear.
   Entonces, dos transacciones pueden llegar al `INSERT` al mismo tiempo:

     Tx A: no encuentra fila -> INSERT -> OK
     Tx B: no encuentra fila -> INSERT -> 1062 (UNIQUE lo frena)

   En la versión simple, Tx B regresaría error.
   En esta versión PRO, Tx B:
     - Detecta 1062 (bandera v_Dup=1)
     - Hace ROLLBACK
     - Re-consulta el registro ya creado
     - Devuelve REUSADA (o REACTIVADA si estaba inactivo)

   SEGURIDAD / INTEGRIDAD
   ----------------------
   - UNIQUE en tabla sigue siendo la última línea de defensa:
       Pais.Codigo UNIQUE
       Pais.Nombre UNIQUE
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
     - Id_Pais
     - Accion: 'CREADA' | 'REACTIVADA' | 'REUSADA'

============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS SP_RegistrarPais$$

CREATE PROCEDURE SP_RegistrarPais(
    IN _Codigo VARCHAR(50),
    IN _Nombre VARCHAR(255)
)
SP: BEGIN
    /* ----------------------------------------------------------------------------------------
       VARIABLES DE TRABAJO
       - v_* guardan el registro encontrado (si existe).
       - v_Dup es una BANDERA para detectar que ocurrió 1062 durante el INSERT.
         (OJO: al ser CONTINUE HANDLER, si no revisas v_Dup, te puedes ir a COMMIT sin insertar.)
    ---------------------------------------------------------------------------------------- */
    DECLARE v_Id_Pais INT DEFAULT NULL;
    DECLARE v_Codigo  VARCHAR(50) DEFAULT NULL;
    DECLARE v_Nombre  VARCHAR(255) DEFAULT NULL;
    DECLARE v_Activo  TINYINT(1) DEFAULT NULL;

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
       - TRIM: evita que "MEX " y "MEX" se comporten como cosas diferentes
       - NULLIF: convierte '' en NULL para validar obligatorios de forma limpia
    ---------------------------------------------------------------------------------------- */
    SET _Codigo = NULLIF(TRIM(_Codigo), '');
    SET _Nombre = NULLIF(TRIM(_Nombre), '');

    /* ----------------------------------------------------------------------------------------
       VALIDACIONES BÁSICAS
    ---------------------------------------------------------------------------------------- */
    IF _Codigo IS NULL OR _Nombre IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Código y Nombre del País son obligatorios.';
    END IF;

    /* ========================================================================================
       TRANSACCIÓN PRINCIPAL (INTENTO NORMAL)
       - Aquí resolvemos por CÓDIGO -> por NOMBRE -> INSERT
    ======================================================================================== */
    START TRANSACTION;

    /* ----------------------------------------------------------------------------------------
       PASO 1: BUSCAR POR CÓDIGO (REGLA PRINCIPAL)
       - FOR UPDATE:
         Si la fila existe, la bloquea para evitar carreras en reactivación/cambios simultáneos.
       - Limpieza de variables:
         Evita que queden valores viejos si el SELECT no retorna fila.
    ---------------------------------------------------------------------------------------- */
    SET v_Id_Pais = NULL; SET v_Codigo = NULL; SET v_Nombre = NULL; SET v_Activo = NULL;

    SELECT Id_Pais, Codigo, Nombre, Activo
      INTO v_Id_Pais, v_Codigo, v_Nombre, v_Activo
    FROM Pais
    WHERE Codigo = _Codigo
    LIMIT 1
    FOR UPDATE;

    IF v_Id_Pais IS NOT NULL THEN
        /* Conflicto fuerte: mismo código pero otro nombre => datos inconsistentes */
        IF v_Nombre <> _Nombre THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'ERROR: Conflicto País. El Código ya existe pero el Nombre no coincide.';
        END IF;

        /* Si existe pero está inactivo => reactivación segura (borrado lógico) */
        IF v_Activo = 0 THEN
            UPDATE Pais
            SET Activo = 1,
                updated_at = NOW()
            WHERE Id_Pais = v_Id_Pais;

            COMMIT;
            SELECT 'País reactivado exitosamente' AS Mensaje,
                   v_Id_Pais AS Id_Pais,
                   'REACTIVADA' AS Accion;
            LEAVE SP;
        END IF;

        /* Si existe y está activo => duplicado REAL (no es concurrencia) */
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Ya existe un País ACTIVO con ese Código.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 2: BUSCAR POR NOMBRE (REGLA SECUNDARIA)
       - Misma lógica que el código, pero al revés.
    ---------------------------------------------------------------------------------------- */
    SET v_Id_Pais = NULL; SET v_Codigo = NULL; SET v_Nombre = NULL; SET v_Activo = NULL;

    SELECT Id_Pais, Codigo, Nombre, Activo
      INTO v_Id_Pais, v_Codigo, v_Nombre, v_Activo
    FROM Pais
    WHERE Nombre = _Nombre
    LIMIT 1
    FOR UPDATE;

    IF v_Id_Pais IS NOT NULL THEN
        /* Conflicto fuerte: mismo nombre pero otro código => datos inconsistentes */
        IF v_Codigo <> _Codigo THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'ERROR: Conflicto País. El Nombre ya existe pero el Código no coincide.';
        END IF;

        IF v_Activo = 0 THEN
            UPDATE Pais
            SET Activo = 1,
                updated_at = NOW()
            WHERE Id_Pais = v_Id_Pais;

            COMMIT;
            SELECT 'País reactivado exitosamente' AS Mensaje,
                   v_Id_Pais AS Id_Pais,
                   'REACTIVADA' AS Accion;
            LEAVE SP;
        END IF;

        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Ya existe un País ACTIVO con ese Nombre.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 3: INSERT (CREACIÓN REAL)
       - Este es el único punto donde la concurrencia puede provocar 1062:
         porque NO había fila para bloquear con FOR UPDATE.
       - v_Dup se reinicia antes del INSERT para que sea confiable.
    ---------------------------------------------------------------------------------------- */
    SET v_Dup = 0;

    INSERT INTO Pais (Codigo, Nombre)
    VALUES (_Codigo, _Nombre);

    /* Si NO hubo 1062, v_Dup sigue en 0 => Insert exitoso */
    IF v_Dup = 0 THEN
        COMMIT;
        SELECT 'País registrado exitosamente' AS Mensaje,
               LAST_INSERT_ID() AS Id_Pais,
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
       RE-RESOLVE A) Localizar por CÓDIGO
       - Si aparece: validamos coherencia con el Nombre solicitado.
       - Si está inactivo: lo reactivamos y devolvemos REACTIVADA.
       - Si está activo: devolvemos REUSADA (UX limpia).
    ---------------------------------------------------------------------------------------- */
    SET v_Id_Pais = NULL; SET v_Codigo = NULL; SET v_Nombre = NULL; SET v_Activo = NULL;

    SELECT Id_Pais, Codigo, Nombre, Activo
      INTO v_Id_Pais, v_Codigo, v_Nombre, v_Activo
    FROM Pais
    WHERE Codigo = _Codigo
    LIMIT 1
    FOR UPDATE;

    IF v_Id_Pais IS NOT NULL THEN
        IF v_Nombre <> _Nombre THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'ERROR: Concurrencia detectada pero hay conflicto: Código existe con otro Nombre.';
        END IF;

        IF v_Activo = 0 THEN
            UPDATE Pais
            SET Activo = 1,
                updated_at = NOW()
            WHERE Id_Pais = v_Id_Pais;

            COMMIT;
            SELECT 'País reactivado (re-resuelto por concurrencia)' AS Mensaje,
                   v_Id_Pais AS Id_Pais,
                   'REACTIVADA' AS Accion;
            LEAVE SP;
        END IF;

        COMMIT;
        SELECT 'País ya existía (reusado por concurrencia)' AS Mensaje,
               v_Id_Pais AS Id_Pais,
               'REUSADA' AS Accion;
        LEAVE SP;
    END IF;

    /* ----------------------------------------------------------------------------------------
       RE-RESOLVE B) Si no apareció por código (muy raro), buscamos por NOMBRE
       - Misma lógica, pero validando coherencia del Código.
    ---------------------------------------------------------------------------------------- */
    SET v_Id_Pais = NULL; SET v_Codigo = NULL; SET v_Nombre = NULL; SET v_Activo = NULL;

    SELECT Id_Pais, Codigo, Nombre, Activo
      INTO v_Id_Pais, v_Codigo, v_Nombre, v_Activo
    FROM Pais
    WHERE Nombre = _Nombre
    LIMIT 1
    FOR UPDATE;

    IF v_Id_Pais IS NOT NULL THEN
        IF v_Codigo <> _Codigo THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'ERROR: Concurrencia detectada pero hay conflicto: Nombre existe con otro Código.';
        END IF;

        IF v_Activo = 0 THEN
            UPDATE Pais
            SET Activo = 1,
                updated_at = NOW()
            WHERE Id_Pais = v_Id_Pais;

            COMMIT;
            SELECT 'País reactivado (re-resuelto por concurrencia)' AS Mensaje,
                   v_Id_Pais AS Id_Pais,
                   'REACTIVADA' AS Accion;
            LEAVE SP;
        END IF;

        COMMIT;
        SELECT 'País ya existía (reusado por concurrencia)' AS Mensaje,
               v_Id_Pais AS Id_Pais,
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
   PROCEDIMIENTO: SP_EditarPais  (VERSIÓN PRO “REAL”: Lock determinístico + SIN CAMBIOS + 1062 controlado)
   ============================================================================================

   OBJETIVO
   --------
   Editar Código y Nombre de un País, con:
   - Validaciones previas entendibles (mensajes claros)
   - “SIN_CAMBIOS” (si el usuario no cambió nada, no hacemos UPDATE)
   - Blindaje contra duplicados (Codigo único / Nombre único)
   - Manejo “PRO” de concurrencia: 1062 => respuesta controlada “CONFLICTO”
   - Lock determinístico de filas para minimizar deadlocks en escenarios de “intercambio” (swap)

   ESCENARIO CLÁSICO DE DEADLOCK (POR QUÉ AQUÍ SÍ IMPORTA “LOCK DETERMINÍSTICO”)
   ----------------------------------------------------------------------------
   Caso:
   - Usuario A edita País #1 (MEX) y lo quiere cambiar a Codigo='USA'
   - Usuario B edita País #2 (USA) y lo quiere cambiar a Codigo='MEX'
   Sin lock determinístico, podría ocurrir:
   - A bloquea País #1 (FOR UPDATE)
   - B bloquea País #2 (FOR UPDATE)
   - A intenta bloquear País #2 (para validar duplicado por código)
   - B intenta bloquear País #1 (para validar duplicado por código)
   => DEADLOCK.

   SOLUCIÓN
   --------
   En vez de “bloquear primero el país a editar y luego el posible conflicto” en orden variable,
   hacemos un lock determinístico de TODAS las filas relevantes (máximo 3):
     - El País que se edita (_Id_Pais)
     - El País que ya tenga el nuevo Código (si existe)
     - El País que ya tenga el nuevo Nombre (si existe)
   Y las bloqueamos SIEMPRE en orden ascendente de Id_Pais.

   REGLAS (CONTRATO DE NEGOCIO)
   ----------------------------
   1) El País a editar DEBE existir.
   2) _Nuevo_Codigo y _Nuevo_Nombre son obligatorios.
   3) No puede existir OTRO País con:
      - el mismo Codigo
      - el mismo Nombre
      (excluimos el mismo Id_Pais para permitir guardar sin cambios)
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
     - Id_Pais

   SIN CAMBIOS:
     - Mensaje
     - Accion = 'SIN_CAMBIOS'
     - Id_Pais

   CONFLICTO (1062):
     - Mensaje
     - Accion = 'CONFLICTO'
     - Campo = 'CODIGO' | 'NOMBRE'
     - Id_Conflicto
     - Id_Pais_Que_Intentabas_Editar
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS SP_EditarPais$$

CREATE PROCEDURE SP_EditarPais(
    IN _Id_Pais INT,
    IN _Nuevo_Codigo VARCHAR(50),
    IN _Nuevo_Nombre VARCHAR(255)
)
SP: BEGIN
    /* ========================================================================================
       PARTE 0) VARIABLES
       ======================================================================================== */

    /* Valores actuales del país (para “SIN_CAMBIOS”) */
    DECLARE v_Codigo_Actual VARCHAR(50)  DEFAULT NULL;
    DECLARE v_Nombre_Actual VARCHAR(255) DEFAULT NULL;

    /* Posibles filas “en conflicto” (por código o por nombre) */
    DECLARE v_Id_Pais_DupCodigo INT DEFAULT NULL;
    DECLARE v_Id_Pais_DupNombre INT DEFAULT NULL;

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
    SET _Nuevo_Codigo = NULLIF(TRIM(_Nuevo_Codigo), '');
    SET _Nuevo_Nombre = NULLIF(TRIM(_Nuevo_Nombre), '');

    /* ========================================================================================
       PARTE 3) VALIDACIONES BÁSICAS
       ======================================================================================== */
    IF _Id_Pais IS NULL OR _Id_Pais <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Id_Pais inválido.';
    END IF;

    IF _Nuevo_Codigo IS NULL OR _Nuevo_Nombre IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Código y Nombre son obligatorios.';
    END IF;

    /* ========================================================================================
       PARTE 4) TRANSACCIÓN PRINCIPAL
       ======================================================================================== */
    START TRANSACTION;

    /* ----------------------------------------------------------------------------------------
       PASO 1) Lectura inicial del País a editar (SIN bloquear todavía)
       ----------------------------------------------------------------------------------------
       - Aquí solo verificamos que exista y obtenemos valores actuales.
       - OJO: aún NO bloqueamos para poder hacer lock determinístico después.
       - Si alguien cambia algo en microsegundos, lo corregimos en PASO 4 (re-lectura con lock).
    ---------------------------------------------------------------------------------------- */
    SET v_Codigo_Actual = NULL;
    SET v_Nombre_Actual = NULL;

    SELECT Codigo, Nombre
      INTO v_Codigo_Actual, v_Nombre_Actual
    FROM Pais
    WHERE Id_Pais = _Id_Pais
    LIMIT 1;

    IF v_Codigo_Actual IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: El País no existe.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 2) Descubrir “posibles conflictos” (SIN bloquear todavía)
       ----------------------------------------------------------------------------------------
       - Buscamos qué fila (si existe) YA tiene el nuevo Código o el nuevo Nombre.
       - Esto nos permite saber QUÉ filas hay que bloquear en orden determinístico.
       - NO usamos FOR UPDATE aquí, justamente para NO inducir locks en orden variable.
    ---------------------------------------------------------------------------------------- */
    SET v_Id_Pais_DupCodigo = NULL;

    SELECT Id_Pais
      INTO v_Id_Pais_DupCodigo
    FROM Pais
    WHERE Codigo = _Nuevo_Codigo
      AND Id_Pais <> _Id_Pais
    LIMIT 1;

    SET v_Id_Pais_DupNombre = NULL;

    SELECT Id_Pais
      INTO v_Id_Pais_DupNombre
    FROM Pais
    WHERE Nombre = _Nuevo_Nombre
      AND Id_Pais <> _Id_Pais
    LIMIT 1;

    /* ----------------------------------------------------------------------------------------
       PASO 3) LOCK DETERMINÍSTICO de filas relevantes (hasta 3)
       ----------------------------------------------------------------------------------------
       - Construimos la lista (Id a editar, Id por código, Id por nombre)
       - Quitamos NULLs y duplicados
       - Bloqueamos SIEMPRE en orden ascendente:
           lock #1: el menor Id
           lock #2: el siguiente
           lock #3: el siguiente
       - Cada lock se hace con SELECT ... FOR UPDATE que NO devuelve result sets “extra”.
    ---------------------------------------------------------------------------------------- */
    SET v_L1 = _Id_Pais;
    SET v_L2 = v_Id_Pais_DupCodigo;
    SET v_L3 = v_Id_Pais_DupNombre;

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

        SELECT 1
          INTO v_Existe
        FROM Pais
        WHERE Id_Pais = v_Min
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

        SELECT 1
          INTO v_Existe
        FROM Pais
        WHERE Id_Pais = v_Min
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

        SELECT 1
          INTO v_Existe
        FROM Pais
        WHERE Id_Pais = v_Min
        LIMIT 1
        FOR UPDATE;

        IF v_Existe IS NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Inconsistencia: fila a bloquear ya no existe (lock #3).';
        END IF;
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 4) Re-lectura del País objetivo YA con lock (consistencia)
       ----------------------------------------------------------------------------------------
       - Ahora sí, ya tenemos un punto estable:
         la fila _Id_Pais está bloqueada dentro de esta transacción.
       - Actualizamos “actuales” por si cambiaron entre PASO 1 y PASO 3.
    ---------------------------------------------------------------------------------------- */
    SET v_Codigo_Actual = NULL;
    SET v_Nombre_Actual = NULL;

    SELECT Codigo, Nombre
      INTO v_Codigo_Actual, v_Nombre_Actual
    FROM Pais
    WHERE Id_Pais = _Id_Pais
    LIMIT 1
    FOR UPDATE;

    IF v_Codigo_Actual IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: El País no existe (desapareció durante la edición).';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 5) SIN CAMBIOS (salida temprana)
       ----------------------------------------------------------------------------------------
       - Si el usuario no cambió ni Código ni Nombre:
         devolvemos “SIN_CAMBIOS” y liberamos locks rápido (COMMIT).
    ---------------------------------------------------------------------------------------- */
    IF v_Codigo_Actual = _Nuevo_Codigo
       AND v_Nombre_Actual = _Nuevo_Nombre THEN

        COMMIT;

        SELECT 'Sin cambios: El País ya tiene ese Código y ese Nombre.' AS Mensaje,
               'SIN_CAMBIOS' AS Accion,
               _Id_Pais AS Id_Pais;
        LEAVE SP;
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 6) Pre-check duplicidad por CÓDIGO (otro Id)
       ----------------------------------------------------------------------------------------
       - Aquí ya estamos bajo locks determinísticos, así reducimos deadlocks.
       - Excluimos el mismo Id_Pais (edición del propio registro).
    ---------------------------------------------------------------------------------------- */
    SET v_DupId = NULL;

    SELECT Id_Pais
      INTO v_DupId
    FROM Pais
    WHERE Codigo = _Nuevo_Codigo
      AND Id_Pais <> _Id_Pais
    ORDER BY Id_Pais
    LIMIT 1
    FOR UPDATE;

    IF v_DupId IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Ya existe OTRO País con ese CÓDIGO.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 7) Pre-check duplicidad por NOMBRE (otro Id)
    ---------------------------------------------------------------------------------------- */
    SET v_DupId = NULL;

    SELECT Id_Pais
      INTO v_DupId
    FROM Pais
    WHERE Nombre = _Nuevo_Nombre
      AND Id_Pais <> _Id_Pais
    ORDER BY Id_Pais
    LIMIT 1
    FOR UPDATE;

    IF v_DupId IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Ya existe OTRO País con ese NOMBRE.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 8) UPDATE FINAL (aquí puede aparecer 1062 por carrera)
       ----------------------------------------------------------------------------------------
       - Reseteamos v_Dup = 0 justo antes del UPDATE.
       - Si alguien “se coló” entre nuestros checks y el update (concurrencia real),
         el UNIQUE dispara 1062 y nuestro handler marca v_Dup=1.
    ---------------------------------------------------------------------------------------- */
    SET v_Dup = 0;

    UPDATE Pais
    SET Codigo = _Nuevo_Codigo,
        Nombre = _Nuevo_Nombre,
        updated_at = NOW()
    WHERE Id_Pais = _Id_Pais;

    /* ----------------------------------------------------------------------------------------
       PASO 9) Si hubo 1062 => CONFLICTO CONTROLADO
       ----------------------------------------------------------------------------------------
       - ROLLBACK: no guardamos nada.
       - Re-consultamos quién causó el choque:
           * primero por Código
           * si no, por Nombre
       - Devolvemos datos para UI (mensaje + Id_Conflicto).
    ---------------------------------------------------------------------------------------- */
    IF v_Dup = 1 THEN
        ROLLBACK;

        SET v_Id_Conflicto = NULL;
        SET v_Campo_Conflicto = NULL;

        /* 9.1) Conflicto por Código */
        SELECT Id_Pais
          INTO v_Id_Conflicto
        FROM Pais
        WHERE Codigo = _Nuevo_Codigo
          AND Id_Pais <> _Id_Pais
        ORDER BY Id_Pais
        LIMIT 1;

        IF v_Id_Conflicto IS NOT NULL THEN
            SET v_Campo_Conflicto = 'CODIGO';
        ELSE
            /* 9.2) Conflicto por Nombre */
            SELECT Id_Pais
              INTO v_Id_Conflicto
            FROM Pais
            WHERE Nombre = _Nuevo_Nombre
              AND Id_Pais <> _Id_Pais
            ORDER BY Id_Pais
            LIMIT 1;

            IF v_Id_Conflicto IS NOT NULL THEN
                SET v_Campo_Conflicto = 'NOMBRE';
            END IF;
        END IF;

        SELECT 'No se guardó: otro usuario se adelantó. Refresca y vuelve a intentar.' AS Mensaje,
               'CONFLICTO' AS Accion,
               v_Campo_Conflicto AS Campo,
               v_Id_Conflicto AS Id_Conflicto,
               _Id_Pais AS Id_Pais_Que_Intentabas_Editar;
        LEAVE SP;
    END IF;

    /* ----------------------------------------------------------------------------------------
       ÉXITO
    ---------------------------------------------------------------------------------------- */
    COMMIT;

    SELECT 'País actualizado correctamente' AS Mensaje,
           'ACTUALIZADA' AS Accion,
           _Id_Pais AS Id_Pais;

END$$

DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_CambiarEstatusPais
   ============================================================================================
   OBJETIVO
   --------
   Activar/Desactivar (borrado lógico) un País:
      Pais.Activo (1 = activo, 0 = inactivo)

   REGLA CRÍTICA (INTEGRIDAD JERÁRQUICA)
   ------------------------------------
   - NO se permite DESACTIVAR un País si tiene:
       * ESTADOS ACTIVOS, o
       * MUNICIPIOS ACTIVOS bajo ese país
   Esto evita inconsistencia:
      Pais.Activo=0
      Estado.Activo=1
      Municipio.Activo=1

   CONCURRENCIA
   ------------
   - SELECT ... FOR UPDATE sobre Pais para:
       * Validar existencia
       * Evitar cambios simultáneos contradictorios
============================================================================================ */
DELIMITER $$

-- DROP PROCEDURE IF EXISTS SP_CambiarEstatusPais$$

CREATE PROCEDURE SP_CambiarEstatusPais(
    IN _Id_Pais INT,
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
    IF _Id_Pais IS NULL OR _Id_Pais <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Id_Pais inválido.';
    END IF;

    IF _Nuevo_Estatus NOT IN (0,1) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Estatus inválido (solo 0 o 1).';
    END IF;

    START TRANSACTION;

    /* ----------------------------------------------------------------------------------------
       1) VALIDAR EXISTENCIA DEL PAÍS Y BLOQUEAR SU FILA
    ---------------------------------------------------------------------------------------- */
    SELECT 1, Activo
      INTO v_Existe, v_Activo_Actual
    FROM Pais
    WHERE Id_Pais = _Id_Pais
    LIMIT 1
    FOR UPDATE;

    IF v_Existe IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: El País no existe.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       2) "SIN CAMBIOS" (IDEMPOTENCIA)
       - Si el país ya estaba en ese estatus, no hacemos nada y devolvemos mensaje claro.
    ---------------------------------------------------------------------------------------- */
    IF v_Activo_Actual = _Nuevo_Estatus THEN
        COMMIT;
        SELECT CASE
            WHEN _Nuevo_Estatus = 1 THEN 'Sin cambios: El País ya estaba Activo.'
            ELSE 'Sin cambios: El País ya estaba Inactivo.'
        END AS Mensaje,
        v_Activo_Actual AS Activo_Anterior,
        _Nuevo_Estatus AS Activo_Nuevo;
    ELSE
        /* ------------------------------------------------------------------------------------
           3) SI INTENTA DESACTIVAR (Nuevo_Estatus=0):
              BLOQUEAR SI HAY HIJOS ACTIVOS
        ------------------------------------------------------------------------------------ */
        IF _Nuevo_Estatus = 0 THEN

            /* 3A) Candado: Estados activos */
            SET v_Tmp = NULL;
            SELECT Id_Estado
              INTO v_Tmp
            FROM Estado
            WHERE Fk_Id_Pais = _Id_Pais
              AND Activo = 1 -- <--- CORRECCIÓN IMPORTANTE
            LIMIT 1;

            IF v_Tmp IS NOT NULL THEN
                SIGNAL SQLSTATE '45000'
                    SET MESSAGE_TEXT = 'BLOQUEADO: No se puede desactivar el País porque tiene ESTADOS ACTIVOS. Desactiva primero los Estados.';
            END IF;

            /* 3B) Candado extra: Municipios activos bajo el país (por si hay datos sucios) */
            SET v_Tmp = NULL;
            SELECT Mun.Id_Municipio
              INTO v_Tmp
            FROM Municipio Mun
            JOIN Estado Est ON Est.Id_Estado = Mun.Fk_Id_Estado
            WHERE Est.Fk_Id_Pais = _Id_Pais
              AND Mun.Activo = 1
            LIMIT 1;

            IF v_Tmp IS NOT NULL THEN
                SIGNAL SQLSTATE '45000'
                    SET MESSAGE_TEXT = 'BLOQUEADO: No se puede desactivar el País porque existen MUNICIPIOS ACTIVOS bajo él. Desactiva primero Municipios/Estados.';
            END IF;
        END IF;

        /* ------------------------------------------------------------------------------------
           4) APLICAR CAMBIO DE ESTATUS
        ------------------------------------------------------------------------------------ */
        UPDATE Pais
        SET Activo = _Nuevo_Estatus,
            updated_at = NOW()
        WHERE Id_Pais = _Id_Pais;

        COMMIT;

        /* ------------------------------------------------------------------------------------
           5) RESPUESTA PARA FRONTEND
        ------------------------------------------------------------------------------------ */
        SELECT CASE
            WHEN _Nuevo_Estatus = 1 THEN 'País Reactivado'
            ELSE 'País Desactivado (Oculto)'
        END AS Mensaje,
        v_Activo_Actual AS Activo_Anterior,
        _Nuevo_Estatus AS Activo_Nuevo;
    END IF;

END$$
DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_EliminarPaisFisico
   ============================================================================================
   OBJETIVO
   --------
   Eliminar físicamente un País, solo si está “limpio” (sin Estados asociados).

   ¿CUÁNDO SE USA?
   --------------
   - Limpieza controlada de catálogo (muy raro en producción).
   - Corrección de carga histórica errónea si no tiene dependencias.

   CANDADO DE SEGURIDAD
   --------------------
   - Si existe al menos un Estado con Fk_Id_Pais = _Id_Pais, se bloquea el DELETE.
   - Esto evita:
     - Romper la jerarquía País -> Estado -> Municipio
     - Errores de integridad referencial

   VALIDACIONES
   ------------
   - El País debe existir.
   - Debe no tener hijos (Estado).
   - (Recomendado) Manejo de errores con HANDLER si luego agregas más dependencias.

   RESPUESTA
   ---------
   - Mensaje de confirmación si se eliminó.
============================================================================================ */
DELIMITER $$

-- DROP PROCEDURE IF EXISTS SP_EliminarPaisFisico$$
CREATE PROCEDURE SP_EliminarPaisFisico(
    IN _Id_Pais INT
)
BEGIN
    DECLARE EXIT HANDLER FOR 1451
    BEGIN
        ROLLBACK;
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: No se puede eliminar el País porque está referenciado por otros registros (FK).';
    END;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    /* Validación */
    IF _Id_Pais IS NULL OR _Id_Pais <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Id_Pais inválido.';
    END IF;

    IF NOT EXISTS(SELECT 1 FROM Pais WHERE Id_Pais = _Id_Pais) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: El País no existe.';
    END IF;

    /* Candado: no debe tener estados */
    IF EXISTS(SELECT 1 FROM Estado WHERE Fk_Id_Pais = _Id_Pais) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR CRÍTICO: No se puede eliminar el País porque tiene ESTADOS asociados. Elimine primero los estados.';
    END IF;

    START TRANSACTION;

    DELETE FROM Pais
    WHERE Id_Pais = _Id_Pais;

    COMMIT;

    SELECT 'País eliminado permanentemente' AS Mensaje;
END$$

DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_RegistrarEstado  (VERSIÓN PRO: 1062 => RE-RESOLVE)
   ============================================================================================
   OBJETIVO
   --------
   Registrar un nuevo Estado dentro de un País específico (seleccionado por dropdown),
   con blindaje fuerte contra duplicados y con manejo PRO de concurrencia (doble submit).

   ¿CUÁNDO SE USA?
   --------------
   - Formulario “Alta de Estado”
   - El usuario captura:
        * Codigo (ej: 'TAB')
        * Nombre (ej: 'TABASCO')
     y selecciona un País ACTIVO del dropdown:
        * _Fk_Id_Pais (Id_Pais)

   REGLAS (CONTRATO DE NEGOCIO)
   ----------------------------
   En el País _Fk_Id_Pais se aplica la MISMA regla determinística que ya estás usando:

   1) Buscar primero por CÓDIGO dentro del País (regla principal).
      - Si existe:
          a) El NOMBRE debe coincidir, si no => ERROR (conflicto Código <-> Nombre).
          b) Si Activo=0 => REACTIVAR (UPDATE Activo=1) y devolver 'REACTIVADA'.
          c) Si Activo=1 => ERROR (ya existe activo).

   2) Si no existe por CÓDIGO, buscar por NOMBRE dentro del País.
      - Si existe:
          a) El CÓDIGO debe coincidir, si no => ERROR (conflicto Nombre <-> Código).
          b) Si Activo=0 => REACTIVAR y devolver 'REACTIVADA'.
          c) Si Activo=1 => ERROR (ya existe activo).

   3) Si no existe por ninguno => INSERT y devolver 'CREADA'.

   CONCURRENCIA (EL PROBLEMA REAL)
   -------------------------------
   Caso típico:
   - Usuario A y Usuario B intentan registrar el mismo Estado (mismo Codigo o mismo Nombre)
     en el MISMO País casi al mismo tiempo.
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
      SET v_Id_Estado = NULL; ...
   antes del SELECT, para que “no encontrado” sea detectable como NULL.

   SEGURIDAD / INTEGRIDAD (TU ESQUEMA)
   -----------------------------------
   - Pais tiene Activo (dropdown debe ser solo activos).
   - Estado tiene UNIQUE compuestos:
        Uk_Estado_Codigo_Pais UNIQUE (Codigo, Fk_Id_Pais)
        Uk_Estado_Nombre_Pais UNIQUE (Nombre, Fk_Id_Pais)
   - TRANSACTION + SELECT ... FOR UPDATE:
        * Si la fila existe => la bloquea y serializa.
        * Si no existe => el candado final es el UNIQUE (y ahí entra el 1062).

   RESULTADO
   ---------
   Retorna:
     - Mensaje
     - Id_Estado
     - Id_Pais
     - Accion: 'CREADA' | 'REACTIVADA' | 'REUSADA'
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS SP_RegistrarEstado$$

CREATE PROCEDURE SP_RegistrarEstado(
    IN _Codigo      VARCHAR(50),
    IN _Nombre      VARCHAR(255),
    IN _Fk_Id_Pais   INT
)
SP: BEGIN
    /* ----------------------------------------------------------------------------------------
       VARIABLES DE TRABAJO (resultado de búsquedas)
    ---------------------------------------------------------------------------------------- */
    DECLARE v_Id_Estado INT DEFAULT NULL;
    DECLARE v_Codigo    VARCHAR(50)  DEFAULT NULL;
    DECLARE v_Nombre    VARCHAR(255) DEFAULT NULL;
    DECLARE v_Activo    TINYINT(1)   DEFAULT NULL;

    /* Variables para validar País padre con lock */
    DECLARE v_Pais_Existe INT DEFAULT NULL;
    DECLARE v_Pais_Activo TINYINT(1) DEFAULT NULL;

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
    SET _Codigo = NULLIF(TRIM(_Codigo), '');
    SET _Nombre = NULLIF(TRIM(_Nombre), '');

    /* ----------------------------------------------------------------------------------------
       VALIDACIONES BÁSICAS (rápidas, antes de tocar datos)
    ---------------------------------------------------------------------------------------- */
    IF _Fk_Id_Pais IS NULL OR _Fk_Id_Pais <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Id_Pais inválido (dropdown).';
    END IF;

    IF _Codigo IS NULL OR _Nombre IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Código y Nombre del Estado son obligatorios.';
    END IF;

    /* ========================================================================================
       TRANSACCIÓN PRINCIPAL (INTENTO NORMAL)
    ======================================================================================== */
    START TRANSACTION;

    /* ----------------------------------------------------------------------------------------
       PASO 0) BLOQUEAR Y VALIDAR PAÍS PADRE
       - Esto evita carreras raras donde:
           * alguien desactiva el País mientras tú estás registrando un Estado
       - Como tu UI lista solo activos, normalmente siempre pasa.
       - Aun así, se blinda el sistema ante requests manipuladas.
    ---------------------------------------------------------------------------------------- */
    SET v_Pais_Existe = NULL; SET v_Pais_Activo = NULL;

    SELECT 1, Activo
      INTO v_Pais_Existe, v_Pais_Activo
    FROM Pais
    WHERE Id_Pais = _Fk_Id_Pais
    LIMIT 1
    FOR UPDATE;

    IF v_Pais_Existe IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: El País no existe.';
    END IF;

    IF v_Pais_Activo <> 1 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: El País está inactivo. No puedes registrar Estados ahí.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 1) BUSCAR POR CÓDIGO DENTRO DEL PAÍS (REGLA PRINCIPAL)
       - Si existe, se bloquea la fila Estado (FOR UPDATE).
       - Si no existe, NO hay lock (y por eso 1062 puede ocurrir en el INSERT).
    ---------------------------------------------------------------------------------------- */
    SET v_Id_Estado = NULL; SET v_Codigo = NULL; SET v_Nombre = NULL; SET v_Activo = NULL;

    SELECT Id_Estado, Codigo, Nombre, Activo
      INTO v_Id_Estado, v_Codigo, v_Nombre, v_Activo
    FROM Estado
    WHERE Codigo = _Codigo
      AND Fk_Id_Pais = _Fk_Id_Pais
    LIMIT 1
    FOR UPDATE;

    IF v_Id_Estado IS NOT NULL THEN
        /* Conflicto: mismo Código pero distinto Nombre => datos inconsistentes */
        IF v_Nombre <> _Nombre THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'ERROR: Conflicto Estado. El Código ya existe pero el Nombre no coincide (en ese País).';
        END IF;

        /* Existe pero estaba inactivo => se reactiva */
        IF v_Activo = 0 THEN
            UPDATE Estado
            SET Activo = 1,
                updated_at = NOW()
            WHERE Id_Estado = v_Id_Estado;

            COMMIT;
            SELECT 'Estado reactivado exitosamente' AS Mensaje,
                   v_Id_Estado AS Id_Estado,
                   _Fk_Id_Pais AS Id_Pais,
                   'REACTIVADA' AS Accion;
            LEAVE SP;
        END IF;

        /* Existe y está activo => no se permite alta */
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Ya existe un Estado ACTIVO con ese Código en el País seleccionado.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 2) BUSCAR POR NOMBRE DENTRO DEL PAÍS (SEGUNDA REGLA)
       - Si existe por Nombre, el Código debe coincidir.
    ---------------------------------------------------------------------------------------- */
    SET v_Id_Estado = NULL; SET v_Codigo = NULL; SET v_Nombre = NULL; SET v_Activo = NULL;

    SELECT Id_Estado, Codigo, Nombre, Activo
      INTO v_Id_Estado, v_Codigo, v_Nombre, v_Activo
    FROM Estado
    WHERE Nombre = _Nombre
      AND Fk_Id_Pais = _Fk_Id_Pais
    LIMIT 1
    FOR UPDATE;

    IF v_Id_Estado IS NOT NULL THEN
        /* Conflicto: mismo Nombre pero distinto Código => datos inconsistentes */
        IF v_Codigo <> _Codigo THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'ERROR: Conflicto Estado. El Nombre ya existe pero el Código no coincide (en ese País).';
        END IF;

        IF v_Activo = 0 THEN
            UPDATE Estado
            SET Activo = 1,
                updated_at = NOW()
            WHERE Id_Estado = v_Id_Estado;

            COMMIT;
            SELECT 'Estado reactivado exitosamente' AS Mensaje,
                   v_Id_Estado AS Id_Estado,
                   _Fk_Id_Pais AS Id_Pais,
                   'REACTIVADA' AS Accion;
            LEAVE SP;
        END IF;

        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Ya existe un Estado ACTIVO con ese Nombre en el País seleccionado.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 3) INSERT FINAL
       - Aquí es donde puede aparecer el 1062 por carrera.
       - v_Dup se reinicia antes del INSERT.
    ---------------------------------------------------------------------------------------- */
    SET v_Dup = 0;

    INSERT INTO Estado (Codigo, Nombre, Fk_Id_Pais)
    VALUES (_Codigo, _Nombre, _Fk_Id_Pais);

    /* Si el INSERT NO disparó 1062, todo bien => CREADA */
    IF v_Dup = 0 THEN
        COMMIT;
        SELECT 'Estado registrado exitosamente' AS Mensaje,
               LAST_INSERT_ID() AS Id_Estado,
               _Fk_Id_Pais AS Id_Pais,
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
       RE-RESOLVE A) Localizar por CÓDIGO dentro del País (más determinístico por UNIQUE)
    ---------------------------------------------------------------------------------------- */
    SET v_Id_Estado = NULL; SET v_Codigo = NULL; SET v_Nombre = NULL; SET v_Activo = NULL;

    SELECT Id_Estado, Codigo, Nombre, Activo
      INTO v_Id_Estado, v_Codigo, v_Nombre, v_Activo
    FROM Estado
    WHERE Codigo = _Codigo
      AND Fk_Id_Pais = _Fk_Id_Pais
    LIMIT 1
    FOR UPDATE;

    IF v_Id_Estado IS NOT NULL THEN
        /* Si el “ganador” tiene otro Nombre => conflicto real (no es el mismo registro lógico) */
        IF v_Nombre <> _Nombre THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'ERROR: Concurrencia detectada pero hay conflicto: Código existe con otro Nombre (en ese País).';
        END IF;

        /* Si por alguna razón estaba inactivo => reactivar */
        IF v_Activo = 0 THEN
            UPDATE Estado
            SET Activo = 1,
                updated_at = NOW()
            WHERE Id_Estado = v_Id_Estado;

            COMMIT;
            SELECT 'Estado reactivado (re-resuelto por concurrencia)' AS Mensaje,
                   v_Id_Estado AS Id_Estado,
                   _Fk_Id_Pais AS Id_Pais,
                   'REACTIVADA' AS Accion;
            LEAVE SP;
        END IF;

        /* Ya existe activo => REUSADA (sin error al usuario) */
        COMMIT;
        SELECT 'Estado ya existía (reusado por concurrencia)' AS Mensaje,
               v_Id_Estado AS Id_Estado,
               _Fk_Id_Pais AS Id_Pais,
               'REUSADA' AS Accion;
        LEAVE SP;
    END IF;

    /* ----------------------------------------------------------------------------------------
       RE-RESOLVE B) Si no aparece por Código (raro), buscar por NOMBRE dentro del País
    ---------------------------------------------------------------------------------------- */
    SET v_Id_Estado = NULL; SET v_Codigo = NULL; SET v_Nombre = NULL; SET v_Activo = NULL;

    SELECT Id_Estado, Codigo, Nombre, Activo
      INTO v_Id_Estado, v_Codigo, v_Nombre, v_Activo
    FROM Estado
    WHERE Nombre = _Nombre
      AND Fk_Id_Pais = _Fk_Id_Pais
    LIMIT 1
    FOR UPDATE;

    IF v_Id_Estado IS NOT NULL THEN
        IF v_Codigo <> _Codigo THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'ERROR: Concurrencia detectada pero hay conflicto: Nombre existe con otro Código (en ese País).';
        END IF;

        IF v_Activo = 0 THEN
            UPDATE Estado
            SET Activo = 1,
                updated_at = NOW()
            WHERE Id_Estado = v_Id_Estado;

            COMMIT;
            SELECT 'Estado reactivado (re-resuelto por concurrencia)' AS Mensaje,
                   v_Id_Estado AS Id_Estado,
                   _Fk_Id_Pais AS Id_Pais,
                   'REACTIVADA' AS Accion;
            LEAVE SP;
        END IF;

        COMMIT;
        SELECT 'Estado ya existía (reusado por concurrencia)' AS Mensaje,
               v_Id_Estado AS Id_Estado,
               _Fk_Id_Pais AS Id_Pais,
               'REUSADA' AS Accion;
        LEAVE SP;
    END IF;

    /* Caso ultra raro: 1062 ocurrió pero no encontramos el registro */
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ERROR: Concurrencia detectada (1062) pero no se pudo localizar el Estado. Refresca y reintenta.';

END$$

DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_EditarEstado  (VERSIÓN PRO “REAL”: Lock determinístico + SIN CAMBIOS + 1062 controlado)
   ============================================================================================

   OBJETIVO
   --------
   Editar un Estado existente permitiendo:
   - Cambiar Código
   - Cambiar Nombre
   - (Opcionalmente) moverlo a otro País (Fk_Id_Pais)

   ¿CUÁNDO SE USA?
   --------------
   - Formulario “Editar Estado”
   - El usuario modifica:
       * _Nuevo_Codigo
       * _Nuevo_Nombre
     y elige en dropdown:
       * _Nuevo_Id_Pais (solo países activos listados por UI)

   REGLAS (CONTRATO DE NEGOCIO)
   ----------------------------
   1) El Estado a editar DEBE existir.
      - Se bloquea su fila con FOR UPDATE para que nadie lo edite al mismo tiempo.
   2) El País destino DEBE existir y estar Activo=1.
      - La UI normalmente solo lista activos, pero aquí lo exigimos en backend.
   3) Anti-duplicados en el País destino:
      - NO puede existir OTRO Estado en el País destino con el mismo Codigo.
        (UNIQUE compuesto típico: (Fk_Id_Pais, Codigo))
      - NO puede existir OTRO Estado en el País destino con el mismo Nombre.
        (UNIQUE compuesto típico: (Fk_Id_Pais, Nombre))
      - Se excluye el mismo Id_Estado para permitir “guardar sin cambios”.
   4) Si el usuario no cambió nada (Codigo, Nombre y País iguales) => “SIN_CAMBIOS”.
   5) Se ejecuta el UPDATE.
   6) Si por concurrencia ocurre 1062 en UPDATE => respuesta “CONFLICTO” controlada.

   ¿POR QUÉ TODAVÍA PUEDE OCURRIR 1062 SI YA HAY PRE-CHECKS?
   ---------------------------------------------------------
   Por carrera (concurrencia real):
   - Usuario A y Usuario B editan estados diferentes
   - Ambos van a poner el mismo (Codigo, País) o (Nombre, País)
   - Ambos validan “no existe duplicado” (todavía)
   - A guarda primero
   - B choca con UNIQUE => MySQL lanza error 1062

   CONCURRENCIA “PRO” EN EDITAR: 1062 => CONFLICTO (NO REUSAR)
   -----------------------------------------------------------
   En EDITAR no queremos “aprovechar” el registro ajeno.
   Queremos informar al frontend:
     - Accion = 'CONFLICTO'
     - Campo  = 'CODIGO' o 'NOMBRE'
     - Id_Conflicto = Id_Estado que ya tomó ese valor

   PRO “DE VERDAD”: LOCK DETERMINÍSTICO DE PAÍSES (ANTI-DEADLOCKS)
   --------------------------------------------------------------
   PROBLEMA:
   - Si una transacción mueve Estado X de País A -> País B
     y otra transacción mueve Estado Y de País B -> País A
     pueden terminar bloqueando países en orden diferente => deadlock.
   SOLUCIÓN:
   - Bloquear países SIEMPRE en el mismo orden:
       Pais_Low  = min(PaisActual, PaisDestino)
       Pais_High = max(PaisActual, PaisDestino)
     y se bloquean en ese orden con FOR UPDATE.

   NOTA SOBRE RESETEOS A NULL ANTES DE SELECT ... INTO
   ---------------------------------------------------
   En MySQL, si SELECT ... INTO no encuentra filas:
   - NO asigna nada y la variable conserva su valor anterior.
   Por eso, antes de cada SELECT ... INTO hacemos:
     SET v_X = NULL;
   para distinguir correctamente “no encontrado”.

   RESULTADO
   ---------
   ÉXITO:
     - Mensaje
     - Accion = 'ACTUALIZADA'
     - Id_Estado
     - Id_Pais (alias compatible)
     - Id_Pais_Anterior (extra útil)
     - Id_Pais_Nuevo (extra útil)

   SIN CAMBIOS:
     - Mensaje
     - Accion = 'SIN_CAMBIOS'
     - Id_Estado
     - Id_Pais (alias compatible)
     - Id_Pais_Anterior
     - Id_Pais_Nuevo

   CONFLICTO (1062):
     - Mensaje
     - Accion = 'CONFLICTO'
     - Campo  = 'CODIGO' | 'NOMBRE'
     - Id_Conflicto
     - Id_Estado_Que_Intentabas_Editar
     - Id_Pais_Destino (como ya tenías)
     - Id_Pais_Anterior
     - Id_Pais_Nuevo
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS SP_EditarEstado$$

CREATE PROCEDURE SP_EditarEstado(
    IN _Id_Estado INT,
    IN _Nuevo_Codigo VARCHAR(50),
    IN _Nuevo_Nombre VARCHAR(255),
    IN _Nuevo_Id_Pais INT
)
SP: BEGIN
    /* ========================================================================================
       PARTE 0) VARIABLES
       ======================================================================================== */

    /* Datos actuales (para poder detectar “SIN CAMBIOS”) */
    DECLARE v_Codigo_Actual VARCHAR(50)  DEFAULT NULL;
    DECLARE v_Nombre_Actual VARCHAR(255) DEFAULT NULL;
    DECLARE v_Id_Pais_Actual INT         DEFAULT NULL;

    /* Auxiliares de validación / duplicidad */
    DECLARE v_Existe INT DEFAULT NULL;
    DECLARE v_DupId INT DEFAULT NULL;

    /* Bandera de choque 1062 en UPDATE */
    DECLARE v_Dup TINYINT(1) DEFAULT 0;

    /* Datos para respuesta de conflicto controlado */
    DECLARE v_Id_Conflicto INT DEFAULT NULL;
    DECLARE v_Campo_Conflicto VARCHAR(20) DEFAULT NULL;

    /* Para lock determinístico de países */
    DECLARE v_Pais_Low INT DEFAULT NULL;
    DECLARE v_Pais_High INT DEFAULT NULL;

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
    SET _Nuevo_Codigo = NULLIF(TRIM(_Nuevo_Codigo), '');
    SET _Nuevo_Nombre = NULLIF(TRIM(_Nuevo_Nombre), '');

    /* ========================================================================================
       PARTE 3) VALIDACIONES BÁSICAS
       ======================================================================================== */
    IF _Id_Estado IS NULL OR _Id_Estado <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Id_Estado inválido.';
    END IF;

    IF _Nuevo_Id_Pais IS NULL OR _Nuevo_Id_Pais <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Id_Pais destino inválido.';
    END IF;

    IF _Nuevo_Codigo IS NULL OR _Nuevo_Nombre IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Código y Nombre del Estado son obligatorios.';
    END IF;

    /* ========================================================================================
       PARTE 4) TRANSACCIÓN PRINCIPAL
       ======================================================================================== */
    START TRANSACTION;

    /* ----------------------------------------------------------------------------------------
       PASO 1) Bloquear el Estado a editar y leer sus valores actuales
       ----------------------------------------------------------------------------------------
       - FOR UPDATE bloquea la fila del Estado => nadie lo edita en paralelo.
       - De aquí sacamos:
           * v_Codigo_Actual
           * v_Nombre_Actual
           * v_Id_Pais_Actual  (para lock determinístico entre País actual y País destino)
    ---------------------------------------------------------------------------------------- */
    SET v_Codigo_Actual = NULL;
    SET v_Nombre_Actual = NULL;
    SET v_Id_Pais_Actual = NULL;

    SELECT
        E.Codigo,
        E.Nombre,
        E.Fk_Id_Pais
    INTO
        v_Codigo_Actual,
        v_Nombre_Actual,
        v_Id_Pais_Actual
    FROM Estado E
    WHERE E.Id_Estado = _Id_Estado
    LIMIT 1
    FOR UPDATE;

    IF v_Id_Pais_Actual IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: El Estado no existe.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 2) LOCK DETERMINÍSTICO DE PAÍSES (anti-deadlocks)
       ----------------------------------------------------------------------------------------
       - Vamos a bloquear SIEMPRE los países en el mismo orden:
           Pais_Low  = min(PaisActual, PaisDestino)
           Pais_High = max(PaisActual, PaisDestino)
       - Esto evita deadlocks cuando hay movimientos cruzados A<->B en paralelo.
    ---------------------------------------------------------------------------------------- */
    IF v_Id_Pais_Actual = _Nuevo_Id_Pais THEN
        SET v_Pais_Low  = v_Id_Pais_Actual;
        SET v_Pais_High = v_Id_Pais_Actual;
    ELSE
        SET v_Pais_Low  = LEAST(v_Id_Pais_Actual, _Nuevo_Id_Pais);
        SET v_Pais_High = GREATEST(v_Id_Pais_Actual, _Nuevo_Id_Pais);
    END IF;

    /* 2.1) Bloquear País LOW (debe existir) */
    SET v_Existe = NULL;

    SELECT 1
      INTO v_Existe
    FROM Pais
    WHERE Id_Pais = v_Pais_Low
    LIMIT 1
    FOR UPDATE;

    IF v_Existe IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Inconsistencia: País (low) no existe.';
    END IF;

    /* 2.2) Bloquear País HIGH (si es distinto) */
    IF v_Pais_High <> v_Pais_Low THEN
        SET v_Existe = NULL;

        SELECT 1
          INTO v_Existe
        FROM Pais
        WHERE Id_Pais = v_Pais_High
        LIMIT 1
        FOR UPDATE;

        IF v_Existe IS NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Inconsistencia: País (high) no existe.';
        END IF;
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 3) Validar País destino ACTIVO (contrato con UI)
       ----------------------------------------------------------------------------------------
       - La UI normalmente lista solo países activos.
       - Aquí lo exigimos para impedir:
           * “guardar” hacia un país que se desactivó mientras el usuario editaba.
       - FOR UPDATE aquí es redundante porque ya bloqueamos el país en PASO 2,
         pero lo dejamos por claridad del “contrato”.
    ---------------------------------------------------------------------------------------- */
    SET v_Existe = NULL;

    SELECT 1
      INTO v_Existe
    FROM Pais
    WHERE Id_Pais = _Nuevo_Id_Pais
      AND Activo = 1
    LIMIT 1
    FOR UPDATE;

    IF v_Existe IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: El País destino no existe o está inactivo.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 4) SIN CAMBIOS (salida temprana)
       ----------------------------------------------------------------------------------------
       - Si no cambió:
           * Código
           * Nombre
           * País
         devolvemos “SIN_CAMBIOS”.
       - COMMIT inmediato => libera locks rápido (mejor concurrencia).
    ---------------------------------------------------------------------------------------- */
    IF v_Codigo_Actual = _Nuevo_Codigo
       AND v_Nombre_Actual = _Nuevo_Nombre
       AND v_Id_Pais_Actual = _Nuevo_Id_Pais THEN

        COMMIT;

        SELECT 'Sin cambios: El Estado ya tiene esos datos y ya pertenece a ese País.' AS Mensaje,
               'SIN_CAMBIOS' AS Accion,
               _Id_Estado AS Id_Estado,
               _Nuevo_Id_Pais AS Id_Pais,           -- alias compatible (como tu SP actual)
               v_Id_Pais_Actual AS Id_Pais_Anterior,
               _Nuevo_Id_Pais AS Id_Pais_Nuevo;
        LEAVE SP;
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 5) Pre-check duplicidad por CÓDIGO en el País destino (excluyendo el mismo Id)
       ----------------------------------------------------------------------------------------
       - Reglas:
         * Dentro del mismo País destino, el Código debe ser único.
         * Excluimos el mismo Id_Estado para permitir actualización del propio registro.
       - ORDER BY Id_Estado:
         * lock determinístico (si hubiera datos sucios o escenarios raros).
       - FOR UPDATE:
         * si encuentra duplicado, bloquea esa fila durante tu TX.
    ---------------------------------------------------------------------------------------- */
    SET v_DupId = NULL;

    SELECT Id_Estado
      INTO v_DupId
    FROM Estado
    WHERE Fk_Id_Pais = _Nuevo_Id_Pais
      AND Codigo = _Nuevo_Codigo
      AND Id_Estado <> _Id_Estado
    ORDER BY Id_Estado
    LIMIT 1
    FOR UPDATE;

    IF v_DupId IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Ya existe OTRO Estado con ese CÓDIGO en el País destino.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 6) Pre-check duplicidad por NOMBRE en el País destino (excluyendo el mismo Id)
    ---------------------------------------------------------------------------------------- */
    SET v_DupId = NULL;

    SELECT Id_Estado
      INTO v_DupId
    FROM Estado
    WHERE Fk_Id_Pais = _Nuevo_Id_Pais
      AND Nombre = _Nuevo_Nombre
      AND Id_Estado <> _Id_Estado
    ORDER BY Id_Estado
    LIMIT 1
    FOR UPDATE;

    IF v_DupId IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Ya existe OTRO Estado con ese NOMBRE en el País destino.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 7) UPDATE FINAL (aquí puede aparecer 1062 por carrera)
       ----------------------------------------------------------------------------------------
       - Reseteamos v_Dup=0 antes del UPDATE para detectar si el handler se disparó aquí.
    ---------------------------------------------------------------------------------------- */
    SET v_Dup = 0;

    UPDATE Estado
    SET Codigo = _Nuevo_Codigo,
        Nombre = _Nuevo_Nombre,
        Fk_Id_Pais = _Nuevo_Id_Pais,
        updated_at = NOW()
    WHERE Id_Estado = _Id_Estado;

    /* ----------------------------------------------------------------------------------------
       PASO 8) Si hubo 1062 => CONFLICTO CONTROLADO
       ----------------------------------------------------------------------------------------
       - ROLLBACK: no guardamos nada.
       - Buscamos el Id_Estado que “ganó” el valor en el País destino:
           * primero por CODIGO
           * si no, por NOMBRE
       - Devolvemos respuesta clara para UI.
    ---------------------------------------------------------------------------------------- */
    IF v_Dup = 1 THEN
        ROLLBACK;

        SET v_Id_Conflicto = NULL;
        SET v_Campo_Conflicto = NULL;

        /* 8.1) Conflicto por CODIGO */
        SELECT Id_Estado
          INTO v_Id_Conflicto
        FROM Estado
        WHERE Fk_Id_Pais = _Nuevo_Id_Pais
          AND Codigo = _Nuevo_Codigo
          AND Id_Estado <> _Id_Estado
        ORDER BY Id_Estado
        LIMIT 1;

        IF v_Id_Conflicto IS NOT NULL THEN
            SET v_Campo_Conflicto = 'CODIGO';
        ELSE
            /* 8.2) Conflicto por NOMBRE */
            SELECT Id_Estado
              INTO v_Id_Conflicto
            FROM Estado
            WHERE Fk_Id_Pais = _Nuevo_Id_Pais
              AND Nombre = _Nuevo_Nombre
              AND Id_Estado <> _Id_Estado
            ORDER BY Id_Estado
            LIMIT 1;

            IF v_Id_Conflicto IS NOT NULL THEN
                SET v_Campo_Conflicto = 'NOMBRE';
            END IF;
        END IF;

        SELECT 'No se guardó: otro usuario se adelantó. Refresca y vuelve a intentar.' AS Mensaje,
               'CONFLICTO' AS Accion,
               v_Campo_Conflicto AS Campo,
               v_Id_Conflicto AS Id_Conflicto,
               _Id_Estado AS Id_Estado_Que_Intentabas_Editar,
               _Nuevo_Id_Pais AS Id_Pais_Destino,
               v_Id_Pais_Actual AS Id_Pais_Anterior,
               _Nuevo_Id_Pais AS Id_Pais_Nuevo;
        LEAVE SP;
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 9) ÉXITO
    ---------------------------------------------------------------------------------------- */
    COMMIT;

    SELECT 'Estado actualizado correctamente' AS Mensaje,
           'ACTUALIZADA' AS Accion,
           _Id_Estado AS Id_Estado,
           _Nuevo_Id_Pais AS Id_Pais,           -- alias compatible (como tu SP actual)
           v_Id_Pais_Actual AS Id_Pais_Anterior,
           _Nuevo_Id_Pais AS Id_Pais_Nuevo;

END$$

DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_CambiarEstatusEstado
   ============================================================================================
   OBJETIVO
   --------
   Activar/Desactivar (borrado lógico) un Estado:
      Estado.Activo (1 = activo, 0 = inactivo)

   REGLAS CRÍTICAS (INTEGRIDAD JERÁRQUICA)
   --------------------------------------
   A) Al DESACTIVAR un Estado (Activo=0):
      - NO se permite si tiene MUNICIPIOS ACTIVOS.
        Evita: Estado=0 con Municipio=1.

   B) Al ACTIVAR un Estado (Activo=1)  <<<<<<<<<<<< CANDADO JERÁRQUICO (C)
      - NO se permite si su PAÍS PADRE está INACTIVO.
        Evita: País=0 con Estado=1 (inconsistencia lógica y UX).

   CONCURRENCIA / BLOQUEOS
   -----------------------
   - Bloqueamos en orden jerárquico: PAÍS -> ESTADO
   - Usamos STRAIGHT_JOIN + FOR UPDATE para:
       * asegurar el orden de lectura/bloqueo
       * evitar carreras donde el País cambie mientras activas el Estado
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS SP_CambiarEstatusEstado$$

CREATE PROCEDURE SP_CambiarEstatusEstado(
    IN _Id_Estado INT,
    IN _Nuevo_Estatus TINYINT -- 1 = Activo, 0 = Inactivo
)
BEGIN
    /* ----------------------------------------------------------------------------------------
       VARIABLES
    ---------------------------------------------------------------------------------------- */
    DECLARE v_Existe INT DEFAULT NULL;

    /* Estatus actual del Estado */
    DECLARE v_Activo_Actual TINYINT(1) DEFAULT NULL;

    /* Datos del padre (País) para el candado jerárquico al ACTIVAR */
    DECLARE v_Id_Pais INT DEFAULT NULL;
    DECLARE v_Pais_Activo TINYINT(1) DEFAULT NULL;

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
    IF _Id_Estado IS NULL OR _Id_Estado <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Id_Estado inválido.';
    END IF;

    IF _Nuevo_Estatus NOT IN (0,1) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Estatus inválido (solo 0 o 1).';
    END IF;

    START TRANSACTION;

    /* ----------------------------------------------------------------------------------------
       1) VALIDAR EXISTENCIA Y BLOQUEAR FILAS EN ORDEN JERÁRQUICO (PAÍS -> ESTADO)
       ----------------------------------------------------------------------------------------
       ¿POR QUÉ ASÍ?
       - Antes solo bloqueabas Estado.
       - Para el CANDADO (C) necesitamos consultar País.Activo.
       - Si solo lo "lees" sin bloquear, otro proceso podría apagar el País al mismo tiempo.
       - Con este SELECT ... FOR UPDATE, bloqueas BOTH: País y Estado (en orden).
    ---------------------------------------------------------------------------------------- */
    SELECT
        1 AS Existe,
        E.Activo AS Activo_Estado,
        E.Fk_Id_Pais AS Id_Pais,
        P.Activo AS Activo_Pais
    INTO
        v_Existe,
        v_Activo_Actual,
        v_Id_Pais,
        v_Pais_Activo
    FROM Pais P
    STRAIGHT_JOIN Estado E ON E.Fk_Id_Pais = P.Id_Pais
    WHERE E.Id_Estado = _Id_Estado
    LIMIT 1
    FOR UPDATE;

    IF v_Existe IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: El Estado no existe.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       2) "SIN CAMBIOS" (IDEMPOTENCIA)
       - Si ya está en ese estado, no hacemos nada.
    ---------------------------------------------------------------------------------------- */
    IF v_Activo_Actual = _Nuevo_Estatus THEN
        COMMIT;
        SELECT CASE
            WHEN _Nuevo_Estatus = 1 THEN 'Sin cambios: El Estado ya estaba Activo.'
            ELSE 'Sin cambios: El Estado ya estaba Inactivo.'
        END AS Mensaje,
        v_Activo_Actual AS Activo_Anterior,
        _Nuevo_Estatus AS Activo_Nuevo;
    ELSE

        /* ------------------------------------------------------------------------------------
           3) CANDADO JERÁRQUICO AL ACTIVAR (C)  <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
           ------------------------------------------------------------------------------------
           REGLA:
           - Si quieres ACTIVAR Estado (Nuevo_Estatus=1),
             su País padre DEBE estar ACTIVO.
           - Si el País está inactivo, bloquear con mensaje claro.
        ------------------------------------------------------------------------------------ */
        IF _Nuevo_Estatus = 1 THEN
            IF v_Pais_Activo = 0 THEN
                SIGNAL SQLSTATE '45000'
                    SET MESSAGE_TEXT = 'BLOQUEADO: No se puede ACTIVAR el Estado porque su PAÍS está INACTIVO. Activa primero el País.';
            END IF;
        END IF;

        /* ------------------------------------------------------------------------------------
           4) SI INTENTA DESACTIVAR: BLOQUEAR SI HAY MUNICIPIOS ACTIVOS (regla original)
        ------------------------------------------------------------------------------------ */
        IF _Nuevo_Estatus = 0 THEN
            SET v_Tmp = NULL;
            SELECT Id_Municipio
              INTO v_Tmp
            FROM Municipio
            WHERE Fk_Id_Estado = _Id_Estado
              AND Activo = 1
            LIMIT 1;

            IF v_Tmp IS NOT NULL THEN
                SIGNAL SQLSTATE '45000'
                    SET MESSAGE_TEXT = 'BLOQUEADO: No se puede desactivar el Estado porque tiene MUNICIPIOS ACTIVOS. Desactiva primero los Municipios.';
            END IF;
        END IF;

        /* ------------------------------------------------------------------------------------
           5) APLICAR CAMBIO DE ESTATUS
        ------------------------------------------------------------------------------------ */
        UPDATE Estado
        SET Activo = _Nuevo_Estatus,
            updated_at = NOW()
        WHERE Id_Estado = _Id_Estado;

        COMMIT;

        /* ------------------------------------------------------------------------------------
           6) RESPUESTA PARA FRONTEND
        ------------------------------------------------------------------------------------ */
        SELECT CASE
            WHEN _Nuevo_Estatus = 1 THEN 'Estado Reactivado'
            ELSE 'Estado Desactivado'
        END AS Mensaje,
        v_Activo_Actual AS Activo_Anterior,
        _Nuevo_Estatus AS Activo_Nuevo;
    END IF;

END$$

DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_EliminarEstadoFisico
   ============================================================================================
   OBJETIVO
   --------
   Eliminar físicamente un Estado, solo si NO tiene Municipios asociados.

   ¿CUÁNDO SE USA?
   --------------
   - Limpieza controlada (muy raro en producción).
   - Correcciones cuando el Estado fue creado por error y aún no tiene hijos.

   CANDADO DE SEGURIDAD
   --------------------
   - Si existe al menos un Municipio con Fk_Id_Estado = _Id_Estado, se bloquea el DELETE.
   - Evita romper la integridad del catálogo.

   VALIDACIONES
   ------------
   - Estado debe existir.
   - No debe tener Municipios asociados.

   RESPUESTA
   ---------
   - Mensaje de confirmación si se elimina.
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS SP_EliminarEstadoFisico$$

CREATE PROCEDURE SP_EliminarEstadoFisico(
    IN _Id_Estado INT
)
BEGIN
    DECLARE EXIT HANDLER FOR 1451
    BEGIN
        ROLLBACK;
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: No se puede eliminar el Estado porque está referenciado por otros registros (FK).';
    END;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    /* Validación */
    IF _Id_Estado IS NULL OR _Id_Estado <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Id_Estado inválido.';
    END IF;

    IF NOT EXISTS(SELECT 1 FROM Estado WHERE Id_Estado = _Id_Estado) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: El Estado no existe.';
    END IF;

    /* Candado: no debe tener municipios */
    IF EXISTS(SELECT 1 FROM Municipio WHERE Fk_Id_Estado = _Id_Estado) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR CRÍTICO: No se puede eliminar el Estado porque tiene MUNICIPIOS asociados.';
    END IF;

    START TRANSACTION;

    DELETE FROM Estado
    WHERE Id_Estado = _Id_Estado;

    COMMIT;

    SELECT 'Estado eliminado permanentemente' AS Mensaje;
END$$

DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_RegistrarMunicipio  (VERSIÓN PRO: 1062 => RE-RESOLVE)
   ============================================================================================
   OBJETIVO
   --------
   Registrar un nuevo Municipio dentro de un Estado específico (seleccionado por dropdown),
   con blindaje fuerte contra duplicados y con manejo PRO de concurrencia (doble-submit).

   ¿CUÁNDO SE USA?
   --------------
   - Formulario “Alta de Municipio”
   - El usuario captura:
        * _Codigo  (ej: '001')
        * _Nombre  (ej: 'CENTRO')
     y selecciona por dropdown:
        * _Id_Pais_Seleccionado  (solo países ACTIVO=1, usado para filtrar estados)
        * _Id_Estado             (solo estados ACTIVO=1 que pertenecen a ese país)

   REGLAS (CONTRATO DE NEGOCIO)
   ----------------------------
   Dentro del Estado _Id_Estado se aplica la misma regla determinística:

   1) Buscar primero por CÓDIGO dentro del Estado (regla principal).
      - Si existe:
          a) El NOMBRE debe coincidir, si no => ERROR (conflicto Código <-> Nombre).
          b) Si Activo=0 => REACTIVAR (UPDATE Activo=1) y devolver 'REACTIVADA'.
          c) Si Activo=1 => ERROR (ya existe activo).

   2) Si no existe por CÓDIGO, buscar por NOMBRE dentro del Estado.
      - Si existe:
          a) El CÓDIGO debe coincidir, si no => ERROR (conflicto Nombre <-> Código).
          b) Si Activo=0 => REACTIVAR y devolver 'REACTIVADA'.
          c) Si Activo=1 => ERROR (ya existe activo).

   3) Si no existe por ninguno => INSERT y devolver 'CREADA'.

   VALIDACIÓN JERÁRQUICA (PAÍS -> ESTADO)
   --------------------------------------
   Aunque el frontend use dropdowns (y “debería” mandar combos válidos), este SP valida:
   - El País existe y está ACTIVO
   - El Estado existe, está ACTIVO y pertenece a ese País
   Esto blinda el backend ante:
   - Requests manipuladas
   - Bugs del frontend
   - Datos “viejos” en cache del navegador (usuario deja la pantalla abierta y cambia catálogo)

   CONCURRENCIA (EL PROBLEMA REAL)
   -------------------------------
   - SELECT ... FOR UPDATE solo bloquea si la fila existe.
   - Si el municipio no existe todavía:
       * Dos usuarios pueden pasar los SELECT sin bloquear nada
       * Ambos intentan INSERT
       * Uno gana, el otro cae en 1062 (por UNIQUE)
   Tu tabla Municipio tiene UNIQUE:
     - Uk_Municipio_Codigo_Estado UNIQUE (Codigo, Fk_Id_Estado)
     - Uk_Municipio_Estado        UNIQUE (Nombre, Fk_Id_Estado)

   SOLUCIÓN PRO: 1062 => “RE-RESOLVE”
   ---------------------------------
   En vez de mostrar error al segundo:
   - Detectamos 1062 (handler)
   - ROLLBACK del intento
   - Nueva transacción
   - Localizamos el registro “ganador”
   - Devolvemos:
        Accion='REUSADA' (ya existía activa)
     o Accion='REACTIVADA' (si estaba inactivo)

   IMPORTANTE: ¿POR QUÉ SE RESETEAN VARIABLES A NULL ANTES DE CADA SELECT INTO?
   ----------------------------------------------------------------------------
   En MySQL, si un SELECT ... INTO no encuentra filas:
   - NO asigna nada (variables conservan valor anterior).
   Por eso hacemos:
      SET v_Id_Municipio = NULL; ...
   antes del SELECT, para que “no encontrado” quede en NULL de forma confiable.

   RESULTADO
   ---------
   Retorna:
     - Mensaje
     - Id_Municipio
     - Id_Estado
     - Id_Pais
     - Accion: 'CREADA' | 'REACTIVADA' | 'REUSADA'
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS SP_RegistrarMunicipio$$
CREATE PROCEDURE SP_RegistrarMunicipio(
    IN _Codigo VARCHAR(50),
    IN _Nombre VARCHAR(255),
    IN _Id_Pais_Seleccionado INT,
    IN _Id_Estado INT
)
SP: BEGIN
    /* ----------------------------------------------------------------------------------------
       VARIABLES DE TRABAJO (resultado de búsquedas)
    ---------------------------------------------------------------------------------------- */
    DECLARE v_Id_Municipio INT DEFAULT NULL;
    DECLARE v_Codigo       VARCHAR(50)  DEFAULT NULL;
    DECLARE v_Nombre       VARCHAR(255) DEFAULT NULL;
    DECLARE v_Activo       TINYINT(1)   DEFAULT NULL;

    /* Variables para validar y BLOQUEAR jerarquía padre (País y Estado) */
    DECLARE v_Pais_Existe  INT DEFAULT NULL;
    DECLARE v_Pais_Activo  TINYINT(1) DEFAULT NULL;

    DECLARE v_Estado_Existe INT DEFAULT NULL;
    DECLARE v_Estado_Activo TINYINT(1) DEFAULT NULL;
    DECLARE v_Estado_Pais   INT DEFAULT NULL;

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
       - TRIM evita "CENTRO " vs "CENTRO"
       - NULLIF convierte '' a NULL para detectar vacíos
    ---------------------------------------------------------------------------------------- */
    SET _Codigo = NULLIF(TRIM(_Codigo), '');
    SET _Nombre = NULLIF(TRIM(_Nombre), '');

    /* ----------------------------------------------------------------------------------------
       VALIDACIONES BÁSICAS (rápidas, antes de tocar datos)
    ---------------------------------------------------------------------------------------- */
    IF _Codigo IS NULL OR _Nombre IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Código y Nombre del Municipio son obligatorios.';
    END IF;

    IF _Id_Pais_Seleccionado IS NULL OR _Id_Pais_Seleccionado <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Id_Pais seleccionado inválido (dropdown).';
    END IF;

    IF _Id_Estado IS NULL OR _Id_Estado <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Id_Estado inválido (dropdown).';
    END IF;

    /* ========================================================================================
       TRANSACCIÓN PRINCIPAL (INTENTO NORMAL)
    ======================================================================================== */
    START TRANSACTION;

    /* ----------------------------------------------------------------------------------------
       PASO 0) BLOQUEAR Y VALIDAR PAÍS PADRE
       - Aunque el dropdown mande solo activos, blindamos backend.
       - FOR UPDATE aquí evita carreras raras con cambios de estatus del País.
    ---------------------------------------------------------------------------------------- */
    SET v_Pais_Existe = NULL; SET v_Pais_Activo = NULL;

    SELECT 1, Activo
      INTO v_Pais_Existe, v_Pais_Activo
    FROM Pais
    WHERE Id_Pais = _Id_Pais_Seleccionado
    LIMIT 1
    FOR UPDATE;

    IF v_Pais_Existe IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: El País no existe.';
    END IF;

    IF v_Pais_Activo <> 1 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: El País está inactivo. No puedes registrar Municipios ahí.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 1) BLOQUEAR Y VALIDAR ESTADO DESTINO + PERTENENCIA AL PAÍS
       - Este es el blindaje “País -> Estado”:
           * Estado debe existir
           * Estado debe estar activo
           * Estado debe pertenecer al País seleccionado
    ---------------------------------------------------------------------------------------- */
    SET v_Estado_Existe = NULL; SET v_Estado_Activo = NULL; SET v_Estado_Pais = NULL;

    SELECT 1, Activo, Fk_Id_Pais
      INTO v_Estado_Existe, v_Estado_Activo, v_Estado_Pais
    FROM Estado
    WHERE Id_Estado = _Id_Estado
    LIMIT 1
    FOR UPDATE;

    IF v_Estado_Existe IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: El Estado no existe.';
    END IF;

    IF v_Estado_Pais <> _Id_Pais_Seleccionado THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: El Estado no pertenece al País seleccionado.';
    END IF;

    IF v_Estado_Activo <> 1 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: El Estado está inactivo. No puedes registrar Municipios ahí.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 2) BUSCAR POR CÓDIGO DENTRO DEL ESTADO (REGLA PRINCIPAL)
       - Si existe fila => FOR UPDATE la bloquea.
       - Si no existe => no hay lock; el candado final será el UNIQUE del INSERT.
    ---------------------------------------------------------------------------------------- */
    SET v_Id_Municipio = NULL; SET v_Codigo = NULL; SET v_Nombre = NULL; SET v_Activo = NULL;

    SELECT Id_Municipio, Codigo, Nombre, Activo
      INTO v_Id_Municipio, v_Codigo, v_Nombre, v_Activo
    FROM Municipio
    WHERE Codigo = _Codigo
      AND Fk_Id_Estado = _Id_Estado
    LIMIT 1
    FOR UPDATE;

    IF v_Id_Municipio IS NOT NULL THEN
        /* Conflicto: mismo Código pero distinto Nombre */
        IF v_Nombre <> _Nombre THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'ERROR: Conflicto Municipio. El Código ya existe pero el Nombre no coincide (en ese Estado).';
        END IF;

        /* Existe pero estaba inactivo => reactivar */
        IF v_Activo = 0 THEN
            UPDATE Municipio
            SET Activo = 1,
                updated_at = NOW()
            WHERE Id_Municipio = v_Id_Municipio;

            COMMIT;
            SELECT 'Municipio reactivado exitosamente' AS Mensaje,
                   v_Id_Municipio AS Id_Municipio,
                   _Id_Estado AS Id_Estado,
                   _Id_Pais_Seleccionado AS Id_Pais,
                   'REACTIVADA' AS Accion;
            LEAVE SP;
        END IF;

        /* Existe y está activo => alta bloqueada */
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Ya existe un Municipio ACTIVO con ese Código en el Estado seleccionado.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 3) BUSCAR POR NOMBRE DENTRO DEL ESTADO (SEGUNDA REGLA)
    ---------------------------------------------------------------------------------------- */
    SET v_Id_Municipio = NULL; SET v_Codigo = NULL; SET v_Nombre = NULL; SET v_Activo = NULL;

    SELECT Id_Municipio, Codigo, Nombre, Activo
      INTO v_Id_Municipio, v_Codigo, v_Nombre, v_Activo
    FROM Municipio
    WHERE Nombre = _Nombre
      AND Fk_Id_Estado = _Id_Estado
    LIMIT 1
    FOR UPDATE;

    IF v_Id_Municipio IS NOT NULL THEN
        /* Conflicto: mismo Nombre pero distinto Código */
        IF v_Codigo <> _Codigo THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'ERROR: Conflicto Municipio. El Nombre ya existe pero el Código no coincide (en ese Estado).';
        END IF;

        IF v_Activo = 0 THEN
            UPDATE Municipio
            SET Activo = 1,
                updated_at = NOW()
            WHERE Id_Municipio = v_Id_Municipio;

            COMMIT;
            SELECT 'Municipio reactivado exitosamente' AS Mensaje,
                   v_Id_Municipio AS Id_Municipio,
                   _Id_Estado AS Id_Estado,
                   _Id_Pais_Seleccionado AS Id_Pais,
                   'REACTIVADA' AS Accion;
            LEAVE SP;
        END IF;

        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Ya existe un Municipio ACTIVO con ese Nombre en el Estado seleccionado.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 4) INSERT FINAL
       - Aquí puede aparecer el 1062 por carrera (dos usuarios insertando al mismo tiempo).
       - Reiniciamos v_Dup antes del INSERT.
    ---------------------------------------------------------------------------------------- */
    SET v_Dup = 0;

    INSERT INTO Municipio (Codigo, Nombre, Fk_Id_Estado)
    VALUES (_Codigo, _Nombre, _Id_Estado);

    /* Si el INSERT NO disparó 1062 => CREADA */
    IF v_Dup = 0 THEN
        COMMIT;
        SELECT 'Municipio registrado exitosamente' AS Mensaje,
               LAST_INSERT_ID() AS Id_Municipio,
               _Id_Estado AS Id_Estado,
               _Id_Pais_Seleccionado AS Id_Pais,
               'CREADA' AS Accion;
        LEAVE SP;
    END IF;

    /* ========================================================================================
       SI LLEGAMOS AQUÍ: HUBO 1062 EN EL INSERT
       => ALGUIEN INSERTÓ PRIMERO (CONCURRENCIA)
       => RE-RESOLVE: localizar y devolver REUSADA/REACTIVADA (UX limpia)
    ======================================================================================== */
    ROLLBACK;

    /* Nueva transacción:
       - evitar quedarnos con locks del intento fallido
       - bloquear la fila real con FOR UPDATE si hay que reactivar */
    START TRANSACTION;

    /* ----------------------------------------------------------------------------------------
       RE-RESOLVE A) Localizar por CÓDIGO dentro del Estado (más determinístico por UNIQUE)
    ---------------------------------------------------------------------------------------- */
    SET v_Id_Municipio = NULL; SET v_Codigo = NULL; SET v_Nombre = NULL; SET v_Activo = NULL;

    SELECT Id_Municipio, Codigo, Nombre, Activo
      INTO v_Id_Municipio, v_Codigo, v_Nombre, v_Activo
    FROM Municipio
    WHERE Codigo = _Codigo
      AND Fk_Id_Estado = _Id_Estado
    LIMIT 1
    FOR UPDATE;

    IF v_Id_Municipio IS NOT NULL THEN
        IF v_Nombre <> _Nombre THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'ERROR: Concurrencia detectada pero hay conflicto: Código existe con otro Nombre (en ese Estado).';
        END IF;

        IF v_Activo = 0 THEN
            UPDATE Municipio
            SET Activo = 1,
                updated_at = NOW()
            WHERE Id_Municipio = v_Id_Municipio;

            COMMIT;
            SELECT 'Municipio reactivado (re-resuelto por concurrencia)' AS Mensaje,
                   v_Id_Municipio AS Id_Municipio,
                   _Id_Estado AS Id_Estado,
                   _Id_Pais_Seleccionado AS Id_Pais,
                   'REACTIVADA' AS Accion;
            LEAVE SP;
        END IF;

        COMMIT;
        SELECT 'Municipio ya existía (reusado por concurrencia)' AS Mensaje,
               v_Id_Municipio AS Id_Municipio,
               _Id_Estado AS Id_Estado,
               _Id_Pais_Seleccionado AS Id_Pais,
               'REUSADA' AS Accion;
        LEAVE SP;
    END IF;

    /* ----------------------------------------------------------------------------------------
       RE-RESOLVE B) Si no aparece por Código (raro), buscar por NOMBRE dentro del Estado
    ---------------------------------------------------------------------------------------- */
    SET v_Id_Municipio = NULL; SET v_Codigo = NULL; SET v_Nombre = NULL; SET v_Activo = NULL;

    SELECT Id_Municipio, Codigo, Nombre, Activo
      INTO v_Id_Municipio, v_Codigo, v_Nombre, v_Activo
    FROM Municipio
    WHERE Nombre = _Nombre
      AND Fk_Id_Estado = _Id_Estado
    LIMIT 1
    FOR UPDATE;

    IF v_Id_Municipio IS NOT NULL THEN
        IF v_Codigo <> _Codigo THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'ERROR: Concurrencia detectada pero hay conflicto: Nombre existe con otro Código (en ese Estado).';
        END IF;

        IF v_Activo = 0 THEN
            UPDATE Municipio
            SET Activo = 1,
                updated_at = NOW()
            WHERE Id_Municipio = v_Id_Municipio;

            COMMIT;
            SELECT 'Municipio reactivado (re-resuelto por concurrencia)' AS Mensaje,
                   v_Id_Municipio AS Id_Municipio,
                   _Id_Estado AS Id_Estado,
                   _Id_Pais_Seleccionado AS Id_Pais,
                   'REACTIVADA' AS Accion;
            LEAVE SP;
        END IF;

        COMMIT;
        SELECT 'Municipio ya existía (reusado por concurrencia)' AS Mensaje,
               v_Id_Municipio AS Id_Municipio,
               _Id_Estado AS Id_Estado,
               _Id_Pais_Seleccionado AS Id_Pais,
               'REUSADA' AS Accion;
        LEAVE SP;
    END IF;

    /* Caso ultra raro: 1062 ocurrió pero no encontramos la fila */
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ERROR: Concurrencia detectada (1062) pero no se pudo localizar el Municipio. Refresca y reintenta.';

END$$

DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_EditarMunicipio  (VERSIÓN PRO “REAL”: Locks determinísticos + JOIN atómico + SIN CAMBIOS + 1062)
   ============================================================================================

   CONTEXTO DE UI (CÓMO FUNCIONA TU FORMULARIO)
   --------------------------------------------
   1) El frontend precarga el registro con SP_ConsultarMunicipioEspecifico:
      - Código, Nombre, timestamps
      - País actual (derivado: Municipio -> Estado -> País)
      - Estado actual

   2) El usuario puede:
      - Cambiar Código y/o Nombre
      - Cambiar Estado destino (dentro del País actual)
      - O cambiar País (dropdown) => recarga Estados del País => elegir nuevo Estado destino

   IMPORTANTE (DISEÑO DE DATOS)
   ----------------------------
   - Municipio NO tiene Fk_Id_Pais.
   - El “País” de un Municipio se determina por el Estado:
         Municipio.Fk_Id_Estado -> Estado.Fk_Id_Pais
   - Entonces “cambiar País” realmente significa:
         elegir un Estado destino que pertenezca al País elegido.

   ¿POR QUÉ ESTE SP RECIBE _Id_Pais_Seleccionado SI YA RECIBE _Id_Estado_Destino?
   ------------------------------------------------------------------------------
   - Porque tu UI trabaja en cascada País -> Estado.
   - En teoría el Estado elegido SIEMPRE pertenece a ese País.
   - PERO en backend se valida para blindar contra:
       * requests manipuladas
       * bugs del frontend
       * catálogos cambiaron mientras el usuario editaba
       * estados cacheados

   OBJETIVO
   --------
   Editar un Municipio existente permitiendo:
   - Cambiar Código
   - Cambiar Nombre
   - Moverlo a otro Estado (Estado destino)

   REGLAS (CONTRATO DE NEGOCIO)
   ----------------------------
   1) El Municipio a editar DEBE existir.
   2) El País seleccionado DEBE existir y estar Activo=1.
   3) El Estado destino DEBE:
      - existir
      - estar Activo=1
      - pertenecer al País seleccionado
   4) Anti-duplicados dentro del Estado destino:
      - NO puede existir OTRO Municipio con el mismo Código en el Estado destino
      - NO puede existir OTRO Municipio con el mismo Nombre en el Estado destino
      (se excluye el mismo Id_Municipio)
   5) Si el usuario realmente no cambió nada => “SIN_CAMBIOS” (no “ACTUALIZADA”).
   6) Se ejecuta el UPDATE.

   CONCURRENCIA (POR QUÉ EXISTE HANDLER 1062 EN UPDATE)
   ----------------------------------------------------
   Aunque hagas pre-checks, puede pasar una carrera:
   - Usuario A y B editan al mismo tiempo hacia el mismo (Codigo/Nombre + Estado destino)
   - Ambos “ven” que no hay duplicado
   - A guarda primero
   - B choca con UNIQUE => MySQL lanza 1062

   SOLUCIÓN PRO EN EDICIÓN: 1062 => CONFLICTO (NO “REUSAR”)
   --------------------------------------------------------
   En EDITAR no queremos usar el registro del otro usuario.
   Queremos avisar:
     - Accion = 'CONFLICTO'
     - Campo  = 'CODIGO' o 'NOMBRE'
     - Id_Conflicto = Id del municipio que ya tomó ese valor

   ¿QUÉ CAMBIA vs TU SP ACTUAL?
   ----------------------------
   A) “LOCK DETERMINÍSTICO DE PAÍSES”
      - Si el municipio está en País A y lo mueves a País B, dos usuarios cruzados (A->B y B->A)
        pueden provocar deadlocks si bloquean Países en diferente orden.
      - SOLUCIÓN: bloquear SIEMPRE en orden por Id:
          1) Pais LOW  (min(IdPaisActual, IdPaisSeleccionado))
          2) Pais HIGH (max(IdPaisActual, IdPaisSeleccionado))

   B) “JOIN ÚNICO PAÍS -> ESTADO DESTINO”
      - En lugar de validar País y Estado por separado, se valida TODO de un jalón:
          * País existe y Activo=1
          * Estado existe, Activo=1
          * Estado pertenece a ese País
      - Esto evita inconsistencias y deja el contrato más blindado.

   C) “SIN CAMBIOS”
      - Si Código, Nombre y Estado destino son iguales al actual:
        - COMMIT inmediato (para liberar locks)
        - Accion = 'SIN_CAMBIOS'

   NOTA IMPORTANTE: RESET A NULL ANTES DE SELECT ... INTO
   ------------------------------------------------------
   En MySQL, si un SELECT ... INTO no encuentra filas, las variables NO se limpian.
   Por eso hacemos SET var = NULL antes de cada SELECT ... INTO.

   RESULTADO
   ---------
   ÉXITO:
     - Mensaje
     - Accion = 'ACTUALIZADA'
     - Id_Municipio
     - Id_Estado_Anterior
     - Id_Estado_Nuevo
     - Id_Pais_Seleccionado

   SIN CAMBIOS:
     - Mensaje
     - Accion = 'SIN_CAMBIOS'
     - Id_Municipio
     - Id_Estado_Anterior
     - Id_Estado_Nuevo
     - Id_Pais_Seleccionado

   CONFLICTO (1062):
     - Mensaje
     - Accion = 'CONFLICTO'
     - Campo ('CODIGO'|'NOMBRE')
     - Id_Conflicto
     - Id_Municipio_Que_Intentabas_Editar
     - Id_Estado_Anterior
     - Id_Estado_Nuevo
     - Id_Pais_Seleccionado

============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS SP_EditarMunicipio$$

CREATE PROCEDURE SP_EditarMunicipio(
    IN _Id_Municipio INT,
    IN _Nuevo_Codigo VARCHAR(50),
    IN _Nuevo_Nombre VARCHAR(255),
    IN _Id_Pais_Seleccionado INT,
    IN _Id_Estado_Destino INT
)
SP: BEGIN
    /* ========================================================================================
       PARTE 0) VARIABLES
       ======================================================================================== */

    /* Datos actuales del municipio (para "SIN CAMBIOS") */
    DECLARE v_Codigo_Actual VARCHAR(50) DEFAULT NULL;
    DECLARE v_Nombre_Actual VARCHAR(255) DEFAULT NULL;

    /* “Estado anterior” (para respuesta y para saber si se movió o no) */
    DECLARE v_Estado_Anterior INT DEFAULT NULL;

    /* País actual del municipio (derivado del Estado anterior) */
    DECLARE v_Id_Pais_Actual INT DEFAULT NULL;

    /* Variable auxiliar genérica para existencia / validaciones */
    DECLARE v_Existe INT DEFAULT NULL;

    /* Para pre-checks de duplicados */
    DECLARE v_DupId INT DEFAULT NULL;

    /* Bandera para detectar choque 1062 en UPDATE */
    DECLARE v_Dup TINYINT(1) DEFAULT 0;

    /* Datos para respuesta de conflicto controlado */
    DECLARE v_Id_Conflicto INT DEFAULT NULL;
    DECLARE v_Campo_Conflicto VARCHAR(20) DEFAULT NULL;

    /* Para lock determinístico de países */
    DECLARE v_Pais_Low INT DEFAULT NULL;
    DECLARE v_Pais_High INT DEFAULT NULL;

    /* ========================================================================================
       PARTE 1) HANDLERS (CONCURRENCIA Y ERRORES)
       ======================================================================================== */

    /* 1062 (Duplicate entry):
       - No abortamos inmediatamente, marcamos v_Dup=1 para responder “CONFLICTO” controlado.
       - Esto solo tiene sentido si el 1062 ocurre en el UPDATE (por eso reseteamos v_Dup=0 antes).
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

    /* TRIM para quitar espacios invisibles.
       NULLIF('', '') para impedir guardar vacío como “valor válido” cuando tu negocio lo considera inválido. */
    SET _Nuevo_Codigo = NULLIF(TRIM(_Nuevo_Codigo), '');
    SET _Nuevo_Nombre = NULLIF(TRIM(_Nuevo_Nombre), '');

    /* ========================================================================================
       PARTE 3) VALIDACIONES BÁSICAS (antes de abrir TX)
       ======================================================================================== */

    IF _Id_Municipio IS NULL OR _Id_Municipio <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Id_Municipio inválido.';
    END IF;

    IF _Nuevo_Codigo IS NULL OR _Nuevo_Nombre IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Código y Nombre del Municipio son obligatorios.';
    END IF;

    IF _Id_Pais_Seleccionado IS NULL OR _Id_Pais_Seleccionado <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: País seleccionado inválido.';
    END IF;

    IF _Id_Estado_Destino IS NULL OR _Id_Estado_Destino <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Estado destino inválido.';
    END IF;

    /* ========================================================================================
       PARTE 4) TRANSACCIÓN PRINCIPAL
       ======================================================================================== */
    START TRANSACTION;

    /* ----------------------------------------------------------------------------------------
       PASO 1) Bloquear el Municipio a editar y leer su estado anterior + datos actuales
       ----------------------------------------------------------------------------------------
       - Aquí bloqueamos SOLO la fila del Municipio (FOR UPDATE).
       - ¿Por qué?
         * Evita que otro usuario cambie este mismo Municipio mientras tú lo editas.
         * Nos permite obtener:
             - v_Estado_Anterior (para respuesta)
             - v_Codigo_Actual y v_Nombre_Actual (para detectar “SIN CAMBIOS”)
       - NOTA: NO bloqueamos Estado/Pais aquí para minimizar riesgo de deadlocks cruzados
         (luego bloqueamos Países en orden determinístico).
    ---------------------------------------------------------------------------------------- */
    SET v_Estado_Anterior = NULL;
    SET v_Codigo_Actual = NULL;
    SET v_Nombre_Actual = NULL;

    SELECT
        M.Fk_Id_Estado,
        M.Codigo,
        M.Nombre
    INTO
        v_Estado_Anterior,
        v_Codigo_Actual,
        v_Nombre_Actual
    FROM Municipio M
    WHERE M.Id_Municipio = _Id_Municipio
    LIMIT 1
    FOR UPDATE;

    IF v_Estado_Anterior IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: El Municipio no existe.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 1.1) Obtener País ACTUAL del municipio (derivado del Estado anterior)
       ----------------------------------------------------------------------------------------
       - Aquí solo necesitamos el Id del país actual para poder:
         * hacer lock determinístico de países (actual vs seleccionado)
       - Si el Estado anterior no existe por alguna inconsistencia, abortamos.
       - No usamos FOR UPDATE aquí (evitamos meter locks antes del orden determinístico).
    ---------------------------------------------------------------------------------------- */
    SET v_Id_Pais_Actual = NULL;

    SELECT E.Fk_Id_Pais
      INTO v_Id_Pais_Actual
    FROM Estado E
    WHERE E.Id_Estado = v_Estado_Anterior
    LIMIT 1;

    IF v_Id_Pais_Actual IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Inconsistencia: el Estado actual del Municipio no existe.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 2) LOCK DETERMINÍSTICO DE PAÍSES (anti-deadlocks)
       ----------------------------------------------------------------------------------------
       PROBLEMA QUE RESUELVE:
       - Si dos transacciones intentan mover municipios entre País A y País B en direcciones opuestas,
         y cada una bloquea primero un país distinto, se puede generar DEADLOCK.
       SOLUCIÓN:
       - Bloqueamos SIEMPRE en el mismo orden:
         1) v_Pais_Low  = min(PaisActual, PaisSeleccionado)
         2) v_Pais_High = max(PaisActual, PaisSeleccionado)
       - Así todas las transacciones compiten por los locks en el mismo orden.
    ---------------------------------------------------------------------------------------- */
    IF v_Id_Pais_Actual = _Id_Pais_Seleccionado THEN
        SET v_Pais_Low = v_Id_Pais_Actual;
        SET v_Pais_High = v_Id_Pais_Actual;
    ELSE
        SET v_Pais_Low = LEAST(v_Id_Pais_Actual, _Id_Pais_Seleccionado);
        SET v_Pais_High = GREATEST(v_Id_Pais_Actual, _Id_Pais_Seleccionado);
    END IF;

    /* 2.1) Bloquear País LOW (debe existir)
       - OJO: el País actual podría estar inactivo y aún así queremos permitir editar,
              lo que exigimos activo es el País “seleccionado/destino”.
    */
    SET v_Existe = NULL;

    SELECT 1
      INTO v_Existe
    FROM Pais
    WHERE Id_Pais = v_Pais_Low
    LIMIT 1
    FOR UPDATE;

    IF v_Existe IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Inconsistencia: País (low) no existe.';
    END IF;

    /* 2.2) Bloquear País HIGH (si es distinto) */
    IF v_Pais_High <> v_Pais_Low THEN
        SET v_Existe = NULL;

        SELECT 1
          INTO v_Existe
        FROM Pais
        WHERE Id_Pais = v_Pais_High
        LIMIT 1
        FOR UPDATE;

        IF v_Existe IS NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Inconsistencia: País (high) no existe.';
        END IF;
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 3) Validación ATÓMICA (JOIN único): País seleccionado + Estado destino
       ----------------------------------------------------------------------------------------
       Validamos TODO en un solo SELECT:
       - País existe y Activo=1
       - Estado existe y Activo=1
       - Estado pertenece al País seleccionado
       Además:
       - FOR UPDATE aquí bloquea la fila del Estado destino (y el País seleccionado ya está bloqueado).
       - STRAIGHT_JOIN fuerza el orden de la consulta para que el optimizador no “reordene” joins.
    ---------------------------------------------------------------------------------------- */
    SET v_Existe = NULL;

    SELECT 1
      INTO v_Existe
    FROM Pais P
    STRAIGHT_JOIN Estado E ON E.Fk_Id_Pais = P.Id_Pais
    WHERE P.Id_Pais = _Id_Pais_Seleccionado
      AND P.Activo = 1
      AND E.Id_Estado = _Id_Estado_Destino
      AND E.Activo = 1
    LIMIT 1
    FOR UPDATE;

    IF v_Existe IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: El Estado destino no pertenece al País seleccionado o el País/Estado están inactivos.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 4) SIN CAMBIOS (salida temprana)
       ----------------------------------------------------------------------------------------
       - Si:
         * Código igual al actual
         * Nombre igual al actual
         * Estado destino igual al estado anterior
       - Entonces no hacemos pre-checks ni UPDATE.
       - COMMIT inmediato para liberar locks (importante para concurrencia).
    ---------------------------------------------------------------------------------------- */
    IF v_Codigo_Actual = _Nuevo_Codigo
       AND v_Nombre_Actual = _Nuevo_Nombre
       AND v_Estado_Anterior = _Id_Estado_Destino THEN

        COMMIT;

        SELECT 'Sin cambios: El Municipio ya tiene esos datos y ya está en ese Estado.' AS Mensaje,
               'SIN_CAMBIOS' AS Accion,
               _Id_Municipio AS Id_Municipio,
               v_Estado_Anterior AS Id_Estado_Anterior,
               _Id_Estado_Destino AS Id_Estado_Nuevo,
               _Id_Pais_Seleccionado AS Id_Pais_Seleccionado;
        LEAVE SP;
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 5) Pre-check duplicidad por CÓDIGO en el Estado destino (excluyendo el mismo Id)
       ----------------------------------------------------------------------------------------
       - “¿Existe OTRO municipio en ese mismo Estado destino con ese Código?”
       - FOR UPDATE:
         * si encuentra la fila duplicada, la bloquea y evita que cambie en medio de tu TX.
       - ORDER BY Id_Municipio:
         * lock determinístico (si hubiera más de uno por datos sucios, eliges siempre el mismo).
    ---------------------------------------------------------------------------------------- */
    SET v_DupId = NULL;

    SELECT Id_Municipio
      INTO v_DupId
    FROM Municipio
    WHERE Fk_Id_Estado = _Id_Estado_Destino
      AND Codigo = _Nuevo_Codigo
      AND Id_Municipio <> _Id_Municipio
    ORDER BY Id_Municipio
    LIMIT 1
    FOR UPDATE;

    IF v_DupId IS NOT NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Ya existe OTRO Municipio con ese CÓDIGO en el Estado destino.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 6) Pre-check duplicidad por NOMBRE en el Estado destino (excluyendo el mismo Id)
       ----------------------------------------------------------------------------------------
       - “¿Existe OTRO municipio en ese mismo Estado destino con ese Nombre?”
    ---------------------------------------------------------------------------------------- */
    SET v_DupId = NULL;

    SELECT Id_Municipio
      INTO v_DupId
    FROM Municipio
    WHERE Fk_Id_Estado = _Id_Estado_Destino
      AND Nombre = _Nuevo_Nombre
      AND Id_Municipio <> _Id_Municipio
    ORDER BY Id_Municipio
    LIMIT 1
    FOR UPDATE;

    IF v_DupId IS NOT NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Ya existe OTRO Municipio con ese NOMBRE en el Estado destino.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 7) UPDATE (aquí puede ocurrir 1062 por carrera)
       ----------------------------------------------------------------------------------------
       - Reseteamos v_Dup = 0 antes del UPDATE para saber si el handler 1062 se disparó aquí.
       - Si el handler se dispara, v_Dup = 1 y pasamos al PASO 8.
    ---------------------------------------------------------------------------------------- */
    SET v_Dup = 0;

    UPDATE Municipio
    SET Codigo = _Nuevo_Codigo,
        Nombre = _Nuevo_Nombre,
        Fk_Id_Estado = _Id_Estado_Destino,
        updated_at = NOW()
    WHERE Id_Municipio = _Id_Municipio;

    /* ----------------------------------------------------------------------------------------
       PASO 8) Si hubo 1062 => CONFLICTO CONTROLADO
       ----------------------------------------------------------------------------------------
       - Hacemos ROLLBACK porque NO queremos guardar nada parcial.
       - Determinamos SI el conflicto fue por:
         * CODIGO (en el Estado destino)
         * NOMBRE (en el Estado destino)
       - Regresamos “CONFLICTO” con Id_Conflicto para que el frontend muestre mensaje claro.
    ---------------------------------------------------------------------------------------- */
    IF v_Dup = 1 THEN
        ROLLBACK;

        SET v_Id_Conflicto = NULL;
        SET v_Campo_Conflicto = NULL;

        /* 8.1) Intentar detectar conflicto por CODIGO */
        SELECT Id_Municipio
          INTO v_Id_Conflicto
        FROM Municipio
        WHERE Fk_Id_Estado = _Id_Estado_Destino
          AND Codigo = _Nuevo_Codigo
          AND Id_Municipio <> _Id_Municipio
        ORDER BY Id_Municipio
        LIMIT 1;

        IF v_Id_Conflicto IS NOT NULL THEN
            SET v_Campo_Conflicto = 'CODIGO';
        ELSE
            /* 8.2) Si no fue CODIGO, intentar conflicto por NOMBRE */
            SELECT Id_Municipio
              INTO v_Id_Conflicto
            FROM Municipio
            WHERE Fk_Id_Estado = _Id_Estado_Destino
              AND Nombre = _Nuevo_Nombre
              AND Id_Municipio <> _Id_Municipio
            ORDER BY Id_Municipio
            LIMIT 1;

            IF v_Id_Conflicto IS NOT NULL THEN
                SET v_Campo_Conflicto = 'NOMBRE';
            END IF;
        END IF;

        SELECT 'No se guardó: otro usuario se adelantó. Refresca y vuelve a intentar.' AS Mensaje,
               'CONFLICTO' AS Accion,
               v_Campo_Conflicto AS Campo,
               v_Id_Conflicto AS Id_Conflicto,
               _Id_Municipio AS Id_Municipio_Que_Intentabas_Editar,
               v_Estado_Anterior AS Id_Estado_Anterior,
               _Id_Estado_Destino AS Id_Estado_Nuevo,
               _Id_Pais_Seleccionado AS Id_Pais_Seleccionado;
        LEAVE SP;
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 9) ÉXITO (commit final + respuesta estándar)
    ---------------------------------------------------------------------------------------- */
    COMMIT;

    SELECT 'Municipio actualizado correctamente' AS Mensaje,
           'ACTUALIZADA' AS Accion,
           _Id_Municipio AS Id_Municipio,
           v_Estado_Anterior AS Id_Estado_Anterior,
           _Id_Estado_Destino AS Id_Estado_Nuevo,
           _Id_Pais_Seleccionado AS Id_Pais_Seleccionado;

END$$

DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_CambiarEstatusMunicipio
   ============================================================================================
   OBJETIVO
   --------
   Activar/Desactivar (borrado lógico) un Municipio:
      Municipio.Activo (1 = activo, 0 = inactivo)

   REGLAS CRÍTICAS
   --------------
   A) Al DESACTIVAR un Municipio (Activo=0):
      - NO se permite si está REFERENCIADO por tablas hijas (tu regla actual).

   B) Al ACTIVAR un Municipio (Activo=1)  <<<<<<<<<<<< CANDADO JERÁRQUICO (C)
      - NO se permite si su ESTADO o su PAÍS están INACTIVOS.
        Evita:
          País=0  con Municipio=1
          Estado=0 con Municipio=1

   CONCURRENCIA / BLOQUEOS
   -----------------------
   - Bloqueamos en orden jerárquico: PAÍS -> ESTADO -> MUNICIPIO
   - Usamos STRAIGHT_JOIN + FOR UPDATE para:
       * asegurar orden de bloqueo
       * evitar carreras (que apaguen Estado/País mientras activas Municipio)
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS SP_CambiarEstatusMunicipio$$

CREATE PROCEDURE SP_CambiarEstatusMunicipio(
    IN _Id_Municipio INT,
    IN _Nuevo_Estatus TINYINT /* 1 = Activo, 0 = Inactivo */
)
BEGIN
    /* ----------------------------------------------------------------------------------------
       VARIABLES
    ---------------------------------------------------------------------------------------- */
    DECLARE v_Existe INT DEFAULT NULL;

    /* Estatus actual del Municipio */
    DECLARE v_Activo_Actual TINYINT(1) DEFAULT NULL;

    /* Datos jerárquicos para candado al ACTIVAR */
    DECLARE v_Id_Estado INT DEFAULT NULL;
    DECLARE v_Estado_Activo TINYINT(1) DEFAULT NULL;

    DECLARE v_Id_Pais INT DEFAULT NULL;
    DECLARE v_Pais_Activo TINYINT(1) DEFAULT NULL;

    /* ----------------------------------------------------------------------------------------
       HANDLER GENERAL
    ---------------------------------------------------------------------------------------- */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    /* ----------------------------------------------------------------------------------------
       VALIDACIONES DE PARÁMETROS
    ---------------------------------------------------------------------------------------- */
    IF _Id_Municipio IS NULL OR _Id_Municipio <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Id_Municipio inválido.';
    END IF;

    IF _Nuevo_Estatus NOT IN (0,1) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Estatus inválido (solo 0 o 1).';
    END IF;

    START TRANSACTION;

    /* ----------------------------------------------------------------------------------------
       1) VALIDAR EXISTENCIA Y BLOQUEAR FILAS EN ORDEN JERÁRQUICO (PAÍS -> ESTADO -> MUNICIPIO)
       ----------------------------------------------------------------------------------------
       ¿POR QUÉ ASÍ?
       - Antes solo bloqueabas Municipio.
       - Para el candado (C) necesitamos leer Estado.Activo y Pais.Activo.
       - Si no bloqueas, te puede pasar:
           * activas municipio
           * en paralelo apagan estado/país
           * terminas con jerarquía inconsistente
       - Con FOR UPDATE aquí, quedan bloqueadas las 3 filas mientras decides.
    ---------------------------------------------------------------------------------------- */
    SELECT
        1 AS Existe,
        M.Activo AS Activo_Municipio,

        M.Fk_Id_Estado AS Id_Estado,
        E.Activo AS Activo_Estado,

        E.Fk_Id_Pais AS Id_Pais,
        P.Activo AS Activo_Pais
    INTO
        v_Existe,
        v_Activo_Actual,
        v_Id_Estado,
        v_Estado_Activo,
        v_Id_Pais,
        v_Pais_Activo
    FROM Pais P
    STRAIGHT_JOIN Estado E ON E.Fk_Id_Pais = P.Id_Pais
    STRAIGHT_JOIN Municipio M ON M.Fk_Id_Estado = E.Id_Estado
    WHERE M.Id_Municipio = _Id_Municipio
    LIMIT 1
    FOR UPDATE;

    IF v_Existe IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: El Municipio no existe.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       2) "SIN CAMBIOS" (IDEMPOTENCIA)
       - Si ya está como lo pide el switch, no hacemos nada.
    ---------------------------------------------------------------------------------------- */
    IF v_Activo_Actual = _Nuevo_Estatus THEN
        COMMIT;
        SELECT CASE
            WHEN _Nuevo_Estatus = 1 THEN 'Sin cambios: El Municipio ya estaba Activo.'
            ELSE 'Sin cambios: El Municipio ya estaba Inactivo.'
        END AS Mensaje,
        v_Activo_Actual AS Activo_Anterior,
        _Nuevo_Estatus AS Activo_Nuevo;
    ELSE

        /* ------------------------------------------------------------------------------------
           3) CANDADO JERÁRQUICO AL ACTIVAR (C)  <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
           ------------------------------------------------------------------------------------
           REGLA:
           - Si quieres ACTIVAR Municipio (Nuevo_Estatus=1),
             su Estado y su País deben estar ACTIVOS.
           - Si alguno está inactivo: bloquear con mensaje claro.
        ------------------------------------------------------------------------------------ */
        IF _Nuevo_Estatus = 1 THEN
            IF v_Pais_Activo = 0 AND v_Estado_Activo = 0 THEN
                SIGNAL SQLSTATE '45000'
                    SET MESSAGE_TEXT = 'BLOQUEADO: No se puede ACTIVAR el Municipio porque su PAÍS y su ESTADO están INACTIVOS. Activa primero País y Estado.';
            END IF;

            IF v_Pais_Activo = 0 THEN
                SIGNAL SQLSTATE '45000'
                    SET MESSAGE_TEXT = 'BLOQUEADO: No se puede ACTIVAR el Municipio porque su PAÍS está INACTIVO. Activa primero el País.';
            END IF;

            IF v_Estado_Activo = 0 THEN
                SIGNAL SQLSTATE '45000'
                    SET MESSAGE_TEXT = 'BLOQUEADO: No se puede ACTIVAR el Municipio porque su ESTADO está INACTIVO. Activa primero el Estado.';
            END IF;
        END IF;

        /* ------------------------------------------------------------------------------------
           4) SI INTENTA DESACTIVAR: BLOQUEAR SI HAY REFERENCIAS (regla original)
           - Cada tabla hija debe impedir el apagado.
           - Mensajes específicos ayudan a soporte y a UX.
        ------------------------------------------------------------------------------------ */
        IF _Nuevo_Estatus = 0 THEN

            /* 4A) Cat_Centros_Trabajo */
            IF EXISTS (
                SELECT 1
                FROM Cat_Centros_Trabajo
                WHERE Fk_Id_Municipio_CatCT = _Id_Municipio
				AND `Activo` = 1 -- <--- CORRECCIÓN IMPORTANTE
                LIMIT 1
            ) THEN
                SIGNAL SQLSTATE '45000'
                    SET MESSAGE_TEXT = 'BLOQUEADO: No se puede desactivar el Municipio porque está referenciado por Cat_Centros_Trabajo (Centros de Trabajo).';
            END IF;

            /* 4B) Cat_Departamentos */
            IF EXISTS (
                SELECT 1
                FROM Cat_Departamentos
                WHERE Fk_Id_Municipio_CatDep = _Id_Municipio
				AND `Activo` = 1 -- <--- CORRECCIÓN IMPORTANTE
                LIMIT 1
            ) THEN
                SIGNAL SQLSTATE '45000'
                    SET MESSAGE_TEXT = 'BLOQUEADO: No se puede desactivar el Municipio porque está referenciado por Cat_Departamentos.';
            END IF;

            /* 4C) Cat_Cases_Sedes */
            IF EXISTS (
                SELECT 1
                FROM Cat_Cases_Sedes
                WHERE Fk_Id_Municipio = _Id_Municipio
				AND `Activo` = 1 -- <--- CORRECCIÓN IMPORTANTE
                LIMIT 1
            ) THEN
                SIGNAL SQLSTATE '45000'
                    SET MESSAGE_TEXT = 'BLOQUEADO: No se puede desactivar el Municipio porque está referenciado por Cat_Cases_Sedes.';
            END IF;

        END IF;

        /* ------------------------------------------------------------------------------------
           5) APLICAR CAMBIO DE ESTATUS
        ------------------------------------------------------------------------------------ */
        UPDATE Municipio
        SET Activo = _Nuevo_Estatus,
            updated_at = NOW()
        WHERE Id_Municipio = _Id_Municipio;

        COMMIT;

        /* ------------------------------------------------------------------------------------
           6) RESPUESTA PARA FRONTEND
        ------------------------------------------------------------------------------------ */
        SELECT CASE
            WHEN _Nuevo_Estatus = 1 THEN 'Municipio Reactivado Exitosamente'
            ELSE 'Municipio Desactivado (Eliminado Lógico)'
        END AS Mensaje,
        v_Activo_Actual AS Activo_Anterior,
        _Nuevo_Estatus AS Activo_Nuevo;

    END IF;

END$$
DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_EliminarMunicipio
   ============================================================================================
   OBJETIVO
   --------
   Eliminar físicamente (DELETE) un Municipio.

   ¿CUÁNDO SE USA?
   --------------
   - Solo en administración avanzada, limpieza de datos o corrección controlada.
   - Normalmente NO se usa en operación diaria (para eso es el borrado lógico).

   RIESGOS / CANDADOS RECOMENDADOS
   -------------------------------
   - Si existe cualquier tabla que referencie Municipio (FK con NO ACTION),
     el DELETE fallará con error de integridad referencial.
   - Por seguridad, es recomendable agregar candados antes del DELETE, por ejemplo:
     - Bloquear si hay Cat_Centros_Trabajo ligados
     - Bloquear si hay Cat_Departamentos ligados
     - Bloquear si hay Cat_Cases_Sedes ligados
     (En tu esquema sí hay FKs hacia Municipio en varias tablas.)

   VALIDACIONES
   ------------
   - Verificar que el Id exista.
   - (Recomendado) Hacer el DELETE dentro de transacción y manejar excepciones con HANDLER,
     para devolver mensajes controlados si hay FKs que bloquean.

   RESPUESTA
   ---------
   - Devuelve un mensaje de confirmación si se eliminó.
============================================================================================ */

/* PROCEDIMIENTO DE ELIMINACION FISICA (BORRAR DEFINITIVAMENTE) */
DELIMITER $$

-- DROP PROCEDURE IF EXISTS SP_EliminarMunicipio$$
CREATE PROCEDURE SP_EliminarMunicipio(
    IN _Id_Municipio INT
)
BEGIN
    /* HANDLER FK: no se puede borrar si está referenciado */
    DECLARE EXIT HANDLER FOR 1451
    BEGIN
        ROLLBACK;
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: No se puede eliminar el Municipio porque está referenciado por otros registros (FK).';
    END;

    /* HANDLER general */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    /* Validación */
    IF _Id_Municipio IS NULL OR _Id_Municipio <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Id_Municipio inválido.';
    END IF;

    IF NOT EXISTS(SELECT 1 FROM Municipio WHERE Id_Municipio = _Id_Municipio) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: El ID del Municipio no existe.';
    END IF;

    START TRANSACTION;

    DELETE FROM Municipio
    WHERE Id_Municipio = _Id_Municipio;

    COMMIT;

    SELECT 'Municipio Eliminado Permanentemente' AS Mensaje;
END$$

DELIMITER ;