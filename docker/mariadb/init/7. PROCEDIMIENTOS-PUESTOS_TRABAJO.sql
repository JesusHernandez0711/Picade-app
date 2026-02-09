USE `PICADE`;

/* ------------------------------------------------------------------------------------------------------ */
/* CREACION DE VISTAS Y PROCEDIMIENTOS DE ALMACENADO PARA LA BASE DE DATOS*/
/* ------------------------------------------------------------------------------------------------------ */

/* ======================================================================================================
   VIEW  Vista_Puestos  
   ======================================================================================================
   
   1. OBJETIVO TÉCNICO Y DE NEGOCIO (BUSINESS GOAL)
   ------------------------------------------------
   Esta vista implementa la **Capa de Abstracción de Lectura** (Data Abstraction Layer) para la entidad
   "Puestos de Trabajo" (`Cat_Puestos_Trabajo`).
   
   Su función es actuar como la interfaz pública y canónica para todos los consumidores de datos
   (API Backend, Reportes de BI, Dashboards Frontend), desacoplando la estructura física de la tabla
   de su representación lógica.

   2. ARQUITECTURA DE DATOS (PATRÓN DE PROYECCIÓN)
   -----------------------------------------------
   Al ser una Entidad de Catálogo Simple (Lookup Table) en la estructura actual (sin dependencias 
   jerárquicas directas a nivel de base de datos), esta vista no requiere JOINs relacionales complejos.
   
   Su valor reside en la **Normalización Semántica**:
   
   - Aliasing (Renombramiento): Transforma nombres técnicos de columnas (`Id_CatPuesto`) a nombres
     de negocio (`Id_Puesto`) para mantener la consistencia con el resto del sistema JSON 
     (ej: { id_puesto: 1, nombre_puesto: "Medico" }).
   
   - Visibilidad Total: Proyecta tanto registros Activos como Inactivos para permitir la gestión
     administrativa completa (Auditoría, Corrección y Reactivación).

   3. GESTIÓN DE INTEGRIDAD Y NULOS
   --------------------------------
   - Campo `Codigo`: Se expone tal cual (Raw Data). Si es NULL, el consumidor (Frontend) decide
     si muestra un badge de "S/C" (Sin Código) o lo oculta.
   - Campo `Descripcion`: Se incluye para dar contexto operativo sobre las responsabilidades del cargo.

   4. CONTEXTO DE USO
   ------------------
   Esta vista alimentará principalmente:
   - Grid de Administración de Puestos (CRUD).
   - Selectores de "Asignación de Puesto" en el Módulo de Personal (`Info_Personal`).
   - Reportes de "Plantilla Laboral por Categoría".

   5. DICCIONARIO DE DATOS (OUTPUT CONTRACT)
   -----------------------------------------
   [Bloque A: Identidad]
   - Id_Puesto:          (INT) Llave Primaria única del catálogo.
   - Codigo_Puesto:      (VARCHAR) Clave corta interna (ej: 'SUP-HSE-01'). Puede ser NULL.
   - Nombre_Puesto:      (VARCHAR) Denominación oficial del cargo (ej: 'SUPERVISOR DE SEGURIDAD').

   [Bloque B: Detalle Operativo]
   - Descripcion_Puesto: (VARCHAR) Resumen de responsabilidades o alcance del cargo.

   [Bloque C: Control de Ciclo de Vida]
   - Estatus_Puesto:     (TINYINT) 1 = Vigente/Asignable, 0 = Obsoleto/Histórico (Baja Lógica).
   - created_at:         (DATETIME) Fecha de alta en el sistema.
   - updated_at:         (DATETIME) Última modificación o cambio de estatus.
   ====================================================================================================== */

-- DROP VIEW IF EXISTS `PICADE`.`Vista_Puestos`;

CREATE OR REPLACE
    ALGORITHM = UNDEFINED 
    SQL SECURITY DEFINER
VIEW `PICADE`.`Vista_Puestos` AS
    SELECT 
        /* -----------------------------------------------------------------------------------
           BLOQUE 1: IDENTIDAD Y CLAVES
           Estandarización de nombres para el consumo del API/Frontend.
           ----------------------------------------------------------------------------------- */
        `Pto`.`Id_CatPuesto`      AS `Id_Puesto`,
        `Pto`.`Codigo`            AS `Codigo_Puesto`,
        `Pto`.`Nombre`            AS `Nombre_Puesto`,

        /* -----------------------------------------------------------------------------------
           BLOQUE 2: DETALLES INFORMATIVOS
           Información descriptiva para tooltips o detalles expandidos en reportes.
           ----------------------------------------------------------------------------------- */
         -- `Pto`.`Descripcion`       AS `Descripcion_Puesto`,

        /* -----------------------------------------------------------------------------------
           BLOQUE 3: METADATOS DE CONTROL (ESTATUS)
           Mapeo semántico: 'Activo' -> 'Estatus_Puesto' para mayor claridad funcional.
           ----------------------------------------------------------------------------------- */
        `Pto`.`Activo`            AS `Estatus_Puesto`
        
        /* -----------------------------------------------------------------------------------
           BLOQUE 4: TRAZABILIDAD (AUDITORÍA)
           Fechas críticas para el ordenamiento cronológico en los Grids administrativos.
           (Descomentar si se requieren en el frontend, se dejan ocultas por defecto para ligereza)
           ----------------------------------------------------------------------------------- */
        -- `Pto`.`created_at`,
        -- `Pto`.`updated_at`

    FROM
        `PICADE`.`Cat_Puestos_Trabajo` `Pto`;

