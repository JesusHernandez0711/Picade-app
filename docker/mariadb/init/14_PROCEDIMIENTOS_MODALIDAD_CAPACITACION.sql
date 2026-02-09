USE `PICADE`;

/* ------------------------------------------------------------------------------------------------------ */
/* CREACION DE VISTAS Y PROCEDIMIENTOS DE ALMACENADO PARA LA BASE DE DATOS                                */
/* ------------------------------------------------------------------------------------------------------ */

/* ======================================================================================================
   VIEW: Vista_Modalidad_Capacitacion
   ======================================================================================================
   
   1. OBJETIVO TÉCNICO Y DE NEGOCIO (BUSINESS GOAL)
   ------------------------------------------------
   Esta vista constituye la **Interfaz Canónica de Administración** para el catálogo de "Modalidades de 
   Capacitación" (El "CÓMO" se imparte el curso: Presencial, Remoto, Híbrido).

   Su función principal es desacoplar la estructura física de la tabla `Cat_Modalidad_Capacitacion` 
   de la capa de presentación, proporcionando un punto de acceso único y estandarizado para:
   - El Grid de Mantenimiento (CRUD).
   - Los selectores en la creación de cursos (`DatosCapacitaciones`).
   - Los reportes estadísticos de distribución de carga (ej: % de cursos virtuales vs presenciales).

   2. ARQUITECTURA DE DATOS (PATRÓN DE PROYECCIÓN)
   -----------------------------------------------
   Al ser una Entidad Raíz (Root Entity) sin dependencias foráneas complejas, esta vista se enfoca en la 
   **Normalización Semántica** y la **Claridad de Contrato de Datos**:

   - Abstracción de Identificadores (Aliasing): Se transforma `Id_CatModalCap` a `Id_Modalidad`.
     Esto facilita la lectura del JSON en el Frontend (ej: `response.data.id_modalidad`).
   
   - Estandarización de Atributos: Se renombran columnas genéricas como `Codigo` y `Nombre` a 
     `Codigo_Modalidad` y `Nombre_Modalidad` para evitar ambigüedades en consultas cruzadas futuras.

   3. GESTIÓN DE INTEGRIDAD Y NULOS
   --------------------------------
   - Campo `Codigo`: La tabla permite valores NULL (para datos históricos o informales). La vista expone 
     el dato crudo (`RAW`). Es responsabilidad del consumidor (Frontend) decidir si renderiza un valor 
     por defecto o deja la celda vacía.
   
   - Campo `Descripcion`: Se expone para brindar contexto operativo (ej: definir qué implica "Híbrido").

   4. VISIBILIDAD DE ESTATUS (AUDITORÍA TOTAL)
   -------------------------------------------
   - La vista proyecta **TODO el universo de datos** (Activos e Inactivos/Borrados Lógicamente).
   - Razón: En los paneles de administración, es vital ver modalidades obsoletas (ej: "A Distancia por Radio") 
     que ya no se usan pero que existen en el historial de cursos antiguos. Ocultarlas rompería la 
     integridad visual de los reportes históricos.
   - El filtrado para listas desplegables operativas ("Crear Nuevo Curso") se delega a los SPs específicos 
     que filtren por `Activo = 1`.

   5. DICCIONARIO DE DATOS (CONTRATO DE SALIDA)
   --------------------------------------------
   [Bloque 1: Identidad]
   - Id_Modalidad:          (INT) Llave Primaria única.
   - Codigo_Modalidad:      (VARCHAR) Clave corta interna (ej: 'PRES', 'VIRT'). Puede ser NULL.
   - Nombre_Modalidad:      (VARCHAR) Denominación oficial (ej: 'PRESENCIAL').

   [Bloque 2: Contexto Operativo]
   - Descripcion_Modalidad: (VARCHAR) Explicación del alcance logístico de la modalidad.

   [Bloque 3: Control de Ciclo de Vida]
   - Estatus_Modalidad:     (TINYINT) Semáforo: 1 = Disponible/Activo, 0 = Descontinuado/Inactivo.

   [Bloque 4: Trazabilidad]
   - (Opcional) Fechas de creación y actualización para auditoría.
   ====================================================================================================== */

CREATE OR REPLACE 
    ALGORITHM = UNDEFINED 
    SQL SECURITY DEFINER
VIEW `PICADE`.`Vista_Modalidad_Capacitacion` AS
    SELECT 
        /* -----------------------------------------------------------------------------------
           BLOQUE 1: IDENTIDAD Y CLAVES
           Estandarización de nombres para consumo agnóstico (API/Frontend/Reportes).
           ----------------------------------------------------------------------------------- */
        `Mod`.`Id_CatModalCap`           AS `Id_Modalidad`,
        `Mod`.`Codigo`                   AS `Codigo_Modalidad`,
        `Mod`.`Nombre`                   AS `Nombre_Modalidad`,

        /* -----------------------------------------------------------------------------------
           BLOQUE 2: DETALLES INFORMATIVOS
           Información contextual para tooltips o documentación de usuario.
           ----------------------------------------------------------------------------------- */
        `Mod`.`Descripcion`              AS `Descripcion_Modalidad`,

        /* -----------------------------------------------------------------------------------
           BLOQUE 3: METADATOS DE CONTROL (ESTATUS)
           Mapeo semántico: 'Activo' -> 'Estatus_Modalidad'.
           Permite diferenciar visualmente en el Grid (ej: Badge Verde vs Gris).
           ----------------------------------------------------------------------------------- */
        `Mod`.`Activo`                   AS `Estatus_Modalidad`
        
        /* -----------------------------------------------------------------------------------
           BLOQUE 4: TRAZABILIDAD (AUDITORÍA)
           Datos temporales para ordenamiento cronológico en paneles administrativos.
           (Comentados por defecto para mantener la vista ligera, descomentar si se requiere).
           ----------------------------------------------------------------------------------- */
        -- , `Mod`.`created_at`          AS `Fecha_Registro`
        -- , `Mod`.`updated_at`          AS `Ultima_Modificacion`

    FROM 
        `PICADE`.`Cat_Modalidad_Capacitacion` `Mod`;

/* --- VERIFICACIÓN DE LA VISTA (QA RÁPIDO) --- */
-- SELECT * FROM Picade.Vista_Modalidad_Capacitacion;

