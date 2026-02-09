USE `PICADE`;

/* ------------------------------------------------------------------------------------------------------ */
/* CREACION DE VISTAS Y PROCEDIMIENTOS DE ALMACENADO PARA LA BASE DE DATOS                                */
/* ------------------------------------------------------------------------------------------------------ */

/* ======================================================================================================
   VIEW: Vista_Estatus_Participante
   ======================================================================================================
   
   1. OBJETIVO TÉCNICO Y DE NEGOCIO (BUSINESS GOAL)
   ------------------------------------------------
   Esta vista constituye la **Interfaz Maestra de Calificación y Seguimiento** para el sistema PICADE. 
   Su función es proporcionar una lectura estandarizada de los posibles estados finales de un asistente
   a un evento de capacitación (ej: Aprobado, Reprobado, Pendiente, No Asistió).

   Es la fuente de verdad única para:
   - El Grid de Administración del Catálogo de Estatus del Participante.
   - El Módulo de Registro de Resultados (Donde el instructor califica a los asistentes).
   - Reportes de Cumplimiento Normativo (Cómputo de personal apto vs no apto).
   - Tableros de KPIs sobre eficacia de la capacitación (% de aprobación por sede o tema).

   2. ARQUITECTURA DE DISEÑO (LOOKUP ABSTRACTION)
   ----------------------------------------------
   Al ser una tabla de referencia atómica (Catálogo de Etiquetado), se aplica una **Normalización 
   Semántica** para garantizar que el contrato de datos sea intuitivo para desarrolladores de API:
   
   - Abstracción de Identificadores: Se renombra `Id_CatEstPart` a `Id_Estatus_Participante`.
   - Nomenclatura de Negocio: Se transforman columnas genéricas como `Codigo` y `Nombre` a 
     `Codigo_Estatus` y `Nombre_Estatus` para evitar colisiones en consultas que involucren 
     múltiples estatus (ej: Estatus del Curso vs Estatus del Alumno).

   3. GESTIÓN DE INTEGRIDAD Y NULOS
   --------------------------------
   - Campo `Codigo_Estatus`: Al ser un campo con restricción UNIQUE en la tabla base, se expone como 
     la "Llave de Negocio" (Natural Key). El sistema lo usa para lógicas cableadas (ej: 'APROB' para 
     permitir la descarga de constancias).
   - Campo `Descripcion_Estatus`: Se proyecta para brindar claridad al administrador sobre los criterios 
     que definen a ese estatus (ej: "Aplica para calificaciones menores a 8.0").

   4. VISIBILIDAD JERÁRQUICA (SOFT DELETES)
   ----------------------------------------
   - Principio de Trazabilidad Histórica: La vista proyecta **TODO el universo de datos** (Activos/Inactivos).
   - Justificación: Si un estatus como "Pendiente de Pago" es desactivado, los registros de 
     participantes antiguos vinculados a él NO deben quedar en blanco en los reportes de auditoría.
     La vista garantiza la persistencia visual del historial.

   5. DICCIONARIO DE DATOS (CONTRATO DE SALIDA)
   --------------------------------------------
   [Bloque 1: Identidad y Claves]
   - Id_Estatus_Participante: (INT) Llave Primaria única. Identificador del sistema.
   - Codigo_Estatus:          (VARCHAR) Clave técnica única (ej: 'ASIS', 'REPR'). 
   - Nombre_Estatus:          (VARCHAR) Etiqueta legible (ej: 'ASISTENCIA CONFIRMADA').

   [Bloque 2: Contexto Operativo]
   - Descripcion_Estatus:     (VARCHAR) Explicación del alcance o criterios del estatus.

   [Bloque 3: Control de Ciclo de Vida]
   - Estatus_Activo:          (TINYINT) 1 = Disponible para nuevos registros, 0 = Obsoleto/Histórico.

   [Bloque 4: Auditoría de Cambios]
   - Fecha_Registro:          (TIMESTAMP) Momento de la creación inicial.
   - Ultima_Modificacion:     (TIMESTAMP) Momento del último ajuste realizado por administración.
   ====================================================================================================== */

CREATE OR REPLACE 
    ALGORITHM = UNDEFINED 
    SQL SECURITY DEFINER
VIEW `PICADE`.`Vista_Estatus_Participante` AS
    SELECT 
        /* -----------------------------------------------------------------------------------
           BLOQUE 1: IDENTIDAD Y CLAVES
           Estandarización de nombres para un consumo agnóstico (API/Frontend/Reportes).
           ----------------------------------------------------------------------------------- */
        `Est`.`Id_CatEstPart`           AS `Id_Estatus_Participante`,
        `Est`.`Codigo`                  AS `Codigo_Estatus`,
        `Est`.`Nombre`                  AS `Nombre_Estatus`,

        /* -----------------------------------------------------------------------------------
           BLOQUE 2: DETALLES INFORMATIVOS
           Información contextual para tooltips o aclaraciones en reportes gerenciales.
           ----------------------------------------------------------------------------------- */
        `Est`.`Descripcion`             AS `Descripcion_Estatus`,

        /* -----------------------------------------------------------------------------------
           BLOQUE 3: METADATOS DE CONTROL (ESTATUS)
           Define si el registro es seleccionable en el flujo operativo actual.
           ----------------------------------------------------------------------------------- */
        `Est`.`Activo`                  AS `Estatus_Activo`
        
        /* -----------------------------------------------------------------------------------
           BLOQUE 4: TRAZABILIDAD (AUDITORÍA)
           Datos temporales para trazabilidad y ordenamiento por relevancia cronológica.
           ----------------------------------------------------------------------------------- */
        -- `Est`.`created_at`              AS `Fecha_Registro`,
        -- `Est`.`updated_at`              AS `Ultima_Modificacion`

    FROM 
        `PICADE`.`Cat_Estatus_Participante` `Est`;

/* --- VERIFICACIÓN DE LA VISTA (QA RÁPIDO) --- */
-- SELECT * FROM Picade.Vista_Estatus_Participante;

