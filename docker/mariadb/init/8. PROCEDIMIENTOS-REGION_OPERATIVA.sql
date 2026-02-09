USE `PICADE`;

/* ------------------------------------------------------------------------------------------------------ */
/* CREACION DE VISTAS Y PROCEDIMIENTOS DE ALMACENADO PARA LA BASE DE DATOS*/
/* ------------------------------------------------------------------------------------------------------ */

/* ======================================================================================================
   VIEW: Vista_Regiones
   ======================================================================================================
   1. OBJETIVO TÉCNICO Y DE NEGOCIO
   --------------------------------
   Esta vista implementa la **Capa de Abstracción de Datos** (DAL) para la entidad "Regiones Operativas".
   Su propósito es definir zonas geográficas o administrativas de alto nivel (ej: Región Norte, 
   Región Marina, Sede Central) que agrupan múltiples Centros de Trabajo o Sedes.

   Actúa como la **Interfaz Canónica** de lectura. El Frontend y los reportes nunca deben consultar 
   la tabla `Cat_Regiones` directamente, sino consumir esta vista para garantizar estabilidad ante
   cambios en el modelo físico.

   2. ARQUITECTURA DE DATOS (PATRÓN DE PROYECCIÓN)
   -----------------------------------------------
   Al ser una Entidad Raíz (Root Entity) dentro del modelo entidad-relación (no tiene llaves foráneas 
   hacia padres), esta vista no requiere JOINs complejos. Su valor radica en la **Normalización Semántica**:
   
   - Renombramiento de Llaves (Aliasing): Transforma `Id_CatRegion` a `Id_Region` para mantener un 
     estándar de nomenclatura consistente (json: { id_region: 1 }).
   
   - Exposición de Auditoría: Proyecta los timestamps (`created_at`, `updated_at`) para permitir 
     la trazabilidad de cambios en el panel administrativo sin exponer lógica interna.

   3. GESTIÓN DE INTEGRIDAD Y NULOS
   --------------------------------
   - Campo `Codigo`: Se expone tal cual (Raw Data). Si es NULL, el consumidor (Frontend) decide 
     si muestra un badge de "S/C" (Sin Código) o lo oculta.
   - Campo `Descripcion`: Se incluye para dar contexto operativo sobre qué abarca esa región
     (ej: "Comprende los estados de Tabasco y Veracruz").

   4. VISIBILIDAD DE ESTATUS (LÓGICA DE BORRADO)
   ---------------------------------------------
   - La vista expone **TODO el universo de datos** (Activos e Inactivos).
   - Razón: Los módulos de administración necesitan ver registros "eliminados lógicamente" (`Activo = 0`) 
     para permitir operaciones de auditoría, reactivación o para filtrar reportes históricos.
   - El filtrado de "Solo Activos" se delega al `WHERE` del consumidor o a los SPs de dropdowns.

   5. DICCIONARIO DE DATOS (ESPECIFICACIÓN DE SALIDA)
   --------------------------------------------------
   [Bloque A: Identidad del Registro]
   - Id_Region:           (INT) Identificador único y llave primaria.
   - Codigo_Region:       (VARCHAR) Clave corta (ej: 'RM-NE'). Puede ser NULL.
   - Nombre_Region:       (VARCHAR) Denominación oficial (ej: 'REGIÓN MARINA NORESTE').
   
   [Bloque B: Información Descriptiva]
   - Descripcion_Region:  (VARCHAR) Detalles sobre el alcance geográfico/operativo de la región.

   [Bloque C: Control y Auditoría]
   - Estatus_Region:      (TINYINT) Bandera booleana: 1 = Operativo/Visible, 0 = Baja Lógica.
   - created_at:          (DATETIME) Marca de tiempo de la creación inicial.
   - updated_at:          (DATETIME) Marca de tiempo de la última modificación.
   ====================================================================================================== */

-- DROP VIEW IF EXISTS `PICADE`.`Vista_Regiones`;

CREATE OR REPLACE
    ALGORITHM = UNDEFINED 
    SQL SECURITY DEFINER
VIEW `PICADE`.`Vista_Regiones` AS
    SELECT 
        /* -----------------------------------------------------------------------------------
           BLOQUE 1: IDENTIDAD Y CLAVES
           Estandarización de nombres para el consumo del API/Frontend.
           ----------------------------------------------------------------------------------- */
        `Reg`.`Id_CatRegion`             AS `Id_Region`,
        `Reg`.`Codigo`                   AS `Codigo_Region`,
        `Reg`.`Nombre`                   AS `Nombre_Region`,

        /* -----------------------------------------------------------------------------------
           BLOQUE 2: DETALLES INFORMATIVOS
           Información complementaria de alcance.
           ----------------------------------------------------------------------------------- */
        -- `Reg`.`Descripcion`              AS `Descripcion_Region`,

        /* -----------------------------------------------------------------------------------
           BLOQUE 3: METADATOS DE CONTROL DE CICLO DE VIDA
           El campo 'Activo' se renombra a 'Estatus_Region' para mayor claridad semántica.
           ----------------------------------------------------------------------------------- */
        `Reg`.`Activo`                   AS `Estatus_Region`
        
        /* -----------------------------------------------------------------------------------
           BLOQUE 4: AUDITORÍA DEL SISTEMA
           Campos necesarios para logs de cambios y ordenamiento cronológico.
           ----------------------------------------------------------------------------------- */
        -- `Reg`.`created_at`,
        -- `Reg`.`updated_at`

    FROM
        `PICADE`.`Cat_Regiones_Trabajo` `Reg`;

