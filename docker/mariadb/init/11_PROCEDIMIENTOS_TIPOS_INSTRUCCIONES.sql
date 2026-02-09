USE `PICADE`;

/* ------------------------------------------------------------------------------------------------------ */
/* CREACION DE VISTAS Y PROCEDIMIENTOS DE ALMACENADO PARA LA BASE DE DATOS                                */
/* ------------------------------------------------------------------------------------------------------ */

/* ======================================================================================================
   VIEW: Vista_Tipos_Instruccion
   ======================================================================================================
   
   1. OBJETIVO TÉCNICO Y DE NEGOCIO (BUSINESS GOAL)
   ------------------------------------------------
   Esta vista actúa como la **Interfaz Canónica de Administración** para el catálogo de "Tipos de 
   Instrucción" (Naturaleza Pedagógica: Teórico, Práctico, Mixto).

   Su función es desacoplar la estructura física de la tabla `Cat_Tipos_Instruccion_Cap` de la capa 
   de presentación, proporcionando un punto de acceso único y estandarizado para el Grid de Mantenimiento.

   2. ARQUITECTURA DE DATOS (PROYECCIÓN TOTAL)
   -------------------------------------------
   A diferencia de las vistas para dropdowns (que son ligeras), esta vista está diseñada para la 
   **Gestión y Auditoría**, por lo que expone la totalidad de las columnas disponibles:
   
   - Datos Descriptivos: Se incluye la `Descripción` para que el administrador entienda el alcance 
     de cada tipo.
   - Datos de Auditoría: Se incluyen `created_at` y `updated_at` para rastrear cuándo se crearon 
     o modificaron los registros.

   3. NOMENCLATURA Y SEMÁNTICA (NORMALIZACIÓN)
   -------------------------------------------
   Se aplica una transformación de nombres (Aliasing) para garantizar consistencia con el resto del sistema:
   - `Id_CatTipoInstCap` -> `Id_Tipo_Instruccion` (Más legible).
   - `Activo` -> `Estatus_Tipo_Instruccion` (Semántica de control).

   4. DICCIONARIO DE DATOS (CONTRATO DE SALIDA)
   --------------------------------------------
   [Bloque 1: Identidad]
   - Id_Tipo_Instruccion:        (INT) Llave Primaria.
   - Nombre_Tipo_Instruccion:    (VARCHAR) Etiqueta principal (ej: 'Teórico-Práctico').

   [Bloque 2: Detalle]
   - Descripcion_Tipo_Instruccion: (VARCHAR) Explicación detallada del tipo.

   [Bloque 3: Control]
   - Estatus_Tipo_Instruccion:   (TINYINT) 1 = Activo, 0 = Inactivo.

   [Bloque 4: Auditoría]
   - Fecha_Registro:             (TIMESTAMP) Fecha de creación.
   - Ultima_Modificacion:        (TIMESTAMP) Fecha de último cambio.
   ====================================================================================================== */

CREATE OR REPLACE 
    ALGORITHM = UNDEFINED 
    SQL SECURITY DEFINER
VIEW `Vista_Tipos_Instruccion` AS
    SELECT 
        /* -----------------------------------------------------------------------------------
           BLOQUE 1: IDENTIDAD
           Datos clave para operaciones CRUD (Update/Delete).
           ----------------------------------------------------------------------------------- */
        `TIC`.`Id_CatTipoInstCap`    AS `Id_Tipo_Instruccion`,
        `TIC`.`Nombre`               AS `Nombre_Tipo_Instruccion`,

        /* -----------------------------------------------------------------------------------
           BLOQUE 2: DETALLE OPERATIVO
           Información contextual para el administrador.
           ----------------------------------------------------------------------------------- */
        `TIC`.`Descripcion`          AS `Descripcion_Tipo_Instruccion`,

        /* -----------------------------------------------------------------------------------
           BLOQUE 3: METADATOS DE CONTROL
           Semáforo de disponibilidad (Visible/Oculto).
           ----------------------------------------------------------------------------------- */
        `TIC`.`Activo`               AS `Estatus_Tipo_Instruccion`
        
        /* -----------------------------------------------------------------------------------
           BLOQUE 4: TRAZABILIDAD (AUDITORÍA)
           Datos temporales requeridos para el control administrativo.
           ----------------------------------------------------------------------------------- */
        -- `TIC`.`created_at`           AS `Fecha_Registro`,
        -- `TIC`.`updated_at`           AS `Ultima_Modificacion`

    FROM 
        `PICADE`.`Cat_Tipos_Instruccion_Cap` `TIC`;