/* ====================================================================================================
   PROCEDIMIENTO: SP_RegistrarPuesto
   ====================================================================================================
   1. VISIÓN GENERAL Y OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   ----------------------------------------------------------------------------------------------------
   Este procedimiento implementa la lógica de ALTA TRANSACCIONAL para la entidad "Puesto de Trabajo"
   (`Cat_Puestos_Trabajo`). Su propósito es gestionar la creación de nuevos cargos en el catálogo
   corporativo, actuando como la única puerta de entrada para garantizar la calidad de los datos.

   2. REGLAS DE VALIDACIÓN ESTRICTA (HARD CONSTRAINTS)
   ----------------------------------------------------------------------------------------------------
   Para mantener un catálogo limpio y auditable, se aplican las siguientes restricciones de negocio:
   
     A) INTEGRIDAD DE DATOS (DATA COMPLETENESS):
        - El campo `Nombre` es el activo más valioso; no se permiten cadenas vacías o espacios.
        - El campo `Código` se exige como obligatorio en la capa de entrada (API Contract) para
          fomentar el orden, aunque el esquema de base de datos técnicamente permita nulos.

     B) IDENTIDAD UNÍVOCA DE DOBLE FACTOR (DUAL IDENTITY CHECK):
        - Unicidad por CÓDIGO: No pueden existir dos puestos con la clave 'PTO-001'.
        - Unicidad por NOMBRE: No pueden existir dos puestos con la denominación 'MÉDICO GENERAL'.
        - Resolución: El sistema verifica primero el Código (Identificador fuerte) y luego el Nombre
          (Identificador semántico).

   3. ESTRATEGIA DE PERSISTENCIA Y CONCURRENCIA (ACID COMPLIANCE)
   ----------------------------------------------------------------------------------------------------
   Este SP está diseñado para operar en entornos de alta concurrencia, utilizando patrones avanzados:

     A) BLOQUEO PESIMISTA (PESSIMISTIC LOCKING):
        - Utilizamos `SELECT ... FOR UPDATE` durante las verificaciones de existencia.
        - Efecto: Si dos administradores intentan crear el puesto "Supervisor" al mismo tiempo,
          la base de datos serializa las peticiones. El segundo usuario esperará a que el primero
          termine, evitando "Race Conditions" (Condiciones de Carrera).

     B) ENRIQUECIMIENTO DE DATOS (DATA ENRICHMENT):
        - Escenario: Existe el puesto "Secretaria" con Código NULL (dato heredado/legacy).
        - Acción: Si intentamos registrar "Secretaria" con el nuevo código "SEC-01", el sistema
          detecta la coincidencia por nombre y ACTUALIZA el código del registro existente en lugar
          de duplicarlo o rechazarlo.

     C) AUTOSANACIÓN (SELF-HEALING / SOFT DELETE RECOVERY):
        - Si el Puesto ya existe en la base de datos pero estaba dado de baja (`Activo = 0`),
          el sistema no lanza error. En su lugar, lo "resucita" (Reactiva) automáticamente y
          actualiza sus datos descriptivos.

     D) TOLERANCIA A FALLOS DE CONCURRENCIA (RE-RESOLVE PATTERN):
        - A pesar de los bloqueos, existe una ventana infinitesimal donde un INSERT concurrente
          podría generar un error nativo `1062 (Duplicate Key)`.
        - Solución: Implementamos un `HANDLER` que captura este error, revierte la transacción
          fallida y ejecuta una rutina de recuperación para devolver el registro que "ganó la carrera",
          simulando un éxito transparente para el usuario final.

   4. CONTRATO DE SALIDA (OUTPUT CONTRACT)
   ----------------------------------------------------------------------------------------------------
   Retorna un resultset de una sola fila (Single Row) con:
     - Mensaje (VARCHAR): Feedback descriptivo para la UI.
     - Id_Puesto (INT): La llave primaria del recurso (creado o recuperado).
     - Accion (VARCHAR): Enumerador de estado ('CREADA', 'REACTIVADA', 'REUSADA').
   ==================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_RegistrarPuesto`$$

CREATE PROCEDURE `SP_RegistrarPuesto`(
    /* -----------------------------------------------------------------
       PARÁMETROS DE ENTRADA (INPUTS)
       Recibimos los datos crudos del formulario. Se asumen cadenas de texto.
       ----------------------------------------------------------------- */
    IN _Codigo      VARCHAR(50),   -- OBLIGATORIO: Clave interna (ej: 'N34-A')
    IN _Nombre      VARCHAR(255),  -- OBLIGATORIO: Denominación del cargo
    IN _Descripcion VARCHAR(255)   -- OPCIONAL: Detalles de funciones
)
THIS_PROC: BEGIN
    
    /* ================================================================================================
       BLOQUE 0: DECLARACIÓN DE VARIABLES DE ENTORNO
       Propósito: Inicializar contenedores para almacenar el estado de los datos y banderas de control.
       ================================================================================================ */
    
    /* Variables de Persistencia (Snapshot): Almacenan la "foto" del registro si ya existe en la BD */
    DECLARE v_Id_Puesto INT DEFAULT NULL;
    DECLARE v_Activo    TINYINT(1) DEFAULT NULL;
    
    /* Variables para Validación Cruzada (Cross-Check): Para detectar conflictos de identidad */
    DECLARE v_Nombre_Existente VARCHAR(255) DEFAULT NULL;
    DECLARE v_Codigo_Existente VARCHAR(50) DEFAULT NULL;
    
    /* Bandera de Control de Flujo (Semáforo): Indica si ocurrió un error SQL controlado (ej: 1062) */
    DECLARE v_Dup TINYINT(1) DEFAULT 0;

    /* ================================================================================================
       BLOQUE 1: HANDLERS (MANEJO ROBUSTO DE EXCEPCIONES)
       Propósito: Garantizar que el SP nunca termine abruptamente sin limpiar la transacción.
       ================================================================================================ */
    
    /* 1.1 HANDLER DE DUPLICIDAD (Error MySQL 1062 - Duplicate Entry)
       Objetivo: Capturar colisiones de Unique Key en el INSERT final (nuestra red de seguridad).
       Estrategia: "Graceful Degradation". En lugar de abortar, encendemos la bandera v_Dup
       para activar la rutina de recuperación (Re-Resolve) más adelante. */
    DECLARE CONTINUE HANDLER FOR 1062 SET v_Dup = 1;

    /* 1.2 HANDLER GENÉRICO (SQLEXCEPTION)
       Objetivo: Capturar fallos de infraestructura (Disco lleno, Conexión perdida, Error de Sintaxis).
       Estrategia: Abortar inmediatamente, deshacer cambios (ROLLBACK) y propagar el error. */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; 
    END;

    /* ================================================================================================
       BLOQUE 2: SANITIZACIÓN Y VALIDACIÓN (FAIL FAST PATTERN)
       Propósito: Rechazar datos inválidos antes de consumir recursos de transacción.
       ================================================================================================ */
    
    /* 2.1 LIMPIEZA DE DATOS (TRIM & NULLIF)
       Eliminamos espacios en blanco al inicio/final. Si la cadena queda vacía, la convertimos a NULL
       para facilitar la validación booleana estricta. */
    SET _Codigo      = NULLIF(TRIM(_Codigo), '');
    SET _Nombre      = NULLIF(TRIM(_Nombre), '');
    SET _Descripcion = NULLIF(TRIM(_Descripcion), '');

    /* 2.2 VALIDACIÓN DE OBLIGATORIEDAD (Business Rule: NO VACÍOS)
       Regla de Negocio: Un Puesto sin nombre o código no es auditable ni funcional. */
    
    IF _Codigo IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN [400]: El CÓDIGO del Puesto es obligatorio.';
    END IF;

    IF _Nombre IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN [400]: El NOMBRE del Puesto es obligatorio.';
    END IF;
    
    /* Nota: La descripción es opcional, por lo que no validamos su nulidad. */

    /* ================================================================================================
       BLOQUE 3: LÓGICA DE NEGOCIO TRANSACCIONAL (CORE)
       Propósito: Ejecutar la lógica de búsqueda, validación y persistencia de forma atómica.
       ================================================================================================ */
    START TRANSACTION;

    /* ------------------------------------------------------------------------------------------------
       PASO 3.1: RESOLUCIÓN DE IDENTIDAD POR CÓDIGO (PRIORIDAD ALTA)
       
       Objetivo: Verificar si la clave única (_Codigo) ya está registrada en el sistema.
       Mecánica: Usamos `FOR UPDATE` para bloquear la fila encontrada. Esto asegura que nadie modifique
       este registro mientras nosotros decidimos qué hacer con él.
       ------------------------------------------------------------------------------------------------ */
    SET v_Id_Puesto = NULL; -- Reset de seguridad

    SELECT `Id_CatPuesto`, `Nombre`, `Activo` 
    INTO v_Id_Puesto, v_Nombre_Existente, v_Activo
    FROM `Cat_Puestos_Trabajo`
    WHERE `Codigo` = _Codigo
    LIMIT 1
    FOR UPDATE;

    /* ESCENARIO A: EL CÓDIGO YA EXISTE */
    IF v_Id_Puesto IS NOT NULL THEN
        
        /* Validación de Integridad Cruzada:
           Si el código existe, el Nombre TAMBIÉN debe coincidir.
           Si el código es igual pero el nombre es diferente, es un CONFLICTO DE DATOS. */
        IF v_Nombre_Existente <> _Nombre THEN
            SIGNAL SQLSTATE '45000' 
                SET MESSAGE_TEXT = 'CONFLICTO DE DATOS [409]: El CÓDIGO ingresado ya existe pero pertenece a un Puesto con diferente NOMBRE. Verifique sus datos.';
        END IF;

        /* Sub-Escenario A.1: Existe pero está INACTIVO (Baja Lógica) -> REACTIVAR (Autosanación) */
        IF v_Activo = 0 THEN
            UPDATE `Cat_Puestos_Trabajo`
            SET `Activo` = 1,
                `Descripcion` = COALESCE(_Descripcion, `Descripcion`), -- Actualizamos descripción si se proveyó
                `updated_at` = NOW()
            WHERE `Id_CatPuesto` = v_Id_Puesto;
            
            COMMIT; 
            SELECT 'ÉXITO: Puesto reactivado y actualizado correctamente.' AS Mensaje, v_Id_Puesto AS Id_Puesto, 'REACTIVADA' AS Accion; 
            LEAVE THIS_PROC;
        
        /* Sub-Escenario A.2: Existe y está ACTIVO -> IDEMPOTENCIA (Reportar éxito sin cambios) */
        ELSE
            COMMIT; 
            SELECT 'AVISO: El Puesto ya se encuentra registrado y activo.' AS Mensaje, v_Id_Puesto AS Id_Puesto, 'REUSADA' AS Accion; 
            LEAVE THIS_PROC;
        END IF;
    END IF;

    /* ------------------------------------------------------------------------------------------------
       PASO 3.2: RESOLUCIÓN DE IDENTIDAD POR NOMBRE (PRIORIDAD SECUNDARIA)
       
       Objetivo: Si llegamos aquí, el CÓDIGO es libre. Ahora verificamos si el NOMBRE ya está en uso.
       Esto previene que se creen duplicados semánticos con códigos diferentes.
       ------------------------------------------------------------------------------------------------ */
    SET v_Id_Puesto = NULL; -- Reset de seguridad

    SELECT `Id_CatPuesto`, `Codigo`, `Activo`
    INTO v_Id_Puesto, v_Codigo_Existente, v_Activo
    FROM `Cat_Puestos_Trabajo`
    WHERE `Nombre` = _Nombre
    LIMIT 1
    FOR UPDATE;

    /* ESCENARIO B: EL NOMBRE YA EXISTE */
    IF v_Id_Puesto IS NOT NULL THEN
        
        /* Conflicto de Identidad: Nombre existe con otro código distinto.
           Esto se considera un error porque un mismo puesto no debería tener dos claves. */
        IF v_Codigo_Existente IS NOT NULL AND v_Codigo_Existente <> _Codigo THEN
             SIGNAL SQLSTATE '45000' 
             SET MESSAGE_TEXT = 'CONFLICTO DE DATOS [409]: El NOMBRE ingresado ya existe pero está asociado a otro CÓDIGO diferente.';
        END IF;
        
        /* Caso Especial: Enriquecimiento de Datos (Data Enrichment)
           El registro existía con Código NULL (dato viejo), y ahora le estamos asignando un Código válido. */
        IF v_Codigo_Existente IS NULL THEN
             UPDATE `Cat_Puestos_Trabajo` 
             SET `Codigo` = _Codigo, `updated_at` = NOW() 
             WHERE `Id_CatPuesto` = v_Id_Puesto;
        END IF;

        /* Reactivación si estaba inactivo */
        IF v_Activo = 0 THEN
            UPDATE `Cat_Puestos_Trabajo` 
            SET `Activo` = 1, `updated_at` = NOW() 
            WHERE `Id_CatPuesto` = v_Id_Puesto;
            
            COMMIT; 
            SELECT 'ÉXITO: Puesto reactivado correctamente (encontrado por Nombre).' AS Mensaje, v_Id_Puesto AS Id_Puesto, 'REACTIVADA' AS Accion; 
            LEAVE THIS_PROC;
        END IF;

        /* Idempotencia: Ya existe activo y con datos consistentes */
        COMMIT; 
        SELECT 'AVISO: El Puesto ya existe (validado por Nombre).' AS Mensaje, v_Id_Puesto AS Id_Puesto, 'REUSADA' AS Accion; 
        LEAVE THIS_PROC;
    END IF;

    /* ------------------------------------------------------------------------------------------------
       PASO 3.3: PERSISTENCIA (INSERCIÓN FÍSICA)
       
       Si pasamos todas las validaciones anteriores, significa que no encontramos coincidencias.
       Es un registro totalmente NUEVO y seguro para insertar.
       ------------------------------------------------------------------------------------------------ */
    SET v_Dup = 0; -- Reiniciamos bandera de error
    
    INSERT INTO `Cat_Puestos_Trabajo`
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
        SELECT 'ÉXITO: Puesto registrado correctamente.' AS Mensaje, LAST_INSERT_ID() AS Id_Puesto, 'CREADA' AS Accion; 
        LEAVE THIS_PROC;
    END IF;

    /* ================================================================================================
       BLOQUE 4: RUTINA DE RECUPERACIÓN DE CONCURRENCIA (RE-RESOLVE PATTERN)
       ================================================================================================
       Si el flujo llega aquí, v_Dup = 1.
       Diagnóstico: Ocurrió una "Race Condition". Otro usuario insertó el registro milisegundos
       antes que nosotros, disparando el Error 1062 (Duplicate Key) en el INSERT del Paso 3.3.
       
       Acción: Recuperar el ID del registro "ganador" y devolverlo como si fuera nuestro. */
    
    ROLLBACK; -- Limpiamos la transacción fallida (para liberar bloqueos parciales)
    
    START TRANSACTION; -- Iniciamos nueva transacción limpia
    
    SET v_Id_Puesto = NULL; -- Reset
    
    /* Intentamos recuperar por CÓDIGO (Identificador fuerte) */
    SELECT `Id_CatPuesto`, `Activo`, `Nombre`
    INTO v_Id_Puesto, v_Activo, v_Nombre_Existente
    FROM `Cat_Puestos_Trabajo`
    WHERE `Codigo` = _Codigo
    LIMIT 1
    FOR UPDATE;
    
    IF v_Id_Puesto IS NOT NULL THEN
        /* Validación de Seguridad: Confirmar que no sea un falso positivo */
        IF v_Nombre_Existente <> _Nombre THEN
             SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR CRÍTICO DE SISTEMA [500]: Concurrencia detectada con conflicto de datos (Códigos iguales, Nombres distintos).';
        END IF;

        /* Reactivación (si el ganador estaba inactivo) */
        IF v_Activo = 0 THEN
            UPDATE `Cat_Puestos_Trabajo` 
            SET `Activo` = 1, `updated_at` = NOW() 
            WHERE `Id_CatPuesto` = v_Id_Puesto;
            
            COMMIT; 
            SELECT 'ÉXITO: Puesto reactivado (recuperado tras concurrencia).' AS Mensaje, v_Id_Puesto AS Id_Puesto, 'REACTIVADA' AS Accion; 
            LEAVE THIS_PROC;
        END IF;
        
        /* Reuso (Ya estaba activo) */
        COMMIT; 
        SELECT 'AVISO: El Puesto ya existía (reusado tras concurrencia).' AS Mensaje, v_Id_Puesto AS Id_Puesto, 'REUSADA' AS Accion; 
        LEAVE THIS_PROC;
    END IF;

    /* Fallo irrecuperable: Si falló por 1062 pero no encontramos el registro (Corrupción de índices o error fantasma) */
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA [500]: Fallo de concurrencia no recuperable en Puestos.';