/* ============================================================================================
   PROCEDIMIENTO: SP_RegistrarRegion
   ============================================================================================
   1. OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   --------------------------------------
   Gestionar el alta de una nueva "Región Operativa" (ej: Región Marina, Región Sur) en el
   Catálogo Corporativo (`Cat_Regiones_Trabajo`).
   
   Este procedimiento actúa como una **Capa de Lógica de Negocio** (BLL) incrustada en la base de datos.
   Su función no es solo insertar, sino garantizar la unicidad, consistencia y reutilización de datos.

   2. REGLAS DE VALIDACIÓN ESTRICTA (HARD CONSTRAINTS)
   ---------------------------------------------------
   A) INTEGRIDAD DE DATOS (MANDATORY FIELDS):
      - Regla: "Datos completos o nada". Aunque la tabla pueda permitir nulos técnicos, el negocio
        exige que una Región tenga `Código` y `Nombre` para ser operativa.
      - Acción: Se rechazan valores nulos o vacíos antes de iniciar cualquier transacción.

   B) IDENTIDAD UNÍVOCA (DOBLE FACTOR):
      - Unicidad por CÓDIGO: No pueden existir dos regiones con clave 'RM-NE'.
      - Unicidad por NOMBRE: No pueden existir dos regiones llamadas 'REGIÓN MARINA NORESTE'.
      - Resolución: Se verifica primero el Código (Identificador fuerte) y luego el Nombre.

   3. ESTRATEGIA DE PERSISTENCIA Y CONCURRENCIA (ACID)
   ---------------------------------------------------
   A) BLOQUEO PESIMISTA (PESSIMISTIC LOCKING):
      - Se utiliza `SELECT ... FOR UPDATE` durante las verificaciones de existencia.
      - Justificación: Esto "congela" (adquiere un Write Lock) la fila encontrada. Evita que
        otro administrador modifique o reactive esa misma región mientras este proceso decide qué hacer.

   B) RECUPERACIÓN DE CONCURRENCIA (RE-RESOLVE PATTERN):
      - Escenario: Dos usuarios envían la misma Región nueva al mismo tiempo (milisegundos de diferencia).
        Ambos pasan la validación de "No existe". Ambos intentan INSERT. El segundo fallará por `1062`.
      - Solución: Un `HANDLER` captura el error 1062, hace Rollback silencioso y busca el registro
        que acaba de crear el "ganador", devolviéndolo como éxito ("REUSADA").

   C) AUTOSANACIÓN (SELF-HEALING / SOFT DELETE RECOVERY):
      - Si la Región YA EXISTE pero estaba dada de baja (`Activo = 0`), el sistema no duplica ni falla.
      - Acción: "Resucita" el registro (`UPDATE Activo = 1`) y actualiza su descripción.

   RESULTADO (OUTPUT CONTRACT)
   ---------------------------
   Retorna un resultset con:
     - Mensaje: Feedback descriptivo.
     - Id_Region: La llave primaria del recurso.
     - Accion: Enumerador ('CREADA', 'REACTIVADA', 'REUSADA').
   ============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_RegistrarRegion`$$
CREATE PROCEDURE `SP_RegistrarRegion`(
    /* -----------------------------------------------------------------
       PARÁMETROS DE ENTRADA (INPUTS)
       Recibimos los datos crudos del formulario.
       ----------------------------------------------------------------- */
    IN _Codigo      VARCHAR(50),   -- OBLIGATORIO: Clave corta (ej: 'RM-NE')
    IN _Nombre      VARCHAR(255),  -- OBLIGATORIO: Nombre oficial
    IN _Descripcion VARCHAR(255)   -- OPCIONAL: Notas adicionales
)
SP: BEGIN
    /* ========================================================================================
       BLOQUE 0: DECLARACIÓN DE VARIABLES DE ENTORNO
       ======================================================================================== */
    
    /* Variables de Persistencia (Snapshot del registro en BD si existe) */
    DECLARE v_Id_Region  INT DEFAULT NULL;
    DECLARE v_Activo     TINYINT(1) DEFAULT NULL;
    
    /* Variables para Validación Cruzada (Cross-Check de identidad) */
    DECLARE v_Nombre_Existente VARCHAR(255) DEFAULT NULL;
    DECLARE v_Codigo_Existente VARCHAR(50) DEFAULT NULL;
    
    /* Bandera de Control de Flujo (Semáforo para errores de concurrencia) */
    DECLARE v_Dup TINYINT(1) DEFAULT 0;

    /* ========================================================================================
       BLOQUE 1: HANDLERS (MANEJO ROBUSTO DE EXCEPCIONES)
       ======================================================================================== */
    
    /* 1.1 HANDLER DE DUPLICIDAD (Error 1062 - Duplicate Entry)
       Objetivo: Capturar colisiones de Unique Key en el INSERT final.
       Acción: No abortar. Encender bandera v_Dup = 1 para activar la rutina de recuperación. */
    DECLARE CONTINUE HANDLER FOR 1062 SET v_Dup = 1;

    /* 1.2 HANDLER GENÉRICO (SQLEXCEPTION)
       Objetivo: Capturar fallos de infraestructura (Disco lleno, Conexión perdida, Syntax Error).
       Acción: Abortar inmediatamente, deshacer cambios (ROLLBACK) y propagar el error. */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; 
    END;

    /* ========================================================================================
       BLOQUE 2: SANITIZACIÓN Y VALIDACIÓN (FAIL FAST STRATEGY)
       ======================================================================================== */
    
    /* 2.1 LIMPIEZA DE DATOS (TRIM & NULLIF)
       Eliminamos espacios al inicio/final. Si la cadena queda vacía, la convertimos a NULL
       para facilitar la validación booleana estricta. */
    SET _Codigo      = NULLIF(TRIM(_Codigo), '');
    SET _Nombre      = NULLIF(TRIM(_Nombre), '');
    SET _Descripcion = NULLIF(TRIM(_Descripcion), '');

    /* 2.2 VALIDACIÓN DE OBLIGATORIEDAD (Business Rule: NO VACÍOS)
       Validamos antes de abrir transacción para ahorrar recursos del servidor. */
    
    IF _Codigo IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN: El CÓDIGO de la Región es obligatorio.';
    END IF;

    IF _Nombre IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN: El NOMBRE de la Región es obligatorio.';
    END IF;
    
    IF _Descripcion IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN: La DESCRIPCIÓN del Régimen es obligatoria.';
    END IF;

    /* ========================================================================================
       BLOQUE 3: LÓGICA DE NEGOCIO TRANSACCIONAL
       ======================================================================================== */
    START TRANSACTION;

    /* ----------------------------------------------------------------------------------------
       PASO 3.1: RESOLUCIÓN DE IDENTIDAD POR CÓDIGO (PRIORIDAD ALTA)
       Verificamos si la clave única (_Codigo) ya está registrada.
       ---------------------------------------------------------------------------------------- */
    SET v_Id_Region = NULL;

    /* BLOQUEO PESIMISTA: 'FOR UPDATE'
       Asegura que si encontramos una región con este código, nadie más la toque mientras
       verificamos su nombre y estatus. */
    SELECT `Id_CatRegion`, `Nombre`, `Activo` 
    INTO v_Id_Region, v_Nombre_Existente, v_Activo
    FROM `Cat_Regiones_Trabajo`
    WHERE `Codigo` = _Codigo
    LIMIT 1
    FOR UPDATE;

    /* ESCENARIO A: EL CÓDIGO YA EXISTE */
    IF v_Id_Region IS NOT NULL THEN
        
        /* Validación de Integridad Cruzada:
           Regla: Si el código existe, el Nombre TAMBIÉN debe coincidir.
           Fallo: Si el código es 'RM-NE' pero el nombre existente es 'REGION SUR', tenemos
           un conflicto grave de datos. */
        IF v_Nombre_Existente <> _Nombre THEN
            SIGNAL SQLSTATE '45000' 
                SET MESSAGE_TEXT = 'ERROR DE CONFLICTO: El CÓDIGO ingresado ya existe pero pertenece a una Región con diferente NOMBRE. Verifique sus datos.';
        END IF;

        /* Sub-Escenario A.1: Existe pero está INACTIVO (Baja Lógica) -> REACTIVAR
           Esto es "Autosanación". Recuperamos el registro histórico. */
        IF v_Activo = 0 THEN
            UPDATE `Cat_Regiones_Trabajo`
            SET `Activo` = 1,
				/* CAMBIO AQUÍ: Eliminé COALESCE. Se guarda el dato nuevo obligatoriamente. */
                `Descripcion` = _Descripcion, 
                `updated_at` = NOW()
            WHERE `Id_CatRegion` = v_Id_Region;
            
            COMMIT; 
            SELECT 'Región reactivada y actualizada exitosamente.' AS Mensaje, v_Id_Region AS Id_Region, 'REACTIVADA' AS Accion; 
            LEAVE SP;
        
        /* Sub-Escenario A.2: Existe y está ACTIVO -> IDEMPOTENCIA
           El registro ya está tal como lo queremos. No hacemos nada. */
        ELSE
            COMMIT; 
            SELECT 'La Región ya se encuentra registrada y activa.' AS Mensaje, v_Id_Region AS Id_Region, 'REUSADA' AS Accion; 
            LEAVE SP;
        END IF;
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 3.2: RESOLUCIÓN DE IDENTIDAD POR NOMBRE (PRIORIDAD SECUNDARIA)
       Si llegamos aquí, el CÓDIGO es libre. Ahora verificamos si el NOMBRE ya está en uso.
       ---------------------------------------------------------------------------------------- */
    SET v_Id_Region = NULL;

    SELECT `Id_CatRegion`, `Codigo`, `Activo`
    INTO v_Id_Region, v_Codigo_Existente, v_Activo
    FROM `Cat_Regiones_Trabajo`
    WHERE `Nombre` = _Nombre
    LIMIT 1
    FOR UPDATE;

    /* ESCENARIO B: EL NOMBRE YA EXISTE */
    IF v_Id_Region IS NOT NULL THEN
        /* Conflicto de Identidad:
           El nombre existe, pero tiene asociado OTRO código diferente al que intentamos registrar.
           (Nota: Como v_Codigo_Existente podría ser NULL en datos legacy, usamos lógica robusta) */
        
        IF v_Codigo_Existente IS NOT NULL AND v_Codigo_Existente <> _Codigo THEN
             SIGNAL SQLSTATE '45000' 
             SET MESSAGE_TEXT = 'ERROR DE CONFLICTO: El NOMBRE ingresado ya existe pero está asociado a otro CÓDIGO diferente.';
        END IF;
        
        /* Caso Especial: Enriquecimiento de Datos (Data Enrichment)
           El registro existía con Código NULL, y ahora le estamos asignando un Código válido. */
        IF v_Codigo_Existente IS NULL THEN
             UPDATE `Cat_Regiones_Trabajo` 
             SET `Codigo` = _Codigo, `updated_at` = NOW() 
             WHERE `Id_CatRegion` = v_Id_Region;
        END IF;

        /* Reactivación si estaba inactivo */
        IF v_Activo = 0 THEN
            UPDATE `Cat_Regiones_Trabajo` 
            SET `Activo` = 1, `updated_at` = NOW() 
            WHERE `Id_CatRegion` = v_Id_Region;
            
            COMMIT; 
            SELECT 'Región reactivada exitosamente (encontrada por Nombre).' AS Mensaje, v_Id_Region AS Id_Region, 'REACTIVADA' AS Accion; 
            LEAVE SP;
        END IF;

        /* Idempotencia: Ya existe y está activo */
        COMMIT; 
        SELECT 'La Región ya existe (validada por Nombre).' AS Mensaje, v_Id_Region AS Id_Region, 'REUSADA' AS Accion; 
        LEAVE SP;
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 3.3: PERSISTENCIA (INSERCIÓN FÍSICA)
       Si pasamos todas las validaciones y no encontramos coincidencias, es un registro NUEVO.
       ---------------------------------------------------------------------------------------- */
    SET v_Dup = 0; -- Reiniciamos bandera de error
    
    INSERT INTO `Cat_Regiones_Trabajo`
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
        1,      -- Activo por defecto
        NOW(),  -- Fecha Creación
        NOW()   -- Fecha Actualización
    );

    /* Verificación de Éxito: Si v_Dup sigue en 0, el INSERT funcionó y no hubo colisión */
    IF v_Dup = 0 THEN
        COMMIT; 
        SELECT 'Región registrada exitosamente.' AS Mensaje, LAST_INSERT_ID() AS Id_Region, 'CREADA' AS Accion; 
        LEAVE SP;
    END IF;

    /* ========================================================================================
       BLOQUE 4: RUTINA DE RECUPERACIÓN DE CONCURRENCIA (RE-RESOLVE)
       ========================================================================================
       Si el flujo llega aquí, v_Dup = 1.
       Diagnóstico: Ocurrió una "Race Condition". Otro usuario insertó el registro milisegundos
       antes que nosotros, disparando el Error 1062 (Duplicate Key).
       
       Acción: Recuperar el ID del registro "ganador" y devolverlo como si fuera nuestro. */
    
    ROLLBACK; -- Limpiamos la transacción fallida (para liberar bloqueos parciales)
    
    START TRANSACTION; -- Iniciamos nueva lectura limpia
    
    SET v_Id_Region = NULL;
    
    /* Intentamos recuperar por CÓDIGO (la restricción más fuerte) */
    SELECT `Id_CatRegion`, `Activo`, `Nombre`
    INTO v_Id_Region, v_Activo, v_Nombre_Existente
    FROM `Cat_Regiones_Trabajo`
    WHERE `Codigo` = _Codigo
    LIMIT 1
    FOR UPDATE;
    
    IF v_Id_Region IS NOT NULL THEN
        /* Validación de Seguridad: Confirmar que no sea un falso positivo */
        IF v_Nombre_Existente <> _Nombre THEN
             SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR CRÍTICO DE SISTEMA: Concurrencia detectada con conflicto de datos (Códigos iguales, Nombres distintos).';
        END IF;

        /* Reactivación (si el ganador estaba inactivo) */
        IF v_Activo = 0 THEN
            UPDATE `Cat_Regiones_Trabajo` 
            SET `Activo` = 1, `updated_at` = NOW() 
            WHERE `Id_CatRegion` = v_Id_Region;
            
            COMMIT; 
            SELECT 'Región reactivada (recuperada tras concurrencia).' AS Mensaje, v_Id_Region AS Id_Region, 'REACTIVADA' AS Accion; 
            LEAVE SP;
        END IF;
        
        /* Éxito por Reuso */
        COMMIT; 
        SELECT 'La Región ya existía (reusada tras concurrencia).' AS Mensaje, v_Id_Region AS Id_Region, 'REUSADA' AS Accion; 
        LEAVE SP;
    END IF;

    /* Si falló por 1062 pero no encontramos el registro ni por Código (Caso extremo de corrupción de índices) */
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA: Fallo de concurrencia no recuperable (Error Fantasma en Regiones). Contacte a Soporte.';