/* ====================================================================================================
   PROCEDIMIENTO: SP_RegistrarTipoInstruccion
   ====================================================================================================
   
   1. VISIÓN GENERAL Y OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   -------------------------------------------------------
   Este procedimiento gestiona el ALTA TRANSACCIONAL de un "Tipo de Instrucción" en el catálogo
   pedagógico (`Cat_Tipos_Instruccion_Cap`).
   
   Su propósito es clasificar la naturaleza de los cursos (ej: Teórico, Práctico, Mixto) para
   fines de logística y certificación. Actúa como la puerta de entrada única para garantizar
   que no existan clasificaciones duplicadas o ambiguas.

   2. REGLAS DE VALIDACIÓN ESTRICTA (HARD CONSTRAINTS)
   ---------------------------------------------------
   A) INTEGRIDAD DE DATOS (DATA HYGIENE):
      - Principio: "Datos limpios desde el origen".
      - Regla: El `Nombre` es el identificador semántico crítico. No se permiten nulos ni cadenas vacías.
      - Acción: Se aplica `TRIM` y validación `NOT NULL` antes de cualquier operación.

   B) IDENTIDAD UNÍVOCA (UNIQUE IDENTITY):
      - Regla: No pueden existir dos tipos con el mismo `Nombre` (ej: dos registros "Teórico").
      - Resolución: Si el nombre ya existe, el sistema evalúa si debe reutilizar el registro activo
        o reactivar uno histórico.

   3. ESTRATEGIA DE PERSISTENCIA Y CONCURRENCIA (ACID)
   ---------------------------------------------------
   A) BLOQUEO PESIMISTA (PESSIMISTIC LOCKING):
      - Se utiliza `SELECT ... FOR UPDATE` al buscar por Nombre.
      - Justificación: Esto "serializa" las peticiones. Si dos coordinadores intentan crear el tipo
        "Híbrido" al mismo tiempo, el segundo esperará a que el primero termine, evitando lecturas
        sucias o inconsistentes.

   B) AUTOSANACIÓN (SELF-HEALING / SOFT DELETE RECOVERY):
      - Escenario: El tipo "Práctico" existía hace años, se dio de baja (`Activo=0`) y ahora se
        quiere volver a usar.
      - Acción: El sistema detecta el registro "muerto", lo reactiva (`Activo=1`), actualiza su
        descripción con la nueva información y lo devuelve como éxito. No se crea un duplicado.

   C) PATRÓN "RE-RESOLVE" (MANEJO DE ERROR 1062):
      - Escenario Crítico: Una "Condición de Carrera" donde dos usuarios hacen INSERT en el mismo
        microsegundo. El motor de BD frenará al segundo con error `1062 (Duplicate Entry)`.
      - Solución: Un `HANDLER` captura el error, hace rollback silencioso y ejecuta una búsqueda
        final para devolver el ID del registro que "ganó", garantizando que el usuario nunca vea
        una pantalla de error técnico.

   4. CONTRATO DE SALIDA (OUTPUT SPECIFICATION)
   --------------------------------------------
   Retorna un Resultset de fila única con:
      - [Mensaje]: Feedback descriptivo (ej: "Tipo registrado exitosamente").
      - [Id_Tipo_Instruccion]: La llave primaria del recurso.
      - [Accion]: Enumerador de estado ('CREADA', 'REACTIVADA', 'REUSADA').
   ==================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_RegistrarTipoInstruccion`$$

CREATE PROCEDURE `SP_RegistrarTipoInstruccion`(
    /* -----------------------------------------------------------------
       PARÁMETROS DE ENTRADA (INPUT LAYER)
       Recibimos los datos crudos del formulario.
       ----------------------------------------------------------------- */
    IN _Nombre      VARCHAR(255),  -- OBLIGATORIO: Identificador natural (ej: 'Teórico')
    IN _Descripcion VARCHAR(255)   -- OPCIONAL: Detalle técnico (ej: 'Requiere aula')
)
THIS_PROC: BEGIN
    
    /* ========================================================================================
       BLOQUE 0: DECLARACIÓN DE VARIABLES DE ENTORNO
       Propósito: Inicializar contenedores para el estado de la base de datos.
       ======================================================================================== */
    /* Variables de Persistencia (Snapshot del registro en BD) */
    DECLARE v_Id_Tipo  INT DEFAULT NULL;
    DECLARE v_Activo   TINYINT(1) DEFAULT NULL;
    
    /* Bandera de Control de Flujo (Semáforo para errores SQL) */
    DECLARE v_Dup      TINYINT(1) DEFAULT 0;

    /* ========================================================================================
       BLOQUE 1: HANDLERS (MANEJO ROBUSTO DE EXCEPCIONES)
       Propósito: Asegurar la estabilidad del sistema ante fallos.
       ======================================================================================== */
    
    /* 1.1 HANDLER DE DUPLICIDAD (Error 1062)
       Objetivo: Capturar colisiones de Unique Key en el INSERT.
       Acción: No abortar. Encender bandera v_Dup = 1 para activar la rutina de recuperación. */
    DECLARE CONTINUE HANDLER FOR 1062 SET v_Dup = 1;

    /* 1.2 HANDLER GENÉRICO (SQLEXCEPTION)
       Objetivo: Capturar fallos técnicos (Disco lleno, Conexión).
       Acción: Abortar inmediatamente, deshacer cambios (ROLLBACK) y propagar el error. */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; 
    END;

    /* ========================================================================================
       BLOQUE 2: SANITIZACIÓN Y VALIDACIÓN (FAIL FAST STRATEGY)
       Propósito: Limpiar datos y rechazar basura antes de tocar la transacción.
       ======================================================================================== */
    
    /* 2.1 LIMPIEZA DE DATOS (TRIM & NULLIF)
       Eliminamos espacios al inicio/final. Si la cadena queda vacía, la convertimos a NULL. */
    SET _Nombre      = NULLIF(TRIM(_Nombre), '');
    SET _Descripcion = NULLIF(TRIM(_Descripcion), '');

    /* 2.2 VALIDACIÓN DE OBLIGATORIEDAD
       Regla: Un Tipo de Instrucción sin nombre no tiene valor semántico. */
    IF _Nombre IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN [400]: El NOMBRE del Tipo de Instrucción es obligatorio.';
    END IF;

    /* ========================================================================================
       BLOQUE 3: LÓGICA DE NEGOCIO TRANSACCIONAL (CORE)
       Propósito: Ejecutar la búsqueda, validación y persistencia de forma atómica.
       ======================================================================================== */
    START TRANSACTION;

    /* ----------------------------------------------------------------------------------------
       PASO 3.1: RESOLUCIÓN DE IDENTIDAD POR NOMBRE (BUSQUEDA PRIMARIA)
       
       Objetivo: Verificar si el concepto (_Nombre) ya existe en el catálogo.
       Mecánica: Usamos `FOR UPDATE` para bloquear la fila encontrada.
       Justificación: Esto evita que otro usuario modifique o reactive este mismo registro
       mientras nosotros tomamos la decisión.
       ---------------------------------------------------------------------------------------- */
    SET v_Id_Tipo = NULL; -- Reset de seguridad

    SELECT `Id_CatTipoInstCap`, `Activo` 
    INTO v_Id_Tipo, v_Activo
    FROM `Cat_Tipos_Instruccion_Cap`
    WHERE `Nombre` = _Nombre
    LIMIT 1
    FOR UPDATE; -- <--- BLOQUEO DE ESCRITURA AQUÍ

    /* ESCENARIO A: EL NOMBRE YA EXISTE */
    IF v_Id_Tipo IS NOT NULL THEN
        
        /* Sub-Escenario A.1: Existe pero está INACTIVO (Baja Lógica) -> REACTIVAR (Autosanación)
           "Resucitamos" el registro y actualizamos su descripción si se proveyó una nueva. */
        IF v_Activo = 0 THEN
            UPDATE `Cat_Tipos_Instruccion_Cap` 
            SET `Activo` = 1, 
                /* Lógica de Fusión: Si el usuario mandó descripción nueva, la usamos. 
                   Si no, mantenemos la histórica. */
                `Descripcion` = COALESCE(_Descripcion, `Descripcion`), 
                `updated_at` = NOW() 
            WHERE `Id_CatTipoInstCap` = v_Id_Tipo;
            
            COMMIT;
            SELECT 'ÉXITO: Tipo de Instrucción reactivado correctamente.' AS Mensaje, 
                   v_Id_Tipo AS Id_Tipo_Instruccion, 
                   'REACTIVADA' AS Accion;
            LEAVE THIS_PROC;
        
        /* Sub-Escenario A.2: Existe y está ACTIVO -> IDEMPOTENCIA
           El registro ya está tal como lo queremos. No hacemos nada y reportamos éxito. */
        ELSE
            COMMIT;
            SELECT 'AVISO: El Tipo de Instrucción ya existe y se encuentra activo.' AS Mensaje, 
                   v_Id_Tipo AS Id_Tipo_Instruccion, 
                   'REUSADA' AS Accion;
            LEAVE THIS_PROC;
        END IF;
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 3.2: PERSISTENCIA (INSERCIÓN FÍSICA)
       
       Si llegamos aquí, el registro no existe por Nombre. Es seguro intentar crearlo.
       Aquí existe un riesgo infinitesimal de "Race Condition" si otro usuario inserta 
       exactamente el mismo nombre en este preciso instante (cubierto por Handler 1062).
       ---------------------------------------------------------------------------------------- */
    SET v_Dup = 0; -- Reiniciamos bandera de error
    
    INSERT INTO `Cat_Tipos_Instruccion_Cap`
    (
        `Nombre`, 
        `Descripcion`,
        `Activo`,
        `created_at`,
        `updated_at`
    )
    VALUES
    (
        _Nombre, 
        _Descripcion,
        1,      -- Default: Activo
        NOW(),  -- Timestamp Creación
        NOW()   -- Timestamp Actualización
    );

    /* Verificación de Éxito: Si v_Dup sigue en 0, el INSERT fue limpio. */
    IF v_Dup = 0 THEN
        COMMIT; 
        SELECT 'ÉXITO: Tipo de Instrucción registrado correctamente.' AS Mensaje, 
               LAST_INSERT_ID() AS Id_Tipo_Instruccion, 
               'CREADA' AS Accion;
        LEAVE THIS_PROC;
    END IF;

    /* ========================================================================================
       BLOQUE 4: RUTINA DE RECUPERACIÓN DE CONCURRENCIA (RE-RESOLVE PATTERN)
       Propósito: Manejar elegantemente el Error 1062 (Duplicate Key) si ocurre una colisión.
       ======================================================================================== */
    
    /* Si estamos aquí, v_Dup = 1. Significa que "perdimos" la carrera contra otro INSERT. */
    
    ROLLBACK; -- 1. Revertir la transacción fallida para liberar bloqueos parciales.
    
    START TRANSACTION; -- 2. Iniciar una nueva transacción limpia.
    
    SET v_Id_Tipo = NULL;
    
    /* 3. Buscar el registro "ganador" (El que insertó el otro usuario) */
    SELECT `Id_CatTipoInstCap`, `Activo`
    INTO v_Id_Tipo, v_Activo
    FROM `Cat_Tipos_Instruccion_Cap`
    WHERE `Nombre` = _Nombre
    LIMIT 1
    FOR UPDATE;
    
    IF v_Id_Tipo IS NOT NULL THEN
        /* Reactivar si el ganador estaba inactivo (caso muy raro en carrera, pero posible) */
        IF v_Activo = 0 THEN
            UPDATE `Cat_Tipos_Instruccion_Cap` 
            SET `Activo` = 1, `updated_at` = NOW() 
            WHERE `Id_CatTipoInstCap` = v_Id_Tipo;
            
            COMMIT;
            SELECT 'ÉXITO: Tipo reactivado (recuperado tras concurrencia).' AS Mensaje, 
                   v_Id_Tipo AS Id_Tipo_Instruccion, 
                   'REACTIVADA' AS Accion;
            LEAVE THIS_PROC;
        END IF;
        
        /* Retornar el ID existente (Reuso) */
        COMMIT;
        SELECT 'AVISO: El Tipo ya existía (reusado tras concurrencia).' AS Mensaje, 
               v_Id_Tipo AS Id_Tipo_Instruccion, 
               'REUSADA' AS Accion;
        LEAVE THIS_PROC;
    END IF;

    /* Fallo Irrecuperable: Si falló por 1062 pero no encontramos el registro 
       (Indica corrupción de índices o error fantasma grave) */
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR CRÍTICO [500]: Fallo de concurrencia no recuperable en Tipos de Instrucción.';

