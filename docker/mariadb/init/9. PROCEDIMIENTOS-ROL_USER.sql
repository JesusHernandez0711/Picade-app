USE `PICADE`;

/* ------------------------------------------------------------------------------------------------------ */
/* CREACION DE VISTAS Y PROCEDIMIENTOS DE ALMACENADO PARA LA BASE DE DATOS                                */
/* ------------------------------------------------------------------------------------------------------ */

/* ======================================================================================================
   VIEW: Vista_Roles
   ======================================================================================================
   1. OBJETIVO TÉCNICO Y ESTRATÉGICO
   ---------------------------------
   Esta vista constituye la **Interfaz Canónica de Seguridad** para el sistema PICADE. 
   Su función principal es desacoplar la estructura física de la tabla `Cat_Roles` de la lógica de 
   autenticación y autorización consumida por el Backend (Laravel) y el Frontend.

   Al centralizar la lectura de roles aquí, garantizamos que cualquier cambio futuro en la tabla base 
   (ej: agregar campos de auditoría extra) no rompa el módulo de login ni el middleware de permisos.

   2. ARQUITECTURA DE DATOS (NORMALIZACIÓN SEMÁNTICA)
   --------------------------------------------------
   Siguiendo el patrón establecido en el sistema, esta vista aplica una normalización de nomenclatura 
   para garantizar que el objeto JSON resultante sea autodocumentado:
   
   - Estandarización de Identificadores: `Id_Rol` se mantiene, pero se asegura su visibilidad clara.
   - Nomenclatura de Negocio: Se transforman columnas genéricas como `Codigo` y `Nombre` a 
     `Codigo_Rol` y `Nombre_Rol`. Esto evita colisiones de nombres cuando se realizan cruces (JOINs) 
     con tablas de Usuarios (`Users`) en consultas complejas.

   3. GESTIÓN DEL CICLO DE VIDA (SOFT DELETES)
   -------------------------------------------
   - Principio de Visibilidad Total: La vista expone **TODOS** los roles, tanto activos (`1`) como 
     inactivos (`0`).
   - Justificación de Seguridad: Un Administrador debe ser capaz de auditar qué usuarios tenían un rol 
     que ha sido desactivado. Ocultar los roles inactivos en esta capa podría generar errores de 
     integridad referencial en los reportes históricos de accesos.
   - El filtrado para listas desplegables (ej: "Asignar Rol") debe realizarse en el `WHERE` del consumidor.

   4. DICCIONARIO DE DATOS (CONTRATO DE SALIDA)
   --------------------------------------------
   [Bloque A: Identidad y Control de Acceso]
   - Id_Rol:          (INT) Llave Primaria. Identificador único del permiso.
   - Codigo_Rol:      (VARCHAR) Slug o Keyword técnico (ej: 'ADMIN_GRAL', 'SOPORTE'). 
                      Vital para los Middlewares de autorización en código (ej: @can('ADMIN_GRAL')).
   - Nombre_Rol:      (VARCHAR) Etiqueta legible para humanos (ej: 'Administrador General').

   [Bloque B: Contexto]
   - Descripcion_Rol: (VARCHAR) Explicación del alcance y limitaciones del rol.

   [Bloque C: Metadatos de Estado]
   - Estatus_Rol:     (TINYINT) 1 = Activo/Asignable, 0 = Revocado/Histórico.
   ====================================================================================================== */

-- DROP VIEW IF EXISTS `PICADE`.`Vista_Roles`;

CREATE OR REPLACE
    ALGORITHM = UNDEFINED 
    SQL SECURITY DEFINER
VIEW `PICADE`.`Vista_Roles` AS
    SELECT 
        /* -----------------------------------------------------------------------------------
           BLOQUE 1: IDENTIDAD Y CLAVES DE AUTORIZACIÓN
           Renombramiento estratégico para evitar ambigüedad en JOINs con tabla de Usuarios.
           ----------------------------------------------------------------------------------- */
        `Roles`.`Id_Rol`              AS `Id_Rol`,
        `Roles`.`Codigo`              AS `Codigo_Rol`,  -- Key sensitive para Middlewares
        `Roles`.`Nombre`              AS `Nombre_Rol`,  -- Label para UI

        /* -----------------------------------------------------------------------------------
           BLOQUE 2: DETALLES INFORMATIVOS
           Información de soporte para los tooltips en el panel de administración de usuarios.
           ----------------------------------------------------------------------------------- */
        `Roles`.`Descripcion`         AS `Descripcion_Rol`,

        /* -----------------------------------------------------------------------------------
           BLOQUE 3: METADATOS DE CONTROL (ESTATUS)
           Mapeo semántico: 'Activo' -> 'Estatus_Rol'.
           Permite al Admin ver roles deprecados para reactivarlos si es necesario.
           ----------------------------------------------------------------------------------- */
        `Roles`.`Activo`              AS `Estatus_Rol`
        
        /* -----------------------------------------------------------------------------------
           BLOQUE 4: TRAZABILIDAD (AUDITORÍA)
           Se mantienen disponibles pero comentados para mantener la vista ligera (Lightweight).
           Descomentar si el módulo de Auditoría requiere ver fechas de creación desde la vista.
           ----------------------------------------------------------------------------------- */
        -- , `Roles`.`created_at`
        -- , `Roles`.`updated_at`

    FROM
        `PICADE`.`Cat_Roles` `Roles`;

