USE `PICADE`;

/* ------------------------------------------------------------------------------------------------------ */
/* CREACION DE VISTAS Y PROCEDIMIENTOS DE ALMACENADO PARA LA BASE DE DATOS*/
/* ------------------------------------------------------------------------------------------------------ */

/* ======================================================================================================
   1. VIEW: Vista_Regimenes
   ======================================================================================================
   1. OBJETIVO TÉCNICO Y DE NEGOCIO
   --------------------------------
   Esta vista implementa la **Capa de Abstracción de Datos** (DAL) para la entidad "Regímenes de Trabajo".
   Su propósito es desacoplar la estructura física de la base de datos (nombres de columnas, tipos de datos)
   de la capa de presentación (Frontend) y lógica de negocio.

   Actúa como la **Interfaz Canónica** de lectura. El Frontend nunca debe consultar la tabla 
   `Cat_Regimenes_Trabajo` directamente; siempre debe consumir esta vista.

   2. ARQUITECTURA DE DATOS (PATRÓN DE PROYECCIÓN)
   -----------------------------------------------
   Al ser una Entidad Raíz (Root Entity) dentro del modelo entidad-relación (no tiene llaves foráneas 
   hacia padres), esta vista no requiere JOINs complejos. Sin embargo, su complejidad radica en la 
   **Normalización Semántica**:
   
   - Renombramiento de Llaves (Aliasing): Transforma `Id_CatRegimen` a `Id_Regimen` para mantener un 
     estándar de nomenclatura consistente en todos los endpoints del API (json: { id_regimen: 1 }).
   
   - Exposición de Auditoría: Proyecta los timestamps (`created_at`, `updated_at`) para permitir 
     la trazabilidad de cambios sin exponer lógica interna de la base de datos.

   3. GESTIÓN DE INTEGRIDAD Y NULOS
   --------------------------------
   - Campo `Codigo`: Dado que la carga histórica de datos permite valores NULL en el código, esta vista
     devuelve el valor crudo (`raw`). 
     * Razón de Diseño: No se utiliza `COALESCE` aquí para permitir que el Frontend detecte explícitamente 
       la ausencia de código (NULL) y decida si mostrar un placeholder ("S/C") o dejar el campo vacío, 
       manteniendo la vista agnóstica a la UI.

   4. VISIBILIDAD DE ESTATUS (LÓGICA DE BORRADO)
   ---------------------------------------------
   - La vista expone **TODO el universo de datos** (Activos e Inactivos).
   - Razón: Los módulos de administración requieren ver registros "eliminados lógicamente" (`Activo = 0`) 
     para permitir operaciones de auditoría o reactivación. El filtrado de "Solo Activos" es responsabilidad 
     del consumidor (WHERE Estatus_Regimen = 1).

   5. DICCIONARIO DE DATOS (ESPECIFICACIÓN DE SALIDA)
   --------------------------------------------------
   [Bloque A: Identidad del Registro]
   - Id_Regimen:          (INT) Identificador único y llave primaria.
   - Codigo_Regimen:      (VARCHAR) Clave corta organizacional (ej: 'CONF', 'PLANTA'). Puede ser NULL.
   - Nombre_Regimen:      (VARCHAR) Denominación oficial y única del régimen.
   
   [Bloque B: Información Descriptiva]
   - Descripcion_Regimen: (VARCHAR) Detalles extendidos sobre las implicaciones del régimen.

   [Bloque C: Control y Auditoría]
   - Estatus_Regimen:     (TINYINT) Bandera booleana: 1 = Operativo/Visible, 0 = Baja Lógica/Oculto.
   - created_at:          (DATETIME) Marca de tiempo de la creación inicial.
   - updated_at:          (DATETIME) Marca de tiempo de la última modificación.
   ====================================================================================================== */

-- DROP VIEW IF EXISTS `PICADE`.`Vista_Regimenes`;

CREATE OR REPLACE
    ALGORITHM = UNDEFINED 
    SQL SECURITY DEFINER
VIEW `PICADE`.`Vista_Regimenes` AS
    SELECT 
        /* -----------------------------------------------------------------------------------
           BLOQUE 1: IDENTIDAD Y CLAVES
           Estandarización de nombres para el consumo del API/Frontend.
           ----------------------------------------------------------------------------------- */
        `Reg`.`Id_CatRegimen`            AS `Id_Regimen`,
        `Reg`.`Codigo`                   AS `Codigo_Regimen`,
        `Reg`.`Nombre`                   AS `Nombre_Regimen`,

        /* -----------------------------------------------------------------------------------
           BLOQUE 2: DETALLES INFORMATIVOS
           Información complementaria no crítica para la integridad referencial.
           ----------------------------------------------------------------------------------- */
         -- `Reg`.`Descripcion`              AS `Descripcion_Regimen`,

        /* -----------------------------------------------------------------------------------
           BLOQUE 3: METADATOS DE CONTROL DE CICLO DE VIDA
           El campo 'Activo' se renombra a 'Estatus_Regimen' para mayor claridad semántica.
           ----------------------------------------------------------------------------------- */
        `Reg`.`Activo`                   AS `Estatus_Regimen`
        
        /* -----------------------------------------------------------------------------------
           BLOQUE 4: AUDITORÍA DEL SISTEMA
           Campos necesarios para logs de cambios y ordenamiento cronológico.
           ----------------------------------------------------------------------------------- */
        -- `Reg`.`created_at`,
        -- `Reg`.`updated_at`

    FROM
        `PICADE`.`Cat_Regimenes_Trabajo` `Reg`;