END$$

DELIMITER ;

/* ============================================================================================
   SECCIÓN: CONSULTAS ESPECÍFICAS (PARA EDICIÓN / DETALLE)
   ============================================================================================
   Estas rutinas son clave para la UX. No solo devuelven el dato pedido, sino todo el 
   contexto necesario para que el formulario de edición se autocomplete correctamente.
   ============================================================================================ */
   
   /* ============================================================================================
   PROCEDIMIENTO: SP_ConsultarTipoInstruccionEspecifico
   ============================================================================================
   
   1. OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   --------------------------------------
   Recuperar la "Ficha Técnica" completa y sin procesar (Raw Data) de un Tipo de Instrucción
   específico, identificado por su llave primaria (`Id_CatTipoInstCap`).

   CASOS DE USO (CONTEXTO DE UI):
   A) PRECARGA DE FORMULARIO DE EDICIÓN (UPDATE):
      - Cuando el administrador va a editar un tipo (ej: corregir "Teórico" por "Teórico-Práctico"),
        el formulario debe llenarse con los datos exactos que residen en la base de datos.
      - Requisito Crítico: Fidelidad del dato. Si la descripción es NULL en la BD, el SP debe
        devolver NULL (o el driver de BD lo hará), para que el input del frontend se muestre limpio.

   B) VISUALIZACIÓN DE DETALLE (AUDITORÍA):
      - Permite visualizar metadatos de auditoría (`created_at`, `updated_at`) que normalmente
        se ocultan en el Grid principal para mantener la limpieza visual.

   2. ARQUITECTURA DE DATOS (DIRECT TABLE ACCESS)
   ----------------------------------------------
   Este procedimiento consulta directamente la tabla física `Cat_Tipos_Instruccion_Cap`, evitando
   el uso de la vista `Vista_Cat_Tipos_Instruccion_Admin`.

   JUSTIFICACIÓN TÉCNICA:
   - Desacoplamiento de Presentación: Las Vistas pueden tener alias "humanizados" o lógica de 
     presentación. Los SPs de Edición requieren los nombres de columna originales o mapeados
     específicamente para el binding del modelo de datos en el Frontend.
   - Performance: El acceso por Primary Key (`Id_CatTipoInstCap`) es de costo computacional O(1),
     garantizando una respuesta instantánea (<1ms).

   3. ESTRATEGIA DE SEGURIDAD (DEFENSIVE PROGRAMMING)
   --------------------------------------------------
   - Validación de Entrada: Se rechazan IDs nulos o negativos antes de tocar el disco.
   - Fail Fast (Fallo Rápido): Se verifica la existencia del registro antes de intentar devolver datos.
     Esto permite diferenciar claramente entre un "Error 404" (Recurso no encontrado) y un
     "Error 500" (Fallo de servidor).

   4. VISIBILIDAD (SCOPE)
   ----------------------
   - NO se filtra por `Activo = 1`.
   - Razón: Un tipo de instrucción puede estar "Desactivado" (Baja Lógica). El administrador 
     necesita poder consultarlo para ver su información y decidir si lo Reactiva. Ocultarlo 
     aquí haría imposible su gestión desde el panel de administración.

   5. DICCIONARIO DE DATOS (OUTPUT)
   --------------------------------
   Retorna una única fila (Single Row) con:
      - [Identidad]: Id_CatTipoInstCap (Alias: Id_Tipo_Instruccion), Nombre.
      - [Detalle]: Descripcion.
      - [Control]: Activo (Vital para el estado del switch de activación en UI).
      - [Auditoría]: created_at, updated_at.
   ============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ConsultarTipoInstruccionEspecifico`$$
CREATE PROCEDURE `SP_ConsultarTipoInstruccionEspecifico`(
    IN _Id_Tipo INT -- Identificador único del Tipo a consultar
)
BEGIN
    /* ========================================================================================
       BLOQUE 1: VALIDACIÓN DE ENTRADA (DEFENSIVE PROGRAMMING)
       Objetivo: Asegurar que el parámetro recibido sea un entero positivo válido.
       Evita cargas innecesarias al motor de base de datos con peticiones basura.
       ======================================================================================== */
    IF _Id_Tipo IS NULL OR _Id_Tipo <= 0 THEN
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: El Identificador del Tipo de Instrucción es inválido (Debe ser un entero positivo).';
    END IF;

    /* ========================================================================================
       BLOQUE 2: VERIFICACIÓN DE EXISTENCIA (FAIL FAST STRATEGY)
       Objetivo: Validar que el recurso realmente exista en la base de datos.
       
       NOTA DE IMPLEMENTACIÓN:
       Usamos `SELECT 1` que es más ligero que seleccionar columnas reales, ya que solo
       necesitamos confirmar la presencia de la llave en el índice primario.
       ======================================================================================== */
    IF NOT EXISTS (SELECT 1 FROM `Cat_Tipos_Instruccion_Cap` WHERE `Id_CatTipoInstCap` = _Id_Tipo) THEN
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [404]: El Tipo de Instrucción solicitado no existe o fue eliminado físicamente.';
    END IF;

    /* ========================================================================================
       BLOQUE 3: CONSULTA PRINCIPAL (DATA RETRIEVAL)
       Objetivo: Retornar el objeto de datos completo y puro (Raw Data).
       ======================================================================================== */
    SELECT 
        /* --- GRUPO A: IDENTIDAD DEL REGISTRO --- */
        /* Este ID es la llave primaria inmutable. */
        `Id_CatTipoInstCap`  AS `Id_Tipo_Instruccion`,
        
        /* --- GRUPO B: DATOS EDITABLES --- */
        /* El Frontend usará estos campos para llenar los inputs de texto. */
        `Nombre`             AS `Nombre_Tipo_Instruccion`,
        `Descripcion`        AS `Descripcion_Tipo_Instruccion`,
        
        /* --- GRUPO C: METADATOS DE CONTROL DE CICLO DE VIDA --- */
        /* Este valor (0 o 1) indica si el tipo es utilizable actualmente.
           1 = Activo/Visible, 0 = Inactivo/Oculto (Baja Lógica). */
        `Activo`             AS `Estatus_Tipo_Instruccion`,        
        
        /* --- GRUPO D: AUDITORÍA DE SISTEMA --- */
        /* Fechas útiles para mostrar en el pie de página del modal de detalle. */
        `created_at`         AS `Fecha_Registro`,
        `updated_at`         AS `Ultima_Modificacion`
        
    FROM `Cat_Tipos_Instruccion_Cap`
    WHERE `Id_CatTipoInstCap` = _Id_Tipo
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
   PROCEDIMIENTO: SP_ListarTiposInstruccionActivos
   ============================================================================================
   1. OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   --------------------------------------
   Proveer un endpoint de datos ligero y optimizado para alimentar el selector (Dropdown)
   de "Tipo de Instrucción" (Naturaleza Pedagógica) en los formularios de gestión académica.

   Este procedimiento es la fuente autorizada para clasificar cursos en:
      - Alta de Nuevos Temas de Capacitación (`Cat_Temas_Capacitacion`).
      - Filtros de Búsqueda en el Catálogo de Cursos.

   2. REGLAS DE NEGOCIO Y FILTRADO (THE VIGENCY CONTRACT)
   ------------------------------------------------------
   A) FILTRO DE VIGENCIA ESTRICTO (HARD FILTER):
      - Regla: La consulta aplica obligatoriamente la cláusula `WHERE Activo = 1`.
      - Justificación Operativa: Un Tipo de Instrucción marcado como inactivo (Baja Lógica)
        representa una clasificación obsoleta o que ya no se imparte en la institución.
        Permitir su selección para un curso nuevo generaría inconsistencia en la matriz de capacitación.
      - Seguridad: El filtro es nativo en BD para blindar la integridad del catálogo.

   B) ORDENAMIENTO COGNITIVO (USABILITY):
      - Regla: Los resultados se ordenan alfabéticamente por `Nombre` (A-Z).
      - Justificación: Facilita la búsqueda visual rápida (ej: encontrar "Teórico" antes de "Virtual").

   3. ARQUITECTURA DE DATOS (ROOT ENTITY OPTIMIZATION)
   ---------------------------------------------------
   - Ausencia de JOINs: `Cat_Tipos_Instruccion_Cap` es una Entidad Raíz (no depende jerárquicamente
     de otra tabla para existir). Esto permite una consulta directa de altísima velocidad (O(1)).
   
   - Proyección Mínima (Payload Reduction):
     Solo se devuelven las columnas necesarias para construir el elemento HTML `<option>`:
       1. ID (Value): Integridad referencial.
       2. Nombre (Label): Lectura humana.
     Se omite la columna `Descripcion` para minimizar el tráfico de red, ya que no es visible en el dropdown.

   4. DICCIONARIO DE DATOS (OUTPUT JSON SCHEMA)
   --------------------------------------------
   Retorna un array de objetos ligeros:
      - `Id_CatTipoInstCap`: (INT) Llave Primaria. Value del selector.
      - `Nombre`:            (VARCHAR) Texto principal (ej: 'Teórico-Práctico').
   ============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ListarTiposInstruccionActivos`$$
CREATE PROCEDURE `SP_ListarTiposInstruccionActivos`()
BEGIN
    /* ========================================================================================
       BLOQUE ÚNICO: CONSULTA DE SELECCIÓN OPTIMIZADA
       No requiere validaciones de entrada ya que es una consulta de catálogo global.
       ======================================================================================== */
    
    SELECT 
        /* IDENTIFICADOR ÚNICO (PK)
           Este es el valor que se guardará como Foreign Key (Fk_Id_CatTipoInstCap) 
           en la tabla Cat_Temas_Capacitacion. */
        `Id_CatTipoInstCap`, 
        
        /* DESCRIPTOR HUMANO
           El texto principal que el usuario leerá en la lista desplegable. */
        `Nombre`

    FROM 
        `Cat_Tipos_Instruccion_Cap`
    
    /* ----------------------------------------------------------------------------------------
       FILTRO DE SEGURIDAD OPERATIVA (VIGENCIA)
       Ocultamos todo lo que no sea "1" (Activo). 
       Esto asegura que nuevos cursos no se asocien a tipos de instrucción extintos.
       ---------------------------------------------------------------------------------------- */
    WHERE 
        `Activo` = 1
    
    /* ----------------------------------------------------------------------------------------
       OPTIMIZACIÓN DE UX
       Ordenamiento alfabético realizado por el motor de base de datos.
       ---------------------------------------------------------------------------------------- */
    ORDER BY 
        `Nombre` ASC;

END$$

DELIMITER ;

/* ============================================================================================
   SECCIÓN: LISTADOS PARA ADMINISTRACIÓN (GRID / TABLA CRUD)
   ============================================================================================
   Estas rutinas son consumidas exclusivamente por los Paneles de Control del Administrador.
   Su objetivo es dar visibilidad total sobre el catálogo para auditoría, gestión y corrección.
   ============================================================================================ */

/* ============================================================================================
   PROCEDIMIENTO: SP_ListarTiposInstruccionAdmin
   ============================================================================================
   
   1. OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   --------------------------------------
   Proveer el inventario maestro y completo de los "Tipos de Instrucción" (Naturaleza Pedagógica)
   para alimentar el Grid Principal del Módulo de Administración.

   CASOS DE USO:
   - Pantalla de Mantenimiento de Catálogos.
   - Auditoría: Revisar qué tipos han existido históricamente.
   - Gestión de Ciclo de Vida: Reactivar tipos que fueron dados de baja por error.

   2. DIFERENCIA CRÍTICA CON EL LISTADO OPERATIVO (DROPDOWN)
   ---------------------------------------------------------
   A) SP_ListarTiposInstruccionActivos (Dropdown):
      - Enfoque: Operatividad.
      - Filtro: Estricto `WHERE Activo = 1`.
      - Objetivo: Evitar asignar tipos obsoletos a cursos nuevos.

   B) SP_ListarTiposInstruccionAdmin (ESTE):
      - Enfoque: Gestión Total.
      - Filtro: NINGUNO (Visibilidad Total).
      - Objetivo: Permitir ver registros inactivos (`Activo = 0`) para poder editarlos 
        o reactivarlos. Ocultar los inactivos aquí impediría su recuperación.

   3. ARQUITECTURA DE DATOS (VIEW CONSUMPTION PATTERN)
   ---------------------------------------------------
   Este procedimiento implementa el patrón de "Abstracción de Lectura" al consumir la vista
   `Vista_Cat_Tipos_Instruccion_Admin` en lugar de la tabla física.

   Ventajas Técnicas:
   - Desacoplamiento: El Grid del Frontend se acopla a los nombres de columnas estandarizados
     de la Vista (ej: `Estatus_Tipo_Instruccion`) y no a los de la tabla física (`Activo`).
   - Estandarización: La vista ya maneja la proyección de columnas limpias.

   4. ESTRATEGIA DE ORDENAMIENTO (UX PRIORITY)
   -------------------------------------------
   El ordenamiento está diseñado para la eficiencia administrativa:
      1. Prioridad Operativa (Estatus DESC): 
         Los registros VIGENTES (1) aparecen arriba. Los obsoletos (0) se van al fondo.
         Esto mantiene la información relevante accesible inmediatamente.
      2. Orden Alfabético (Nombre ASC): 
         Dentro de cada grupo, se ordenan A-Z para facilitar la búsqueda visual rápida.

   5. DICCIONARIO DE DATOS (OUTPUT)
   --------------------------------
   Retorna el contrato de datos definido en `Vista_Cat_Tipos_Instruccion_Admin`:
      - [Identidad]: Id_Tipo_Instruccion, Nombre_Tipo_Instruccion.
      - [Detalle]: Descripcion_Tipo_Instruccion.
      - [Control]: Estatus_Tipo_Instruccion (1 = Activo, 0 = Inactivo).
   ============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ListarTiposInstruccionAdmin`$$
