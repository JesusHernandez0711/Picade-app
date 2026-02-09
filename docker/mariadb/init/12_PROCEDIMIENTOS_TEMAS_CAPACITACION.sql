USE `PICADE`;

/* ------------------------------------------------------------------------------------------------------ */
/* CREACION DE VISTAS Y PROCEDIMIENTOS DE ALMACENADO PARA LA BASE DE DATOS                                */
/* ------------------------------------------------------------------------------------------------------ */

/* ======================================================================================================
   VIEW: Vista_Temas_Capacitacion
   ======================================================================================================
   
   1. OBJETIVO TÉCNICO Y DE NEGOCIO (BUSINESS GOAL)
   ------------------------------------------------
   Esta vista constituye el **Tablero de Control Académico** para el administrador del sistema.
   Su función es proporcionar un inventario "aplanado" y legible de todos los Temas de Capacitación 
   disponibles, enriquecido con la información de su clasificación pedagógica.

   Actúa como la interfaz de lectura para el Grid Principal de Temas, permitiendo identificar rápidamente
   qué se enseña, cuánto dura y bajo qué modalidad instruccional.

   2. ARQUITECTURA DE DATOS (ESTRATEGIA DE VISIBILIDAD TOTAL)
   ----------------------------------------------------------
   - TIPO DE JOIN: Se utiliza **LEFT JOIN** entre `Temas` e `Instrucción`.
   
   - JUSTIFICACIÓN TÉCNICA: 
     En la operación real, es posible que se carguen Temas masivamente (vía CSV) sin asignarles 
     todavía un Tipo de Instrucción. 
     Si usáramos INNER JOIN, esos temas "huérfanos" desaparecerían del grid, volviéndose invisibles 
     e imposibles de corregir desde la UI. 
     El LEFT JOIN garantiza que el administrador vea TODO el catálogo, incluso los registros incompletos.

   3. NOMENCLATURA Y SEMÁNTICA (UX OPTIMIZATION)
   ----------------------------------------------
   - Limpieza de Ruido: Se omiten columnas técnicas irrelevantes para el listado masivo 
     (como descripciones largas o IDs foráneos), priorizando la velocidad de lectura visual.
   - Estandarización: Se renombran las columnas (`Nombre_Tema`, `Estatus_Tema`) para mantener 
     coherencia con el resto de los módulos del sistema (Usuarios, Geografía).

   4. DICCIONARIO DE DATOS (CONTRATO DE SALIDA)
   --------------------------------------------
   [Bloque 1: Identidad del Recurso]
   - Id_Tema:                 (INT) Llave primaria (Oculta en UI, usada para los botones Editar/Eliminar).
   - Codigo_Tema:             (VARCHAR) Clave interna (ej: 'SEG-001').
   - Nombre_Tema:             (VARCHAR) Denominación del curso/tema.

   [Bloque 2: Detalles Académicos]
   - Duracion_Horas:          (INT) Carga horaria estándar.
   - Nombre_Tipo_Instruccion: (VARCHAR) Clasificación pedagógica (ej: 'Teórico', 'Práctico').
                              Puede ser NULL si no se ha asignado aún.

   [Bloque 3: Control]
   - Estatus_Tema:            (TINYINT) 1 = Activo (Programable), 0 = Baja Lógica (Histórico).
   ====================================================================================================== */

CREATE OR REPLACE 
    ALGORITHM = UNDEFINED 
    SQL SECURITY DEFINER
VIEW `Vista_Temas_Capacitacion` AS
    SELECT 
        /* -----------------------------------------------------------------------------------
           BLOQUE 1: IDENTIDAD DEL REGISTRO
           Datos fundamentales para la identificación única y operaciones CRUD.
           ----------------------------------------------------------------------------------- */
        `Tem`.`Id_Cat_TemasCap`      AS `Id_Tema`,      -- Identificador único para el Backend

        /* -----------------------------------------------------------------------------------
           BLOQUE 2: INFORMACIÓN VISUAL PRINCIPAL
           Datos descriptivos que el usuario final lee en la tabla.
           ----------------------------------------------------------------------------------- */
        `Tem`.`Codigo`               AS `Codigo_Tema`,  -- Clave corta o mnemotécnico
        `Tem`.`Nombre`               AS `Nombre_Tema`,  -- Título oficial del tema
        `Tem`.`Duracion_Horas`       AS `Duracion_Horas`,

        /* -----------------------------------------------------------------------------------
           BLOQUE 3: INFORMACIÓN RELACIONAL (HUMANIZADA)
           Contexto pedagógico proveniente del catálogo satélite.
           ----------------------------------------------------------------------------------- */
        /* Nota: Se proyecta el nombre directo. Si es NULL, el Frontend (Laravel/Vue) debe 
           manejar la visualización (ej: pintar un guion "-" o una etiqueta "Sin Asignar"). */
		-- `Inst`.`Id_CatTipoCap` AS `Id_Tipo_Instruccion`,
        `Inst`.`Nombre`              AS `Nombre_Tipo_Instruccion`, 
        -- COALESCE(`Inst`.`Nombre`, '--- SIN TIPO ASIGNADO ---') AS `Nombre_Tipo_Capacitacion`,
		-- `Inst`.`Descripcion` AS `Descripcion_TipoCap`, 
        
        /* -----------------------------------------------------------------------------------
           BLOQUE 4: ESTADO OPERATIVO
           Semáforo para indicar disponibilidad en la programación de cursos.
           ----------------------------------------------------------------------------------- */
        `Tem`.`Activo`               AS `Estatus_Tema`

    FROM 
        `PICADE`.`Cat_Temas_Capacitacion` `Tem`
        
        /* LEFT JOIN ESTRATÉGICO: 
           Garantiza la visibilidad de temas 'huérfanos' (sin tipo de instrucción asignado)
           para permitir su corrección administrativa. */
        LEFT JOIN `PICADE`.`Cat_Tipos_Instruccion_Cap` `Inst` 
            ON `Tem`.`Fk_Id_CatTipoInstCap` = `Inst`.`Id_CatTipoInstCap`;