/* ============================================================================================
   PROCEDIMIENTO: SP_RegistrarRegimen
   ============================================================================================ 
   1. OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   --------------------------------------
   Gestionar el alta de un nuevo "Régimen de Trabajo" (ej: Planta, Transitorio, Confianza) en el
   Catálogo Corporativo. Este procedimiento actúa como una **Capa de Lógica de Negocio** en la base
   de datos, asegurando que solo datos completos, íntegros y únicos sean persistidos.

   2. REGLAS DE VALIDACIÓN ESTRICTA (HARD CONSTRAINTS)
   ---------------------------------------------------
   A) INTEGRIDAD DE DATOS (NOT NULL / NOT EMPTY):
      - Principio: "Basura que entra, basura que sale". Se prohíbe terminantemente el ingreso de
        cadenas vacías o espacios en blanco.
      - Alcance: Los campos `Código`, `Nombre` y `Descripción` son MANDATORIOS.
      - Acción: Si algún campo llega vacío tras la sanitización (`TRIM`), se aborta la operación
        con un error de validación (SQLSTATE 45000) antes de iniciar cualquier transacción.

   B) IDENTIDAD UNÍVOCA (DOBLE FACTOR):
      - Unicidad por CÓDIGO: No pueden existir dos regímenes con la clave 'CONF'.
      - Unicidad por NOMBRE: No pueden existir dos regímenes llamados 'CONFIANZA'.
      - Resolución de Conflictos: Se verifica primero el Código (Identificador fuerte) y luego
        el Nombre (Identificador semántico).

   3. ESTRATEGIA DE PERSISTENCIA Y CONCURRENCIA (ACID & RACE CONDITIONS)
   ---------------------------------------------------------------------
   A) BLOQUEO PESIMISTA (PESSIMISTIC LOCKING):
      - Se utiliza `SELECT ... FOR UPDATE` durante las verificaciones de existencia.
      - Justificación: Esto "serializa" las transacciones concurrentes sobre el mismo registro,
        evitando que dos administradores intenten crear o reactivar el mismo régimen al mismo
        milisegundo, garantizando lecturas consistentes.

   B) RECUPERACIÓN DE CONCURRENCIA (RE-RESOLVE PATTERN):
      - A pesar de los bloqueos, existe una ventana infinitesimal donde un `INSERT` concurrente
        podría generar un error nativo `1062 (Duplicate Key)`.
      - Solución: Se implementa un `HANDLER` específico que captura este error, revierte la
        transacción fallida y ejecuta una rutina de búsqueda para devolver el registro que
        "ganó la carrera", simulando un éxito para el usuario final (Transparencia).

   C) AUTOSANACIÓN (SELF-HEALING / SOFT DELETE RECOVERY):
      - Si el sistema detecta que el régimen que se intenta crear YA EXISTE pero fue eliminado
        lógicamente (`Activo = 0`), no lanza error.
      - Acción: Ejecuta una reactivación automática (`UPDATE Activo = 1`) y actualiza los datos
        descriptivos con la nueva información proporcionada.

   RESULTADO (OUTPUT CONTRACT)
   ---------------------------
   Retorna un resultset con:
     - Mensaje: Feedback descriptivo para la UI.
     - Id_Regimen: La llave primaria del recurso (creado o recuperado).
     - Accion: Enumerador de estado ('CREADA', 'REACTIVADA', 'REUSADA').
   ============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_RegistrarRegimen`$$
CREATE PROCEDURE `SP_RegistrarRegimen`(
    /* -----------------------------------------------------------------
       PARÁMETROS DE ENTRADA (INPUTS)
       Todos se asumen como Strings crudos que requieren sanitización.
       ----------------------------------------------------------------- */
    IN _Codigo      VARCHAR(50),   -- OBLIGATORIO: Clave única interna (ej: 'PLA')
    IN _Nombre      VARCHAR(255),  -- OBLIGATORIO: Nombre descriptivo (ej: 'Planta')
    IN _Descripcion VARCHAR(255)   -- OBLIGATORIO: Detalle operativo
)
SP: BEGIN
    /* ========================================================================================
       BLOQUE 0: DECLARACIÓN DE VARIABLES DE ENTORNO
       ======================================================================================== */
    
    /* Variables de Persistencia (Snapshot del registro en BD) */
    DECLARE v_Id_Regimen INT DEFAULT NULL;
    DECLARE v_Activo     TINYINT(1) DEFAULT NULL;
    
    /* Variables de Validación de Integridad (Para chequeos cruzados) */
    DECLARE v_Nombre_Existente VARCHAR(255) DEFAULT NULL;
    DECLARE v_Codigo_Existente VARCHAR(50) DEFAULT NULL;
    
    /* Bandera de Control de Flujo (Semáforo para errores SQL) */
    DECLARE v_Dup TINYINT(1) DEFAULT 0;

    /* ========================================================================================
       BLOQUE 1: HANDLERS (MANEJO ROBUSTO DE EXCEPCIONES)
       ======================================================================================== */
    
    /* 1.1 HANDLER DE DUPLICIDAD (Error 1062)
       Objetivo: Capturar colisiones de Unique Key en el INSERT.
       Acción: No abortar. Encender bandera v_Dup = 1 para activar la rutina de recuperación. */
    DECLARE CONTINUE HANDLER FOR 1062 SET v_Dup = 1;

    /* 1.2 HANDLER GENÉRICO (SQLEXCEPTION)
       Objetivo: Capturar fallos de infraestructura (Disco lleno, Conexión perdida, Syntax Error).
       Acción: Abortar inmediatamente, deshacer cambios (ROLLBACK) y propagar el error (RESIGNAL). */
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
       para facilitar la validación booleana. */
    SET _Codigo      = NULLIF(TRIM(_Codigo), '');
    SET _Nombre      = NULLIF(TRIM(_Nombre), '');
    SET _Descripcion = NULLIF(TRIM(_Descripcion), '');

    /* 2.2 VALIDACIÓN DE OBLIGATORIEDAD (Business Rule: NO VACÍOS)
       Validamos antes de abrir transacción para ahorrar recursos del servidor. */
    
    IF _Codigo IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN: El CÓDIGO del Régimen es obligatorio.';
    END IF;

    IF _Nombre IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN: El NOMBRE del Régimen es obligatorio.';
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
    SET v_Id_Regimen = NULL;

    /* BLOQUEO PESIMISTA: 'FOR UPDATE' asegura que nadie modifique este registro mientras lo leemos */
    SELECT `Id_CatRegimen`, `Nombre`, `Activo` 
    INTO v_Id_Regimen, v_Nombre_Existente, v_Activo
    FROM `Cat_Regimenes_Trabajo`
    WHERE `Codigo` = _Codigo
    LIMIT 1
    FOR UPDATE;

    /* ESCENARIO A: EL CÓDIGO YA EXISTE */
    IF v_Id_Regimen IS NOT NULL THEN
        
        /* Validación de Integridad Cruzada:
           Regla: Si el código existe, el Nombre TAMBIÉN debe coincidir.
           Fallo: Si el código es igual pero el nombre es diferente, es un CONFLICTO DE DATOS. */
        IF v_Nombre_Existente <> _Nombre THEN
            SIGNAL SQLSTATE '45000' 
                SET MESSAGE_TEXT = 'ERROR DE CONFLICTO: El CÓDIGO ingresado ya existe pero pertenece a un Régimen con diferente NOMBRE. Verifique sus datos.';
        END IF;

        /* Sub-Escenario A.1: Existe pero está INACTIVO (Baja Lógica) -> REACTIVAR */
        IF v_Activo = 0 THEN
            UPDATE `Cat_Regimenes_Trabajo`
            SET `Activo` = 1,
                `Descripcion` = _Descripcion, -- Actualizamos la descripción con el dato fresco
                `updated_at` = NOW()
            WHERE `Id_CatRegimen` = v_Id_Regimen;
            
            COMMIT; 
            SELECT 'Régimen reactivado y actualizado exitosamente.' AS Mensaje, v_Id_Regimen AS Id_Regimen, 'REACTIVADA' AS Accion; 
            LEAVE SP;
        
        /* Sub-Escenario A.2: Existe y está ACTIVO -> IDEMPOTENCIA (Reportar éxito sin cambios) */
        ELSE
            COMMIT; 
            SELECT 'El Régimen ya se encuentra registrado y activo.' AS Mensaje, v_Id_Regimen AS Id_Regimen, 'REUSADA' AS Accion; 
            LEAVE SP;
        END IF;
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 3.2: RESOLUCIÓN DE IDENTIDAD POR NOMBRE (PRIORIDAD SECUNDARIA)
       Si llegamos aquí, el CÓDIGO es libre. Ahora verificamos si el NOMBRE ya está en uso.
       ---------------------------------------------------------------------------------------- */
    SET v_Id_Regimen = NULL;

    SELECT `Id_CatRegimen`, `Codigo`, `Activo`
    INTO v_Id_Regimen, v_Codigo_Existente, v_Activo
    FROM `Cat_Regimenes_Trabajo`
    WHERE `Nombre` = _Nombre
    LIMIT 1
    FOR UPDATE;

    /* ESCENARIO B: EL NOMBRE YA EXISTE */
    IF v_Id_Regimen IS NOT NULL THEN
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
             UPDATE `Cat_Regimenes_Trabajo` 
             SET `Codigo` = _Codigo, `updated_at` = NOW() 
             WHERE `Id_CatRegimen` = v_Id_Regimen;
        END IF;

        /* Reactivación si estaba inactivo */
        IF v_Activo = 0 THEN
            UPDATE `Cat_Regimenes_Trabajo` 
            SET `Activo` = 1, `Descripcion` = _Descripcion, `updated_at` = NOW() 
            WHERE `Id_CatRegimen` = v_Id_Regimen;
            
            COMMIT; 
            SELECT 'Régimen reactivado exitosamente (encontrado por Nombre).' AS Mensaje, v_Id_Regimen AS Id_Regimen, 'REACTIVADA' AS Accion; 
            LEAVE SP;
        END IF;

        COMMIT; 
        SELECT 'El Régimen ya existe (validado por Nombre).' AS Mensaje, v_Id_Regimen AS Id_Regimen, 'REUSADA' AS Accion; 
        LEAVE SP;
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 3.3: PERSISTENCIA (INSERCIÓN FÍSICA)
       Si pasamos todas las validaciones y no encontramos coincidencias, es un registro NUEVO.
       ---------------------------------------------------------------------------------------- */
    SET v_Dup = 0; -- Reiniciamos bandera de error
    
    INSERT INTO `Cat_Regimenes_Trabajo`
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

    /* Verificación de Éxito: Si v_Dup sigue en 0, el INSERT funcionó */
    IF v_Dup = 0 THEN
        COMMIT; 
        SELECT 'Régimen registrado exitosamente.' AS Mensaje, LAST_INSERT_ID() AS Id_Regimen, 'CREADA' AS Accion; 
        LEAVE SP;
    END IF;

    /* ========================================================================================
       BLOQUE 4: RUTINA DE RECUPERACIÓN DE CONCURRENCIA (RE-RESOLVE)
       ========================================================================================
       Si el flujo llega aquí, v_Dup = 1.
       Diagnóstico: Ocurrió una "Race Condition". Otro usuario insertó el registro milisegundos
       antes que nosotros, disparando el Error 1062 (Duplicate Key).
       
       Acción: Recuperar el ID del registro ganador y devolverlo como si fuera nuestro. */
    
    ROLLBACK; -- Limpiamos la transacción fallida
    
    START TRANSACTION; -- Iniciamos nueva lectura limpia
    
    SET v_Id_Regimen = NULL;
    
    /* Intentamos recuperar por CÓDIGO (la restricción más fuerte) */
    SELECT `Id_CatRegimen`, `Activo`, `Nombre`
    INTO v_Id_Regimen, v_Activo, v_Nombre_Existente
    FROM `Cat_Regimenes_Trabajo`
    WHERE `Codigo` = _Codigo
    LIMIT 1
    FOR UPDATE;
    
    IF v_Id_Regimen IS NOT NULL THEN
        /* Validación de Seguridad: Confirmar que no sea un falso positivo */
        IF v_Nombre_Existente <> _Nombre THEN
             SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR CRÍTICO DE SISTEMA: Concurrencia detectada con conflicto de datos (Códigos iguales, Nombres distintos).';
        END IF;

        /* Reactivación (si el ganador estaba inactivo) */
        IF v_Activo = 0 THEN
            UPDATE `Cat_Regimenes_Trabajo` 
            SET `Activo` = 1, `Descripcion` = _Descripcion, `updated_at` = NOW() 
            WHERE `Id_CatRegimen` = v_Id_Regimen;
            
            COMMIT; 
            SELECT 'Régimen reactivado (recuperado tras concurrencia).' AS Mensaje, v_Id_Regimen AS Id_Regimen, 'REACTIVADA' AS Accion; 
            LEAVE SP;
        END IF;
        
        /* Éxito por Reuso */
        COMMIT; 
        SELECT 'Régimen ya existía (reusado tras concurrencia).' AS Mensaje, v_Id_Regimen AS Id_Regimen, 'REUSADA' AS Accion; 
        LEAVE SP;
    END IF;

    /* Si falló por 1062 pero no encontramos el registro ni por Código (Caso extremo) */
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA: Fallo de concurrencia no recuperable (Error Fantasma). Contacte a Soporte.';