END$$

DELIMITER ;

/* ============================================================================================
   SECCIÓN: CONSULTAS ESPECÍFICAS (PARA EDICIÓN / DETALLE)
   ============================================================================================
   Esta sección contiene rutinas optimizadas para la recuperación de un único registro (Single Row).
   Son fundamentales para la Experiencia de Usuario (UX) en los formularios de mantenimiento.
   ============================================================================================ */

/* ============================================================================================
   PROCEDIMIENTO: SP_ConsultarRegionEspecifica
   ============================================================================================
   1. OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   --------------------------------------
   Recuperar la "Ficha Técnica" completa y sin procesar (Raw Data) de una Región Operativa
   específica, identificada por su llave primaria (`Id_CatRegion`).

   Este endpoint de base de datos habilita dos flujos críticos en la interfaz:
   
   A) PRECARGA DE FORMULARIO DE EDICIÓN (UPDATE):
      - Cuando un administrador hace clic en "Editar", el sistema debe llenar los campos del 
        formulario con la información actual.
      - Requisito Crítico: La fidelidad del dato. Si el código en la base de datos es NULL, 
        el SP debe devolver NULL (para que el input aparezca vacío) y no una cadena transformada 
        como "S/C" (que es útil para reportes, pero dañina para edición).

   B) VISUALIZACIÓN DE DETALLE (AUDITORÍA VISUAL):
      - Permite mostrar metadatos que no caben en la tabla principal (Grid), como las fechas 
        exactas de creación y última modificación (`created_at`, `updated_at`).

   2. ARQUITECTURA DE DATOS (DIRECT TABLE ACCESS PATTERN)
   ------------------------------------------------------
   A diferencia de los listados masivos que consumen la `Vista_Regiones` (Capa de Abstracción), 
   este procedimiento consulta directamente la tabla física `Cat_Regiones_Trabajo`.

   JUSTIFICACIÓN TÉCNICA:
   - Desacoplamiento de Capas: Las Vistas están diseñadas para "Lectura Humana" (formateo, 
     concatenación, reemplazo de nulos). Los SPs de Edición requieren "Lectura de Sistema" 
     (datos puros y tipos nativos) para asegurar que el UPDATE posterior sea consistente.
   - Performance: Al acceder por Primary Key (`Id_CatRegion`), la búsqueda es O(1) (costo constante),
     lo que garantiza una respuesta instantánea (<10ms) incluso con millones de registros.

   3. ESTRATEGIA DE SEGURIDAD (DEFENSIVE PROGRAMMING)
   --------------------------------------------------
   - Fail Fast (Fallo Rápido): Validamos los parámetros de entrada antes de ejecutar la consulta.
     Esto protege al motor de base de datos de procesar peticiones basura.
   - Verificación de Existencia: Comprobamos si el registro existe antes de intentar devolverlo.
     Esto permite diferenciar semánticamente entre un "Error 404" (No existe) y un "Resultset Vacío",
     facilitando el manejo de errores en el Backend (API).

   4. VISIBILIDAD DE DATOS (TOTAL VISIBILITY)
   ------------------------------------------
   - Regla: NO se aplica filtro por estatus (`WHERE Activo = 1`).
   - Razón: Un administrador necesita poder consultar una Región que fue eliminada lógicamente 
     (Inactiva) para ver su historial o decidir si la reactiva. Ocultarla aquí impediría su gestión.

   5. DICCIONARIO DE DATOS (OUTPUT)
   --------------------------------
   Retorna una única fila con:
     - [Identidad]: Id_CatRegion, Codigo, Nombre.
     - [Detalle]: Descripcion (Notas operativas).
     - [Control]: Activo (1 = Operativo, 0 = Baja Lógica).
     - [Auditoría]: created_at, updated_at.
   ============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ConsultarRegionEspecifica`$$
CREATE PROCEDURE `SP_ConsultarRegionEspecifica`(
    IN _Id_Region INT -- Identificador único de la Región a consultar
)
BEGIN
    /* ========================================================================================
       BLOQUE 1: VALIDACIÓN DE ENTRADA (DEFENSIVE PROGRAMMING)
       Objetivo: Asegurar que el parámetro recibido cumpla con los requisitos mínimos
       antes de intentar cualquier operación de lectura. Evita inyecciones de valores absurdos.
       ======================================================================================== */
    IF _Id_Region IS NULL OR _Id_Region <= 0 THEN
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'ERROR DE SISTEMA: El Identificador de la Región es inválido (Debe ser un entero positivo).';
    END IF;

    /* ========================================================================================
       BLOQUE 2: VERIFICACIÓN DE EXISTENCIA (FAIL FAST STRATEGY)
       Objetivo: Validar que el recurso realmente exista en la base de datos.
       
       NOTA DE IMPLEMENTACIÓN:
       Usamos `SELECT 1` que es más ligero que seleccionar columnas reales, ya que solo
       necesitamos confirmar la presencia de la llave en el índice.
       ======================================================================================== */
    IF NOT EXISTS (SELECT 1 FROM `Cat_Regiones_Trabajo` WHERE `Id_CatRegion` = _Id_Region) THEN
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'ERROR DE NEGOCIO: La Región solicitada no existe en el catálogo o fue eliminada físicamente.';
    END IF;

    /* ========================================================================================
       BLOQUE 3: CONSULTA PRINCIPAL (DATA RETRIEVAL)
       Objetivo: Retornar el objeto de datos completo y puro (Raw Data).
       ======================================================================================== */
    SELECT 
        /* --- GRUPO A: IDENTIDAD DEL REGISTRO --- */
        /* Este ID es inmutable y debe viajar oculto en el formulario para el UPDATE posterior */
        `Id_CatRegion`,
        
        /* --- GRUPO B: DATOS EDITABLES --- */
        /* Nota: 'Codigo' puede ser NULL en la BD. El Frontend debe manejar esto renderizando
           un input vacío, permitiendo al usuario asignar un código si lo desea. */
        `Codigo`,       
        `Nombre`,
        `Descripcion`,
        
        /* --- GRUPO C: METADATOS DE CONTROL DE CICLO DE VIDA --- */
        /* Este valor (0 o 1) determina el estado visual del Switch/Toggle en la UI.
           1 = Verde/Activo, 0 = Gris/Inactivo. */
        `Activo`,       
        
        /* --- GRUPO D: AUDITORÍA DE SISTEMA --- */
        /* Útiles para mostrar etiquetas informativas como "Creado el..." o "Última edición..." */
        `created_at`,
        `updated_at`
        
    FROM `Cat_Regiones_Trabajo`
    WHERE `Id_CatRegion` = _Id_Region
    LIMIT 1; /* Buena práctica: Detiene el escaneo del motor al encontrar la primera coincidencia (aunque sea PK) */

END$$

DELIMITER ;

/* ============================================================================================
   SECCIÓN: LISTADOS PARA DROPDOWNS (SOLO REGISTROS ACTIVOS)
   ============================================================================================
   Estas rutinas son consumidas por los formularios de captura (Frontend).
   Su objetivo es ofrecer al usuario solo las opciones válidas y vigentes para evitar errores.
   ============================================================================================ */