/* ====================================================================================================
	PROCEDIMIENTO SP_RegistrarTemaCapacitacion
   ====================================================================================================

   ----------------------------------------------------------------------------------------------------
   1. CONTEXTO Y PROPÓSITO DEL NEGOCIO (BUSINESS CONTEXT)
   ----------------------------------------------------------------------------------------------------
   Este procedimiento gestiona el ciclo de vida inicial (ALTA) de un "Tema de Capacitación" (Curso).
   Los Temas son el activo central del sistema de capacitación; representan el catálogo de conocimientos
   que la organización puede impartir (ej: "Seguridad Industrial Nivel 1", "Excel Avanzado").
   
   Su función no es simplemente insertar un dato. Actúa como un GUARDIÁN DE INTEGRIDAD que impide:
     a) La creación de cursos "huérfanos" (sin una clasificación pedagógica válida).
     b) La duplicidad de claves o nombres que generarían confusión operativa.
     c) La corrupción de datos por condiciones de carrera en entornos de alta concurrencia.

   ----------------------------------------------------------------------------------------------------
   2. REGLAS DE NEGOCIO ESTRICTAS (HARD CONSTRAINTS)
   ----------------------------------------------------------------------------------------------------
   [RN-01] INTEGRIDAD DE DATOS (MANDATORY FIELDS):
       - CÓDIGO: Es la llave maestra de identificación (ej: 'SEG-001'). NO puede ser Nulo.
       - NOMBRE: Es la identidad humana del curso. NO puede ser Nulo.
       - DURACIÓN: Es vital para el cálculo de horas-hombre. NO puede ser Nulo ni negativo.
       - TIPO DE INSTRUCCIÓN: Es la clasificación pedagógica. NO puede ser Nulo.

   [RN-02] INTEGRIDAD JERÁRQUICA (PARENT LOCKING):
       - Principio: "Un hijo no puede nacer de un padre muerto".
       - Validación: El Tipo de Instrucción (Padre) debe existir Y estar ACTIVO (1).
       - Seguridad: Se bloquea la fila del Padre durante la transacción para evitar que otro
         administrador lo desactive mientras se registra el curso.

   [RN-03] IDENTIDAD UNÍVOCA DE DOBLE FACTOR:
       - El sistema protege la unicidad por dos vías:
         1. Por CÓDIGO: No pueden existir dos cursos con la clave 'EXCEL-01'.
         2. Por NOMBRE: No pueden existir dos cursos llamados 'EXCEL BÁSICO'.
       - Resolución de Conflictos:
         * Si Coinciden Código y Nombre -> ÉXITO (Se reactiva o reutiliza el registro existente).
         * Si Coincide uno pero no el otro -> ERROR (Conflicto de Datos).

   ----------------------------------------------------------------------------------------------------
   3. ARQUITECTURA DE CONCURRENCIA (ACID & RECOVERY)
   ----------------------------------------------------------------------------------------------------
   [ESTRATEGIA]: BLOQUEO PESIMISTA + RECUPERACIÓN OPTIMISTA
   
   1. Bloqueo Pesimista (FOR UPDATE): Se utiliza al validar el Padre y al buscar duplicados.
      Esto serializa las operaciones conflictivas.
   
   2. Patrón "Re-Resolve" (Handler 1062):
      - Problema: Existe una ventana de microsegundos entre la validación (SELECT) y la inserción (INSERT)
        donde otro usuario podría insertar el mismo registro.
      - Solución: Si el motor de BD lanza un error de duplicado (1062), este SP lo captura,
        revierte la transacción fallida, y busca el registro "ganador" para devolverlo como éxito.
      - Beneficio: El usuario final jamás ve un error técnico por concurrencia.

   ----------------------------------------------------------------------------------------------------
   4. CONTRATO DE SALIDA (OUTPUT)
   ----------------------------------------------------------------------------------------------------
   Retorna un Resultset con:
     - Mensaje: Texto descriptivo para la UI.
     - Id_Tema: La llave primaria del recurso gestionado.
     - Accion: 'CREADA' (Nuevo), 'REACTIVADA' (Recuperado), 'REUSADA' (Existente).
   ==================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_RegistrarTemaCapacitacion`$$

CREATE PROCEDURE `SP_RegistrarTemaCapacitacion`(
    /* ------------------------------------------------------------------------------------------------
       SECCIÓN DE PARÁMETROS DE ENTRADA (INPUT LAYER)
       Recibimos datos crudos. Se asume que requieren sanitización.
       ------------------------------------------------------------------------------------------------ */
    IN _Codigo          VARCHAR(50),   -- [OBLIGATORIO] Clave única interna.
    IN _Nombre          VARCHAR(255),  -- [OBLIGATORIO] Nombre descriptivo único.
    IN _Descripcion     VARCHAR(255),  -- [OPCIONAL] Temario o notas adicionales (Puede ser NULL).
    IN _Duracion_Horas  SMALLINT,      -- [OBLIGATORIO] Carga horaria (Debe ser > 0).
    IN _Id_TipoInst     INT            -- [OBLIGATORIO] FK hacia el catálogo de Tipos.
)
THIS_PROC: BEGIN
    
    /* ================================================================================================
       BLOQUE 0: INICIALIZACIÓN DE VARIABLES DE ENTORNO
       Propósito: Definir los contenedores que mantendrán el estado de la base de datos en memoria.
       ================================================================================================ */
    
    /* Variables de Diagnóstico (Snapshots del registro si ya existe) */
    DECLARE v_Id_Tema      INT DEFAULT NULL;
    DECLARE v_Activo       TINYINT(1) DEFAULT NULL;
    DECLARE v_Nombre_Exist VARCHAR(255) DEFAULT NULL;
    DECLARE v_Codigo_Exist VARCHAR(50) DEFAULT NULL;
    
    /* Variables de Integridad Jerárquica (Estado del Padre) */
    DECLARE v_Padre_Existe INT DEFAULT NULL;
    DECLARE v_Padre_Activo TINYINT(1) DEFAULT NULL;

    /* Semáforo de Control de Errores (Bandera de Concurrencia) */
    DECLARE v_Dup          TINYINT(1) DEFAULT 0;

    /* ================================================================================================
       BLOQUE 1: DEFINICIÓN DE HANDLERS (SISTEMA DE DEFENSA)
       Propósito: Asegurar que el procedimiento termine de forma controlada ante cualquier eventualidad.
       ================================================================================================ */
    
    /* 1.1 HANDLER DE DUPLICIDAD (Error 1062 - Duplicate Entry)
       Objetivo: Capturar colisiones de Unique Key en el INSERT final.
       Acción: No abortar. Encender bandera v_Dup = 1 para activar el protocolo de recuperación. */
    DECLARE CONTINUE HANDLER FOR 1062 SET v_Dup = 1;

    /* 1.2 HANDLER DE FALLO CRÍTICO (SQLEXCEPTION)
       Objetivo: Capturar errores de infraestructura (Disco, Red, Sintaxis).
       Acción: Rollback total y propagación del error. */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; 
    END;

    /* ================================================================================================
       BLOQUE 2: SANITIZACIÓN Y NORMALIZACIÓN (DATA HYGIENE)
       Propósito: Limpiar los datos de entrada para evitar registros sucios o espacios invisibles.
       ================================================================================================ */
    
    /* Limpieza de cadenas: TRIM elimina espacios. NULLIF convierte cadenas vacías en NULL reales. */
    SET _Codigo      = NULLIF(TRIM(_Codigo), '');
    SET _Nombre      = NULLIF(TRIM(_Nombre), '');
    SET _Descripcion = NULLIF(TRIM(_Descripcion), '');
    
    /* Sanitización numérica: Convertir NULL o negativos a 0 para validación lógica posterior. */
    SET _Duracion_Horas = IFNULL(_Duracion_Horas, 0);

    /* ================================================================================================
       BLOQUE 3: VALIDACIONES PREVIAS (FAIL FAST STRATEGY)
       Propósito: Rechazar peticiones inválidas antes de consumir recursos de transacción.
       ================================================================================================ */
    
    /* Regla: El Código es la identidad técnica primaria. */
    IF _Codigo IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN [400]: El CÓDIGO del Tema es obligatorio.';
    END IF;

    /* Regla: El Nombre es la identidad semántica. */
    IF _Nombre IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN [400]: El NOMBRE del Tema es obligatorio.';
    END IF;

    /* Regla: Un curso sin duración o con duración negativa no es planificable. */
    IF _Duracion_Horas <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN [400]: La DURACIÓN debe ser un número mayor a 0.';
    END IF;

    /* Regla: Integridad Referencial Básica. */
    IF _Id_TipoInst IS NULL OR _Id_TipoInst <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN [400]: Debe seleccionar un TIPO DE INSTRUCCIÓN válido.';
    END IF;

    /* ================================================================================================
       BLOQUE 4: FASE TRANSACCIONAL (NÚCLEO DEL PROCESO)
       Propósito: Ejecutar la lógica de negocio de manera atómica (Todo o Nada).
       ================================================================================================ */
    START TRANSACTION;

    /* ------------------------------------------------------------------------------------------------
       PASO 4.1: VALIDACIÓN JERÁRQUICA (EL CANDADO DEL PADRE)
       Objetivo: Asegurar que el curso se asigne a una categoría válida y viva.
       Mecánica: `FOR UPDATE` bloquea la fila del Tipo de Instrucción.
       Justificación: Evita condiciones de carrera donde un Admin A desactiva el Tipo, mientras
       el Admin B crea un curso bajo ese Tipo.
       ------------------------------------------------------------------------------------------------ */
    SET v_Padre_Existe = NULL;
    SET v_Padre_Activo = NULL;

    SELECT 1, `Activo` 
    INTO v_Padre_Existe, v_Padre_Activo
    FROM `Cat_Tipos_Instruccion_Cap` 
    WHERE `Id_CatTipoInstCap` = _Id_TipoInst
    LIMIT 1 
    FOR UPDATE; -- <--- BLOQUEO PREVENTIVO AL PADRE

    /* Chequeo de Existencia */
    IF v_Padre_Existe IS NULL THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE INTEGRIDAD [404]: El Tipo de Instrucción seleccionado no existe en el catálogo.';
    END IF;

    /* Chequeo de Vigencia */
    IF v_Padre_Activo = 0 THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [409]: El Tipo de Instrucción seleccionado está INACTIVO. No se pueden registrar nuevos temas bajo una categoría obsoleta.';
    END IF;

    /* ------------------------------------------------------------------------------------------------
       PASO 4.2: RESOLUCIÓN DE IDENTIDAD POR CÓDIGO (REGLA PRIMARIA)
       Objetivo: Verificar si la Clave Única ya existe.
       ------------------------------------------------------------------------------------------------ */
    SET v_Id_Tema = NULL;

    SELECT `Id_Cat_TemasCap`, `Activo`, `Nombre`
    INTO v_Id_Tema, v_Activo, v_Nombre_Exist
    FROM `Cat_Temas_Capacitacion`
    WHERE `Codigo` = _Codigo
    LIMIT 1
    FOR UPDATE; -- Bloqueo preventivo a la fila si existe

    /* ESCENARIO A: EL CÓDIGO YA EXISTE */
    IF v_Id_Tema IS NOT NULL THEN
        
        /* Validación de Consistencia: Si el código existe, el nombre DEBE ser el mismo. 
           Si el código es igual pero el nombre diferente, es un conflicto de datos. */
        IF v_Nombre_Exist <> _Nombre THEN
            ROLLBACK;
            SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'CONFLICTO DE DATOS [409]: El CÓDIGO ingresado ya existe pero pertenece a un Tema con diferente NOMBRE. Verifique sus datos.';
        END IF;

        /* Sub-Escenario A.1: Autosanación (Reactivar si estaba borrado lógico) */
        IF v_Activo = 0 THEN
            UPDATE `Cat_Temas_Capacitacion`
            SET `Activo` = 1,
                `Descripcion`      = COALESCE(_Descripcion, `Descripcion`), -- Solo actualiza si hay dato nuevo
                `Duracion_Horas`   = _Duracion_Horas,
                `Fk_Id_CatTipoInstCap` = _Id_TipoInst, -- Actualizamos el padre por si cambió la asignación
                `updated_at`       = NOW()
            WHERE `Id_Cat_TemasCap` = v_Id_Tema;

            COMMIT;
            SELECT 'Tema reactivado y actualizado exitosamente.' AS Mensaje, v_Id_Tema AS Id_Tema, 'REACTIVADA' AS Accion;
            LEAVE THIS_PROC;
            
        /* Sub-Escenario A.2: Idempotencia (Ya existe y está activo) */
        ELSE
            COMMIT;
            SELECT 'El Tema ya se encuentra registrado y activo.' AS Mensaje, v_Id_Tema AS Id_Tema, 'REUSADA' AS Accion;
            LEAVE THIS_PROC;
        END IF;
    END IF;

    /* ------------------------------------------------------------------------------------------------
       PASO 4.3: RESOLUCIÓN DE IDENTIDAD POR NOMBRE (REGLA SECUNDARIA)
       Objetivo: Si el código es nuevo, verificamos que el NOMBRE no esté ocupado por otro código.
       ------------------------------------------------------------------------------------------------ */
    SET v_Id_Tema = NULL;
    SET v_Codigo_Exist = NULL;

    SELECT `Id_Cat_TemasCap`, `Activo`, `Codigo`
    INTO v_Id_Tema, v_Activo, v_Codigo_Exist
    FROM `Cat_Temas_Capacitacion`
    WHERE `Nombre` = _Nombre
    LIMIT 1
    FOR UPDATE; -- Bloqueo preventivo

    /* ESCENARIO B: EL NOMBRE YA EXISTE */
    IF v_Id_Tema IS NOT NULL THEN
        
        /* Validación de Conflicto: El nombre existe, pero tiene un código diferente al ingresado.
           Esto se bloquea para evitar duplicados semánticos. */
        IF v_Codigo_Exist <> _Codigo THEN
             ROLLBACK;
             SIGNAL SQLSTATE '45000' 
             SET MESSAGE_TEXT = 'CONFLICTO DE DATOS [409]: El NOMBRE ingresado ya existe pero está asociado a un CÓDIGO diferente.';
        END IF;
        
        /* Nota: Si el código coincidiera, habría caído en el PASO 4.2. 
           Si llegamos aquí y los códigos son distintos, es error definitivo. */
    END IF;

    /* ------------------------------------------------------------------------------------------------
       PASO 4.4: PERSISTENCIA (INSERCIÓN FÍSICA)
       Si llegamos aquí, no hay duplicados ni conflictos. El registro es nuevo y válido.
       ------------------------------------------------------------------------------------------------ */
    SET v_Dup = 0; -- Reiniciar bandera de control

    INSERT INTO `Cat_Temas_Capacitacion` (
        `Codigo`, 
        `Nombre`, 
        `Descripcion`, 
        `Duracion_Horas`, 
        `Fk_Id_CatTipoInstCap`,
        `Activo`,
        `created_at`,
        `updated_at`
    ) VALUES (
        _Codigo, 
        _Nombre, 
        _Descripcion, 
        _Duracion_Horas, 
        _Id_TipoInst,
        1,      -- Activo por defecto
        NOW(),  -- Created
        NOW()   -- Updated
    );

    /* Verificación de Éxito: Si la bandera v_Dup sigue en 0, el INSERT fue limpio. */
    IF v_Dup = 0 THEN
        COMMIT;
        SELECT 'Tema registrado exitosamente.' AS Mensaje, LAST_INSERT_ID() AS Id_Tema, 'CREADA' AS Accion;
        LEAVE THIS_PROC;
    END IF;

    /* ================================================================================================
       BLOQUE 5: PROTOCOLO DE RECUPERACIÓN DE CONCURRENCIA (RE-RESOLVE PATTERN)
       Propósito: Manejar el Error 1062 si alguien "ganó la carrera" de inserción milisegundos antes.
       ================================================================================================ */
    
    /* 1. Limpiamos la transacción fallida para liberar bloqueos parciales */
    ROLLBACK; 
    
    /* 2. Iniciamos nueva lectura limpia */
    START TRANSACTION;
    
    SET v_Id_Tema = NULL;

    /* 3. Buscamos al ganador por CÓDIGO (Identificador fuerte) */
    SELECT `Id_Cat_TemasCap`, `Activo`, `Nombre`
    INTO v_Id_Tema, v_Activo, v_Nombre_Exist
    FROM `Cat_Temas_Capacitacion`
    WHERE `Codigo` = _Codigo
    LIMIT 1
    FOR UPDATE;

    IF v_Id_Tema IS NOT NULL THEN
        /* Validación de seguridad: Que no sea un falso positivo con nombre distinto */
        IF v_Nombre_Exist <> _Nombre THEN
             SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR CRÍTICO [500]: Concurrencia detectada con inconsistencia de datos (Nombres no coinciden).';
        END IF;

        /* Si el ganador estaba inactivo, lo reactivamos nosotros */
        IF v_Activo = 0 THEN
             UPDATE `Cat_Temas_Capacitacion` SET `Activo` = 1, `updated_at` = NOW() WHERE `Id_Cat_TemasCap` = v_Id_Tema;
             COMMIT;
             SELECT 'Tema reactivado (recuperado tras concurrencia).' AS Mensaje, v_Id_Tema AS Id_Tema, 'REACTIVADA' AS Accion;
             LEAVE THIS_PROC;
        END IF;
        
        /* Si ya está activo, lo reusamos */
        COMMIT;
        SELECT 'El Tema ya existía (reusado tras concurrencia).' AS Mensaje, v_Id_Tema AS Id_Tema, 'REUSADA' AS Accion;
        LEAVE THIS_PROC;
    END IF;

    /* 4. Fallo Irrecuperable (Corrupción de índices o error fantasma) */
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR CRÍTICO [500]: Fallo de concurrencia no recuperable al registrar Tema.';