END$$

DELIMITER ;

/* ============================================================================================
   SECCIÓN: CONSULTAS ESPECÍFICAS (PARA EDICIÓN / DETALLE)
   ============================================================================================
   Esta sección contiene rutinas optimizadas para la recuperación de un único registro (Single Row).
   Son fundamentales para la Experiencia de Usuario (UX) en los formularios de mantenimiento.
   ============================================================================================ */

/* ============================================================================================
   PROCEDIMIENTO: SP_ConsultarPuestoEspecifico
   ============================================================================================
   1. OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   --------------------------------------
   Recuperar la "Ficha Técnica" completa, cruda y sin procesar (Raw Data) de un Puesto de Trabajo
   específico, identificado por su llave primaria (`Id_CatPuesto`).

   CASOS DE USO (CONTEXTO DE UI):
   A) PRECARGA DE FORMULARIO DE EDICIÓN (UPDATE):
      - Cuando el administrador va a editar un puesto, el formulario debe llenarse con los datos
        exactos que residen en la base de datos.
      - Requisito Crítico: Si el campo `Codigo` es NULL en la BD, el SP debe devolver NULL.
        No debe devolver transformaciones cosméticas (como "S/C" o "-"), ya que esto ensuciaría
        el input del formulario, obligando al usuario a borrar texto basura antes de editar.

   B) VISUALIZACIÓN DE DETALLE (AUDITORÍA):
      - Permite visualizar metadatos de auditoría (`created_at`, `updated_at`) que normalmente
        se ocultan en los listados generales para no saturar la vista.

   2. ARQUITECTURA DE DATOS (DIRECT TABLE ACCESS)
   ----------------------------------------------
   Este procedimiento consulta directamente la tabla física `Cat_Puestos_Trabajo`, evitando el uso
   de la vista `Vista_Puestos`.

   JUSTIFICACIÓN TÉCNICA:
   - Desacoplamiento de Presentación: Las Vistas están optimizadas para lectura humana (formateo,
     etiquetas amigables). Los SPs de Edición están optimizados para lectura de sistema (datos
     puros para el binding de modelos en Angular/React/Vue/Laravel).
   - Performance: El acceso por Primary Key (`Id_CatPuesto`) tiene un costo computacional de O(1),
     garantizando una respuesta instantánea.

   3. ESTRATEGIA DE SEGURIDAD (DEFENSIVE PROGRAMMING)
   --------------------------------------------------
   - Validación de Entrada: Se rechazan IDs nulos o negativos antes de consultar.
   - Fail Fast (Fallo Rápido): Se verifica la existencia del registro antes de intentar devolver datos.
     Esto permite al Backend diferenciar claramente entre un error 404 (Recurso no encontrado) y
     un error 500 (Fallo de servidor).

   4. VISIBILIDAD (SCOPE)
   ----------------------
   - NO se filtra por `Activo = 1`.
   - Razón: Un puesto puede estar "Desactivado" (Baja Lógica). El administrador necesita poder
     consultarlo para ver su información y decidir si lo Reactiva. Ocultarlo aquí haría imposible
     su gestión.

   5. DICCIONARIO DE DATOS (OUTPUT)
   --------------------------------
   Retorna una única fila (Single Row) con:
     - [Identidad]: Id_CatPuesto, Codigo, Nombre.
     - [Detalle]: Descripcion.
     - [Control]: Activo (Vital para el estado del switch de activación).
     - [Auditoría]: created_at, updated_at.
   ============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ConsultarPuestoEspecifico`$$
CREATE PROCEDURE `SP_ConsultarPuestoEspecifico`(
    IN _Id_Puesto INT -- Identificador único del Puesto a consultar
)
BEGIN
    /* ========================================================================================
       BLOQUE 1: VALIDACIÓN DE ENTRADA (DEFENSIVE PROGRAMMING)
       Objetivo: Asegurar que el parámetro recibido sea un entero positivo válido.
       Evita cargas innecesarias al motor de base de datos con peticiones basura.
       ======================================================================================== */
    IF _Id_Puesto IS NULL OR _Id_Puesto <= 0 THEN
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'ERROR DE SISTEMA: El Identificador del Puesto es inválido (Debe ser un entero positivo).';
    END IF;

    /* ========================================================================================
       BLOQUE 2: VERIFICACIÓN DE EXISTENCIA (FAIL FAST STRATEGY)
       Objetivo: Validar que el recurso realmente exista en la base de datos.
       
       NOTA DE IMPLEMENTACIÓN:
       Usamos `SELECT 1` que es más ligero que seleccionar columnas reales, ya que solo
       necesitamos confirmar la presencia de la llave en el índice primario.
       ======================================================================================== */
    IF NOT EXISTS (SELECT 1 FROM `Cat_Puestos_Trabajo` WHERE `Id_CatPuesto` = _Id_Puesto) THEN
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'ERROR DE NEGOCIO: El Puesto de Trabajo solicitado no existe en el catálogo o fue eliminado físicamente.';
    END IF;

    /* ========================================================================================
       BLOQUE 3: CONSULTA PRINCIPAL (DATA RETRIEVAL)
       Objetivo: Retornar el objeto de datos completo y puro (Raw Data).
       ======================================================================================== */
    SELECT 
        /* --- GRUPO A: IDENTIDAD DEL REGISTRO --- */
        /* Este ID es la llave primaria inmutable. El Frontend debe mantenerlo protegido. */
        `Id_CatPuesto`,
        
        /* --- GRUPO B: DATOS EDITABLES --- */
        /* Nota: 'Codigo' puede ser NULL. El API debe entregar 'null' nativo JSON, 
           no strings vacíos ni "null" como texto. */
        `Codigo`,        
        `Nombre`,
        `Descripcion`,
        
        /* --- GRUPO C: METADATOS DE CONTROL DE CICLO DE VIDA --- */
        /* Este valor (0 o 1) indica si el puesto es utilizable actualmente.
           1 = Activo/Visible, 0 = Inactivo/Oculto (Baja Lógica). */
        `Activo`,        
        
        /* --- GRUPO D: AUDITORÍA DE SISTEMA --- */
        /* Fechas útiles para mostrar en el pie de página del modal de detalle. */
        `created_at`,
        `updated_at`
        
    FROM `Cat_Puestos_Trabajo`
    WHERE `Id_CatPuesto` = _Id_Puesto
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
   PROCEDIMIENTO: SP_ListarPuestosActivos
   ============================================================================================
   1. OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   --------------------------------------
   Proveer un endpoint de datos ligero y altamente optimizado para alimentar elementos de 
   Interfaz de Usuario (UI) tipo "Selector", "Dropdown" o "ComboBox".
   
   Este procedimiento es la fuente autorizada para desplegar las opciones de "Puestos de Trabajo"
   disponibles en los formularios de:
     - Alta y Edición de Personal (Tabla `Info_Personal`).
     - Asignación de vacantes.
     - Filtros de búsqueda en Reportes de Plantilla.

   2. REGLAS DE NEGOCIO Y FILTRADO (THE VIGENCY CONTRACT)
   ------------------------------------------------------
   A) FILTRO DE VIGENCIA ESTRICTO (HARD FILTER):
      - Regla: La consulta aplica obligatoriamente la cláusula `WHERE Activo = 1`.
      - Justificación Operativa: Un Puesto marcado como inactivo (Baja Lógica) representa un 
        cargo obsoleto, reestructurado o eliminado del organigrama oficial. Permitir su selección 
        para un empleado activo generaría inconsistencias administrativas ("Empleado asignado a un puesto fantasma").
      - Seguridad: El filtro es backend-side, garantizando que ni siquiera una API manipulada 
        pueda recuperar puestos obsoletos por esta vía.

   B) ORDENAMIENTO COGNITIVO (USABILITY):
      - Regla: Los resultados se ordenan alfabéticamente por `Nombre` (A-Z).
      - Justificación: Facilita la búsqueda visual rápida por parte del usuario humano en listas largas.

   3. ARQUITECTURA DE DATOS (ROOT ENTITY OPTIMIZATION)
   ---------------------------------------------------
   - Ausencia de JOINs: En la estructura actual, `Cat_Puestos_Trabajo` opera como una Entidad Raíz 
     (no depende jerárquicamente de otra tabla para existir en el catálogo, aunque funcionalmente 
     se asigne a centros de trabajo). Esto permite una consulta directa y veloz.
   
   - Proyección Mínima (Payload Reduction):
     Solo se devuelven las columnas necesarias para construir el elemento HTML `<option>`:
       1. ID (Value): Integridad referencial.
       2. Nombre (Label): Lectura humana.
       3. Código (Hint): Referencia visual rápida.
     Se omiten campos pesados como `Descripcion`, `created_at`, etc., para minimizar el tráfico de red.

   4. DICCIONARIO DE DATOS (OUTPUT JSON SCHEMA)
   --------------------------------------------
   Retorna un array de objetos ligeros:
     - `Id_CatPuesto`: (INT) Llave Primaria. Value del selector.
     - `Codigo`:       (VARCHAR) Clave corta (ej: 'SUP-01'). Puede ser NULL.
     - `Nombre`:       (VARCHAR) Texto principal (ej: 'Supervisor de Seguridad').
   ============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ListarPuestosActivos`$$
CREATE PROCEDURE `SP_ListarPuestosActivos`()
BEGIN
    /* ========================================================================================
       BLOQUE ÚNICO: CONSULTA DE SELECCIÓN OPTIMIZADA
       No requiere validaciones de entrada ya que es una consulta de catálogo global.
       ======================================================================================== */
    
    SELECT 
        /* IDENTIFICADOR ÚNICO (PK)
           Este es el valor que se guardará como Foreign Key (Fk_Id_CatPuesto) en la tabla Info_Personal. */
        `Id_CatPuesto`, 
        
        /* CLAVE CORTA / MNEMOTÉCNICA
           Útil para mostrar en el frontend como 'badge' o texto secundario entre paréntesis.
           Ej: "Supervisor de Obra (SUP-OB)" */
        `Codigo`, 
        
        /* DESCRIPTOR HUMANO
           El texto principal que el usuario leerá y buscará en la lista desplegable. */
        `Nombre`

    FROM 
        `Cat_Puestos_Trabajo`
    
    /* ----------------------------------------------------------------------------------------
       FILTRO DE SEGURIDAD OPERATIVA (VIGENCIA)
       Ocultamos todo lo que no sea "1" (Activo). 
       Esto asegura que nuevos empleados no sean dados de alta en puestos extintos.
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
   Su objetivo es dar visibilidad total sobre el catálogo para auditoría y gestión.
   ============================================================================================ */

/* ============================================================================================
   PROCEDIMIENTO: SP_ListarPuestosAdmin
   ============================================================================================
   1. OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   --------------------------------------
   Proveer el inventario maestro y completo de los "Puestos de Trabajo" (`Cat_Puestos_Trabajo`)
   para alimentar el Grid Principal del Módulo de Administración.
   
   Este endpoint permite al Administrador visualizar la totalidad de los datos (históricos y actuales)
   para realizar tareas de:
     - Auditoría: Revisar qué cargos han existido en la historia de la empresa.
     - Mantenimiento: Detectar errores de captura en nombres o códigos y corregirlos.
     - Gestión de Ciclo de Vida: Reactivar puestos que fueron dados de baja por error o que
       vuelven a ser operativos tras una reestructuración.

   2. DIFERENCIA CRÍTICA CON EL LISTADO OPERATIVO (DROPDOWN)
   ---------------------------------------------------------
   Es vital distinguir este SP de `SP_ListarPuestosActivos`:
   
   A) SP_ListarPuestosActivos (Dropdown): 
      - Enfoque: Operatividad y Seguridad.
      - Filtro: Estricto `WHERE Activo = 1`.
      - Objetivo: Evitar que se asignen nuevos empleados a puestos obsoletos.
   
   B) SP_ListarPuestosAdmin (ESTE):
      - Enfoque: Gestión y Auditoría.
      - Filtro: NINGUNO (Visibilidad Total).
      - Objetivo: Permitir al Admin ver registros inactivos (`Estatus = 0`) para poder editarlos
        o reactivarlos. Ocultar los inactivos aquí impediría su recuperación y gestión.

   3. ARQUITECTURA DE DATOS (VIEW CONSUMPTION PATTERN)
   ---------------------------------------------------
   Este procedimiento implementa el patrón de "Abstracción de Lectura" al consumir la vista
   `Vista_Puestos` en lugar de la tabla física.

   Ventajas Técnicas:
   - Desacoplamiento: El Grid del Frontend se acopla a los nombres de columnas estandarizados de la Vista 
     (ej: `Estatus_Puesto`) y no a los de la tabla física (`Activo`). Si la tabla cambia,
     solo ajustamos la Vista y este SP sigue funcionando sin cambios.
   - Estandarización: La vista ya maneja la proyección de columnas de auditoría y metadatos.

   4. ESTRATEGIA DE ORDENAMIENTO (UX PRIORITY)
   -------------------------------------------
   El ordenamiento no es arbitrario; está diseñado para la eficiencia administrativa:
     1. Prioridad Operativa (`Estatus_Puesto` DESC): 
        Los registros VIGENTES (1) aparecen en la parte superior. Los obsoletos (0) se van al fondo.
        Esto mantiene la información relevante accesible inmediatamente sin scrollear.
     2. Orden Alfabético (`Nombre_Puesto` ASC): 
        Dentro de cada grupo de estatus, se ordenan A-Z para facilitar la búsqueda visual rápida.

   5. DICCIONARIO DE DATOS (OUTPUT)
   --------------------------------
   Retorna el contrato de datos definido en `Vista_Puestos`:
     - [Identidad]: Id_Puesto, Codigo_Puesto, Nombre_Puesto.
     - [Detalle]: Descripcion_Puesto.
     - [Control]: Estatus_Puesto (1 = Activo, 0 = Inactivo).
     - [Auditoría]: created_at, updated_at (aunque ocultos por defecto en la vista, si se activan).
   ============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ListarPuestosAdmin`$$