/* ============================================================================================
   PROCEDIMIENTO: SP_ListarRegionesActivas
   ============================================================================================
   1. OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   --------------------------------------
   Proveer un endpoint de datos ligero y altamente optimizado para alimentar elementos de 
   Interfaz de Usuario (UI) tipo "Selector", "Dropdown" o "ComboBox".
   
   Este procedimiento es la fuente autorizada para desplegar las Regiones Operativas disponibles
   en los formularios de:
     - Alta de Centros de Trabajo (Asignación de Región).
     - Alta de Sedes.
     - Filtros de búsqueda en Dashboards Ejecutivos.

   2. REGLAS DE NEGOCIO Y FILTRADO (THE VIGENCY CONTRACT)
   ------------------------------------------------------
   A) FILTRO DE VIGENCIA ESTRICTO (HARD FILTER):
      - Regla: La consulta aplica obligatoriamente la cláusula `WHERE Activo = 1`.
      - Justificación Operativa: Una Región marcada como inactiva (Baja Lógica) implica que
        ya no existe operativamente (ej: reestructuración de la empresa). Permitir seleccionarla
        para un nuevo Centro de Trabajo rompería la integridad del modelo organizacional actual.
      - Seguridad: El filtro es backend-side, garantizando que ni siquiera una API manipulada
        pueda recuperar regiones obsoletas por esta vía.

   B) ORDENAMIENTO COGNITIVO (USABILITY):
      - Regla: Los resultados se ordenan alfabéticamente por `Nombre` (A-Z).
      - Justificación: Facilita la búsqueda visual rápida por parte del usuario humano.

   3. ARQUITECTURA DE DATOS (ROOT ENTITY OPTIMIZATION)
   ---------------------------------------------------
   - Ausencia de JOINs: A diferencia de Municipios o Sedes, las Regiones son "Entidades Raíz"
     (no dependen de un padre activo para existir). Por lo tanto, la consulta es directa y
     extremadamente rápida (O(1) table scan indexado).
   
   - Proyección Mínima (Payload Reduction):
     Solo se devuelven las columnas necesarias para construir el elemento HTML `<option>`:
       1. ID (Value): Integridad.
       2. Nombre (Label): Lectura.
       3. Código (Hint): Referencia visual rápida.
     Se omiten campos pesados como `Descripcion`, `created_at`, etc., para ahorrar ancho de banda.

   4. DICCIONARIO DE DATOS (OUTPUT JSON SCHEMA)
   --------------------------------------------
   Retorna un array de objetos ligeros:
     - `Id_CatRegion`: (INT) Llave Primaria. Value del selector.
     - `Codigo`:       (VARCHAR) Clave corta (ej: 'RM-S').
     - `Nombre`:       (VARCHAR) Texto principal (ej: 'Región Marina Suroeste').
   ============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ListarRegionesActivas`$$
CREATE PROCEDURE `SP_ListarRegionesActivas`()
BEGIN
    /* ========================================================================================
       BLOQUE ÚNICO: CONSULTA DE SELECCIÓN OPTIMIZADA
       No requiere validaciones de entrada ya que es una consulta de catálogo global.
       ======================================================================================== */
    
    SELECT 
        /* IDENTIFICADOR ÚNICO (PK)
           Este es el valor que se guardará como Foreign Key en las tablas hijas. */
        `Id_CatRegion`, 
        
        /* CLAVE CORTA
           Útil para mostrar en el frontend como 'badge' o texto secundario.
           Ej: "Región Sur (R-SUR)" */
        `Codigo`, 
        
        /* DESCRIPTOR HUMANO
           El texto principal que el usuario leerá en la lista desplegable. */
        `Nombre`

    FROM 
        `Cat_Regiones_Trabajo`
    
    /* ----------------------------------------------------------------------------------------
       FILTRO DE SEGURIDAD OPERATIVA (VIGENCIA)
       Ocultamos todo lo que no sea "1" (Activo). 
       Esto asegura que nuevos registros no se asocien a regiones extintas.
       ---------------------------------------------------------------------------------------- */
    WHERE 
        `Activo` = 1
    
    /* ----------------------------------------------------------------------------------------
       OPTIMIZACIÓN DE UX
       Ordenamiento alfabético en el motor de base de datos.
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
   PROCEDIMIENTO: SP_ListarRegionesAdmin
   ============================================================================================
   
   1. OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   --------------------------------------
   Proveer el inventario maestro y completo de las "Regiones Operativas" (`Cat_Regiones_Trabajo`)
   para alimentar el Grid Principal del Módulo de Administración.
   
   Este endpoint permite al Administrador visualizar la totalidad de los datos (históricos y actuales)
   para realizar tareas de:
     - Auditoría: Revisar qué regiones han existido en la historia de la empresa.
     - Mantenimiento: Detectar errores de captura en nombres o códigos.
     - Gestión de Ciclo de Vida: Reactivar regiones que fueron dadas de baja por error o que
       vuelven a ser operativas.

   2. DIFERENCIA CRÍTICA CON EL LISTADO OPERATIVO (DROPDOWN)
   ---------------------------------------------------------
   Es vital distinguir este SP de `SP_ListarRegionesActivas`:
   
   A) SP_ListarRegionesActivas (Dropdown): 
      - Enfoque: Operatividad y Seguridad.
      - Filtro: Estricto `WHERE Activo = 1`.
      - Objetivo: Evitar que se asignen nuevos recursos a regiones obsoletas.
   
   B) SP_ListarRegionesAdmin (ESTE):
      - Enfoque: Gestión y Auditoría.
      - Filtro: NINGUNO (Visibilidad Total).
      - Objetivo: Permitir al Admin ver registros inactivos (`Estatus = 0`) para poder editarlos
        o reactivarlos. Ocultar los inactivos aquí impediría su recuperación.

   3. ARQUITECTURA DE DATOS (VIEW CONSUMPTION PATTERN)
   ---------------------------------------------------
   Este procedimiento implementa el patrón de "Abstracción de Lectura" al consumir la vista
   `Vista_Regiones` en lugar de la tabla física.

   Ventajas Técnicas:
   - Desacoplamiento: El Grid del Frontend se acopla a los nombres de columnas estandarizados de la Vista 
     (ej: `Estatus_Region`) y no a los de la tabla física (`Activo`). Si la tabla cambia,
     solo ajustamos la Vista y este SP sigue funcionando sin cambios.
   - Estandarización: La vista ya maneja la proyección de columnas de auditoría y metadatos.

   4. ESTRATEGIA DE ORDENAMIENTO (UX PRIORITY)
   -------------------------------------------
   El ordenamiento no es arbitrario; está diseñado para la eficiencia administrativa:
     1. Prioridad Operativa (`Estatus_Region` DESC): 
        Los registros VIGENTES (1) aparecen en la parte superior. Los obsoletos (0) se van al fondo.
        Esto mantiene la información relevante accesible inmediatamente sin scrollear.
     2. Orden Alfabético (`Nombre_Region` ASC): 
        Dentro de cada grupo de estatus, se ordenan A-Z para facilitar la búsqueda visual rápida.

   5. DICCIONARIO DE DATOS (OUTPUT)
   --------------------------------
   Retorna el contrato de datos definido en `Vista_Regiones`:
     - [Identidad]: Id_Region, Codigo_Region, Nombre_Region.
     - [Detalle]: Descripcion_Region.
     - [Control]: Estatus_Region (1 = Activo, 0 = Inactivo).
     - [Auditoría]: created_at, updated_at.
   ============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ListarRegionesAdmin`$$
CREATE PROCEDURE `SP_ListarRegionesAdmin`()
BEGIN
    /* ========================================================================================
       BLOQUE ÚNICO: CONSULTA MAESTRA
       No requiere validaciones de entrada ya que es una consulta global sobre el catálogo.
       ======================================================================================== */
    
    SELECT 
        /* Proyección total de la Vista Maestra */
        * FROM 
        `Vista_Regiones`
    
    /* ========================================================================================
       ORDENAMIENTO ESTRATÉGICO
       Optimizamos la presentación para el usuario administrador.
       ======================================================================================== */
    ORDER BY 
        `Estatus_Region` DESC,  -- 1º: Muestra primero lo que está vivo (Operativo)
        `Nombre_Region` ASC;    -- 2º: Ordena alfabéticamente para facilitar búsqueda visual

END$$

DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_EditarRegion
   ============================================================================================
   1. OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   --------------------------------------
   Modificar los datos fundamentales de una "Región Operativa" existente en el catálogo.
   
   Este procedimiento no es un simple UPDATE; es un motor transaccional diseñado para operar
   en entornos de alta concurrencia, garantizando que:
     - No se generen duplicados (por Código o Nombre).
     - No se sobrescriban datos si no hubo cambios reales (Idempotencia).
     - No ocurran bloqueos mutuos (Deadlocks) entre usuarios.

   2. REGLAS DE VALIDACIÓN ESTRICTA (HARD CONSTRAINTS)
   ---------------------------------------------------
   A) OBLIGATORIEDAD DE CAMPOS:
      - Regla: "Todo o Nada". No se permite guardar cambios si el Código, el Nombre o la 
        Descripción son nulos o cadenas vacías.
      - Justificación: Mantener la calidad de los datos maestros para reportes ejecutivos.

   B) UNICIDAD GLOBAL (EXCLUSIÓN PROPIA):
      - Se verifica que el nuevo Código no pertenezca a OTRA región (`Id <> _Id_Region`).
      - Se verifica que el nuevo Nombre no pertenezca a OTRA región.
      - Nota: Es perfectamente legal que el registro choque consigo mismo (ej: cambiar solo la descripción
        manteniendo el mismo código).

   3. ARQUITECTURA DE CONCURRENCIA (DETERMINISTIC LOCKING PATTERN)
   ---------------------------------------------------------------
   Para prevenir **Deadlocks** (Abrazos Mortales), implementamos una estrategia de BLOQUEO DETERMINÍSTICO.
   
   El Problema:
     - Usuario A quiere cambiar Región 1 -> Código 'B'.
     - Usuario B quiere cambiar Región 2 -> Código 'A'.
     - Si A bloquea 1 y luego intenta bloquear 2, mientras B bloquea 2 y luego intenta bloquear 1,
       el motor de base de datos mata uno de los procesos.

   La Solución (El Algoritmo):
     1. Identificación: Detectamos todos los IDs involucrados (El que edito + El que tiene mi código deseado + El que tiene mi nombre deseado).
     2. Ordenamiento: Ordenamos esos IDs de MENOR a MAYOR.
     3. Ejecución: Bloqueamos (`FOR UPDATE`) siguiendo estrictamente ese orden.
     
   Resultado: Todos los procesos compiten por los recursos en la misma dirección, eliminando matemáticamente el ciclo de espera.

   4. IDEMPOTENCIA (OPTIMIZACIÓN DE RECURSOS)
   ------------------------------------------
   - Antes de escribir en disco, el SP compara el estado actual (`Snapshot`) contra los nuevos valores.
   - Si son idénticos, retorna éxito ('SIN_CAMBIOS') inmediatamente. Esto evita escrituras innecesarias
     en el Log de Transacciones y mantiene intacta la fecha `updated_at`.

   RESULTADO (OUTPUT CONTRACT)
   ---------------------------
   Retorna un dataset con:
     - Mensaje: Feedback descriptivo.
     - Accion: 'ACTUALIZADA', 'SIN_CAMBIOS', 'CONFLICTO'.
     - Id_Region: Identificador del recurso manipulado.
   ============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_EditarRegion`$$
CREATE PROCEDURE `SP_EditarRegion`(
    /* -----------------------------------------------------------------
       PARÁMETROS DE ENTRADA (INPUTS)
       Recibimos los datos crudos del formulario.
       ----------------------------------------------------------------- */
    IN _Id_Region    INT,           -- OBLIGATORIO: ID del registro a modificar (PK)
    IN _Nuevo_Codigo VARCHAR(50),   -- OBLIGATORIO: Nueva Clave (ej: 'RM-S')
    IN _Nuevo_Nombre VARCHAR(255),  -- OBLIGATORIO: Nuevo Nombre (ej: 'Región Sur')
    IN _Nueva_Desc   VARCHAR(255)   -- OBLIGATORIO: Descripción detallada
)
SP: BEGIN
    /* ========================================================================================
       BLOQUE 0: DECLARACIÓN DE VARIABLES DE ESTADO
       ======================================================================================== */
    
    /* Snapshots: Almacenan el estado actual del registro antes de la edición (para comparar cambios) */
    DECLARE v_Cod_Act  VARCHAR(50)  DEFAULT NULL;
    DECLARE v_Nom_Act  VARCHAR(255) DEFAULT NULL;
    DECLARE v_Desc_Act VARCHAR(255) DEFAULT NULL;

    /* IDs para la Estrategia de Bloqueo Determinístico (Candidatos a conflicto) */
    DECLARE v_Id_Conflicto_Cod INT DEFAULT NULL; -- ID del dueño actual del Código deseado (si existe)
    DECLARE v_Id_Conflicto_Nom INT DEFAULT NULL; -- ID del dueño actual del Nombre deseado (si existe)

    /* Variables auxiliares para el algoritmo de ordenamiento de locks */
    DECLARE v_L1 INT DEFAULT NULL;
    DECLARE v_L2 INT DEFAULT NULL;
    DECLARE v_L3 INT DEFAULT NULL;
    DECLARE v_Min INT DEFAULT NULL;
    DECLARE v_Existe INT DEFAULT NULL; -- Auxiliar para validar bloqueos

    /* Bandera de Error Crítico (Concurrency Collision) */
    DECLARE v_Dup TINYINT(1) DEFAULT 0;

    /* Variables para Diagnóstico de Errores (Post-Mortem) */
    DECLARE v_Campo_Error VARCHAR(20) DEFAULT NULL;
    DECLARE v_Id_Error    INT DEFAULT NULL;

    /* ========================================================================================
       BLOQUE 1: HANDLERS (SEGURIDAD Y ROBUSTEZ)
       ======================================================================================== */
    
    /* 1.1 HANDLER DE DUPLICIDAD (Error 1062)
       Captura colisiones de Unique Key en el último milisegundo (Race Condition). 
       Permite manejar el error controladamente en lugar de abortar. */
    DECLARE CONTINUE HANDLER FOR 1062 SET v_Dup = 1;

    /* 1.2 HANDLER GENÉRICO (SQLEXCEPTION)
       Captura fallos técnicos graves (Desconexión, Disco lleno, Sintaxis). Aborta todo. */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; 
    END;

    /* ========================================================================================
       BLOQUE 2: SANITIZACIÓN Y VALIDACIÓN (FAIL FAST)
       ======================================================================================== */
    
    /* 2.1 LIMPIEZA DE DATOS
       Eliminamos espacios basura. Si queda vacío, se convierte a NULL para activar las validaciones. */
    SET _Nuevo_Codigo = NULLIF(TRIM(_Nuevo_Codigo), '');
    SET _Nuevo_Nombre = NULLIF(TRIM(_Nuevo_Nombre), '');
    SET _Nueva_Desc   = NULLIF(TRIM(_Nueva_Desc), '');

    /* 2.2 VALIDACIÓN DE OBLIGATORIEDAD (REGLA DE NEGOCIO ESTRICTA)
       El formulario exige que todos los campos existan. */
    
    IF _Id_Region IS NULL OR _Id_Region <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA: Identificador de Región inválido.';
    END IF;

    IF _Nuevo_Codigo IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN: El CÓDIGO es obligatorio para la edición.';
    END IF;

    IF _Nuevo_Nombre IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN: El NOMBRE es obligatorio para la edición.';
    END IF;
    
    IF _Nueva_Desc IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN: La DESCRIPCIÓN es obligatoria para la edición.';
    END IF;

    /* ========================================================================================
       BLOQUE 3: ESTRATEGIA DE BLOQUEO DETERMINÍSTICO (PREVENCIÓN DE DEADLOCKS)
       ======================================================================================== */
    START TRANSACTION;

    /* ----------------------------------------------------------------------------------------
       PASO 3.1: RECONOCIMIENTO (LECTURA SUCIA / NO BLOQUEANTE)
       Primero "miramos" el panorama para saber qué filas están involucradas sin bloquear nada aún.
       ---------------------------------------------------------------------------------------- */
    
    /* A) Identificar el registro objetivo (Target) */
    SELECT `Codigo`, `Nombre` INTO v_Cod_Act, v_Nom_Act
    FROM `Cat_Regiones_Trabajo` WHERE `Id_CatRegion` = _Id_Region;

    /* Si no encontramos el registro propio, abortamos (pudo ser borrado por otro admin) */
    IF v_Cod_Act IS NULL AND v_Nom_Act IS NULL THEN 
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO: La Región que intenta editar no existe.';
    END IF;

    /* B) Identificar posible conflicto de CÓDIGO (¿Alguien más ya tiene mi nuevo código?)
       Solo buscamos si el código cambió. */
    IF _Nuevo_Codigo <> IFNULL(v_Cod_Act, '') THEN
        SELECT `Id_CatRegion` INTO v_Id_Conflicto_Cod 
        FROM `Cat_Regiones_Trabajo` 
        WHERE `Codigo` = _Nuevo_Codigo AND `Id_CatRegion` <> _Id_Region LIMIT 1;
    END IF;

    /* C) Identificar posible conflicto de NOMBRE (¿Alguien más ya tiene mi nuevo nombre?)
       Solo buscamos si el nombre cambió. */
    IF _Nuevo_Nombre <> v_Nom_Act THEN
        SELECT `Id_CatRegion` INTO v_Id_Conflicto_Nom 
        FROM `Cat_Regiones_Trabajo` 
        WHERE `Nombre` = _Nuevo_Nombre AND `Id_CatRegion` <> _Id_Region LIMIT 1;
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 3.2: EJECUCIÓN DE BLOQUEOS ORDENADOS
       Esta es la parte crítica para evitar Deadlocks.
       Ordenamos los IDs (Propio, ConflictoCod, ConflictoNom) y bloqueamos de MENOR a MAYOR.
       Esto garantiza que todos los procesos adquieran recursos en la misma dirección.
       ---------------------------------------------------------------------------------------- */
    
    /* Llenamos el pool de IDs a bloquear */
    SET v_L1 = _Id_Region;
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
        SELECT 1 INTO v_Existe FROM `Cat_Regiones_Trabajo` WHERE `Id_CatRegion` = v_Min FOR UPDATE;
        /* Marcar como procesado (borrar del pool) */
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
        SELECT 1 INTO v_Existe FROM `Cat_Regiones_Trabajo` WHERE `Id_CatRegion` = v_Min FOR UPDATE;
        /* Marcar como procesado */
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
        SELECT 1 INTO v_Existe FROM `Cat_Regiones_Trabajo` WHERE `Id_CatRegion` = v_Min FOR UPDATE;
    END IF;

    /* ========================================================================================
       BLOQUE 4: LÓGICA DE NEGOCIO (BAJO PROTECCIÓN DE LOCKS)
       ======================================================================================== */

    /* 4.1 RE-LECTURA AUTORIZADA
       Ahora que tenemos los bloqueos, leemos el estado definitivo de nuestro registro.
       (Podría haber cambiado en los milisegundos previos al bloqueo). */
    SELECT `Codigo`, `Nombre`, `Descripcion` 
    INTO v_Cod_Act, v_Nom_Act, v_Desc_Act
    FROM `Cat_Regiones_Trabajo` 
    WHERE `Id_CatRegion` = _Id_Region; 

    IF v_Nom_Act IS NULL THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR CRÍTICO: El registro desapareció durante la transacción.';
    END IF;

    /* 4.2 DETECCIÓN DE IDEMPOTENCIA (SIN CAMBIOS)
       Comparamos si los datos nuevos son matemáticamente iguales a los actuales. 
       Usamos `<=>` (Null-Safe Equality) para manejar correctamente los NULLs. */
    IF (v_Cod_Act <=> _Nuevo_Codigo) 
       AND (v_Nom_Act = _Nuevo_Nombre) 
       AND (v_Desc_Act <=> _Nueva_Desc) THEN
        
        COMMIT;
        /* Retorno anticipado para ahorrar I/O */
        SELECT 'No se detectaron cambios en la información.' AS Mensaje, 'SIN_CAMBIOS' AS Accion, _Id_Region AS Id_Region;
        LEAVE SP;
    END IF;

    /* 4.3 VALIDACIÓN FINAL DE UNICIDAD (PRE-UPDATE CHECK)
       Verificamos si existen duplicados REALES. Al tener los registros conflictivos bloqueados,
       esta verificación es 100% fiable. */
    
    /* Validación por CÓDIGO */
    SET v_Id_Error = NULL;
    SELECT `Id_CatRegion` INTO v_Id_Error FROM `Cat_Regiones_Trabajo` 
    WHERE `Codigo` = _Nuevo_Codigo AND `Id_CatRegion` <> _Id_Region LIMIT 1;
    
    IF v_Id_Error IS NOT NULL THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE DUPLICIDAD: El CÓDIGO ya pertenece a otra Región.';
    END IF;

    /* Validación por NOMBRE */
    SET v_Id_Error = NULL;
    SELECT `Id_CatRegion` INTO v_Id_Error FROM `Cat_Regiones_Trabajo` 
    WHERE `Nombre` = _Nuevo_Nombre AND `Id_CatRegion` <> _Id_Region LIMIT 1;
    
    IF v_Id_Error IS NOT NULL THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE DUPLICIDAD: El NOMBRE ya pertenece a otra Región.';
    END IF;

    /* ========================================================================================
       BLOQUE 5: PERSISTENCIA (UPDATE)
       ======================================================================================== */
    
    SET v_Dup = 0; -- Resetear bandera de error antes de escribir

    UPDATE `Cat_Regiones_Trabajo`
    SET `Codigo`      = _Nuevo_Codigo,
        `Nombre`      = _Nuevo_Nombre,
        `Descripcion` = _Nueva_Desc,
        `updated_at`  = NOW()
    WHERE `Id_CatRegion` = _Id_Region;

    /* ========================================================================================
       BLOQUE 6: MANEJO DE COLISIÓN TARDÍA (RECUPERACIÓN DE ERROR 1062)
       ========================================================================================
       Si v_Dup = 1, significa que otro usuario insertó un registro conflictivo en el 
       instante exacto entre nuestro SELECT de validación y el UPDATE (Race Condition extrema). */
    IF v_Dup = 1 THEN
        ROLLBACK;
        
        /* Diagnóstico Post-Mortem para el usuario */
        SET v_Campo_Error = 'DESCONOCIDO';
        SET v_Id_Error = NULL;

        /* ¿Fue conflicto de Código? */
        SELECT `Id_CatRegion` INTO v_Id_Error FROM `Cat_Regiones_Trabajo` 
        WHERE `Codigo` = _Nuevo_Codigo AND `Id_CatRegion` <> _Id_Region LIMIT 1;
        
        IF v_Id_Error IS NOT NULL THEN
            SET v_Campo_Error = 'CODIGO';
        ELSE
            /* Entonces fue conflicto de Nombre */
            SELECT `Id_CatRegion` INTO v_Id_Error FROM `Cat_Regiones_Trabajo` 
            WHERE `Nombre` = _Nuevo_Nombre AND `Id_CatRegion` <> _Id_Region LIMIT 1;
            SET v_Campo_Error = 'NOMBRE';
        END IF;

        SELECT 'Error de Concurrencia: Conflicto detectado al guardar (Otro usuario ganó).' AS Mensaje, 
               'CONFLICTO' AS Accion, 
               v_Campo_Error AS Campo, 
               v_Id_Error AS Id_Conflicto;
        LEAVE SP;
    END IF;

    /* ========================================================================================
       BLOQUE 7: CONFIRMACIÓN EXITOSA
       ======================================================================================== */
    COMMIT;
    
    SELECT 'Región actualizada correctamente.' AS Mensaje, 
           'ACTUALIZADA' AS Accion, 
           _Id_Region AS Id_Region;

END$$

DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_CambiarEstatusRegion
   ============================================================================================
   
   1. DEFINICIÓN DEL OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   ----------------------------------------------------------------------------------------------------
   Este procedimiento implementa la lógica de "Gestión de Ciclo de Vida" para la entidad [Regiones].
   Su función principal es administrar el mecanismo de BAJA LÓGICA (Soft Delete), permitiendo:
     A) SUSPENSIÓN OPERATIVA (Desactivar): Ocultar una región de los selectores operativos sin
        eliminar su historial transaccional.
     B) RESTAURACIÓN (Activar): Recuperar una región histórica para su uso activo.

   2. ARQUITECTURA DE INTEGRIDAD REFERENCIAL (CRITICAL PATH)
   ----------------------------------------------------------------------------------------------------
   Se aplica una política estricta de "No Huérfanos" (Orphan Prevention Strategy).
   - REGLA DE BLOQUEO: No se permite desactivar una Región si existen recursos humanos (Personal)
     actualmente asignados y activos en ella.
   - JUSTIFICACIÓN: Evita inconsistencias sistémicas donde un empleado activo pertenece a una
     ubicación administrativa inexistente.

   3. ESTRATEGIA DE CONCURRENCIA Y AISLAMIENTO (ACID COMPLIANCE)
   ----------------------------------------------------------------------------------------------------
   - NIVEL DE AISLAMIENTO: Utiliza 'SELECT ... FOR UPDATE' (Pessimistic Locking).
   - OBJETIVO: Serializar el acceso al registro específico de la región durante la transacción.
   - ESCENARIO EVITADO (RACE CONDITION): Previene que un Administrador A desactive la región
     mientras un Administrador B asigna simultáneamente un nuevo empleado a dicha región.

   4. OPTIMIZACIÓN DE RECURSOS (IDEMPOTENCY)
   ----------------------------------------------------------------------------------------------------
   - El procedimiento es IDEMPOTENTE. Antes de iniciar escrituras en disco (I/O costoso), verifica
     si el estado deseado ya es el estado actual. Si son iguales, aborta la escritura y retorna
     éxito, preservando los timestamps de auditoría y reduciendo la carga del Transaction Log.

   5. CONTRATO DE SALIDA (OUTPUT CONTRACT)
   ----------------------------------------------------------------------------------------------------
   Retorna un resultset (Single Row) con:
     - Mensaje (VARCHAR): Feedback legible para el usuario final.
     - Activo_Anterior (TINYINT): Estado previo para rollback visual en Frontend.
     - Activo_Nuevo (TINYINT): Estado final confirmado.
   ==================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_CambiarEstatusRegion`$$