/* ====================================================================================================
   PROCEDIMIENTO: SP_RegistrarEstatusParticipante
   ====================================================================================================
   
   1. VISIÓN GENERAL Y OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   ----------------------------------------------------------------------------------------------------
   Este procedimiento gestiona el ALTA TRANSACCIONAL de un "Estatus de Participante" en el catálogo
   maestro (`Cat_Estatus_Participante`).
   
   Su propósito es definir los posibles resultados finales de un asistente en un curso (ej: Aprobado, 
   Reprobado, No Asistió, Cancelado). Actúa como la **Puerta de Entrada Única** (Single Gateway) para 
   garantizar que no existan estados ambiguos que corrompan los reportes de cumplimiento normativo.

   2. REGLAS DE VALIDACIÓN ESTRICTA (HARD CONSTRAINTS)
   ---------------------------------------------------
   A) INTEGRIDAD DE DATOS (DATA HYGIENE):
      - Principio: "Datos limpios desde el origen".
      - Regla: El `Código` y el `Nombre` son obligatorios. No se permiten cadenas vacías o espacios.
      - Acción: Se aplica `TRIM` y validación `NOT NULL` antes de cualquier operación.

   B) IDENTIDAD UNÍVOCA DE DOBLE FACTOR (DUAL IDENTITY CHECK):
      - Unicidad por CÓDIGO: No pueden existir dos estatus con la clave 'APROB'.
      - Unicidad por NOMBRE: No pueden existir dos estatus llamados 'APROBADO'.
      - Resolución: Se verifica primero el Código (Identificador fuerte) y luego el Nombre.

   3. ESTRATEGIA DE PERSISTENCIA Y CONCURRENCIA (ACID & RACE CONDITIONS)
   ----------------------------------------------------------------------------------------------------
   A) BLOQUEO PESIMISTA (PESSIMISTIC LOCKING):
      - Se utiliza `SELECT ... FOR UPDATE` durante las verificaciones de existencia.
      - Justificación: Esto "serializa" las peticiones. Si dos administradores intentan crear el estatus
        "Oyente" al mismo tiempo, el segundo esperará a que el primero termine, evitando lecturas sucias.

   B) AUTOSANACIÓN (SELF-HEALING / SOFT DELETE RECOVERY):
      - Escenario: El estatus "Pendiente" existía, se dio de baja (`Activo=0`) y ahora se quiere volver a usar.
      - Acción: El sistema detecta el registro "muerto", lo reactiva (`Activo=1`), actualiza su descripción
        con la nueva información y lo devuelve como éxito. No se crea un duplicado físico.

   C) PATRÓN DE RECUPERACIÓN "RE-RESOLVE" (MANEJO DE ERROR 1062):
      - Escenario Crítico: Una "Condición de Carrera" donde dos usuarios hacen INSERT en el mismo microsegundo.
        El motor de BD frenará al segundo con error `1062 (Duplicate Entry)`.
      - Solución: Un `HANDLER` captura el error, hace rollback silencioso y ejecuta una búsqueda final
        para devolver el ID del registro que "ganó", garantizando una experiencia de usuario transparente.

   4. CONTRATO DE SALIDA (OUTPUT SPECIFICATION)
   --------------------------------------------
   Retorna un Resultset de fila única con:
      - [Mensaje]: Feedback descriptivo (ej: "Estatus registrado exitosamente").
      - [Id_Estatus_Participante]: La llave primaria del recurso.
      - [Accion]: Enumerador de estado ('CREADA', 'REACTIVADA', 'REUSADA').
   ==================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_RegistrarEstatusParticipante`$$

CREATE PROCEDURE `SP_RegistrarEstatusParticipante`(
    /* -----------------------------------------------------------------
       PARÁMETROS DE ENTRADA (INPUT LAYER)
       Recibimos los datos crudos del formulario.
       ----------------------------------------------------------------- */
    IN _Codigo      VARCHAR(50),   -- [OBLIGATORIO] Identificador corto (ej: 'APROB').
    IN _Nombre      VARCHAR(255),  -- [OBLIGATORIO] Nombre descriptivo (ej: 'APROBADO').
    IN _Descripcion VARCHAR(255)   -- [OPCIONAL] Detalles operativos (ej: 'Calif >= 8.0').
)
THIS_PROC: BEGIN
    
    /* ========================================================================================
       BLOQUE 0: DECLARACIÓN DE VARIABLES DE ENTORNO
       Propósito: Inicializar contenedores para el estado de la base de datos.
       ======================================================================================== */
    
    /* Variables de Persistencia (Snapshot): Almacenan la "foto" del registro si ya existe */
    DECLARE v_Id_Estatus INT DEFAULT NULL;
    DECLARE v_Activo       TINYINT(1) DEFAULT NULL;
    
    /* Variables para Validación Cruzada (Cross-Check): Para detectar conflictos de identidad */
    DECLARE v_Nombre_Existente VARCHAR(255) DEFAULT NULL;
    DECLARE v_Codigo_Existente VARCHAR(50) DEFAULT NULL;
    
    /* Bandera de Control de Flujo (Semáforo): Indica si ocurrió un error SQL controlado (1062) */
    DECLARE v_Dup          TINYINT(1) DEFAULT 0;

    /* ========================================================================================
       BLOQUE 1: HANDLERS (MANEJO ROBUSTO DE EXCEPCIONES)
       Propósito: Asegurar la estabilidad del sistema ante fallos previstos e imprevistos.
       ======================================================================================== */
    
    /* 1.1 HANDLER DE DUPLICIDAD (Error 1062 - Duplicate Entry)
       Objetivo: Capturar colisiones de Unique Key en el INSERT final (la red de seguridad).
       Acción: No abortar. Encender bandera v_Dup = 1 para activar la rutina de recuperación. */
    DECLARE CONTINUE HANDLER FOR 1062 SET v_Dup = 1;

    /* 1.2 HANDLER GENÉRICO (SQLEXCEPTION)
       Objetivo: Capturar fallos técnicos (Disco lleno, Conexión perdida, Syntax Error).
       Acción: Abortar inmediatamente, deshacer cambios (ROLLBACK) y propagar el error. */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; 
    END;

    /* ========================================================================================
       BLOQUE 2: SANITIZACIÓN Y VALIDACIÓN PREVIA (FAIL FAST STRATEGY)
       Propósito: Rechazar datos inválidos antes de consumir recursos de transacción.
       ======================================================================================= */
    
    /* 2.1 LIMPIEZA DE DATOS (TRIM & NULLIF)
       Eliminamos espacios al inicio/final. Si la cadena queda vacía, la convertimos a NULL
       para facilitar la validación booleana estricta. */
    SET _Codigo      = NULLIF(TRIM(_Codigo), '');
    SET _Nombre      = NULLIF(TRIM(_Nombre), '');
    SET _Descripcion = NULLIF(TRIM(_Descripcion), '');

    /* 2.2 VALIDACIÓN DE OBLIGATORIEDAD (Business Rule: NO VACÍOS)
       Regla: Un Estatus sin Código o Nombre es una entidad corrupta inutilizable. */
    
    IF _Codigo IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN [400]: El CÓDIGO del Estatus es obligatorio.';
    END IF;

    IF _Nombre IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN [400]: El NOMBRE del Estatus es obligatorio.';
    END IF;

    /* ========================================================================================
       BLOQUE 3: LÓGICA DE NEGOCIO TRANSACCIONAL (CORE)
       Propósito: Ejecutar la búsqueda, validación y persistencia de forma atómica.
       ======================================================================================== */
    START TRANSACTION;

    /* ----------------------------------------------------------------------------------------
       PASO 3.1: RESOLUCIÓN DE IDENTIDAD POR CÓDIGO (PRIORIDAD ALTA)
       
       Objetivo: Verificar si la clave única (_Codigo) ya está registrada en el sistema.
       Mecánica: Usamos `FOR UPDATE` para bloquear la fila encontrada.
       Justificación: Esto evita que otro usuario modifique o reactive este mismo registro
       mientras nosotros tomamos la decisión.
       ---------------------------------------------------------------------------------------- */
    SET v_Id_Estatus = NULL; -- Reset de seguridad

    SELECT `Id_CatEstPart`, `Nombre`, `Activo` 
    INTO v_Id_Estatus, v_Nombre_Existente, v_Activo
    FROM `Cat_Estatus_Participante`
    WHERE `Codigo` = _Codigo
    LIMIT 1
    FOR UPDATE; -- <--- BLOQUEO DE ESCRITURA AQUÍ

    /* ESCENARIO A: EL CÓDIGO YA EXISTE */
    IF v_Id_Estatus IS NOT NULL THEN
        
        /* A.1 Validación de Integridad Cruzada:
           Regla: Si el código existe, el Nombre TAMBIÉN debe coincidir.
           Fallo: Si el código es igual pero el nombre es diferente, es un CONFLICTO DE DATOS. */
        IF v_Nombre_Existente <> _Nombre THEN
            SIGNAL SQLSTATE '45000' 
                SET MESSAGE_TEXT = 'CONFLICTO DE DATOS [409]: El CÓDIGO ingresado ya existe pero pertenece a un Estatus con diferente NOMBRE. Verifique sus datos.';
        END IF;

        /* A.2 Sub-Escenario: Existe pero está INACTIVO (Baja Lógica) -> REACTIVAR (Autosanación)
           "Resucitamos" el registro y actualizamos su descripción si se proveyó una nueva. */
        IF v_Activo = 0 THEN
            UPDATE `Cat_Estatus_Participante` 
            SET `Activo` = 1, 
                /* Lógica de Fusión: Si el usuario mandó descripción nueva, la usamos. 
                   Si no, mantenemos la histórica (COALESCE). */
                `Descripcion` = COALESCE(_Descripcion, `Descripcion`), 
                `updated_at` = NOW() 
            WHERE `Id_CatEstPart` = v_Id_Estatus;
            
            COMMIT; 
            SELECT 'ÉXITO: Estatus reactivado y actualizado correctamente.' AS Mensaje, v_Id_Estatus AS Id_Estatus_Participante, 'REACTIVADA' AS Accion; 
            LEAVE THIS_PROC;
        
        /* A.3 Sub-Escenario: Existe y está ACTIVO -> IDEMPOTENCIA
           El registro ya está tal como lo queremos. No hacemos nada y reportamos éxito. */
        ELSE
            COMMIT; 
            SELECT 'AVISO: El Estatus ya se encuentra registrado y activo.' AS Mensaje, v_Id_Estatus AS Id_Estatus_Participante, 'REUSADA' AS Accion; 
            LEAVE THIS_PROC;
        END IF;
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 3.2: RESOLUCIÓN DE IDENTIDAD POR NOMBRE (PRIORIDAD SECUNDARIA)
       
       Objetivo: Si llegamos aquí, el CÓDIGO es libre. Ahora verificamos si el NOMBRE ya está en uso.
       Esto previene que se creen duplicados semánticos con códigos diferentes (ej: 'APROBADO' vs 'APROBADO-1').
       ---------------------------------------------------------------------------------------- */
    SET v_Id_Estatus = NULL; -- Reset de seguridad

    SELECT `Id_CatEstPart`, `Codigo`, `Activo`
    INTO v_Id_Estatus, v_Codigo_Existente, v_Activo
    FROM `Cat_Estatus_Participante`
    WHERE `Nombre` = _Nombre
    LIMIT 1
    FOR UPDATE;

    /* ESCENARIO B: EL NOMBRE YA EXISTE */
    IF v_Id_Estatus IS NOT NULL THEN
        
        /* B.1 Conflicto de Identidad:
           El nombre existe, pero tiene asociado OTRO código diferente al que intentamos registrar. */
        IF v_Codigo_Existente IS NOT NULL AND v_Codigo_Existente <> _Codigo THEN
             SIGNAL SQLSTATE '45000' 
             SET MESSAGE_TEXT = 'CONFLICTO DE DATOS [409]: El NOMBRE ingresado ya existe pero está asociado a otro CÓDIGO diferente.';
        END IF;
        
        /* B.2 Caso Especial: Enriquecimiento de Datos (Data Enrichment)
           El registro existía con Código NULL (dato viejo), y ahora le estamos asignando un Código válido. */
        IF v_Codigo_Existente IS NULL THEN
             UPDATE `Cat_Estatus_Participante` 
             SET `Codigo` = _Codigo, `updated_at` = NOW() 
             WHERE `Id_CatEstPart` = v_Id_Estatus;
        END IF;

        /* B.3 Reactivación si estaba inactivo */
        IF v_Activo = 0 THEN
            UPDATE `Cat_Estatus_Participante` 
            SET `Activo` = 1, `Descripcion` = COALESCE(_Descripcion, `Descripcion`), `updated_at` = NOW() 
            WHERE `Id_CatEstPart` = v_Id_Estatus;
            
            COMMIT; 
            SELECT 'ÉXITO: Estatus reactivado correctamente (encontrado por Nombre).' AS Mensaje, v_Id_Estatus AS Id_Estatus_Participante, 'REACTIVADA' AS Accion; 
            LEAVE THIS_PROC;
        END IF;

        /* B.4 Idempotencia: Ya existe y está activo */
        COMMIT; 
        SELECT 'AVISO: El Estatus ya existe (validado por Nombre).' AS Mensaje, v_Id_Estatus AS Id_Estatus_Participante, 'REUSADA' AS Accion; 
        LEAVE THIS_PROC;
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 3.3: PERSISTENCIA (INSERCIÓN FÍSICA)
       
       Si pasamos todas las validaciones y no encontramos coincidencias, es un registro NUEVO.
       Aquí existe un riesgo infinitesimal de "Race Condition" si otro usuario inserta 
       exactamente los mismos datos en este preciso instante (cubierto por Handler 1062).
       ---------------------------------------------------------------------------------------- */
    SET v_Dup = 0; -- Reiniciamos bandera de error
    
    INSERT INTO `Cat_Estatus_Participante`
    (
        `Codigo`, 
        `Nombre`, 
        `Descripcion`, 
        `Activo`,
        `created_at`,
        `updated_at`
    )
    VALUES
    (
        _Codigo, 
        _Nombre, 
        _Descripcion, 
        1,      -- Activo por defecto (Born Alive)
        NOW(),  -- Timestamp Creación
        NOW()   -- Timestamp Actualización
    );

    /* Verificación de Éxito: Si v_Dup sigue en 0, el INSERT fue limpio. */
    IF v_Dup = 0 THEN
        COMMIT; 
        SELECT 'ÉXITO: Estatus registrado correctamente.' AS Mensaje, LAST_INSERT_ID() AS Id_Estatus_Participante, 'CREADA' AS Accion; 
        LEAVE THIS_PROC;
    END IF;

    /* ========================================================================================
       BLOQUE 4: RUTINA DE RECUPERACIÓN DE CONCURRENCIA (RE-RESOLVE PATTERN)
       Propósito: Manejar elegantemente el Error 1062 (Duplicate Key) si ocurre una colisión.
       ======================================================================================== */
    
    /* Si estamos aquí, v_Dup = 1. Significa que "perdimos" la carrera contra otro INSERT. */
    
    ROLLBACK; -- 1. Revertir la transacción fallida para liberar bloqueos parciales.
    
    START TRANSACTION; -- 2. Iniciar una nueva transacción limpia.
    
    SET v_Id_Estatus = NULL;
    
    /* 3. Buscar el registro "ganador" (El que insertó el otro usuario).
       Intentamos recuperar por CÓDIGO (la restricción más fuerte). */
    SELECT `Id_CatEstPart`, `Activo`, `Nombre`
    INTO v_Id_Estatus, v_Activo, v_Nombre_Existente
    FROM `Cat_Estatus_Participante`
    WHERE `Codigo` = _Codigo
    LIMIT 1
    FOR UPDATE;
    
    IF v_Id_Estatus IS NOT NULL THEN
        /* Validación de Seguridad: Confirmar que no sea un falso positivo (nombre distinto) */
        IF v_Nombre_Existente <> _Nombre THEN
             SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR CRÍTICO DE SISTEMA [500]: Concurrencia detectada con conflicto de datos (Códigos iguales, Nombres distintos).';
        END IF;

        /* Reactivación (si el ganador estaba inactivo) */
        IF v_Activo = 0 THEN
            UPDATE `Cat_Estatus_Participante` 
            SET `Activo` = 1, `Descripcion` = COALESCE(_Descripcion, `Descripcion`), `updated_at` = NOW() 
            WHERE `Id_CatEstPart` = v_Id_Estatus;
            
            COMMIT; 
            SELECT 'ÉXITO: Estatus reactivado (recuperado tras concurrencia).' AS Mensaje, v_Id_Estatus AS Id_Estatus_Participante, 'REACTIVADA' AS Accion; 
            LEAVE THIS_PROC;
        END IF;
        
        /* Éxito por Reuso (El ganador ya estaba activo) */
        COMMIT; 
        SELECT 'AVISO: El Estatus ya existía (reusado tras concurrencia).' AS Mensaje, v_Id_Estatus AS Id_Estatus_Participante, 'REUSADA' AS Accion; 
        LEAVE THIS_PROC;
    END IF;

    /* Fallo Irrecuperable: Si falló por 1062 pero no encontramos el registro 
       (Indica corrupción de índices o error fantasma grave) */
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR CRÍTICO [500]: Fallo de concurrencia no recuperable en Estatus de Participante.';

END$$

DELIMITER ;

/* ============================================================================================
   SECCIÓN: CONSULTAS ESPECÍFICAS (PARA EDICIÓN / DETALLE)
   ============================================================================================
   Estas rutinas son críticas para la UX administrativa. No solo devuelven el dato pedido, sino 
   que garantizan la integridad de lectura antes de permitir una operación de modificación.
   ============================================================================================ */