CREATE PROCEDURE `SP_ListarPuestosAdmin`()
BEGIN
    /* ========================================================================================
       BLOQUE ÚNICO: CONSULTA MAESTRA
       No requiere validaciones de entrada ya que es una consulta global sobre el catálogo.
       ======================================================================================== */
    
    SELECT 
        /* Proyección total de la Vista Maestra */
        * FROM 
        `Vista_Puestos`
    
    /* ========================================================================================
       ORDENAMIENTO ESTRATÉGICO
       Optimizamos la presentación para el usuario administrador.
       ======================================================================================== */
    ORDER BY 
        `Estatus_Puesto` DESC,  -- 1º: Muestra primero lo que está vivo (Operativo)
        `Nombre_Puesto` ASC;    -- 2º: Ordena alfabéticamente para facilitar búsqueda visual

END$$

DELIMITER ;

/* ====================================================================================================
   PROCEDIMIENTO: SP_EditarPuesto
   ====================================================================================================
   1. VISIÓN GENERAL Y OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   ----------------------------------------------------------------------------------------------------
   Este procedimiento orquesta la modificación de los atributos descriptivos de un "Puesto de Trabajo"
   existente en el catálogo corporativo.
   
   No se trata de un simple `UPDATE`. Es un motor transaccional diseñado para operar en entornos de 
   alta concurrencia (múltiples administradores editando simultáneamente), garantizando las propiedades ACID:
     - Atomicidad: O se aplican todos los cambios, o ninguno.
     - Consistencia: No se permiten duplicados de Código o Nombre.
     - Aislamiento: Uso de bloqueos determinísticos para prevenir abrazos mortales (Deadlocks).
     - Durabilidad: Confirmación explícita (COMMIT) tras validar reglas.

   2. REGLAS DE VALIDACIÓN ESTRICTA (HARD CONSTRAINTS)
   ----------------------------------------------------------------------------------------------------
   A) OBLIGATORIEDAD DE CAMPOS:
      - Regla: "Todo o Nada". No se permite guardar cambios si el Código o el Nombre son cadenas vacías.
      - Justificación: Un puesto sin nombre pierde su valor semántico en los reportes históricos.

   B) UNICIDAD GLOBAL (EXCLUSIÓN PROPIA):
      - Se verifica que el nuevo Código no pertenezca a OTRO puesto (`Id <> _Id_Puesto`).
      - Se verifica que el nuevo Nombre no pertenezca a OTRO puesto.
      - Nota: Es perfectamente legal que el registro choque consigo mismo (ej: cambiar solo la descripción).

   3. ARQUITECTURA DE CONCURRENCIA (DETERMINISTIC LOCKING PATTERN)
   ----------------------------------------------------------------------------------------------------
   Para prevenir **Deadlocks** (Bloqueos Mutuos) en escenarios de "Intercambio" (Swap Scenario) donde
   el Usuario A quiere renombrar el Puesto 1 como 'X', y el Usuario B quiere renombrar el Puesto 2 
   como 'Y' (cruzados), implementamos una estrategia de BLOQUEO DETERMINÍSTICO:

     - FASE 1 (Identificación): Detectamos todos los IDs involucrados en la transacción (El ID objetivo,
       el ID dueño del código deseado y el ID dueño del nombre deseado).
     - FASE 2 (Ordenamiento): Ordenamos estos IDs numéricamente de MENOR a MAYOR.
     - FASE 3 (Ejecución): Adquirimos los bloqueos (`FOR UPDATE`) siguiendo estrictamente ese orden.
   
   Resultado: Todos los procesos compiten por los recursos en la misma dirección ("fila india"), 
   eliminando matemáticamente la posibilidad de un ciclo de espera.

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
     - Id_Puesto (INT): Identificador del recurso manipulado.
   ==================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_EditarPuesto`$$

CREATE PROCEDURE `SP_EditarPuesto`(
    /* -----------------------------------------------------------------
       PARÁMETROS DE ENTRADA (INPUTS)
       Recibimos los datos crudos del formulario de edición.
       ----------------------------------------------------------------- */
    IN _Id_Puesto    INT,           -- OBLIGATORIO: ID del registro a modificar (PK)
    IN _Nuevo_Codigo VARCHAR(50),   -- OBLIGATORIO: Nueva Clave (ej: 'MED-ESP')
    IN _Nuevo_Nombre VARCHAR(255),  -- OBLIGATORIO: Nuevo Nombre (ej: 'Médico Especialista')
    IN _Nueva_Desc   VARCHAR(255)   -- OPCIONAL: Descripción detallada
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
    DECLARE v_Id_Conflicto_Cod INT DEFAULT NULL; -- ID del dueño actual del Código deseado (si existe)
    DECLARE v_Id_Conflicto_Nom INT DEFAULT NULL; -- ID del dueño actual del Nombre deseado (si existe)

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
    
    IF _Id_Puesto IS NULL OR _Id_Puesto <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: Identificador de Puesto inválido.';
    END IF;

    IF _Nuevo_Codigo IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN [400]: El CÓDIGO es obligatorio para la edición.';
    END IF;

    IF _Nuevo_Nombre IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN [400]: El NOMBRE es obligatorio para la edición.';
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
    FROM `Cat_Puestos_Trabajo` WHERE `Id_CatPuesto` = _Id_Puesto;

    /* Si no encontramos el registro propio, abortamos (pudo ser borrado por otro admin hace instantes) */
    IF v_Cod_Act IS NULL AND v_Nom_Act IS NULL THEN 
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [404]: El Puesto que intenta editar no existe.';
    END IF;

    /* B) Identificar posible conflicto de CÓDIGO (¿Alguien más ya tiene mi nuevo código?)
       Solo buscamos si el código cambió respecto al actual. */
    IF _Nuevo_Codigo <> IFNULL(v_Cod_Act, '') THEN
        SELECT `Id_CatPuesto` INTO v_Id_Conflicto_Cod 
        FROM `Cat_Puestos_Trabajo` 
        WHERE `Codigo` = _Nuevo_Codigo AND `Id_CatPuesto` <> _Id_Puesto LIMIT 1;
    END IF;

    /* C) Identificar posible conflicto de NOMBRE (¿Alguien más ya tiene mi nuevo nombre?)
       Solo buscamos si el nombre cambió respecto al actual. */
    IF _Nuevo_Nombre <> v_Nom_Act THEN
        SELECT `Id_CatPuesto` INTO v_Id_Conflicto_Nom 
        FROM `Cat_Puestos_Trabajo` 
        WHERE `Nombre` = _Nuevo_Nombre AND `Id_CatPuesto` <> _Id_Puesto LIMIT 1;
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
    SET v_L1 = _Id_Puesto;
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
        SELECT 1 INTO v_Existe FROM `Cat_Puestos_Trabajo` WHERE `Id_CatPuesto` = v_Min FOR UPDATE;
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
        SELECT 1 INTO v_Existe FROM `Cat_Puestos_Trabajo` WHERE `Id_CatPuesto` = v_Min FOR UPDATE;
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
        SELECT 1 INTO v_Existe FROM `Cat_Puestos_Trabajo` WHERE `Id_CatPuesto` = v_Min FOR UPDATE;
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
    FROM `Cat_Puestos_Trabajo` 
    WHERE `Id_CatPuesto` = _Id_Puesto; 

    /* Safety Check: Si al bloquear descubrimos que el registro fue borrado */
    IF v_Nom_Act IS NULL THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR CRÍTICO [410]: El registro desapareció durante la transacción.';
    END IF;

    /* 4.2 DETECCIÓN DE IDEMPOTENCIA (SIN CAMBIOS)
       Comparamos si los datos nuevos son matemáticamente iguales a los actuales. 
       Usamos `<=>` (Null-Safe Equality) para manejar correctamente los NULLs en campos opcionales. */
    IF (v_Cod_Act <=> _Nuevo_Codigo) 
       AND (v_Nom_Act = _Nuevo_Nombre) 
       AND (v_Desc_Act <=> _Nueva_Desc) THEN
       
       COMMIT; -- Liberamos locks inmediatamente
       
       /* Retorno anticipado para ahorrar I/O y notificar al Frontend */
       SELECT 'AVISO: No se detectaron cambios en la información.' AS Mensaje, 'SIN_CAMBIOS' AS Accion, _Id_Puesto AS Id_Puesto;
       LEAVE THIS_PROC;
    END IF;

    /* 4.3 VALIDACIÓN FINAL DE UNICIDAD (PRE-UPDATE CHECK)
       Verificamos si existen duplicados REALES. Al tener los registros conflictivos bloqueados,
       esta verificación es 100% fiable. */
    
    /* A) Validación por CÓDIGO */
    SET v_Id_Error = NULL;
    SELECT `Id_CatPuesto` INTO v_Id_Error FROM `Cat_Puestos_Trabajo` 
    WHERE `Codigo` = _Nuevo_Codigo AND `Id_CatPuesto` <> _Id_Puesto LIMIT 1;
    
    IF v_Id_Error IS NOT NULL THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'CONFLICTO DE DATOS [409]: El CÓDIGO ingresado ya pertenece a otro Puesto.';
    END IF;

    /* B) Validación por NOMBRE */
    SET v_Id_Error = NULL;
    SELECT `Id_CatPuesto` INTO v_Id_Error FROM `Cat_Puestos_Trabajo` 
    WHERE `Nombre` = _Nuevo_Nombre AND `Id_CatPuesto` <> _Id_Puesto LIMIT 1;
    
    IF v_Id_Error IS NOT NULL THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'CONFLICTO DE DATOS [409]: El NOMBRE ingresado ya pertenece a otro Puesto.';
    END IF;

    /* ================================================================================================
       BLOQUE 5: PERSISTENCIA Y FINALIZACIÓN (UPDATE)
       Propósito: Aplicar los cambios una vez superadas todas las barreras de seguridad.
       ================================================================================================ */
    
    SET v_Dup = 0; -- Resetear bandera de error antes de escribir

    UPDATE `Cat_Puestos_Trabajo`
    SET `Codigo`      = _Nuevo_Codigo,
        `Nombre`      = _Nuevo_Nombre,
        `Descripcion` = _Nueva_Desc,
        `updated_at`  = NOW() -- Auditoría automática
    WHERE `Id_CatPuesto` = _Id_Puesto;

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
        SELECT `Id_CatPuesto` INTO v_Id_Error FROM `Cat_Puestos_Trabajo` 
        WHERE `Codigo` = _Nuevo_Codigo AND `Id_CatPuesto` <> _Id_Puesto LIMIT 1;
        
        IF v_Id_Error IS NOT NULL THEN
            SET v_Campo_Error = 'CODIGO';
        ELSE
            /* Entonces fue conflicto de Nombre */
            SELECT `Id_CatPuesto` INTO v_Id_Error FROM `Cat_Puestos_Trabajo` 
            WHERE `Nombre` = _Nuevo_Nombre AND `Id_CatPuesto` <> _Id_Puesto LIMIT 1;
            SET v_Campo_Error = 'NOMBRE';
        END IF;

        SELECT 'Error de Concurrencia: Conflicto detectado al guardar (Otro usuario ganó).' AS Mensaje, 
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
    
    SELECT 'ÉXITO: Puesto actualizado correctamente.' AS Mensaje, 
           'ACTUALIZADA' AS Accion, 
           _Id_Puesto AS Id_Puesto;