END$$

DELIMITER ;

/* ============================================================================================
   SECCIÓN: CONSULTAS ESPECÍFICAS (PARA EDICIÓN / DETALLE)
   ============================================================================================
   Estas rutinas son clave para la UX. No solo devuelven el dato pedido, sino todo el 
   contexto necesario para que el formulario de edición se autocomplete correctamente.
   ============================================================================================ */
   
   /* ============================================================================================
   PROCEDIMIENTO: SP_ConsultarTemaCapacitacionEspecifico
   ============================================================================================
   
   1. OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   --------------------------------------
   Recuperar la "Hoja de Vida" completa y técnica de un Tema de Capacitación (Curso) específico,
   identificado por su llave primaria (`Id_Cat_TemasCap`).

   CASOS DE USO (CONTEXTO DE UI):
   A) PRECARGA DE FORMULARIO DE EDICIÓN (UPDATE):
      - El sistema necesita los valores exactos (Raw Data) para llenar los inputs:
        * Input Texto: Nombre, Código.
        * Input Numérico: Duración (Horas).
        * Select/Dropdown: Tipo de Instrucción (Se necesita el ID del Padre para el 'value').

   B) VISUALIZACIÓN DE DETALLE (FICHA TÉCNICA):
      - Mostrar al administrador la información completa del curso, incluyendo a qué 
        categoría pedagógica pertenece (Nombre del Tipo).

   2. ARQUITECTURA DE DATOS (JOIN DE CONTEXTO)
   -------------------------------------------
   A diferencia de una consulta plana, aquí realizamos un `LEFT JOIN` con `Cat_Tipos_Instruccion_Cap`.
   
   ¿Por qué LEFT JOIN?
   - Robustez: Si por algún error de base de datos (manipulación manual) el Tipo de Instrucción
     asignado fue borrado físicamente, queremos seguir viendo el Curso (con el Tipo en NULL)
     para poder corregirlo, en lugar de que el Curso se vuelva invisible (Ghost Record).

   3. ESTRATEGIA DE SEGURIDAD (DEFENSIVE PROGRAMMING)
   --------------------------------------------------
   - Fail Fast: Validamos ID nulo o negativo al inicio.
   - Verificación de Existencia: Comprobamos si el tema existe antes de intentar traer datos,
     permitiendo diferenciar un error de red de un error 404 real.
   - Visibilidad Total: NO filtramos por `Activo = 1`. Un administrador necesita acceso a 
     registros históricos/inactivos.

   4. DICCIONARIO DE DATOS (OUTPUT)
   --------------------------------
   Retorna una única fila con:
      - [Identidad]: Id_Tema, Codigo_Tema, Nombre_Tema.
      - [Contenido]: Descripcion_Tema, Duracion_Horas.
      - [Clasificación]: Id_Tipo_Instruccion (FK), Nombre_Tipo_Instruccion (Label visual).
      - [Control]: Estatus_Tema (Activo).
      - [Auditoría]: Fecha_Registro, Ultima_Modificacion.
   ============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ConsultarTemaCapacitacionEspecifico`$$
CREATE PROCEDURE `SP_ConsultarTemaCapacitacionEspecifico`(
    IN _Id_Tema INT -- Identificador único del Tema a consultar
)
BEGIN
    /* ========================================================================================
       BLOQUE 1: VALIDACIÓN DE ENTRADA (DEFENSIVE PROGRAMMING)
       Objetivo: Evitar desperdiciar recursos si el parámetro es basura.
       ======================================================================================== */
    IF _Id_Tema IS NULL OR _Id_Tema <= 0 THEN
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: El ID del Tema es inválido.';
    END IF;

    /* ========================================================================================
       BLOQUE 2: VERIFICACIÓN DE EXISTENCIA (FAIL FAST)
       Objetivo: Dar un mensaje de error semántico si el curso no existe.
       ======================================================================================== */
    IF NOT EXISTS (SELECT 1 FROM `Cat_Temas_Capacitacion` WHERE `Id_Cat_TemasCap` = _Id_Tema) THEN
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [404]: El Tema de Capacitación solicitado no existe o fue eliminado físicamente.';
    END IF;

    /* ========================================================================================
       BLOQUE 3: CONSULTA PRINCIPAL (DATA RETRIEVAL)
       Objetivo: Retornar el objeto de datos completo, enriquecido con el nombre del Padre.
       ======================================================================================== */
    SELECT 
        /* --- GRUPO A: DATOS DEL TEMA (HIJO) --- */
        `T`.`Id_Cat_TemasCap`        AS `Id_Tema`,
        `T`.`Codigo`                 AS `Codigo_Tema`,
        `T`.`Nombre`                 AS `Nombre_Tema`,
        `T`.`Descripcion`            AS `Descripcion_Tema`,
        `T`.`Duracion_Horas`         AS `Duracion_Horas`,
        
        /* --- GRUPO B: DATOS DE CLASIFICACIÓN (PADRE) --- */
        /* FK: Vital para precargar el Select de "Tipo de Instrucción" (ng-model / v-model) */
        `T`.`Fk_Id_CatTipoInstCap`   AS `Id_Tipo_Instruccion`, 
        
        /* Label: Contexto visual para mostrar al usuario sin hacer otra consulta */
        `Tipo`.`Nombre`              AS `Nombre_Tipo_Instruccion`,
        
        /* --- GRUPO C: METADATOS DE CONTROL --- */
        /* 1 = Activo, 0 = Inactivo (Para el switch de la UI) */
        `T`.`Activo`                 AS `Estatus_Tema`,
        
        /* --- GRUPO D: AUDITORÍA --- */
        `T`.`created_at`             AS `Fecha_Registro`,
        `T`.`updated_at`             AS `Ultima_Modificacion`
        
    FROM `Cat_Temas_Capacitacion` `T`
    
    /* LEFT JOIN: Usamos LEFT por seguridad. Si el Tipo de Instrucción fue borrado físicamente 
       (algo que no debería pasar pero prevenimos), aún devolvemos el Tema. */
    LEFT JOIN `Cat_Tipos_Instruccion_Cap` `Tipo` 
        ON `T`.`Fk_Id_CatTipoInstCap` = `Tipo`.`Id_CatTipoInstCap`
        
    WHERE `T`.`Id_Cat_TemasCap` = _Id_Tema
    LIMIT 1;