END$$

DELIMITER ;

/* ============================================================================================
   SECCIÓN: CONSULTAS ESPECÍFICAS (PARA EDICIÓN / DETALLE)
   ============================================================================================
   Estas rutinas son clave para la UX. No solo devuelven el dato pedido, sino todo el 
   contexto jerárquico necesario para que el formulario de edición se autocomplete.
   ============================================================================================ */

/* ============================================================================================
   PROCEDIMIENTO: SP_ConsultarRegimenEspecifico
   ============================================================================================
   AUTOR: Arquitectura de Datos / Gemini
   FECHA: 2026

   1. OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   --------------------------------------
   Recuperar la "Ficha Técnica" completa y sin procesar (Raw Data) de un Régimen de Contratación
   específico, identificado por su llave primaria.

   CASOS DE USO (CONTEXTO DE UI):
   A) PRECARGA DE FORMULARIO DE EDICIÓN (UPDATE):
      - El sistema necesita los valores exactos que están en la base de datos para llenar los
        inputs del formulario (Nombre, Código, Descripción).
      - Es crítico recibir `NULL` real en el Código (si no existe) en lugar de un texto formateado
        como "S/C" (que vendría de una Vista), para que el input aparezca vacío y no con texto basura.

   B) VISUALIZACIÓN DE DETALLE (MODAL / CARD):
      - Mostrar la información extendida y los metadatos de auditoría (creación/actualización)
        que no suelen aparecer en la tabla principal (Grid) por cuestiones de espacio.

   2. ARQUITECTURA DE DATOS (SINGLE SOURCE OF TRUTH)
   -------------------------------------------------
   A diferencia de los listados masivos que consumen `Vista_Regimenes`, este procedimiento ataca
   directamente a la tabla física `Cat_Regimenes_Trabajo`.

   JUSTIFICACIÓN TÉCNICA (POR QUÉ NO USAR LA VISTA):
   - Integridad de Edición: Las vistas suelen aplicar transformaciones cosméticas (formatos de fecha,
     concatenaciones, manejo de nulos visuales). Para editar, requerimos la fidelidad absoluta del dato.
   - Desacoplamiento: Si en el futuro la Vista cambia para mostrar "Código - Nombre" concatenado,
     este cambio rompería el formulario de edición. Al usar el SP directo, garantizamos estabilidad.

   3. ESTRATEGIA DE SEGURIDAD Y VALIDACIÓN (DEFENSIVE PROGRAMMING)
   ---------------------------------------------------------------
   - Fail Fast: Se validan los parámetros de entrada antes de tocar el disco duro.
   - Verificación de Existencia: Se comprueba si el registro existe antes de devolver un resultset.
     Esto permite diferenciar entre "No hay datos" (Resultset vacío) y "Error de Petición" (ID no existe),
     permitiendo al Frontend mostrar mensajes de error más precisos (404 Not Found).

   4. DICCIONARIO DE DATOS (OUTPUT)
   --------------------------------
   Retorna una única fila conteniendo:
     - [Identidad]: Id_CatRegimen, Codigo, Nombre.
     - [Detalle]: Descripción.
     - [Control]: Activo (Vital para saber si el botón de acción debe decir "Activar" o "Desactivar").
     - [Auditoría]: created_at, updated_at.
   ============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ConsultarRegimenEspecifico`$$
CREATE PROCEDURE `SP_ConsultarRegimenEspecifico`(
    IN _Id_Regimen INT -- Identificador único del Régimen a consultar
)
BEGIN
    /* ========================================================================================
       BLOQUE 1: VALIDACIÓN DE ENTRADA (DEFENSIVE PROGRAMMING)
       Objetivo: Asegurar que el parámetro recibido cumpla con los requisitos mínimos
       antes de intentar cualquier operación de lectura. Evita inyecciones de valores absurdos.
       ======================================================================================== */
    IF _Id_Regimen IS NULL OR _Id_Regimen <= 0 THEN
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'ERROR DE SISTEMA: El Identificador del Régimen es inválido (Debe ser un entero positivo).';
    END IF;

    /* ========================================================================================
       BLOQUE 2: VERIFICACIÓN DE EXISTENCIA (FAIL FAST STRATEGY)
       Objetivo: Validar que el recurso realmente exista en la base de datos.
       
       NOTA DE DISEÑO (VISIBILIDAD):
       - No filtramos por `Activo = 1`. 
       - Razón: El administrador debe poder consultar (y eventualmente editar) registros que 
         están dados de baja lógica para poder reactivarlos o auditar su historia.
         Ocultar los inactivos aquí impediría su restauración.
       ======================================================================================== */
    IF NOT EXISTS (SELECT 1 FROM `Cat_Regimenes_Trabajo` WHERE `Id_CatRegimen` = _Id_Regimen) THEN
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'ERROR DE NEGOCIO: El Régimen solicitado no existe en el catálogo o fue eliminado físicamente.';
    END IF;

    /* ========================================================================================
       BLOQUE 3: CONSULTA PRINCIPAL (DATA RETRIEVAL)
       Objetivo: Retornar el objeto de datos completo y puro (Raw Data).
       ======================================================================================== */
    SELECT 
        /* --- GRUPO A: IDENTIDAD DEL REGISTRO --- */
        `Id_CatRegimen`,
        
        /* --- GRUPO B: DATOS EDITABLES --- */
        /* Nota: El Frontend debe estar preparado para recibir NULL en 'Codigo' 
           y renderizarlo como un campo de texto vacío. */
        `Codigo`,       
        `Nombre`,
        `Descripcion`,
        
        /* --- GRUPO C: METADATOS DE CONTROL DE CICLO DE VIDA --- */
        /* Este valor (0 o 1) determina el estado del "Switch" o "Toggle" en la UI */
        `Activo`,       
        
        /* --- GRUPO D: AUDITORÍA DE SISTEMA --- */
        `created_at`,
        `updated_at`
        
    FROM `Cat_Regimenes_Trabajo`
    WHERE `Id_CatRegimen` = _Id_Regimen
    LIMIT 1; /* Buena práctica: Asegura al optimizador que se detenga tras el primer hallazgo */

END$$

DELIMITER ;