/* ====================================================================================================
   PROCEDIMIENTO: SP_RegistrarModalidadCapacitacion
   ====================================================================================================
   
   1. VISIÓN GENERAL Y OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   ----------------------------------------------------------------------------------------------------
   Este procedimiento gestiona el ALTA TRANSACCIONAL de una "Modalidad de Capacitación" en el catálogo
   maestro (`Cat_Modalidad_Capacitacion`).
   
   Su propósito es clasificar la logística de impartición de los cursos (ej: Presencial, Virtual, Híbrido,
   Asincrónico). Actúa como la **Puerta de Entrada Única** (Single Gateway) para garantizar que no 
   existan modalidades duplicadas, ambiguas o con datos corruptos que afecten la programación de cursos.

   2. REGLAS DE VALIDACIÓN ESTRICTA (HARD CONSTRAINTS)
   ---------------------------------------------------
   A) INTEGRIDAD DE DATOS (DATA HYGIENE):
      - Principio: "Datos limpios desde el origen".
      - Regla: El `Código` y el `Nombre` son obligatorios. No se permiten cadenas vacías o espacios.
      - Acción: Se aplica `TRIM` y validación `NOT NULL` antes de cualquier operación.

   B) IDENTIDAD UNÍVOCA DE DOBLE FACTOR (DUAL IDENTITY CHECK):
      - Unicidad por CÓDIGO: No pueden existir dos modalidades con la clave 'VIRT'.
      - Unicidad por NOMBRE: No pueden existir dos modalidades llamadas 'VIRTUAL REMOTO'.
      - Resolución: Se verifica primero el Código (Identificador fuerte) y luego el Nombre.

   3. ESTRATEGIA DE PERSISTENCIA Y CONCURRENCIA (ACID & RACE CONDITIONS)
   ----------------------------------------------------------------------------------------------------
   A) BLOQUEO PESIMISTA (PESSIMISTIC LOCKING):
      - Se utiliza `SELECT ... FOR UPDATE` durante las verificaciones de existencia.
      - Justificación: Esto "serializa" las peticiones. Si dos administradores intentan crear la modalidad
        "Híbrido" al mismo tiempo, el segundo esperará a que el primero termine, evitando lecturas sucias.

   B) AUTOSANACIÓN (SELF-HEALING / SOFT DELETE RECOVERY):
      - Escenario: La modalidad "Presencial" existía, se dio de baja (`Activo=0`) y ahora se quiere volver a usar.
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
      - [Mensaje]: Feedback descriptivo (ej: "Modalidad registrada exitosamente").
      - [Id_Modalidad]: La llave primaria del recurso.
      - [Accion]: Enumerador de estado ('CREADA', 'REACTIVADA', 'REUSADA').
   ==================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_RegistrarModalidadCapacitacion`$$

CREATE PROCEDURE `SP_RegistrarModalidadCapacitacion`(
    /* -----------------------------------------------------------------
       PARÁMETROS DE ENTRADA (INPUT LAYER)
       Recibimos los datos crudos del formulario.
       ----------------------------------------------------------------- */
    IN _Codigo      VARCHAR(50),   -- [OBLIGATORIO] Identificador corto (ej: 'VIRT').
    IN _Nombre      VARCHAR(255),  -- [OBLIGATORIO] Nombre descriptivo (ej: 'VIRTUAL').
    IN _Descripcion VARCHAR(255)   -- [OPCIONAL] Detalles operativos (ej: 'Vía Teams/Zoom').
)
THIS_PROC: BEGIN
    
    /* ========================================================================================
       BLOQUE 0: DECLARACIÓN DE VARIABLES DE ENTORNO
       Propósito: Inicializar contenedores para el estado de la base de datos.
       ======================================================================================== */
    
    /* Variables de Persistencia (Snapshot): Almacenan la "foto" del registro si ya existe */
    DECLARE v_Id_Modalidad INT DEFAULT NULL;
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
       ======================================================================================== */
    
    /* 2.1 LIMPIEZA DE DATOS (TRIM & NULLIF)
       Eliminamos espacios al inicio/final. Si la cadena queda vacía, la convertimos a NULL
       para facilitar la validación booleana estricta. */
    SET _Codigo      = NULLIF(TRIM(_Codigo), '');
    SET _Nombre      = NULLIF(TRIM(_Nombre), '');
    SET _Descripcion = NULLIF(TRIM(_Descripcion), '');

    /* 2.2 VALIDACIÓN DE OBLIGATORIEDAD (Business Rule: NO VACÍOS)
       Regla: Una Modalidad sin Código o Nombre es una entidad corrupta inutilizable. */
    
    IF _Codigo IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN [400]: El CÓDIGO de la Modalidad es obligatorio.';
    END IF;

    IF _Nombre IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN [400]: El NOMBRE de la Modalidad es obligatorio.';
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
    SET v_Id_Modalidad = NULL; -- Reset de seguridad

    SELECT `Id_CatModalCap`, `Nombre`, `Activo` 
    INTO v_Id_Modalidad, v_Nombre_Existente, v_Activo
    FROM `Cat_Modalidad_Capacitacion`
    WHERE `Codigo` = _Codigo
    LIMIT 1
    FOR UPDATE; -- <--- BLOQUEO DE ESCRITURA AQUÍ

    /* ESCENARIO A: EL CÓDIGO YA EXISTE */
    IF v_Id_Modalidad IS NOT NULL THEN
        
        /* A.1 Validación de Integridad Cruzada:
           Regla: Si el código existe, el Nombre TAMBIÉN debe coincidir.
           Fallo: Si el código es igual pero el nombre es diferente, es un CONFLICTO DE DATOS. */
        IF v_Nombre_Existente <> _Nombre THEN
            SIGNAL SQLSTATE '45000' 
                SET MESSAGE_TEXT = 'CONFLICTO DE DATOS [409]: El CÓDIGO ingresado ya existe pero pertenece a una Modalidad con diferente NOMBRE. Verifique sus datos.';
        END IF;

        /* A.2 Sub-Escenario: Existe pero está INACTIVO (Baja Lógica) -> REACTIVAR (Autosanación)
           "Resucitamos" el registro y actualizamos su descripción si se proveyó una nueva. */
        IF v_Activo = 0 THEN
            UPDATE `Cat_Modalidad_Capacitacion` 
            SET `Activo` = 1, 
                /* Lógica de Fusión: Si el usuario mandó descripción nueva, la usamos. 
                   Si no, mantenemos la histórica (COALESCE). */
                `Descripcion` = COALESCE(_Descripcion, `Descripcion`), 
                `updated_at` = NOW() 
            WHERE `Id_CatModalCap` = v_Id_Modalidad;
            
            COMMIT; 
            SELECT 'ÉXITO: Modalidad reactivada y actualizada correctamente.' AS Mensaje, v_Id_Modalidad AS Id_Modalidad, 'REACTIVADA' AS Accion; 
            LEAVE THIS_PROC;
        
        /* A.3 Sub-Escenario: Existe y está ACTIVO -> IDEMPOTENCIA
           El registro ya está tal como lo queremos. No hacemos nada y reportamos éxito. */
        ELSE
            COMMIT; 
            SELECT 'AVISO: La Modalidad ya se encuentra registrada y activa.' AS Mensaje, v_Id_Modalidad AS Id_Modalidad, 'REUSADA' AS Accion; 
            LEAVE THIS_PROC;
        END IF;
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 3.2: RESOLUCIÓN DE IDENTIDAD POR NOMBRE (PRIORIDAD SECUNDARIA)
       
       Objetivo: Si llegamos aquí, el CÓDIGO es libre. Ahora verificamos si el NOMBRE ya está en uso.
       Esto previene que se creen duplicados semánticos con códigos diferentes (ej: 'VIRTUAL' vs 'VIRTUAL-1').
       ---------------------------------------------------------------------------------------- */
    SET v_Id_Modalidad = NULL; -- Reset de seguridad

    SELECT `Id_CatModalCap`, `Codigo`, `Activo`
    INTO v_Id_Modalidad, v_Codigo_Existente, v_Activo
    FROM `Cat_Modalidad_Capacitacion`
    WHERE `Nombre` = _Nombre
    LIMIT 1
    FOR UPDATE;

    /* ESCENARIO B: EL NOMBRE YA EXISTE */
    IF v_Id_Modalidad IS NOT NULL THEN
        
        /* B.1 Conflicto de Identidad:
           El nombre existe, pero tiene asociado OTRO código diferente al que intentamos registrar. */
        IF v_Codigo_Existente IS NOT NULL AND v_Codigo_Existente <> _Codigo THEN
             SIGNAL SQLSTATE '45000' 
             SET MESSAGE_TEXT = 'CONFLICTO DE DATOS [409]: El NOMBRE ingresado ya existe pero está asociado a otro CÓDIGO diferente.';
        END IF;
        
        /* B.2 Caso Especial: Enriquecimiento de Datos (Data Enrichment)
           El registro existía con Código NULL (dato viejo), y ahora le estamos asignando un Código válido. */
        IF v_Codigo_Existente IS NULL THEN
             UPDATE `Cat_Modalidad_Capacitacion` 
             SET `Codigo` = _Codigo, `updated_at` = NOW() 
             WHERE `Id_CatModalCap` = v_Id_Modalidad;
        END IF;

        /* B.3 Reactivación si estaba inactivo */
        IF v_Activo = 0 THEN
            UPDATE `Cat_Modalidad_Capacitacion` 
            SET `Activo` = 1, `Descripcion` = COALESCE(_Descripcion, `Descripcion`), `updated_at` = NOW() 
            WHERE `Id_CatModalCap` = v_Id_Modalidad;
            
            COMMIT; 
            SELECT 'ÉXITO: Modalidad reactivada correctamente (encontrada por Nombre).' AS Mensaje, v_Id_Modalidad AS Id_Modalidad, 'REACTIVADA' AS Accion; 
            LEAVE THIS_PROC;
        END IF;

        /* B.4 Idempotencia: Ya existe y está activo */
        COMMIT; 
        SELECT 'AVISO: La Modalidad ya existe (validada por Nombre).' AS Mensaje, v_Id_Modalidad AS Id_Modalidad, 'REUSADA' AS Accion; 
        LEAVE THIS_PROC;
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 3.3: PERSISTENCIA (INSERCIÓN FÍSICA)
       
       Si pasamos todas las validaciones y no encontramos coincidencias, es un registro NUEVO.
       Aquí existe un riesgo infinitesimal de "Race Condition" si otro usuario inserta 
       exactamente los mismos datos en este preciso instante (cubierto por Handler 1062).
       ---------------------------------------------------------------------------------------- */
    SET v_Dup = 0; -- Reiniciamos bandera de error
    
    INSERT INTO `Cat_Modalidad_Capacitacion`
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
        SELECT 'ÉXITO: Modalidad registrada correctamente.' AS Mensaje, LAST_INSERT_ID() AS Id_Modalidad, 'CREADA' AS Accion; 
        LEAVE THIS_PROC;
    END IF;

    /* ========================================================================================
       BLOQUE 4: RUTINA DE RECUPERACIÓN DE CONCURRENCIA (RE-RESOLVE PATTERN)
       Propósito: Manejar elegantemente el Error 1062 (Duplicate Key) si ocurre una colisión.
       ======================================================================================== */
    
    /* Si estamos aquí, v_Dup = 1. Significa que "perdimos" la carrera contra otro INSERT. */
    
    ROLLBACK; -- 1. Revertir la transacción fallida para liberar bloqueos parciales.
    
    START TRANSACTION; -- 2. Iniciar una nueva transacción limpia.
    
    SET v_Id_Modalidad = NULL;
    
    /* 3. Buscar el registro "ganador" (El que insertó el otro usuario).
       Intentamos recuperar por CÓDIGO (la restricción más fuerte). */
    SELECT `Id_CatModalCap`, `Activo`, `Nombre`
    INTO v_Id_Modalidad, v_Activo, v_Nombre_Existente
    FROM `Cat_Modalidad_Capacitacion`
    WHERE `Codigo` = _Codigo
    LIMIT 1
    FOR UPDATE;
    
    IF v_Id_Modalidad IS NOT NULL THEN
        /* Validación de Seguridad: Confirmar que no sea un falso positivo (nombre distinto) */
        IF v_Nombre_Existente <> _Nombre THEN
             SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR CRÍTICO DE SISTEMA [500]: Concurrencia detectada con conflicto de datos (Códigos iguales, Nombres distintos).';
        END IF;

        /* Reactivación (si el ganador estaba inactivo) */
        IF v_Activo = 0 THEN
            UPDATE `Cat_Modalidad_Capacitacion` 
            SET `Activo` = 1, `Descripcion` = COALESCE(_Descripcion, `Descripcion`), `updated_at` = NOW() 
            WHERE `Id_CatModalCap` = v_Id_Modalidad;
            
            COMMIT; 
            SELECT 'ÉXITO: Modalidad reactivada (recuperada tras concurrencia).' AS Mensaje, v_Id_Modalidad AS Id_Modalidad, 'REACTIVADA' AS Accion; 
            LEAVE THIS_PROC;
        END IF;
        
        /* Éxito por Reuso (El ganador ya estaba activo) */
        COMMIT; 
        SELECT 'AVISO: La Modalidad ya existía (reusada tras concurrencia).' AS Mensaje, v_Id_Modalidad AS Id_Modalidad, 'REUSADA' AS Accion; 
        LEAVE THIS_PROC;
    END IF;

    /* Fallo Irrecuperable: Si falló por 1062 pero no encontramos el registro 
       (Indica corrupción de índices o error fantasma grave) */
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR CRÍTICO [500]: Fallo de concurrencia no recuperable en Modalidades.';