END$$

DELIMITER ;

/* ============================================================================================
   SECCIÓN: LISTADOS PARA DROPDOWNS (SOLO REGISTROS ACTIVOS)
   ============================================================================================
   Estas rutinas son consumidas por los formularios de captura (Frontend).
   Su objetivo es ofrecer al usuario solo las opciones válidas y vigentes para evitar errores.
   ============================================================================================ */

/* ============================================================================================
   PROCEDIMIENTO: SP_ListarTemasActivos
   ============================================================================================

   --------------------------------------------------------------------------------------------
   I. CONTEXTO OPERATIVO Y PROPÓSITO (THE "WHAT" & "FOR WHOM")
   --------------------------------------------------------------------------------------------
   [QUÉ ES]: 
   Es el motor de datos de "Alta Disponibilidad" diseñado para alimentar el componente visual 
   "Selector de Curso" (Select2/Dropdown) en los módulos de logística y programación.

   [EL PROBLEMA QUE RESUELVE]: 
   La gestión de catálogos heterogéneos (donde algunos registros tienen códigos técnicos y otros no)
   suele generar deuda técnica en la capa de base de datos al intentar formatear cadenas de texto.
   Este SP resuelve el problema entregando datos atómicos para que la UI decida la presentación.

   [SOLUCIÓN IMPLEMENTADA]:
   Una consulta directa, optimizada por índices y libre de lógica de presentación (Concat), 
   delegando la estética al cliente (Separation of Concerns).

   --------------------------------------------------------------------------------------------
   II. DICCIONARIO DE REGLAS DE NEGOCIO (BUSINESS RULES ENGINE)
   --------------------------------------------------------------------------------------------
   Las siguientes reglas son IMPERATIVAS y definen la lógica del `WHERE`:

   [RN-01] REGLA DE VIGENCIA OPERATIVA (SOFT DELETE CHECK)
      - Definición: "Solo lo que está activo es programable".
      - Implementación: Cláusula `WHERE Activo = 1`.
      - Impacto: Filtra automáticamente cursos históricos, obsoletos o dados de baja.

   [RN-02] ARQUITECTURA DE SEGURIDAD "KILL SWITCH" (INTEGRITY AT WRITE)
      - Definición: "La integridad del padre se garantiza en la escritura, no en la lectura".
      - Justificación Técnica: Se eliminó el `JOIN` con `Cat_Tipos_Instruccion_Cap`. Nos basamos en 
        la premisa de que el sistema de Bajas (Update) impide desactivar un Padre si tiene Hijos activos.
      - Beneficio: Reducción drástica de complejidad ciclomática y eliminación de overhead por Joins.

   [RN-03] ESTRATEGIA DE "RAW DATA" (PRESENTATION LAYER DELEGATION)
      - Definición: "La base de datos no maquilla datos".
      - Implementación: Se entregan `Codigo` y `Nombre` en columnas separadas.
      - Justificación: Evita problemas de `NULL` en concatenaciones SQL y permite al Frontend renderizar 
        componentes ricos (ej: Badges, Negritas, Tooltips) sin depender de un string pre-formateado.

   --------------------------------------------------------------------------------------------
   III. ANÁLISIS TÉCNICO Y RENDIMIENTO (PERFORMANCE SPECS)
   --------------------------------------------------------------------------------------------
   [A] COMPLEJIDAD ALGORÍTMICA: O(1) - INDEX SCAN
       Al eliminar los JOINS y filtrar únicamente por una columna booleana indexada (`Activo`), 
       el motor de base de datos realiza un acceso directo a las páginas de datos relevantes.

   [B] CARGA ÚTIL MÍNIMA (LEAN PAYLOAD)
       Se excluyen columnas de texto pesado (`Descripcion`, `created_at`). Solo viajan los bytes 
       estrictamente necesarios para construir el objeto `<option value="id">label</option>`.

   --------------------------------------------------------------------------------------------
   IV. CONTRATO DE INTERFAZ (OUTPUT API)
   --------------------------------------------------------------------------------------------
   Retorna un arreglo JSON estricto:
      1. `Id_Tema` (INT): Valor relacional (Foreign Key).
      2. `Codigo` (STRING | NULL): Metadato técnico. Puede ser nulo en registros legacy.
      3. `Nombre` (STRING): Etiqueta visual principal para el humano.
   ============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ListarTemasActivos`$$

CREATE PROCEDURE `SP_ListarTemasActivos`()
BEGIN
    /* ========================================================================================
       SECCIÓN 1: PROYECCIÓN DE DATOS (SELECT)
       Define qué datos viajan a la red. Se aplica estrategia "Raw Data".
       ======================================================================================== */
    SELECT 
        /* [DATO CRÍTICO] IDENTIFICADOR DE SISTEMA
           Este campo es invisible para el usuario pero vital para el sistema.
           Se usará en el `INSERT INTO Programacion (Fk_Id_Tema)...` */
        `Id_Cat_TemasCap`  AS `Id_Tema`,
        
        /* [VECTOR VISUAL 1] CÓDIGO INTERNO (RAW)
           Se envía el dato crudo sin procesar. 
           Permite al Frontend decidir si lo muestra, lo oculta o lo formatea condicionalmente. 
           Ejemplo UI: <span class="badge badge-gray">{{ item.Codigo }}</span> */
        `Codigo`,
        
        /* [VECTOR VISUAL 2] NOMBRE DESCRIPTIVO
           La etiqueta principal para la lectura humana y el ordenamiento alfabético. */
        `Nombre`
        
        /* ------------------------------------------------------------------------------------
           COLUMNA DE ETIQUETA (LABEL)
           Formato "Humanizado" para el usuario final. 
           Ejemplo Visual: "SEG-001 - SEGURIDAD INDUSTRIAL BÁSICA"
           ------------------------------------------------------------------------------------ */
        -- CONCAT(`T`.`Codigo`, ' - ', `T`.`Nombre`) AS `Nombre_Completo`
        
        /* ------------------------------------------------------------------------------------
           METADATOS DE SOPORTE (DATA ATTRIBUTES)
           Información auxiliar para lógica de frontend (ej: sumar horas en un calendario).
           ------------------------------------------------------------------------------------ */
        -- `T`.`Duracion_Horas`
        
    /* ========================================================================================
       SECCIÓN 2: ORIGEN DE DATOS (FROM)
       Acceso directo a la tabla física sin intermediarios.
       ======================================================================================== */
    FROM 
        `Cat_Temas_Capacitacion`
        
    /* ----------------------------------------------------------------------------------------
       INNER JOIN: EL CANDADO JERÁRQUICO
       Unimos con la tabla de Tipos para validar el estado del padre.
       Si el Tipo no existe o no cumple el WHERE, la fila del Tema se descarta.
       ---------------------------------------------------------------------------------------- */
    /*LEFT JOIN `Cat_Tipos_Instruccion_Cap` `Tipo` 
        ON `T`.`Fk_Id_CatTipoInstCap` = `Tipo`.`Id_CatTipoInstCap`*/
                
    /* ========================================================================================
       SECCIÓN 3: MOTOR DE REGLAS DE NEGOCIO (WHERE)
       Filtro de alta velocidad sobre índice booleano.
       ======================================================================================== */
    WHERE 
        /* [REGLA 1] VIGENCIA OPERATIVA
           Solo se listan los recursos marcados como disponibles para nuevas operaciones.
           Confiamos en el Kill Switch para la integridad del padre (sin JOIN). */
        `Activo` = 1
        
    /* ========================================================================================
       SECCIÓN 4: ORDENAMIENTO (UX)
       ======================================================================================== */
    /* ESTANDARIZACIÓN VISUAL:
       Orden alfabético A-Z por Nombre para facilitar la búsqueda en listas largas. */
    ORDER BY 
        `Nombre` ASC;

END$$

DELIMITER ;

/* ============================================================================================
   SECCIÓN: LISTADOS PARA ADMINISTRACIÓN (TABLAS CRUD)
   ============================================================================================
   Estas rutinas son consumidas exclusivamente por los Paneles de Control (Grid/Tabla de Mantenimiento).
   Su objetivo es dar visibilidad total sobre el catálogo para auditoría, gestión y corrección.
   ============================================================================================ */