/* ====================================================================================================
   PROCEDIMIENTO: SP_ConsultarEstatusParticipanteEspecifico
   ====================================================================================================
   
   ----------------------------------------------------------------------------------------------------
   I. OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   ----------------------------------------------------------------------------------------------------
   [QUÉ ES]:
   Es el endpoint de lectura de alta fidelidad para recuperar la "Ficha Técnica" completa de un
   Estatus de Participante específico, identificado por su llave primaria (`Id_CatEstPart`).

   [PARA QUÉ SE USA (CONTEXTO DE UI)]:
   A) PRECARGA DE FORMULARIO DE EDICIÓN (UPDATE):
      - Cuando el administrador necesita corregir un estatus (ej: cambiar "REPROBADO" por "NO APTO"),
        el formulario debe llenarse con los datos exactos que residen en la base de datos.
      - Requisito Crítico: La fidelidad del dato. Los valores se entregan crudos (Raw Data).
        Si la descripción es NULL, se entrega NULL, permitiendo al frontend renderizar un input vacío
        limpio en lugar de un texto "placeholder" (como "Sin descripción") que el usuario tendría 
        que borrar manualmente.

   B) VISUALIZACIÓN DE DETALLE (AUDITORÍA):
      - Permite visualizar metadatos de auditoría (`created_at`, `updated_at`) que certifican la
        antigüedad del registro en el sistema.

   ----------------------------------------------------------------------------------------------------
   II. ARQUITECTURA DE DATOS (DIRECT TABLE ACCESS)
   ----------------------------------------------------------------------------------------------------
   Este procedimiento consulta directamente la tabla física `Cat_Estatus_Participante`.
   
   [JUSTIFICACIÓN TÉCNICA]:
   - Desacoplamiento de Presentación: A diferencia de las Vistas (que formatean datos para lectura humana),
     este SP prepara los datos para el consumo del sistema (Binding de Modelos en Angular/Vue/React).
   - Performance: El acceso por Primary Key (`Id_CatEstPart`) tiene un costo computacional de O(1),
     garantizando una respuesta instantánea (<1ms).

   ----------------------------------------------------------------------------------------------------
   III. ESTRATEGIA DE SEGURIDAD (DEFENSIVE PROGRAMMING)
   ----------------------------------------------------------------------------------------------------
   - Validación de Entrada: Se rechazan IDs nulos o negativos antes de tocar el disco.
   - Fail Fast (Fallo Rápido): Se verifica la existencia del registro antes de intentar devolver datos.
     Esto permite diferenciar claramente entre un "Error 404" (Recurso no encontrado) y un 
     "Error 500" (Fallo de servidor/red).

   ----------------------------------------------------------------------------------------------------
   IV. VISIBILIDAD (SCOPE)
   ----------------------------------------------------------------------------------------------------
   - NO se filtra por `Activo = 1`.
   - Razón: Un estatus puede estar "Desactivado" (Baja Lógica). El administrador necesita poder 
     consultarlo para ver su información y decidir si lo Reactiva. Ocultarlo aquí haría imposible 
     su gestión y recuperación.

   ----------------------------------------------------------------------------------------------------
   V. DICCIONARIO DE DATOS (OUTPUT CONTRACT)
   ----------------------------------------------------------------------------------------------------
   Retorna una única fila (Single Row) mapeada semánticamente:
      - [Id_Estatus_Participante]: Llave primaria.
      - [Codigo_Estatus]: Clave corta técnica.
      - [Nombre_Estatus]: Etiqueta humana.
      - [Descripcion_Estatus]: Contexto operativo.
      - [Estatus_Activo]: Alias de negocio para `Activo` (1=Vigente, 0=Baja).
      - [Auditoría]: Fechas de creación y modificación.
   ==================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ConsultarEstatusParticipanteEspecifico`$$

CREATE PROCEDURE `SP_ConsultarEstatusParticipanteEspecifico`(
    IN _Id_Estatus INT -- [OBLIGATORIO] Identificador único del Estatus a consultar
)
BEGIN
    /* ========================================================================================
       BLOQUE 1: VALIDACIÓN DE ENTRADA (DEFENSIVE PROGRAMMING)
       Objetivo: Asegurar que el parámetro recibido sea un entero positivo válido.
       Evita cargas innecesarias al motor de base de datos con peticiones basura.
       ======================================================================================== */
    IF _Id_Estatus IS NULL OR _Id_Estatus <= 0 THEN
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: El Identificador del Estatus es inválido (Debe ser un entero positivo).';
    END IF;

    /* ========================================================================================
       BLOQUE 2: VERIFICACIÓN DE EXISTENCIA (FAIL FAST STRATEGY)
       Objetivo: Validar que el recurso realmente exista en la base de datos.
       
       NOTA DE IMPLEMENTACIÓN:
       Usamos `SELECT 1` que es más ligero que seleccionar columnas reales, ya que solo 
       necesitamos confirmar la presencia de la llave en el índice primario.
       ======================================================================================== */
    IF NOT EXISTS (SELECT 1 FROM `Cat_Estatus_Participante` WHERE `Id_CatEstPart` = _Id_Estatus) THEN
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [404]: El Estatus de Participante solicitado no existe o fue eliminado físicamente.';
    END IF;

    /* ========================================================================================
       BLOQUE 3: CONSULTA PRINCIPAL (DATA RETRIEVAL)
       Objetivo: Retornar el objeto de datos completo y puro (Raw Data) con alias semánticos.
       ======================================================================================== */
    SELECT 
        /* --- GRUPO A: IDENTIDAD DEL REGISTRO --- */
        /* Este ID es la llave primaria inmutable. */
        `Id_CatEstPart`   AS `Id_Estatus_Participante`,
        
        /* --- GRUPO B: DATOS EDITABLES --- */
        /* El Frontend usará estos campos para llenar los inputs de texto. */
        `Codigo`          AS `Codigo_Estatus`,
        `Nombre`          AS `Nombre_Estatus`,
        `Descripcion`     AS `Descripcion_Estatus`,
        
        /* --- GRUPO C: METADATOS DE CONTROL DE CICLO DE VIDA --- */
        /* Este valor (0 o 1) indica si el estatus es utilizable actualmente en nuevos registros.
           1 = Activo/Visible, 0 = Inactivo/Oculto (Baja Lógica). */
        `Activo`          AS `Estatus_Activo`,        
        
        /* --- GRUPO D: AUDITORÍA DE SISTEMA --- */
        /* Fechas útiles para mostrar en el pie de página del modal de detalle o tooltip. */
        `created_at`      AS `Fecha_Registro`,
        `updated_at`      AS `Ultima_Modificacion`
        
    FROM `Cat_Estatus_Participante`
    WHERE `Id_CatEstPart` = _Id_Estatus
    LIMIT 1; /* Buena práctica: Asegura al optimizador que se detenga tras el primer hallazgo. */

END$$

DELIMITER ;

/* ============================================================================================
   SECCIÓN: LISTADOS PARA DROPDOWNS (SOLO REGISTROS ACTIVOS)
   ============================================================================================
   Estas rutinas son consumidas por los formularios de captura (Frontend).
   Su objetivo es ofrecer al usuario solo las opciones válidas y vigentes para evitar errores.
   ============================================================================================ */

/* ====================================================================================================
   PROCEDIMIENTO: SP_ListarEstatusParticipanteActivos
   ====================================================================================================
   
   1. OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   ----------------------------------------------------------------------------------------------------
   Proveer un endpoint de datos de alta velocidad para alimentar el componente visual 
   "Selector de Estatus de Asistencia" (Dropdown) en los formularios de evaluación de cursos.

   Este procedimiento es la fuente autorizada para que los Instructores califiquen el desempeño
   final de un asistente (ej: 'Aprobado', 'Reprobado', 'Cancelado').

   2. REGLAS DE NEGOCIO Y FILTRADO (THE VIGENCY CONTRACT)
   ----------------------------------------------------------------------------------------------------
   A) FILTRO DE VIGENCIA ESTRICTO (HARD FILTER):
      - Regla: La consulta aplica obligatoriamente la cláusula `WHERE Activo = 1`.
      - Justificación Operativa: Un Estatus marcado como inactivo (Baja Lógica) indica que esa 
        categoría de calificación ya no es válida en la normativa actual. Permitir su selección 
        generaría reportes de cumplimiento inconsistentes.
      - Seguridad: El filtro es nativo en BD, impidiendo que una UI desactualizada inyecte 
        estados obsoletos.

   B) ORDENAMIENTO COGNITIVO (USABILITY):
      - Regla: Los resultados se ordenan alfabéticamente por `Nombre` (A-Z).
      - Justificación: Facilita la búsqueda visual rápida en la lista desplegable.

   3. ARQUITECTURA DE DATOS (ROOT ENTITY OPTIMIZATION)
   ---------------------------------------------------
   - Ausencia de JOINs: `Cat_Estatus_Participante` es una Entidad Raíz. Esto permite una 
     ejecución directa sobre el índice primario.
   
   - Proyección Mínima (Payload Reduction):
     Solo se devuelven las columnas vitales para construir el elemento HTML `<option>`:
       1. ID (Value): Para la integridad referencial.
       2. Nombre (Label): Para la lectura humana.
       3. Código (Hint/Badge): Para lógica visual en el frontend (ej: pintar de verde si es 'APROB').
     
     Se omiten campos pesados como `Descripcion` o auditoría (`created_at`) para minimizar 
     la latencia de red.

   4. DICCIONARIO DE DATOS (OUTPUT JSON SCHEMA)
   --------------------------------------------
   Retorna un array de objetos ligeros:
      - `Id_CatEstPart`: (INT) Llave Primaria. Value del selector.
      - `Codigo`:        (VARCHAR) Clave corta (ej: 'APROB'). Útil para badges de colores.
      - `Nombre`:        (VARCHAR) Texto principal (ej: 'Aprobado').
   ==================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ListarEstatusParticipanteActivos`$$

CREATE PROCEDURE `SP_ListarEstatusParticipanteActivos`()
BEGIN
    /* ========================================================================================
       BLOQUE ÚNICO: CONSULTA DE SELECCIÓN OPTIMIZADA
       No requiere validaciones de entrada ya que es una consulta de catálogo global.
       ======================================================================================== */
    
    SELECT 
        /* IDENTIFICADOR ÚNICO (PK)
           Este es el valor que se guardará como Foreign Key en la tabla intermedia de asistencia. */
        `Id_CatEstPart`, 
        
        /* CLAVE CORTA / MNEMOTÉCNICA
           Dato auxiliar para que el Frontend pueda aplicar estilos condicionales.
           Ej: Si Codigo == 'REP' (Reprobado) -> Pintar texto en Rojo.
               Si Codigo == 'APR' (Aprobado) -> Pintar texto en Verde. */
        `Codigo`, 
        
        /* DESCRIPTOR HUMANO
           El texto principal que el usuario leerá en la lista desplegable. */
        `Nombre`

    FROM 
        `Cat_Estatus_Participante`
    
    /* ----------------------------------------------------------------------------------------
       FILTRO DE SEGURIDAD OPERATIVA (VIGENCIA)
       Ocultamos todo lo que no sea "1" (Activo). 
       Esto asegura que las calificaciones nuevas solo usen estatus vigentes.
       ---------------------------------------------------------------------------------------- */
    WHERE 
        `Activo` = 1
    
    /* ----------------------------------------------------------------------------------------
       OPTIMIZACIÓN DE UX
       Ordenamiento alfabético realizado por el motor de base de datos para eficiencia.
       ---------------------------------------------------------------------------------------- */
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

