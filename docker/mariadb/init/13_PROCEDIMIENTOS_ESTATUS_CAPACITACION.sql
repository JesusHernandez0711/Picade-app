USE `PICADE`;

/* ------------------------------------------------------------------------------------------------------ */
/* CREACION DE VISTAS Y PROCEDIMIENTOS DE ALMACENADO PARA LA BASE DE DATOS                                */
/* ------------------------------------------------------------------------------------------------------ */

/* ======================================================================================================
   1. VIEW: Vista_Estatus_Capacitacion
   ======================================================================================================
   
   1. OBJETIVO TÉCNICO Y DE NEGOCIO (BUSINESS GOAL)
   ------------------------------------------------
   Esta vista constituye la **Interfaz Maestra de Control de Estados** para el sistema PICADE. 
   Su función es proporcionar una lectura estandarizada de las etapas del ciclo de vida de una 
   capacitación (ej: Programado, En Curso, Finalizado).

   Es la fuente de verdad única para:
   - El Grid de Administración del Catálogo de Estatus.
   - Middlewares de autorización que verifican si una capacitación es "Final" para liberar temas.
   - Reportes de indicadores de avance y gestión operativa.

   2. ARQUITECTURA DE DISEÑO (FLATTENED LOOKUP)
   --------------------------------------------
   Al ser una tabla de referencia atómica (Catálogo Raíz), no requiere JOINs complejos hacia padres. 
   Sin embargo, su valor Diamond Standard reside en la **Normalización Semántica** y la 
   **Exposición de Lógica de Negocio**:
   
   - Abstracción de Identificadores: Se renombran columnas técnicas (Id_CatEstCap) a alias de negocio
     (Id_Estatus_Capacitacion) para asegurar que el contrato de datos (API/Frontend) sea legible.
   
   - Visibilidad de Atributos Críticos: Se expone de forma clara la bandera `Es_Final`, la cual 
     es el interruptor lógico que decide si una capacitación deja de ser un "compromiso activo" 
     en los calendarios.

   3. LÓGICA DE CONTROL Y VISIBILIDAD (SOFT DELETES)
   -------------------------------------------------
   - Principio de Auditoría Total: La vista proyecta todos los registros (Activos e Inactivos).
   - Justificación: Los administradores deben poder identificar estatus que han sido "deprecados" 
     pero que siguen existiendo en el historial de miles de capacitaciones pasadas. Ocultarlos 
     rompería la integridad visual de los reportes históricos.
   - El filtrado para selectores dinámicos se delega a los procedimientos específicos (SP_ListarActivos).

   4. DICCIONARIO DE DATOS (CONTRATO DE SALIDA)
   --------------------------------------------
   [Bloque 1: Identidad y Claves]
   - Id_Estatus_Capacitacion:  (INT) Identificador único y llave primaria.
   - Codigo_Estatus:           (VARCHAR) Clave corta única para lógica interna (ej: 'PROG', 'FIN').
   - Nombre_Estatus:           (VARCHAR) Denominación oficial y legible para el usuario.

   [Bloque 2: Información Operativa]
   - Descripcion_Estatus:      (VARCHAR) Explicación del significado de la etapa para el usuario.
   - Es_Estado_Final:          (TINYINT) Booleano: 1 = Indica que el curso concluyó (libera candados), 
                                0 = El curso sigue en proceso u operativo.

   [Bloque 3: Control y Auditoría]
   - Estatus_Activo:           (TINYINT) 1 = Disponible para nuevos registros, 0 = Baja Lógica.
   - Ultima_Actualizacion:     (TIMESTAMP) Marca de tiempo del último cambio realizado.
   ====================================================================================================== */

CREATE OR REPLACE 
    ALGORITHM = UNDEFINED 
    SQL SECURITY DEFINER
VIEW `PICADE`.`Vista_Estatus_Capacitacion` AS
    SELECT 
        /* -----------------------------------------------------------------------------------
           BLOQUE 1: IDENTIDAD Y CLAVES
           Estandarización de nombres para un consumo agnóstico desde el API/Frontend.
           ----------------------------------------------------------------------------------- */
        `Est`.`Id_CatEstCap`         AS `Id_Estatus_Capacitacion`,
        `Est`.`Codigo`               AS `Codigo_Estatus`,
        `Est`.`Nombre`               AS `Nombre_Estatus`,

        /* -----------------------------------------------------------------------------------
           BLOQUE 2: LÓGICA OPERATIVA Y DESCRIPCIÓN
           Campos que dictan el comportamiento del sistema ante este registro.
           ----------------------------------------------------------------------------------- */
         `Est`.`Descripcion`          AS `Descripcion_Estatus`,
        -- `Est`.`Es_Final`             AS `Bandera_de_Bloqueo`,

        /* -----------------------------------------------------------------------------------
           BLOQUE 3: METADATOS DE CICLO DE VIDA
           Control de borrado lógico (Activo/Inactivo).
           ----------------------------------------------------------------------------------- */
        `Est`.`Activo`               AS `Estatus_de_Capacitacion`
        
        /* -----------------------------------------------------------------------------------
           BLOQUE 4: TRAZABILIDAD
           Datos de auditoría para el administrador. Se expone la fecha de actualización
           para facilitar el ordenamiento en el Grid (Mostrar cambios recientes primero).
           ----------------------------------------------------------------------------------- */
		-- `Est`.`created_at`           AS `Fecha_de_Creacion`
        -- `Est`.`updated_at`           AS `Ultima_Actualizacion`

    FROM 
        `PICADE`.`Cat_Estatus_Capacitacion` `Est`;

/* --- VERIFICACIÓN DE LA VISTA --- */
-- SELECT * FROM Picade.Vista_Cat_Estatus_Capacitacion;