/* ====================================================================================================
   PROCEDIMIENTO: SP_RegistrarRol
   ====================================================================================================
   
   1. CONTEXTO ARQUITECTÓNICO Y OBJETIVO DE NEGOCIO
   ----------------------------------------------------------------------------------------------------
   Este procedimiento constituye el **Núcleo de la Gestión de Seguridad (RBAC)**. 
   Implementa el patrón de "Alta Transaccional Idempotente" para la entidad `Cat_Roles`.
   Su objetivo es garantizar que la creación de perfiles de acceso sea atómica, consistente y 
   resistente a condiciones de carrera en entornos de alta concurrencia.

   2. REGLAS DE NEGOCIO Y RESTRICCIONES DURAS (HARD CONSTRAINTS)
   ----------------------------------------------------------------------------------------------------
   A) SANITIZACIÓN E INTEGRIDAD DE ENTRADA (INPUT HYGIENE):
      - Principio "Fail Fast": Se rechazan cadenas vacías o nulas antes de iniciar la transacción.
      - Normalización: `TRIM` forzoso para evitar duplicados visuales (" ADMIN" vs "ADMIN").

   B) IDENTIDAD DUAL (DUAL IDENTITY VERIFICATION):
      El sistema impone una restricción de unicidad de dos niveles:
      1. Nivel Técnico (Strong ID): El `Código` (Slug) debe ser único (ej: 'SYS_ADMIN').
      2. Nivel Semántico (Weak ID): El `Nombre` debe ser único (ej: 'Administrador del Sistema').
      
      * Resolución de Conflictos: Se prioriza la existencia del Código. Si el Código es nuevo 
        pero el Nombre ya existe bajo otro Código, se bloquea la operación para evitar ambigüedad.

   3. ESTRATEGIA DE VALIDACIÓN HÍBRIDA (DB vs APP LAYER)
   ----------------------------------------------------------------------------------------------------
   A) FLEXIBILIDAD DEL ESQUEMA (Database Layer):
      - La tabla `Cat_Roles` permite que `Descripcion` sea NULL.
      - Razón: Compatibilidad con procesos ETL o cargas masivas históricas (CSV).

   B) RIGIDEZ DEL PROCEDIMIENTO (Application Layer):
      - Regla: La `Descripcion` es OBLIGATORIA. No se permite crear roles "mudos" desde el sistema.
      - Justificación: Garantizar documentación viva dentro del catálogo de seguridad.

   4. ESTRATEGIA DE PERSISTENCIA Y CONCURRENCIA (ACID PATTERNS)
   ----------------------------------------------------------------------------------------------------
   A) BLOQUEO PESIMISTA (PESSIMISTIC WRITE LOCK):
      - Uso de `SELECT ... FOR UPDATE`.
      - Justificación: Serializa las peticiones concurrentes sobre un mismo recurso potencial. 
        Evita "Lecturas Fantasma" donde dos administradores validan "que no existe" al mismo tiempo.

   B) AUTOSANACIÓN (SELF-HEALING / SOFT DELETE RECOVERY):
      - Si el rol existe pero tiene `Activo = 0` (Borrado Lógico), el sistema NO devuelve error.
      - Acción: Reactiva el registro, actualiza sus metadatos (Descripción) y retorna éxito.

   C) PATRÓN DE RECUPERACIÓN "RE-RESOLVE" (CONCURRENCY TOLERANCE):
      - Maneja la ventana de tiempo infinitesimal entre el SELECT y el INSERT donde puede ocurrir 
        una colisión (Error 1062).
      - Mecánica: Captura el error -> Rollback Silencioso -> Nueva Transacción -> Lectura del Ganador.

   5. CONTRATO DE RESPUESTA (OUTPUT SPECIFICATION)
   ----------------------------------------------------------------------------------------------------
   Devuelve un Resultset de fila única con:
      - [Mensaje]: Feedback descriptivo para UI (Toast Notification).
      - [Id_Rol]: Llave primaria del recurso manipulado.
      - [Accion]: Enumerador de estado ('CREADA', 'REACTIVADA', 'REUSADA').
   ==================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_RegistrarRol`$$

CREATE PROCEDURE `SP_RegistrarRol`(
    /* -----------------------------------------------------------------
       PARÁMETROS DE ENTRADA (INPUT LAYER)
       Se asumen tipos de datos crudos (Raw Data) que requieren limpieza.
       ----------------------------------------------------------------- */
    IN _Codigo      VARCHAR(50),   -- OBLIGATORIO: Identificador técnico para Middlewares (ej: 'RH_SUPERVISOR')
    IN _Nombre      VARCHAR(255),  -- OBLIGATORIO: Etiqueta legible para la Interfaz de Usuario.
    IN _Descripcion VARCHAR(255)   -- OBLIGATORIO: Contexto detallado (Regla de Negocio Estricta)
)
THIS_PROC: BEGIN
    
    /* ================================================================================================
       BLOQUE 0: INICIALIZACIÓN DE VARIABLES DE ENTORNO
       Propósito: Definir contenedores para el estado de la base de datos y banderas de control.
       ================================================================================================ */
    
    /* Variables de Snapshot: Capturan el estado actual del registro si es encontrado */
    DECLARE v_Id_Rol INT DEFAULT NULL;
    DECLARE v_Activo TINYINT(1) DEFAULT NULL;
    
    /* Variables de Cross-Check: Para validación cruzada de integridad (Código vs Nombre) */
    DECLARE v_Nombre_Existente VARCHAR(255) DEFAULT NULL;
    DECLARE v_Codigo_Existente VARCHAR(50) DEFAULT NULL;
    
    /* Bandera de Semáforo: Controla el flujo lógico cuando ocurren excepciones SQL controladas */
    DECLARE v_Dup TINYINT(1) DEFAULT 0;

    /* ================================================================================================
       BLOQUE 1: DEFINICIÓN DE HANDLERS (MANEJO ROBUSTO DE EXCEPCIONES)
       Propósito: Asegurar la atomicidad y la recuperación ante fallos.
       ================================================================================================ */
    
    /* 1.1 HANDLER DE COLISIÓN (Error 1062 - Duplicate Entry)
       Estrategia: "Graceful Degradation". Si el INSERT falla por duplicado, no abortamos el SP.
       Marcamos la bandera v_Dup = 1 para activar la subrutina de recuperación (Re-Resolve). */
    DECLARE CONTINUE HANDLER FOR 1062 SET v_Dup = 1;

    /* 1.2 HANDLER CRÍTICO (SQLEXCEPTION)
       Estrategia: "Abort & Report". Ante fallos de sistema (conexión, disco, sintaxis), 
       revertimos cualquier cambio parcial y propagamos el error. */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; 
    END;

    /* ================================================================================================
       BLOQUE 2: SANITIZACIÓN Y VALIDACIÓN PREVIA (FAIL FAST STRATEGY)
       Propósito: Proteger la base de datos de datos basura antes de abrir transacciones costosas.
       ================================================================================================ */
    
    /* 2.1 NORMALIZACIÓN DE CADENAS
       Eliminamos espacios redundantes. NULLIF convierte cadenas vacías '' en NULL reales. */
    SET _Codigo      = NULLIF(TRIM(_Codigo), '');
    SET _Nombre      = NULLIF(TRIM(_Nombre), '');
    SET _Descripcion = NULLIF(TRIM(_Descripcion), '');

    /* 2.2 VALIDACIÓN DE INTEGRIDAD DE CAMPOS OBLIGATORIOS
       Regla: Un Rol sin Código, Nombre o Descripción es una entidad corrupta para el formulario. */
    
    IF _Codigo IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN [400]: El campo CÓDIGO es obligatorio.';
    END IF;

    IF _Nombre IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN [400]: El campo NOMBRE es obligatorio.';
    END IF;

    /* Aplicación de la Regla de Negocio Híbrida: Aunque la BD acepte NULL, aquí exigimos valor. */
    IF _Descripcion IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN [400]: La DESCRIPCIÓN del Rol es obligatoria. Debe detallar el alcance del permiso.';
    END IF;

    /* ================================================================================================
       BLOQUE 3: LÓGICA TRANSACCIONAL PRINCIPAL (CORE BUSINESS LOGIC)
       Propósito: Ejecutar la búsqueda, validación y persistencia de forma atómica.
       ================================================================================================ */
    START TRANSACTION;

    /* ------------------------------------------------------------------------------------------------
       PASO 3.1: VERIFICACIÓN PRIMARIA POR CÓDIGO (STRONG ID CHECK)
       Objetivo: Determinar si el identificador técnico ya existe.
       Estrategia: Bloqueo Pesimista (FOR UPDATE) para serializar el acceso a este registro.
       ------------------------------------------------------------------------------------------------ */
    SET v_Id_Rol = NULL; -- Reset de seguridad

    SELECT `Id_Rol`, `Nombre`, `Activo` 
    INTO v_Id_Rol, v_Nombre_Existente, v_Activo
    FROM `Cat_Roles`
    WHERE `Codigo` = _Codigo
    LIMIT 1
    FOR UPDATE; -- <--- BLOQUEO DE ESCRITURA AQUÍ

    /* ESCENARIO A: EL CÓDIGO YA EXISTE EN LA BASE DE DATOS */
    IF v_Id_Rol IS NOT NULL THEN
        
        /* A.1 Validación de Consistencia Semántica
           Regla: Si el código existe, el Nombre asociado debe coincidir con el input.
           Si el código es igual pero el nombre diferente, es un conflicto de integridad. */
        IF v_Nombre_Existente <> _Nombre THEN
            SIGNAL SQLSTATE '45000' 
                SET MESSAGE_TEXT = 'CONFLICTO DE INTEGRIDAD [409]: El CÓDIGO ya existe pero pertenece a un Rol con distinto NOMBRE.';
        END IF;

        /* A.2 Autosanación (Self-Healing)
           Si el registro existe pero está borrado lógicamente (Activo=0), lo recuperamos. 
           NOTA: Se fuerza la actualización de la Descripción con el nuevo dato obligatorio. */
        IF v_Activo = 0 THEN
            UPDATE `Cat_Roles`
            SET `Activo` = 1,
                `Descripcion` = _Descripcion, -- Actualización mandataria
                `updated_at` = NOW()
            WHERE `Id_Rol` = v_Id_Rol;
            
            COMMIT; 
            SELECT 'ÉXITO: Rol reactivado y actualizado.' AS Mensaje, v_Id_Rol AS Id_Rol, 'REACTIVADA' AS Accion; 
            LEAVE THIS_PROC;
        
        /* A.3 Idempotencia
           Si ya existe y está activo, no duplicamos ni fallamos. Reportamos éxito silente. */
        ELSE
            COMMIT; 
            SELECT 'AVISO: El Rol ya existe y está activo.' AS Mensaje, v_Id_Rol AS Id_Rol, 'REUSADA' AS Accion; 
            LEAVE THIS_PROC;
        END IF;
    END IF;

    /* ------------------------------------------------------------------------------------------------
       PASO 3.2: VERIFICACIÓN SECUNDARIA POR NOMBRE (WEAK ID CHECK)
       Objetivo: Si el Código es nuevo, asegurarnos que el NOMBRE no esté ocupado por otro código.
       Esto previene duplicados semánticos (ej: dos roles 'Admin' con códigos distintos).
       ------------------------------------------------------------------------------------------------ */
    SET v_Id_Rol = NULL; -- Reset

    SELECT `Id_Rol`, `Codigo`, `Activo`
    INTO v_Id_Rol, v_Codigo_Existente, v_Activo
    FROM `Cat_Roles`
    WHERE `Nombre` = _Nombre
    LIMIT 1
    FOR UPDATE; -- <--- BLOQUEO DE ESCRITURA AQUÍ

    /* ESCENARIO B: EL NOMBRE YA EXISTE */
    IF v_Id_Rol IS NOT NULL THEN
        
        /* B.1 Detección de Conflicto Cruzado
           El nombre existe, pero tiene un código diferente al que intentamos registrar. */
        IF v_Codigo_Existente IS NOT NULL AND v_Codigo_Existente <> _Codigo THEN
             SIGNAL SQLSTATE '45000' 
             SET MESSAGE_TEXT = 'CONFLICTO DE INTEGRIDAD [409]: El NOMBRE ya existe asociado a otro CÓDIGO diferente.';
        END IF;
        
        /* B.2 Data Enrichment (Caso Legacy)
           Si el registro existía con Código NULL (datos viejos), le asignamos el nuevo código. */
        IF v_Codigo_Existente IS NULL THEN
             UPDATE `Cat_Roles` SET `Codigo` = _Codigo, `updated_at` = NOW() WHERE `Id_Rol` = v_Id_Rol;
        END IF;

        /* B.3 Autosanación por Nombre
           Si estaba inactivo, lo reactivamos y nos aseguramos de guardar la nueva descripción. */
        IF v_Activo = 0 THEN
            UPDATE `Cat_Roles` 
            SET `Activo` = 1, 
                `Descripcion` = _Descripcion, -- Actualización mandataria
                `updated_at` = NOW() 
            WHERE `Id_Rol` = v_Id_Rol;
            
            COMMIT; 
            SELECT 'ÉXITO: Rol reactivado (encontrado por Nombre).' AS Mensaje, v_Id_Rol AS Id_Rol, 'REACTIVADA' AS Accion; 
            LEAVE THIS_PROC;
        END IF;

        /* B.4 Idempotencia por Nombre */
        COMMIT; 
        SELECT 'AVISO: El Rol ya existe (validado por Nombre).' AS Mensaje, v_Id_Rol AS Id_Rol, 'REUSADA' AS Accion; 
        LEAVE THIS_PROC;
    END IF;

    /* ------------------------------------------------------------------------------------------------
       PASO 3.3: PERSISTENCIA (INSERT FÍSICO)
       Si llegamos aquí, no hay colisiones. Procedemos a insertar.
       Aquí existe un riesgo infinitesimal de "Race Condition" si otro usuario inserta en este preciso instante.
       ------------------------------------------------------------------------------------------------ */
    SET v_Dup = 0; -- Reiniciar bandera de error
    
    INSERT INTO `Cat_Roles`
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
        1,      -- Default: Activo
        NOW(),  -- Timestamp Creación
        NOW()   -- Timestamp Actualización
    );

    /* Verificación de Éxito: Si v_Dup sigue en 0, el INSERT fue limpio. */
    IF v_Dup = 0 THEN
        COMMIT; 
        SELECT 'ÉXITO: Rol creado correctamente.' AS Mensaje, LAST_INSERT_ID() AS Id_Rol, 'CREADA' AS Accion; 
        LEAVE THIS_PROC;
    END IF;

    /* ================================================================================================
       BLOQUE 4: SUBRUTINA DE RECUPERACIÓN DE CONCURRENCIA (RE-RESOLVE PATTERN)
       Propósito: Manejar elegantemente el Error 1062 (Duplicate Key) si ocurre una condición de carrera.
       ================================================================================================ */
    
    /* Si estamos aquí, v_Dup = 1. Significa que "perdimos" la carrera contra otro INSERT concurrente. */
    
    ROLLBACK; -- 1. Revertir la transacción fallida para liberar bloqueos parciales.
    
    START TRANSACTION; -- 2. Iniciar una nueva transacción limpia.
    
    SET v_Id_Rol = NULL;
    
    /* 3. Buscar el registro "ganador" (El que insertó el otro usuario) */
    SELECT `Id_Rol`, `Activo`, `Nombre`
    INTO v_Id_Rol, v_Activo, v_Nombre_Existente
    FROM `Cat_Roles`
    WHERE `Codigo` = _Codigo
    LIMIT 1
    FOR UPDATE;
    
    IF v_Id_Rol IS NOT NULL THEN
        /* Validación de Seguridad Post-Recuperación */
        IF v_Nombre_Existente <> _Nombre THEN
             SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA [500]: Concurrencia detectada con datos inconsistentes.';
        END IF;

        /* Reactivar si el ganador estaba inactivo */
        IF v_Activo = 0 THEN
            UPDATE `Cat_Roles` 
            SET `Activo` = 1, 
                `Descripcion` = _Descripcion, -- Actualización mandataria
                `updated_at` = NOW() 
            WHERE `Id_Rol` = v_Id_Rol;
            
            COMMIT; 
            SELECT 'ÉXITO: Rol reactivado (recuperado tras concurrencia).' AS Mensaje, v_Id_Rol AS Id_Rol, 'REACTIVADA' AS Accion; 
            LEAVE THIS_PROC;
        END IF;
        
        /* Retornar el ID existente */
        COMMIT; 
        SELECT 'AVISO: El Rol ya existía (reusado tras concurrencia).' AS Mensaje, v_Id_Rol AS Id_Rol, 'REUSADA' AS Accion; 
        LEAVE THIS_PROC;
    END IF;

    /* Fallo Irrecuperable (Corrupción de índices o error fantasma) */
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR CRÍTICO [500]: Fallo de concurrencia no recuperable.';