/* ====================================================================================================
   PROCEDIMIENTO: SP_ListarEstatusParticipante
   ====================================================================================================
   
   ----------------------------------------------------------------------------------------------------
   I. FICHA TÉCNICA Y CONTEXTO DE NEGOCIO (BUSINESS CONTEXT)
   ----------------------------------------------------------------------------------------------------
   [NOMBRE LÓGICO]: Listado Maestro de Estatus de Participante (Versión Ligera).
   [TIPO]: Rutina de Lectura (Read-Only).
   [DEPENDENCIA]: Consume la vista `Vista_Estatus_Participante`.

   [PROPÓSITO ESTRATÉGICO]:
   Este procedimiento actúa como el proveedor de datos para el **Grid Principal de Administración**.
   Permite al Administrador visualizar el inventario completo de los posibles resultados de 
   calificación (ej: Aprobado, Reprobado, Cancelado), incluyendo aquellos que ya no están vigentes.

   ----------------------------------------------------------------------------------------------------
   II. ESTRATEGIA DE OPTIMIZACIÓN DE CARGA (PAYLOAD REDUCTION STRATEGY)
   ----------------------------------------------------------------------------------------------------
   [EL PROBLEMA]:
   En un Dashboard Administrativo, la velocidad es crítica. Cargar columnas de texto largo 
   (como descripciones detalladas o logs de auditoría extensos) en una tabla que muestra 
   50 o 100 filas genera latencia innecesaria.

   [LA SOLUCIÓN: PROYECCIÓN SELECTIVA]:
   Este SP aplica un patrón de "Adelgazamiento de Datos". Aunque la Vista fuente contiene la columna 
   `Descripcion_Estatus`, este procedimiento la **EXCLUYE DELIBERADAMENTE** del listado principal.
   
   [JUSTIFICACIÓN]:
   En la tabla resumen, el usuario solo necesita identificar el registro por Código y Nombre. 
   Los detalles profundos se cargan "bajo demanda" (Lazy Loading) solo cuando el usuario hace 
   clic en "Editar" o "Ver Detalle" (usando `SP_ConsultarEstatusParticipanteEspecifico`).

   ----------------------------------------------------------------------------------------------------
   III. REGLAS DE VISIBILIDAD Y ORDENAMIENTO (UX RULES)
   ----------------------------------------------------------------------------------------------------
   [RN-01] VISIBILIDAD TOTAL (NO FILTERING):
      - Regla: No se aplica ninguna cláusula `WHERE` sobre el estatus.
      - Razón: "Lo que se oculta no se puede gestionar". El admin debe ver los registros inactivos
        para poder reactivarlos si fue un error.

   [RN-02] JERARQUÍA VISUAL (SORTING):
      - Primer Nivel: `Estatus_Activo DESC`. Los registros ACTIVOS (1) aparecen arriba.
        Los INACTIVOS (0) se hunden al fondo de la lista para no estorbar la operación diaria.
      - Segundo Nivel: `Nombre_Estatus ASC`. Orden alfabético para búsqueda visual rápida.

   ----------------------------------------------------------------------------------------------------
   IV. CONTRATO DE SALIDA (API RESPONSE SPECIFICATION)
   ----------------------------------------------------------------------------------------------------
   Retorna un Array de Objetos JSON optimizado:
      1. [Id_Estatus_Participante]: (INT) Llave Primaria. Oculta en el grid, usada en botones de acción.
      2. [Codigo_Estatus]: (STRING) Clave visual corta (Badge).
      3. [Nombre_Estatus]: (STRING) La etiqueta principal visible.
      4. [Estatus_Activo]: (INT) 1/0. Permite al Frontend pintar de gris los items inactivos.
   ==================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ListarEstatusParticipante`$$

CREATE PROCEDURE `SP_ListarEstatusParticipante`()
BEGIN
    /* ========================================================================================
       BLOQUE ÚNICO: CONSULTA DE PROYECCIÓN SELECTIVA
       ----------------------------------------------------------------------------------------
       Nota de Implementación:
       Enumeramos explícitamente las columnas para garantizar un payload ligero.
       ======================================================================================== */
    
    SELECT 
        /* -------------------------------------------------------------------------------
           GRUPO 1: IDENTIDAD DEL RECURSO (PRIMARY KEYS & CODES)
           Datos necesarios para mantener la integridad referencial en la selección.
           ------------------------------------------------------------------------------- */
        `Id_Estatus_Participante`,    -- ID oculto para operaciones CRUD.
        `Codigo_Estatus`,             -- Identificador semántico corto (ej: 'APROB').

        /* -------------------------------------------------------------------------------
           GRUPO 2: DESCRIPTOR HUMANO (LABEL)
           La información principal que el usuario final leerá en la interfaz.
           ------------------------------------------------------------------------------- */
        `Nombre_Estatus`             -- Texto descriptivo (ej: 'APROBADO').
        
        /* -------------------------------------------------------------------------------
           GRUPO 3: METADATOS DE CONTROL (STATUS FLAG)
           Dato crítico para la UX del Administrador.
           Permite aplicar estilos visuales (ej: fila gris, icono de 'apagado') a los
           elementos inactivos.
           ------------------------------------------------------------------------------- */
        -- `Estatus_Activo`              -- 1 = Operativo, 0 = Deprecado/Histórico.
        
        /* [COLUMNA EXCLUIDA]: `Descripcion_Estatus`
           Se omite por optimización. El detalle se ve en el modal de edición. */
        
    FROM 
        `Vista_Estatus_Participante`
    
    /* ========================================================================================
       BLOQUE DE ORDENAMIENTO (UX OPTIMIZATION)
       ----------------------------------------------------------------------------------------
       Diseñado para maximizar la eficiencia del operador.
       ======================================================================================== */
    ORDER BY 
        `Estatus_Activo` DESC,  -- Prioridad 1: Mantener lo útil (Activos) al principio.
        `Nombre_Estatus` ASC;   -- Prioridad 2: Facilitar el escaneo visual alfabético.

END$$

DELIMITER ;