/* ====================================================================================================
   PROCEDIMIENTO: SP_RegistrarEstatusCapacitacion
   ====================================================================================================

   ----------------------------------------------------------------------------------------------------
   I. VISIÓN GENERAL Y OBJETIVO ESTRATÉGICO (EXECUTIVE SUMMARY)
   ----------------------------------------------------------------------------------------------------
   [DEFINICIÓN DEL COMPONENTE]:
   Este Stored Procedure actúa como el **Constructor de la Máquina de Estados** del sistema PICADE.
   Su responsabilidad es dar de alta los nodos lógicos que definirán el flujo de trabajo de las capacitaciones
   (ej: 'PROGRAMADO' -> 'EN CURSO' -> 'FINALIZADO').

   [EL PROBLEMA DE NEGOCIO (THE BUSINESS RISK)]:
   La integridad de los reportes operativos depende de que no existan estados duplicados, ambiguos o 
   "fantasmas". 
   - Riesgo 1 (Ambigüedad): Tener dos estados 'CANCELADO' y 'ANULADO' confunde a los usuarios y fragmenta la data.
   - Riesgo 2 (Inconsistencia): Un estado 'FINALIZADO' que no tenga la bandera `Es_Final=1` provocaría que 
     los cursos nunca liberen a sus instructores, bloqueando la programación futura.

   [LA SOLUCIÓN: GESTIÓN DE IDENTIDAD UNÍVOCA]:
   Este SP implementa una estrategia de **"Alta Inteligente con Autosanación"**.
   No solo inserta datos; verifica la existencia previa, resuelve conflictos de identidad y recupera 
   registros históricos ("Muertos") para evitar la proliferación de basura en la base de datos.

   ----------------------------------------------------------------------------------------------------
   II. DICCIONARIO DE REGLAS DE BLINDAJE (SECURITY & INTEGRITY RULES)
   ----------------------------------------------------------------------------------------------------
   
   [RN-01] INTEGRIDAD DE DATOS (MANDATORY FIELDS):
      - Principio: "Datos completos o nada".
      - Regla: El `Código` (ID Técnico) y el `Nombre` (ID Humano) son obligatorios.
      - Justificación: Un estatus sin código no puede ser referenciado por el backend. Un estatus sin nombre 
        es invisible para el usuario.
      - Nota: La `Descripción` es opcional (puede ir vacía).

   [RN-02] IDENTIDAD DE DOBLE FACTOR (DUAL IDENTITY CHECK):
      - Principio: "Unicidad Total".
      - Regla: No pueden existir dos estatus con el mismo CÓDIGO (ej: 'FIN'). Tampoco pueden existir dos 
        estatus con el mismo NOMBRE (ej: 'FINALIZADO').
      - Resolución: Se verifica primero el Código (Identificador fuerte) y luego el Nombre. Si hay conflicto 
        cruzado (mismo nombre, diferente código), se aborta para prevenir ambigüedad.

   [RN-03] AUTOSANACIÓN Y RECUPERACIÓN (SELF-HEALING PATTERN):
      - Principio: "Reciclar antes que crear".
      - Regla: Si el estatus que se intenta crear YA EXISTE pero fue eliminado lógicamente (`Activo=0`), 
        el sistema no lanza error. En su lugar, lo "resucita" (Reactiva), actualiza su configuración 
        (`Es_Final`, `Descripción`) y lo devuelve como éxito.

   [RN-04] TOLERANCIA A CONCURRENCIA (RACE CONDITION SHIELD):
      - Principio: "El usuario nunca ve un error técnico".
      - Escenario: Dos administradores intentan crear el mismo estatus al mismo tiempo.
      - Mecanismo: Se implementa el patrón "Re-Resolve". Si el INSERT falla por duplicado (Error 1062), 
        el SP captura el error, revierte la transacción y busca el registro "ganador" para devolverlo 
        como éxito transparente.

   ----------------------------------------------------------------------------------------------------
   III. ESPECIFICACIÓN TÉCNICA (DATABASE SPECS)
   ----------------------------------------------------------------------------------------------------
   - TIPO: Transacción ACID con Aislamiento Serializable (vía Row-Level Locking).
   - ESTRATEGIA DE BLOQUEO: `SELECT ... FOR UPDATE` (Pessimistic Locking).
     * Congela la fila encontrada o el rango de índice durante la validación.
     * Evita lecturas sucias y condiciones de carrera en la verificación de existencia.
   - IDEMPOTENCIA: Si se solicita crear un estatus que ya existe y es idéntico, el sistema retorna éxito 
     sin consumir ciclos de escritura (I/O Optimization).
   ==================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_RegistrarEstatusCapacitacion`$$

CREATE PROCEDURE `SP_RegistrarEstatusCapacitacion`(
    /* ------------------------------------------------------------------------------------------------
       SECCIÓN DE PARÁMETROS DE ENTRADA (INPUT LAYER)
       Recibimos los datos crudos del formulario. Se asume que requieren sanitización.
       ------------------------------------------------------------------------------------------------ */
    IN _Codigo      VARCHAR(50),   -- [OBLIGATORIO] Clave única interna (ej: 'PROG').
    IN _Nombre      VARCHAR(255),  -- [OBLIGATORIO] Nombre descriptivo único (ej: 'PROGRAMADO').
    IN _Descripcion VARCHAR(255),  -- [OPCIONAL] Contexto detallado de uso.
    IN _Es_Final    TINYINT(1)     -- [CRÍTICO] Bandera de lógica de negocio (0=Vivo/Bloqueante, 1=Muerto/Liberador).
)
THIS_PROC: BEGIN
    
    /* ============================================================================================
       BLOQUE 0: INICIALIZACIÓN DE VARIABLES DE ENTORNO
       Definición de contenedores para almacenar el estado de la base de datos y diagnósticos.
       ============================================================================================ */
    
    /* Variables de Persistencia (Snapshot del registro en BD) */
    DECLARE v_Id_Estatus INT DEFAULT NULL;       -- Almacena el ID si encontramos el registro.
    DECLARE v_Activo     TINYINT(1) DEFAULT NULL; -- Almacena el estado actual (Activo/Inactivo).
    
    /* Variables para Validación Cruzada (Cross-Check de identidad) */
    DECLARE v_Nombre_Existente VARCHAR(255) DEFAULT NULL;
    DECLARE v_Codigo_Existente VARCHAR(50) DEFAULT NULL;
    
    /* Bandera de Semáforo: Controla el flujo lógico cuando ocurren excepciones SQL controladas */
    DECLARE v_Dup TINYINT(1) DEFAULT 0;

    /* ============================================================================================
       BLOQUE 1: DEFINICIÓN DE HANDLERS (SISTEMA DE DEFENSA)
       Propósito: Asegurar que el procedimiento termine de forma controlada ante cualquier eventualidad.
       ============================================================================================ */
    
    /* 1.1 HANDLER DE COLISIÓN (Error 1062 - Duplicate Entry)
       Objetivo: Capturar colisiones de Unique Key en el INSERT final (nuestra red de seguridad).
       Estrategia: "Graceful Degradation". En lugar de abortar, encendemos la bandera v_Dup
       para activar la rutina de recuperación (Re-Resolve) más adelante. */
    DECLARE CONTINUE HANDLER FOR 1062 SET v_Dup = 1;

    /* 1.2 HANDLER CRÍTICO (SQLEXCEPTION)
       Objetivo: Capturar fallos de infraestructura (Disco lleno, Conexión perdida, Error de Sintaxis).
       Estrategia: "Abort & Report". Ante fallos de sistema, revertimos cualquier cambio parcial 
       (ROLLBACK) y propagamos el error original (RESIGNAL) para los logs del backend. */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; 
    END;

    /* ============================================================================================
       BLOQUE 2: SANITIZACIÓN Y VALIDACIÓN (FAIL FAST STRATEGY)
       Propósito: Proteger la base de datos de datos basura antes de abrir transacciones costosas.
       ============================================================================================ */
    
    /* 2.1 NORMALIZACIÓN DE CADENAS
       Eliminamos espacios redundantes (TRIM). NULLIF convierte cadenas vacías '' en NULL reales
       para facilitar la validación booleana estricta. */
    SET _Codigo      = NULLIF(TRIM(_Codigo), '');
    SET _Nombre      = NULLIF(TRIM(_Nombre), '');
    SET _Descripcion = NULLIF(TRIM(_Descripcion), '');
    
    /* Sanitización de Bandera Lógica: Si viene NULL, asumimos FALSE (0 - Bloqueante) por seguridad. */
    SET _Es_Final    = IFNULL(_Es_Final, 0);

    /* 2.2 VALIDACIÓN DE INTEGRIDAD DE CAMPOS OBLIGATORIOS
       Regla: Un Estatus sin Código o Nombre es una entidad corrupta. */
    
    IF _Codigo IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN [400]: El CÓDIGO del estatus es obligatorio.';
    END IF;

    IF _Nombre IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN [400]: El NOMBRE del estatus es obligatorio.';
    END IF;

    /* 2.3 VALIDACIÓN DE DOMINIO (Valores permitidos)
       Regla de Negocio: Es_Final es binario. */
    IF _Es_Final NOT IN (0, 1) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE LÓGICA [400]: El campo Es_Final solo acepta 0 (Bloqueante) o 1 (Final).';
    END IF;

    /* ============================================================================================
       BLOQUE 3: LÓGICA TRANSACCIONAL PRINCIPAL (CORE BUSINESS LOGIC)
       Propósito: Ejecutar la búsqueda, validación y persistencia de forma atómica.
       ============================================================================================ */
    START TRANSACTION;

    /* --------------------------------------------------------------------------------------------
       PASO 3.1: VERIFICACIÓN PRIMARIA POR CÓDIGO (STRONG ID CHECK)
       Objetivo: Determinar si el identificador técnico ya existe.
       Estrategia: Bloqueo Pesimista (FOR UPDATE) para serializar el acceso a este registro.
       Esto evita que otro admin modifique este registro mientras lo evaluamos.
       -------------------------------------------------------------------------------------------- */
    SET v_Id_Estatus = NULL; -- Reset de seguridad

    SELECT `Id_CatEstCap`, `Nombre`, `Activo` 
    INTO v_Id_Estatus, v_Nombre_Existente, v_Activo
    FROM `Cat_Estatus_Capacitacion`
    WHERE `Codigo` = _Codigo
    LIMIT 1
    FOR UPDATE; -- <--- BLOQUEO DE ESCRITURA AQUÍ

    /* ESCENARIO A: EL CÓDIGO YA EXISTE EN LA BASE DE DATOS */
    IF v_Id_Estatus IS NOT NULL THEN
        
        /* A.1 Validación de Consistencia Semántica
           Regla: Si el código existe, el Nombre asociado debe coincidir con el input.
           Fallo: Si el código es igual pero el nombre diferente, es un conflicto de integridad. */
        IF v_Nombre_Existente <> _Nombre THEN
            ROLLBACK; -- Liberamos el bloqueo antes de lanzar error
            SIGNAL SQLSTATE '45000' 
                SET MESSAGE_TEXT = 'CONFLICTO DE DATOS [409]: El CÓDIGO ingresado ya existe pero está asignado a otro nombre.';
        END IF;

        /* A.2 Autosanación (Self-Healing)
           Si el registro existe pero está borrado lógicamente (Activo=0), lo recuperamos.
           NOTA: Se actualizan también la Descripción y la bandera Es_Final con los datos nuevos. */
        IF v_Activo = 0 THEN
            UPDATE `Cat_Estatus_Capacitacion`
            SET `Activo` = 1,
                /* Lógica de actualización: Si el usuario mandó nueva descripción, la usamos. 
                   Si mandó NULL, conservamos la antigua. */
                `Descripcion` = COALESCE(_Descripcion, `Descripcion`),
                `Es_Final` = _Es_Final, -- Actualización crítica de lógica de negocio
                `updated_at` = NOW()
            WHERE `Id_CatEstCap` = v_Id_Estatus;
            
            COMMIT;
            SELECT 'ÉXITO: Estatus recuperado y actualizado correctamente.' AS Mensaje, v_Id_Estatus AS Id_Estatus, 'REACTIVADA' AS Accion;
            LEAVE THIS_PROC;
        
        /* A.3 Idempotencia
           Si ya existe y está activo, no duplicamos ni fallamos. Reportamos éxito silente. */
        ELSE
            COMMIT;
            SELECT 'AVISO: El código del estatus ya existe y está activo.' AS Mensaje, v_Id_Estatus AS Id_Estatus, 'REUSADA' AS Accion;
            LEAVE THIS_PROC;
        END IF;
    END IF;

    /* --------------------------------------------------------------------------------------------
       PASO 3.2: VERIFICACIÓN SECUNDARIA POR NOMBRE (WEAK ID CHECK)
       Objetivo: Si el Código es nuevo, asegurarnos que el NOMBRE no esté ocupado por otro código.
       Esto previene duplicados semánticos (ej: dos estatus 'CANCELADO' con códigos distintos).
       -------------------------------------------------------------------------------------------- */
    SET v_Id_Estatus = NULL; -- Reset

    SELECT `Id_CatEstCap`, `Codigo`, `Activo`
    INTO v_Id_Estatus, v_Codigo_Existente, v_Activo
    FROM `Cat_Estatus_Capacitacion`
    WHERE `Nombre` = _Nombre
    LIMIT 1
    FOR UPDATE; -- <--- BLOQUEO DE ESCRITURA AQUÍ

    /* ESCENARIO B: EL NOMBRE YA EXISTE */
    IF v_Id_Estatus IS NOT NULL THEN
        
        /* B.1 Detección de Conflicto Cruzado
           El nombre existe, pero tiene un código diferente al que intentamos registrar. */
        IF v_Codigo_Existente <> _Codigo THEN
             ROLLBACK;
             SIGNAL SQLSTATE '45000' 
             SET MESSAGE_TEXT = 'CONFLICTO DE DATOS [409]: El NOMBRE ya existe asociado a otro CÓDIGO diferente.';
        END IF;

        /* B.2 Data Enrichment (Caso Legacy)
           Si el registro existía con Código NULL (datos viejos), le asignamos el nuevo código. */
        IF v_Codigo_Existente IS NULL THEN
             UPDATE `Cat_Estatus_Capacitacion` SET `Codigo` = _Codigo, `updated_at` = NOW() WHERE `Id_CatEstCap` = v_Id_Estatus;
        END IF;

        /* B.3 Autosanación por Nombre
           Si estaba inactivo, lo reactivamos y actualizamos su configuración lógica. */
        IF v_Activo = 0 THEN
            UPDATE `Cat_Estatus_Capacitacion` 
            SET `Activo` = 1, 
                `Descripcion` = COALESCE(_Descripcion, `Descripcion`),
                `Es_Final` = _Es_Final,
                `updated_at` = NOW() 
            WHERE `Id_CatEstCap` = v_Id_Estatus;
            
            COMMIT;
            SELECT 'ÉXITO: Estatus reactivado (encontrado por Nombre).' AS Mensaje, v_Id_Estatus AS Id_Estatus, 'REACTIVADA' AS Accion;
            LEAVE THIS_PROC;
        END IF;

        /* B.4 Idempotencia por Nombre */
        COMMIT;
        SELECT 'AVISO: El estatus ya existe y está activo.' AS Mensaje, v_Id_Estatus AS Id_Estatus, 'REUSADA' AS Accion;
        LEAVE THIS_PROC;
    END IF;

    /* --------------------------------------------------------------------------------------------
       PASO 3.3: PERSISTENCIA FÍSICA (INSERT)
       Si llegamos aquí, no hay colisiones conocidas. Procedemos a insertar.
       Aquí existe un riesgo infinitesimal de "Race Condition" si otro usuario inserta en este preciso instante.
       -------------------------------------------------------------------------------------------- */
    SET v_Dup = 0; -- Reiniciar bandera de error
    
    INSERT INTO `Cat_Estatus_Capacitacion`
    (
        `Codigo`, 
        `Nombre`, 
        `Descripcion`, 
        `Es_Final`, 
        `Activo`,
        `created_at`,
        `updated_at`
    )
    VALUES
    (
        _Codigo, 
        _Nombre, 
        _Descripcion, 
        _Es_Final,
        1,      -- Default: Activo
        NOW(),  -- Timestamp Creación
        NOW()   -- Timestamp Actualización
    );

    /* Verificación de Éxito: Si v_Dup sigue en 0, el INSERT fue limpio. */
    IF v_Dup = 0 THEN
        COMMIT; 
        SELECT 'ÉXITO: Estatus registrado correctamente.' AS Mensaje, LAST_INSERT_ID() AS Id_Estatus, 'CREADA' AS Accion; 
        LEAVE THIS_PROC;
    END IF;

    /* ============================================================================================
       BLOQUE 4: SUBRUTINA DE RECUPERACIÓN DE CONCURRENCIA (RE-RESOLVE PATTERN)
       Propósito: Manejar elegantemente el Error 1062 (Duplicate Key) si ocurre una condición de carrera.
       ============================================================================================ */
    
    /* Si estamos aquí, v_Dup = 1. Significa que "perdimos" la carrera contra otro INSERT concurrente. */
    
    ROLLBACK; -- 1. Revertir la transacción fallida para liberar bloqueos parciales.
    
    START TRANSACTION; -- 2. Iniciar una nueva transacción limpia.
    
    SET v_Id_Estatus = NULL;
    
    /* 3. Buscar el registro "ganador" (El que insertó el otro usuario) */
    SELECT `Id_CatEstCap`, `Activo`, `Nombre`
    INTO v_Id_Estatus, v_Activo, v_Nombre_Existente
    FROM `Cat_Estatus_Capacitacion`
    WHERE `Codigo` = _Codigo
    LIMIT 1
    FOR UPDATE;
    
    IF v_Id_Estatus IS NOT NULL THEN
        /* Validación de Seguridad Post-Recuperación */
        IF v_Nombre_Existente <> _Nombre THEN
             SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR CRÍTICO [500]: Concurrencia detectada con conflicto de datos.';
        END IF;

        /* Reactivar si el ganador estaba inactivo */
        IF v_Activo = 0 THEN
            UPDATE `Cat_Estatus_Capacitacion` 
            SET `Activo` = 1, `Es_Final` = _Es_Final, `updated_at` = NOW() 
            WHERE `Id_CatEstCap` = v_Id_Estatus;
            
            COMMIT; 
            SELECT 'ÉXITO: Estatus reactivado (tras concurrencia).' AS Mensaje, v_Id_Estatus AS Id_Estatus, 'REACTIVADA' AS Accion; 
            LEAVE THIS_PROC;
        END IF;
        
        /* Retornar el ID existente */
        COMMIT; 
        SELECT 'AVISO: Estatus ya existente (reusado tras concurrencia).' AS Mensaje, v_Id_Estatus AS Id_Estatus, 'REUSADA' AS Accion; 
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
   PROCEDIMIENTO: SP_ConsultarEstatusCapacitacionEspecifico
   ============================================================================================
   
   --------------------------------------------------------------------------------------------
   I. OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   --------------------------------------------------------------------------------------------
   [QUÉ ES]:
   Es el endpoint de lectura de alta fidelidad para recuperar la "Ficha Técnica" de un Estatus 
   de Capacitación específico, identificado por su llave primaria (`Id_CatEstCap`).

   [PARA QUÉ SE USA (CONTEXTO DE UI)]:
   A) PRECARGA DE FORMULARIO DE EDICIÓN (UPDATE):
      - Cuando el administrador va a modificar un estatus (ej: cambiar la regla de bloqueo), 
        el formulario debe "hidratarse" con los datos exactos que residen en la base de datos.
      - Requisito Crítico: La fidelidad del dato. Los valores se entregan crudos (Raw Data) 
        para que los inputs del HTML reflejen la realidad sin transformaciones cosméticas.

   B) VISUALIZACIÓN DE DETALLE (AUDITORÍA):
      - Permite visualizar metadatos de auditoría (`created_at`, `updated_at`) y configuración 
        lógica profunda (`Es_Final`) que suele estar oculta en el listado general.

   --------------------------------------------------------------------------------------------
   II. ARQUITECTURA DE DATOS (DIRECT TABLE ACCESS)
   --------------------------------------------------------------------------------------------
   Este procedimiento consulta directamente la tabla física `Cat_Estatus_Capacitacion`.
   
   [JUSTIFICACIÓN TÉCNICA]:
   - Desacoplamiento de Presentación: A diferencia de las Vistas (que formatean datos para lectura 
     humana), este SP prepara los datos para el consumo del sistema (Binding de Modelos).
   - Performance: El acceso por Primary Key (`Id_CatEstCap`) tiene un costo computacional de O(1), 
     garantizando una respuesta instantánea (<1ms).

   --------------------------------------------------------------------------------------------
   III. ESTRATEGIA DE SEGURIDAD (DEFENSIVE PROGRAMMING)
   --------------------------------------------------------------------------------------------
   - Validación de Entrada: Se rechazan IDs nulos o negativos antes de tocar el disco.
   - Fail Fast (Fallo Rápido): Se verifica la existencia del registro antes de intentar devolver datos. 
     Esto permite diferenciar claramente entre un "Error 404" (Recurso no encontrado) y un 
     "Error 500" (Fallo de servidor).

   --------------------------------------------------------------------------------------------
   IV. VISIBILIDAD (SCOPE)
   --------------------------------------------------------------------------------------------
   - NO se filtra por `Activo = 1`.
   - Razón: Un estatus puede estar "Desactivado" (Baja Lógica). El administrador necesita poder 
     consultarlo para ver su configuración y decidir si lo Reactiva.

   --------------------------------------------------------------------------------------------
   V. DICCIONARIO DE DATOS (OUTPUT CONTRACT)
   --------------------------------------------------------------------------------------------
   Retorna una única fila (Single Row) mapeada semánticamente:
      - [Id_Estatus]: Llave primaria.
      - [Codigo_Estatus]: Clave corta técnica.
      - [Nombre_Estatus]: Etiqueta humana.
      - [Descripcion_Estatus]: Contexto.
      - [Bandera_de_Bloqueo]: Alias de negocio para `Es_Final` (0=Bloquea, 1=Libera).
      - [Estatus]: Alias de negocio para `Activo` (1=Vigente, 0=Baja).
      - [Auditoría]: Fechas de creación y modificación.
   ============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ConsultarEstatusCapacitacionEspecifico`$$

CREATE PROCEDURE `SP_ConsultarEstatusCapacitacionEspecifico`(
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
    IF NOT EXISTS (SELECT 1 FROM `Cat_Estatus_Capacitacion` WHERE `Id_CatEstCap` = _Id_Estatus) THEN
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [404]: El Estatus de Capacitación solicitado no existe o fue eliminado físicamente.';
    END IF;

    /* ========================================================================================
       BLOQUE 3: CONSULTA PRINCIPAL (DATA RETRIEVAL)
       Objetivo: Retornar el objeto de datos completo y puro (Raw Data) con alias semánticos.
       ======================================================================================== */
    SELECT 
        /* --- GRUPO A: IDENTIDAD DEL REGISTRO --- */
        /* Este ID es la llave primaria inmutable. */
        `Id_CatEstCap`   AS `Id_Estatus`,
        
        /* --- GRUPO B: DATOS EDITABLES --- */
        /* El Frontend usará estos campos para llenar los inputs de texto. */
        `Codigo`         AS `Codigo_Estatus`,
        `Nombre`         AS `Nombre_Estatus`,
        `Descripcion`    AS `Descripcion_Estatus`,
        
        /* --- GRUPO C: LÓGICA DE NEGOCIO (CORE LOGIC) --- */
        /* [IMPORTANTE]: Este campo define el comportamiento de los Killswitches.
           Alias: `Bandera_de_Bloqueo` 
           Valor 0 = El proceso está vivo (Bloquea eliminación de temas/usuarios).
           Valor 1 = El proceso terminó (Libera recursos). */
        `Es_Final`       AS `Bandera_de_Bloqueo`,

        /* --- GRUPO D: METADATOS DE CONTROL DE CICLO DE VIDA --- */
        /* Este valor (0 o 1) indica si el estatus es utilizable actualmente en nuevos registros.
           1 = Activo/Visible, 0 = Inactivo/Oculto (Baja Lógica). */
        `Activo`         AS `Estatus_de_Capacitacion`,        
        
        /* --- GRUPO E: AUDITORÍA DE SISTEMA --- */
        /* Fechas útiles para mostrar en el pie de página del modal de detalle o tooltip. */
        `created_at`     AS `Fecha_Registro`,
        `updated_at`     AS `Ultima_Modificacion`
        
    FROM `Cat_Estatus_Capacitacion`
    WHERE `Id_CatEstCap` = _Id_Estatus
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
   PROCEDIMIENTO: SP_ListarEstatusCapacitacionActivos
   ============================================================================================
   
   1. OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   --------------------------------------
   Proveer un endpoint de datos de alta velocidad para alimentar el componente visual 
   "Selector de Estatus" (Dropdown) en los formularios de gestión operativa (ej: "Actualizar 
   Avance de Curso").

   Este procedimiento es la fuente autorizada para que los Coordinadores o Instructores 
   cambien el estado de una capacitación (de 'Programado' a 'En Curso', etc.).

   2. REGLAS DE NEGOCIO Y FILTRADO (THE VIGENCY CONTRACT)
   ------------------------------------------------------
   A) FILTRO DE VIGENCIA ESTRICTO (HARD FILTER):
      - Regla: La consulta aplica obligatoriamente la cláusula `WHERE Activo = 1`.
      - Justificación Operativa: Un Estatus marcado como inactivo (Baja Lógica) indica que esa 
        fase del proceso ya no se utiliza en la metodología actual de la empresa. Permitir su 
        selección generaría datos inconsistentes con los procesos vigentes.
      - Seguridad: El filtro es nativo en BD, impidiendo que una UI desactualizada inyecte 
        estados obsoletos.

   B) ORDENAMIENTO COGNITIVO (USABILITY):
      - Regla: Los resultados se ordenan alfabéticamente por `Nombre` (A-Z).
      - Justificación: Facilita la búsqueda visual rápida en la lista desplegable.

   3. ARQUITECTURA DE DATOS (ROOT ENTITY OPTIMIZATION)
   ---------------------------------------------------
   - Ausencia de JOINs: `Cat_Estatus_Capacitacion` es una Entidad Raíz (no tiene dependencias 
     jerárquicas hacia arriba). Esto permite una ejecución directa sobre el índice primario.
   
   - Proyección Mínima (Payload Reduction):
     Solo se devuelven las columnas vitales para construir el elemento HTML `<option>`:
       1. ID (Value): Para la integridad referencial.
       2. Nombre (Label): Para la lectura humana.
       3. Código (Hint/Badge): Para lógica visual en el frontend (ej: pintar de rojo si es 'CAN').
     
     Se omiten campos pesados como `Descripcion` o auditoría (`created_at`) para minimizar 
     la latencia de red en dispositivos móviles o conexiones lentas.

   4. DICCIONARIO DE DATOS (OUTPUT JSON SCHEMA)
   --------------------------------------------
   Retorna un array de objetos ligeros:
      - `Id_CatEstCap`: (INT) Llave Primaria. Value del selector.
      - `Codigo`:       (VARCHAR) Clave corta (ej: 'PROG'). Útil para badges de colores.
      - `Nombre`:       (VARCHAR) Texto principal (ej: 'Programado').
   ============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ListarEstatusCapacitacionActivos`$$