END$$

DELIMITER ;

/* ============================================================================================
   SECCIÓN: CONSULTAS ESPECÍFICAS (PARA EDICIÓN / DETALLE)
   ============================================================================================
   Estas rutinas son clave para la UX. No solo devuelven el dato pedido, sino todo el 
   contexto necesario para que el formulario de edición se autocomplete correctamente.
   ============================================================================================ */

/* ============================================================================================
   PROCEDIMIENTO: SP_ConsultarRolEspecifico
   ============================================================================================
   
   1. OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   --------------------------------------
   Recuperar la "Ficha Técnica" completa, cruda y fidedigna (Raw Data) de un Rol de Sistema
   específico, identificado por su llave primaria (`Id_Rol`).

   CASOS DE USO (CONTEXTO DE UI):
   A) PRECARGA DE FORMULARIO DE EDICIÓN (UPDATE):
      - Cuando un Administrador de Seguridad va a modificar un perfil, el formulario debe 
        llenarse con los datos exactos que residen en la base de datos.
      - Requisito Crítico: La fidelidad del dato. Si la descripción es NULL, debe llegar NULL.
        El `Codigo` es vital porque es el enlace con los Middlewares del Backend.

   B) VISUALIZACIÓN DE DETALLE (AUDITORÍA):
      - Permite visualizar metadatos de auditoría (`created_at`, `updated_at`) para saber
        cuándo se creó o modificó el permiso por última vez.

   2. ARQUITECTURA DE DATOS (DIRECT TABLE ACCESS)
   ----------------------------------------------
   Este procedimiento consulta directamente la tabla física `Cat_Roles`, evitando el uso
   de la vista `Vista_Roles`.

   JUSTIFICACIÓN TÉCNICA:
   - Desacoplamiento de Presentación: `Vista_Roles` aplica alias como `Codigo_Rol` o `Estatus_Rol`
     pensados para reportes JSON legibles. Sin embargo, para el UPDATE, el ORM o el Backend 
     suelen esperar los nombres de columna originales (`Codigo`, `Activo`) para hacer el 
     binding automático.
   - Performance: El acceso por Primary Key (`Id_Rol`) es de costo computacional O(1).

   3. ESTRATEGIA DE SEGURIDAD (DEFENSIVE PROGRAMMING)
   --------------------------------------------------
   - Validación de Entrada: Se rechazan IDs nulos o negativos antes de tocar el disco.
   - Fail Fast (Fallo Rápido): Se verifica la existencia del registro antes de intentar devolver datos.
     Esto permite diferenciar un "Error 404" (Rol no existe) de un "Error 500".

   4. VISIBILIDAD (SCOPE)
   ----------------------
   - NO se filtra por `Activo = 1`.
   - Razón: Un rol puede estar "Revocado" (Inactivo). El administrador necesita poder 
     consultarlo para ver sus detalles y decidir si lo Reactiva. 

   5. DICCIONARIO DE DATOS (OUTPUT)
   --------------------------------
   Retorna una única fila (Single Row) con:
     - [Identidad]: Id_Rol, Codigo (Slug), Nombre.
     - [Contexto]: Descripcion.
     - [Control]: Activo (1 = Vigente, 0 = Revocado).
     - [Auditoría]: created_at, updated_at.
   ============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ConsultarRolEspecifico`$$
CREATE PROCEDURE `SP_ConsultarRolEspecifico`(
    IN _Id_Rol INT -- Identificador único del Rol a consultar
)
BEGIN
    /* ========================================================================================
       BLOQUE 1: VALIDACIÓN DE ENTRADA (DEFENSIVE PROGRAMMING)
       Objetivo: Asegurar que el parámetro recibido sea un entero positivo válido.
       Evita cargas innecesarias al motor de base de datos con peticiones basura.
       ======================================================================================== */
    IF _Id_Rol IS NULL OR _Id_Rol <= 0 THEN
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'ERROR DE SISTEMA: El Identificador del Rol es inválido (Debe ser un entero positivo).';
    END IF;

    /* ========================================================================================
       BLOQUE 2: VERIFICACIÓN DE EXISTENCIA (FAIL FAST STRATEGY)
       Objetivo: Validar que el recurso realmente exista en la base de datos.
       
       NOTA DE IMPLEMENTACIÓN:
       Usamos `SELECT 1` que es más ligero que seleccionar columnas reales, ya que solo
       necesitamos confirmar la presencia de la llave en el índice primario.
       ======================================================================================== */
    IF NOT EXISTS (SELECT 1 FROM `Cat_Roles` WHERE `Id_Rol` = _Id_Rol) THEN
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'ERROR DE NEGOCIO: El Rol de Sistema solicitado no existe o fue eliminado físicamente.';
    END IF;

    /* ========================================================================================
       BLOQUE 3: CONSULTA PRINCIPAL (DATA RETRIEVAL)
       Objetivo: Retornar el objeto de datos completo y puro (Raw Data).
       ======================================================================================== */
    SELECT 
        /* --- GRUPO A: IDENTIDAD DEL REGISTRO --- */
        /* Este ID es la llave primaria inmutable. */
        `Id_Rol`,
        
        /* --- GRUPO B: DATOS EDITABLES CRÍTICOS --- */
        /* 'Codigo': Es el Slug usado en el código fuente (ej: @can('ADMIN')). 
           Es vital que este dato sea exacto. */
        `Codigo`,        
        `Nombre`,
        
        /* 'Descripcion': Contexto del alcance del rol. */
        `Descripcion`,
        
        /* --- GRUPO C: METADATOS DE CONTROL DE CICLO DE VIDA --- */
        /* Este valor (0 o 1) indica si el rol está vigente.
           1 = Activo/Asignable, 0 = Inactivo/Revocado (Baja Lógica). */
        `Activo`,        
        
        /* --- GRUPO D: AUDITORÍA DE SISTEMA --- */
        /* Fechas útiles para mostrar en el pie de página del modal de detalle. */
        `created_at`,
        `updated_at`
        
    FROM `Cat_Roles`
    WHERE `Id_Rol` = _Id_Rol
    LIMIT 1; /* Buena práctica: Asegura al optimizador que se detenga tras el primer hallazgo. */

END$$

DELIMITER ;