/* ============================================================================================
   PROCEDIMIENTO: SP_ListarTemasAdmin
   ============================================================================================
   
   1. OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   --------------------------------------
   Proveer el inventario maestro y completo de los "Temas de Capacitación" para alimentar el
   Grid Principal del Módulo de Administración.
   
   Permite al administrador:
     - Auditar la totalidad de cursos creados (Histórico y Actual).
     - Identificar cursos "huérfanos" (cuyo Tipo de Instrucción fue eliminado).
     - Gestionar el ciclo de vida (Reactivar cursos dados de baja).

   2. ARQUITECTURA DE DATOS (VIEW CONSUMPTION PATTERN)
   ---------------------------------------------------
   Este procedimiento implementa el patrón de "Abstracción de Lectura" al consumir la vista
   `Vista_Cat_Temas_Capacitacion`.
   
   Ventajas Técnicas:
     - Desacoplamiento: Si cambia la estructura de la tabla física, la vista absorbe el impacto
       y este SP no necesita ser recompilado.
     - Estandarización: La vista ya entrega los nombres de columnas "limpios" y los JOINs (LEFT)
       necesarios para mostrar datos aunque tengan integridad parcial.

   3. DIFERENCIA CRÍTICA CON EL DROPDOWN (VISIBILIDAD)
   ---------------------------------------------------
   A diferencia de `SP_ListarTemasActivos`, aquí NO EXISTE la cláusula `WHERE Activo = 1`.
   
   Justificación:
     - En Administración, "Ocultar" es "Perder". Un registro inactivo (`Estatus_Tema = 0`)
       debe ser visible para poder editarlo o reactivarlo. Si lo ocultamos aquí, sería
       imposible recuperarlo sin acceso directo a la base de datos.

   4. ESTRATEGIA DE ORDENAMIENTO (UX PRIORITY)
   -------------------------------------------
   El ordenamiento está diseñado para la eficiencia administrativa:
     1. Prioridad Operativa (Estatus DESC): Los registros VIGENTES (1) aparecen arriba.
        Los obsoletos (0) se van al fondo.
     2. Orden Alfabético (Nombre ASC): Dentro de cada grupo, se ordenan A-Z.
   ============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ListarTemasAdmin`$$

CREATE PROCEDURE `SP_ListarTemasAdmin`()
BEGIN
    /* ========================================================================================
       BLOQUE ÚNICO: CONSULTA MAESTRA SOBRE LA VISTA
       No requiere parámetros ni validaciones previas al ser una lectura global.
       ======================================================================================== */
    
    SELECT 
        /* Proyección total de la Vista Maestra.
           Incluye: ID, Códigos, Nombres, Descripciones, Duración, Nombre del Tipo, Estatus. */
        * FROM 
        `Vista_Temas_Capacitacion`
    
    /* ========================================================================================
       ORDENAMIENTO ESTRATÉGICO
       Optimizamos la presentación para el usuario administrador.
       ======================================================================================== */
    ORDER BY 
        `Estatus_Tema` DESC,  -- 1º: Los activos arriba (Prioridad de atención)
        `Nombre_Tema` ASC;    -- 2º: Orden alfabético para búsqueda rápida

END$$

DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_EditarTemaCapacitacion
   ============================================================================================

   --------------------------------------------------------------------------------------------
   I. VISIÓN GENERAL Y OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   --------------------------------------------------------------------------------------------
   [QUÉ ES]:
   Es el motor transaccional encargado de modificar los atributos técnicos y pedagógicos de un
   "Tema de Capacitación" (Curso) existente en el catálogo.

   [ALCANCE]:
   Permite la actualización de:
     - Identidad: Código (Clave Única) y Nombre (Clave Semántica).
     - Contenido: Descripción y Duración (Carga Horaria).
     - Clasificación: Reasignación a otro "Tipo de Instrucción" (Padre).

   --------------------------------------------------------------------------------------------
   II. REGLAS DE VALIDACIÓN ESTRICTA (HARD CONSTRAINTS)
   --------------------------------------------------------------------------------------------
   [RN-01] INTEGRIDAD DE DATOS (MANDATORY FIELDS):
      - Regla: "Todo o Nada" (excepto descripción).
      - Campos Obligatorios: Código, Nombre, Duración (>0) y Tipo de Instrucción.
      - Justificación: Un curso sin código o con duración cero es inoperable para la logística.

   [RN-02] IDENTIDAD UNÍVOCA (EXCLUSIÓN PROPIA):
      - Regla: El nuevo Código o Nombre no deben chocar con OTROS registros (`Id <> _Id_Tema`).
      - Excepción: Se permite que el registro coincida consigo mismo (Idempotencia).

   [RN-03] INTEGRIDAD JERÁRQUICA (PARENT VALIDATION):
      - Si se cambia el `Id_TipoInst`, el nuevo Padre debe existir y estar ACTIVO (`Activo=1`).
      - Esto evita mover un curso activo hacia una categoría obsoleta o eliminada.

   --------------------------------------------------------------------------------------------
   III. ARQUITECTURA DE CONCURRENCIA (PESSIMISTIC LOCKING PATTERN)
   --------------------------------------------------------------------------------------------
   Para prevenir la corrupción de datos y la "Edición Fantasma" (Lost Update):

      - FASE 1 (Bloqueo): Al inicio, ejecutamos `SELECT ... FOR UPDATE` sobre el ID del Tema.
      - FASE 2 (Congelamiento): La fila queda bloqueada para esta sesión. Nadie más puede
        editarla o eliminarla hasta que terminemos.
      - FASE 3 (Validación Segura): Al tener el bloqueo, nuestras verificaciones de duplicidad
        son 100% fiables (excepto inserciones fantasma milimétricas, cubiertas por el Handler 1062).

   --------------------------------------------------------------------------------------------
   IV. IDEMPOTENCIA (OPTIMIZACIÓN DE RECURSOS)
   --------------------------------------------------------------------------------------------
   [MOTOR DE DETECCIÓN DE CAMBIOS]:
   - Antes de escribir en disco, comparamos el "Snapshot" (Estado Actual) vs "Inputs" (Nuevos).
   - Si no hay diferencias matemáticas, retornamos éxito ('SIN_CAMBIOS') inmediatamente.
   - Beneficio: Ahorro de I/O y preservación de la fecha de auditoría `updated_at`.

   --------------------------------------------------------------------------------------------
   V. CONTRATO DE SALIDA (OUTPUT CONTRACT)
   --------------------------------------------------------------------------------------------
   Retorna un resultset con:
      - Mensaje: Feedback descriptivo.
      - Accion: 'ACTUALIZADA', 'SIN_CAMBIOS', 'CONFLICTO'.
      - Id_Tema: El identificador del recurso.
   ============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_EditarTemaCapacitacion`$$

CREATE PROCEDURE `SP_EditarTemaCapacitacion`(
    /* -----------------------------------------------------------------
       PARÁMETROS DE ENTRADA (INPUTS)
       Recibimos los datos crudos del formulario.
       ----------------------------------------------------------------- */
    IN _Id_Tema         INT,           -- [OBLIGATORIO] PK del registro a editar
    IN _Codigo          VARCHAR(50),   -- [OBLIGATORIO] Nueva clave única
    IN _Nombre          VARCHAR(255),  -- [OBLIGATORIO] Nuevo nombre único
    IN _Descripcion     VARCHAR(255),  -- [OPCIONAL] Nueva descripción
    IN _Duracion_Horas  SMALLINT,      -- [OBLIGATORIO] Nueva duración (> 0)
    IN _Id_TipoInst     INT            -- [OBLIGATORIO] Nuevo Padre (FK)
)
THIS_PROC: BEGIN
    
    /* ================================================================================================
       BLOQUE 0: DECLARACIÓN DE VARIABLES DE ESTADO Y CONTEXTO
       Propósito: Inicializar los contenedores que gestionarán la lógica del procedimiento.
       ================================================================================================ */
    
    /* [Snapshots]: Estado actual del registro antes de la edición */
    DECLARE v_Cod_Act     VARCHAR(50);
    DECLARE v_Nom_Act     VARCHAR(255);
    DECLARE v_Desc_Act    VARCHAR(255);
    DECLARE v_Dur_Act     SMALLINT;
    DECLARE v_Tipo_Act    INT;
    
    /* [Variables de Validación Jerárquica] */
    DECLARE v_Padre_Activo TINYINT(1);

    /* [Variables de Conflicto]: Para pre-checks de duplicidad */
    DECLARE v_Id_Conflicto INT DEFAULT NULL;
    DECLARE v_Campo_Error  VARCHAR(20) DEFAULT NULL;

    /* [Bandera de Control]: Semáforo para detectar errores de concurrencia (Error 1062) */
    DECLARE v_Dup          TINYINT(1) DEFAULT 0;

    /* ================================================================================================
       BLOQUE 1: HANDLERS (MANEJO ROBUSTO DE EXCEPCIONES)
       Propósito: Garantizar una salida limpia ante errores técnicos o de concurrencia.
       ================================================================================================ */
    
    /* 1.1 HANDLER DE DUPLICIDAD (Error 1062)
       Objetivo: Capturar colisiones de Unique Key en el último milisegundo (Race Condition).
       Acción: No abortamos. Encendemos la bandera v_Dup = 1 para manejar el conflicto controladamente. */
    DECLARE CONTINUE HANDLER FOR 1062 SET v_Dup = 1;

    /* 1.2 HANDLER GENÉRICO (SQLEXCEPTION)
       Objetivo: Capturar fallos técnicos graves (Desconexión, Disco lleno).
       Acción: Abortar inmediatamente (ROLLBACK) y propagar el error. */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; 
    END;

    /* ================================================================================================
       BLOQUE 2: SANITIZACIÓN Y VALIDACIÓN PREVIA (FAIL FAST)
       Propósito: Rechazar datos inválidos antes de consumir recursos de transacción.
       ================================================================================================ */
    
    /* 2.1 LIMPIEZA DE DATOS (TRIM & NULLIF) */
    SET _Codigo      = NULLIF(TRIM(_Codigo), '');
    SET _Nombre      = NULLIF(TRIM(_Nombre), '');
    SET _Descripcion = NULLIF(TRIM(_Descripcion), '');
    
    /* Sanitización numérica: Convertir NULL o negativos a 0 para validación lógica */
    SET _Duracion_Horas = IFNULL(_Duracion_Horas, 0);

    /* 2.2 VALIDACIÓN DE OBLIGATORIEDAD (REGLAS DE NEGOCIO) */
    
    IF _Id_Tema IS NULL OR _Id_Tema <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: Identificador de Tema inválido.';
    END IF;

    IF _Codigo IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN [400]: El CÓDIGO es obligatorio.';
    END IF;

    IF _Nombre IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN [400]: El NOMBRE es obligatorio.';
    END IF;

    IF _Duracion_Horas <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN [400]: La DURACIÓN debe ser mayor a 0 horas.';
    END IF;

    IF _Id_TipoInst IS NULL OR _Id_TipoInst <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN [400]: Debe seleccionar un TIPO DE INSTRUCCIÓN válido.';
    END IF;

    /* ================================================================================================
       BLOQUE 3: INICIO DE TRANSACCIÓN Y BLOQUEO PESIMISTA
       Propósito: Adquirir exclusividad sobre el registro a editar.
       ================================================================================================ */
    START TRANSACTION;

    /* ------------------------------------------------------------------------------------------------
       PASO 3.1: LEER Y BLOQUEAR EL REGISTRO ACTUAL
       
       Objetivo: Obtener los valores actuales y congelar la fila.
       Mecánica: `FOR UPDATE` asegura que si otro admin intenta editar esto al mismo tiempo,
       deberá esperar a que terminemos.
       ------------------------------------------------------------------------------------------------ */
    SELECT 
        `Codigo`, `Nombre`, `Descripcion`, `Duracion_Horas`, `Fk_Id_CatTipoInstCap`
    INTO 
        v_Cod_Act, v_Nom_Act, v_Desc_Act, v_Dur_Act, v_Tipo_Act
    FROM `Cat_Temas_Capacitacion`
    WHERE `Id_Cat_TemasCap` = _Id_Tema
    FOR UPDATE; -- <--- BLOQUEO DE ESCRITURA AQUÍ

    /* Safety Check: Si al bloquear descubrimos que el registro fue borrado por otro usuario */
    IF v_Cod_Act IS NULL THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR CRÍTICO [404]: El Tema que intenta editar ya no existe (fue eliminado externamente).';
    END IF;

    /* ------------------------------------------------------------------------------------------------
       PASO 3.2: DETECCIÓN DE IDEMPOTENCIA (SIN CAMBIOS)
       
       Objetivo: Evitar escrituras si el usuario guardó lo mismo.
       Lógica: Comparamos campo por campo. Usamos `<=>` para la descripción (nullable).
       ------------------------------------------------------------------------------------------------ */
    IF (v_Cod_Act = _Codigo) 
       AND (v_Nom_Act = _Nombre) 
       AND (v_Desc_Act <=> _Descripcion)
       AND (v_Dur_Act = _Duracion_Horas)
       AND (v_Tipo_Act = _Id_TipoInst) THEN
        
        COMMIT; -- Liberamos locks inmediatamente
        
        /* Retorno anticipado para ahorrar I/O y notificar al Frontend */
        SELECT 'AVISO: No se detectaron cambios en la información.' AS Mensaje, 'SIN_CAMBIOS' AS Accion, _Id_Tema AS Id_Tema;
        LEAVE THIS_PROC;
    END IF;

    /* ================================================================================================
       BLOQUE 4: VALIDACIONES DE NEGOCIO (BAJO PROTECCIÓN DE LOCKS)
       ================================================================================================ */

    /* 4.1 VALIDACIÓN JERÁRQUICA (SOLO SI CAMBIÓ EL PADRE)
       Si el usuario seleccionó un Tipo de Instrucción diferente al actual, verificamos que sea válido y activo. */
    IF v_Tipo_Act <> _Id_TipoInst THEN
        SET v_Padre_Activo = NULL;
        
        /* Consultamos el catálogo padre */
        SELECT `Activo` INTO v_Padre_Activo
        FROM `Cat_Tipos_Instruccion_Cap`
        WHERE `Id_CatTipoInstCap` = _Id_TipoInst; 

        IF v_Padre_Activo IS NULL THEN
             ROLLBACK;
             SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE INTEGRIDAD [404]: El nuevo Tipo de Instrucción seleccionado no existe.';
        END IF;

        IF v_Padre_Activo = 0 THEN
             ROLLBACK;
             SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [409]: El nuevo Tipo de Instrucción seleccionado está INACTIVO.';
        END IF;
    END IF;

    /* 4.2 VALIDACIÓN FINAL DE UNICIDAD (PRE-UPDATE CHECK)
       Verificamos si existen duplicados REALES. Al tener el registro propio bloqueado, 
       validamos contra el resto de la tabla. */
    
    /* A) Validación por CÓDIGO (si cambió) */
    IF v_Cod_Act <> _Codigo THEN
        SET v_Id_Conflicto = NULL;
        SELECT `Id_Cat_TemasCap` INTO v_Id_Conflicto
        FROM `Cat_Temas_Capacitacion`
        WHERE `Codigo` = _Codigo AND `Id_Cat_TemasCap` <> _Id_Tema
        LIMIT 1
        FOR UPDATE; -- Bloqueo preventivo al conflicto

        IF v_Id_Conflicto IS NOT NULL THEN
            ROLLBACK;
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'CONFLICTO DE DATOS [409]: El CÓDIGO ingresado ya pertenece a otro Tema.';
        END IF;
    END IF;

    /* B) Validación por NOMBRE (si cambió) */
    IF v_Nom_Act <> _Nombre THEN
        SET v_Id_Conflicto = NULL;
        SELECT `Id_Cat_TemasCap` INTO v_Id_Conflicto
        FROM `Cat_Temas_Capacitacion`
        WHERE `Nombre` = _Nombre AND `Id_Cat_TemasCap` <> _Id_Tema
        LIMIT 1
        FOR UPDATE; -- Bloqueo preventivo al conflicto

        IF v_Id_Conflicto IS NOT NULL THEN
            ROLLBACK;
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'CONFLICTO DE DATOS [409]: El NOMBRE ingresado ya pertenece a otro Tema.';
        END IF;
    END IF;

    /* ================================================================================================
       BLOQUE 5: PERSISTENCIA Y FINALIZACIÓN (UPDATE)
       Propósito: Aplicar los cambios una vez superadas todas las barreras de seguridad.
       ================================================================================================ */
    
    SET v_Dup = 0; -- Resetear bandera de error antes de escribir

    UPDATE `Cat_Temas_Capacitacion`
    SET 
        `Codigo`               = _Codigo,
        `Nombre`               = _Nombre,
        `Descripcion`          = _Descripcion,
        `Duracion_Horas`       = _Duracion_Horas,
        `Fk_Id_CatTipoInstCap` = _Id_TipoInst,
        `updated_at`           = NOW() -- Auditoría automática
    WHERE 
        `Id_Cat_TemasCap` = _Id_Tema;

    /* ================================================================================================
       BLOQUE 6: MANEJO DE COLISIÓN TARDÍA (RECUPERACIÓN DE ERROR 1062)
       Propósito: Gestionar el caso extremo donde un insert fantasma ocurre justo antes del update.
       ================================================================================================ */
    IF v_Dup = 1 THEN
        ROLLBACK;
        
        /* Diagnóstico Post-Mortem para el usuario */
        SET v_Campo_Error = 'DESCONOCIDO';
        SET v_Id_Conflicto = NULL;

        /* ¿Fue conflicto de Código? */
        SELECT `Id_Cat_TemasCap` INTO v_Id_Conflicto FROM `Cat_Temas_Capacitacion` 
        WHERE `Codigo` = _Codigo AND `Id_Cat_TemasCap` <> _Id_Tema LIMIT 1;
        
        IF v_Id_Conflicto IS NOT NULL THEN
            SET v_Campo_Error = 'CODIGO';
        ELSE
            /* Entonces fue conflicto de Nombre */
            SELECT `Id_Cat_TemasCap` INTO v_Id_Conflicto FROM `Cat_Temas_Capacitacion` 
            WHERE `Nombre` = _Nombre AND `Id_Cat_TemasCap` <> _Id_Tema LIMIT 1;
            SET v_Campo_Error = 'NOMBRE';
        END IF;

        SELECT 'Error de Concurrencia: Conflicto detectado al guardar.' AS Mensaje, 
               'CONFLICTO' AS Accion, 
               v_Campo_Error AS Campo, 
               v_Id_Conflicto AS Id_Conflicto;
        LEAVE THIS_PROC;
    END IF;

    /* ================================================================================================
       BLOQUE 7: CONFIRMACIÓN EXITOSA
       Propósito: Confirmar la transacción y notificar al cliente.
       ================================================================================================ */
    COMMIT;
    
    SELECT 'ÉXITO: Tema actualizado correctamente.' AS Mensaje, 
           'ACTUALIZADA' AS Accion, 
           _Id_Tema AS Id_Tema;

END$$

DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_CambiarEstatusTemaCapacitacion
   ============================================================================================

   --------------------------------------------------------------------------------------------
   I. CONTEXTO Y PROPÓSITO DEL NEGOCIO (THE "WHAT" & "WHY")
   --------------------------------------------------------------------------------------------
   [QUÉ ES]:
   Es el mecanismo de control de ciclo de vida para los "Temas de Capacitación" (Cursos).
   Permite alternar entre dos estados operativos:
     - ACTIVO (1): El curso es visible y seleccionable para nuevas programaciones.
     - INACTIVO (0): El curso se oculta (Baja Lógica) pero se preserva para auditoría histórica.

   [EL PROBLEMA DE LA INTEGRIDAD OPERATIVA]:
   No podemos retirar del catálogo un curso que se va a impartir mañana (Programado) o que se
   está impartiendo hoy (En Curso). Hacerlo dejaría a la operación sin referencia válida.
   
   Sin embargo, SÍ debemos permitir retirar cursos obsoletos que ya fueron impartidos en el 
   pasado (Finalizados), para limpiar el catálogo sin perder el historial.

   --------------------------------------------------------------------------------------------
   II. REGLAS DE BLINDAJE (KILL SWITCHES INTELIGENTES)
   --------------------------------------------------------------------------------------------
   
   [RN-01] CANDADO DE DEPENDENCIA OPERATIVA (AL DESACTIVAR):
      - Definición: "Solo se puede archivar lo que no está en uso activo".
      - Mecanismo Técnico: El sistema consulta la bandera `Es_Final` del estatus actual.
        Si `Es_Final = 0` (Operativo), se bloquea la desactivación.
      
      - Lógica de Negocio (Referencia de Configuración):
        Si se intenta DESACTIVAR (0), el sistema escanea `DatosCapacitaciones`.
        Los estatus se clasifican conceptualmente de la siguiente manera:

      - Estatus Bloqueantes (Conflictos - Es_Final = 0):
          * 1 (PROGRAMADO): Compromiso futuro.
          * 2 (POR INICIAR): Inminencia operativa.
          * 3 (EN CURSO): Ejecución en tiempo real.
          * 5 (EN EVALUACIÓN): Proceso administrativo pendiente.
          * 9 (REPROGRAMADO): Compromiso reagendado.
      
      - Estatus NO Bloqueantes (Permitidos - Es_Final = 1):
          * 4 (FINALIZADO), 6 (CANCELADO), 7 (SUSPENDIDO), 8 (DESERTO).
      
      - Acción: Si se detecta un curso en estatus bloqueante, se ABORTA con error 409.

   [RN-02] CANDADO JERÁRQUICO (AL REACTIVAR):
      - Regla: "Un hijo no puede vivir si el padre está muerto".
      - Acción: Si se intenta REACTIVAR (1), verificamos que el `Tipo de Instrucción` (Padre)
        esté ACTIVO. Si no, se bloquea.

   --------------------------------------------------------------------------------------------
   III. ESPECIFICACIÓN TÉCNICA
   --------------------------------------------------------------------------------------------
   - TIPO: Transacción ACID con Aislamiento Serializable.
   - ESTRATEGIA: Bloqueo Pesimista (`FOR UPDATE`) para evitar condiciones de carrera.
   ============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_CambiarEstatusTemaCapacitacion`$$