END$$

DELIMITER ;


/* ============================================================================================
   SECCIÓN: CONSULTAS ESPECÍFICAS (PARA EDICIÓN / DETALLE)
   ============================================================================================
   Estas rutinas son clave para la UX. No solo devuelven el dato pedido, sino todo el 
   contexto necesario para que el formulario de edición se autocomplete correctamente.
   ============================================================================================ */

/* ====================================================================================================
   PROCEDIMIENTO: SP_ConsultarModalidadCapacitacionEspecifico
   ====================================================================================================
   
   ----------------------------------------------------------------------------------------------------
   I. OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   ----------------------------------------------------------------------------------------------------
   [QUÉ ES]:
   Es el endpoint de lectura de alta fidelidad para recuperar la "Ficha Técnica" completa de una 
   Modalidad de Capacitación específica, identificada por su llave primaria (`Id_CatModalCap`).

   [PARA QUÉ SE USA (CONTEXTO DE UI)]:
   A) PRECARGA DE FORMULARIO DE EDICIÓN (UPDATE):
      - Cuando el administrador va a modificar una modalidad (ej: corregir el nombre "VIRTUAL" a "REMOTO"),
        el formulario debe llenarse ("hidratarse") con los datos exactos que residen en la base de datos.
      - Requisito Crítico: La fidelidad del dato. Los valores se entregan crudos (Raw Data) para que 
        los inputs del HTML reflejen la realidad sin transformaciones cosméticas (ej: si el código es NULL,
        devuelve NULL, no "S/C").

   B) VISUALIZACIÓN DE DETALLE (AUDITORÍA):
      - Permite visualizar metadatos de auditoría (`created_at`, `updated_at`) que suelen estar ocultos
        en el listado general para mantener la limpieza visual.

   ----------------------------------------------------------------------------------------------------
   II. ARQUITECTURA DE DATOS (DIRECT TABLE ACCESS)
   ----------------------------------------------------------------------------------------------------
   Este procedimiento consulta directamente la tabla física `Cat_Modalidad_Capacitacion`.
   
   [JUSTIFICACIÓN TÉCNICA]:
   - Desacoplamiento de Presentación: A diferencia de las Vistas (que formatean datos para lectura humana),
     este SP prepara los datos para el consumo del sistema (Binding de Modelos en el Frontend).
   - Performance: El acceso por Primary Key (`Id_CatModalCap`) tiene un costo computacional de O(1),
     garantizando una respuesta instantánea (<1ms).

   ----------------------------------------------------------------------------------------------------
   III. ESTRATEGIA DE SEGURIDAD (DEFENSIVE PROGRAMMING)
   ----------------------------------------------------------------------------------------------------
   - Validación de Entrada: Se rechazan IDs nulos o negativos antes de tocar el disco.
   - Fail Fast (Fallo Rápido): Se verifica la existencia del registro antes de intentar devolver datos.
     Esto permite diferenciar claramente entre un "Error 404" (Recurso no encontrado) y un 
     "Error 500" (Fallo de servidor).

   ----------------------------------------------------------------------------------------------------
   IV. VISIBILIDAD (SCOPE)
   ----------------------------------------------------------------------------------------------------
   - NO se filtra por `Activo = 1`.
   - Razón: Una modalidad puede estar "Desactivada" (Baja Lógica). El administrador necesita poder 
     consultarla para ver su información y decidir si la Reactiva.

   ----------------------------------------------------------------------------------------------------
   V. DICCIONARIO DE DATOS (OUTPUT CONTRACT)
   ----------------------------------------------------------------------------------------------------
   Retorna una única fila (Single Row) mapeada semánticamente:
      - [Id_Modalidad]: Llave primaria.
      - [Codigo_Modalidad]: Clave corta técnica.
      - [Nombre_Modalidad]: Etiqueta humana.
      - [Descripcion_Modalidad]: Contexto operativo.
      - [Estatus_Modalidad]: Alias de negocio para `Activo` (1=Vigente, 0=Baja).
      - [Auditoría]: Fechas de creación y modificación.
   ==================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ConsultarModalidadCapacitacionEspecifico`$$

CREATE PROCEDURE `SP_ConsultarModalidadCapacitacionEspecifico`(
    IN _Id_Modalidad INT -- [OBLIGATORIO] Identificador único de la Modalidad a consultar
)
BEGIN
    /* ========================================================================================
       BLOQUE 1: VALIDACIÓN DE ENTRADA (DEFENSIVE PROGRAMMING)
       Objetivo: Asegurar que el parámetro recibido sea un entero positivo válido.
       Evita cargas innecesarias al motor de base de datos con peticiones basura.
       ======================================================================================== */
    IF _Id_Modalidad IS NULL OR _Id_Modalidad <= 0 THEN
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: El Identificador de la Modalidad es inválido (Debe ser un entero positivo).';
    END IF;

    /* ========================================================================================
       BLOQUE 2: VERIFICACIÓN DE EXISTENCIA (FAIL FAST STRATEGY)
       Objetivo: Validar que el recurso realmente exista en la base de datos.
       
       NOTA DE IMPLEMENTACIÓN:
       Usamos `SELECT 1` que es más ligero que seleccionar columnas reales, ya que solo 
       necesitamos confirmar la presencia de la llave en el índice primario.
       ======================================================================================== */
    IF NOT EXISTS (SELECT 1 FROM `Cat_Modalidad_Capacitacion` WHERE `Id_CatModalCap` = _Id_Modalidad) THEN
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [404]: La Modalidad de Capacitación solicitada no existe o fue eliminada físicamente.';
    END IF;

    /* ========================================================================================
       BLOQUE 3: CONSULTA PRINCIPAL (DATA RETRIEVAL)
       Objetivo: Retornar el objeto de datos completo y puro (Raw Data) con alias semánticos.
       ======================================================================================== */
    SELECT 
        /* --- GRUPO A: IDENTIDAD DEL REGISTRO --- */
        /* Este ID es la llave primaria inmutable. */
        `Id_CatModalCap`   AS `Id_Modalidad`,
        
        /* --- GRUPO B: DATOS EDITABLES --- */
        /* El Frontend usará estos campos para llenar los inputs de texto. */
        `Codigo`           AS `Codigo_Modalidad`,
        `Nombre`           AS `Nombre_Modalidad`,
        `Descripcion`      AS `Descripcion_Modalidad`,
        
        /* --- GRUPO C: METADATOS DE CONTROL DE CICLO DE VIDA --- */
        /* Este valor (0 o 1) indica si la modalidad es utilizable actualmente en nuevos registros.
           1 = Activo/Visible, 0 = Inactivo/Oculto (Baja Lógica). */
        `Activo`           AS `Estatus_Modalidad`,        
        
        /* --- GRUPO D: AUDITORÍA DE SISTEMA --- */
        /* Fechas útiles para mostrar en el pie de página del modal de detalle o tooltip. */
        `created_at`       AS `Fecha_Registro`,
        `updated_at`       AS `Ultima_Modificacion`
        
    FROM `Cat_Modalidad_Capacitacion`
    WHERE `Id_CatModalCap` = _Id_Modalidad
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
   PROCEDIMIENTO: SP_ListarModalidadCapacitacionActivos
   ====================================================================================================
   
   1. OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   ----------------------------------------------------------------------------------------------------
   Proveer un endpoint de datos ligero y optimizado para alimentar el componente visual 
   "Selector de Modalidad" (Dropdown) en los formularios de creación y edición de cursos.

   Este procedimiento es la fuente autorizada para que los Coordinadores elijan el formato
   logístico de una capacitación (ej: 'Presencial', 'Virtual', 'Híbrido').

   2. REGLAS DE NEGOCIO Y FILTRADO (THE VIGENCY CONTRACT)
   ----------------------------------------------------------------------------------------------------
   A) FILTRO DE VIGENCIA ESTRICTO (HARD FILTER):
      - Regla: La consulta aplica obligatoriamente la cláusula `WHERE Activo = 1`.
      - Justificación Operativa: Una Modalidad marcada como inactiva (Baja Lógica) indica que ese 
        formato de impartición ya no está soportado por la infraestructura actual. Permitir su 
        selección generaría cursos imposibles de ejecutar.
      - Seguridad: El filtro es nativo en BD, blindando el sistema contra UIs desactualizadas.

   B) ORDENAMIENTO COGNITIVO (USABILITY):
      - Regla: Los resultados se ordenan alfabéticamente por `Nombre` (A-Z).
      - Justificación: Facilita la búsqueda visual rápida en la lista desplegable.

   3. ARQUITECTURA DE DATOS (ROOT ENTITY OPTIMIZATION)
   ---------------------------------------------------
   - Ausencia de JOINs: `Cat_Modalidad_Capacitacion` es una Entidad Raíz (sin padres).
     Esto permite una ejecución directa y veloz sobre el índice primario.
   
   - Proyección Mínima (Payload Reduction):
     Solo se devuelven las columnas vitales para construir el elemento HTML `<option>`:
       1. ID (Value): Para la integridad referencial.
       2. Nombre (Label): Para la lectura humana.
       3. Código (Hint/Badge): Para lógica visual en el frontend (ej: iconos).
     
     Se omiten campos pesados como `Descripcion` o auditoría (`created_at`) para minimizar 
     la latencia de red en conexiones lentas.

   4. DICCIONARIO DE DATOS (OUTPUT JSON SCHEMA)
   --------------------------------------------
   Retorna un array de objetos ligeros:
      - `Id_CatModalCap`: (INT) Llave Primaria. Value del selector.
      - `Codigo`:         (VARCHAR) Clave corta (ej: 'PRES'). Útil para iconos.
      - `Nombre`:         (VARCHAR) Texto principal (ej: 'Presencial').
   ==================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ListarModalidadCapacitacionActivos`$$

CREATE PROCEDURE `SP_ListarModalidadCapacitacionActivos`()
BEGIN
    /* ========================================================================================
       BLOQUE ÚNICO: CONSULTA DE SELECCIÓN OPTIMIZADA
       No requiere validaciones de entrada ya que es una consulta de catálogo global.
       ======================================================================================== */
    
    SELECT 
        /* IDENTIFICADOR ÚNICO (PK)
           Este es el valor que se guardará como Foreign Key (Fk_Id_CatModalCap) 
           en la tabla operativa 'DatosCapacitaciones'. */
        `Id_CatModalCap`, 
        
        /* CLAVE CORTA / MNEMOTÉCNICA
           Dato auxiliar para que el Frontend pueda aplicar estilos o iconos condicionales.
           Ej: Si Codigo == 'VIRT' -> Mostrar icono de computadora. */
        `Codigo`, 
        
        /* DESCRIPTOR HUMANO
           El texto principal que el usuario leerá en la lista desplegable. */
        `Nombre`

    FROM 
        `Cat_Modalidad_Capacitacion`
    
    /* ----------------------------------------------------------------------------------------
       FILTRO DE SEGURIDAD OPERATIVA (VIGENCIA)
       Ocultamos todo lo que no sea "1" (Activo). 
       Esto asegura que las operaciones vivas solo usen modalidades aprobadas actualmente.
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
   PROCEDIMIENTO: SP_ListarModalidadCapacitacion
   ====================================================================================================
   
   ----------------------------------------------------------------------------------------------------
   I. FICHA TÉCNICA Y CONTEXTO DE NEGOCIO (BUSINESS CONTEXT)
   ----------------------------------------------------------------------------------------------------
   [NOMBRE LÓGICO]: Listado Maestro de Modalidades (Versión Ligera).
   [TIPO]: Rutina de Lectura (Read-Only).
   [DEPENDENCIA]: Consume la vista `Vista_Modalidad_Capacitacion`.

   [PROPÓSITO ESTRATÉGICO]:
   Este procedimiento actúa como el proveedor de datos para los **Filtros de Búsqueda Avanzada** en los 
   Paneles Administrativos y Reportes de Auditoría.
   
   A diferencia de los listados operativos (que solo muestran lo vigente), este SP debe entregar la 
   **Totalidad Histórica** del catálogo (Activos + Inactivos) para permitir que un auditor pueda 
   buscar cursos antiguos que se impartieron bajo modalidades ya extintas (ej: "A distancia por radio").

   ----------------------------------------------------------------------------------------------------
   II. ESTRATEGIA DE OPTIMIZACIÓN DE CARGA (PAYLOAD REDUCTION STRATEGY)
   ----------------------------------------------------------------------------------------------------
   [EL PROBLEMA]:
   En un Dashboard Administrativo, es común cargar 10 o 15 dropdowns simultáneamente al iniciar la página.
   Si cada dropdown trae descripciones largas, textos de ayuda y metadatos innecesarios, el tamaño del 
   JSON de respuesta crece exponencialmente, causando lentitud en la carga (Latency bloat).

   [LA SOLUCIÓN: PROYECCIÓN SELECTIVA]:
   Este SP aplica un patrón de "Adelgazamiento de Datos". Aunque la Vista fuente contiene la columna 
   `Descripcion_Modalidad` (que puede ser texto extenso), este procedimiento la **EXCLUYE DELIBERADAMENTE**.

   [JUSTIFICACIÓN]:
   En un control `<select>` o filtro de tabla, el usuario solo necesita ver el `Nombre` para elegir. 
   La descripción es ruido en este contexto. Al eliminarla, reducimos el consumo de ancho de banda y 
   memoria del navegador.

   ----------------------------------------------------------------------------------------------------
   III. REGLAS DE VISIBILIDAD Y ORDENAMIENTO (UX RULES)
   ----------------------------------------------------------------------------------------------------
   [RN-01] VISIBILIDAD TOTAL (NO FILTERING):
      - Regla: No se aplica ninguna cláusula `WHERE` sobre el estatus.
      - Razón: "Lo que se oculta no se puede auditar". El admin debe ver todo.

   [RN-02] JERARQUÍA VISUAL (SORTING):
      - Primer Nivel: `Estatus_Modalidad DESC`. Los registros ACTIVOS (1) aparecen arriba.
        Los INACTIVOS (0) se hunden al fondo de la lista.
      - Segundo Nivel: `Nombre_Modalidad ASC`. Orden alfabético para búsqueda rápida.

   ----------------------------------------------------------------------------------------------------
   IV. CONTRATO DE SALIDA (API RESPONSE SPECIFICATION)
   ----------------------------------------------------------------------------------------------------
   Retorna un Array de Objetos JSON optimizado:
      1. [Id_Modalidad]: (INT) El valor (`value`) del filtro.
      2. [Codigo_Modalidad]: (STRING) Clave técnica para lógica de iconos en el frontend.
      3. [Nombre_Modalidad]: (STRING) La etiqueta (`label`) visible.
      4. [Estatus_Modalidad]: (INT) 1/0. Permite al Frontend pintar de gris los items inactivos.
   ==================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ListarModalidadCapacitacion`$$