/* ============================================================================================
   SECCIÓN: LISTADOS PARA DROPDOWNS (SOLO REGISTROS ACTIVOS)
   ============================================================================================
   Estas rutinas son consumidas por los formularios de captura (Frontend).
   Su objetivo es ofrecer al usuario solo las opciones válidas y vigentes.
   ============================================================================================ */
/* ============================================================================================
   PROCEDIMIENTO: SP_ListarRegimenesActivos
   ============================================================================================
   AUTOR: Arquitectura de Datos / Gemini
   FECHA: 2026

   1. OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   --------------------------------------
   Proveer un endpoint de datos ligero y altamente optimizado para alimentar elementos de 
   Interfaz de Usuario (UI) tipo "Selector", "Dropdown" o "ComboBox".
   
   Este procedimiento es la única fuente autorizada para desplegar las opciones de contratación
   disponibles en los formularios de:
     - Alta de Personal (Info_Personal).
     - Filtros de Búsqueda en Reportes de RRHH.
     - Asignación de Plazas.

   2. REGLAS DE NEGOCIO Y FILTRADO (THE VIGENCY CONTRACT)
   ------------------------------------------------------
   A) FILTRO DE VIGENCIA ESTRICTO (HARD FILTER):
      - Regla: La consulta aplica obligatoriamente la cláusula `WHERE Activo = 1`.
      - Justificación Operativa: Un Régimen marcado como inactivo (Baja Lógica) representa una 
        modalidad de contratación obsoleta o derogada. Permitir su selección en un nuevo registro 
        generaría inconsistencias legales y administrativas ("Contratar a alguien bajo un esquema extinto").
      - Seguridad: Este filtro se aplica a nivel de base de datos, no se delega al Frontend.

   B) ORDENAMIENTO COGNITIVO (USABILITY):
      - Regla: Los resultados se ordenan alfabéticamente por `Nombre` (A-Z).
      - Justificación: Reduce la carga cognitiva del usuario. Buscar "Transitorio" es más rápido 
        en una lista ordenada alfabéticamente que en una ordenada por ID de inserción.

   3. ARQUITECTURA DE DATOS Y OPTIMIZACIÓN (PERFORMANCE)
   -----------------------------------------------------
   - Proyección Mínima (Payload Reduction):
     A diferencia de las vistas de administración, este SP NO devuelve columnas auditoras 
     (`created_at`, `updated_at`) ni descriptivas largas (`Descripcion`).
     
     Solo devuelve las 3 columnas esenciales para construir un elemento `<option>` HTML:
       1. ID (Value): Para la integridad referencial.
       2. Nombre (Label): Para la lectura humana.
       3. Código (Hint): Para la identificación rápida visual.
     
     Esto reduce el tráfico de red (Network Overhead) cuando el catálogo crece.

   4. DICCIONARIO DE DATOS (OUTPUT JSON SCHEMA)
   --------------------------------------------
   Retorna un array de objetos con la siguiente estructura:
     - `Id_CatRegimen`: (INT) Llave Primaria. Se usará como el `value` del selector.
     - `Codigo`:        (VARCHAR) Clave corta (ej: 'CONF'). Útil para mostrar entre paréntesis.
     - `Nombre`:        (VARCHAR) Texto principal (ej: 'Personal de Confianza').
   ============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ListarRegimenesActivos`$$
CREATE PROCEDURE `SP_ListarRegimenesActivos`()
BEGIN
    /* ========================================================================================
       BLOQUE ÚNICO: CONSULTA DE SELECCIÓN
       No se requieren parámetros de entrada ni validaciones complejas, ya que es una lectura
       directa sobre una entidad raíz (sin dependencias jerárquicas activas).
       ======================================================================================== */
    
    SELECT 
        /* IDENTIFICADOR ÚNICO (PK)
           Este es el dato que el Frontend enviará de regreso al servidor al guardar el formulario. */
        `Id_CatRegimen`, 
        
        /* CLAVE MNEMOTÉCNICA
           Dato auxiliar para UI avanzada (ej: badges o hints). Puede ser NULL. */
        `Codigo`, 
        
        /* DESCRIPTOR HUMANO
           El texto principal que el usuario leerá en la lista desplegable. */
        `Nombre`

    FROM 
        `Cat_Regimenes_Trabajo`
    
    /* ----------------------------------------------------------------------------------------
       FILTRO DE SEGURIDAD OPERATIVA
       Ocultamos todo lo que no sea "1" (Activo). 
       Esto previene errores de "dedo" al seleccionar opciones obsoletas.
       ---------------------------------------------------------------------------------------- */
    WHERE 
        `Activo` = 1
    
    /* ----------------------------------------------------------------------------------------
       OPTIMIZACIÓN DE UX
       El ordenamiento se hace en el motor de BD (que es más rápido indexando) 
       para que el navegador no tenga que reordenar con JavaScript.
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
   PROCEDIMIENTO: SP_ListarRegimenesAdmin
   ============================================================================================
    1. OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   --------------------------------------
   Proveer el inventario maestro y completo de los "Regímenes de Contratación" (Cat_Regimenes_Trabajo)
   para alimentar el Grid Principal del Módulo de Administración.
   
   Este endpoint permite al Administrador visualizar la totalidad de los datos (históricos y actuales)
   para realizar tareas de:
     - Auditoría: Revisar qué tipos de contratos han existido.
     - Mantenimiento: Detectar errores ortográficos o de captura en nombres/códigos.
     - Gestión de Ciclo de Vida: Reactivar regímenes que fueron dados de baja por error.

   2. DIFERENCIA CRÍTICA CON EL LISTADO OPERATIVO (DROPDOWN)
   ---------------------------------------------------------
   Es vital distinguir este SP de `SP_ListarRegimenesActivos`:
   
   A) SP_ListarRegimenesActivos (Dropdown): 
      - Enfoque: Operatividad.
      - Filtro: Estricto `WHERE Activo = 1`.
      - Objetivo: Evitar que se asignen regímenes obsoletos a nuevos empleados.
   
   B) SP_ListarRegimenesAdmin (ESTE):
      - Enfoque: Gestión y Auditoría.
      - Filtro: NINGUNO (Visibilidad Total).
      - Objetivo: Permitir al Admin ver registros inactivos (`Estatus = 0`) para poder editarlos
        o reactivarlos. Ocultar los inactivos aquí impediría su recuperación.

   3. ARQUITECTURA DE DATOS (VIEW CONSUMPTION PATTERN)
   ---------------------------------------------------
   Este procedimiento implementa el patrón de "Abstracción de Lectura" al consumir la vista
   `Vista_Regimenes` en lugar de la tabla física.

   Ventajas Técnicas:
   - Desacoplamiento: El Grid del Frontend se acopla a los nombres de columnas de la Vista 
     (ej: `Estatus_Regimen`) y no a los de la tabla física (`Activo`). Si la tabla cambia,
     solo ajustamos la Vista y este SP sigue funcionando sin cambios.
   - Estandarización: La vista ya maneja la lógica de presentación de nulos (aunque en este caso
     se decidió dejar el Código como raw data, la estructura está lista para evolucionar).

   4. ESTRATEGIA DE ORDENAMIENTO (UX PRIORITY)
   -------------------------------------------
   El ordenamiento no es arbitrario; está diseñado para la eficiencia administrativa:
     1. Prioridad Operativa (`Estatus_Regimen` DESC): 
        Los registros VIGENTES (1) aparecen en la parte superior. Los obsoletos (0) se van al fondo.
        Esto mantiene la información relevante accesible inmediatamente sin scrollear.
     2. Orden Alfabético (`Nombre_Regimen` ASC): 
        Dentro de cada grupo de estatus, se ordenan A-Z para facilitar la búsqueda visual rápida.

   5. DICCIONARIO DE DATOS (OUTPUT)
   --------------------------------
   Retorna el contrato de datos definido en `Vista_Regimenes`:
     - [Identidad]: Id_Regimen, Codigo_Regimen, Nombre_Regimen.
     - [Detalle]: Descripcion_Regimen.
     - [Control]: Estatus_Regimen (1 = Activo, 0 = Inactivo).
     - [Auditoría]: created_at, updated_at.
   ============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ListarRegimenesAdmin`$$
CREATE PROCEDURE `SP_ListarRegimenesAdmin`()
BEGIN
    /* ========================================================================================
       BLOQUE ÚNICO: CONSULTA MAESTRA
       No requiere validaciones de entrada ya que es una consulta global sobre el catálogo.
       ======================================================================================== */
    
    SELECT 
        /* Proyección total de la Vista Maestra */
        * FROM 
        `Vista_Regimenes`
    
    /* ========================================================================================
       ORDENAMIENTO ESTRATÉGICO
       Optimizamos la presentación para el usuario administrador.
       ======================================================================================== */
    ORDER BY 
        `Estatus_Regimen` DESC,  -- 1º: Muestra primero lo que está vivo (Operativo)
        `Nombre_Regimen` ASC;    -- 2º: Ordena alfabéticamente para facilitar búsqueda visual