CREATE PROCEDURE `SP_ListarEstatusCapacitacionActivos`()
BEGIN
    /* ========================================================================================
       BLOQUE ÚNICO: CONSULTA DE SELECCIÓN OPTIMIZADA
       No requiere validaciones de entrada ya que es una consulta de catálogo global.
       ======================================================================================== */
    
    SELECT 
        /* IDENTIFICADOR ÚNICO (PK)
           Este es el valor que se guardará como Foreign Key (Fk_Id_CatEstCap) 
           en la tabla operativa 'DatosCapacitaciones'. */
        `Id_CatEstCap`, 
        
        /* CLAVE CORTA / MNEMOTÉCNICA
           Dato auxiliar para que el Frontend pueda aplicar estilos condicionales.
           Ej: Si Codigo == 'CAN' (Cancelado) -> Pintar texto en Rojo.
               Si Codigo == 'FIN' (Finalizado) -> Pintar texto en Verde. */
        `Codigo`, 
        
        /* DESCRIPTOR HUMANO
           El texto principal que el usuario leerá en la lista desplegable. */
        `Nombre`

    FROM 
        `Cat_Estatus_Capacitacion`
    
    /* ----------------------------------------------------------------------------------------
       FILTRO DE SEGURIDAD OPERATIVA (VIGENCIA)
       Ocultamos todo lo que no sea "1" (Activo). 
       Esto asegura que las operaciones vivas solo usen estados aprobados actualmente.
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

/* ============================================================================================
   PROCEDIMIENTO: SP_ListarEstatusCapacitacion
   ============================================================================================
   
   1. OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   --------------------------------------
   Proveer el inventario maestro y completo de los "Estatus de Capacitación" para alimentar el 
   Grid Principal del Módulo de Administración.
   
   Permite al administrador:
     - Auditar la totalidad de estados configurados (Histórico y Actual).
     - Identificar qué estados son "Finales" (liberadores) y cuáles "Bloqueantes".
     - Gestionar el ciclo de vida (Reactivar estatus que fueron dados de baja por error).

   2. ARQUITECTURA DE DATOS (VIEW CONSUMPTION PATTERN)
   ---------------------------------------------------
   Este procedimiento implementa el patrón de "Abstracción de Lectura" al consumir la vista 
   `Vista_Estatus_Capacitacion` en lugar de la tabla física.
   
   [VENTAJAS TÉCNICAS]:
     - Desacoplamiento: El Grid del Frontend se acopla a los nombres de columnas estandarizados 
       de la Vista (ej: `Estatus_Activo`, `Descripcion_Estatus`) y no a los nombres técnicos 
       de la tabla física.
     - Estandarización: La vista ya maneja la proyección de columnas limpias y cualquier 
       lógica de presentación necesaria.

   3. DIFERENCIA CRÍTICA CON EL DROPDOWN (VISIBILIDAD)
   ---------------------------------------------------
   A diferencia de `SP_ListarEstatusCapacitacionActivos`, aquí NO EXISTE la cláusula 
   `WHERE Activo = 1`.
   
   [JUSTIFICACIÓN]:
     - En Administración, "Ocultar" es "Perder". Un registro inactivo (`Activo = 0`) 
       debe ser visible en la tabla para poder editarlo o reactivarlo. Si lo ocultamos aquí, 
       sería imposible recuperarlo sin acceso directo a la base de datos (SQL).

   4. ESTRATEGIA DE ORDENAMIENTO (UX PRIORITY)
   -------------------------------------------
   El ordenamiento está diseñado para la eficiencia administrativa:
     1. Prioridad Operativa (Estatus DESC): Los registros VIGENTES (1) aparecen arriba. 
        Los obsoletos (0) se van al fondo de la tabla.
     2. Orden Alfabético (Nombre ASC): Dentro de cada grupo, se ordenan A-Z para facilitar 
        la búsqueda visual.

   5. DICCIONARIO DE DATOS (OUTPUT VIA VIEW)
   -----------------------------------------
   Retorna las columnas definidas en `Vista_Estatus_Capacitacion`:
     - Id_Estatus_Capacitacion, Codigo_Estatus, Nombre_Estatus.
     - Descripcion_Estatus.
     - Estatus_Activo (1=Sí, 0=No).
   ============================================================================================ */