CREATE PROCEDURE `SP_ListarTiposInstruccion`()
BEGIN
    /* ========================================================================================
       BLOQUE ÚNICO: CONSULTA MAESTRA
       No requiere validaciones de entrada ya que es una consulta global sobre el catálogo.
       ======================================================================================== */
    
    SELECT 
        /* Proyección total de la Vista Maestra */
        * FROM 
        `Vista_Tipos_Instruccion`
    
    /* ========================================================================================
       ORDENAMIENTO ESTRATÉGICO
       Optimizamos la presentación para el usuario administrador.
       ======================================================================================== */
    ORDER BY 
        `Estatus_Tipo_Instruccion` DESC,  -- 1º: Prioridad a los activos (1 antes que 0)
        `Nombre_Tipo_Instruccion` ASC;    -- 2º: Orden alfabético visual

END$$

DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_EditarTipoInstruccion
   ============================================================================================
   
   1. VISIÓN GENERAL Y OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   -------------------------------------------------------
   Este procedimiento gestiona la modificación de los atributos descriptivos de un "Tipo de Instrucción"
   (`Cat_Tipos_Instruccion_Cap`) existente en el catálogo pedagógico.
   
   No es un simple UPDATE; es un motor transaccional diseñado para operar en entornos de alta 
   concurrencia, garantizando las propiedades ACID y evitando la corrupción de datos por duplicidad.

   2. REGLAS DE VALIDACIÓN ESTRICTA (HARD CONSTRAINTS)
   ---------------------------------------------------
   A) OBLIGATORIEDAD DE CAMPOS:
      - Regla: "Todo o Nada". El Nombre es MANDATORIO.
      - Justificación: Un tipo de instrucción sin nombre rompe la integridad visual de los reportes.

   B) UNICIDAD GLOBAL (EXCLUSIÓN PROPIA):
      - Se verifica que el nuevo Nombre no pertenezca a OTRO tipo (`Id <> _Id_Tipo`).
      - Nota: Es perfectamente legal que el registro se llame igual a sí mismo (ej: cambiar solo la descripción).

   3. ARQUITECTURA DE CONCURRENCIA (PESSIMISTIC LOCKING PATTERN)
   -------------------------------------------------------------
   Para prevenir la "Edición Fantasma" (Lost Update) donde dos administradores editan el mismo
   registro al mismo tiempo:
   
      - FASE 1 (Bloqueo): Al inicio de la transacción, ejecutamos `SELECT ... FOR UPDATE` sobre el ID.
      - FASE 2 (Edición): La fila queda "congelada" para nuestra sesión. Nadie más puede escribir en ella.
      - FASE 3 (Liberación): Al hacer COMMIT, se libera el recurso.
   
   4. IDEMPOTENCIA (OPTIMIZACIÓN DE RECURSOS)
   ------------------------------------------
   - Antes de escribir en disco, el SP compara el estado actual (`Snapshot`) contra los nuevos valores.
   - Si son idénticos, retorna éxito ('SIN_CAMBIOS') inmediatamente.
   - Beneficio: Evita escrituras innecesarias en el Transaction Log y mantiene intacta la fecha `updated_at`.

   5. CONTRATO DE SALIDA (OUTPUT CONTRACT)
   ---------------------------------------
   Retorna un resultset con:
      - Mensaje (VARCHAR): Feedback descriptivo.
      - Accion (VARCHAR): 'ACTUALIZADA', 'SIN_CAMBIOS', 'CONFLICTO'.
      - Id_Tipo (INT): Identificador del recurso manipulado.
   ============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_EditarTipoInstruccion`$$

CREATE PROCEDURE `SP_EditarTipoInstruccion`(
    /* -----------------------------------------------------------------
       PARÁMETROS DE ENTRADA (INPUTS)
       Recibimos los datos crudos del formulario de edición.
       ----------------------------------------------------------------- */
    IN _Id_Tipo     INT,           -- OBLIGATORIO: ID del registro a modificar (PK)
    IN _Nombre      VARCHAR(255),  -- OBLIGATORIO: Nuevo Nombre (ej: 'Teórico-Práctico')
    IN _Descripcion VARCHAR(255)   -- OPCIONAL: Descripción detallada
)
THIS_PROC: BEGIN
    
    /* ================================================================================================
       BLOQUE 0: DECLARACIÓN DE VARIABLES DE ESTADO Y CONTEXTO
       Propósito: Inicializar los contenedores que gestionarán la lógica del procedimiento.
       ================================================================================================ */
    
    /* [Snapshots]: Almacenan el estado actual del registro antes de la edición (para comparar cambios) */
    DECLARE v_Nom_Act  VARCHAR(255) DEFAULT NULL;
    DECLARE v_Desc_Act VARCHAR(255) DEFAULT NULL;

    /* [IDs de Conflicto]: Identificadores de filas que podrían chocar con nuestros nuevos datos */
    DECLARE v_Id_Conflicto INT DEFAULT NULL; 

    /* [Bandera de Control]: Semáforo para detectar errores de concurrencia (Error 1062) */
    DECLARE v_Dup TINYINT(1) DEFAULT 0;

    /* ================================================================================================
       BLOQUE 1: HANDLERS (MANEJO ROBUSTO DE EXCEPCIONES)
       Propósito: Garantizar una salida limpia ante errores técnicos o de concurrencia.
       ================================================================================================ */
    
    /* 1.1 HANDLER DE DUPLICIDAD (Error 1062)
       Objetivo: Capturar colisiones de Unique Key en el último milisegundo (Race Condition).
       Acción: No abortamos. Encendemos la bandera v_Dup = 1 para manejar el conflicto controladamente. */
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
       Eliminamos espacios basura. Si queda vacío, se convierte a NULL. */
    SET _Nombre      = NULLIF(TRIM(_Nombre), '');
    SET _Descripcion = NULLIF(TRIM(_Descripcion), '');

    /* 2.2 VALIDACIÓN DE OBLIGATORIEDAD
       El formulario exige que los campos críticos existan. */
    
    IF _Id_Tipo IS NULL OR _Id_Tipo <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: Identificador de Tipo inválido.';
    END IF;

    IF _Nombre IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN [400]: El NOMBRE es obligatorio para la edición.';
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
    
    SELECT `Nombre`, `Descripcion` 
    INTO v_Nom_Act, v_Desc_Act
    FROM `Cat_Tipos_Instruccion_Cap` 
    WHERE `Id_CatTipoInstCap` = _Id_Tipo
    FOR UPDATE; -- <--- BLOQUEO DE ESCRITURA AQUÍ

    /* Safety Check: Si al bloquear descubrimos que el registro fue borrado por otro usuario */
    IF v_Nom_Act IS NULL THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR CRÍTICO [410]: El registro desapareció durante la transacción (fue eliminado externamente).';
    END IF;

    /* ------------------------------------------------------------------------------------------------
       PASO 3.2: DETECCIÓN DE IDEMPOTENCIA (SIN CAMBIOS)
       
       Objetivo: Evitar escrituras si el usuario guardó lo mismo.
       Lógica: Comparamos si los datos nuevos son matemáticamente iguales a los actuales. 
       Usamos <=> (Null-Safe Equality) para manejar correctamente los NULLs en la descripción.
       ------------------------------------------------------------------------------------------------ */
    IF (_Nombre = v_Nom_Act) 
       AND (_Descripcion <=> v_Desc_Act) THEN
        
        COMMIT; -- Liberamos locks inmediatamente
        
        /* Retorno anticipado para ahorrar I/O y notificar al Frontend */
        SELECT 'AVISO: No se detectaron cambios en la información.' AS Mensaje, 'SIN_CAMBIOS' AS Accion, _Id_Tipo AS Id_Tipo;
        LEAVE THIS_PROC;
    END IF;

    /* ------------------------------------------------------------------------------------------------
       PASO 3.3: VALIDACIÓN FINAL DE UNICIDAD (PRE-UPDATE CHECK)
       
       Objetivo: Verificar si existen duplicados REALES en OTROS registros.
       Regla: `Id <> _Id_Tipo` (Excluirme a mí mismo).
       ------------------------------------------------------------------------------------------------ */
    
    /* Validación por NOMBRE */
    SET v_Id_Conflicto = NULL;
    
    SELECT `Id_CatTipoInstCap` INTO v_Id_Conflicto 
    FROM `Cat_Tipos_Instruccion_Cap` 
    WHERE `Nombre` = _Nombre 
      AND `Id_CatTipoInstCap` <> _Id_Tipo 
    LIMIT 1
    FOR UPDATE; -- Bloqueamos también al posible conflicto para evitar carreras
    
    IF v_Id_Conflicto IS NOT NULL THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'CONFLICTO DE DATOS [409]: El NOMBRE ingresado ya pertenece a otro Tipo de Instrucción.';
    END IF;

    /* ================================================================================================
       BLOQUE 5: PERSISTENCIA Y FINALIZACIÓN (UPDATE)
       Propósito: Aplicar los cambios una vez superadas todas las barreras de seguridad.
       ================================================================================================ */
    
    SET v_Dup = 0; -- Resetear bandera de error antes de escribir

    UPDATE `Cat_Tipos_Instruccion_Cap`
    SET `Nombre`      = _Nombre,
        `Descripcion` = _Descripcion,
        `updated_at`  = NOW() -- Auditoría automática
    WHERE `Id_CatTipoInstCap` = _Id_Tipo;

    /* ================================================================================================
       BLOQUE 6: MANEJO DE COLISIÓN TARDÍA (RECUPERACIÓN DE ERROR 1062)
       Propósito: Gestionar el caso extremo donde un insert fantasma ocurre justo antes del update.
       ================================================================================================ */
    IF v_Dup = 1 THEN
        ROLLBACK;
        
        /* Diagnóstico para el usuario */
        SET v_Id_Conflicto = NULL;

        SELECT `Id_CatTipoInstCap` INTO v_Id_Conflicto 
        FROM `Cat_Tipos_Instruccion_Cap` 
        WHERE `Nombre` = _Nombre 
          AND `Id_CatTipoInstCap` <> _Id_Tipo 
        LIMIT 1;

        SELECT 'Error de Concurrencia: Conflicto detectado al guardar.' AS Mensaje, 
               'CONFLICTO' AS Accion, 
               'NOMBRE' AS Campo, 
               v_Id_Conflicto AS Id_Conflicto;
        LEAVE THIS_PROC;
    END IF;

    /* ================================================================================================
       BLOQUE 7: CONFIRMACIÓN EXITOSA
       Propósito: Confirmar la transacción y notificar al cliente.
       ================================================================================================ */
    COMMIT;
    
    SELECT 'ÉXITO: Tipo de Instrucción actualizado correctamente.' AS Mensaje, 
           'ACTUALIZADA' AS Accion, 
           _Id_Tipo AS Id_Tipo;

END$$

DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_CambiarEstatusTipoInstruccion
   ============================================================================================
   
   1. OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   --------------------------------------
   Gestionar el Ciclo de Vida (Lifecycle) de un "Tipo de Instrucción" (ej: Teórico, Práctico)
   mediante el mecanismo de "Baja Lógica" (Soft Delete).
   
   Permite al administrador:
   A) DESACTIVAR (0): Ocultar el tipo de los selectores de "Nuevo Curso", volviéndolo obsoleto.
   B) REACTIVAR (1): Recuperar un tipo histórico para su reutilización.

   2. REGLA DE INTEGRIDAD CRÍTICA (EL CANDADO DESCENDENTE)
   -------------------------------------------------------
   "No puedes eliminar la categoría si existen productos clasificados en ella".
   
   - Validación: Si se intenta DESACTIVAR (`_Nuevo_Estatus = 0`), el sistema consulta la tabla
     `Cat_Temas_Capacitacion` (Cursos).
   - Condición de Bloqueo: Si existe AL MENOS UN curso activo (`Activo = 1`) que use este tipo,
     la operación se bloquea inmediatamente.
   - Justificación: Si permitiéramos esto, tendríamos cursos "huérfanos" en el sistema que no
     se podrían editar o clasificar correctamente, rompiendo los reportes por tipo.

   3. ESTRATEGIA DE CONCURRENCIA (BLOQUEO PESIMISTA)
   -------------------------------------------------
   - Problema: ¿Qué pasa si un Admin A desactiva el tipo "Teórico" justo en el milisegundo en que
     un Admin B está creando el curso "Seguridad Básica (Teórico)"?
   - Solución: `SELECT ... FOR UPDATE`.
   - Efecto: Congelamos el registro del Tipo. Cualquier otra transacción deberá esperar.

   4. IDEMPOTENCIA (OPTIMIZACIÓN)
   ------------------------------
   - Si el registro ya tiene el estatus solicitado, retornamos éxito inmediato sin tocar el disco.
   - Esto evita actualizaciones fantasmas en la columna `updated_at`.

   5. CONTRATO DE SALIDA
   ---------------------
   Retorna:
      - Mensaje: Feedback claro.
      - Accion: 'ESTATUS_CAMBIADO', 'SIN_CAMBIOS'.
      - Nuevo_Estatus: El valor final en BD.
   ============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_CambiarEstatusTipoInstruccion`$$