END$$

DELIMITER ;

/* ====================================================================================================
   PROCEDIMIENTO: SP_CambiarEstatusPuesto
   ====================================================================================================
   1. DEFINICIÓN DEL OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   ----------------------------------------------------------------------------------------------------
   Gestionar el cambio de estado (Activación/Desactivación) de un "Puesto de Trabajo" (`Cat_Puestos_Trabajo`)
   mediante el mecanismo de BAJA LÓGICA (Soft Delete).

   Este procedimiento permite al Administrador:
     A) DESACTIVAR (Ocultar): Marcar un puesto como obsoleto (ej: "Mecanógrafo") para que no aparezca
        en los selectores de nuevas contrataciones.
     B) REACTIVAR (Mostrar): Recuperar un puesto histórico para volver a utilizarlo.

   2. ARQUITECTURA DE INTEGRIDAD REFERENCIAL (CRITICAL PATH)
   ----------------------------------------------------------------------------------------------------
   Se aplica una política estricta de "No Huérfanos Operativos" (Operational Orphan Prevention).
   
   - REGLA DE BLOQUEO (Downstream Dependency Check):
     Si se solicita DESACTIVAR un puesto, el sistema consulta proactivamente la tabla de Personal (`Info_Personal`).
   
   - CONDICIÓN DE RECHAZO:
     Si existe AL MENOS UN empleado con estatus `Activo = 1` que ocupa este puesto, la operación se
     bloquea inmediatamente con un error de negocio.
   
   - JUSTIFICACIÓN:
     Evita la inconsistencia de tener empleados activos asignados a un cargo que "ya no existe" 
     administrativamente. Primero se debe reasignar o dar de baja al personal.

   3. ESTRATEGIA DE CONCURRENCIA (BLOQUEO PESIMISTA / ACID)
   ----------------------------------------------------------------------------------------------------
   - NIVEL DE AISLAMIENTO: Utiliza `SELECT ... FOR UPDATE` al inicio de la transacción.
   - OBJETIVO: Serializar el acceso al registro del Puesto.
   - ESCENARIO EVITADO (RACE CONDITION): Previene que el Admin A desactive el puesto justo en el
     milisegundo en que el Admin B está asignando ese mismo puesto a un nuevo empleado.

   4. IDEMPOTENCIA (OPTIMIZACIÓN DE RECURSOS)
   ----------------------------------------------------------------------------------------------------
   - Antes de escribir en disco, verificamos si el registro ya tiene el estatus solicitado.
   - Si `Activo_Actual == Nuevo_Estatus`, el SP retorna éxito sin realizar el UPDATE.
   - Beneficio: Ahorro de I/O y preservación del timestamp `updated_at`.

   5. CONTRATO DE SALIDA (OUTPUT CONTRACT)
   ----------------------------------------------------------------------------------------------------
   Retorna un resultset (Single Row) con:
     - Mensaje (VARCHAR): Feedback legible para el usuario final.
     - Activo_Anterior (TINYINT): Estado previo para rollback visual en Frontend.
     - Activo_Nuevo (TINYINT): Estado final confirmado.
   ==================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_CambiarEstatusPuesto`$$

CREATE PROCEDURE `SP_CambiarEstatusPuesto`(
    IN _Id_Puesto    INT,     -- Identificador Único (PK) del Puesto a modificar
    IN _Nuevo_Estatus TINYINT -- Flag de Estado Solicitado: 1 = Activo (Visible), 0 = Inactivo (Soft Delete)
)
THIS_PROC: BEGIN
    
    /* ================================================================================================
       BLOQUE 0: VARIABLES DE ESTADO Y CONTROL
       Propósito: Inicializar los contenedores de datos que mantendrán la "foto" (Snapshot) del
       registro antes de cualquier modificación.
       ================================================================================================ */
    
    -- [Flag de Existencia]: Determina si el ID proporcionado apunta a un registro válido en la BDD.
    DECLARE v_Existe        INT DEFAULT NULL;
    
    -- [Snapshot de Estado]: Almacena el valor actual de la columna `Activo` antes de la modificación.
    -- Vital para la verificación de idempotencia.
    DECLARE v_Activo_Actual TINYINT(1) DEFAULT NULL;
    
    -- [Semáforo de Dependencias]: Variable auxiliar utilizada durante la validación de integridad.
    -- Si cambia a NOT NULL, indica que existe un bloqueo de negocio (Empleados activos ocupando el puesto).
    DECLARE v_Dependencias  INT DEFAULT NULL;

    /* ================================================================================================
       BLOQUE 1: GESTIÓN DE EXCEPCIONES Y ATOMICIDAD (ERROR HANDLING)
       Propósito: Garantizar que la base de datos nunca quede en un estado inconsistente ante fallos.
       ================================================================================================ */
    
    -- [Safety Net]: Captura cualquier error SQL (SQLEXCEPTION) no controlado explícitamente.
    -- ACCIÓN: Ejecuta un ROLLBACK total y propaga el error (RESIGNAL).
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; 
    END;

    /* ================================================================================================
       BLOQUE 2: PROTOCOLO DE VALIDACIÓN DE ENTRADA (DEFENSIVE PROGRAMMING)
       Propósito: Rechazar peticiones malformadas ("Fail Fast") antes de consumir recursos.
       ================================================================================================ */
    
    -- [Validación de Identidad]: El ID debe ser un entero positivo.
    IF _Id_Puesto IS NULL OR _Id_Puesto <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: El ID del Puesto es inválido o nulo.';
    END IF;

    -- [Validación de Dominio]: El estatus debe ser binario estrictamente (0 o 1).
    IF _Nuevo_Estatus NOT IN (0, 1) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: El valor de Estatus está fuera de rango (Permitido: 0, 1).';
    END IF;

    /* ================================================================================================
       BLOQUE 3: INICIO DE TRANSACCIÓN Y BLOQUEO PESIMISTA
       Propósito: Aislar el registro objetivo para asegurar consistencia durante la lectura y escritura.
       ================================================================================================ */
    START TRANSACTION;

    /* ------------------------------------------------------------------------------------------------
       PASO 3.1: ADQUISICIÓN DE SNAPSHOT CON BLOQUEO DE ESCRITURA (FOR UPDATE)
       
       Mecánica Técnica:
       Se realiza una lectura del registro usando la cláusula `FOR UPDATE`.
       
       Efecto en el Motor de Base de Datos:
       1. Verifica si el registro existe.
       2. Coloca un "Row-Level Lock" (X-Lock) sobre la fila específica del ID.
       3. Cualquier otra transacción concurrente deberá esperar.
       ------------------------------------------------------------------------------------------------ */
    SELECT 1, `Activo` 
    INTO v_Existe, v_Activo_Actual
    FROM `Cat_Puestos_Trabajo` 
    WHERE `Id_CatPuesto` = _Id_Puesto 
    LIMIT 1 
    FOR UPDATE;

    -- [Verificación de Existencia]: Si el SELECT no encontró nada, v_Existe sigue siendo NULL.
    IF v_Existe IS NULL THEN 
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [404]: El Puesto de Trabajo solicitado no existe en el catálogo.'; 
    END IF;

    /* ------------------------------------------------------------------------------------------------
       PASO 3.2: VERIFICACIÓN DE IDEMPOTENCIA (OPTIMIZACIÓN)
       
       Lógica de Negocio:
       "Si ya está encendido, no intentes encenderlo de nuevo".
       
       Beneficio Técnico:
       - Evita un UPDATE innecesario (ahorra ciclos de CPU y escrituras en disco).
       - Evita alterar la columna `updated_at` innecesariamente (preserva la auditoría real).
       ------------------------------------------------------------------------------------------------ */
    IF v_Activo_Actual = _Nuevo_Estatus THEN
        
        COMMIT; -- Liberamos el bloqueo (Lock) inmediatamente.
        
        -- Retorno informativo indicando que no hubo cambios.
        SELECT CASE 
            WHEN _Nuevo_Estatus = 1 THEN 'OPERACIÓN OMITIDA: El Puesto ya se encuentra en estado ACTIVO.' 
            ELSE 'OPERACIÓN OMITIDA: El Puesto ya se encuentra en estado INACTIVO.' 
        END AS Mensaje,
        v_Activo_Actual AS Activo_Anterior,
        _Nuevo_Estatus AS Activo_Nuevo;
        
        -- Salimos del bloque principal para terminar el SP.
        LEAVE THIS_PROC; 
    END IF;

    /* ================================================================================================
       BLOQUE 4: EVALUACIÓN DE REGLAS DE NEGOCIO COMPLEJAS (INTEGRIDAD REFERENCIAL)
       Propósito: Validar que el cambio de estado no rompa la coherencia de los datos relacionados.
       ================================================================================================ */

    /* ------------------------------------------------------------------------------------------------
       PASO 4.1: REGLA DE "BAJA SEGURA" (SAFE DELETE GUARD)
       Condición: Esta validación SOLO se ejecuta si intentamos DESACTIVAR (_Nuevo_Estatus = 0).
       Objetivo: Proteger a la tabla de Personal (`Info_Personal`) de tener asignados puestos "muertos".
       ------------------------------------------------------------------------------------------------ */
    IF _Nuevo_Estatus = 0 THEN
        
        -- Reiniciamos el semáforo
        SET v_Dependencias = NULL;
        
        -- [Sondeo de Dependencias]:
        -- Buscamos si existe AL MENOS UN registro en la tabla de Personal que cumpla dos condiciones:
        -- 1. Esté asignado a este Puesto (`Fk_Id_CatPuesto`).
        -- 2. El empleado esté ACTIVO (`Activo` = 1). (Los empleados históricos/baja no bloquean).
        SELECT 1 INTO v_Dependencias
        FROM `Info_Personal`
        WHERE `Fk_Id_CatPuesto` = _Id_Puesto
          AND `Activo` = 1 
        LIMIT 1;

        -- [Disparador de Bloqueo]: Si encontramos dependencias, abortamos la operación.
        IF v_Dependencias IS NOT NULL THEN
            SIGNAL SQLSTATE '45000' 
                SET MESSAGE_TEXT = 'CONFLICTO DE INTEGRIDAD [409]: No es posible dar de baja este Puesto. Existen EMPLEADOS ACTIVOS ocupando este cargo. Realice el cambio de puesto o baja del personal primero.';
        END IF;
    END IF;

    /* ================================================================================================
       BLOQUE 5: PERSISTENCIA Y FINALIZACIÓN (COMMIT)
       Propósito: Aplicar los cambios validados y confirmar la transacción.
       ================================================================================================ */

    /* ------------------------------------------------------------------------------------------------
       PASO 5.1: EJECUCIÓN DE LA ACTUALIZACIÓN (UPDATE)
       En este punto, hemos superado todas las validaciones (Input, Existencia, Idempotencia, Integridad).
       Es seguro escribir en la base de datos.
       ------------------------------------------------------------------------------------------------ */
    UPDATE `Cat_Puestos_Trabajo` 
    SET `Activo` = _Nuevo_Estatus, 
        `updated_at` = NOW() -- [Traza de Auditoría]: Actualizamos la marca de tiempo del sistema.
    WHERE `Id_CatPuesto` = _Id_Puesto;
    
    /* ------------------------------------------------------------------------------------------------
       PASO 5.2: CONFIRMACIÓN DE TRANSACCIÓN (COMMIT)
       Hacemos permanentes los cambios y liberamos los bloqueos (Locks).
       ------------------------------------------------------------------------------------------------ */
    COMMIT; 
    
    /* ------------------------------------------------------------------------------------------------
       PASO 5.3: GENERACIÓN DE RESPUESTA AL CLIENTE (RESPONSE MAPPING)
       Retornamos el estado final para que la interfaz de usuario pueda sincronizarse con el Backend.
       ------------------------------------------------------------------------------------------------ */
    SELECT CASE 
        WHEN _Nuevo_Estatus = 1 THEN 'ÉXITO: El Puesto ha sido REACTIVADO y está disponible para asignación.' 
        ELSE 'ÉXITO: El Puesto ha sido DESACTIVADO (Baja Lógica). No se mostrará en nuevos registros.' 
    END AS Mensaje,
    v_Activo_Actual AS Activo_Anterior,
    _Nuevo_Estatus AS Activo_Nuevo;