CREATE PROCEDURE `SP_ListarModalidadCapacitacion`()
BEGIN
    /* ========================================================================================
       BLOQUE ÚNICO: CONSULTA DE PROYECCIÓN SELECTIVA
       ----------------------------------------------------------------------------------------
       Nota de Implementación:
       No usamos `SELECT *`. Enumeramos explícitamente las columnas para garantizar que la
       `Descripcion_Modalidad` NO viaje por la red.
       ======================================================================================== */
    
    SELECT 
        /* -------------------------------------------------------------------------------
           GRUPO 1: IDENTIDAD DEL RECURSO (PRIMARY KEYS & CODES)
           Datos necesarios para mantener la integridad referencial en la selección.
           ------------------------------------------------------------------------------- */
        `Id_Modalidad`,        -- Vinculación con FKs en tablas de hechos (Cursos).
        `Codigo_Modalidad`,    -- Identificador semántico corto (ej: 'VIRT').

        /* -------------------------------------------------------------------------------
           GRUPO 2: DESCRIPTOR HUMANO (LABEL)
           La información principal que el usuario final leerá en la interfaz.
           ------------------------------------------------------------------------------- */
        `Nombre_Modalidad`    -- Texto descriptivo (ej: 'VIRTUAL SINCRÓNICO').
        
        /* -------------------------------------------------------------------------------
           GRUPO 3: METADATOS DE CONTROL (STATUS FLAG)
           Dato crítico para la UX del Administrador.
           Permite aplicar estilos visuales (ej: tachado, gris, icono de alerta) a los
           elementos que ya no están vigentes, sin ocultarlos del filtro.
           ------------------------------------------------------------------------------- */
        -- `Estatus_Modalidad`    -- 1 = Operativo, 0 = Deprecado/Histórico.
        
        /* [COLUMNA EXCLUIDA]: `Descripcion_Modalidad`
           Se omite por optimización de Payload. No aporta valor en un Dropdown. */
        
    FROM 
        `Vista_Modalidad_Capacitacion`
    
    /* ========================================================================================
       BLOQUE DE ORDENAMIENTO (UX OPTIMIZATION)
       ----------------------------------------------------------------------------------------
       Diseñado para maximizar la eficiencia del operador.
       ======================================================================================== */
    ORDER BY 
        `Estatus_Modalidad` DESC,  -- Prioridad 1: Mantener lo útil (Activos) al principio.
        `Nombre_Modalidad` ASC;    -- Prioridad 2: Facilitar el escaneo visual alfabético.

END$$

DELIMITER ;