END$$

DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_EditarRegimen
   ============================================================================================
   1. OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   --------------------------------------
   Modificar los atributos fundamentales de un "Régimen de Contratación" existente, asegurando
   la persistencia de datos íntegros y válidos.
   
   Este procedimiento impone reglas de negocio más estrictas que la propia estructura de la tabla:
   aunque la base de datos permita nulos, la lógica de negocio para la EDICIÓN exige que el
   Código y el Nombre siempre tengan valor.

   2. REGLAS DE VALIDACIÓN ESTRICTA (HARD CONSTRAINTS)
   ---------------------------------------------------
   A) OBLIGATORIEDAD DE CAMPOS:
      - Regla: "Todo o Nada". No se permite guardar cambios si el Código o el Nombre están vacíos.
      - Justificación: En la operación diaria, un Régimen sin código puede causar errores en 
        interfaces con sistemas legados (nómina). Por tanto, al editar, se fuerza la captura.

   B) UNICIDAD GLOBAL (EXCLUSIÓN PROPIA):
      - Se verifica que el nuevo Código no pertenezca a OTRO registro (`Id <> _Id_Regimen`).
      - Se verifica que el nuevo Nombre no pertenezca a OTRO registro.
      - Es perfectamente legal "actualizarse a sí mismo" (ej: cambiar solo la descripción).

   3. ARQUITECTURA DE CONCURRENCIA (DETERMINISTIC LOCKING PATTERN)
   ---------------------------------------------------------------
   Para prevenir **Deadlocks** (Abrazos Mortales) en un entorno donde múltiples administradores
   podrían estar intercambiando nombres o códigos entre registros simultáneamente, se implementa
   una estrategia de BLOQUEO DETERMINÍSTICO:

   - Paso 1: Identificación. Antes de bloquear nada, identificamos qué filas están involucradas:
       a) La fila que queremos editar (Target).
       b) La fila que (posiblemente) ya tiene el Código que queremos usar (Conflicto A).
       c) La fila que (posiblemente) ya tiene el Nombre que queremos usar (Conflicto B).
   
   - Paso 2: Ordenamiento. Ordenamos estos IDs de menor a mayor.
   
   - Paso 3: Ejecución de Bloqueos. Aplicamos `FOR UPDATE` siguiendo estrictamente ese orden.
     Al adquirir los recursos siempre en la misma secuencia (Ascendente), eliminamos matemáticamente
     la posibilidad de un ciclo de espera (Deadlock).

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
     - Id_Regimen: Identificador del recurso manipulado.
   ============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_EditarRegimen`$$
CREATE PROCEDURE `SP_EditarRegimen`(
    /* -----------------------------------------------------------------
       PARÁMETROS DE ENTRADA (INPUTS)
       Recibimos los datos crudos del formulario.
       ----------------------------------------------------------------- */
    IN _Id_Regimen   INT,           -- OBLIGATORIO: ID del registro a modificar
    IN _Nuevo_Codigo VARCHAR(50),   -- OBLIGATORIO: Nueva Clave (ej: 'CONF')
    IN _Nuevo_Nombre VARCHAR(255),  -- OBLIGATORIO: Nuevo Nombre (ej: 'Confianza')
    IN _Nueva_Desc   VARCHAR(255)   -- OPCIONAL: Descripción detallada
)
SP: BEGIN
    /* ========================================================================================
       BLOQUE 0: DECLARACIÓN DE VARIABLES DE ESTADO
       ======================================================================================== */
    
    /* Snapshots: Almacenan el estado actual del registro antes de la edición */
    DECLARE v_Cod_Act  VARCHAR(50)  DEFAULT NULL;
    DECLARE v_Nom_Act  VARCHAR(255) DEFAULT NULL;
    DECLARE v_Desc_Act VARCHAR(255) DEFAULT NULL;

    /* IDs para la Estrategia de Bloqueo Determinístico */
    DECLARE v_Id_Conflicto_Cod INT DEFAULT NULL; -- ID del dueño actual del Código deseado
    DECLARE v_Id_Conflicto_Nom INT DEFAULT NULL; -- ID del dueño actual del Nombre deseado

    /* Variables auxiliares para el algoritmo de ordenamiento de locks */
    DECLARE v_L1 INT DEFAULT NULL;
    DECLARE v_L2 INT DEFAULT NULL;
    DECLARE v_L3 INT DEFAULT NULL;
    DECLARE v_Min INT DEFAULT NULL;
    DECLARE v_Existe INT DEFAULT NULL;

    /* Bandera de Error Crítico (Concurrency Collision) */
    DECLARE v_Dup TINYINT(1) DEFAULT 0;

    /* Variables para Diagnóstico de Errores */
    DECLARE v_Campo_Error VARCHAR(20) DEFAULT NULL;
    DECLARE v_Id_Error    INT DEFAULT NULL;

    /* ========================================================================================
       BLOQUE 1: HANDLERS (SEGURIDAD Y ROBUSTEZ)
       ======================================================================================== */
    
    /* 1.1 HANDLER DE DUPLICIDAD (Error 1062)
       Captura colisiones de Unique Key en el último milisegundo (Race Condition). */
    DECLARE CONTINUE HANDLER FOR 1062 SET v_Dup = 1;

    /* 1.2 HANDLER GENÉRICO (SQLEXCEPTION)
       Captura fallos técnicos (Desconexión, Disco lleno, Sintaxis). Aborta todo. */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; 
    END;

    /* ========================================================================================
       BLOQUE 2: SANITIZACIÓN Y VALIDACIÓN (FAIL FAST)
       ======================================================================================== */
    
    /* 2.1 LIMPIEZA DE DATOS
       Eliminamos espacios basura. Si queda vacío, se convierte a NULL. */
    SET _Nuevo_Codigo = NULLIF(TRIM(_Nuevo_Codigo), '');
    SET _Nuevo_Nombre = NULLIF(TRIM(_Nuevo_Nombre), '');
    SET _Nueva_Desc   = NULLIF(TRIM(_Nueva_Desc), '');

    /* 2.2 VALIDACIÓN DE OBLIGATORIEDAD (REGLA DE NEGOCIO ESTRICTA)
       El formulario exige que Código y Nombre existan. */
    
    IF _Id_Regimen IS NULL OR _Id_Regimen <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA: Identificador de Régimen inválido.';
    END IF;

    IF _Nuevo_Codigo IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN: El CÓDIGO es obligatorio para la edición.';
    END IF;

    IF _Nuevo_Nombre IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN: El NOMBRE es obligatorio para la edición.';
    END IF;
    
    /* La descripción es opcional, pero si es obligatoria según tu regla "Todo es Obligatorio", descomentar: */
    
    IF _Nueva_Desc IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN: La DESCRIPCIÓN es obligatoria.';
    END IF;
    
    /* ========================================================================================
       BLOQUE 3: ESTRATEGIA DE BLOQUEO DETERMINÍSTICO (PREVENCIÓN DE DEADLOCKS)
       ======================================================================================== */
    START TRANSACTION;

    /* ----------------------------------------------------------------------------------------
       PASO 3.1: RECONOCIMIENTO (LECTURA SUCIA / NO BLOQUEANTE)
       Primero "miramos" el panorama para saber qué filas están involucradas.
       ---------------------------------------------------------------------------------------- */
    
    /* A) Identificar el registro objetivo */
    SELECT `Codigo`, `Nombre` INTO v_Cod_Act, v_Nom_Act
    FROM `Cat_Regimenes_Trabajo` WHERE `Id_CatRegimen` = _Id_Regimen;

    IF v_Cod_Act IS NULL AND v_Nom_Act IS NULL THEN 
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO: El Régimen que intenta editar no existe.';
    END IF;

    /* B) Identificar posible conflicto de CÓDIGO (¿Alguien más ya tiene mi nuevo código?) */
    IF _Nuevo_Codigo <> IFNULL(v_Cod_Act, '') THEN
        SELECT `Id_CatRegimen` INTO v_Id_Conflicto_Cod 
        FROM `Cat_Regimenes_Trabajo` 
        WHERE `Codigo` = _Nuevo_Codigo AND `Id_CatRegimen` <> _Id_Regimen LIMIT 1;
    END IF;

    /* C) Identificar posible conflicto de NOMBRE (¿Alguien más ya tiene mi nuevo nombre?) */
    IF _Nuevo_Nombre <> v_Nom_Act THEN
        SELECT `Id_CatRegimen` INTO v_Id_Conflicto_Nom 
        FROM `Cat_Regimenes_Trabajo` 
        WHERE `Nombre` = _Nuevo_Nombre AND `Id_CatRegimen` <> _Id_Regimen LIMIT 1;
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 3.2: EJECUCIÓN DE BLOQUEOS ORDENADOS
       Ordenamos los IDs (Propio, ConflictoCod, ConflictoNom) y bloqueamos de menor a mayor.
       Esto garantiza que todos los procesos adquieran recursos en la misma dirección.
       ---------------------------------------------------------------------------------------- */
    
    /* Llenamos el pool de IDs a bloquear */
    SET v_L1 = _Id_Regimen;
    SET v_L2 = v_Id_Conflicto_Cod;
    SET v_L3 = v_Id_Conflicto_Nom;

    /* Normalización: Eliminar duplicados en las variables (ej: si conflicto Cod y Nom son el mismo ID) */
    IF v_L2 = v_L1 THEN SET v_L2 = NULL; END IF;
    IF v_L3 = v_L1 THEN SET v_L3 = NULL; END IF;
    IF v_L3 = v_L2 THEN SET v_L3 = NULL; END IF;

    /* --- RONDA 1: Bloquear el ID Menor --- */
    SET v_Min = NULL;
    IF v_L1 IS NOT NULL THEN SET v_Min = v_L1; END IF;
    IF v_L2 IS NOT NULL AND (v_Min IS NULL OR v_L2 < v_Min) THEN SET v_Min = v_L2; END IF;
    IF v_L3 IS NOT NULL AND (v_Min IS NULL OR v_L3 < v_Min) THEN SET v_Min = v_L3; END IF;

    IF v_Min IS NOT NULL THEN
        SELECT 1 INTO v_Existe FROM `Cat_Regimenes_Trabajo` WHERE `Id_CatRegimen` = v_Min FOR UPDATE;
        /* Marcar como procesado */
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
        SELECT 1 INTO v_Existe FROM `Cat_Regimenes_Trabajo` WHERE `Id_CatRegimen` = v_Min FOR UPDATE;
        IF v_L1 = v_Min THEN SET v_L1 = NULL; END IF;
        IF v_L2 = v_Min THEN SET v_L2 = NULL; END IF;
        IF v_L3 = v_Min THEN SET v_L3 = NULL; END IF;
    END IF;

    /* --- RONDA 3: Bloquear el ID Mayor --- */
    SET v_Min = NULL;
    IF v_L1 IS NOT NULL THEN SET v_Min = v_L1; END IF;
    IF v_L2 IS NOT NULL AND (v_Min IS NULL OR v_L2 < v_Min) THEN SET v_Min = v_L2; END IF;
    IF v_L3 IS NOT NULL AND (v_Min IS NULL OR v_L3 < v_Min) THEN SET v_Min = v_L3; END IF;

    IF v_Min IS NOT NULL THEN
        SELECT 1 INTO v_Existe FROM `Cat_Regimenes_Trabajo` WHERE `Id_CatRegimen` = v_Min FOR UPDATE;
    END IF;

    /* ========================================================================================
       BLOQUE 4: LÓGICA DE NEGOCIO (BAJO PROTECCIÓN DE LOCKS)
       ======================================================================================== */

    /* 4.1 RE-LECTURA AUTORIZADA
       Ahora que tenemos el bloqueo, leemos el estado definitivo. */
    SELECT `Codigo`, `Nombre`, `Descripcion` 
    INTO v_Cod_Act, v_Nom_Act, v_Desc_Act
    FROM `Cat_Regimenes_Trabajo` 
    WHERE `Id_CatRegimen` = _Id_Regimen; 

    IF v_Nom_Act IS NULL THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR CRÍTICO: El registro desapareció durante la transacción.';
    END IF;

    /* 4.2 DETECCIÓN DE IDEMPOTENCIA (SIN CAMBIOS)
       Comparamos si los datos nuevos son matemáticamente iguales a los actuales. 
       Usamos <=> (Null-Safe Equality) para manejar correctamente los NULLs. */
    IF (v_Cod_Act <=> _Nuevo_Codigo) 
       AND (v_Nom_Act = _Nuevo_Nombre) 
       AND (v_Desc_Act <=> _Nueva_Desc) THEN
        
        COMMIT;
        SELECT 'No se detectaron cambios en la información.' AS Mensaje, 'SIN_CAMBIOS' AS Accion;
        LEAVE SP;
    END IF;

    /* 4.3 VALIDACIÓN FINAL DE UNICIDAD (PRE-UPDATE CHECK)
       Verificamos si existen duplicados. Al tener los registros bloqueados, esta verificación
       es 100% fiable (salvo inserciones fantasma, cubiertas por el Handler 1062). */
    
    /* Validación por CÓDIGO */
    SET v_Id_Error = NULL;
    SELECT `Id_CatRegimen` INTO v_Id_Error FROM `Cat_Regimenes_Trabajo` 
    WHERE `Codigo` = _Nuevo_Codigo AND `Id_CatRegimen` <> _Id_Regimen LIMIT 1;
    
    IF v_Id_Error IS NOT NULL THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE DUPLICIDAD: El CÓDIGO ya pertenece a otro Régimen.';
    END IF;

    /* Validación por NOMBRE */
    SET v_Id_Error = NULL;
    SELECT `Id_CatRegimen` INTO v_Id_Error FROM `Cat_Regimenes_Trabajo` 
    WHERE `Nombre` = _Nuevo_Nombre AND `Id_CatRegimen` <> _Id_Regimen LIMIT 1;
    
    IF v_Id_Error IS NOT NULL THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE DUPLICIDAD: El NOMBRE ya pertenece a otro Régimen.';
    END IF;

    /* ========================================================================================
       BLOQUE 5: PERSISTENCIA (UPDATE)
       ======================================================================================== */
    
    SET v_Dup = 0; -- Resetear bandera de error

    UPDATE `Cat_Regimenes_Trabajo`
    SET `Codigo`      = _Nuevo_Codigo,
        `Nombre`      = _Nuevo_Nombre,
        `Descripcion` = _Nueva_Desc,
        `updated_at`  = NOW()
    WHERE `Id_CatRegimen` = _Id_Regimen;

    /* ========================================================================================
       BLOQUE 6: MANEJO DE COLISIÓN TARDÍA (RECUPERACIÓN DE ERROR 1062)
       ========================================================================================
       Si v_Dup = 1, significa que otro usuario insertó un registro conflictivo en el 
       instante exacto entre nuestro SELECT de validación y el UPDATE. */
    IF v_Dup = 1 THEN
        ROLLBACK;
        
        /* Diagnóstico Post-Mortem para el usuario */
        SET v_Campo_Error = 'DESCONOCIDO';
        SET v_Id_Error = NULL;

        /* ¿Fue conflicto de Código? */
        SELECT `Id_CatRegimen` INTO v_Id_Error FROM `Cat_Regimenes_Trabajo` 
        WHERE `Codigo` = _Nuevo_Codigo AND `Id_CatRegimen` <> _Id_Regimen LIMIT 1;
        
        IF v_Id_Error IS NOT NULL THEN
            SET v_Campo_Error = 'CODIGO';
        ELSE
            /* Entonces fue conflicto de Nombre */
            SELECT `Id_CatRegimen` INTO v_Id_Error FROM `Cat_Regimenes_Trabajo` 
            WHERE `Nombre` = _Nuevo_Nombre AND `Id_CatRegimen` <> _Id_Regimen LIMIT 1;
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
    
    SELECT 'Régimen actualizado correctamente.' AS Mensaje, 'ACTUALIZADA' AS Accion;

END$$

DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_CambiarEstatusRegimen
   ============================================================================================
   1. OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   --------------------------------------
   Gestionar el Ciclo de Vida (Lifecycle) de un "Régimen de Contratación" mediante el mecanismo
   de "Baja Lógica" (Soft Delete).

   Este procedimiento permite al Administrador:
     A) DESACTIVAR (Ocultar): Marcar un régimen como obsoleto para que no aparezca en los
        selectores de "Nuevo Empleado", evitando asignaciones futuras de contratos extintos.
     B) REACTIVAR (Mostrar): Recuperar un régimen histórico para volver a utilizarlo.

   2. ARQUITECTURA DE INTEGRIDAD (EL CANDADO DESCENDENTE)
   ------------------------------------------------------
   El mayor riesgo de desactivar un catálogo maestro es la "Orfandad Operativa".
   
   Regla Crítica: "No puedes derogar una ley si hay ciudadanos amparados por ella".
   
   - Validación: Si se solicita DESACTIVAR (`_Nuevo_Estatus = 0`), el sistema consulta
     proactivamente la tabla de Personal (`Info_Personal`).
   - Condición de Bloqueo: Si existe AL MENOS UN empleado con estatus `Activo = 1` asignado
     a este Régimen, la operación se bloquea inmediatamente.
   - Justificación: Permitir esta acción rompería los reportes de Nómina y RRHH, generando
     empleados "activos" bajo un régimen "inexistente".

   3. ESTRATEGIA DE CONCURRENCIA (BLOQUEO PESIMISTA / ACID)
   --------------------------------------------------------
   - Problema: ¿Qué pasa si un Admin A desactiva el régimen justo en el milisegundo en que
     un Admin B está dando de alta a un empleado con ese régimen?
   - Solución: Se aplica `SELECT ... FOR UPDATE` al inicio de la transacción.
   - Efecto: Esto "congela" la fila del Régimen. Cualquier otra transacción que intente
     usar este registro deberá esperar a que terminemos de decidir su destino.

   4. IDEMPOTENCIA (OPTIMIZACIÓN DE RECURSOS)
   ------------------------------------------
   - Antes de escribir en disco, verificamos si el registro ya tiene el estatus solicitado.
   - Si `Activo_Actual == Nuevo_Estatus`, el SP retorna éxito sin realizar el UPDATE.
   - Beneficio: Ahorro de I/O, reducción de crecimiento del Log de Transacciones y preservación
     del timestamp `updated_at` (no se modifica si no hubo un cambio real).

   RESULTADO (OUTPUT CONTRACT)
   ---------------------------
   Retorna un dataset informativo:
     - Mensaje: Feedback de éxito o explicación del bloqueo.
     - Activo_Anterior / Activo_Nuevo: Para que el Frontend actualice el estado visual del "Switch".
   ============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_CambiarEstatusRegimen`$$