END$$

DELIMITER ;

/* ====================================================================================================
   PROCEDIMIENTO: SP_EliminarPuestoFisico
   ====================================================================================================
   
   1. VISIÓN GENERAL Y OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   ----------------------------------------------------------------------------------------------------
   Este procedimiento implementa la operación de ELIMINACIÓN FÍSICA (Hard Delete) sobre la entidad
   "Puesto de Trabajo" (`Cat_Puestos_Trabajo`).
   
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
       empleado está "Activo" o "Inactivo". Si un empleado *alguna vez* ocupó este puesto,
       el registro se vuelve INBORRABLE para preservar la trazabilidad histórica de los expedientes.
     - ACCIÓN: Devuelve un error 409 (Conflict) legible para el humano.

     ANILLO 3: VALIDACIÓN REACTIVA DE MOTOR (Database Constraint - Last Resort)
     - Se apoya en las Foreign Keys (FK) del motor InnoDB.
     - Si existe una relación oculta (ej: una tabla de "Vacantes" o "Perfiles" que olvidamos revisar),
       el motor bloqueará el DELETE lanzando el error 1451.
     - ACCIÓN: Un HANDLER captura este error y hace un Rollback seguro.

   3. MODELO DE CONCURRENCIA Y BLOQUEO (ACID COMPLIANCE)
   ----------------------------------------------------------------------------------------------------
   - AISLAMIENTO: Serializable (vía Locking).
   - MECÁNICA: Al ejecutar el comando `DELETE`, el motor InnoDB adquiere automáticamente un
     BLOQUEO EXCLUSIVO DE FILA (X-LOCK).
   - EFECTO: Nadie puede leer, editar o asignar este puesto a un empleado durante los milisegundos
     que dura la transacción de borrado.

   4. CONTRATO DE SALIDA (OUTPUT CONTRACT)
   ----------------------------------------------------------------------------------------------------
   Retorna un resultset de una sola fila (Single Row) indicando el éxito de la operación.
   En caso de fallo, se lanzan señales SQLSTATE controladas (400, 404, 409).
   ==================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_EliminarPuestoFisico`$$

CREATE PROCEDURE `SP_EliminarPuestoFisico`(
    /* PARÁMETRO DE ENTRADA */
    IN _Id_Puesto INT -- PK: Identificador único del Puesto a purgar.
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
            SET MESSAGE_TEXT = 'BLOQUEO DE INTEGRIDAD [1451]: El sistema de base de datos impidió el borrado. Existen registros en otras tablas (posiblemente Personal o Historial) vinculados a este Puesto que no fueron detectados por la validación previa.'; 
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
    IF _Id_Puesto IS NULL OR _Id_Puesto <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: El parámetro ID de Puesto es inválido o nulo.';
    END IF;

    /* 2.2 Validación de Existencia: Verificación contra el Catálogo Maestro.
       Nota: Hacemos esto antes de buscar dependencias para diferenciar un error "No encontrado" (404)
       de un error "No se puede borrar" (409). */
    IF NOT EXISTS (SELECT 1 FROM `Cat_Puestos_Trabajo` WHERE `Id_CatPuesto` = _Id_Puesto) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [404]: El Puesto que intenta eliminar no existe en la base de datos.';
    END IF;

    /* ================================================================================================
       BLOQUE 3: CANDADO DE NEGOCIO (LOGIC LOCK)
       Propósito: Aplicar las reglas de dominio específicas para la destrucción de información.
       ================================================================================================ */
    
    /* ------------------------------------------------------------------------------------------------
       PASO 3.1: INSPECCIÓN DE HISTORIAL LABORAL (`Info_Personal`)
       
       Objetivo Técnico:
       Escanear la tabla transaccional de empleados para ver si el Puesto _Id_Puesto
       ha sido utilizado alguna vez como llave foránea (`Fk_Id_CatPuesto`).
       
       Justificación de Negocio (POR QUÉ NO FILTRAMOS POR "ACTIVO"):
       Un empleado puede estar dado de baja (Inactivo) hoy, pero ocupó este puesto hace 3 años.
       Si borramos el Puesto físicamente, el registro histórico del empleado quedaría apuntando a NULL
       o generaría inconsistencia en los reportes de "Trayectoria Laboral".
       Por lo tanto, la mera existencia de un registro (activo o inactivo) es motivo de BLOQUEO.
       ------------------------------------------------------------------------------------------------ */
    SELECT 1 INTO v_Dependencias
    FROM `Info_Personal`
    WHERE `Fk_Id_CatPuesto` = _Id_Puesto
    LIMIT 1; -- Optimización: Con encontrar uno solo es suficiente para detener el proceso.

    /* ------------------------------------------------------------------------------------------------
       PASO 3.2: EVALUACIÓN DEL BLOQUEO
       Si la variable v_Dependencias dejó de ser NULL, significa que hay historial.
       ------------------------------------------------------------------------------------------------ */
    IF v_Dependencias IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'CONFLICTO DE NEGOCIO [409]: Operación denegada. No es posible eliminar este Puesto porque existen expedientes de PERSONAL (Activos o Históricos) asociados a él. La eliminación física rompería la integridad histórica. Utilice la opción "Desactivar/Baja Lógica".';
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
    DELETE FROM `Cat_Puestos_Trabajo` 
    WHERE `Id_CatPuesto` = _Id_Puesto;

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
        'ÉXITO: El Puesto ha sido eliminado permanentemente del sistema.' AS Mensaje, 
        'HARD_DELETE' AS Tipo_Operacion,
        _Id_Puesto AS Id_Recurso_Eliminado,
        NOW() AS Fecha_Ejecucion;

END$$

DELIMITER ;