/* ============================================================================================
   SECCIÓN: LISTADOS PARA DROPDOWNS (SOLO REGISTROS ACTIVOS)
   ============================================================================================
   Estas rutinas son consumidas por los formularios de captura (Frontend).
   Su objetivo es ofrecer al usuario solo las opciones válidas y vigentes para evitar errores.
   ============================================================================================ */

/* ============================================================================================
   PROCEDIMIENTO: SP_ListarRolesActivos
   ============================================================================================
   1. OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   --------------------------------------
   Proveer un endpoint de datos ultraligero para alimentar elementos de Interfaz de Usuario (UI)
   tipo "Selector", "Dropdown" o "Select2" en el módulo de Gestión de Usuarios.

   Este procedimiento es la **Única Fuente de Verdad** para desplegar los perfiles de seguridad
   disponibles en los formularios de:
      - Alta de Nuevos Usuarios.
      - Reasignación de Permisos.
      - Filtros de Auditoría de Accesos.

   2. REGLAS DE NEGOCIO Y FILTRADO (THE VIGENCY CONTRACT)
   ------------------------------------------------------
   A) FILTRO DE SEGURIDAD ESTRICTO (HARD FILTER):
      - Regla: La consulta aplica obligatoriamente la cláusula `WHERE Activo = 1`.
      - Justificación de Seguridad: Un Rol marcado como inactivo (`Activo = 0`) significa que ha sido
        revocado, deprecado o suspendido temporalmente por la administración. Permitir su selección
        crearía una brecha de seguridad (asignar permisos que no deberían existir) o inconsistencias
        en el middleware de autorización.
      - Implementación: El filtro es nativo en BD, blindando al sistema incluso contra APIs externas.

   B) ORDENAMIENTO COGNITIVO (USABILITY):
      - Regla: Los resultados se ordenan alfabéticamente por `Nombre` (A-Z).
      - Justificación: Facilita que el administrador encuentre rápidamente el rol deseado
        (ej: "Administrador" al inicio, "Supervisor" al final) sin tener que leer toda la lista.

   3. ARQUITECTURA DE DATOS (ROOT ENTITY OPTIMIZATION)
   ---------------------------------------------------
   - Optimización de Lectura: Al ser `Cat_Roles` una tabla de catálogo pequeña y de alto acceso
     (High Read / Low Write), esta consulta es extremadamente rápida.
   
   - Proyección Mínima (Payload Reduction):
     Solo se proyectan las 3 columnas vitales para el componente visual HTML/JS:
       1. ID (Value): Para la relación en base de datos (`Id_Rol`).
       2. Nombre (Label): Lo que ve el humano (`Administrador`).
       3. Código (Auxiliary): Para lógica de frontend (ej: íconos condicionales basados en 'ADMIN' o 'USER').
     
     Se omiten campos de auditoría o descripciones largas para maximizar la velocidad de respuesta.

   4. DICCIONARIO DE DATOS (OUTPUT JSON SCHEMA)
   --------------------------------------------
   Retorna un array de objetos JSON optimizados:
      - `Id_Rol`: (INT) Llave Primaria.
      - `Codigo`: (VARCHAR) Slug técnico (ej: 'SOPORTE_TI').
      - `Nombre`: (VARCHAR) Etiqueta (ej: 'Soporte Técnico').
   ============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ListarRolesActivos`$$
CREATE PROCEDURE `SP_ListarRolesActivos`()
BEGIN
    /* ========================================================================================
       BLOQUE ÚNICO: CONSULTA DE SELECCIÓN OPTIMIZADA
       No requiere parámetros. Es un "Full Table Scan" filtrado, ideal para catálogos.
       ======================================================================================== */
    
    SELECT 
        /* IDENTIFICADOR ÚNICO (PK)
           Este valor se guardará en la tabla de relación Users-Roles (o en la tabla Users). */
        `Id_Rol`, 
        
        /* CÓDIGO TÉCNICO / SLUG
           Útil si el frontend necesita pintar íconos específicos según el rol 
           (ej: si Codigo='ADMIN' -> mostrar escudo). */
        `Codigo`, 
        
        /* ETIQUETA HUMANA
           El texto que se renderiza dentro de la etiqueta <option> del select. */
        `Nombre`

    FROM 
        `Cat_Roles`
    
    /* ----------------------------------------------------------------------------------------
       FILTRO DE VIGENCIA (SEGURIDAD)
       Solo roles "vivos". Los revocados (0) se ocultan para prevenir asignaciones erróneas.
       ---------------------------------------------------------------------------------------- */
    WHERE 
        `Activo` = 1
    
    /* ----------------------------------------------------------------------------------------
       ORDENAMIENTO
       Alfabético por nombre para mejorar la experiencia de usuario (UX).
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

/* ============================================================================================
   PROCEDIMIENTO: SP_ListarRolesAdmin
   ============================================================================================
   1. OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   --------------------------------------
   Proveer el inventario maestro y completo de los "Roles de Sistema" (`Cat_Roles`) para 
   alimentar el Grid Principal del Módulo de Gestión de Seguridad.

   Este endpoint permite al Administrador de Seguridad (CISO/SuperAdmin) visualizar la totalidad 
   de los perfiles de acceso (históricos y actuales) para realizar tareas de:
      - Auditoría de Accesos: Revisar qué roles han existido y su alcance.
      - Depuración: Identificar roles duplicados u obsoletos.
      - Gestión de Ciclo de Vida: Reactivar permisos que fueron revocados temporalmente.

   2. DIFERENCIA CRÍTICA CON EL LISTADO OPERATIVO (DROPDOWN)
   ---------------------------------------------------------
   Es vital distinguir este SP de `SP_ListarRolesActivos`:
   
   A) SP_ListarRolesActivos (Dropdown): 
      - Enfoque: Asignación de Permisos.
      - Filtro: Estricto `WHERE Activo = 1`.
      - Objetivo: Evitar asignar roles revocados a usuarios nuevos.
   
   B) SP_ListarRolesAdmin (ESTE):
      - Enfoque: Gobernanza y Auditoría.
      - Filtro: NINGUNO (Visibilidad Total).
      - Objetivo: Permitir al Admin ver roles inactivos (`Estatus = 0`) para poder editarlos 
        (ej: corregir descripción) o reactivarlos. Ocultar los inactivos aquí impediría su gestión.

   3. ARQUITECTURA DE DATOS (VIEW CONSUMPTION PATTERN)
   ---------------------------------------------------
   Este procedimiento implementa el patrón de "Abstracción de Lectura" al consumir la vista 
   `Vista_Roles` en lugar de la tabla física.

   Ventajas Técnicas:
   - Desacoplamiento: El Grid del Frontend se acopla a los nombres de columnas estandarizados de la Vista 
     (ej: `Estatus_Rol`, `Codigo_Rol`) y no a los de la tabla física (`Activo`, `Codigo`).
   - Estandarización: La vista ya aplica transformaciones semánticas útiles para la UI.

   4. ESTRATEGIA DE ORDENAMIENTO (UX PRIORITY)
   -------------------------------------------
   El ordenamiento está diseñado para la eficiencia administrativa:
      1. Prioridad Operativa (`Estatus_Rol` DESC): 
         Los roles VIGENTES (1) aparecen arriba. Los revocados (0) se van al fondo.
         Esto mantiene la información relevante accesible inmediatamente.
      2. Orden Alfabético (`Nombre_Rol` ASC): 
         Dentro de cada grupo, se ordenan A-Z para facilitar la búsqueda visual rápida.

   5. DICCIONARIO DE DATOS (OUTPUT)
   --------------------------------
   Retorna el contrato de datos definido en `Vista_Roles`:
      - [Identidad]: Id_Rol, Codigo_Rol (Slug), Nombre_Rol.
      - [Contexto]: Descripcion_Rol.
      - [Control]: Estatus_Rol (1 = Activo, 0 = Inactivo).
      - [Auditoría]: created_at, updated_at (Disponibles si se descomentan en la vista).
   ============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ListarRolesAdmin`$$
CREATE PROCEDURE `SP_ListarRolesAdmin`()
BEGIN
    /* ========================================================================================
       BLOQUE ÚNICO: CONSULTA MAESTRA
       No requiere validaciones de entrada ya que es una consulta global sobre el catálogo.
       ======================================================================================== */
    
    SELECT 
        /* Proyección total de la Vista Maestra de Seguridad */
        * FROM 
        `Vista_Roles`
    
    /* ========================================================================================
       ORDENAMIENTO ESTRATÉGICO
       Optimizamos la presentación para el auditor de seguridad.
       ======================================================================================== */
    ORDER BY 
        `Estatus_Rol` DESC,  -- 1º: Prioridad a los roles activos
        `Nombre_Rol` ASC;    -- 2º: Orden alfabético para búsqueda visual

END$$

DELIMITER ;