CREATE PROCEDURE `SP_CambiarEstatusRegimen`(
    IN _Id_Regimen    INT,     -- ID del Régimen a modificar
    IN _Nuevo_Estatus TINYINT  -- 1 = Activar (Visible), 0 = Desactivar (Oculto)
)
BEGIN
    /* ========================================================================================
       BLOQUE 0: VARIABLES DE ESTADO Y CONTROL
       ======================================================================================== */
    
    /* Variables para capturar la "foto" del registro antes de modificarlo */
    DECLARE v_Existe        INT DEFAULT NULL;
    DECLARE v_Activo_Actual TINYINT(1) DEFAULT NULL;
    
    /* Variable auxiliar para verificar dependencias en tablas hijas (Empleados) */
    DECLARE v_Dependencias  INT DEFAULT NULL;

    /* ========================================================================================
       BLOQUE 1: HANDLERS (MANEJO DE ERRORES TÉCNICOS)
       ======================================================================================== */
    
    /* Handler Genérico: Ante cualquier fallo SQL (Deadlock, Conexión, Sintaxis), 
       garantizamos que la transacción se revierta (ROLLBACK) para no dejar datos sucios. */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; 
    END;

    /* ========================================================================================
       BLOQUE 2: VALIDACIONES PREVIAS (DEFENSIVE PROGRAMMING)
       ======================================================================================== */
    
    /* Validación de Integridad de Entrada: Evitamos procesar basura. */
    IF _Id_Regimen IS NULL OR _Id_Regimen <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA: El ID del Régimen es inválido.';
    END IF;

    /* Validación de Dominio: El estatus solo puede ser binario. */
    IF _Nuevo_Estatus NOT IN (0, 1) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA: El Estatus proporcionado es inválido (solo se permite 0 o 1).';
    END IF;

    /* ========================================================================================
       BLOQUE 3: INICIO DE TRANSACCIÓN Y LECTURA BLOQUEANTE
       ======================================================================================== */
    START TRANSACTION;

    /* ----------------------------------------------------------------------------------------
       PASO 3.1: OBTENCIÓN DE SNAPSHOT CON BLOQUEO (FOR UPDATE)
       - Buscamos el registro.
       - Adquirimos un candado de escritura (Write Lock) sobre la fila.
       - Esto asegura la serialización: Nadie más puede tocar este régimen hasta que terminemos.
       ---------------------------------------------------------------------------------------- */
    SELECT 1, `Activo` 
    INTO v_Existe, v_Activo_Actual
    FROM `Cat_Regimenes_Trabajo` 
    WHERE `Id_CatRegimen` = _Id_Regimen 
    LIMIT 1 
    FOR UPDATE;

    /* Si el puntero es NULL, el registro no existe */
    IF v_Existe IS NULL THEN 
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO: El Régimen solicitado no existe en el catálogo.'; 
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 3.2: VERIFICACIÓN DE IDEMPOTENCIA (SIN CAMBIOS)
       Si el usuario pide "Activar" y ya está activo, salimos inmediatamente.
       ---------------------------------------------------------------------------------------- */
    IF v_Activo_Actual = _Nuevo_Estatus THEN
        
        COMMIT; -- Liberamos el bloqueo inmediatamente
        
        SELECT CASE 
            WHEN _Nuevo_Estatus = 1 THEN 'Sin cambios: El Régimen ya se encontraba Activo.' 
            ELSE 'Sin cambios: El Régimen ya se encontraba Inactivo.' 
        END AS Mensaje,
        v_Activo_Actual AS Activo_Anterior,
        _Nuevo_Estatus AS Activo_Nuevo;
        
    ELSE
        /* ====================================================================================
           BLOQUE 4: APLICACIÓN DE REGLAS DE NEGOCIO (SI HAY CAMBIO DE ESTADO)
           ==================================================================================== */

        /* ------------------------------------------------------------------------------------
           PASO 4.1: REGLA DE DESACTIVACIÓN (CANDADO DE INTEGRIDAD REFERENCIAL)
           Solo ejecutamos esto si _Nuevo_Estatus es 0 (Apagar).
           ------------------------------------------------------------------------------------ */
        IF _Nuevo_Estatus = 0 THEN
            
            SET v_Dependencias = NULL;
            
            /* BÚSQUEDA DE DEPENDENCIAS ACTIVAS:
               Consultamos la tabla `Info_Personal`.
               CRITERIO ESTRICTO: Solo nos preocupan los empleados con `Activo = 1`.
               (Los empleados dados de baja en el pasado no impiden desactivar el régimen hoy). */
            
            SELECT 1 INTO v_Dependencias
            FROM `Info_Personal`
            WHERE `Fk_Id_CatRegimen` = _Id_Regimen
              AND `Activo` = 1 -- Solo empleados vigentes
            LIMIT 1;

            /* SI SE ENCUENTRA AL MENOS UN EMPLEADO... BLOQUEO TOTAL. */
            IF v_Dependencias IS NOT NULL THEN
                SIGNAL SQLSTATE '45000' 
                    SET MESSAGE_TEXT = 'BLOQUEO DE INTEGRIDAD: No es posible desactivar este Régimen porque existen EMPLEADOS ACTIVOS asignados a él. Debe reasignar o dar de baja al personal antes de continuar.';
            END IF;
        END IF;

        /* ------------------------------------------------------------------------------------
           PASO 4.2: EJECUCIÓN DEL UPDATE (PERSISTENCIA)
           Si pasamos los candados, aplicamos el cambio.
           ------------------------------------------------------------------------------------ */
        UPDATE `Cat_Regimenes_Trabajo` 
        SET `Activo` = _Nuevo_Estatus, 
            `updated_at` = NOW() -- Auditoría: Registramos cuándo ocurrió el cambio
        WHERE `Id_CatRegimen` = _Id_Regimen;
        
        /* ------------------------------------------------------------------------------------
           PASO 4.3: CONFIRMACIÓN
           ------------------------------------------------------------------------------------ */
        COMMIT; -- Se hacen efectivos los cambios y se libera la fila
        
        /* ------------------------------------------------------------------------------------
           PASO 4.4: RESPUESTA AL FRONTEND
           Devolvemos el estado final para que la UI se actualice correctamente.
           ------------------------------------------------------------------------------------ */
        SELECT CASE 
            WHEN _Nuevo_Estatus = 1 THEN 'Régimen Reactivado Exitosamente.' 
            ELSE 'Régimen Desactivado (Baja Lógica) Correctamente.' 
        END AS Mensaje,
        v_Activo_Actual AS Activo_Anterior,
        _Nuevo_Estatus AS Activo_Nuevo;
        
    END IF;