/* ====================================================================================================
   PROCEDIMIENTO: SP_EditarEstatusParticipante
   ====================================================================================================

   ----------------------------------------------------------------------------------------------------
   I. CONTEXTO TÉCNICO Y DE NEGOCIO (BUSINESS CONTEXT)
   ----------------------------------------------------------------------------------------------------
   [QUÉ ES]:
   Es el motor transaccional de alta fidelidad encargado de modificar los atributos fundamentales de 
   un "Estatus de Participante" (`Cat_Estatus_Participante`) existente en el catálogo.

   [OBJETIVO ESTRATÉGICO]:
   Permitir al administrador corregir o actualizar la identidad (`Código`, `Nombre`) y el contexto 
   operativo (`Descripción`) de un resultado de calificación (ej: cambiar 'REPROBADO' por 'NO APTO').
   
   [IMPORTANCIA CRÍTICA]:
   La modificación de estos estatus afecta la interpretación histórica de las capacitaciones. 
   Este SP garantiza la consistencia ACID (Atomicidad, Consistencia, Aislamiento, Durabilidad) en un 
   entorno multi-usuario de alta concurrencia, evitando duplicados y bloqueos mutuos.

   ----------------------------------------------------------------------------------------------------
   II. REGLAS DE BLINDAJE (HARD CONSTRAINTS)
   ----------------------------------------------------------------------------------------------------
   [RN-01] OBLIGATORIEDAD DE DATOS (DATA INTEGRITY):
      - Principio: "Todo o Nada". No se permite persistir un estatus sin `Código` o sin `Nombre`.
      - Justificación: Un registro anónimo rompe la integridad visual de los reportes.

   [RN-02] EXCLUSIÓN PROPIA (GLOBAL UNIQUENESS):
      - Regla A: El nuevo `Código` no puede pertenecer a OTRO estatus (`Id <> _Id_Estatus`).
      - Regla B: El nuevo `Nombre` no puede pertenecer a OTRO estatus.
      - Nota: Es perfectamente legal que el registro coincida consigo mismo (Idempotencia).
      - Implementación: Esta validación se realiza "Bajo Llave" (dentro de la transacción con bloqueo).

   [RN-03] IDEMPOTENCIA (OPTIMIZACIÓN DE I/O):
      - Antes de escribir en disco, el SP compara el estado actual (`Snapshot`) contra los inputs.
      - Si son matemáticamente idénticos, retorna éxito ('SIN_CAMBIOS') inmediatamente.
      - Beneficio: Evita escrituras innecesarias en el Transaction Log y mantiene intacta la fecha de auditoría `updated_at`.

   ----------------------------------------------------------------------------------------------------
   III. ARQUITECTURA DE CONCURRENCIA (DETERMINISTIC LOCKING PATTERN)
   ----------------------------------------------------------------------------------------------------
   [EL PROBLEMA DE LOS DEADLOCKS (ABRAZOS MORTALES)]:
   En un escenario de "Intercambio" (Swap Scenario), donde:
      - Usuario A quiere renombrar Estatus 1 como 'APROBADO'.
      - Usuario B quiere renombrar Estatus 2 como 'ASISTENCIA'.
   Si ambos registros ya existen y se cruzan las referencias, y si bloquean los recursos en orden inverso,
   el motor de base de datos detectará un ciclo y matará uno de los procesos.

   [LA SOLUCIÓN MATEMÁTICA - ALGORITMO DE ORDENAMIENTO]:
   Implementamos el patrón de "Bloqueo Determinístico Total":
   
   1. FASE DE RECONOCIMIENTO (Dirty Read):
      Identificamos todos los IDs potenciales involucrados:
        a) El ID que edito (Target).
        b) El ID que actualmente posee el Código que quiero usar (Conflicto A).
        c) El ID que actualmente posee el Nombre que quiero usar (Conflicto B).
   
   2. FASE DE ORDENAMIENTO:
      Ordenamos estos IDs numéricamente de MENOR a MAYOR.
   
   3. FASE DE EJECUCIÓN:
      Adquirimos los bloqueos (`FOR UPDATE`) siguiendo estrictamente ese orden "en fila india".
   
   Resultado: Todos los procesos compiten en la misma dirección. Cero Deadlocks garantizados.

   ----------------------------------------------------------------------------------------------------
   IV. CONTRATO DE SALIDA (OUTPUT SPECIFICATION)
   ----------------------------------------------------------------------------------------------------
   Retorna un resultset de una sola fila con:
      - [Mensaje]: Feedback descriptivo y humano para la UI.
      - [Accion]: Código de estado ('ACTUALIZADA', 'SIN_CAMBIOS', 'CONFLICTO').
      - [Id_Estatus_Participante]: Identificador del recurso manipulado.
   ==================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_EditarEstatusParticipante`$$

CREATE PROCEDURE `SP_EditarEstatusParticipante`(
    /* -----------------------------------------------------------------
       PARÁMETROS DE ENTRADA (INPUT LAYER)
       Recibimos los datos crudos desde el formulario web.
       Se asume que son cadenas de texto que requieren limpieza.
       ----------------------------------------------------------------- */
    IN _Id_Estatus   INT,           -- [OBLIGATORIO] PK del registro a editar (Target).
    IN _Codigo       VARCHAR(50),   -- [OBLIGATORIO] Nuevo Código (ej: 'APR').
    IN _Nombre       VARCHAR(255),  -- [OBLIGATORIO] Nuevo Nombre (ej: 'APROBADO').
    IN _Descripcion  VARCHAR(255)   -- [OPCIONAL] Nueva Descripción (Contexto).
)
THIS_PROC: BEGIN

    /* ========================================================================================
       BLOQUE 0: DECLARACIÓN DE VARIABLES DE ESTADO Y CONTEXTO
       Propósito: Inicializar los contenedores en memoria para la lógica del procedimiento.
       ======================================================================================== */
    
    /* [Snapshots]: Almacenan la "foto" del registro ANTES de editarlo. 
       Son vitales para comparar si hubo cambios reales (Lógica de Idempotencia). */
    DECLARE v_Cod_Act  VARCHAR(50)  DEFAULT NULL;
    DECLARE v_Nom_Act  VARCHAR(255) DEFAULT NULL;
    DECLARE v_Desc_Act VARCHAR(255) DEFAULT NULL;
    
    /* [IDs de Conflicto]: Identifican a "los otros" registros que podrían estorbar.
       Se llenan durante la Fase de Reconocimiento. */
    DECLARE v_Id_Conflicto_Cod INT DEFAULT NULL; -- ¿Quién tiene ya este Código?
    DECLARE v_Id_Conflicto_Nom INT DEFAULT NULL; -- ¿Quién tiene ya este Nombre?
    
    /* Variable genérica para reportar errores en el bloque final */
    DECLARE v_Id_Conflicto     INT DEFAULT NULL; 
    
    /* [Variables de Algoritmo de Bloqueo]: Auxiliares para ordenar y ejecutar los locks.
       Nos permiten estructurar la "Fila India" de bloqueos. */
    DECLARE v_L1 INT DEFAULT NULL;   -- Candidato 1 a bloquear
    DECLARE v_L2 INT DEFAULT NULL;   -- Candidato 2 a bloquear
    DECLARE v_L3 INT DEFAULT NULL;   -- Candidato 3 a bloquear
    DECLARE v_Min INT DEFAULT NULL;  -- El menor ID de la ronda actual
    DECLARE v_Existe INT DEFAULT NULL; -- Validación booleana de éxito del lock

    /* [Bandera de Control]: Semáforo para detectar errores de concurrencia (Error 1062).
       Permite manejar la excepción sin abortar el flujo inmediatamente. */
    DECLARE v_Dup TINYINT(1) DEFAULT 0;

    /* [Variables de Diagnóstico]: Para el análisis Post-Mortem en caso de fallo.
       Permiten decirle al usuario EXACTAMENTE qué campo causó el error. */
    DECLARE v_Campo_Error VARCHAR(20) DEFAULT NULL;
    DECLARE v_Id_Error    INT DEFAULT NULL;

    /* ========================================================================================
       BLOQUE 1: HANDLERS (SISTEMA DE DEFENSA)
       Propósito: Capturar excepciones técnicas y convertirlas en respuestas controladas.
       ======================================================================================== */
    
    /* 1.1 HANDLER DE DUPLICIDAD (Error 1062 - Duplicate Entry)
       Objetivo: Si ocurre una "Race Condition" en el último milisegundo (alguien insertó el duplicado
       justo antes de nuestro UPDATE y después de nuestro SELECT), no abortamos.
       Acción: Encendemos la bandera v_Dup = 1 para activar la rutina de recuperación al final. */
    DECLARE CONTINUE HANDLER FOR 1062 SET v_Dup = 1;

    /* 1.2 HANDLER GENÉRICO (SQLEXCEPTION)
       Objetivo: Ante fallos catastróficos (Disco lleno, Red caída, Error de Sintaxis).
       Acción: Abortamos todo (ROLLBACK) y propagamos el error original (RESIGNAL) para el log. */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; 
    END;

    /* ========================================================================================
       BLOQUE 2: SANITIZACIÓN Y VALIDACIÓN PREVIA (FAIL FAST STRATEGY)
       Propósito: Limpiar la entrada y rechazar basura antes de gastar recursos de transacción.
       ======================================================================================== */
    
    /* 2.1 LIMPIEZA DE DATOS (TRIM & NULLIF)
       Eliminamos espacios al inicio/final. Si la cadena queda vacía, la convertimos a NULL
       para facilitar la validación booleana estricta más adelante. */
    SET _Codigo      = NULLIF(TRIM(_Codigo), '');
    SET _Nombre      = NULLIF(TRIM(_Nombre), '');
    SET _Descripcion = NULLIF(TRIM(_Descripcion), '');

    /* 2.2 VALIDACIÓN DE OBLIGATORIEDAD (REGLAS DE NEGOCIO)
       Validamos la integridad básica de la petición. */
    
    IF _Id_Estatus IS NULL OR _Id_Estatus <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: Identificador de Estatus inválido.';
    END IF;

    IF _Codigo IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN [400]: El CÓDIGO es obligatorio.';
    END IF;

    IF _Nombre IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN [400]: El NOMBRE es obligatorio.';
    END IF;

    /* ========================================================================================
       BLOQUE 3: ESTRATEGIA DE BLOQUEO DETERMINÍSTICO (PREVENCIÓN DE DEADLOCKS)
       Propósito: Adquirir recursos en orden estricto (Menor a Mayor) para evitar ciclos de espera.
       ======================================================================================== */
    START TRANSACTION;

    /* ----------------------------------------------------------------------------------------
       PASO 3.1: RECONOCIMIENTO (LECTURA SUCIA / NO BLOQUEANTE)
       Primero "escaneamos" el entorno para identificar a los actores involucrados sin bloquear.
       Esto nos permite construir la lista de IDs que necesitamos asegurar.
       ---------------------------------------------------------------------------------------- */
    
    /* A) Identificar al Objetivo (Target) */
    SELECT `Codigo`, `Nombre` INTO v_Cod_Act, v_Nom_Act
    FROM `Cat_Estatus_Participante` WHERE `Id_CatEstPart` = _Id_Estatus;

    /* Check de Existencia: Si no existe, abortamos. (Pudo ser borrado por otro admin hace un segundo) */
    IF v_Cod_Act IS NULL AND v_Nom_Act IS NULL THEN 
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [404]: El Estatus que intenta editar no existe.';
    END IF;

    /* B) Identificar Conflicto de CÓDIGO 
       ¿Alguien más tiene el código que quiero usar? (Solo buscamos si el código cambió) */
    IF _Codigo <> IFNULL(v_Cod_Act, '') THEN
        SELECT `Id_CatEstPart` INTO v_Id_Conflicto_Cod 
        FROM `Cat_Estatus_Participante` 
        WHERE `Codigo` = _Codigo AND `Id_CatEstPart` <> _Id_Estatus LIMIT 1;
    END IF;

    /* C) Identificar Conflicto de NOMBRE 
       ¿Alguien más tiene el nombre que quiero usar? (Solo buscamos si el nombre cambió) */
    IF _Nombre <> v_Nom_Act THEN
        SELECT `Id_CatEstPart` INTO v_Id_Conflicto_Nom 
        FROM `Cat_Estatus_Participante` 
        WHERE `Nombre` = _Nombre AND `Id_CatEstPart` <> _Id_Estatus LIMIT 1;
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 3.2: EJECUCIÓN DE BLOQUEOS ORDENADOS (EL ALGORITMO)
       Ordenamos los IDs detectados y los bloqueamos secuencialmente.
       ---------------------------------------------------------------------------------------- */
    
    /* Llenamos el pool de candidatos a bloquear */
    SET v_L1 = _Id_Estatus;
    SET v_L2 = v_Id_Conflicto_Cod;
    SET v_L3 = v_Id_Conflicto_Nom;

    /* Normalización: Eliminar duplicados en las variables 
       (Ej: Si el conflicto de código y nombre es el mismo registro, no intentamos bloquearlo dos veces) */
    IF v_L2 = v_L1 THEN SET v_L2 = NULL; END IF;
    IF v_L3 = v_L1 THEN SET v_L3 = NULL; END IF;
    IF v_L3 = v_L2 THEN SET v_L3 = NULL; END IF;

    /* --- RONDA 1: Bloquear el ID Menor --- */
    SET v_Min = NULL;
    /* Encontramos el mínimo valor no nulo entre L1, L2 y L3 */
    IF v_L1 IS NOT NULL THEN SET v_Min = v_L1; END IF;
    IF v_L2 IS NOT NULL AND (v_Min IS NULL OR v_L2 < v_Min) THEN SET v_Min = v_L2; END IF;
    IF v_L3 IS NOT NULL AND (v_Min IS NULL OR v_L3 < v_Min) THEN SET v_Min = v_L3; END IF;

    IF v_Min IS NOT NULL THEN
        /* Bloqueo Pesimista sobre el ID menor */
        SELECT 1 INTO v_Existe FROM `Cat_Estatus_Participante` WHERE `Id_CatEstPart` = v_Min FOR UPDATE;
        
        /* Marcar como procesado (borrar del pool) para la siguiente ronda */
        IF v_L1 = v_Min THEN SET v_L1 = NULL; END IF;
        IF v_L2 = v_Min THEN SET v_L2 = NULL; END IF;
        IF v_L3 = v_Min THEN SET v_L3 = NULL; END IF;
    END IF;

    /* --- RONDA 2: Bloquear el Siguiente ID (El del medio) --- */
    SET v_Min = NULL;
    IF v_L1 IS NOT NULL THEN SET v_Min = v_L1; END IF;
    IF v_L2 IS NOT NULL AND (v_Min IS NULL OR v_L2 < v_Min) THEN SET v_Min = v_L2; END IF;
    IF v_L3 IS NOT NULL AND (v_Min IS NULL OR v_L3 < v_Min) THEN SET v_Min = v_L3; END IF;

    IF v_Min IS NOT NULL THEN
        SELECT 1 INTO v_Existe FROM `Cat_Estatus_Participante` WHERE `Id_CatEstPart` = v_Min FOR UPDATE;
        IF v_L1 = v_Min THEN SET v_L1 = NULL; END IF;
        IF v_L2 = v_Min THEN SET v_L2 = NULL; END IF;
        IF v_L3 = v_Min THEN SET v_L3 = NULL; END IF;
    END IF;

    /* --- RONDA 3: Bloquear el ID Mayor (Último) --- */
    SET v_Min = NULL;
    IF v_L1 IS NOT NULL THEN SET v_Min = v_L1; END IF;
    IF v_L2 IS NOT NULL AND (v_Min IS NULL OR v_L2 < v_Min) THEN SET v_Min = v_L2; END IF;
    IF v_L3 IS NOT NULL AND (v_Min IS NULL OR v_L3 < v_Min) THEN SET v_Min = v_L3; END IF;

    IF v_Min IS NOT NULL THEN
        SELECT 1 INTO v_Existe FROM `Cat_Estatus_Participante` WHERE `Id_CatEstPart` = v_Min FOR UPDATE;
    END IF;

    /* ========================================================================================
       BLOQUE 4: LÓGICA DE NEGOCIO (BAJO PROTECCIÓN DE LOCKS)
       Propósito: Aplicar validaciones definitivas con la certeza de que nadie más mueve los datos.
       ======================================================================================== */

    /* 4.1 RE-LECTURA AUTORIZADA
       Leemos el estado definitivo del registro.
       (Pudo haber cambiado en los milisegundos previos al bloqueo o durante la espera del lock). */
    SELECT `Codigo`, `Nombre`, `Descripcion`
    INTO v_Cod_Act, v_Nom_Act, v_Desc_Act
    FROM `Cat_Estatus_Participante` 
    WHERE `Id_CatEstPart` = _Id_Estatus; 

    /* Check Anti-Zombie: Si al bloquear descubrimos que el registro fue borrado */
    IF v_Cod_Act IS NULL THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR CRÍTICO [410]: El registro desapareció durante la transacción.';
    END IF;

    /* 4.2 DETECCIÓN DE IDEMPOTENCIA (SIN CAMBIOS)
       Comparamos Snapshot vs Inputs. 
       Usamos `<=>` (Null-Safe Equality) para manejar correctamente los NULLs en la Descripción. 
       Si todo es igual, no tiene sentido hacer un UPDATE. */
    IF (v_Cod_Act <=> _Codigo) 
       AND (v_Nom_Act = _Nombre) 
       AND (v_Desc_Act <=> _Descripcion) THEN
       
       COMMIT; -- Liberamos locks inmediatamente
       
       /* Retorno anticipado para ahorrar I/O */
       SELECT 'AVISO: No se detectaron cambios en la información.' AS Mensaje, 'SIN_CAMBIOS' AS Accion, _Id_Estatus AS Id_Estatus_Participante;
       LEAVE THIS_PROC;
    END IF;

    /* 4.3 VALIDACIÓN FINAL DE UNICIDAD (PRE-UPDATE CHECK)
       Verificamos duplicados reales bajo lock. Esta validación es 100% fiable. */
    
    /* A) Validación por CÓDIGO */
    SET v_Id_Error = NULL;
    SELECT `Id_CatEstPart` INTO v_Id_Error FROM `Cat_Estatus_Participante` 
    WHERE `Codigo` = _Codigo AND `Id_CatEstPart` <> _Id_Estatus LIMIT 1;
    
    IF v_Id_Error IS NOT NULL THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'CONFLICTO DE DATOS [409]: El CÓDIGO ingresado ya pertenece a otro Estatus.';
    END IF;

    /* B) Validación por NOMBRE */
    SET v_Id_Error = NULL;
    SELECT `Id_CatEstPart` INTO v_Id_Error FROM `Cat_Estatus_Participante` 
    WHERE `Nombre` = _Nombre AND `Id_CatEstPart` <> _Id_Estatus LIMIT 1;
    
    IF v_Id_Error IS NOT NULL THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'CONFLICTO DE DATOS [409]: El NOMBRE ingresado ya pertenece a otro Estatus.';
    END IF;

    /* ========================================================================================
       BLOQUE 5: PERSISTENCIA (UPDATE FÍSICO)
       Propósito: Aplicar los cambios físicos en el disco.
       ======================================================================================== */
    
    SET v_Dup = 0; -- Resetear bandera de error antes de intentar escribir

    UPDATE `Cat_Estatus_Participante`
    SET `Codigo`      = _Codigo,
        `Nombre`      = _Nombre,
        `Descripcion` = _Descripcion,
        `updated_at`  = NOW() -- Auditoría automática
    WHERE `Id_CatEstPart` = _Id_Estatus;

    /* ========================================================================================
       BLOQUE 6: MANEJO DE COLISIÓN TARDÍA (RECUPERACIÓN DE ERROR 1062)
       Propósito: Gestionar el caso extremo de inserción fantasma justo antes del update.
       ======================================================================================== */
    
    /* Si v_Dup = 1, el UPDATE falló por una violación de UNIQUE KEY inesperada. */
    IF v_Dup = 1 THEN
        ROLLBACK;
        
        /* Diagnóstico Post-Mortem: ¿Qué campo causó el error? */
        SET v_Id_Conflicto = NULL;
        
        /* Prueba 1: ¿Fue Código? */
        SELECT `Id_CatEstPart` INTO v_Id_Conflicto FROM `Cat_Estatus_Participante` 
        WHERE `Codigo` = _Codigo AND `Id_CatEstPart` <> _Id_Estatus LIMIT 1;

        IF v_Id_Conflicto IS NOT NULL THEN 
             SET v_Campo_Error = 'CODIGO';
        ELSE 
             /* Prueba 2: Fue Nombre */
             SELECT `Id_CatEstPart` INTO v_Id_Conflicto FROM `Cat_Estatus_Participante` 
             WHERE `Nombre` = _Nombre AND `Id_CatEstPart` <> _Id_Estatus LIMIT 1;
             SET v_Campo_Error = 'NOMBRE';
        END IF;

        /* Devolvemos el error estructurado al Frontend */
        SELECT 'Error de Concurrencia: Conflicto detectado al guardar.' AS Mensaje, 
               'CONFLICTO' AS Accion, 
               v_Campo_Error AS Campo,
               v_Id_Conflicto AS Id_Conflicto;
        LEAVE THIS_PROC;
    END IF;

    /* ========================================================================================
       BLOQUE 7: CONFIRMACIÓN EXITOSA
       Si llegamos aquí, todo salió bien. Hacemos permanentes los cambios.
       ======================================================================================== */
    COMMIT;
    
    SELECT 'ÉXITO: Estatus actualizado correctamente.' AS Mensaje, 
           'ACTUALIZADA' AS Accion, 
           _Id_Estatus AS Id_Estatus_Participante;