CREATE PROCEDURE `SP_CambiarEstatusRegion`(
    IN _Id_Region    INT,     -- Identificador Único (PK) de la Región objetivo en `Cat_Regiones_Trabajo`.
    IN _Nuevo_Estatus TINYINT -- Flag de Estado Solicitado: 1 = Activo (Visible), 0 = Inactivo (Soft Delete).
)
THIS_PROC: BEGIN
    /* ================================================================================================
       SECCIÓN 1: DEFINICIÓN DE CONTEXTO Y VARIABLES DE ESTADO
       Propósito: Inicializar los contenedores de datos que mantendrán la "foto" (Snapshot) del
       registro antes de cualquier modificación.
       ================================================================================================ */
    
    -- [Flag de Existencia]: Determina si el ID proporcionado apunta a un registro válido en la BDD.
    DECLARE v_Existe        INT DEFAULT NULL;
    
    -- [Snapshot de Estado]: Almacena el valor actual de la columna `Activo` antes de la modificación.
    -- Vital para la verificación de idempotencia.
    DECLARE v_Activo_Actual TINYINT(1) DEFAULT NULL;
    
    -- [Semáforo de Dependencias]: Variable auxiliar utilizada durante la validación de integridad.
    -- Si cambia a NOT NULL, indica que existe un bloqueo de negocio (ej. Empleados activos).
    DECLARE v_Dependencias  INT DEFAULT NULL;

    /* ================================================================================================
       SECCIÓN 2: GESTIÓN DE EXCEPCIONES Y ATOMICIDAD (ERROR HANDLING)
       Propósito: Garantizar que la base de datos nunca quede en un estado inconsistente ante fallos.
       ================================================================================================ */
    
    -- [Safety Net]: Captura cualquier error SQL (SQLEXCEPTION) no controlado explícitamente.
    -- ACCIÓN: Ejecuta un ROLLBACK total para deshacer cambios pendientes y propaga el error (RESIGNAL)
    -- para que la capa de aplicación (Backend/API) sea notificada del fallo técnico.
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; 
    END;

    /* ================================================================================================
       SECCIÓN 3: PROTOCOLO DE VALIDACIÓN DE ENTRADA (DEFENSIVE PROGRAMMING)
       Propósito: Rechazar peticiones malformadas ("Fail Fast") antes de consumir recursos de transacción.
       ================================================================================================ */
    
    -- [Validación de Identidad]: El ID debe ser un entero positivo.
    IF _Id_Region IS NULL OR _Id_Region <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: El ID de la Región es inválido o nulo.';
    END IF;

    -- [Validación de Dominio]: El estatus debe ser binario estrictamente (0 o 1).
    IF _Nuevo_Estatus NOT IN (0, 1) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: El valor de Estatus está fuera de rango (Permitido: 0, 1).';
    END IF;

    /* ================================================================================================
       SECCIÓN 4: INICIO DE TRANSACCIÓN Y BLOQUEO PESIMISTA
       Propósito: Aislar el registro objetivo para asegurar consistencia durante la lectura y escritura.
       ================================================================================================ */
    START TRANSACTION;

    /* ------------------------------------------------------------------------------------------------
       PASO 4.1: ADQUISICIÓN DE SNAPSHOT CON BLOQUEO DE ESCRITURA (FOR UPDATE)
       
       Mecánica Técnica:
       Se realiza una lectura del registro usando la cláusula `FOR UPDATE`.
       
       Efecto en el Motor de Base de Datos:
       1. Verifica si el registro existe.
       2. Coloca un "Row-Level Lock" (X-Lock) sobre la fila específica del ID.
       3. Cualquier otra transacción que intente leer o escribir en ESTA fila deberá esperar
          hasta que esta transacción termine (COMMIT o ROLLBACK).
       ------------------------------------------------------------------------------------------------ */
    SELECT 1, `Activo` 
    INTO v_Existe, v_Activo_Actual
    FROM `Cat_Regiones_Trabajo` 
    WHERE `Id_CatRegion` = _Id_Region 
    LIMIT 1 
    FOR UPDATE;

    -- [Verificación de Existencia]: Si el SELECT no encontró nada, v_Existe sigue siendo NULL.
    IF v_Existe IS NULL THEN 
        -- Nota: No se requiere ROLLBACK explícito aquí porque no se ha modificado nada aún,
        -- pero el SIGNAL abortará la transacción implícitamente.
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [404]: La Región solicitada no existe en el catálogo maestro.'; 
    END IF;

    /* ------------------------------------------------------------------------------------------------
       PASO 4.2: VERIFICACIÓN DE IDEMPOTENCIA (OPTIMIZACIÓN)
       
       Lógica de Negocio:
       "Si me pides encender la luz, pero la luz ya está encendida, no toco el interruptor".
       
       Beneficio Técnico:
       - Evita un UPDATE innecesario (ahorra ciclos de CPU y escrituras en disco).
       - Evita alterar la columna `updated_at` innecesariamente (preserva la auditoría real).
       ------------------------------------------------------------------------------------------------ */
    IF v_Activo_Actual = _Nuevo_Estatus THEN
        
        COMMIT; -- Liberamos el bloqueo (Lock) inmediatamente.
        
        -- Retorno informativo indicando que no hubo cambios.
        SELECT CASE 
            WHEN _Nuevo_Estatus = 1 THEN 'OPERACIÓN OMITIDA: La Región ya se encuentra en estado ACTIVO.' 
            ELSE 'OPERACIÓN OMITIDA: La Región ya se encuentra en estado INACTIVO.' 
        END AS Mensaje,
        v_Activo_Actual AS Activo_Anterior,
        _Nuevo_Estatus AS Activo_Nuevo;
        
        -- Salimos del bloque principal para terminar el SP.
        LEAVE THIS_PROC; 
    END IF;

    /* ================================================================================================
       SECCIÓN 5: EVALUACIÓN DE REGLAS DE NEGOCIO COMPLEJAS (INTEGRIDAD REFERENCIAL)
       Propósito: Validar que el cambio de estado no rompa la coherencia de los datos relacionados.
       ================================================================================================ */

    /* ------------------------------------------------------------------------------------------------
       PASO 5.1: REGLA DE "BAJA SEGURA" (SAFE DELETE GUARD)
       Condición: Esta validación SOLO se ejecuta si intentamos DESACTIVAR (_Nuevo_Estatus = 0).
       Objetivo: Proteger a las tablas hijas (`Info_Personal`) de quedar huérfanas lógica y funcionalmente.
       ------------------------------------------------------------------------------------------------ */
    IF _Nuevo_Estatus = 0 THEN
        
        -- Reiniciamos el semáforo
        SET v_Dependencias = NULL;
        
        -- [Sondeo de Dependencias]:
        -- Buscamos si existe AL MENOS UN registro en la tabla de Personal que cumpla dos condiciones:
        -- 1. Esté asignado a esta región (`Fk_Id_CatRegion`).
        -- 2. El empleado esté ACTIVO (`Activo` = 1). (Los empleados históricos/baja no bloquean).
        SELECT 1 INTO v_Dependencias
        FROM `Info_Personal`
        WHERE `Fk_Id_CatRegion` = _Id_Region
          AND `Activo` = 1 
        LIMIT 1;

        -- [Disparador de Bloqueo]: Si encontramos dependencias, abortamos la operación.
        IF v_Dependencias IS NOT NULL THEN
            SIGNAL SQLSTATE '45000' 
                SET MESSAGE_TEXT = 'CONFLICTO DE INTEGRIDAD [409]: No es posible dar de baja la Región. Existen EMPLEADOS ACTIVOS asignados a esta ubicación. Realice la reasignación o baja del personal primero.';
        END IF;
    END IF;

    /* ================================================================================================
       SECCIÓN 6: PERSISTENCIA Y FINALIZACIÓN (COMMIT)
       Propósito: Aplicar los cambios validados y confirmar la transacción.
       ================================================================================================ */

    /* ------------------------------------------------------------------------------------------------
       PASO 6.1: EJECUCIÓN DE LA ACTUALIZACIÓN (UPDATE)
       En este punto, hemos superado todas las validaciones (Input, Existencia, Idempotencia, Integridad).
       Es seguro escribir en la base de datos.
       ------------------------------------------------------------------------------------------------ */
    UPDATE `Cat_Regiones_Trabajo` 
    SET `Activo` = _Nuevo_Estatus, 
        `updated_at` = NOW() -- [Traza de Auditoría]: Actualizamos la marca de tiempo del sistema.
    WHERE `Id_CatRegion` = _Id_Region;
    
    /* ------------------------------------------------------------------------------------------------
       PASO 6.2: CONFIRMACIÓN DE TRANSACCIÓN (COMMIT)
       Hacemos permanentes los cambios y liberamos los bloqueos (Locks) adquiridos en el PASO 4.1.
       ------------------------------------------------------------------------------------------------ */
    COMMIT; 
    
    /* ------------------------------------------------------------------------------------------------
       PASO 6.3: GENERACIÓN DE RESPUESTA AL CLIENTE (RESPONSE MAPPING)
       Retornamos el estado final para que la interfaz de usuario pueda sincronizarse con el Backend.
       ------------------------------------------------------------------------------------------------ */
    SELECT CASE 
        WHEN _Nuevo_Estatus = 1 THEN 'ÉXITO: La Región ha sido REACTIVADA y está visible para operaciones.' 
        ELSE 'ÉXITO: La Región ha sido DESACTIVADA (Baja Lógica). No se mostrará en nuevos registros.' 
    END AS Mensaje,
    v_Activo_Actual AS Activo_Anterior,
    _Nuevo_Estatus AS Activo_Nuevo;