DELIMITER $$

 -- DROP PROCEDURE IF EXISTS `SP_ListarEstatusCapacitacion`$$

CREATE PROCEDURE `SP_ListarEstatusCapacitacion`()
BEGIN
    /* ========================================================================================
       BLOQUE ÚNICO: CONSULTA MAESTRA SOBRE LA VISTA
       No requiere parámetros ni validaciones previas al ser una lectura global del catálogo.
       ======================================================================================== */
    
    SELECT 
        /* Proyección total de la Vista Maestra.
           Incluye: ID, Código, Nombre, Descripción, Estatus Activo. */
        * FROM 
        `Vista_Estatus_Capacitacion`
    
    /* ========================================================================================
       ORDENAMIENTO ESTRATÉGICO
       Optimizamos la presentación para el usuario administrador.
       ======================================================================================== */
    ORDER BY 
        `Estatus_de_Capacitacion` DESC,  -- 1º: Los activos arriba (Prioridad de atención)
        `Nombre_Estatus` ASC;   -- 2º: Orden alfabético para búsqueda rápida visual

END$$

DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_EditarEstatusCapacitacion
   ============================================================================================
   
   --------------------------------------------------------------------------------------------
   I. VISIÓN GENERAL Y OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   --------------------------------------------------------------------------------------------
   [QUÉ ES]:
   Es el motor transaccional blindado encargado de modificar los atributos descriptivos y la
   Lógica de Negocio (`Es_Final`) de un Estatus de Capacitación existente.

   [POR QUÉ ES CRÍTICO]:
   Este catálogo gobierna el comportamiento del sistema. 
   - Modificar un nombre es trivial.
   - Pero modificar la bandera `Es_Final` tiene consecuencias operativas masivas: puede liberar
     o bloquear la edición de miles de cursos e instructores asociados.
   
   Por ello, este SP no es un simple UPDATE. Es una orquestación de bloqueos y validaciones 
   diseñada para operar bajo fuego (alta concurrencia) sin corromper la data.

   --------------------------------------------------------------------------------------------
   II. ARQUITECTURA DE CONCURRENCIA (DETERMINISTIC LOCKING PATTERN)
   --------------------------------------------------------------------------------------------
   [EL PROBLEMA DE LOS ABRAZOS MORTALES (DEADLOCKS)]:
   Imagina que el Admin A quiere renombrar el estatus 'X' a 'Y', y al mismo tiempo el Admin B
   quiere renombrar el estatus 'Y' a 'X'. 
   Si bloquean los registros en orden diferente, la base de datos mata uno de los procesos.

   [LA SOLUCIÓN MATEMÁTICA]:
   Implementamos el patrón de "Bloqueo Determinístico":
   1. Identificamos todos los IDs involucrados (El que edito + El que tiene el código que quiero + El que tiene el nombre que quiero).
   2. Los ordenamos de MENOR a MAYOR.
   3. Los bloqueamos (`FOR UPDATE`) siguiendo estrictamente ese orden "en fila india".
   Resultado: Cero Deadlocks garantizados.

   --------------------------------------------------------------------------------------------
   III. REGLAS DE BLINDAJE (HARD CONSTRAINTS)
   --------------------------------------------------------------------------------------------
   [RN-01] INTEGRIDAD TOTAL: Código, Nombre y Es_Final son obligatorios.
   [RN-02] EXCLUSIÓN PROPIA: Puedo llamarme igual a mí mismo, pero no igual a mi vecino.
   [RN-03] IDEMPOTENCIA: Si guardas sin cambios, el sistema lo detecta y no toca el disco duro.

   ============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_EditarEstatusCapacitacion`$$

CREATE PROCEDURE `SP_EditarEstatusCapacitacion`(
    /* -----------------------------------------------------------------
       SECCIÓN DE PARÁMETROS DE ENTRADA (INPUT LAYER)
       Recibimos los datos crudos desde el formulario web.
       ----------------------------------------------------------------- */
    IN _Id_Estatus  INT,           -- [OBLIGATORIO] PK del registro a editar (Target).
    IN _Codigo      VARCHAR(50),   -- [OBLIGATORIO] Nuevo Código (o el mismo).
    IN _Nombre      VARCHAR(255),  -- [OBLIGATORIO] Nuevo Nombre (o el mismo).
    IN _Descripcion VARCHAR(255),  -- [OPCIONAL] Nueva Descripción (Contexto).
    IN _Es_Final    TINYINT(1)     -- [CRÍTICO] 0=Bloqueante (Vivo), 1=Liberador (Finalizado).
)
THIS_PROC: BEGIN

    /* ========================================================================================
       BLOQUE 0: DECLARACIÓN DE VARIABLES DE ESTADO Y CONTEXTO
       Propósito: Inicializar los contenedores en memoria para la lógica del procedimiento.
       ======================================================================================== */
    
    /* [Snapshots]: Almacenan la "foto" del registro ANTES de editarlo. 
       Vitales para comparar si hubo cambios reales (Idempotencia). */
    DECLARE v_Cod_Act    VARCHAR(50)  DEFAULT NULL;
    DECLARE v_Nom_Act    VARCHAR(255) DEFAULT NULL;
    DECLARE v_Desc_Act   VARCHAR(255) DEFAULT NULL;
    DECLARE v_Final_Act  TINYINT(1)   DEFAULT NULL;
    
    /* [IDs de Conflicto]: Identifican a "los otros" registros que podrían estorbar. */
    DECLARE v_Id_Conflicto_Cod INT DEFAULT NULL; -- ¿Quién tiene ya este Código?
    DECLARE v_Id_Conflicto_Nom INT DEFAULT NULL; -- ¿Quién tiene ya este Nombre?
    
    /* --- CORRECCIÓN: SE AGREGA LA VARIABLE FALTANTE PARA EL BLOQUE 6 --- */
    DECLARE v_Id_Conflicto     INT DEFAULT NULL; -- Variable genérica para reportar errores

    /* [Variables de Algoritmo de Bloqueo]: Auxiliares para ordenar y ejecutar los locks. */
    DECLARE v_L1 INT DEFAULT NULL;   -- Candidato 1 a bloquear
    DECLARE v_L2 INT DEFAULT NULL;   -- Candidato 2 a bloquear
    DECLARE v_L3 INT DEFAULT NULL;   -- Candidato 3 a bloquear
    DECLARE v_Min INT DEFAULT NULL;  -- El menor de la ronda actual
    DECLARE v_Existe INT DEFAULT NULL; -- Validación de éxito del lock

    /* [Bandera de Control]: Semáforo para detectar errores de concurrencia (Error 1062). */
    DECLARE v_Dup TINYINT(1) DEFAULT 0;

    /* [Variables de Diagnóstico]: Para el análisis Post-Mortem en caso de fallo. */
    DECLARE v_Campo_Error VARCHAR(20) DEFAULT NULL;
    DECLARE v_Id_Error    INT DEFAULT NULL;

    /* ========================================================================================
       BLOQUE 1: HANDLERS (SISTEMA DE DEFENSA)
       Propósito: Capturar excepciones técnicas y convertirlas en respuestas controladas.
       ======================================================================================== */
    
    /* 1.1 HANDLER DE DUPLICIDAD (Error 1062)
       Objetivo: Si ocurre una "Race Condition" en el último milisegundo (alguien insertó el duplicado
       justo antes de nuestro UPDATE), no abortamos. Activamos la bandera v_Dup. */
    DECLARE CONTINUE HANDLER FOR 1062 SET v_Dup = 1;

    /* 1.2 HANDLER GENÉRICO (SQLEXCEPTION)
       Objetivo: Ante fallos catastróficos (Disco lleno, Red caída), abortamos todo (ROLLBACK). */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; 
    END;

    /* ========================================================================================
       BLOQUE 2: SANITIZACIÓN Y VALIDACIÓN PREVIA (FAIL FAST)
       Propósito: Limpiar la entrada y rechazar basura antes de gastar recursos de transacción.
       ======================================================================================== */
    
    /* 2.1 LIMPIEZA (TRIM & NULLIF)
       Quitamos espacios y convertimos cadenas vacías a NULL para validar. */
    SET _Codigo      = NULLIF(TRIM(_Codigo), '');
    SET _Nombre      = NULLIF(TRIM(_Nombre), '');
    SET _Descripcion = NULLIF(TRIM(_Descripcion), '');
    /* Sanitización de Lógica: Si Es_Final viene NULL, asumimos FALSE (0) por seguridad */
    SET _Es_Final    = IFNULL(_Es_Final, 0);

    /* 2.2 VALIDACIÓN DE OBLIGATORIEDAD (REGLAS DE NEGOCIO) */
    
    IF _Id_Estatus IS NULL OR _Id_Estatus <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: Identificador de Estatus inválido.';
    END IF;

    IF _Codigo IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN [400]: El CÓDIGO es obligatorio.';
    END IF;

    IF _Nombre IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN [400]: El NOMBRE es obligatorio.';
    END IF;

    /* Validación de Dominio: Es_Final es binario */
    IF _Es_Final NOT IN (0, 1) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE LÓGICA [400]: El campo Es_Final solo acepta 0 o 1.';
    END IF;

    /* ========================================================================================
       BLOQUE 3: ESTRATEGIA DE BLOQUEO DETERMINÍSTICO (PREVENCIÓN DE DEADLOCKS)
       Propósito: Adquirir recursos en orden estricto (Menor a Mayor) para evitar ciclos de espera.
       ======================================================================================== */
    START TRANSACTION;

    /* ----------------------------------------------------------------------------------------
       PASO 3.1: RECONOCIMIENTO (LECTURA SUCIA / NO BLOQUEANTE)
       Primero "escaneamos" el entorno para identificar a los actores involucrados sin bloquear.
       ---------------------------------------------------------------------------------------- */
    
    /* A) Identificar al Objetivo (Target) */
    SELECT `Codigo`, `Nombre` INTO v_Cod_Act, v_Nom_Act
    FROM `Cat_Estatus_Capacitacion` WHERE `Id_CatEstCap` = _Id_Estatus;

    /* Si no existe, abortamos. (Pudo ser borrado por otro admin hace un segundo) */
    IF v_Cod_Act IS NULL AND v_Nom_Act IS NULL THEN 
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [404]: El Estatus que intenta editar no existe.';
    END IF;

    /* B) Identificar Conflicto de CÓDIGO (¿Alguien más tiene el código que quiero?) */
    IF _Codigo <> IFNULL(v_Cod_Act, '') THEN
        SELECT `Id_CatEstCap` INTO v_Id_Conflicto_Cod 
        FROM `Cat_Estatus_Capacitacion` 
        WHERE `Codigo` = _Codigo AND `Id_CatEstCap` <> _Id_Estatus LIMIT 1;
    END IF;

    /* C) Identificar Conflicto de NOMBRE (¿Alguien más tiene el nombre que quiero?) */
    IF _Nombre <> v_Nom_Act THEN
        SELECT `Id_CatEstCap` INTO v_Id_Conflicto_Nom 
        FROM `Cat_Estatus_Capacitacion` 
        WHERE `Nombre` = _Nombre AND `Id_CatEstCap` <> _Id_Estatus LIMIT 1;
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 3.2: EJECUCIÓN DE BLOQUEOS ORDENADOS
       Ordenamos los IDs detectados y los bloqueamos secuencialmente.
       ---------------------------------------------------------------------------------------- */
    
    /* Llenamos el pool de candidatos */
    SET v_L1 = _Id_Estatus;
    SET v_L2 = v_Id_Conflicto_Cod;
    SET v_L3 = v_Id_Conflicto_Nom;

    /* Normalización: Eliminar duplicados en las variables */
    IF v_L2 = v_L1 THEN SET v_L2 = NULL; END IF;
    IF v_L3 = v_L1 THEN SET v_L3 = NULL; END IF;
    IF v_L3 = v_L2 THEN SET v_L3 = NULL; END IF;

    /* --- RONDA 1: Bloquear el ID Menor --- */
    SET v_Min = NULL;
    IF v_L1 IS NOT NULL THEN SET v_Min = v_L1; END IF;
    IF v_L2 IS NOT NULL AND (v_Min IS NULL OR v_L2 < v_Min) THEN SET v_Min = v_L2; END IF;
    IF v_L3 IS NOT NULL AND (v_Min IS NULL OR v_L3 < v_Min) THEN SET v_Min = v_L3; END IF;

    IF v_Min IS NOT NULL THEN
        SELECT 1 INTO v_Existe FROM `Cat_Estatus_Capacitacion` WHERE `Id_CatEstCap` = v_Min FOR UPDATE;
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
        SELECT 1 INTO v_Existe FROM `Cat_Estatus_Capacitacion` WHERE `Id_CatEstCap` = v_Min FOR UPDATE;
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
        SELECT 1 INTO v_Existe FROM `Cat_Estatus_Capacitacion` WHERE `Id_CatEstCap` = v_Min FOR UPDATE;
    END IF;

    /* ========================================================================================
       BLOQUE 4: LÓGICA DE NEGOCIO (BAJO PROTECCIÓN DE LOCKS)
       Propósito: Aplicar validaciones definitivas con la certeza de que nadie más mueve los datos.
       ======================================================================================== */

    /* 4.1 RE-LECTURA AUTORIZADA
       Leemos el estado definitivo. (Pudo haber cambiado en los milisegundos previos al bloqueo). */
    SELECT `Codigo`, `Nombre`, `Descripcion`, `Es_Final`
    INTO v_Cod_Act, v_Nom_Act, v_Desc_Act, v_Final_Act
    FROM `Cat_Estatus_Capacitacion` 
    WHERE `Id_CatEstCap` = _Id_Estatus; 

    /* Check Anti-Zombie: Si al bloquear descubrimos que el registro fue borrado */
    IF v_Cod_Act IS NULL THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR CRÍTICO [410]: El registro desapareció durante la transacción.';
    END IF;

    /* 4.2 DETECCIÓN DE IDEMPOTENCIA (SIN CAMBIOS)
       Comparamos Snapshot vs Inputs. Usamos `<=>` (Null-Safe) para manejar NULLs en Descripción. */
    IF (v_Cod_Act <=> _Codigo) 
       AND (v_Nom_Act = _Nombre) 
       AND (v_Desc_Act <=> _Descripcion)
       AND (v_Final_Act = _Es_Final) THEN
        
        COMMIT; -- Liberamos locks inmediatamente
        
        /* Retorno anticipado para ahorrar I/O */
        SELECT 'AVISO: No se detectaron cambios en la información.' AS Mensaje, 'SIN_CAMBIOS' AS Accion, _Id_Estatus AS Id_Estatus;
        LEAVE THIS_PROC;
    END IF;

    /* 4.3 VALIDACIÓN FINAL DE UNICIDAD (PRE-UPDATE CHECK)
       Verificamos duplicados reales bajo lock. */
    
    /* Validación por CÓDIGO */
    SET v_Id_Error = NULL;
    SELECT `Id_CatEstCap` INTO v_Id_Error FROM `Cat_Estatus_Capacitacion` 
    WHERE `Codigo` = _Codigo AND `Id_CatEstCap` <> _Id_Estatus LIMIT 1;
    
    IF v_Id_Error IS NOT NULL THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'CONFLICTO DE DATOS [409]: El CÓDIGO ingresado ya pertenece a otro Estatus.';
    END IF;

    /* Validación por NOMBRE */
    SET v_Id_Error = NULL;
    SELECT `Id_CatEstCap` INTO v_Id_Error FROM `Cat_Estatus_Capacitacion` 
    WHERE `Nombre` = _Nombre AND `Id_CatEstCap` <> _Id_Estatus LIMIT 1;
    
    IF v_Id_Error IS NOT NULL THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'CONFLICTO DE DATOS [409]: El NOMBRE ingresado ya pertenece a otro Estatus.';
    END IF;

    /* ========================================================================================
       BLOQUE 5: PERSISTENCIA (UPDATE)
       Propósito: Aplicar los cambios físicos.
       ======================================================================================== */
    
    SET v_Dup = 0; -- Resetear bandera de error

    UPDATE `Cat_Estatus_Capacitacion`
    SET `Codigo`      = _Codigo,
        `Nombre`      = _Nombre,
        `Descripcion` = _Descripcion,
        `Es_Final`    = _Es_Final,
        `updated_at`  = NOW() -- Actualizamos la auditoría temporal.
    WHERE `Id_CatEstCap` = _Id_Estatus;

    /* ========================================================================================
       BLOQUE 6: MANEJO DE COLISIÓN TARDÍA (RECUPERACIÓN DE ERROR 1062)
       Propósito: Gestionar el caso extremo de inserción fantasma justo antes del update.
       ======================================================================================== */
    IF v_Dup = 1 THEN
        ROLLBACK;
        
        /* Diagnóstico Post-Mortem */
        SET v_Id_Conflicto = NULL;
        
        /* ¿Fue Código? */
        SELECT `Id_CatEstCap` INTO v_Id_Conflicto FROM `Cat_Estatus_Capacitacion` 
        WHERE `Codigo` = _Codigo AND `Id_CatEstCap` <> _Id_Estatus LIMIT 1;

        IF v_Id_Conflicto IS NOT NULL THEN
             SET v_Campo_Error = 'CODIGO';
        ELSE
             /* Fue Nombre */
             SELECT `Id_CatEstCap` INTO v_Id_Conflicto FROM `Cat_Estatus_Capacitacion` 
             WHERE `Nombre` = _Nombre AND `Id_CatEstCap` <> _Id_Estatus LIMIT 1;
             SET v_Campo_Error = 'NOMBRE';
        END IF;

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
           _Id_Estatus AS Id_Estatus;

END$$

DELIMITER ;

/* ====================================================================================================
	PROCEDIMEINTOS: SP_CambiarEstatusEstatusCapacitacion
   ====================================================================================================

   ----------------------------------------------------------------------------------------------------
   I. VISIÓN GENERAL Y OBJETIVO DE NEGOCIO (EXECUTIVE SUMMARY)
   ----------------------------------------------------------------------------------------------------
   Este procedimiento administra el mecanismo de "Baja Lógica" (Soft Delete) para el catálogo maestro
   de Estatus de Capacitación.
   
   Permite al Administrador:
     A) DESACTIVAR (Ocultar): Retirar un estatus de los selectores para que no se use en nuevas
        capacitaciones (ej: un estatus obsoleto como "PENDIENTE DE FIRMA").
     B) REACTIVAR (Mostrar): Recuperar un estatus histórico para volver a utilizarlo.

   ----------------------------------------------------------------------------------------------------
   II. MATRIZ DE RIESGOS Y REGLAS DE BLINDAJE (INTEGRITY RULES)
   ----------------------------------------------------------------------------------------------------
   [RN-01] CANDADO DESCENDENTE (DEPENDENCY CHECK):
      - Problema: Si desactivamos el estatus "EN CURSO" mientras hay 50 cursos impartiéndose en ese
        momento, rompemos la integridad visual del sistema. Los cursos aparecerían con un estatus
        "nulo" o inválido en los reportes.
      - Solución: Antes de desactivar (`_Nuevo_Estatus = 0`), el sistema escanea la tabla operativa
        `DatosCapacitaciones`.
      - Condición de Bloqueo: Si existe AL MENOS UNA capacitación activa (`Activo = 1`) que tenga
        asignado este estatus, la operación se ABORTA con un error 409 (Conflicto).

   [RN-02] PROTECCIÓN DE HISTORIAL:
      - Nota Técnica: La validación solo busca capacitaciones ACTIVAS. Si el estatus fue usado en
        capacitaciones de hace 5 años que ya están borradas o archivadas, NO bloqueamos la baja.
        Esto permite limpiar el catálogo sin quedar "secuestrados" por el pasado.

   ----------------------------------------------------------------------------------------------------
   III. ARQUITECTURA TÉCNICA (CONCURRENCY & PERFORMANCE)
   ----------------------------------------------------------------------------------------------------
   1. BLOQUEO PESIMISTA (PESSIMISTIC LOCKING):
      - Se utiliza `SELECT ... FOR UPDATE` al inicio.
      - Esto "congela" la fila del estatus. Garantiza que nadie más edite el nombre o la lógica
        del estatus mientras nosotros estamos decidiendo si lo apagamos o no.

   2. IDEMPOTENCIA (OPTIMIZACIÓN DE I/O):
      - Antes de escribir en disco, verificamos: ¿El estatus ya está como lo pide el usuario?
      - Si `Activo_Actual == Nuevo_Estatus`, retornamos éxito inmediato sin realizar el UPDATE.
      - Beneficio: Ahorra ciclos de escritura en disco y evita "ensuciar" el log de transacciones.

   ----------------------------------------------------------------------------------------------------
   IV. CONTRATO DE SALIDA (OUTPUT)
   ----------------------------------------------------------------------------------------------------
   Retorna una fila con:
      - Mensaje: Feedback claro para la UI.
      - Accion: 'ESTATUS_CAMBIADO', 'SIN_CAMBIOS'.
      - Id_Estatus: El recurso manipulado.
   ==================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_CambiarEstatusEstatusCapacitacion`$$