END$$

DELIMITER ;

/* ====================================================================================================
   PROCEDIMIENTO: SP_CambiarEstatusParticipante (Gestor de Ciclo de Vida)                    
   ====================================================================================================

   ----------------------------------------------------------------------------------------------------
   I. MANIFIESTO DE PROPÓSITO Y CONTEXTO OPERATIVO (THE "WHY")
   ----------------------------------------------------------------------------------------------------
   [DEFINICIÓN DEL COMPONENTE]:
   Este Stored Procedure (SP) no es un simple script de actualización. Es el **Gobernador de Disponibilidad**
   del catálogo `Cat_Estatus_Participante`. Su responsabilidad es administrar la transición de estados
   entre "Operativo" (1) y "Obsoleto/Baja Lógica" (0).

   [EL PROBLEMA DE LA "HISTORIA VIVA" (THE LIVE HISTORY PROBLEM)]:
   En este sistema, la tabla `Capacitaciones_Participantes` actúa como una bitácora histórica inmutable
   (no tiene borrado lógico). Esto presenta un desafío único para la integridad referencial:
   
   * Si desactivamos el estatus "INSCRITO", ¿qué pasa con los alumnos que están en clase AHORA MISMO?
   
   No podemos simplemente preguntar "¿Este estatus se ha usado antes?". La respuesta siempre será SÍ.
   Debemos preguntar: **"¿Este estatus se está usando en un proceso VIVO en este preciso segundo?"**

   [SOLUCIÓN: EL KILLSWITCH FORENSE DINÁMICO]:
   Implementamos un algoritmo de **Validación de Integridad Transitiva de 4 Niveles**:
   1.  Nivel 1 (El Estatus): ¿Quién lo tiene asignado?
   2.  Nivel 2 (El Alumno): ¿A qué capacitación pertenece ese alumno?
   3.  Nivel 3 (La Vida del Curso): ¿El registro del curso está activo (`Activo=1`)?
   4.  Nivel 4 (La Fase del Curso): ¿El curso está en una etapa operativa (No Final)?

   Solo si se superan los 4 niveles de riesgo, se bloquea la desactivación. De lo contrario, se permite
   archivar el estatus como "historia antigua".

   ----------------------------------------------------------------------------------------------------
   II. MATRIZ DE REGLAS DE BLINDAJE (HARD CONSTRAINTS)
   ----------------------------------------------------------------------------------------------------
   [RN-01] INTEGRIDAD DE DOMINIO (INPUT HYGIENE):
      - Principio: "Calidad a la entrada, calidad a la salida".
      - Mecanismo: Se rechazan explícitamente valores NULL o fuera del rango binario [0,1].
      - Objetivo: Prevenir comportamientos indefinidos por lógica trivalente de SQL.

   [RN-02] AISLAMIENTO SERIALIZABLE (ACID CONCURRENCY):
      - Principio: "Un solo escritor a la vez".
      - Mecanismo: Uso de `SELECT ... FOR UPDATE` (Bloqueo Pesimista / Pessimistic Locking).
      - Objetivo: Evitar la "Condición de Carrera" (Race Condition) donde dos administradores
        intentan modificar el mismo estatus simultáneamente.

   [RN-03] IDEMPOTENCIA DE ESTADO (RESOURCE OPTIMIZATION):
      - Principio: "Si no está roto, no lo arregles".
      - Mecanismo: Si el estado en disco ya es igual al solicitado, se aborta la escritura.
      - Objetivo: Reducir I/O de disco, evitar crecimiento del Transaction Log y preservar la
        fidelidad forense del campo `updated_at`.

   [RN-04] PROTOCOLO DE DESACTIVACIÓN SEGURA (SAFE DELETE):
      - Principio: "No apagues la luz si hay gente operando".
      - Mecanismo: Escaneo profundo de dependencias vivas mediante JOINs.
      - Acción: Error 409 (Conflict) si se detectan dependencias activas.

   ----------------------------------------------------------------------------------------------------
   III. ESPECIFICACIÓN TÉCNICA (TECHNICAL SPECS)
   ----------------------------------------------------------------------------------------------------
   - TIPO: Transacción Atómica.
   - SCOPE: `Cat_Estatus_Participante` (Target), `Capacitaciones_Participantes` (Dependency),
            `DatosCapacitaciones` (Context), `Cat_Estatus_Capacitacion` (Logic).
   - OUTPUT: JSON-Structure Resultset { Mensaje, Accion, Estado_Nuevo, Estado_Anterior, Id }.
   ==================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_CambiarEstatusParticipante`$$

CREATE PROCEDURE `SP_CambiarEstatusParticipante`(
    /* ------------------------------------------------------------------------------------------------
       SECCIÓN A: CAPA DE ENTRADA (INPUT PARAMETERS)
       Recibimos los datos atómicos necesarios para ejecutar la transacción.
       ------------------------------------------------------------------------------------------------ */
    IN _Id_Estatus    INT,       -- [OBLIGATORIO] Identificador Único (PK) del estatus a modificar.
    IN _Nuevo_Estatus TINYINT    -- [OBLIGATORIO] Bandera de estado deseado (1=Activar, 0=Desactivar).
)
THIS_PROC: BEGIN
    
    /* ============================================================================================
       SECCIÓN B: DECLARACIÓN DE VARIABLES Y CONTEXTO (VARIABLE SCOPE)
       Definimos los contenedores de memoria necesarios para el procesamiento lógico.
       ============================================================================================ */
    
    /* [B.1] Variables de Snapshot (Estado Previo):
       Almacenan la "foto" del registro tal como existe en disco antes de tocarlo.
       Vitales para la lógica de Idempotencia y para construir mensajes de error humanos. */
    DECLARE v_Nombre_Actual VARCHAR(255) DEFAULT NULL; -- Nombre descriptivo (ej: 'APROBADO')
    DECLARE v_Activo_Actual TINYINT      DEFAULT NULL; -- Estado actual (0 o 1)
    
    /* [B.2] Semáforo Forense (Integrity Flag):
       Variable crítica que almacenará el conteo de conflictos de integridad encontrados.
       Si este valor > 0, significa que hay riesgo operativo y debemos abortar. */
    DECLARE v_Dependencias_Vivas INT DEFAULT 0;

    /* [B.3] Variables de Diagnóstico (Debugging):
       Utilizadas para construir el mensaje de error detallado en caso de bloqueo. */
    DECLARE v_Folio_Curso_Conflicto VARCHAR(50) DEFAULT NULL; -- Para decirle al usuario QUÉ curso estorba.
    DECLARE v_Estado_Curso_Conflicto VARCHAR(255) DEFAULT NULL; -- Para decirle EN QUÉ estado está.

    /* [B.4] Buffer de Mensajería:
       Almacena el texto final que se enviará al cliente. */
    DECLARE v_Mensaje_Final TEXT;
    DECLARE v_Mensaje_Error TEXT;

    /* ============================================================================================
       SECCIÓN C: GESTIÓN DE EXCEPCIONES Y SEGURIDAD (SAFETY NET)
       Configuración de handlers para asegurar una salida limpia ante errores catastróficos.
       ============================================================================================ */
    
    /* [C.1] Handler Genérico (SQLEXCEPTION):
       Captura cualquier error no controlado (Deadlocks, Timeout, Disco Lleno, Sintaxis).
       ACCIÓN:
         1. ROLLBACK: Revertir cualquier cambio parcial.
         2. RESIGNAL: Propagar el error original al backend para que quede en el log del servidor. */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; 
    END;

    /* ============================================================================================
       SECCIÓN D: VALIDACIONES PREVIAS (FAIL FAST STRATEGY)
       Protegemos la base de datos rechazando peticiones "basura" antes de iniciar la transacción.
       ============================================================================================ */
    
    /* [D.1] Validación de Integridad de Identidad:
       El ID debe ser un número entero positivo. Un ID negativo o nulo es un error de sistema. */
    IF _Id_Estatus IS NULL OR _Id_Estatus <= 0 THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: El ID de Estatus proporcionado es inválido o nulo.';
    END IF;

    /* [D.2] Validación de Dominio Estricta:
       El estatus es un valor binario. SQL permite NULL, pero nuestra lógica de negocio NO.
       Rechazamos explícitamente los Nulos para evitar lógica trivalente peligrosa. */
    IF _Nuevo_Estatus IS NULL OR _Nuevo_Estatus NOT IN (0, 1) THEN
        SIGNAL SQLSTATE '45000' 