/* ====================================================================================================
   PROCEDIMIENTO ALMACENADO: SP_EditarRol
   ====================================================================================================
   
   1. VISIÓN GENERAL Y OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   ----------------------------------------------------------------------------------------------------
   Este procedimiento orquesta la modificación de los atributos descriptivos de un "Rol de Sistema"
   (`Cat_Roles`) existente en el catálogo de seguridad.
   
   No es un simple UPDATE; es un motor transaccional diseñado para operar en entornos de alta 
   concurrencia, garantizando las propiedades ACID:
     - Atomicidad: O se aplican todos los cambios, o ninguno.
     - Consistencia: No se permiten duplicados de Código o Nombre.
     - Aislamiento: Uso de bloqueos determinísticos para prevenir abrazos mortales (Deadlocks).
     - Durabilidad: Confirmación explícita (COMMIT) tras validar reglas.

   2. REGLAS DE VALIDACIÓN ESTRICTA (HARD CONSTRAINTS)
   ----------------------------------------------------------------------------------------------------
   A) OBLIGATORIEDAD DE CAMPOS:
      - Regla: "Todo o Nada". Código, Nombre y Descripción son MANDATORIOS.
      - Justificación: Un rol sin descripción clara es un riesgo de seguridad (ambigüedad de alcance).

   B) UNICIDAD GLOBAL (EXCLUSIÓN PROPIA):
      - Se verifica que el nuevo Código no pertenezca a OTRO rol (`Id <> _Id_Rol`).
      - Se verifica que el nuevo Nombre no pertenezca a OTRO rol.
      - Nota: Es perfectamente legal que el registro "choque consigo mismo" (ej: cambiar solo la descripción).

   3. ARQUITECTURA DE CONCURRENCIA (DETERMINISTIC LOCKING PATTERN)
   ----------------------------------------------------------------------------------------------------
   Para prevenir **Deadlocks** (Bloqueos Mutuos) en escenarios de "Intercambio" (Swap Scenario) donde
   dos administradores intentan editar registros cruzados simultáneamente, implementamos una estrategia 
   de BLOQUEO DETERMINÍSTICO:

     - FASE 1 (Identificación): Detectamos todos los IDs involucrados en la transacción (El ID objetivo,
       el ID dueño del código deseado y el ID dueño del nombre deseado).
     - FASE 2 (Ordenamiento): Ordenamos estos IDs numéricamente de MENOR a MAYOR.
     - FASE 3 (Ejecución): Adquirimos los bloqueos (`FOR UPDATE`) siguiendo estrictamente ese orden.
   
   Resultado: Todos los procesos compiten por los recursos en la misma dirección ("fila india"), 
   eliminando matemáticamente la posibilidad de un ciclo de espera infinito.

   4. IDEMPOTENCIA (OPTIMIZACIÓN DE RECURSOS)
   ----------------------------------------------------------------------------------------------------
   - Antes de escribir en disco, el SP compara el estado actual (`Snapshot`) contra los nuevos valores.
   - Si son idénticos, retorna éxito ('SIN_CAMBIOS') inmediatamente.
   - Beneficio: Evita escrituras innecesarias en el Transaction Log y mantiene intacta la fecha `updated_at`.

   5. CONTRATO DE SALIDA (OUTPUT CONTRACT)
   ----------------------------------------------------------------------------------------------------
   Retorna un resultset con:
      - Mensaje (VARCHAR): Feedback descriptivo.
      - Accion (VARCHAR): 'ACTUALIZADA', 'SIN_CAMBIOS', 'CONFLICTO'.
      - Id_Rol (INT): Identificador del recurso manipulado.
   ==================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_EditarRol`$$

CREATE PROCEDURE `SP_EditarRol`(
    /* -----------------------------------------------------------------
       PARÁMETROS DE ENTRADA (INPUTS)
       Recibimos los datos crudos del formulario de edición.
       ----------------------------------------------------------------- */
    IN _Id_Rol      INT,           -- OBLIGATORIO: ID del registro a modificar (PK)
    IN _Nuevo_Codigo VARCHAR(50),   -- OBLIGATORIO: Nueva Clave (ej: 'ADMIN_SYS')
    IN _Nuevo_Nombre VARCHAR(255),  -- OBLIGATORIO: Nuevo Nombre (ej: 'Administrador de Sistema')
    IN _Nueva_Desc   VARCHAR(255)   -- OBLIGATORIO: Descripción detallada (Regla de Negocio)
)
THIS_PROC: BEGIN
    
    /* ================================================================================================
       BLOQUE 0: DECLARACIÓN DE VARIABLES DE ESTADO Y CONTEXTO
       Propósito: Inicializar los contenedores que gestionarán la lógica del procedimiento.
       ================================================================================================ */
    
    /* [Snapshots]: Almacenan el estado actual del registro antes de la edición (para comparar cambios) */
    DECLARE v_Cod_Act  VARCHAR(50)  DEFAULT NULL;
    DECLARE v_Nom_Act  VARCHAR(255) DEFAULT NULL;
    DECLARE v_Desc_Act VARCHAR(255) DEFAULT NULL;

    /* [IDs de Conflicto]: Identificadores de filas que podrían chocar con nuestros nuevos datos */
    DECLARE v_Id_Conflicto_Cod INT DEFAULT NULL; 
    DECLARE v_Id_Conflicto_Nom INT DEFAULT NULL; 

    /* [Variables de Algoritmo de Bloqueo]: Auxiliares para ordenar los locks de Menor a Mayor */
    DECLARE v_L1 INT DEFAULT NULL;
    DECLARE v_L2 INT DEFAULT NULL;
    DECLARE v_L3 INT DEFAULT NULL;
    DECLARE v_Min INT DEFAULT NULL;
    DECLARE v_Existe INT DEFAULT NULL; -- Auxiliar para validar que el lock fue exitoso

    /* [Bandera de Control]: Semáforo para detectar errores de concurrencia (Error 1062) */
    DECLARE v_Dup TINYINT(1) DEFAULT 0;

    /* [Variables de Diagnóstico]: Para reportar al usuario qué campo causó el error */
    DECLARE v_Campo_Error VARCHAR(20) DEFAULT NULL;
    DECLARE v_Id_Error    INT DEFAULT NULL;

    /* ================================================================================================
       BLOQUE 1: HANDLERS (MANEJO ROBUSTO DE EXCEPCIONES)
       Propósito: Garantizar una salida limpia ante errores técnicos o de concurrencia.
       ================================================================================================ */
    
    /* 1.1 HANDLER DE DUPLICIDAD (Error 1062)
       Objetivo: Capturar colisiones de Unique Key en el último milisegundo (Race Condition).
       Acción: No abortamos. Encendemos la bandera v_Dup = 1 para manejar el conflicto controladamente al final. */
    DECLARE CONTINUE HANDLER FOR 1062 SET v_Dup = 1;

    /* 1.2 HANDLER GENÉRICO (SQLEXCEPTION)
       Objetivo: Capturar fallos técnicos graves (Desconexión, Disco lleno, Sintaxis).
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
    
    /* 2.1 LIMPIEZA DE DATOS (TRIM & NULLIF)
       Eliminamos espacios basura. Si queda vacío, se convierte a NULL para activar las validaciones. */
    SET _Nuevo_Codigo = NULLIF(TRIM(_Nuevo_Codigo), '');
    SET _Nuevo_Nombre = NULLIF(TRIM(_Nuevo_Nombre), '');
    SET _Nueva_Desc   = NULLIF(TRIM(_Nueva_Desc), '');

    /* 2.2 VALIDACIÓN DE OBLIGATORIEDAD
       El formulario exige que todos los campos críticos existan. */
    
    IF _Id_Rol IS NULL OR _Id_Rol <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: Identificador de Rol inválido.';
    END IF;

    IF _Nuevo_Codigo IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN [400]: El CÓDIGO es obligatorio para la edición.';
    END IF;

    IF _Nuevo_Nombre IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN [400]: El NOMBRE es obligatorio para la edición.';
    END IF;
    
    /* Regla Estricta: Descripción obligatoria para asegurar la documentación del rol */
    IF _Nueva_Desc IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN [400]: La DESCRIPCIÓN es obligatoria.';
    END IF;
    
    /* ================================================================================================
       BLOQUE 3: ESTRATEGIA DE BLOQUEO DETERMINÍSTICO (PREVENCIÓN DE DEADLOCKS)
       Propósito: Adquirir los recursos necesarios en un orden estricto para evitar bloqueos mutuos.
       ================================================================================================ */
    START TRANSACTION;

    /* ------------------------------------------------------------------------------------------------
       PASO 3.1: RECONOCIMIENTO (LECTURA SUCIA / NO BLOQUEANTE)
       Primero "miramos" el panorama para saber qué filas están involucradas sin bloquear nada aún.
       Esto nos permite armar la lista de IDs que necesitaremos bloquear.
       ------------------------------------------------------------------------------------------------ */
    
    /* A) Identificar el registro objetivo (Target) */
    SELECT `Codigo`, `Nombre` INTO v_Cod_Act, v_Nom_Act
    FROM `Cat_Roles` WHERE `Id_Rol` = _Id_Rol;

    /* Si no encontramos el registro propio, abortamos (pudo ser borrado por otro admin hace instantes) */
    IF v_Cod_Act IS NULL AND v_Nom_Act IS NULL THEN 
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [404]: El Rol que intenta editar no existe.';
    END IF;

    /* B) Identificar posible conflicto de CÓDIGO (¿Alguien más ya tiene mi nuevo código?)
       Solo buscamos si el código cambió respecto al actual. */
    IF _Nuevo_Codigo <> IFNULL(v_Cod_Act, '') THEN
        SELECT `Id_Rol` INTO v_Id_Conflicto_Cod 
        FROM `Cat_Roles` 
        WHERE `Codigo` = _Nuevo_Codigo AND `Id_Rol` <> _Id_Rol LIMIT 1;
    END IF;

    /* C) Identificar posible conflicto de NOMBRE (¿Alguien más ya tiene mi nuevo nombre?)
       Solo buscamos si el nombre cambió respecto al actual. */
    IF _Nuevo_Nombre <> v_Nom_Act THEN
        SELECT `Id_Rol` INTO v_Id_Conflicto_Nom 
        FROM `Cat_Roles` 
        WHERE `Nombre` = _Nuevo_Nombre AND `Id_Rol` <> _Id_Rol LIMIT 1;
    END IF;

    /* ------------------------------------------------------------------------------------------------
       PASO 3.2: EJECUCIÓN DE BLOQUEOS ORDENADOS (ALGORITMO)
       Esta es la parte crítica. Ordenamos los IDs (Propio, ConflictoCod, ConflictoNom) y bloqueamos 
       de MENOR a MAYOR.
       
       Justificación: Si la Transacción A quiere bloquear (1, 5) y la Transacción B quiere bloquear (5, 1),
       al forzar el orden ascendente, ambas intentarán bloquear (1) primero. Una esperará a la otra. 
       Sin este orden, ocurriría un Deadlock.
       ------------------------------------------------------------------------------------------------ */
    
    /* Llenamos el pool de IDs a bloquear */
    SET v_L1 = _Id_Rol;
    SET v_L2 = v_Id_Conflicto_Cod;
    SET v_L3 = v_Id_Conflicto_Nom;

    /* Normalización: Eliminar duplicados en las variables (ej: si conflicto Cod y Nom son el mismo ID externo) */
    IF v_L2 = v_L1 THEN SET v_L2 = NULL; END IF;
    IF v_L3 = v_L1 THEN SET v_L3 = NULL; END IF;
    IF v_L3 = v_L2 THEN SET v_L3 = NULL; END IF;

    /* --- RONDA 1: Bloquear el ID Menor --- */
    SET v_Min = NULL;
    IF v_L1 IS NOT NULL THEN SET v_Min = v_L1; END IF;
    IF v_L2 IS NOT NULL AND (v_Min IS NULL OR v_L2 < v_Min) THEN SET v_Min = v_L2; END IF;
    IF v_L3 IS NOT NULL AND (v_Min IS NULL OR v_L3 < v_Min) THEN SET v_Min = v_L3; END IF;

    IF v_Min IS NOT NULL THEN
        SELECT 1 INTO v_Existe FROM `Cat_Roles` WHERE `Id_Rol` = v_Min FOR UPDATE;
        /* Marcar como procesado (borrar del pool) para la siguiente ronda */
        IF v_L1 = v_Min THEN SET v_L1 = NULL; END IF;
        IF v_L2 = v_Min THEN SET v_L2 = NULL; END IF;
        IF v_L3 = v_Min THEN SET v_L3 = NULL; END IF;
    END IF;

    /* --- RONDA 2: Bloquear el Siguiente ID --- */
    SET v_Min = NULL;
    IF v_L1 IS NOT NULL THEN SET v_Min = v_L1; END IF;
    IF v_L2 IS NOT NULL AND (v_Min IS NULL OR v_L2 < v_Min) THEN SET v_Min = v_L2; END IF;
    IF v_L3 IS NOT NULL AND (v_Min IS NULL OR v_L3 < v_Min) THEN SET v_Min = v_L3; END IF;

    IF v_Min IS NOT NULL THEN
        SELECT 1 INTO v_Existe FROM `Cat_Roles` WHERE `Id_Rol` = v_Min FOR UPDATE;
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
        SELECT 1 INTO v_Existe FROM `Cat_Roles` WHERE `Id_Rol` = v_Min FOR UPDATE;
    END IF;

    /* ================================================================================================
       BLOQUE 4: LÓGICA DE NEGOCIO (BAJO PROTECCIÓN DE LOCKS)
       Propósito: Ahora que tenemos exclusividad sobre las filas, aplicamos las reglas de negocio.
       ================================================================================================ */

    /* 4.1 RE-LECTURA AUTORIZADA
       Ahora que tenemos los bloqueos, leemos el estado definitivo de nuestro registro.
       (El registro podría haber cambiado en los milisegundos previos al bloqueo). */
    SELECT `Codigo`, `Nombre`, `Descripcion` 
    INTO v_Cod_Act, v_Nom_Act, v_Desc_Act
    FROM `Cat_Roles` 
    WHERE `Id_Rol` = _Id_Rol; 

    /* Safety Check: Si al bloquear descubrimos que el registro fue borrado */
    IF v_Nom_Act IS NULL THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR CRÍTICO [410]: El registro desapareció durante la transacción.';
    END IF;

    /* 4.2 DETECCIÓN DE IDEMPOTENCIA (SIN CAMBIOS)
       Comparamos si los datos nuevos son matemáticamente iguales a los actuales. 
       Usamos <=> (Null-Safe Equality) para manejar correctamente los NULLs en campos opcionales. */
    IF (v_Cod_Act <=> _Nuevo_Codigo) 
       AND (v_Nom_Act = _Nuevo_Nombre) 
       AND (v_Desc_Act <=> _Nueva_Desc) THEN
        
        COMMIT; -- Liberamos locks inmediatamente
        
        /* Retorno anticipado para ahorrar I/O y notificar al Frontend */
        SELECT 'AVISO: No se detectaron cambios en la información.' AS Mensaje, 'SIN_CAMBIOS' AS Accion, _Id_Rol AS Id_Rol;
        LEAVE THIS_PROC;
    END IF;

    /* 4.3 VALIDACIÓN FINAL DE UNICIDAD (PRE-UPDATE CHECK)
       Verificamos si existen duplicados REALES. Al tener los registros conflictivos bloqueados,
       esta verificación es 100% fiable. */
    
    /* A) Validación por CÓDIGO */
    SET v_Id_Error = NULL;
    SELECT `Id_Rol` INTO v_Id_Error FROM `Cat_Roles` 
    WHERE `Codigo` = _Nuevo_Codigo AND `Id_Rol` <> _Id_Rol LIMIT 1;
    
    IF v_Id_Error IS NOT NULL THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'CONFLICTO DE DATOS [409]: El CÓDIGO ingresado ya pertenece a otro Rol.';
    END IF;

    /* B) Validación por NOMBRE */
    SET v_Id_Error = NULL;
    SELECT `Id_Rol` INTO v_Id_Error FROM `Cat_Roles` 
    WHERE `Nombre` = _Nuevo_Nombre AND `Id_Rol` <> _Id_Rol LIMIT 1;
    
    IF v_Id_Error IS NOT NULL THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'CONFLICTO DE DATOS [409]: El NOMBRE ingresado ya pertenece a otro Rol.';
    END IF;

    /* ================================================================================================
       BLOQUE 5: PERSISTENCIA Y FINALIZACIÓN (UPDATE)
       Propósito: Aplicar los cambios una vez superadas todas las barreras de seguridad.
       ================================================================================================ */
    
    SET v_Dup = 0; -- Resetear bandera de error antes de escribir

    UPDATE `Cat_Roles`
    SET `Codigo`      = _Nuevo_Codigo,
        `Nombre`      = _Nuevo_Nombre,
        `Descripcion` = _Nueva_Desc,
        `updated_at`  = NOW() -- Auditoría automática
    WHERE `Id_Rol` = _Id_Rol;

    /* ================================================================================================
       BLOQUE 6: MANEJO DE COLISIÓN TARDÍA (RECUPERACIÓN DE ERROR 1062)
       Propósito: Gestionar el caso extremo donde un insert fantasma ocurre justo antes del update.
       ================================================================================================ */
    IF v_Dup = 1 THEN
        ROLLBACK;
        
        /* Diagnóstico Post-Mortem para el usuario */
        SET v_Campo_Error = 'DESCONOCIDO';
        SET v_Id_Error = NULL;

        /* ¿Fue conflicto de Código? */
        SELECT `Id_Rol` INTO v_Id_Error FROM `Cat_Roles` 
        WHERE `Codigo` = _Nuevo_Codigo AND `Id_Rol` <> _Id_Rol LIMIT 1;
        
        IF v_Id_Error IS NOT NULL THEN
            SET v_Campo_Error = 'CODIGO';
        ELSE
            /* Entonces fue conflicto de Nombre */
            SELECT `Id_Rol` INTO v_Id_Error FROM `Cat_Roles` 
            WHERE `Nombre` = _Nuevo_Nombre AND `Id_Rol` <> _Id_Rol LIMIT 1;
            SET v_Campo_Error = 'NOMBRE';
        END IF;

        SELECT 'Error de Concurrencia: Conflicto detectado al guardar.' AS Mensaje, 
               'CONFLICTO' AS Accion, 
               v_Campo_Error AS Campo, 
               v_Id_Error AS Id_Conflicto;
        LEAVE THIS_PROC;
    END IF;

    /* ================================================================================================
       BLOQUE 7: CONFIRMACIÓN EXITOSA
       Propósito: Confirmar la transacción y notificar al cliente.
       ================================================================================================ */
    COMMIT;
    
    SELECT 'ÉXITO: Rol actualizado correctamente.' AS Mensaje, 
           'ACTUALIZADA' AS Accion, 
           _Id_Rol AS Id_Rol;