/* ====================================================================================================
   PROCEDIMIENTO: SP_EditarModalidadCapacitacion
   ====================================================================================================

   ----------------------------------------------------------------------------------------------------
   I. CONTEXTO TÉCNICO Y DE NEGOCIO (BUSINESS CONTEXT)
   ----------------------------------------------------------------------------------------------------
   [QUÉ ES]:
   Es el motor transaccional de alta fidelidad encargado de modificar los atributos fundamentales de 
   una "Modalidad de Capacitación" (`Cat_Modalidad_Capacitacion`) existente en el catálogo corporativo.

   [OBJETIVO ESTRATÉGICO]:
   Permitir al administrador corregir o actualizar la identidad (`Código`, `Nombre`) y el contexto 
   operativo (`Descripción`) de una modalidad.
   
   [IMPORTANCIA CRÍTICA]:
   Las modalidades (Presencial, Virtual, Híbrido) son la base de la logística de cursos. Un error de 
   integridad aquí (ej: duplicar conceptos o perder descripciones) corrompería la inteligencia de 
   negocios de todos los reportes históricos y futuros.

   Este SP garantiza la consistencia ACID (Atomicidad, Consistencia, Aislamiento, Durabilidad) en un 
   entorno multi-usuario de alta concurrencia.

   ----------------------------------------------------------------------------------------------------
   II. REGLAS DE BLINDAJE (HARD CONSTRAINTS)
   ----------------------------------------------------------------------------------------------------
   [RN-01] OBLIGATORIEDAD DE DATOS (DATA INTEGRITY):
      - Principio: "Todo o Nada". No se permite persistir una modalidad sin `Código` o sin `Nombre`.
      - Justificación: Un registro anónimo o sin clave técnica rompe la integridad visual de los 
        selectores (dropdowns) y las referencias en el backend.

   [RN-02] EXCLUSIÓN PROPIA (GLOBAL UNIQUENESS):
      - Regla A: El nuevo `Código` no puede pertenecer a OTRA modalidad (`Id <> _Id_Modalidad`).
      - Regla B: El nuevo `Nombre` no puede pertenecer a OTRA modalidad.
      - Nota: Es perfectamente legal que el registro coincida consigo mismo (Idempotencia).
      - Implementación: Esta validación se realiza "Bajo Llave" (dentro de la transacción con bloqueo).

   [RN-03] IDEMPOTENCIA (OPTIMIZACIÓN DE I/O):
      - Antes de escribir en disco, el SP compara el estado actual (`Snapshot`) contra los inputs.
      - Si son matemáticamente idénticos, retorna éxito ('SIN_CAMBIOS') inmediatamente.
      - Beneficio: Evita escrituras innecesarias en el Transaction Log, reduce el crecimiento de la 
        BD y mantiene intacta la fecha de auditoría `updated_at`.

   ----------------------------------------------------------------------------------------------------
   III. ARQUITECTURA DE CONCURRENCIA (DETERMINISTIC LOCKING PATTERN)
   ----------------------------------------------------------------------------------------------------
   [EL PROBLEMA DE LOS DEADLOCKS (ABRAZOS MORTALES)]:
   En un escenario de "Intercambio" (Swap Scenario), donde:
      - Usuario A quiere renombrar la Modalidad 1 como 'VIRTUAL'.
      - Usuario B quiere renombrar la Modalidad 2 como 'PRESENCIAL'.
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
      - [Id_Modalidad]: Identificador del recurso manipulado.
   ==================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_EditarModalidadCapacitacion`$$

CREATE PROCEDURE `SP_EditarModalidadCapacitacion`(
    /* -----------------------------------------------------------------
       PARÁMETROS DE ENTRADA (INPUT LAYER)
       Recibimos los datos crudos desde el formulario web.
       Se asume que son cadenas de texto que requieren limpieza.
       ----------------------------------------------------------------- */
    IN _Id_Modalidad INT,           -- [OBLIGATORIO] PK del registro a editar (Target).
    IN _Codigo       VARCHAR(50),   -- [OBLIGATORIO] Nuevo Código (ej: 'VIRT-02').
    IN _Nombre       VARCHAR(255),  -- [OBLIGATORIO] Nuevo Nombre (ej: 'VIRTUAL ASINCRÓNICO').
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
    
	/* --- CORRECCIÓN: SE AGREGA LA VARIABLE FALTANTE PARA EL BLOQUE 6 --- */
    DECLARE v_Id_Conflicto     INT DEFAULT NULL; -- Variable genérica para reportar errores
    
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
    
    IF _Id_Modalidad IS NULL OR _Id_Modalidad <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: Identificador de Modalidad inválido.';
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
    FROM `Cat_Modalidad_Capacitacion` WHERE `Id_CatModalCap` = _Id_Modalidad;

    /* Check de Existencia: Si no existe, abortamos. (Pudo ser borrado por otro admin hace un segundo) */
    IF v_Cod_Act IS NULL AND v_Nom_Act IS NULL THEN 
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [404]: La Modalidad que intenta editar no existe.';
    END IF;

    /* B) Identificar Conflicto de CÓDIGO 
       ¿Alguien más tiene el código que quiero usar? (Solo buscamos si el código cambió) */
    IF _Codigo <> IFNULL(v_Cod_Act, '') THEN
        SELECT `Id_CatModalCap` INTO v_Id_Conflicto_Cod 
        FROM `Cat_Modalidad_Capacitacion` 
        WHERE `Codigo` = _Codigo AND `Id_CatModalCap` <> _Id_Modalidad LIMIT 1;
    END IF;

    /* C) Identificar Conflicto de NOMBRE 
       ¿Alguien más tiene el nombre que quiero usar? (Solo buscamos si el nombre cambió) */
    IF _Nombre <> v_Nom_Act THEN
        SELECT `Id_CatModalCap` INTO v_Id_Conflicto_Nom 
        FROM `Cat_Modalidad_Capacitacion` 
        WHERE `Nombre` = _Nombre AND `Id_CatModalCap` <> _Id_Modalidad LIMIT 1;
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 3.2: EJECUCIÓN DE BLOQUEOS ORDENADOS (EL ALGORITMO)
       Ordenamos los IDs detectados y los bloqueamos secuencialmente.
       ---------------------------------------------------------------------------------------- */
    
    /* Llenamos el pool de candidatos a bloquear */
    SET v_L1 = _Id_Modalidad;
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
        SELECT 1 INTO v_Existe FROM `Cat_Modalidad_Capacitacion` WHERE `Id_CatModalCap` = v_Min FOR UPDATE;
        
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
        SELECT 1 INTO v_Existe FROM `Cat_Modalidad_Capacitacion` WHERE `Id_CatModalCap` = v_Min FOR UPDATE;
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
        SELECT 1 INTO v_Existe FROM `Cat_Modalidad_Capacitacion` WHERE `Id_CatModalCap` = v_Min FOR UPDATE;
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
    FROM `Cat_Modalidad_Capacitacion` 
    WHERE `Id_CatModalCap` = _Id_Modalidad; 

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
        SELECT 'AVISO: No se detectaron cambios en la información.' AS Mensaje, 'SIN_CAMBIOS' AS Accion, _Id_Modalidad AS Id_Modalidad;
        LEAVE THIS_PROC;
    END IF;

    /* 4.3 VALIDACIÓN FINAL DE UNICIDAD (PRE-UPDATE CHECK)
       Verificamos duplicados reales bajo lock. Esta validación es 100% fiable. */
    
    /* A) Validación por CÓDIGO */
    SET v_Id_Error = NULL;
    SELECT `Id_CatModalCap` INTO v_Id_Error FROM `Cat_Modalidad_Capacitacion` 
    WHERE `Codigo` = _Codigo AND `Id_CatModalCap` <> _Id_Modalidad LIMIT 1;
    
    IF v_Id_Error IS NOT NULL THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'CONFLICTO DE DATOS [409]: El CÓDIGO ingresado ya pertenece a otra Modalidad.';
    END IF;

    /* B) Validación por NOMBRE */
    SET v_Id_Error = NULL;
    SELECT `Id_CatModalCap` INTO v_Id_Error FROM `Cat_Modalidad_Capacitacion` 
    WHERE `Nombre` = _Nombre AND `Id_CatModalCap` <> _Id_Modalidad LIMIT 1;
    
    IF v_Id_Error IS NOT NULL THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'CONFLICTO DE DATOS [409]: El NOMBRE ingresado ya pertenece a otra Modalidad.';
    END IF;

    /* ========================================================================================
       BLOQUE 5: PERSISTENCIA (UPDATE FÍSICO)
       Propósito: Aplicar los cambios físicos en el disco.
       ======================================================================================== */
    
    SET v_Dup = 0; -- Resetear bandera de error antes de intentar escribir

    UPDATE `Cat_Modalidad_Capacitacion`
    SET `Codigo`      = _Codigo,
        `Nombre`      = _Nombre,
        `Descripcion` = _Descripcion,
        `updated_at`  = NOW() -- Auditoría automática
    WHERE `Id_CatModalCap` = _Id_Modalidad;

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
        SELECT `Id_CatModalCap` INTO v_Id_Conflicto FROM `Cat_Modalidad_Capacitacion` 
        WHERE `Codigo` = _Codigo AND `Id_CatModalCap` <> _Id_Modalidad LIMIT 1;

        IF v_Id_Conflicto IS NOT NULL THEN
             SET v_Campo_Error = 'CODIGO';
        ELSE
             /* Prueba 2: Fue Nombre */
             SELECT `Id_CatModalCap` INTO v_Id_Conflicto FROM `Cat_Modalidad_Capacitacion` 
             WHERE `Nombre` = _Nombre AND `Id_CatModalCap` <> _Id_Modalidad LIMIT 1;
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
    
    SELECT 'ÉXITO: Modalidad actualizada correctamente.' AS Mensaje, 
           'ACTUALIZADA' AS Accion, 
           _Id_Modalidad AS Id_Modalidad;

END$$

DELIMITER ;