END$$

DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_EliminarRegimenFisico
   ============================================================================================
   AUTOR: Arquitectura de Datos / Gemini
   FECHA: 2026

   1. OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   --------------------------------------
   Ejecutar la eliminación DEFINITIVA, FÍSICA e IRREVERSIBLE de un registro en el catálogo
   de "Regímenes de Contratación" (`Cat_Regimenes_Trabajo`).

   CONTEXTO DE USO Y ADVERTENCIAS:
   - Naturaleza: Operación Destructiva (`DELETE`).
   - Caso de Uso Permitido: Únicamente para tareas de depuración administrativa inmediata
     (ej: "Acabo de crear por error el régimen 'Pru3ba' y quiero borrarlo ya").
   - Restricción: NO debe usarse para la gestión operativa histórica. Si un régimen dejó de
     usarse (ej: "Planta Extinta"), se debe usar el procedimiento de Baja Lógica (Desactivar)
     para no romper los expedientes de los empleados que tuvieron ese régimen.

   2. ESTRATEGIA DE INTEGRIDAD REFERENCIAL (DEFENSA EN CAPAS)
   ----------------------------------------------------------
   Para garantizar que la base de datos nunca quede con "Registros Huérfanos" (empleados apuntando
   a un régimen que ya no existe), implementamos dos niveles de seguridad:

   CAPA A: VALIDACIÓN DE NEGOCIO PROACTIVA (Mejora de UX)
   - Antes de intentar borrar, el SP escanea explícitamente la tabla hija `Info_Personal`.
   - Criterio Estricto: Si existe CUALQUIER historial (sea un empleado activo o uno dado de baja
     hace 10 años) vinculado a este régimen, la operación se aborta.
   - Beneficio: Permite devolver un mensaje de error semántico ("No se puede borrar porque hay
     historial") en lugar de un error técnico de SQL.

   CAPA B: VALIDACIÓN DE MOTOR REACTIVA (Database Constraint - Safety Net)
   - Si existiera una tabla oculta o futura que olvidamos validar manualmente, el motor InnoDB
     bloqueará el `DELETE` disparando el error `1451` (Foreign Key Constraint Fails).
   - El SP captura este error mediante un `HANDLER`, hace Rollback y entrega un mensaje controlado,
     evitando que el sistema colapse o muestre pantallas de error crípticas.

   3. ATOMICIDAD Y CONCURRENCIA
   ----------------------------
   - La operación se envuelve en una transacción.
   - El motor aplica un bloqueo exclusivo (X-Lock) sobre la fila durante el borrado, asegurando
     que nadie más pueda leer o vincular este régimen mientras se destruye.

   RESULTADO (OUTPUT)
   ------------------
   Retorna un dataset informativo:
     - Mensaje: Confirmación de éxito.
     - Accion: 'ELIMINADA'.
     - Id_Regimen: El ID del recurso purgado.
   ============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_EliminarRegimenFisico`$$
CREATE PROCEDURE `SP_EliminarRegimenFisico`(
    /* -----------------------------------------------------------------
       PARÁMETROS DE ENTRADA
       ----------------------------------------------------------------- */
    IN _Id_Regimen INT -- Identificador único del registro a destruir
)
BEGIN
    /* ========================================================================================
       BLOQUE 0: VARIABLES DE DIAGNÓSTICO
       ======================================================================================== */
    /* Variable para almacenar el resultado de la búsqueda de dependencias */
    DECLARE v_Dependencias INT DEFAULT NULL;

    /* ========================================================================================
       BLOQUE 1: HANDLERS (MANEJO ROBUSTO DE EXCEPCIONES)
       ======================================================================================== */
    
    /* 1.1 HANDLER DE INTEGRIDAD REFERENCIAL (Error 1451)
       Objetivo: Actuar como "paracaídas" o red de seguridad final.
       Escenario: Intentamos borrar, pero el motor de BD detecta que hay una FK activa apuntando
       a este registro desde otra tabla (quizás una que no validamos en el Bloque 3).
       Acción: Revertir todo y avisar al usuario que el sistema protegió el dato. */
    DECLARE EXIT HANDLER FOR 1451 
    BEGIN 
        ROLLBACK; 
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'BLOQUEO DE INTEGRIDAD (SISTEMA): El registro está blindado por la base de datos porque existen referencias en otras tablas históricas no depuradas.'; 
    END;

    /* 1.2 HANDLER GENÉRICO (SQLEXCEPTION)
       Objetivo: Capturar fallos de infraestructura (Disco, Conexión). */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; 
    END;

    /* ========================================================================================
       BLOQUE 2: VALIDACIONES PREVIAS (FAIL FAST)
       ======================================================================================== */
    
    /* 2.1 Validación de Input */
    IF _Id_Regimen IS NULL OR _Id_Regimen <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA: Identificador inválido.';
    END IF;

    /* 2.2 Validación de Existencia
       Verificamos si el registro existe antes de verificar dependencias. */
    IF NOT EXISTS (SELECT 1 FROM `Cat_Regimenes_Trabajo` WHERE `Id_CatRegimen` = _Id_Regimen) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO: El Régimen que intenta eliminar no existe.';
    END IF;

    /* ========================================================================================
       BLOQUE 3: CANDADO DE NEGOCIO (VALIDACIÓN PROACTIVA DE DEPENDENCIAS)
       ======================================================================================== */
    
    /* OBJETIVO: Proteger el Historial Laboral.
       Buscamos en la tabla `Info_Personal`.
       CRÍTICO: NO filtramos por `Activo = 1`. 
       Razón: Si un empleado trabajó bajo el régimen "Planta 1990" y hoy está dado de baja (Inactivo),
       ese historial sigue siendo sagrado. Si borramos el régimen, el expediente de ese empleado
       se corrompe (FK apunta a NULL o error). Por eso validamos TODO el universo. */
    
    SELECT 1 INTO v_Dependencias
    FROM `Info_Personal`
    WHERE `Fk_Id_CatRegimen` = _Id_Regimen
    LIMIT 1;

    /* SI ENCONTRAMOS AL MENOS UN REGISTRO ASOCIADO... */
    IF v_Dependencias IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'BLOQUEO DE NEGOCIO: No es posible eliminar este Régimen porque existen expedientes de PERSONAL (Activos o Históricos) asociados a él. La eliminación física rompería el historial laboral. Utilice la opción "Desactivar" en su lugar.';
    END IF;

    /* ========================================================================================
       BLOQUE 4: EJECUCIÓN DESTRUCTIVA (ZONA CRÍTICA)
       ======================================================================================== */
    START TRANSACTION;

    /* Ejecución del Borrado Físico.
       En este punto, el motor adquiere un bloqueo exclusivo sobre la fila. */
    DELETE FROM `Cat_Regimenes_Trabajo` 
    WHERE `Id_CatRegimen` = _Id_Regimen;

    /* Si llegamos aquí sin que salten los Handlers (especialmente el 1451),
       significa que el registro estaba limpio y fue destruido correctamente. */
    COMMIT;

    /* ========================================================================================
       BLOQUE 5: CONFIRMACIÓN
       ======================================================================================== */
    SELECT 
        'Registro eliminado permanentemente de la base de datos.' AS Mensaje, 
        'ELIMINADA' AS Accion,
        _Id_Regimen AS Id_Regimen;

END$$

DELIMITER ;