END$$

DELIMITER ;

/* ====================================================================================================
   PROCEDIMIENTO ALMACENADO: SP_CambiarEstatusRol
   ====================================================================================================
   
   1. DEFINICIÓN DEL OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   ----------------------------------------------------------------------------------------------------
   Gestionar el Ciclo de Vida (Lifecycle) de un "Rol de Sistema" (`Cat_Roles`) mediante el mecanismo
   de "Baja Lógica" (Soft Delete).
   
   Este procedimiento actúa como un "Interruptor Maestro" (Master Toggle) de seguridad que permite:
     A) REVOCAR (Desactivar): Impedir que el rol sea asignado a nuevos usuarios en el futuro.
        Esto es crítico para retirar permisos obsoletos sin romper el historial de auditoría.
     B) RESTAURAR (Reactivar): Volver a habilitar un rol histórico para su uso operativo.

   2. ARQUITECTURA DE INTEGRIDAD REFERENCIAL (SEGURIDAD PRIMERO)
   ----------------------------------------------------------------------------------------------------
   A) NO DESTRUCCIÓN DE DATOS (DATA PRESERVATION):
      - Regla Absoluta: Jamás se ejecuta un `DELETE` físico sobre un Rol.
      - Justificación: Eliminar un rol rompería la integridad de la tabla de relación `Usuarios_Roles`
        (o donde se asignen los permisos), dejando usuarios "huérfanos" de acceso o causando errores 
        fatales en el Middleware de autorización del Backend (Laravel/Node).

   B) VALIDACIÓN DE EXISTENCIA (FAIL FAST):
      - Antes de intentar cualquier cambio, verificamos que el ID del rol exista.
      - Esto evita "Updates Fantasma" que reportan éxito falsamente cuando el registro no existe.

   3. ESTRATEGIA DE CONCURRENCIA (BLOQUEO PESIMISTA / ACID)
   ----------------------------------------------------------------------------------------------------
   - NIVEL DE AISLAMIENTO: Se utiliza `SELECT ... FOR UPDATE` al inicio de la transacción.
   - OBJETIVO: Serializar el acceso al registro del Rol.
   - ESCENARIO EVITADO (RACE CONDITION): Previene situaciones donde un Administrador intenta 
     desactivar el rol mientras otro intenta editar su nombre o descripción simultáneamente.
     El bloqueo asegura que las operaciones ocurran una después de la otra.

   4. IDEMPOTENCIA (OPTIMIZACIÓN DE RECURSOS)
   ----------------------------------------------------------------------------------------------------
   - Lógica de "Sin Cambios": Si se solicita activar un rol que YA está activo, el SP detecta la 
     redundancia y retorna éxito inmediato sin tocar el disco duro.
   - Beneficio: Ahorra I/O, reduce el crecimiento del Log de Transacciones y mantiene intacta 
     la fecha de auditoría `updated_at` (solo cambia cuando realmente hubo una modificación).

   5. CONTRATO DE SALIDA (OUTPUT CONTRACT)
   ----------------------------------------------------------------------------------------------------
   Retorna un resultset (Single Row) diseñado para refrescar la UI (Switch/Botón):
      - Mensaje (VARCHAR): Feedback descriptivo para el usuario.
      - Activo_Anterior (TINYINT): Estado previo (útil para rollback visual en frontend).
      - Activo_Nuevo (TINYINT): El nuevo estado confirmado en base de datos.
      - Accion (VARCHAR): 'CAMBIO_ESTATUS' o 'SIN_CAMBIOS'.
   ==================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_CambiarEstatusRol`$$

CREATE PROCEDURE `SP_CambiarEstatusRol`(
    /* -----------------------------------------------------------------
       PARÁMETROS DE ENTRADA
       ----------------------------------------------------------------- */
    IN _Id_Rol        INT,      -- OBLIGATORIO: El ID del rol a modificar (PK)
    IN _NuevoEstatus  TINYINT   -- OBLIGATORIO: 1 = Activar, 0 = Desactivar
)
THIS_PROC: BEGIN
    
    /* ================================================================================================
       BLOQUE 0: VARIABLES DE ESTADO Y CONTROL
       Propósito: Inicializar los contenedores para el snapshot de datos.
       ================================================================================================ */
    
    /* Variable para almacenar el estado actual en base de datos antes del cambio */
    DECLARE v_EstatusActual TINYINT DEFAULT NULL;
    
    /* Bandera de existencia */
    DECLARE v_Existe INT DEFAULT NULL;

    /* ================================================================================================
       BLOQUE 1: GESTIÓN DE EXCEPCIONES Y ATOMICIDAD (ERROR HANDLING)
       Propósito: Garantizar una salida limpia ante errores técnicos.
       ================================================================================================ */
    
    /* Handler Genérico: Ante cualquier fallo SQL (Deadlock, Conexión), hacemos Rollback. */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; 
    END;

    /* ================================================================================================
       BLOQUE 2: PROTOCOLO DE VALIDACIÓN DE ENTRADA (DEFENSIVE PROGRAMMING)
       Propósito: Rechazar peticiones malformadas antes de consumir recursos.
       ================================================================================================ */
    
    /* 2.1 Validación de Integridad de Identificador */
    IF _Id_Rol IS NULL OR _Id_Rol <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: ID de Rol inválido o nulo.';
    END IF;

    /* 2.2 Validación de Integridad Booleana (Dominio Estricto) */
    IF _NuevoEstatus NOT IN (0, 1) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN [400]: El estatus solo puede ser 1 (Activo) o 0 (Inactivo).';
    END IF;

    /* ================================================================================================
       BLOQUE 3: INICIO DE TRANSACCIÓN Y BLOQUEO PESIMISTA
       Propósito: Aislar el registro para asegurar consistencia.
       ================================================================================================ */
    START TRANSACTION;

    /* ------------------------------------------------------------------------------------------------
       PASO 3.1: ADQUISICIÓN DE SNAPSHOT CON BLOQUEO (FOR UPDATE)
       
       Mecánica Técnica:
       - Buscamos el rol por su ID.
       - Adquirimos un candado de escritura (X-Lock) sobre la fila.
       - Efecto: Cualquier otra transacción que quiera leer o escribir este Rol deberá esperar.
       ------------------------------------------------------------------------------------------------ */
    SELECT 1, `Activo` 
    INTO v_Existe, v_EstatusActual
    FROM `Cat_Roles`
    WHERE `Id_Rol` = _Id_Rol
    LIMIT 1
    FOR UPDATE;

    /* ------------------------------------------------------------------------------------------------
       PASO 3.2: MANEJO DE ERROR (NO ENCONTRADO)
       Si v_Existe sigue en NULL, el registro no existe o fue eliminado por otro usuario.
       ------------------------------------------------------------------------------------------------ */
    IF v_Existe IS NULL THEN
        ROLLBACK; -- Liberamos recursos aunque no haya locks efectivos
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [404]: El Rol solicitado no existe en el catálogo.';
    END IF;

    /* ------------------------------------------------------------------------------------------------
       PASO 3.3: VALIDACIÓN DE REDUNDANCIA (BUSINESS LOGIC OPTIMIZATION)
       Objetivo: Si el estatus en BD ya es igual al que queremos poner, no hacemos nada.
       Beneficio: No "ensuciamos" el campo `updated_at` sin razón real.
       ------------------------------------------------------------------------------------------------ */
    IF v_EstatusActual = _NuevoEstatus THEN
        
        COMMIT; -- Liberamos el bloqueo inmediatamente
        
        /* Respuesta informativa (Idempotente) */
        SELECT 
            CASE 
                WHEN _NuevoEstatus = 1 THEN 'AVISO: El Rol ya se encuentra ACTIVO.' 
                ELSE 'AVISO: El Rol ya se encuentra INACTIVO.' 
            END AS Mensaje,
            _Id_Rol AS Id_Rol,
            _NuevoEstatus AS Nuevo_Estatus,
            'SIN_CAMBIOS' AS Accion;
            
        LEAVE THIS_PROC; -- Salimos del SP
    END IF;

    /* ================================================================================================
       BLOQUE 4: PERSISTENCIA Y FINALIZACIÓN (COMMIT)
       Propósito: Aplicar el cambio de estado validado.
       ================================================================================================ */

    /* ------------------------------------------------------------------------------------------------
       PASO 4.1: EJECUCIÓN DEL CAMBIO DE ESTADO (SOFT DELETE / RESTORE)
       Si llegamos aquí, el cambio es necesario y seguro.
       ------------------------------------------------------------------------------------------------ */
    UPDATE `Cat_Roles`
    SET 
        `Activo` = _NuevoEstatus,
        `updated_at` = NOW() -- Auditoría: Registramos el momento exacto del cambio
    WHERE `Id_Rol` = _Id_Rol;

    /* ------------------------------------------------------------------------------------------------
       PASO 4.2: CONFIRMACIÓN DE TRANSACCIÓN
       Hacemos permanentes los cambios y liberamos el bloqueo de fila.
       ------------------------------------------------------------------------------------------------ */
    COMMIT;

    /* ------------------------------------------------------------------------------------------------
       PASO 4.3: GENERACIÓN DE RESPUESTA AL CLIENTE
       ------------------------------------------------------------------------------------------------ */
    SELECT 
        CASE 
            WHEN _NuevoEstatus = 1 THEN 'ÉXITO: Rol reactivado correctamente.' 
            ELSE 'ÉXITO: Rol desactivado correctamente.' 
        END AS Mensaje,
        _Id_Rol AS Id_Rol,
        _NuevoEstatus AS Nuevo_Estatus,
        'CAMBIO_ESTATUS' AS Accion;