/* ====================================================================================================
   PROCEDIMIENTO: SP_CambiarEstatusModalidadCapacitacion
   ====================================================================================================
   
   ----------------------------------------------------------------------------------------------------
   I. RESUMEN EJECUTIVO Y CONTEXTO DE NEGOCIO (EXECUTIVE SUMMARY)
   ----------------------------------------------------------------------------------------------------
   [DEFINICIÓN DEL COMPONENTE]:
   Este procedimiento actúa como el "Interruptor Maestro de Disponibilidad" (Availability Toggle) para 
   el catálogo de Modalidades de Capacitación. Su función no es simplemente actualizar una columna 
   booleana; es un orquestador de integridad que decide si es seguro retirar un recurso del ecosistema.

   [EL RIESGO OPERATIVO (THE BUSINESS RISK)]:
   En un sistema de gestión de capacitación (LMS), la "Modalidad" no es un dato decorativo; es un 
   eje estructural. Define la logística, los recursos necesarios (salas vs licencias Zoom) y las 
   reglas de asistencia.
   
   Escenario Catastrófico:
   1. Un Administrador desactiva la modalidad "VIRTUAL" un lunes a las 09:00 AM.
   2. Existen 50 cursos programados para iniciar esa semana bajo esa modalidad.
   3. Resultado: Los instructores no pueden registrar asistencia, los reportes de cumplimiento fallan 
      por "Modalidad Nula/Inválida", y la operación se detiene.

   [LA SOLUCIÓN ARQUITECTÓNICA (THE SOLUTION)]:
   Implementamos un patrón de diseño llamado "Safe Soft Delete" (Baja Lógica Segura).
   El sistema realiza un análisis de impacto en tiempo real antes de permitir la desactivación.
   Si detecta dependencias vivas, bloquea la acción y protege la continuidad del negocio.

   ----------------------------------------------------------------------------------------------------
   II. MATRIZ DE REGLAS DE BLINDAJE (SECURITY & INTEGRITY RULES)
   ----------------------------------------------------------------------------------------------------
   [RN-01] INTEGRIDAD REFERENCIAL DESCENDENTE (DOWNSTREAM INTEGRITY):
      - Principio: "Un padre no puede morir si sus hijos dependen de él para vivir".
      - Regla Técnica: No se permite establecer `Activo = 0` si existen registros en la tabla 
        `DatosCapacitaciones` que cumplan dos condiciones simultáneas:
          a) Estén vinculados a esta Modalidad (`Fk_Id_CatModalCap`).
          b) Tengan un estatus operativo VIGENTE (`Activo = 1`).
      - Excepción: Si los cursos históricos ya están "muertos" (Cancelados/Finalizados/Borrados), 
        el bloqueo no aplica. Esto permite la depuración del catálogo a largo plazo.

   [RN-02] IDEMPOTENCIA DE ESTADO (STATE IDEMPOTENCY):
      - Principio: "No arregles lo que no está roto".
      - Regla Técnica: Si el sistema recibe una solicitud para cambiar el estatus al valor que YA tiene 
        actualmente (ej: Activar una modalidad Activa), el procedimiento aborta la escritura y retorna 
        un mensaje de éxito informativo.
      - Beneficio: 
          1. Reducción de I/O en disco (no hay UPDATE).
          2. Preservación de la auditoría (no se altera `updated_at` artificialmente).
          3. Menor bloqueo de filas (mayor concurrencia).

   [RN-03] ATOMICIDAD TRANSACCIONAL (ACID COMPLIANCE):
      - Principio: "Todo o Nada".
      - Mecanismo: La lectura de verificación y la escritura del cambio ocurren dentro de una 
        transacción aislada con nivel SERIALIZABLE (vía `FOR UPDATE`).
      - Justificación: Evita la "Condición de Carrera del Milisegundo" (Race Condition), donde un 
        usuario crea un curso nuevo justo en el instante entre la validación y la desactivación.

   ----------------------------------------------------------------------------------------------------
   III. ESPECIFICACIÓN TÉCNICA DE ALTO NIVEL (TECHNICAL SPECS)
   ----------------------------------------------------------------------------------------------------
   - TIPO: Stored Procedure Transaccional (InnoDB).
   - AISLAMIENTO: Pessimistic Locking (Bloqueo Pesimista).
   - INPUT: 
       * _Id_Modalidad (INT): Identificador único.
       * _Nuevo_Estatus (TINYINT): Flag binario (0/1).
   - OUTPUT: Resultset JSON-Friendly { Mensaje, Accion, Estado_Nuevo, Estado_Anterior }.
   - ERRORES CONTROLADOS: 
       * 400 (Bad Request): Datos de entrada inválidos.
       * 404 (Not Found): Recurso inexistente.
       * 409 (Conflict): Bloqueo por reglas de negocio.
       * 500 (Internal Server Error): Fallos de SQL.

   ----------------------------------------------------------------------------------------------------
   IV. MAPA DE MEMORIA Y VARIABLES (MEMORY ALLOCATION)
   ----------------------------------------------------------------------------------------------------
   El procedimiento reserva espacio para:
      - Snapshots del registro actual (para comparar antes/después).
      - Contadores de dependencias (para la lógica de bloqueo).
      - Banderas de control de flujo.
   ==================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_CambiarEstatusModalidadCapacitacion`$$

CREATE PROCEDURE `SP_CambiarEstatusModalidadCapacitacion`(
    /* ------------------------------------------------------------------------------------------------
       SECCIÓN DE PARÁMETROS DE ENTRADA (INPUT LAYER)
       Recibimos los datos crudos desde el controlador del Backend.
       ------------------------------------------------------------------------------------------------ */
    IN _Id_Modalidad INT,        -- [OBLIGATORIO] Identificador del recurso a modificar.
    IN _Nuevo_Estatus TINYINT    -- [OBLIGATORIO] 1 = Activar, 0 = Desactivar.
)
THIS_PROC: BEGIN
    
    /* ================================================================================================
       BLOQUE 0: INICIALIZACIÓN DE VARIABLES DE ESTADO
       Propósito: Definir los contenedores en memoria para la lógica del procedimiento.
       ================================================================================================ */
    
    /* [Snapshot del Estado Actual]:
       Almacenamos cómo está el registro en la BD antes de tocarlo. 
       Vital para la verificación de idempotencia y para el mensaje de respuesta. */
    DECLARE v_Estatus_Actual TINYINT(1) DEFAULT NULL;
    DECLARE v_Nombre_Modalidad VARCHAR(255) DEFAULT NULL;
    
    /* [Semáforo de Dependencias]:
       Contador utilizado para escanear la tabla `DatosCapacitaciones`.
       Si este valor es > 0, significa que hay hijos vivos y debemos activar el bloqueo. */
    DECLARE v_Dependencias_Activas INT DEFAULT 0;

    /* [Bandera de Existencia]:
       Variable auxiliar para confirmar si el ID proporcionado es válido. */
    DECLARE v_Existe INT DEFAULT NULL;

    /* ================================================================================================
       BLOQUE 1: GESTIÓN DE EXCEPCIONES Y SEGURIDAD (ERROR HANDLING)
       Propósito: Garantizar que la base de datos nunca quede en un estado inconsistente.
       ================================================================================================ */
    
    /* Handler Genérico (Catch-All):
       Ante cualquier error SQL inesperado (Deadlock, Conexión perdida, Corrupción de índice),
       este bloque se activa automáticamente para:
         1. Revertir cualquier cambio pendiente (ROLLBACK).
         2. Propagar el error original al cliente (RESIGNAL). */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; 
    END;

    /* ================================================================================================
       BLOQUE 2: PROTOCOLO DE VALIDACIÓN PREVIA (FAIL FAST STRATEGY)
       Propósito: Rechazar peticiones malformadas ("Basura") antes de consumir recursos.
       ================================================================================================ */
    
    /* 2.1 Validación de Dominio (Type Safety):
       El estatus es un valor booleano lógico. Solo aceptamos 0 o 1.
       Cualquier otro valor (ej: 2, 99, -1) indica un error en la capa de aplicación. 
    IF _Nuevo_Estatus NOT IN (0, 1) THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERROR DE LÓGICA [400]: El parámetro _Nuevo_Estatus solo acepta valores binarios: 0 (Inactivo) o 1 (Activo).';
    END IF;*/
    
    /* 2.1 Validación de Dominio (Type Safety):
       El estatus es un valor booleano lógico. Solo aceptamos 0 o 1.
       Agregamos 'IS NULL' para capturar el error de lógica de tres estados de SQL. */
    IF _Nuevo_Estatus IS NULL OR _Nuevo_Estatus NOT IN (0, 1) THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERROR DE LÓGICA [400]: El estatus es obligatorio y solo acepta valores binarios: 0 (Inactivo) o 1 (Activo).';
    END IF;

    /* 2.2 Validación de Identidad (Integrity Check):
       El ID debe ser un entero positivo. */
    IF _Id_Modalidad IS NULL OR _Id_Modalidad <= 0 THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: El ID de la Modalidad es inválido o nulo.';
    END IF;

    /* ================================================================================================
       BLOQUE 3: INICIO DE TRANSACCIÓN Y BLOQUEO PESIMISTA
       El núcleo de la seguridad transaccional. Aquí aislamos el proceso del resto del mundo.
       ================================================================================================ */
    START TRANSACTION;

    /* ------------------------------------------------------------------------------------------------
       PASO 3.1: LECTURA Y BLOQUEO DEL RECURSO (SNAPSHOT ACQUISITION)
       
       Mecánica Técnica:
       Ejecutamos un SELECT con la cláusula `FOR UPDATE`.
       
       Efecto en el Motor de Base de Datos (InnoDB):
       1. Localiza la fila específica en el índice primario (`Id_CatModalCap`).
       2. Coloca un "Exclusive Lock (X-Lock)" sobre esa fila.
       3. Cualquier otra transacción que intente leer o escribir en ESTA fila entrará en 
          estado de espera (WAIT) hasta que nosotros hagamos COMMIT o ROLLBACK.
       
       Justificación de Negocio:
       Evita que otro administrador edite el nombre de la modalidad o la borre físicamente
       mientras nosotros estamos evaluando si es seguro desactivarla.
       ------------------------------------------------------------------------------------------------ */
    SELECT `Activo`, `Nombre` 
    INTO v_Estatus_Actual, v_Nombre_Modalidad
    FROM `Cat_Modalidad_Capacitacion` 
    WHERE `Id_CatModalCap` = _Id_Modalidad 
    LIMIT 1
    FOR UPDATE;

    /* ------------------------------------------------------------------------------------------------
       PASO 3.2: VALIDACIÓN DE EXISTENCIA (NOT FOUND HANDLER)
       Si la variable v_Estatus_Actual sigue siendo NULL, significa que el SELECT no encontró nada.
       El registro no existe (Error 404).
       ------------------------------------------------------------------------------------------------ */
    IF v_Estatus_Actual IS NULL THEN
        ROLLBACK; -- Liberamos recursos aunque no haya locks efectivos.
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [404]: La Modalidad solicitada no existe en el catálogo maestro.';
    END IF;

    /* ------------------------------------------------------------------------------------------------
       PASO 3.3: VERIFICACIÓN DE IDEMPOTENCIA (OPTIMIZACIÓN DE RECURSOS)
       
       Concepto:
       Una operación es idempotente si realizarla múltiples veces tiene el mismo efecto que una sola vez.
       
       Lógica Aplicada:
       Si el usuario pide "ACTIVAR" una modalidad que ya está "ACTIVA", no hay cambio de estado.
       Por lo tanto, no hay necesidad de ejecutar un UPDATE.
       
       Beneficios:
       1. Ahorro de I/O de disco (escritura).
       2. Ahorro de espacio en logs de transacción.
       3. Integridad de Auditoría: No se modifica la fecha `updated_at` falsamente.
       ------------------------------------------------------------------------------------------------ */
    IF v_Estatus_Actual = _Nuevo_Estatus THEN
        
        COMMIT; -- Liberamos el bloqueo inmediatamente.
        
        /* Retornamos un mensaje de éxito informativo pero aclaratorio */
        SELECT CONCAT('AVISO: La Modalidad "', v_Nombre_Modalidad, '" ya se encuentra en el estado solicitado (', IF(_Nuevo_Estatus=1,'ACTIVO','INACTIVO'), ').') AS Mensaje, 
               'SIN_CAMBIOS' AS Accion,
               v_Estatus_Actual AS Estado_Anterior,
               _Nuevo_Estatus AS Estado_Nuevo;
        
        LEAVE THIS_PROC; -- Salimos del procedimiento limpiamente.
    END IF;

    /* ================================================================================================
       BLOQUE 4: EVALUACIÓN DE REGLAS DE BLINDAJE (CANDADOS DE INTEGRIDAD)
       Solo ejecutamos este análisis profundo si realmente vamos a cambiar el estado.
       ================================================================================================ */

    /* ------------------------------------------------------------------------------------------------
       PASO 4.1: CANDADO OPERATIVO DESCENDENTE (SOLO AL DESACTIVAR)
       
       Contexto:
       Desactivar (`_Nuevo_Estatus = 0`) es una operación destructiva lógica. Puede dejar huérfanos.
       Activar (`_Nuevo_Estatus = 1`) es una operación segura (generalmente).
       
       Por tanto, este bloque solo se ejecuta si la intención es APAGAR el recurso.
       ------------------------------------------------------------------------------------------------ */
    IF _Nuevo_Estatus = 0 THEN
        
        /* [ANÁLISIS DE DEPENDENCIAS]:
           Consultamos la tabla operativa `DatosCapacitaciones`.
           Esta tabla contiene el historial de todos los cursos impartidos.
           
           Criterios de Búsqueda:
           1. `Fk_Id_CatModalCap` = ID de la modalidad actual.
           2. `Activo` = 1.
           
           ¿Por qué `Activo = 1`?
           Porque solo nos preocupan los cursos VIVOS. Si un curso fue cancelado o eliminado
           lógicamente en el pasado, no representa un conflicto para desactivar la modalidad hoy.
           Pero si el curso está programado, en curso o finalizado (sin borrar), es una dependencia dura. */
        
        SELECT COUNT(*) INTO v_Dependencias_Activas
        FROM `DatosCapacitaciones`
        WHERE `Fk_Id_CatModalCap` = _Id_Modalidad
          AND `Activo` = 1; -- Solo nos importan los cursos vigentes.

        /* [DISPARADOR DE BLOQUEO DE INTEGRIDAD]:
           Si el contador es mayor a 0, significa que hay al menos un curso que depende de esta modalidad.
           La operación es ILEGAL bajo las reglas de negocio. */
        IF v_Dependencias_Activas > 0 THEN
            
            ROLLBACK; -- Cancelamos la operación. Se liberan los locks. Ningún dato fue tocado.
            
            /* Retornamos un error 409 (Conflicto) claro y explicativo para el usuario */
            SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'BLOQUEO DE INTEGRIDAD [409]: Operación Denegada. No se puede desactivar esta Modalidad porque existen CAPACITACIONES ACTIVAS que dependen de ella. Para proceder, primero debe finalizar, cancelar o reasignar los cursos asociados.';
        END IF;
    END IF;

    /* ================================================================================================
       BLOQUE 5: PERSISTENCIA (EJECUCIÓN DEL CAMBIO)
       Si el flujo llega a este punto, significa que:
         1. El registro existe.
         2. El cambio es necesario (no es idempotente).
         3. No viola ninguna regla de integridad referencial.
       Es seguro escribir en el disco.
       ================================================================================================ */
    
    UPDATE `Cat_Modalidad_Capacitacion` 
    SET `Activo` = _Nuevo_Estatus, 
        `updated_at` = NOW() -- Auditoría: Registramos el momento exacto del cambio.
    WHERE `Id_CatModalCap` = _Id_Modalidad;

    /* ================================================================================================
       BLOQUE 6: CONFIRMACIÓN Y RESPUESTA FINAL
       Propósito: Cerrar la transacción y comunicar el resultado al cliente.
       ================================================================================================ */
    
    /* Confirmamos la transacción (COMMIT).
       Esto hace permanentes los cambios en el disco y libera el bloqueo de la fila,
       permitiendo que otros usuarios vuelvan a leer/escribir este registro. */
    COMMIT;

    /* Generamos la respuesta estructurada para el Frontend.
       Usamos lógica condicional para dar un mensaje humano ("Reactivada" vs "Desactivada"). */
    SELECT 
        CASE 
            WHEN _Nuevo_Estatus = 1 THEN CONCAT('ÉXITO: La Modalidad "', v_Nombre_Modalidad, '" ha sido REACTIVADA y está disponible para nuevas asignaciones.')
            ELSE CONCAT('ÉXITO: La Modalidad "', v_Nombre_Modalidad, '" ha sido DESACTIVADA (Baja Lógica) correctamente.')
        END AS Mensaje,
        'ESTATUS_CAMBIADO' AS Accion,
        v_Estatus_Actual AS Estado_Anterior,
        _Nuevo_Estatus AS Estado_Nuevo;