CREATE PROCEDURE `SP_CambiarEstatusTipoInstruccion`(
    IN _Id_Tipo        INT,       -- ID del registro a modificar (PK)
    IN _Nuevo_Estatus  TINYINT    -- 1 = Activar, 0 = Desactivar
)
THIS_PROC: BEGIN
    /* ========================================================================================
       BLOQUE 0: VARIABLES DE ESTADO
       ======================================================================================== */
    DECLARE v_Estatus_Actual TINYINT DEFAULT NULL;
    DECLARE v_Nombre_Actual  VARCHAR(255) DEFAULT NULL;
    
    /* Variable para contar hijos activos (Dependencias) */
    DECLARE v_Dependencias   INT DEFAULT 0;

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
    IF _Id_Tipo IS NULL OR _Id_Tipo <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: ID inválido.';
    END IF;

    IF _Nuevo_Estatus NOT IN (0, 1) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: El estatus solo puede ser 0 o 1.';
    END IF;

    /* ========================================================================================
       BLOQUE 3: INICIO DE TRANSACCIÓN Y BLOQUEO
       ======================================================================================== */
    START TRANSACTION;

    /* ----------------------------------------------------------------------------------------
       PASO 3.1: LEER Y BLOQUEAR EL REGISTRO
       ----------------------------------------------------------------------------------------
       Adquirimos un "Write Lock" sobre la fila. Esto asegura serialización. */
    
    SELECT `Activo`, `Nombre` 
    INTO v_Estatus_Actual, v_Nombre_Actual
    FROM `Cat_Tipos_Instruccion_Cap`
    WHERE `Id_CatTipoInstCap` = _Id_Tipo
    FOR UPDATE;

    /* Si no se encuentra, abortamos */
    IF v_Estatus_Actual IS NULL THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [404]: El Tipo de Instrucción no existe.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 3.2: IDEMPOTENCIA (SIN CAMBIOS)
       ---------------------------------------------------------------------------------------- */
    IF v_Estatus_Actual = _Nuevo_Estatus THEN
        COMMIT;
        SELECT CONCAT('AVISO: El Tipo "', v_Nombre_Actual, '" ya se encuentra en el estado solicitado.') AS Mensaje,
               'SIN_CAMBIOS' AS Accion,
               _Nuevo_Estatus AS Nuevo_Estatus;
        
        /* CORRECCIÓN APLICADA: Se usa LEAVE con la etiqueta del bloque principal */
        LEAVE THIS_PROC; 
    END IF;

    /* ========================================================================================
       BLOQUE 4: REGLAS DE NEGOCIO (CANDADOS DE INTEGRIDAD)
       ======================================================================================== */

    /* ----------------------------------------------------------------------------------------
       PASO 4.1: VALIDACIÓN DE DEPENDENCIAS (SOLO AL DESACTIVAR)
       ---------------------------------------------------------------------------------------- */
    IF _Nuevo_Estatus = 0 THEN
        
        /* Buscamos si existen Temas (Cursos) activos que dependan de este Tipo.
           Solo nos importan los cursos con `Activo = 1`. 
           Si hay cursos históricos (borrados), no bloqueamos la operación. */
        
        SELECT COUNT(*) INTO v_Dependencias
        FROM `Cat_Temas_Capacitacion`
        WHERE `Fk_Id_CatTipoInstCap` = _Id_Tipo
          AND `Activo` = 1; 

        /* Si encontramos al menos uno, BLOQUEAMOS */
        IF v_Dependencias > 0 THEN
            ROLLBACK;
            SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'BLOQUEO DE INTEGRIDAD [409]: No se puede desactivar este Tipo de Instrucción porque existen CURSOS ACTIVOS asociados a él. Primero reasigne o desactive esos cursos.';
        END IF;

    END IF;

    /* ========================================================================================
       BLOQUE 5: PERSISTENCIA (UPDATE)
       ======================================================================================== */
    
    UPDATE `Cat_Tipos_Instruccion_Cap`
    SET 
        `Activo` = _Nuevo_Estatus,
        `updated_at` = NOW() -- Auditoría temporal
    WHERE `Id_CatTipoInstCap` = _Id_Tipo;

    /* ========================================================================================
       BLOQUE 6: CONFIRMACIÓN Y RESPUESTA
       ======================================================================================== */
    COMMIT;

    SELECT 
        CASE 
            WHEN _Nuevo_Estatus = 1 THEN CONCAT('ÉXITO: El Tipo "', v_Nombre_Actual, '" ha sido REACTIVADO.')
            ELSE CONCAT('ÉXITO: El Tipo "', v_Nombre_Actual, '" ha sido DESACTIVADO.')
        END AS Mensaje,
        'ESTATUS_CAMBIADO' AS Accion,
        _Nuevo_Estatus AS Nuevo_Estatus;