CREATE PROCEDURE `SP_CambiarEstatusTemaCapacitacion`(
    IN _Id_Tema        INT,        -- [OBLIGATORIO] El Curso a modificar (PK)
    IN _Nuevo_Estatus  TINYINT     -- [OBLIGATORIO] 1 = Activar, 0 = Desactivar
)
THIS_PROC: BEGIN
    
    /* ========================================================================================
       BLOQUE 0: VARIABLES DE ENTORNO
       ======================================================================================== */
    /* Snapshot del estado actual */
    DECLARE v_Activo_Actual      TINYINT DEFAULT NULL;
    DECLARE v_Nombre_Tema        VARCHAR(255) DEFAULT NULL;
    DECLARE v_Id_TipoInst        INT DEFAULT NULL;
    
    /* Variables para validaciones */
    DECLARE v_Tipo_Activo        TINYINT DEFAULT NULL;
    
    /* Variables de Diagnóstico Operativo */
    DECLARE v_Curso_Conflictivo  VARCHAR(50) DEFAULT NULL;
    DECLARE v_Estatus_Conflicto  VARCHAR(255) DEFAULT NULL;
    
    /* ========================================================================================
       BLOQUE 1: HANDLERS (SEGURIDAD TÉCNICA)
       ======================================================================================== */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; 
    END;
    
    /* ========================================================================================
       BLOQUE 2: VALIDACIONES BÁSICAS (FAIL FAST)
       ======================================================================================== */
    IF _Id_Tema IS NULL OR _Id_Tema <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: ID de Tema inválido.';
    END IF;

    IF _Nuevo_Estatus NOT IN (0, 1) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: El estatus solo puede ser 0 o 1.';
    END IF;

    /* ========================================================================================
       BLOQUE 3: CANDADO OPERATIVO (INTEGRACIÓN CON CAPACITACIONES)
       Propósito: Validar que el tema no sea esencial para operaciones VIVAS.
       Condición: Solo se ejecuta si la intención es APAGAR (0) el tema.
       ======================================================================================== */
    IF _Nuevo_Estatus = 0 THEN
        
        /* Buscamos si existe alguna capacitación VIGENTE que use este tema y esté en una fase activa.
           Usamos JOINs para obtener nombres legibles para el error. */
        
        SELECT 
            C.Numero_Capacitacion,
            EC.Nombre -- Nombre del Estatus (ej: "EN CURSO")
        INTO 
            v_Curso_Conflictivo,
            v_Estatus_Conflicto
        FROM `Capacitaciones` C
        /* Unimos con DatosCapacitaciones para ver el historial activo */
        INNER JOIN `DatosCapacitaciones` DC ON C.Id_Capacitacion = DC.Fk_Id_Capacitacion
        /* Unimos con el Catálogo para leer la regla de negocio (Es_Final) */
        INNER JOIN `Cat_Estatus_Capacitacion` EC ON DC.Fk_Id_CatEstCap = EC.Id_CatEstCap
        WHERE 
            C.Fk_Id_Cat_TemasCap = _Id_Tema
            AND C.Activo = 1  -- La capacitación general está activa
            AND DC.Activo = 1 -- El registro de detalle es el vigente
			/* LISTA NEGRA DE ESTATUS (NO SE PUEDE BORRAR SI ESTÁ AQUÍ):
               1 = Programado
               2 = Por Iniciar
               3 = En Curso
               5 = En Evaluación
               9 = Reprogramado */
            -- AND DC.Fk_Id_CatEstCap IN (1, 2, 3, 5, 9)
            /* --- KILLSWITCH DINÁMICO (Soportado por la documentación de IDs arriba) --- */
            AND EC.Es_Final = 0 
        LIMIT 1;

        /* Si encontramos un conflicto, abortamos con un mensaje claro */
        IF v_Curso_Conflictivo IS NOT NULL THEN
            SET @MensajeError = CONCAT('CONFLICTO OPERATIVO [409]: No se puede desactivar el Tema. Está asignado a la capacitación activa "', v_Curso_Conflictivo, '" que se encuentra "', v_Estatus_Conflicto, '". Este estatus se considera operativo (No Final). Debe finalizar o cancelar esa capacitación primero.');
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = @MensajeError;
        END IF;

    END IF;

    /* ========================================================================================
       BLOQUE 4: INICIO DE TRANSACCIÓN Y BLOQUEO PESIMISTA
       ======================================================================================== */
    START TRANSACTION;

    /* ----------------------------------------------------------------------------------------
       PASO 4.1: LEER Y BLOQUEAR EL REGISTRO
       ----------------------------------------------------------------------------------------
       Adquirimos un "Write Lock" sobre la fila. Esto asegura serialización. */
    
    SELECT `Activo`, `Nombre`, `Fk_Id_CatTipoInstCap`
    INTO v_Activo_Actual, v_Nombre_Tema, v_Id_TipoInst
    FROM `Cat_Temas_Capacitacion`
    WHERE `Id_Cat_TemasCap` = _Id_Tema
    FOR UPDATE;

    /* Si no se encuentra, abortamos */
    IF v_Activo_Actual IS NULL THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [404]: El Tema solicitado no existe.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 4.2: IDEMPOTENCIA (SIN CAMBIOS)
       ---------------------------------------------------------------------------------------- */
    IF v_Activo_Actual = _Nuevo_Estatus THEN
        COMMIT;
        SELECT CONCAT('AVISO: El Tema "', v_Nombre_Tema, '" ya se encuentra en el estado solicitado.') AS Mensaje,
               'SIN_CAMBIOS' AS Accion,
               _Id_Tema AS Id_Tema,
               _Nuevo_Estatus AS Nuevo_Estatus;
        
        LEAVE THIS_PROC; 
    END IF;

    /* ========================================================================================
       BLOQUE 5: VALIDACIÓN JERÁRQUICA (SOLO AL REACTIVAR)
       ======================================================================================== */
    IF _Nuevo_Estatus = 1 THEN
        
        /* Solo validamos si tiene un Tipo asignado (no es huérfano) */
        IF v_Id_TipoInst IS NOT NULL THEN
            
            SELECT `Activo` INTO v_Tipo_Activo
            FROM `Cat_Tipos_Instruccion_Cap`
            WHERE `Id_CatTipoInstCap` = v_Id_TipoInst;

            /* Si el padre está inactivo, prohibimos la reactivación del hijo */
            IF v_Tipo_Activo = 0 THEN
                ROLLBACK;
                SIGNAL SQLSTATE '45000' 
                SET MESSAGE_TEXT = 'ERROR DE INTEGRIDAD [409]: No se puede reactivar este Tema porque su Categoría Padre (Tipo de Instrucción) está INACTIVA. Reactive la categoría primero.';
            END IF;
        END IF;
    END IF;
    
    
/* CODIGO LEGADO DE VALIDACION (Referencia)
    IF _Nuevo_Estatus = 1 THEN
        
        IF v_Id_TipoInst IS NOT NULL THEN
            
            SELECT `Activo` INTO v_Tipo_Activo
            FROM `Cat_Tipos_Instruccion_Cap`
            WHERE `Id_CatTipoInstCap` = v_Id_TipoInst;

             Si el padre está inactivo (0), se LANZA ERROR para detener el flujo 
            IF v_Tipo_Activo = 0 THEN
                ROLLBACK;
                SIGNAL SQLSTATE '45000' 
                SET MESSAGE_TEXT = 'ERROR DE INTEGRIDAD [409]: No se puede reactivar este Tema porque su Categoría Padre (Tipo de Instrucción) está INACTIVA. Reactive la categoría primero.';
            END IF;
        END IF;
    END IF;*/

    /* ========================================================================================
       BLOQUE 6: PERSISTENCIA (UPDATE)
       ======================================================================================== */
    UPDATE `Cat_Temas_Capacitacion`
    SET 
        `Activo`     = _Nuevo_Estatus,
        `updated_at` = NOW()
    WHERE 
        `Id_Cat_TemasCap` = _Id_Tema;

    /* ========================================================================================
       BLOQUE 7: CONFIRMACIÓN Y RESPUESTA
       ======================================================================================== */
    COMMIT;

    SELECT 
        CASE 
            WHEN _Nuevo_Estatus = 1 THEN CONCAT('ÉXITO: El Tema "', v_Nombre_Tema, '" ha sido REACTIVADO.')
            ELSE CONCAT('ÉXITO: El Tema "', v_Nombre_Tema, '" ha sido DESACTIVADO (Archivado).')
        END AS Mensaje,
        
        'ESTATUS_MODIFICADO' AS Accion,
        _Id_Tema AS Id_Tema,
        _Nuevo_Estatus AS Nuevo_Estatus;