END$$

DELIMITER ;

/* ====================================================================================================
   PROCEDIMIENTO: SP_EliminarRegionFisica
   ====================================================================================================
1. VISIÓN GENERAL Y OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   ----------------------------------------------------------------------------------------------------
   Este procedimiento implementa la operación de ELIMINACIÓN FÍSICA (Hard Delete) sobre la entidad
   "Región Operativa" (`Cat_Regiones_Trabajo`).
   
   A diferencia de la "Baja Lógica" (que solo oculta el registro), este proceso DESTRUYE la información
   de manera permanente. Su uso está estrictamente limitado a tareas de:
     A) Saneamiento de Datos (Data Cleansing): Eliminación de registros creados por error humano
        inmediatamente después de su creación (antes de tener uso).
     B) Depuración Administrativa: Mantenimiento técnico de catálogos corruptos.

   2. ARQUITECTURA DE INTEGRIDAD REFERENCIAL (ESTRATEGIA "DEFENSA EN PROFUNDIDAD")
   ----------------------------------------------------------------------------------------------------
   Para prevenir la corrupción silenciosa de la base de datos (Orphaned Records), este SP implementa
   tres anillos de seguridad antes de permitir la destrucción:

     ANILLO 1: VALIDACIÓN DE EXISTENCIA (Fail Fast)
     - Rechaza inmediatamente IDs nulos o inexistentes para evitar bloqueos innecesarios.

     ANILLO 2: VALIDACIÓN PROACTIVA DE NEGOCIO (Logic Guard)
     - Consulta explícita a la tabla `Info_Personal`.
     - REGLA CRÍTICA DE AUDITORÍA: La validación busca CUALQUIER historial. No importa si el
       empleado está "Activo" o "Inactivo". Si un empleado *alguna vez* perteneció a esta región,
       el registro se vuelve INBORRABLE para preservar la trazabilidad histórica de los reportes.
     - ACCIÓN: Devuelve un error 409 (Conflict) legible para el humano.

     ANILLO 3: VALIDACIÓN REACTIVA DE MOTOR (Database Constraint - Last Resort)
     - Se apoya en las Foreign Keys (FK) del motor InnoDB.
     - Si existe una relación oculta (ej: una tabla de "Auditoría_Regiones" que olvidamos revisar),
       el motor bloqueará el DELETE lanzando el error 1451.
     - ACCIÓN: Un HANDLER captura este error y hace un Rollback seguro.

   3. MODELO DE CONCURRENCIA Y BLOQUEO (ACID COMPLIANCE)
   ----------------------------------------------------------------------------------------------------
   - AISLAMIENTO: Serializable (vía Locking).
   - MECÁNICA: Al ejecutar el comando `DELETE`, el motor InnoDB adquiere automáticamente un
     BLOQUEO EXCLUSIVO DE FILA (X-LOCK).
   - EFECTO: Nadie puede leer, editar o asignar empleados a esta Región durante los milisegundos
     que dura la transacción de borrado.

   4. CONTRATO DE SALIDA (OUTPUT CONTRACT)
   ----------------------------------------------------------------------------------------------------
   Retorna un resultset de una sola fila (Single Row) indicando el éxito de la operación.
   En caso de fallo, se lanzan señales SQLSTATE controladas (400, 404, 409).
   ==================================================================================================== */
DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_EliminarRegionFisica`$$

CREATE PROCEDURE `SP_EliminarRegionFisica`(
    /* PARÁMETRO DE ENTRADA */
    IN _Id_Region INT -- PK: Identificador único de la Región a purgar.
)
THIS_PROC: BEGIN
    
    /* ================================================================================================
       BLOQUE 0: VARIABLES DE DIAGNÓSTICO
       Propósito: Definición de contenedores locales para almacenar el estado de las validaciones.
       ================================================================================================ */
    -- Semáforo para detectar si existen hijos/dependencias en tablas relacionadas.
    DECLARE v_Dependencias INT DEFAULT NULL;

    /* ================================================================================================
       BLOQUE 1: DEFINICIÓN DE HANDLERS (MANEJO DE EXCEPCIONES TÉCNICAS)
       Propósito: Asegurar que el procedimiento nunca termine abruptamente sin limpiar la transacción.
       ================================================================================================ */
    
    /* ------------------------------------------------------------------------------------------------
       HANDLER 1.1: PROTECCIÓN DE INTEGRIDAD REFERENCIAL (Error MySQL 1451)
       Contexto: Este error ocurre cuando intentamos borrar un padre que tiene hijos (FK) activos.
       Estrategia: "Graceful Failure". En lugar de mostrar un error SQL críptico al usuario,
       revertimos la transacción y mostramos un mensaje de negocio explicativo.
       ------------------------------------------------------------------------------------------------ */
    DECLARE EXIT HANDLER FOR 1451 
    BEGIN 
        ROLLBACK; 
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'BLOQUEO DE INTEGRIDAD [1451]: El sistema de base de datos impidió el borrado. Existen registros en otras tablas (Gerencias, Históricos o Auditoría) vinculados a esta Región que no fueron detectados por la validación previa.'; 
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
    IF _Id_Region IS NULL OR _Id_Region <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: El parámetro ID de Región es inválido o nulo.';
    END IF;

    /* 2.2 Validación de Existencia: Verificación contra el Catálogo Maestro.
       Nota: Hacemos esto antes de buscar dependencias para diferenciar un error "No encontrado" (404)
       de un error "No se puede borrar" (409). */
    IF NOT EXISTS (SELECT 1 FROM `Cat_Regiones_Trabajo` WHERE `Id_CatRegion` = _Id_Region) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [404]: La Región que intenta eliminar no existe en la base de datos.';
    END IF;

    /* ================================================================================================
       BLOQUE 3: CANDADO DE NEGOCIO (LOGIC LOCK)
       Propósito: Aplicar las reglas de dominio específicas para la destrucción de información.
       ================================================================================================ */
    
    /* ------------------------------------------------------------------------------------------------
       PASO 3.1: INSPECCIÓN DE HISTORIAL LABORAL (`Info_Personal`)
       
       Objetivo Técnico:
       Escanear la tabla transaccional de empleados para ver si la Región _Id_Region
       ha sido utilizada alguna vez como llave foránea (`Fk_Id_CatRegion`).
       
       Justificación de Negocio (POR QUÉ NO FILTRAMOS POR "ACTIVO"):
       Un empleado puede estar dado de baja (Inactivo) hoy, pero trabajó en esta Región hace 3 años.
       Si borramos la Región físicamente, el registro histórico del empleado quedaría apuntando a NULL
       o generaría inconsistencia en los reportes de antigüedad y trayectoria.
       Por lo tanto, la mera existencia de un registro (activo o inactivo) es motivo de BLOQUEO.
       ------------------------------------------------------------------------------------------------ */
    SELECT 1 INTO v_Dependencias
    FROM `Info_Personal`
    WHERE `Fk_Id_CatRegion` = _Id_Region
    LIMIT 1; -- Optimización: Con encontrar uno solo es suficiente para detener el proceso.

    /* ------------------------------------------------------------------------------------------------
       PASO 3.2: EVALUACIÓN DEL BLOQUEO
       Si la variable v_Dependencias dejó de ser NULL, significa que hay historial.
       ------------------------------------------------------------------------------------------------ */
    IF v_Dependencias IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'CONFLICTO DE NEGOCIO [409]: Operación denegada. No es posible eliminar esta Región porque existen expedientes de PERSONAL (Activos o Históricos) asociados a ella. La eliminación física rompería la integridad histórica. Utilice la opción "Desactivar/Baja Lógica".';
    END IF;

    /* ================================================================================================
       BLOQUE 4: TRANSACCIÓN DE BORRADO (ZONA CRÍTICA)
       Propósito: Ejecutar el cambio de estado persistente de manera atómica.
       ================================================================================================ */
    START TRANSACTION;

    /* ------------------------------------------------------------------------------------------------
       PASO 4.1: EJECUCIÓN DEL DELETE
       Acción: El motor intenta eliminar la fila física.
       
       Implicación de Motor (InnoDB):
       1. Se verifica nuevamente la restricción de llave foránea (Constraint Check).
       2. Si pasa, se adquiere un LOCK EXCLUSIVO (X-LOCK) en el índice primario.
       3. Se escribe el cambio en el Buffer Pool y en el Redo Log.
       
       Red de Seguridad:
       Si alguna tabla (no validada en el Bloque 3) tiene una referencia, aquí saltará el HANDLER 1451.
       ------------------------------------------------------------------------------------------------ */
    DELETE FROM `Cat_Regiones_Trabajo` 
    WHERE `Id_CatRegion` = _Id_Region;

    /* ------------------------------------------------------------------------------------------------
       PASO 4.2: CONFIRMACIÓN (COMMIT)
       Acción: Se finaliza la transacción.
       Efecto: El bloqueo exclusivo se libera. El espacio en disco se marca como reutilizable.
       ------------------------------------------------------------------------------------------------ */
    COMMIT;

    /* ================================================================================================
       BLOQUE 5: RESPUESTA AL CLIENTE (RESPONSE MAPPING)
       Propósito: Informar al Frontend/API que la operación concluyó exitosamente.
       ================================================================================================ */
    SELECT 
        'ÉXITO: La Región ha sido eliminada permanentemente del sistema.' AS Mensaje, 
        'HARD_DELETE' AS Tipo_Operacion,
        _Id_Region AS Id_Recurso_Eliminado,
        NOW() AS Fecha_Ejecucion;

END$$

DELIMITER ;