END$$ -- Fin del bloque etiquetado

DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_EliminarTipoInstruccionFisico
   ============================================================================================
   
   1. OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   --------------------------------------
   Ejecutar la eliminación DEFINITIVA, FÍSICA e IRREVERSIBLE de un registro en el catálogo
   de "Tipos de Instrucción" (`Cat_Tipos_Instruccion_Cap`).

   CONTEXTO DE USO Y ADVERTENCIAS:
   - Naturaleza: Operación Destructiva (`DELETE`).
   - Caso de Uso Permitido: Únicamente para tareas de depuración administrativa inmediata
     (ej: "Acabo de crear por error el tipo 'TallerX' y quiero borrarlo ya").
   - Restricción: NO debe usarse para la gestión operativa histórica. Si un tipo dejó de
     usarse, se debe usar el procedimiento de Baja Lógica (`SP_CambiarEstatusTipoInstruccion`)
     para no romper la clasificación de los cursos antiguos.

   2. ESTRATEGIA DE INTEGRIDAD REFERENCIAL (DEFENSA EN CAPAS)
   ----------------------------------------------------------
   Para garantizar que la base de datos nunca quede con "Cursos Huérfanos" (temas apuntando
   a un tipo que ya no existe), implementamos dos niveles de seguridad:

   CAPA A: VALIDACIÓN DE NEGOCIO PROACTIVA (Logic Guard)
   - Antes de intentar borrar, el SP escanea explícitamente la tabla hija `Cat_Temas_Capacitacion`.
   - Criterio Estricto: Si existe CUALQUIER historial (sea un curso activo o uno dado de baja),
     la operación se aborta.
   - Beneficio: Permite devolver un mensaje de error semántico ("No se puede borrar porque hay
     temas asociados") en lugar de un error técnico de SQL.

   CAPA B: VALIDACIÓN DE MOTOR REACTIVA (Database Constraint - Safety Net)
   - Si existiera una tabla oculta o futura que olvidamos validar manualmente, el motor InnoDB
     bloqueará el `DELETE` disparando el error `1451` (Foreign Key Constraint Fails).
   - El SP captura este error mediante un `HANDLER`, hace Rollback seguro y entrega un mensaje controlado.

   3. ATOMICIDAD Y CONCURRENCIA
   ----------------------------
   - La operación se envuelve en una transacción.
   - El motor aplica un bloqueo exclusivo (X-Lock) sobre la fila durante el borrado, asegurando
     que nadie más pueda leer o vincular este tipo mientras se destruye.

   4. CONTRATO DE SALIDA (OUTPUT)
   ------------------------------
   Retorna un dataset informativo:
      - Mensaje: Confirmación de éxito.
      - Accion: 'ELIMINADA'.
      - Id_Tipo: El ID del recurso purgado.
   ============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_EliminarTipoInstruccionFisico`$$

CREATE PROCEDURE `SP_EliminarTipoInstruccionFisico`(
    /* -----------------------------------------------------------------
       PARÁMETROS DE ENTRADA
       ----------------------------------------------------------------- */
    IN _Id_Tipo INT -- Identificador único del registro a destruir (PK)
)
THIS_PROC: BEGIN
    
    /* ========================================================================================
       BLOQUE 0: VARIABLES DE DIAGNÓSTICO
       ======================================================================================== */
    /* Variable para almacenar el resultado de la búsqueda de dependencias */
    DECLARE v_Dependencias INT DEFAULT NULL;

    /* ========================================================================================
       BLOQUE 1: HANDLERS (MANEJO ROBUSTO DE EXCEPCIONES)
       ======================================================================================== */
    
    /* 1.1 HANDLER DE INTEGRIDAD REFERENCIAL (Error 1451)
       Objetivo: Actuar como "paracaídas" final.
       Escenario: Intentamos borrar, pero el motor de BD detecta una FK activa apuntando a este registro.
       Acción: Revertir todo y avisar al usuario. */
    DECLARE EXIT HANDLER FOR 1451 
    BEGIN 
        ROLLBACK; 
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'BLOQUEO DE INTEGRIDAD (SISTEMA) [1451]: El registro está blindado por la base de datos porque existen referencias en otras tablas no depuradas.'; 
    END;

    /* 1.2 HANDLER GENÉRICO (SQLEXCEPTION)
       Objetivo: Capturar fallos de infraestructura. */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; 
    END;

    /* ========================================================================================
       BLOQUE 2: VALIDACIONES PREVIAS (FAIL FAST)
       ======================================================================================== */
    
    /* 2.1 Validación de Input */
    IF _Id_Tipo IS NULL OR _Id_Tipo <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: Identificador inválido.';
    END IF;

    /* 2.2 Validación de Existencia
       Verificamos si el registro existe antes de verificar dependencias. */
    IF NOT EXISTS (SELECT 1 FROM `Cat_Tipos_Instruccion_Cap` WHERE `Id_CatTipoInstCap` = _Id_Tipo) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [404]: El Tipo de Instrucción que intenta eliminar no existe.';
    END IF;

    /* ========================================================================================
       BLOQUE 3: CANDADO DE NEGOCIO (VALIDACIÓN PROACTIVA DE DEPENDENCIAS)
       ======================================================================================== */
    
    /* OBJETIVO: Proteger el Historial Académico.
       Buscamos en la tabla `Cat_Temas_Capacitacion`.
       CRÍTICO: NO filtramos por `Activo = 1`. 
       Razón: Si un curso "Excel 97" usaba este tipo y hoy está dado de baja, 
       ese historial sigue existiendo. Borrar el tipo rompería la integridad de ese registro. */
    
    SELECT 1 INTO v_Dependencias
    FROM `Cat_Temas_Capacitacion`
    WHERE `Fk_Id_CatTipoInstCap` = _Id_Tipo
    LIMIT 1;

    /* SI ENCONTRAMOS AL MENOS UN REGISTRO ASOCIADO... */
    IF v_Dependencias IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'BLOQUEO DE NEGOCIO [409]: No es posible eliminar este Tipo porque existen TEMAS DE CAPACITACIÓN (Activos o Históricos) asociados a él. La eliminación física rompería el catálogo de cursos. Utilice la opción "Desactivar" en su lugar.';
    END IF;

    /* ========================================================================================
       BLOQUE 4: EJECUCIÓN DESTRUCTIVA (ZONA CRÍTICA)
       ======================================================================================== */
    START TRANSACTION;

    /* Ejecución del Borrado Físico.
       En este punto, el motor adquiere un bloqueo exclusivo sobre la fila. */
    DELETE FROM `Cat_Tipos_Instruccion_Cap` 
    WHERE `Id_CatTipoInstCap` = _Id_Tipo;

    /* Si llegamos aquí sin que salten los Handlers,
       significa que el registro estaba limpio y fue destruido correctamente. */
    COMMIT;

    /* ========================================================================================
       BLOQUE 5: CONFIRMACIÓN
       ======================================================================================== */
    SELECT 
        'Registro eliminado permanentemente de la base de datos.' AS Mensaje, 
        'ELIMINADA' AS Accion,
        _Id_Tipo AS Id_Tipo_Instruccion;

END$$

DELIMITER ;