END$$

DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_EliminarTemaCapacitacionFisico
   ============================================================================================
   
   --------------------------------------------------------------------------------------------
   I. PROPÓSITO Y OBJETIVO DE NEGOCIO (THE "WHAT" & "WHY")
   --------------------------------------------------------------------------------------------
   [QUÉ ES]:
   Es el mecanismo de "Destrucción Total" (Hard Delete) para un registro del catálogo de 
   Temas de Capacitación (Cursos).
   
   [ADVERTENCIA DE SEGURIDAD]:
   Esta operación es IRREVERSIBLE. Elimina físicamente la fila de la base de datos.
   Su uso está estrictamente restringido a tareas de **Saneamiento de Datos** (Data Cleansing)
   para corregir errores de captura inmediata (ej: se creó un curso duplicado por error y se
   borra al instante antes de usarse).

   [INTEGRIDAD REFERENCIAL - EL PROBLEMA DE LA "ORFANDAD"]:
   Si eliminamos un Tema (ej: "Soldadura") que fue utilizado en una capacitación hace 3 años,
   automáticamente corrompemos el historial de todos los empleados que tomaron ese curso.
   El reporte diría: "Juan Pérez tomó el curso NULL".
   
   Este SP previene esa corrupción mediante una estrategia de **Defensa en Profundidad**.

   --------------------------------------------------------------------------------------------
   II. ESTRATEGIA DE DEFENSA EN CAPAS (LAYERED DEFENSE)
   --------------------------------------------------------------------------------------------
   Para garantizar "Cero Orfandad", implementamos tres anillos de seguridad:

   [ANILLO 1] VALIDACIÓN DE EXISTENCIA (FAIL FAST):
      - Se rechazan IDs nulos o inexistentes antes de iniciar cualquier transacción costosa.

   [ANILLO 2] VALIDACIÓN DE NEGOCIO PROACTIVA (LOGIC GUARD):
      - Antes de intentar borrar, el SP realiza un escaneo forense en la tabla `Capacitaciones`.
      - REGLA DE ORO: Si existe **CUALQUIER** historial (Programado, Finalizado, Cancelado) 
        vinculado a este tema, la operación se ABORTA con un error 409 (Conflicto).
      - BENEFICIO: Provee un mensaje de error semántico y humano ("No se puede borrar porque tiene historial") 
        en lugar de un error técnico genérico.

   [ANILLO 3] VALIDACIÓN REACTIVA DE MOTOR (DATABASE CONSTRAINT):
      - Actúa como "Red de Seguridad" final.
      - Si existiera una tabla oculta (ej: `Material_Didactico`) que olvidamos validar manualmente, 
        el motor InnoDB bloqueará el `DELETE` disparando el error `1451` (Foreign Key Constraint Fails).
      - El SP captura este error, hace Rollback y entrega un mensaje controlado.

   --------------------------------------------------------------------------------------------
   III. ESPECIFICACIÓN TÉCNICA (ACID)
   --------------------------------------------------------------------------------------------
   - TIPO: Transacción Atómica.
   - BLOQUEO: Al ejecutar el `DELETE`, el motor InnoDB adquiere un **Bloqueo Exclusivo (X-Lock)**
     sobre la fila, asegurando que nadie más pueda leer o vincular este tema mientras se destruye.
   ============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_EliminarTemaCapacitacionFisico`$$

CREATE PROCEDURE `SP_EliminarTemaCapacitacionFisico`(
    /* -----------------------------------------------------------------
       PARÁMETROS DE ENTRADA
       ----------------------------------------------------------------- */
    IN _Id_Tema INT -- [OBLIGATORIO] Identificador único del registro a destruir (PK)
)
THIS_PROC: BEGIN
    
    /* ========================================================================================
       BLOQUE 0: VARIABLES DE DIAGNÓSTICO
       Propósito: Contenedores locales para los resultados de las pruebas de integridad.
       ======================================================================================== */
    
    /* [Semáforo de Dependencias]
       Almacena el resultado del escaneo en tablas hijas. 
       NULL = Limpio / NOT NULL = Tiene historial. */
    DECLARE v_Dependencias INT DEFAULT NULL;

    /* ========================================================================================
       BLOQUE 1: HANDLERS (MANEJO ROBUSTO DE EXCEPCIONES)
       Propósito: Asegurar que la transacción nunca quede abierta ante un error.
       ======================================================================================== */
    
    /* [1.1] HANDLER DE INTEGRIDAD REFERENCIAL (Error 1451 - MySQL FK Constraint)
       OBJETIVO: Actuar como "paracaídas" final.
       ESCENARIO: Intentamos borrar, pero el motor de BD detecta una FK activa en una tabla 
       desconocida o futura que apunta a este registro.
       ACCIÓN: Revertir todo (ROLLBACK) y avisar al usuario que la BD protegió el dato. */
    DECLARE EXIT HANDLER FOR 1451 
    BEGIN 
        ROLLBACK; 
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'BLOQUEO DE INTEGRIDAD (SISTEMA) [1451]: El registro está blindado por la base de datos porque existen referencias en otras tablas (posiblemente materiales o evaluaciones) que impiden su eliminación.'; 
    END;

    /* [1.2] HANDLER GENÉRICO (SQLEXCEPTION)
       OBJETIVO: Capturar fallos de infraestructura (Disco lleno, caída de red). */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; 
    END;

    /* ========================================================================================
       BLOQUE 2: VALIDACIONES PREVIAS (FAIL FAST PATTERN)
       Propósito: Validar la calidad de los datos de entrada antes de consumir recursos.
       ======================================================================================== */
    
    /* 2.1 Validación de Input */
    IF _Id_Tema IS NULL OR _Id_Tema <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: El Identificador del Tema es inválido.';
    END IF;

    /* 2.2 Validación de Existencia
       Verificamos si el registro existe antes de gastar recursos buscando sus dependencias. */
    IF NOT EXISTS (SELECT 1 FROM `Cat_Temas_Capacitacion` WHERE `Id_Cat_TemasCap` = _Id_Tema) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [404]: El Tema de Capacitación que intenta eliminar no existe.';
    END IF;

    /* ========================================================================================
       BLOQUE 3: CANDADO DE NEGOCIO (VALIDACIÓN PROACTIVA DE DEPENDENCIAS)
       Propósito: Proteger la coherencia de los datos operativos (Capacitaciones).
       ======================================================================================== */
    
    /* [ANÁLISIS FORENSE DE CAPACITACIONES]
       Objetivo: Proteger el Historial Operativo.
       Buscamos en la tabla `Capacitaciones` (Módulo Siguiente).
       
       CRITERIO CRÍTICO: NO filtramos por `Activo = 1`.
       Razón: Si se impartió un curso de "Soldadura" hace 3 años y hoy está finalizado/inactivo,
       ese registro histórico es SAGRADO para las auditorías. Borrar el Tema rompería la 
       integridad referencial de ese reporte histórico. */
    
    SELECT 1 INTO v_Dependencias
    FROM `Capacitaciones`
    WHERE `Fk_Id_Cat_TemasCap` = _Id_Tema
    LIMIT 1; -- Optimización: Con encontrar uno solo es suficiente para detener el proceso.

    /* [EVALUACIÓN DEL BLOQUEO] */
    IF v_Dependencias IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'BLOQUEO DE NEGOCIO [409]: No es posible eliminar este Tema porque existen CAPACITACIONES (Programadas, Finalizadas o Históricas) asociadas a él. La eliminación física rompería el historial de la empresa. Utilice la opción "Desactivar" (Baja Lógica) en su lugar.';
    END IF;

    /*  */

    /* ========================================================================================
       BLOQUE 4: EJECUCIÓN DESTRUCTIVA (ZONA CRÍTICA)
       Propósito: Ejecutar el borrado persistente de manera atómica.
       ======================================================================================== */
    START TRANSACTION;

    /* 4.1 Ejecución del Borrado Físico.
       En este punto, el motor InnoDB adquiere un BLOQUEO EXCLUSIVO (X-LOCK) sobre la fila.
       Esto asegura que nadie más pueda leer o asignar este tema durante el microsegundo 
       que dura la destrucción. */
    DELETE FROM `Cat_Temas_Capacitacion` 
    WHERE `Id_Cat_TemasCap` = _Id_Tema;

    /* 4.2 Confirmación.
       Si llegamos aquí sin que salten los Handlers (especialmente el 1451),
       significa que el registro estaba limpio y fue destruido correctamente. */
    COMMIT;

    /* ========================================================================================
       BLOQUE 5: CONFIRMACIÓN Y RESPUESTA
       Propósito: Informar al Frontend/API que la operación concluyó exitosamente.
       ======================================================================================== */
    SELECT 
        'Registro eliminado permanentemente de la base de datos.' AS Mensaje, 
        'ELIMINADA' AS Accion,
        _Id_Tema AS Id_Tema;

END$$

DELIMITER ;