CREATE PROCEDURE `SP_CambiarEstatusEstatusCapacitacion`(
    /* ------------------------------------------------------------------------------------------------
       SECCIÓN DE PARÁMETROS DE ENTRADA
       ------------------------------------------------------------------------------------------------ */
    IN _Id_Estatus     INT,     -- [OBLIGATORIO] Identificador del Estatus a modificar.
    IN _Nuevo_Estatus  TINYINT  -- [OBLIGATORIO] 1 = Activar (Visible), 0 = Desactivar (Oculto).
)
THIS_PROC: BEGIN

    /* ============================================================================================
       BLOQUE 0: DECLARACIÓN DE VARIABLES DE ESTADO
       Contenedores para almacenar la "foto" del registro y auxiliares de validación.
       ============================================================================================ */
    
    /* Variable para validar existencia y bloquear la fila */
    DECLARE v_Existe INT DEFAULT NULL;
    
    /* Variables para el Snapshot (Estado Actual) */
    DECLARE v_Activo_Actual  TINYINT(1) DEFAULT NULL;
    DECLARE v_Nombre_Estatus VARCHAR(255) DEFAULT NULL;
    
    /* Semáforo para contar dependencias activas (Hijos en DatosCapacitaciones) */
    DECLARE v_Dependencias   INT DEFAULT NULL;

    /* ============================================================================================
       BLOQUE 1: HANDLERS (SISTEMA DE DEFENSA)
       Manejo robusto de errores técnicos.
       ============================================================================================ */
    
    /* Handler Genérico: Ante cualquier error SQL (Deadlock, Conexión perdida, etc.),
       revertimos la transacción para mantener la consistencia de la BD. */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; -- Propagar el error original al backend.
    END;

    /* ============================================================================================
       BLOQUE 2: VALIDACIONES PREVIAS (FAIL FAST)
       Rechazar peticiones basura antes de abrir transacciones costosas.
       ============================================================================================ */
    
    /* 2.1 Validación de Identidad */
    IF _Id_Estatus IS NULL OR _Id_Estatus <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: El ID del Estatus es inválido.';
    END IF;

    /* 2.2 Validación de Dominio (Solo 0 o 1) */
    IF _Nuevo_Estatus NOT IN (0, 1) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: El estatus solo puede ser 0 (Inactivo) o 1 (Activo).';
    END IF;

    /* ============================================================================================
       BLOQUE 3: INICIO DE TRANSACCIÓN Y BLOQUEO PESIMISTA
       El núcleo de la seguridad transaccional.
       ============================================================================================ */
    START TRANSACTION;

    /* --------------------------------------------------------------------------------------------
       PASO 3.1: LECTURA Y BLOQUEO DEL REGISTRO (SNAPSHOT)
       - Buscamos el registro en `Cat_Estatus_Capacitacion`.
       - `FOR UPDATE`: Adquiere un candado de escritura (X-Lock) sobre la fila.
       - Efecto: Serializa la operación. Nadie más puede tocar este estatus hasta el COMMIT.
       -------------------------------------------------------------------------------------------- */
    SELECT 1, `Activo`, `Nombre` 
    INTO v_Existe, v_Activo_Actual, v_Nombre_Estatus
    FROM `Cat_Estatus_Capacitacion`
    WHERE `Id_CatEstCap` = _Id_Estatus
    LIMIT 1
    FOR UPDATE;

    /* --------------------------------------------------------------------------------------------
       PASO 3.2: VALIDACIÓN DE EXISTENCIA
       Si el SELECT anterior no encontró nada, v_Existe seguirá siendo NULL.
       -------------------------------------------------------------------------------------------- */
    IF v_Existe IS NULL THEN
        ROLLBACK; -- Liberar recursos aunque no haya locks efectivos.
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [404]: El Estatus solicitado no existe en el catálogo.';
    END IF;

    /* --------------------------------------------------------------------------------------------
       PASO 3.3: VERIFICACIÓN DE IDEMPOTENCIA (OPTIMIZACIÓN "SIN CAMBIOS")
       - Lógica: "Si ya está encendido, no intentes encenderlo de nuevo".
       - Beneficio: Evita escrituras en disco y preserva el timestamp `updated_at`.
       -------------------------------------------------------------------------------------------- */
    IF v_Activo_Actual = _Nuevo_Estatus THEN
        
        COMMIT; -- Liberamos el bloqueo inmediatamente.
        
        /* Retornamos mensaje de éxito informativo */
        SELECT CONCAT('AVISO: El Estatus "', v_Nombre_Estatus, '" ya se encuentra en el estado solicitado.') AS Mensaje,
               'SIN_CAMBIOS' AS Accion,
               _Id_Estatus AS Id_Estatus,
               _Nuevo_Estatus AS Nuevo_Estatus;
        
        LEAVE THIS_PROC; -- Salimos del procedimiento.
    END IF;

    /* ============================================================================================
       BLOQUE 4: REGLAS DE BLINDAJE (CANDADOS DE INTEGRIDAD)
       Solo ejecutamos esto si realmente vamos a cambiar el estado.
       ============================================================================================ */

    /* --------------------------------------------------------------------------------------------
       PASO 4.1: REGLA DE DESACTIVACIÓN (CANDADO DESCENDENTE)
       - Condición: Solo si `_Nuevo_Estatus = 0` (Intentamos apagar).
       - Objetivo: Evitar dejar capacitaciones "huérfanas" de estatus.
       -------------------------------------------------------------------------------------------- */
    IF _Nuevo_Estatus = 0 THEN
        
        /* Reiniciamos el semáforo */
        SET v_Dependencias = NULL;

        /* [SONDEO DE DEPENDENCIAS]:
           Consultamos la tabla operativa `DatosCapacitaciones`.
           Buscamos si existe AL MENOS UNA fila que cumpla:
             1. Use este estatus (`Fk_Id_CatEstCap`).
             2. Esté VIVA (`Activo = 1`). No nos importan los registros históricos borrados.
        */
        SELECT 1 INTO v_Dependencias
        FROM `DatosCapacitaciones`
        WHERE `Fk_Id_CatEstCap` = _Id_Estatus
          AND `Activo` = 1
        LIMIT 1; 

        /* [DISPARADOR DE BLOQUEO]:
           Si `v_Dependencias` no es NULL, significa que encontramos un conflicto. */
        IF v_Dependencias IS NOT NULL THEN
            ROLLBACK; -- Cancelamos la operación.
            
            /* Retornamos un error 409 (Conflicto) claro para el usuario */
            SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'BLOQUEO DE INTEGRIDAD [409]: No se puede desactivar este Estatus porque existen CAPACITACIONES ACTIVAS asignadas a él. Primero debe cambiar el estatus de esas capacitaciones a otro valor.';
        END IF;

    END IF;

    /* ============================================================================================
       BLOQUE 5: PERSISTENCIA (EJECUCIÓN DEL CAMBIO)
       Si llegamos aquí, hemos pasado todas las validaciones. Es seguro escribir.
       ============================================================================================ */
    
    /* Ejecutamos el UPDATE físico en la tabla */
    UPDATE `Cat_Estatus_Capacitacion`
    SET 
        `Activo` = _Nuevo_Estatus,
        `updated_at` = NOW() -- Auditoría: Registramos el momento exacto del cambio.
    WHERE `Id_CatEstCap` = _Id_Estatus;

    /* ============================================================================================
       BLOQUE 6: CONFIRMACIÓN Y RESPUESTA FINAL
       ============================================================================================ */
    
    /* Confirmamos la transacción (Hacemos permanentes los cambios y liberamos locks) */
    COMMIT;

    /* Generamos la respuesta para el Frontend */
    SELECT 
        CASE 
            WHEN _Nuevo_Estatus = 1 THEN CONCAT('ÉXITO: El Estatus "', v_Nombre_Estatus, '" ha sido REACTIVADO y está disponible para su uso.')
            ELSE CONCAT('ÉXITO: El Estatus "', v_Nombre_Estatus, '" ha sido DESACTIVADO (Baja Lógica).')
        END AS Mensaje,
        'ESTATUS_CAMBIADO' AS Accion,
        _Id_Estatus AS Id_Estatus,
        _Nuevo_Estatus AS Nuevo_Estatus;