-- CAMBIO: Quitamos los guiones bajos para que se lea natural
        SET MESSAGE_TEXT = 'ERROR DE LÓGICA [400]: El campo "Nuevo Estatus" es obligatorio y solo acepta valores binarios: 0 (Inactivo) o 1 (Activo).';
    END IF;

    /* ============================================================================================
       SECCIÓN E: INICIO DE TRANSACCIÓN Y AISLAMIENTO (ACID BEGINS)
       A partir de este punto, entramos en modo "Atomicidad". O todo ocurre, o nada ocurre.
       ============================================================================================ */
    START TRANSACTION;

    /* --------------------------------------------------------------------------------------------
       PASO E.1: ADQUISICIÓN DE SNAPSHOT CON BLOQUEO (PESSIMISTIC LOCK)
       
       [QUÉ HACE]: Ejecuta un `SELECT ... FOR UPDATE`.
       
       [POR QUÉ LO HACEMOS]:
       Necesitamos "congelar" el tiempo para este registro. 
       - Imaginemos que el Admin A intenta desactivar el estatus.
       - Al mismo tiempo, el Admin B intenta cambiarle el nombre a "PENDIENTE URGENTE".
       - Sin bloqueo, podríamos desactivar un estatus que acaba de cambiar de significado.
       
       [EFECTO TÉCNICO]:
       InnoDB coloca un candado exclusivo (X-Lock) en la fila del índice primario.
       Nadie más puede leer (en modo lock) o escribir en esta fila hasta que terminemos.
       -------------------------------------------------------------------------------------------- */
    SELECT `Nombre`, `Activo`
    INTO v_Nombre_Actual, v_Activo_Actual
    FROM `Cat_Estatus_Participante`
    WHERE `Id_CatEstPart` = _Id_Estatus
    LIMIT 1
    FOR UPDATE;

    /* --------------------------------------------------------------------------------------------
       PASO E.2: VALIDACIÓN DE EXISTENCIA (NOT FOUND)
       Si las variables siguen siendo NULL después del SELECT, el registro no existe físicamente.
       -------------------------------------------------------------------------------------------- */
    IF v_Nombre_Actual IS NULL THEN
        ROLLBACK; -- Liberamos recursos del lock inmediatamente.
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [404]: El Estatus solicitado no existe en el catálogo maestro. Pudo haber sido eliminado previamente.';
    END IF;

    /* --------------------------------------------------------------------------------------------
       PASO E.3: VERIFICACIÓN DE IDEMPOTENCIA (OPTIMIZACIÓN)
       
       [LÓGICA]: "Si ya está encendido, no gastes energía en encenderlo de nuevo".
       
       [BENEFICIO CRÍTICO]: 
       1. **Ahorro de I/O:** No se escribe en disco si no es necesario.
       2. **Integridad de Auditoría:** Si hacemos un UPDATE con los mismos valores, MySQL podría
          actualizar el `updated_at` (dependiendo de la config). Queremos evitar falsos positivos
          de modificación.
       -------------------------------------------------------------------------------------------- */
    IF v_Activo_Actual = _Nuevo_Estatus THEN
        
        COMMIT; -- Liberamos el bloqueo. La transacción termina aquí benignamente.
        
        /* Construimos respuesta informativa */
        SELECT CONCAT('AVISO DE SISTEMA: El Estatus "', v_Nombre_Actual, '" ya se encuentra en el estado solicitado (', IF(_Nuevo_Estatus=1,'ACTIVO','INACTIVO'), '). No se requirieron cambios.') AS Mensaje,
               'SIN_CAMBIOS' AS Accion,
               v_Activo_Actual AS Estado_Anterior,
               _Nuevo_Estatus AS Estado_Nuevo;
        
        LEAVE THIS_PROC; -- Salida limpia y temprana del SP.
    END IF;

    /* ============================================================================================
       SECCIÓN F: ANÁLISIS DE IMPACTO Y KILLSWITCH (THE LOGIC CORE)
       Aquí reside la inteligencia del procedimiento. Decidimos si es seguro proceder.
       ============================================================================================ */
    
    /* --------------------------------------------------------------------------------------------
       CASO F.1: PROTOCOLO DE DESACTIVACIÓN (KILLSWITCH / BAJA LÓGICA)
       Condición: `_Nuevo_Estatus = 0` (El usuario quiere APAGAR el estatus).
       
       [RIESGO]: Dejar "ciegos" a los reportes de cursos actuales.
       [DEFENSA]: Integridad Referencial Transitiva.
       -------------------------------------------------------------------------------------------- */
    IF _Nuevo_Estatus = 0 THEN
        
        /* [CONSULTA FORENSE MULTI-NIVEL]:
           Buscamos si existe AL MENOS UN CASO que impida la desactivación.
           
           Navegación de la consulta:
           1. FROM `Capacitaciones_Participantes` CP: 
              -> ¿Hay alumnos con este estatus? (Histórico y Actual).
              
           2. INNER JOIN `DatosCapacitaciones` DC: 
              -> ¿A qué curso específico pertenecen esos alumnos?
              
           3. INNER JOIN `Capacitaciones` C:
              -> Necesario para obtener el Folio (Numero_Capacitacion) para el error.
              
           4. INNER JOIN `Cat_Estatus_Capacitacion` EC:
              -> EL CEREBRO. Consultamos la bandera `Es_Final`.
              
           5. WHERE ...
              -> CP.Fk... = _Id_Estatus: Filtramos por el estatus que queremos borrar.
              -> DC.Activo = 1: El registro histórico del curso es el vigente.
              -> EC.Es_Final = 0: EL CURSO ESTÁ VIVO (No ha finalizado).
        */
        
        SELECT 
            C.Numero_Capacitacion, -- Evidencia 1: El folio del curso culpable
            EC.Nombre              -- Evidencia 2: El estado del curso (ej: "EN CURSO")
        INTO 
            v_Folio_Curso_Conflicto,
            v_Estado_Curso_Conflicto
        FROM `Capacitaciones_Participantes` CP
        
        /* Conexión con el Historial del Curso */
        INNER JOIN `DatosCapacitaciones` DC ON CP.Fk_Id_DatosCap = DC.Id_DatosCap
        
        /* Conexión con la Cabecera del Curso (Para el Folio) */
        INNER JOIN `Capacitaciones` C ON DC.Fk_Id_Capacitacion = C.Id_Capacitacion
        
        /* Conexión con el Catálogo de Estatus del Curso (Para la Lógica de Negocio) */
        INNER JOIN `Cat_Estatus_Capacitacion` EC ON DC.Fk_Id_CatEstCap = EC.Id_CatEstCap
        
        WHERE 
            CP.Fk_Id_CatEstPart = _Id_Estatus  -- Buscamos uso de ESTE estatus
            AND DC.Activo = 1                  -- En cursos que no han sido borrados (Soft Delete)
            AND C.Activo = 1                   -- En cabeceras que no han sido borradas
            
            /* --- EL CANDADO MAESTRO --- */
            AND EC.Es_Final = 0                -- Solo nos importan los cursos OPERATIVOS.
                                               -- Si Es_Final=1 (Finalizado/Cancelado), no bloqueamos.
        
        LIMIT 1; -- Con encontrar UN solo conflicto es suficiente para abortar.

        /* [EVALUACIÓN DEL SEMÁFORO]:
           Si las variables de conflicto se llenaron (IS NOT NULL), tenemos un problema. */
        IF v_Folio_Curso_Conflicto IS NOT NULL THEN
            
            ROLLBACK; -- Cancelación inmediata de la transacción. Seguridad ante todo.
            
            /* Construcción del Mensaje Forense:
               Le explicamos al usuario EXACTAMENTE por qué no puede proceder. */
            SET v_Mensaje_Error = CONCAT(
                'BLOQUEO DE INTEGRIDAD [409]: Operación Denegada. ',
                'No se puede desactivar el estatus "', v_Nombre_Actual, '" ',
                'porque está siendo utilizado activamente por participantes en el curso con Folio "', v_Folio_Curso_Conflicto, '" ',
                'que se encuentra actualmente en estado "', v_Estado_Curso_Conflicto, '". ',
                'Este curso se considera OPERATIVO (No Finalizado). ',
                'Para proceder, debe finalizar el curso o cambiar el estatus de los alumnos involucrados.'
            );
                                   
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_Mensaje_Error;
        END IF;
        
        /* Si llegamos aquí, significa que v_Folio_Curso_Conflicto es NULL.
           El estatus puede haber sido usado 1000 veces en el pasado, pero NO se está usando
           en ningún curso vivo hoy. Es seguro proceder. */
    END IF;

    /* --------------------------------------------------------------------------------------------
       CASO F.2: PROTOCOLO DE REACTIVACIÓN (RESURRECTION)
       Condición: `_Nuevo_Estatus = 1` (El usuario quiere PRENDER el estatus).
       
       [ANÁLISIS]:
       Reactivar es seguro. No rompe integridad. Solo vuelve disponible una opción.
       No requiere validaciones adicionales en este diseño.
       -------------------------------------------------------------------------------------------- */
    IF _Nuevo_Estatus = 1 THEN
        -- Pasamos directo a la persistencia.
        SET v_Dependencias_Vivas = 0; 
    END IF;

    /* ============================================================================================
       SECCIÓN G: PERSISTENCIA Y CIERRE (COMMIT PHASE)
       Si el flujo llega a este punto, hemos pasado todas las aduanas de seguridad forense.
       ============================================================================================ */
    
    /* G.1 Ejecución del Cambio de Estado (UPDATE) */
    UPDATE `Cat_Estatus_Participante`
    SET `Activo` = _Nuevo_Estatus,
        `updated_at` = NOW() -- Auditoría: Se marca el momento exacto de la modificación.
    WHERE `Id_CatEstPart` = _Id_Estatus;

    /* G.2 Confirmación de la Transacción */
    COMMIT; -- Los cambios se hacen permanentes y visibles para otros usuarios. Se libera el Lock.

    /* ============================================================================================
       SECCIÓN H: RESPUESTA AL CLIENTE (FEEDBACK LAYER)
       Generamos un mensaje humano que confirme la acción específica realizada.
       ============================================================================================ */
    SELECT 
        CASE 
            WHEN _Nuevo_Estatus = 1 THEN CONCAT('ÉXITO: El Estatus "', v_Nombre_Actual, '" ha sido REACTIVADO y está disponible nuevamente en los selectores operativos.')
            ELSE CONCAT('ÉXITO: El Estatus "', v_Nombre_Actual, '" ha sido DESACTIVADO (Baja Lógica). Se mantendrá en el histórico pero no podrá seleccionarse en nuevos registros.')
        END AS Mensaje,
        'ESTATUS_CAMBIADO' AS Accion,
        v_Activo_Actual AS Estado_Anterior,
        _Nuevo_Estatus AS Estado_Nuevo,
        _Id_Estatus AS Id_Estatus_Participante;

END$$

DELIMITER ;