END$$

DELIMITER ;

/* ====================================================================================================
   PROCEDIMIENTO: SP_EliminarModalidadCapacitacionFisico
   ====================================================================================================

   ----------------------------------------------------------------------------------------------------
   I. FILOSOFÍA DE DISEÑO Y CONTEXTO ESTRATÉGICO (DATA GOVERNANCE)
   ----------------------------------------------------------------------------------------------------
   [QUÉ ES]:
   Este procedimiento representa el nivel máximo de autoridad administrativa en el ciclo de vida de los 
   datos: la "Eliminación Dura" (Hard Delete). Su ejecución implica la destrucción física de los 
   registros en las páginas de datos del disco duro para la tabla `Cat_Modalidad_Capacitacion`.

   [JUSTIFICACIÓN DE LA RIGIDEZ]:
   En un sistema de grado industrial, la información no es solo "texto", es una cadena de custodia. 
   Eliminar una modalidad que alguna vez fue utilizada es equivalente a borrar un eslabón en una cadena 
   de auditoría. Si borramos la modalidad "PRESENCIAL" y existen cursos históricos ligados a ella, 
   estamos creando "Datos Fantasma" o registros huérfanos que harían que los reportes de BI 
   (Business Intelligence) y las auditorías de cumplimiento (SSPA/PEMEX) fallen por inconsistencia.

   [DIFERENCIACIÓN DE PROCESOS]:
   1. BAJA LÓGICA (SP_CambiarEstatus...): Es la operación estándar. El dato se oculta pero se preserva 
      la integridad histórica. "El registro existió, pero ya no está disponible".
   2. BAJA FÍSICA (Este Procedimiento): Es una operación quirúrgica de limpieza. Su único fin es 
      eliminar errores de captura que JAMÁS llegaron a tener vida operativa (ej. creaste un registro 
      por error y lo borras 1 minuto después).

   ----------------------------------------------------------------------------------------------------
   II. MATRIZ DE RIESGOS Y REGLAS DE BLINDAJE (INTEGRITY ARCHITECTURE)
   ----------------------------------------------------------------------------------------------------
   [RN-01] CANDADO HISTÓRICO ABSOLUTO (THE FORENSIC GUARD):
      - Principio: "Inmutabilidad del Rastro Operativo".
      - Regla de Negocio: Queda terminantemente PROHIBIDO el borrado físico si el registro aparece como 
        Foreign Key (FK) en la tabla de hechos `DatosCapacitaciones`.
      - Alcance Forense: El escaneo es agnóstico al estatus. No importa si el curso hijo está 
        'Activo', 'Cancelado', 'Finalizado' o 'Eliminado Lógicamente'. Si el ID de la modalidad 
        está en la tabla de hechos, el padre no puede ser destruido físicamente.

   [RN-02] ATOMICIDAD TRANSACCIONAL Y SERIALIZACIÓN (ACID):
      - Mecanismo: Implementación de Bloqueo Pesimista (`FOR UPDATE`).
      - Objetivo: Evitar la "Carrera de Destrucción". Esto impide que un Usuario A valide que no hay 
        hijos mientras un Usuario B crea un hijo nuevo en el microsegundo exacto antes del DELETE.
      - Nivel de Aislamiento: Se fuerza un comportamiento SERIALIZABLE para este recurso específico.

   [RN-03] DEFENSA EN PROFUNDIDAD (LAYERED DEFENSE):
      - Capa 1 (Aplicación): El SP valida el ID y la existencia del registro.
      - Capa 2 (Negocio): El SP escanea manualmente las tablas dependientes (`COUNT`).
      - Capa 3 (Motor): El Handler de MySQL para el error 1451 atrapa cualquier dependencia oculta 
        definida a nivel de esquema (Constraints).

   ----------------------------------------------------------------------------------------------------
   III. ESPECIFICACIÓN TÉCNICA DE ALTO NIVEL
   ----------------------------------------------------------------------------------------------------
   - TIPO: Destructivo / Atómico.
   - INPUT: _Id_Modalidad (INT).
   - OUTPUT: Resultset detallado con { Mensaje, Accion, Id_Eliminado }.
   - IMPACTO EN RENDIMIENTO: Al realizar un scan sobre `DatosCapacitaciones`, se recomienda que la 
     columna `Fk_Id_CatModalCap` en dicha tabla tenga un ÍNDICE activo para garantizar velocidad O(log n).

   ----------------------------------------------------------------------------------------------------
   IV. CONTRATO DE RESPUESTA (API SPEC)
   ----------------------------------------------------------------------------------------------------
   El procedimiento garantiza retornar siempre un resultado legible, evitando que el Frontend 
   tenga que lidiar con excepciones crípticas de la base de datos.
   ==================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_EliminarModalidadCapacitacionFisico`$$

CREATE PROCEDURE `SP_EliminarModalidadCapacitacionFisico`(
    /* -----------------------------------------------------------------
       PARÁMETRO DE ENTRADA (INPUT)
       El identificador único que será el objetivo de la purga.
       ----------------------------------------------------------------- */
    IN _Id_Modalidad INT 
)
THIS_PROC: BEGIN

    /* ========================================================================================
       BLOQUE 0: DECLARACIÓN DE VARIABLES DE ESTADO Y CONTROL
       Propósito: Reservar espacio en memoria para los diagnósticos de integridad.
       ======================================================================================== */
    
    /* [Snapshot de Identidad]:
       Almacenamos el nombre antes de borrarlo para poder informarlo en el mensaje de éxito. */
    DECLARE v_Nombre_Modalidad VARCHAR(255) DEFAULT NULL;
    
    /* [Semáforo de Integridad]:
       Contador forense para medir el uso histórico del registro en el sistema operativo. */
    DECLARE v_Referencias_Historicas INT DEFAULT 0;

    /* [Bandera de Existencia]:
       Variable booleana auxiliar para el bloqueo pesimista. */
    DECLARE v_Existe INT DEFAULT NULL;

    /* ========================================================================================
       BLOQUE 1: HANDLERS DE EMERGENCIA (THE SAFETY NET)
       Propósito: Capturar errores nativos del motor InnoDB y darles un tratamiento humano.
       ======================================================================================== */
    
    /* [1.1] Handler para Error 1451 (Cannot delete or update a parent row: a foreign key constraint fails)
       Este es el cinturón de seguridad de la base de datos. Si nuestra validación lógica (Bloque 4) 
       fallara o si se agregaran nuevas tablas en el futuro sin actualizar este SP, el motor de BD 
       bloqueará el borrado. Este handler captura ese evento, deshace la transacción y da feedback. */
    DECLARE EXIT HANDLER FOR 1451 
    BEGIN 
        ROLLBACK; -- Crucial: Liberar cualquier lock adquirido.
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'BLOQUEO DE MOTOR [1451]: Integridad Referencial Estricta detectada. La base de datos impidió la eliminación física porque existen vínculos en tablas del sistema (FK) no contempladas en la validación de negocio.'; 
    END;

    /* [1.2] Handler Genérico (Catch-All Exception)
       Objetivo: Capturar cualquier anomalía técnica (disco lleno, pérdida de conexión, etc.). */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; -- Reenvía el error original para ser logueado por el Backend.
    END;

    /* ========================================================================================
       BLOQUE 2: PROTOCOLO DE VALIDACIÓN PREVIA (FAIL FAST)
       Propósito: Identificar peticiones inválidas antes de comprometer recursos de servidor.
       ======================================================================================== */
    
    /* 2.1 Validación de Tipado e Integridad de Entrada:
       Un ID nulo o negativo es una anomalía de la aplicación cliente que no debe procesarse. */
    IF _Id_Modalidad IS NULL OR _Id_Modalidad <= 0 THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERROR DE PROTOCOLO [400]: El Identificador de Modalidad proporcionado es inválido o nulo.';
    END IF;

    /* ========================================================================================
       BLOQUE 3: INICIO DE TRANSACCIÓN Y SECUESTRO DE FILA (X-LOCK)
       Propósito: Aislar el registro objetivo para asegurar que la destrucción sea atómica.
       ======================================================================================== */
    START TRANSACTION;

    /* ----------------------------------------------------------------------------------------
       PASO 3.1: LECTURA CON BLOQUEO EXCLUSIVO (FOR UPDATE)
       
       Lógica Técnica:
       No basta con un SELECT simple. El uso de `FOR UPDATE` garantiza que:
       1. Si el registro existe, queda bloqueado para lectura/escritura de otros usuarios.
       2. Evitamos que otro Admin lo "use" para crear una capacitación mientras estamos 
          en medio del proceso de borrado.
       ---------------------------------------------------------------------------------------- */
    
    SELECT 1, `Nombre` 
    INTO v_Existe, v_Nombre_Modalidad
    FROM `Cat_Modalidad_Capacitacion`
    WHERE `Id_CatModalCap` = _Id_Modalidad
    LIMIT 1
    FOR UPDATE;

    /* ----------------------------------------------------------------------------------------
       PASO 3.2: VALIDACIÓN DE EXISTENCIA REAL (IDEMPOTENCIA DE BORRADO)
       Si v_Existe es NULL, el registro ya no existe (pudo ser borrado por otro Admin en paralelo).
       ---------------------------------------------------------------------------------------- */
    IF v_Existe IS NULL THEN
        ROLLBACK; -- Liberamos la transacción.
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [404]: La Modalidad que intenta eliminar no existe en el catálogo (probablemente ya fue purgada).';
    END IF;

    /* ========================================================================================
       BLOQUE 4: ANÁLISIS FORENSE DE IMPACTO (HISTORICAL DEPENDENCY SCAN)
       Propósito: Validar que el registro no tenga rastro histórico en la base de datos operativa.
       ======================================================================================== */

    /* ----------------------------------------------------------------------------------------
       PASO 4.1: ESCANEO DE LA TABLA DE HECHOS (`DatosCapacitaciones`)
       
       Justificación Forense:
       La tabla `DatosCapacitaciones` es el corazón de la operación. Cualquier vínculo aquí 
       significa que la modalidad fue parte de un proceso de negocio.
       
       Regla Diamante:
       Se utiliza un escaneo TOTAL. No filtramos por `Activo = 1`. 
       Incluso si el curso hijo está borrado lógicamente, la relación física FK persiste en la BD.
       Borrar el padre causaría un error de integridad referencial insalvable.
       ---------------------------------------------------------------------------------------- */
    
    SELECT COUNT(*) INTO v_Referencias_Historicas
    FROM `DatosCapacitaciones`
    WHERE `Fk_Id_CatModalCap` = _Id_Modalidad;

    /* ----------------------------------------------------------------------------------------
       PASO 4.2: EVALUACIÓN DEL CANDADO DE INTEGRIDAD
       Si el contador es mayor a cero, el registro es INBORRABLE.
       ---------------------------------------------------------------------------------------- */
    IF v_Referencias_Historicas > 0 THEN
        
        ROLLBACK; -- Cancelamos la destrucción. Liberamos los bloqueos de fila.
        
        /* Construimos un mensaje explicativo que guíe al administrador hacia la solución correcta */
        SET @ErrorMsg = CONCAT('BLOQUEO DE INTEGRIDAD [409]: Imposible eliminar físicamente la Modalidad "', v_Nombre_Modalidad, '". Se detectaron ', v_Referencias_Historicas, ' registros históricos que dependen de este identificador. Para proteger la integridad de los reportes y auditorías, utilice la opción de "DESACTIVAR" (Baja Lógica) en su lugar.');
        
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = @ErrorMsg;
    END IF;

    /* ========================================================================================
       BLOQUE 5: EJECUCIÓN DE LA PURGA (HARD DELETE)
       Propósito: Eliminar físicamente la fila una vez superados todos los controles de seguridad.
       ======================================================================================== */
    
    /* Si el flujo de ejecución alcanza este punto, el sistema ha certificado bajo lock que:
       1. El registro existe.
       2. El registro es "VIRGEN" (Sin descendencia ni historial).
       3. No hay riesgos de orfandad de datos. */
       
    DELETE FROM `Cat_Modalidad_Capacitacion`
    WHERE `Id_CatModalCap` = _Id_Modalidad;

    /* ========================================================================================
       BLOQUE 6: CONFIRMACIÓN DE OPERACIÓN Y DESCARGA DE RESPUESTA
       Propósito: Sellar los cambios en el disco y notificar al cliente.
       ======================================================================================== */
    
    /* El comando COMMIT:
       1. Hace permanentes los cambios en los platos del disco duro.
       2. Genera la entrada final en el REDO LOG de la base de datos.
       3. Libera el bloqueo exclusivo (X-Lock), permitiendo que el espacio sea reutilizado por InnoDB. */
    COMMIT;

    /* Retornamos el contrato de salida estructurado para la interfaz de usuario. */
    SELECT 
        CONCAT('ÉXITO: La Modalidad "', v_Nombre_Modalidad, '" ha sido eliminada permanentemente y todos sus recursos han sido liberados.') AS Mensaje,
        'ELIMINACION_FISICA_COMPLETA' AS Accion,
        _Id_Modalidad AS Id_Eliminado,
        NOW() AS Timestamp_Ejecucion;

END$$

DELIMITER ;