END$$

DELIMITER ;

/* ====================================================================================================
   PROCEDIMIENTO ALMACENADO: SP_EliminarRolFisicamente
   ====================================================================================================
   
   1. VISIÓN GENERAL Y OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   ----------------------------------------------------------------------------------------------------
   Este procedimiento implementa la operación de ELIMINACIÓN FÍSICA (Hard Delete) sobre la entidad
   "Rol de Sistema" (`Cat_Roles`).
   
   A diferencia de la "Baja Lógica" (que solo oculta el registro mediante un flag), este proceso DESTRUYE 
   la información de manera permanente e irreversible. Su uso está estrictamente limitado a casos excepcionales:
     A) Saneamiento de Datos (Data Cleansing): Eliminación de registros creados por error humano
        inmediatamente después de su creación (antes de ser asignados a usuarios).
     B) Depuración Administrativa: Mantenimiento técnico profundo por parte de Super-Admins.

   2. ARQUITECTURA DE INTEGRIDAD REFERENCIAL (ESTRATEGIA "DEFENSA EN PROFUNDIDAD")
   ----------------------------------------------------------------------------------------------------
   Para prevenir la corrupción silenciosa de la seguridad del sistema (Orphaned Permissions), 
   este SP implementa tres anillos de seguridad defensiva antes de permitir la destrucción:

     ANILLO 1: VALIDACIÓN DE EXISTENCIA (Fail Fast)
     - Rechaza inmediatamente IDs nulos o inexistentes para evitar abrir transacciones innecesarias.

     ANILLO 2: VALIDACIÓN PROACTIVA DE NEGOCIO (Logic Guard)
     - Consulta explícita a la tabla `Usuarios`.
     - REGLA CRÍTICA: Si existe AL MENOS UN usuario (activo o inactivo) que tenga este rol asignado,
       el registro se vuelve INBORRABLE. Esto es vital para no dejar usuarios con permisos "null" o rotos,
       lo cual podría causar excepciones de "Null Pointer" en el middleware de autenticación.
     - ACCIÓN: Devuelve un error 409 (Conflict) legible para el humano.

     ANILLO 3: VALIDACIÓN REACTIVA DE MOTOR (Database Constraint - Last Resort)
     - Se apoya en las Foreign Keys (FK) del motor InnoDB.
     - Si existe una relación oculta (en una tabla nueva que olvidamos validar manualmente), el motor 
       bloqueará el DELETE lanzando el error 1451.
     - ACCIÓN: Un HANDLER captura este error y hace un Rollback seguro, devolviendo un mensaje amigable.

   3. MODELO DE CONCURRENCIA Y BLOQUEO (ACID COMPLIANCE)
   ----------------------------------------------------------------------------------------------------
   - AISLAMIENTO: Serializable (vía Locking).
   - MECÁNICA: Al ejecutar la validación previa, utilizamos `SELECT ... FOR UPDATE`. Esto adquiere
     un BLOQUEO EXCLUSIVO (X-LOCK) sobre la fila objetivo.
   - EFECTO: Nadie puede leer, editar o asignar este rol a un usuario durante los milisegundos
     que dura la transacción de borrado. Esto evita la condición de carrera ("Race Condition") donde 
     alguien asigna el rol justo antes de que sea borrado.

   4. CONTRATO DE SALIDA (OUTPUT CONTRACT)
   ----------------------------------------------------------------------------------------------------
   Retorna un resultset de una sola fila (Single Row) indicando el éxito de la operación.
   En caso de fallo, se lanzan señales SQLSTATE controladas (400, 404, 409).
   ==================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_EliminarRolFisicamente`$$

CREATE PROCEDURE `SP_EliminarRolFisicamente`(
    /* PARÁMETRO DE ENTRADA */
    IN _Id_Rol INT -- PK: Identificador único del Rol a purgar.
)
THIS_PROC: BEGIN
    
    /* ================================================================================================
       BLOQUE 0: VARIABLES DE DIAGNÓSTICO
       Propósito: Definición de contenedores locales para almacenar el estado de las validaciones.
       ================================================================================================ */
    -- Semáforo para detectar si existen usuarios vinculados.
    DECLARE v_Dependencias INT DEFAULT NULL;
    
    -- Bandera de existencia para el bloqueo pesimista.
    DECLARE v_Existe INT DEFAULT NULL;

    /* ================================================================================================
       BLOQUE 1: DEFINICIÓN DE HANDLERS (MANEJO DE EXCEPCIONES TÉCNICAS)
       Propósito: Asegurar que el procedimiento nunca termine abruptamente sin limpiar la transacción.
       ================================================================================================ */
    
    /* ------------------------------------------------------------------------------------------------
       HANDLER 1.1: PROTECCIÓN DE INTEGRIDAD REFERENCIAL (Error MySQL 1451)
       Contexto: Este error ocurre cuando intentamos borrar un registro padre que tiene hijos (FK) activos.
       Estrategia: "Graceful Failure". En lugar de mostrar un error SQL críptico al usuario,
       revertimos la transacción y mostramos un mensaje de negocio explicativo.
       ------------------------------------------------------------------------------------------------ */
    DECLARE EXIT HANDLER FOR 1451 
    BEGIN 
        ROLLBACK; 
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'BLOQUEO DE INTEGRIDAD [1451]: El sistema de base de datos impidió el borrado. Existen registros vinculados a este Rol (como Usuarios) que no fueron detectados por la validación previa.'; 
    END;

    /* ------------------------------------------------------------------------------------------------
       HANDLER 1.2: EXCEPCIÓN GENERAL (SQLEXCEPTION)
       Contexto: Fallos de disco, pérdida de conexión de red, corrupción de índices, timeout.
       Estrategia: Abortar operación (Rollback) y relanzar el error para logs del sistema.
       ------------------------------------------------------------------------------------------------ */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; 
    END;

    /* ================================================================================================
       BLOQUE 2: VALIDACIONES PRELIMINARES (FAIL FAST PATTERN)
       Propósito: Validar la calidad de los datos de entrada antes de consumir recursos de procesamiento.
       ================================================================================================ */
    
    /* 2.1 Validación de Sintaxis: El ID debe ser un entero positivo válido. */
    IF _Id_Rol IS NULL OR _Id_Rol <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: El parámetro ID de Rol es inválido o nulo.';
    END IF;

    /* ================================================================================================
       BLOQUE 3: INICIO DE TRANSACCIÓN Y BLOQUEO DE SEGURIDAD
       Propósito: Aislar el registro para evitar modificaciones concurrentes mientras validamos.
       ================================================================================================ */
    START TRANSACTION;

    /* ------------------------------------------------------------------------------------------------
       PASO 3.1: VERIFICACIÓN DE EXISTENCIA Y BLOQUEO (FOR UPDATE)
       
       Objetivo: Asegurar que el registro existe y "congelarlo" para nosotros.
       Efecto: Si otro admin intenta asignar este rol en este preciso instante, su transacción se
       detendrá hasta que nosotros terminemos (Serialize).
       ------------------------------------------------------------------------------------------------ */
    SELECT 1 INTO v_Existe
    FROM `Cat_Roles`
    WHERE `Id_Rol` = _Id_Rol
    LIMIT 1
    FOR UPDATE;

    IF v_Existe IS NULL THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [404]: El Rol que intenta eliminar no existe en la base de datos.';
    END IF;

    /* ================================================================================================
       BLOQUE 4: CANDADO DE NEGOCIO (VALIDACIÓN LÓGICA DE DEPENDENCIAS)
       Propósito: Aplicar las reglas de dominio específicas para la destrucción de información.
       ================================================================================================ */
    
    /* ------------------------------------------------------------------------------------------------
       PASO 4.1: INSPECCIÓN DE USUARIOS ASIGNADOS
       
       Objetivo Técnico: Escanear la tabla `Usuarios` para ver si la columna `Fk_Rol` apunta a este ID.
       
       Justificación: No podemos dejar usuarios "huérfanos" de rol, ya que el sistema no sabría
       qué permisos otorgarles o qué vistas mostrarles.
       ------------------------------------------------------------------------------------------------ */
    
    SELECT 1 INTO v_Dependencias
    FROM `Usuarios` 
    WHERE `Fk_Rol` = _Id_Rol
    LIMIT 1;

    /* Evaluación del Bloqueo: Si encontramos al menos un usuario, ABORTAMOS. */
    IF v_Dependencias IS NOT NULL THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'CONFLICTO DE SEGURIDAD [409]: Operación denegada. No es posible eliminar este Rol porque existen USUARIOS registrados con este perfil. Debe reasignar el rol de esos usuarios antes de proceder.';
    END IF;

    /* ================================================================================================
       BLOQUE 5: EJECUCIÓN DESTRUCTIVA (ZONA CRÍTICA)
       Propósito: Ejecutar el borrado persistente de manera atómica.
       ================================================================================================ */

    /* ------------------------------------------------------------------------------------------------
       PASO 5.1: EJECUCIÓN DEL DELETE
       Acción: El motor intenta eliminar la fila física.
       
       Implicación de Motor (InnoDB):
       1. Se verifica nuevamente la restricción de llave foránea (Constraint Check) a nivel físico.
       2. Si pasa, se ejecuta el borrado físico de la página de datos.
       
       Red de Seguridad:
       Si alguna tabla oculta tiene una referencia a este Rol, aquí saltará el HANDLER 1451.
       ------------------------------------------------------------------------------------------------ */
    DELETE FROM `Cat_Roles` 
    WHERE `Id_Rol` = _Id_Rol;

    /* ------------------------------------------------------------------------------------------------
       PASO 5.2: CONFIRMACIÓN (COMMIT)
       Acción: Se finaliza la transacción.
       Efecto: El bloqueo exclusivo se libera. El espacio en disco se marca como reutilizable.
       ------------------------------------------------------------------------------------------------ */
    COMMIT;

    /* ================================================================================================
       BLOQUE 6: RESPUESTA AL CLIENTE (RESPONSE MAPPING)
       Propósito: Informar al Frontend/API que la operación concluyó exitosamente.
       ================================================================================================ */
    SELECT 
        'ÉXITO: El Rol ha sido eliminado permanentemente del sistema.' AS Mensaje, 
        'HARD_DELETE' AS Tipo_Operacion,
        _Id_Rol AS Id_Recurso_Eliminado,
        NOW() AS Fecha_Ejecucion;

END$$

DELIMITER ;