END$$

DELIMITER ;

/* ====================================================================================================
   PROCEDIMIENTO: SP_EliminarEstatusCapacitacionFisico
   ====================================================================================================

   ----------------------------------------------------------------------------------------------------
   I. VISIÓN GENERAL Y OBJETIVO DE NEGOCIO (EXECUTIVE SUMMARY)
   ----------------------------------------------------------------------------------------------------
   [QUÉ ES]:
   Este procedimiento representa el mecanismo de "Eliminación Dura" o "Destrucción Física" para un registro
   del catálogo de Estatus de Capacitación. Su función es ejecutar un comando `DELETE` real en la base de datos,
   borrando la información de manera irreversible.

   [CUÁNDO SE USA (ESCENARIOS DE USO)]:
   Esta operación está reservada exclusivamente para tareas de **Corrección Administrativa Inmediata**.
   Se utiliza cuando un administrador ha creado un registro por error (ej: "ESTATUS_PRUEBA_123" o con un código incorrecto)
   y detecta el error antes de que el registro haya sido utilizado en cualquier operación del sistema.

   [DIFERENCIA CRÍTICA CON BAJA LÓGICA]:
   - Baja Lógica (`SP_CambiarEstatus...`): "Este estatus existió y se usó en el pasado, pero ya no lo queremos ver en listas nuevas".
     Se logra cambiando `Activo = 0`. Mantiene la historia.
   - Baja Física (Este SP): "Este estatus fue un error de dedo, nunca debió existir y nadie lo ha usado".
     Se logra con `DELETE FROM`. Borra la historia.

   ----------------------------------------------------------------------------------------------------
   II. MATRIZ DE RIESGOS Y REGLAS DE BLINDAJE (ZERO TOLERANCE INTEGRITY)
   ----------------------------------------------------------------------------------------------------
   [RN-01] CANDADO DE HISTORIAL ABSOLUTO (HISTORICAL LOCK):
      - Principio: "La historia es sagrada e inmutable".
      - Regla de Negocio: Está estrictamente PROHIBIDO eliminar físicamente un estatus si este ha sido referenciado
        en **CUALQUIER** momento por una capacitación (`DatosCapacitaciones`).
      - Alcance de la Validación: La validación no distingue entre capacitaciones activas o inactivas. Si existe
        un registro de hace 5 años (aunque esté borrado lógicamente) que usó este estatus, la eliminación se bloquea.
      - Justificación Técnica: Si permitimos el borrado, las capacitaciones históricas quedarían con una llave foránea
        rota (`Fk_Id_CatEstCap` apuntando a un ID inexistente), lo que provocaría errores en reportes, auditorías
        o violaciones de integridad referencial a nivel de motor de base de datos (Error 1451).

   ----------------------------------------------------------------------------------------------------
   III. ESPECIFICACIÓN TÉCNICA (DATABASE SPECS)
   ----------------------------------------------------------------------------------------------------
   - TIPO: Transacción ACID con nivel de aislamiento serializable para la fila objetivo.
   - ESTRATEGIA DE CONCURRENCIA: Implementación de **Bloqueo Pesimista** (`SELECT ... FOR UPDATE`).
     Esto asegura que mientras el sistema verifica si el registro tiene dependencias, ningún otro usuario
     pueda agregarle una dependencia nueva (Race Condition).
   - MANEJO DE ERRORES: Captura específica de violaciones de integridad referencial (SQLSTATE 1451) como
     segunda línea de defensa.

   ==================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_EliminarEstatusCapacitacionFisico`$$

CREATE PROCEDURE `SP_EliminarEstatusCapacitacionFisico`(
    IN _Id_Estatus INT -- [OBLIGATORIO] El Identificador Único (PK) del registro que se desea destruir permanentemente.
)
THIS_PROC: BEGIN

    /* ========================================================================================
       BLOQUE 0: DEFINICIÓN DE VARIABLES DE ENTORNO
       Propósito: Inicializar los contenedores temporales necesarios para la lógica de validación.
       ======================================================================================== */
    
    /* Variable de control para verificar si el registro objetivo existe en la base de datos. */
    DECLARE v_Existe INT DEFAULT NULL;
    
    /* Variable para almacenar el nombre del estatus y usarlo en el mensaje de éxito (Feedback de usuario). */
    DECLARE v_Nombre_Estatus VARCHAR(255) DEFAULT NULL;
    
    /* Variable contador para cuantificar el número de veces que este estatus ha sido utilizado en la historia. */
    DECLARE v_Referencias INT DEFAULT 0;

    /* ========================================================================================
       BLOQUE 1: DEFINICIÓN DE HANDLERS (SISTEMA DE DEFENSA)
       Propósito: Establecer protocolos de respuesta ante errores técnicos críticos.
       ======================================================================================== */
    
    /* [1.1] Handler para Error de Llave Foránea (Foreign Key Constraint Fail - 1451)
       Objetivo: Actúa como una red de seguridad final. Si por alguna razón nuestra validación manual (Bloque 4)
       falla o se omite, el motor de base de datos intentará bloquear el DELETE si hay hijos. Este handler
       captura ese error nativo y lo traduce a un mensaje comprensible para el usuario. */
    DECLARE EXIT HANDLER FOR 1451 
    BEGIN 
        ROLLBACK; -- Deshace cualquier cambio pendiente.
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA [1451]: No se puede eliminar el registro porque existen dependencias a nivel de base de datos (FK Constraint) que no fueron detectadas previamente.'; 
    END;

    /* [1.2] Handler Genérico para Excepciones SQL
       Objetivo: Capturar cualquier otro error imprevisto (caída de conexión, disco lleno, error de sintaxis). */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; -- Reenvía el error original al servidor de aplicaciones.
    END;

    /* ========================================================================================
       BLOQUE 2: VALIDACIONES PREVIAS (FAIL FAST)
       Propósito: Verificar la integridad de los parámetros de entrada antes de iniciar procesos costosos.
       ======================================================================================== */
    
    /* Validación de Integridad: El ID no puede ser nulo ni menor o igual a cero. */
    IF _Id_Estatus IS NULL OR _Id_Estatus <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: El ID de Estatus proporcionado es inválido.';
    END IF;

    /* ========================================================================================
       BLOQUE 3: INICIO DE TRANSACCIÓN Y BLOQUEO PESIMISTA
       Propósito: Aislar el registro objetivo del resto del sistema para operar con seguridad.
       ======================================================================================== */
    START TRANSACTION;

    /* ----------------------------------------------------------------------------------------
       PASO 3.1: LECTURA Y BLOQUEO DEL REGISTRO OBJETIVO
       ----------------------------------------------------------------------------------------
       Ejecutamos una consulta para obtener los datos del registro y aplicar un bloqueo de escritura (`FOR UPDATE`).
       
       EFECTO DEL BLOQUEO:
       - La fila correspondiente a `_Id_Estatus` queda "congelada".
       - Nadie puede editar este estatus mientras decidimos si lo borramos.
       - Nadie puede usar este estatus para una nueva capacitación mientras estamos aquí.
       - Nadie puede borrarlo en paralelo. */
    
    SELECT 1, `Nombre` 
    INTO v_Existe, v_Nombre_Estatus
    FROM `Cat_Estatus_Capacitacion`
    WHERE `Id_CatEstCap` = _Id_Estatus
    LIMIT 1
    FOR UPDATE;

    /* Validación de Existencia: Si el SELECT no encontró nada, `v_Existe` será NULL. */
    IF v_Existe IS NULL THEN
        ROLLBACK; -- Liberamos recursos aunque no haya locks efectivos.
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [404]: El Estatus solicitado para eliminación no existe.';
    END IF;

    /* ========================================================================================
       BLOQUE 4: REGLAS DE NEGOCIO (INTEGRIDAD REFERENCIAL MANUAL)
       Propósito: Verificar lógicamente si es seguro proceder con la destrucción.
       ======================================================================================== */

    /* ----------------------------------------------------------------------------------------
       PASO 4.1: ESCANEO DE HISTORIAL (EL CANDADO ABSOLUTO)
       ----------------------------------------------------------------------------------------
       Realizamos un conteo en la tabla operativa `DatosCapacitaciones` para ver si este ID
       aparece en la columna `Fk_Id_CatEstCap`.
       
       CRITERIO DE BÚSQUEDA (IMPORTANTE):
       - NO aplicamos ningún filtro de `Activo = 1`.
       - Buscamos en TODO el historial, incluyendo registros que hayan sido dados de baja lógica.
       - Razón: La integridad referencial física de la base de datos no distingue entre registros activos o inactivos.
         Si existe una fila hija apuntando a este padre, el padre no puede morir. */
    
    SELECT COUNT(*) INTO v_Referencias
    FROM `DatosCapacitaciones`
    WHERE `Fk_Id_CatEstCap` = _Id_Estatus;

    /* EVALUACIÓN DEL RESULTADO:
       Si `v_Referencias` es mayor a 0, significa que el estatus tiene historia.
       Por lo tanto, la eliminación física está prohibida. */
    IF v_Referencias > 0 THEN
        ROLLBACK; -- Cancelamos la operación de borrado.
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'BLOQUEO DE INTEGRIDAD [409]: Imposible eliminar físicamente este Estatus. Existen registros históricos de capacitaciones (activos o inactivos) asociados a él. Para ocultarlo, utilice la opción de DESACTIVACIÓN (Baja Lógica).';
    END IF;

    /* ========================================================================================
       BLOQUE 5: EJECUCIÓN DESTRUCTORA (DELETE)
       Propósito: Realizar el borrado físico una vez superadas todas las validaciones.
       ======================================================================================== */
    
    /* Si el flujo llega a este punto, significa que:
       1. El registro existe.
       2. Está bloqueado para nosotros.
       3. No tiene ninguna dependencia en la tabla de capacitaciones.
       Es seguro proceder con la destrucción. */
       
    DELETE FROM `Cat_Estatus_Capacitacion`
    WHERE `Id_CatEstCap` = _Id_Estatus;

    /* ========================================================================================
       BLOQUE 6: CONFIRMACIÓN Y RESPUESTA FINAL
       Propósito: Hacer permanentes los cambios y notificar al cliente.
       ======================================================================================== */
    COMMIT; -- Confirmamos la transacción. El registro desaparece permanentemente.

    /* Retornamos un mensaje de éxito incluyendo el nombre del estatus borrado para confirmación visual */
    SELECT CONCAT('ÉXITO: El Estatus "', v_Nombre_Estatus, '" ha sido eliminado permanentemente del sistema.') AS Mensaje,
           'ELIMINADO_FISICO' AS Accion,
           _Id_Estatus AS Id_Estatus;

END$$

DELIMITER ;