/* ====================================================================================================
   PROCEDIMIENTOS: SP_EliminarEstatusParticipanteFisico (Hard Delete / Purga)
   ====================================================================================================

   ----------------------------------------------------------------------------------------------------
   I. MANIFIESTO DE SEGURIDAD Y PROPÓSITO (THE SAFETY MANIFESTO)
   ----------------------------------------------------------------------------------------------------
   [DEFINICIÓN DEL COMPONENTE]:
   Este procedimiento almacenado implementa el mecanismo de **Eliminación Física** (`DELETE`) para un 
   registro del catálogo `Cat_Estatus_Participante`. A diferencia de la desactivación lógica 
   (`SP_CambiarEstatus`), esta operación elimina los bits de datos del disco duro de manera permanente. 
   No existe posibilidad de recuperación ("Rollback") una vez confirmado el `COMMIT`.

   [CASO DE USO LEGÍTIMO - "DATA HYGIENE"]:
   Esta herramienta está diseñada EXCLUSIVAMENTE para la **Corrección de Errores de Captura Inmediata** (Saneamiento de Datos).
   
   * Escenario Válido: El administrador crea el estatus "Aprovado" (con error ortográfico). Se da cuenta 
     al instante (T < 1 min). Nadie lo ha usado aún. En lugar de desactivarlo y dejar "basura" en la BD, 
     se utiliza este SP para purgarlo y mantener el catálogo impoluto.

   [LA REGLA DE "CERO TOLERANCIA" (ZERO TOLERANCE POLICY)]:
   Para garantizar la Integridad Referencial Dura (Hard Referential Integrity), este SP aplica la regla 
   más estricta del sistema de bases de datos relacionales:
   
   > "Un Padre no puede ser eliminado si tiene siquiera un Hijo, vivo, muerto o archivado."

   [DIFERENCIA CRÍTICA CON SOFT DELETE]:
   - Soft Delete: Permite apagar un estatus si el curso ya terminó. (Preserva la historia).
   - Hard Delete: Bloquea la eliminación si existe CUALQUIER registro histórico. (Protege la integridad).
   
   No importa si el curso donde se usó está "Activo", "Cancelado", "Finalizado" o "Archivado". 
   Si existe una sola fila en la tabla `Capacitaciones_Participantes` vinculada a este estatus, 
   la eliminación se bloquea. Borrarlo rompería la llave foránea (FK) y corrompería el historial 
   académico de los participantes.

   ----------------------------------------------------------------------------------------------------
   II. MATRIZ DE REGLAS DE BLINDAJE (DESTRUCTIVE RULES MATRIX)
   ----------------------------------------------------------------------------------------------------
   [RN-01] VERIFICACIÓN DE EXISTENCIA PREVIA (FAIL FAST PATTERN):
      - Principio: "No intentar matar lo que ya está muerto".
      - Mecanismo: Validamos que el registro exista antes de intentar borrarlo.
      - Beneficio: Permite devolver un error 404 (Not Found) preciso, en lugar de un mensaje genérico 
        de "0 filas afectadas".

   [RN-02] BLOQUEO DE RECURSO (PESSIMISTIC CONCURRENCY LOCK):
      - Principio: "Aislamiento Serializable".
      - Mecanismo: Se adquiere un bloqueo exclusivo (`FOR UPDATE`) sobre la fila a borrar al inicio 
        de la transacción.
      - Justificación: Esto evita la "Condición de Carrera" (Race Condition) donde el Usuario A 
        intenta borrar el estatus mientras el Usuario B le asigna un alumno en el mismo milisegundo.

   [RN-03] ESCANEO DE DEPENDENCIAS TOTALES (TOTAL FORENSIC SCAN):
      - Principio: "Integridad sobre Conveniencia".
      - Mecanismo: Se consulta `Capacitaciones_Participantes` sin filtros de estado.
      - Condición: `COUNT(*) > 0`.
      - Acción: Si se encuentra cualquier uso (histórico o actual), se aborta con Error 409.
      
   [RN-04] PROTECCIÓN DE MOTOR (LAST LINE OF DEFENSE):
      - Principio: "Defensa en Profundidad".
      - Mecanismo: Si fallara la validación lógica manual (RN-03), el `HANDLER 1451` captura el error 
        nativo de Foreign Key de MySQL.
      - Beneficio: Evita que el usuario final vea errores técnicos crípticos del motor SQL.

   ----------------------------------------------------------------------------------------------------
   III. ESPECIFICACIÓN TÉCNICA (TECHNICAL SPECS)
   ----------------------------------------------------------------------------------------------------
   - INPUT: `_Id_Estatus` (INT).
   - OUTPUT: JSON { Mensaje, Accion, Id_Eliminado }.
   - LOCKING STRATEGY: `X-Lock` (Exclusive Row Lock) via InnoDB.
   - ISOLATION LEVEL: Read Committed (por defecto) elevado a Serializable para la fila objetivo.
   ==================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_EliminarEstatusParticipanteFisico`$$

CREATE PROCEDURE `SP_EliminarEstatusParticipanteFisico`(
    /* -----------------------------------------------------------------
       PARÁMETROS DE ENTRADA (INPUT LAYER)
       Recibe el identificador atómico del recurso a destruir.
       ----------------------------------------------------------------- */
    IN _Id_Estatus INT -- [OBLIGATORIO] ID único (PK) del estatus a purgar.
)
THIS_PROC: BEGIN
    
    /* ============================================================================================
       SECCIÓN A: DECLARACIÓN DE VARIABLES Y CONTEXTO (VARIABLE SCOPE)
       Inicialización de contenedores de memoria para el diagnóstico forense.
       ============================================================================================ */
    
    /* [Variable de Evidencia]: 
       Almacena el nombre del registro antes de borrarlo. 
       Se usa para confirmar al usuario QUÉ fue lo que eliminó en el mensaje de éxito. */
    DECLARE v_Nombre_Actual VARCHAR(255);
    
    /* [Semáforo de Integridad]: 
       Variable crítica. Almacena el conteo de referencias encontradas en tablas hijas.
       Si > 0, es un bloqueo absoluto. */
    DECLARE v_Dependencias_Totales INT DEFAULT 0;
    
    /* [Buffer de Mensajería]: 
       Para construir mensajes de error dinámicos y detallados en tiempo de ejecución. */
    DECLARE v_Mensaje_Error TEXT;

    /* ============================================================================================
       SECCIÓN B: HANDLERS DE SEGURIDAD (EXCEPTION HANDLING LAYER)
       Configuración de la "Red de Seguridad" para atrapar errores del motor de base de datos.
       ============================================================================================ */
    
    /* [B.1] Handler de Integridad Referencial (Error MySQL 1451)
       OBJETIVO: Actuar como "Paracaídas". 
       ESCENARIO: Si agregamos una nueva tabla en el futuro que use este estatus y olvidamos 
       actualizar la validación manual de este SP, el motor bloqueará el DELETE.
       ACCIÓN: Este handler atrapa ese bloqueo técnico y devuelve un mensaje humano. */
    DECLARE EXIT HANDLER FOR 1451 
    BEGIN 
        ROLLBACK; -- Deshacer transacción inmediatamente.
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'BLOQUEO DE SISTEMA [1451]: La base de datos impidió la eliminación porque existen vínculos en tablas del sistema no detectados por la lógica de negocio (Integridad Referencial).'; 
    END;

    /* [B.2] Handler Genérico (SQLEXCEPTION)
       OBJETIVO: Capturar fallos de infraestructura (Disco lleno, Timeout, Conexión caída). */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; -- Propagar el error original al backend para logs de sistema.
    END;

    /* ============================================================================================
       SECCIÓN C: VALIDACIONES PREVIAS (FAIL FAST STRATEGY)
       Filtrado de peticiones inválidas antes de iniciar transacciones costosas.
       ============================================================================================ */
    
    /* [C.1] Validación de Integridad de Entrada (Type Safety)
       Asegura que el ID sea un número positivo. */
    IF _Id_Estatus IS NULL OR _Id_Estatus <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: ID de Estatus inválido o nulo. Verifique la petición.';
    END IF;

    /* ============================================================================================
       SECCIÓN D: INICIO DE TRANSACCIÓN Y BLOQUEO (ACID TRANSACTION START)
       A partir de aquí, las operaciones son atómicas y aisladas.
       ============================================================================================ */
    START TRANSACTION;

    /* --------------------------------------------------------------------------------------------
       PASO D.1: IDENTIFICACIÓN Y BLOQUEO PESIMISTA (PESSIMISTIC LOCKING)
       
       
       [ESTRATEGIA TÉCNICA]:
       Ejecutamos `SELECT ... FOR UPDATE`.
       
       [IMPACTO EN EL MOTOR]:
       InnoDB adquiere un "Exclusive Lock (X)" sobre la fila específica en el índice primario.
       
       [JUSTIFICACIÓN DE NEGOCIO]:
       Estamos "secuestrando" el registro. Mientras esta transacción esté viva, nadie más puede:
         1. Asignar este estatus a un alumno (INSERT en tabla hija).
         2. Modificar este estatus (UPDATE).
         3. Borrar este estatus (DELETE concurrente).
       Esto garantiza que nuestro escaneo de dependencias sea válido hasta el final.
       -------------------------------------------------------------------------------------------- */
    SELECT `Nombre` INTO v_Nombre_Actual
    FROM `Cat_Estatus_Participante`
    WHERE `Id_CatEstPart` = _Id_Estatus
    LIMIT 1
    FOR UPDATE;

    /* [D.2] Validación de Existencia (404 Check)
       Si la variable sigue siendo NULL, el registro no existe físicamente. */
    IF v_Nombre_Actual IS NULL THEN
        ROLLBACK; -- Liberar recursos.
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [404]: El Estatus no existe o ya fue eliminado previamente.';
    END IF;

    /* ============================================================================================
       SECCIÓN E: ESCANEO DE DEPENDENCIAS (LA REGLA DE CERO TOLERANCIA)
       Aquí reside la diferencia crítica con el Soft Delete.
       ============================================================================================ */
    
    /* --------------------------------------------------------------------------------------------
       PASO E.1: CONSULTA DE USO HISTÓRICO TOTAL (FORENSIC SCAN)
       
       [ANÁLISIS DE LA CONSULTA]:
       1. TARGET: Tabla `Capacitaciones_Participantes` (La tabla de hechos).
       2. FILTRO: `Fk_Id_CatEstPart` = ID Objetivo.
       3. SCOPE: **GLOBAL**. 
          - NO hacemos JOIN con `DatosCapacitaciones`.
          - NO preguntamos si el curso está activo (`Activo=1`).
          - NO preguntamos si el curso finalizó (`Es_Final=1`).
          - NO preguntamos si el curso fue borrado (`Activo=0`).
       
       [FILOSOFÍA]: "Si existe un registro hijo, el padre es inmortal".
       Incluso si el curso fue borrado hace 10 años, la integridad referencial física de la BD 
       exige que la llave foránea apunte a algo existente. Borrar el padre dejaría un "Hijo Huérfano"
       o rompería el constraint físico.
       -------------------------------------------------------------------------------------------- */
    SELECT COUNT(*) INTO v_Dependencias_Totales
    FROM `Capacitaciones_Participantes`
    WHERE `Fk_Id_CatEstPart` = _Id_Estatus;

    /* --------------------------------------------------------------------------------------------
       PASO E.2: EVALUACIÓN DE BLOQUEO (DECISION GATE)
       Si el contador es > 0, se activa el protocolo de rechazo.
       -------------------------------------------------------------------------------------------- */
    IF v_Dependencias_Totales > 0 THEN
        
        ROLLBACK; -- Liberar el bloqueo y cancelar la transacción inmediatamente.
        
        /* Construcción del Mensaje Humano:
           Explicamos claramente al usuario la razón técnica del bloqueo. */
        SET v_Mensaje_Error = CONCAT(
            'BLOQUEO DE INTEGRIDAD REFERENCIAL [409]: Operación Denegada. ',
            'No es posible ELIMINAR FÍSICAMENTE el estatus "', v_Nombre_Actual, '". ',
            'El sistema detectó ', v_Dependencias_Totales, ' registros históricos de participantes asociados a este estatus. ',
            'Nota Técnica: Aunque los cursos hayan finalizado, estén archivados o borrados, la integridad de la base de datos impide borrar un catálogo con historial. ',
            'SOLUCIÓN: Utilice la opción de "Desactivar" (Baja Lógica) en su lugar.'
        );
                               
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_Mensaje_Error;
    END IF;

    /* ============================================================================================
       SECCIÓN F: EJECUCIÓN DESTRUCTIVA (HARD DELETE EXECUTION)
       Si el flujo llega a este punto, hemos certificado que el registro está "limpio", "virgen" 
       y "solo". Es seguro proceder con la destrucción.
       ============================================================================================ */
    
    /* [F.1] Ejecución del Comando de Borrado
       Esta instrucción elimina la fila de la página de datos del disco. */
    DELETE FROM `Cat_Estatus_Participante`
    WHERE `Id_CatEstPart` = _Id_Estatus;

    /* ============================================================================================
       SECCIÓN G: CONFIRMACIÓN Y RESPUESTA (COMMIT & FEEDBACK)
       Finalización exitosa del protocolo.
       ============================================================================================ */
    
    /* [G.1] Confirmación de Transacción (COMMIT)
       Hacemos permanentes los cambios. 
       - El registro deja de existir.
       - El bloqueo (X-Lock) se libera.
       - El espacio en disco se marca como disponible. */
    COMMIT;

    /* [G.2] Respuesta Estructurada al Frontend
       Devolvemos un objeto JSON-like para que la UI pueda actualizarse (ej: quitar la fila de la tabla). */
    SELECT 
        CONCAT('ÉXITO: El Estatus "', v_Nombre_Actual, '" ha sido ELIMINADO permanentemente del sistema.') AS Mensaje,
        'ELIMINACION_FISICA_COMPLETA' AS Accion,
        _Id_Estatus AS Id_Estatus_Eliminado,
        NOW() AS Fecha_Ejecucion;

END$$

DELIMITER ;

