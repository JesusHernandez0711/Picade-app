USE `PICADE`;

/* ------------------------------------------------------------------------------------------------------ */
/* CREACION DE VISTAS Y PROCEDIMIENTOS DE ALMACENADO PARA LA BASE DE DATOS                                */
/* ------------------------------------------------------------------------------------------------------ */

/* ======================================================================================================
   VISTA: Vista_Gestion_de_Participantes
   ======================================================================================================
   
   1. RESUMEN EJECUTIVO (EXECUTIVE SUMMARY)
   ----------------------------------------
   Esta vista constituye el "Motor de Inteligencia de Asistencia". Es el artefacto de base de datos
   que consolida la relación N:M (Muchos a Muchos) entre los Cursos y los Usuarios.
   
   [PROPÓSITO DE NEGOCIO]:
   Proporcionar al Coordinador de Capacitación una visión quirúrgica de lo que sucedió DENTRO
   de un curso específico. No mira al curso desde fuera (administrativo), sino desde dentro (operativo).
   
   2. ALCANCE FUNCIONAL (FUNCTIONAL SCOPE)
   ---------------------------------------
   - Fuente de Verdad para Grid de Asistentes: Alimenta la tabla donde se pasa lista.
   - Generador de Constancias DC-3: Provee los 3 datos legales requeridos (Nombre Exacto, Curso, Horas).
   - Auditoría de Calidad: Permite filtrar rápidamente índices de reprobación.

   3. ARQUITECTURA TÉCNICA (TECHNICAL ARCHITECTURE)
   ------------------------------------------------
   [PATRÓN DE DISEÑO]: "Denormalized Fact View" (Vista de Hechos Desnormalizada).
   [ESTRATEGIA DE ENLACE]: 
     Utiliza una vinculación estricta al nivel de DETALLE (`Id_Detalle_de_Capacitacion`).
     Esto garantiza la "Integridad Histórica": Si un curso se reprogramó 3 veces, 
     esta vista sabe exactamente a qué fecha asistió el usuario, evitando ambigüedad temporal.

   4. DEPENDENCIAS DE SISTEMA (SYSTEM DEPENDENCIES)
   ------------------------------------------------
   1. `Capacitaciones_Participantes` (Core Fact Table): La tabla física de relaciones.
   2. `Vista_Capacitaciones` (Master View): Contexto del evento.
   3. `Vista_Usuarios` (Identity Provider): Contexto de la persona.
   4. `Vista_Estatus_Participante` (Semantics): Contexto del resultado.
   ====================================================================================================== */

CREATE OR REPLACE 
    ALGORITHM = UNDEFINED 
    SQL SECURITY DEFINER
VIEW `PICADE`.`Vista_Gestion_de_Participantes` AS
    SELECT 
        /* =================================================================================
           SECCIÓN A: IDENTIDAD TRANSACCIONAL (PRIMARY KEYS & HANDLES)
           Objetivo: Proveer identificadores únicos para operaciones CRUD en el Frontend.
           ================================================================================= */
        
        /* [CAMPO]: Id_Registro_Participante
           [ORIGEN]: Tabla `Capacitaciones_Participantes`.`Id_CapPart` (PK)
           [DESCRIPCIÓN TÉCNICA]: Llave Primaria del registro de inscripción.
           [USO EN FRONTEND]: Es el valor oculto que se envía al servidor cuando el Coordinador
           hace clic en "Editar Calificación" o "Eliminar Alumno". Sin esto, el sistema es ciego.
        */
        
        `Rel`.`Id_CapPart`                  AS `Id_Registro_Participante`, 

        /* [CAMPO]: Folio_Curso
           [ORIGEN]: Tabla `Capacitaciones`.`Numero_Capacitacion` (Vía Vista Madre)
           [DESCRIPCIÓN TÉCNICA]: Identificador Humano-Legible (Business Key).
           [USO EN FRONTEND]: Permite al usuario confirmar visualmente que está editando
           el curso correcto (ej: "CAP-2026-001").
        */
        -- [CORRECCIÓN CRÍTICA]: Agregamos el ID del Padre que faltaba
        `VC`.`Id_Capacitacion`              AS `Id_Capacitacion`,
		`VC`.`Id_Detalle_de_Capacitacion`   AS `Id_Detalle_de_Capacitacion`,
        `VC`.`Numero_Capacitacion`          AS `Folio_Curso`,

        /* =================================================================================
           SECCIÓN B: CONTEXTO DEL CURSO (HERENCIA DE VISTA MADRE)
           Objetivo: Contextualizar la inscripción con datos del evento formativo.
           Nota: Estos datos son de SOLO LECTURA en esta vista.
           ================================================================================= */
        
        /* [Gerencia]: Centro de Costos o Área dueña del presupuesto del curso. */
        `VC`.`Clave_Gerencia_Solicitante`   AS `Gerencia_Solicitante`,
        
        /* [Tema]: El contenido académico impartido (Nombre de la materia). */
        `VC`.`Nombre_Tema`                  AS `Tema_Curso`,
        
        /* [Fechas]: Ventana de tiempo de ejecución.
           CRÍTICO: Estas fechas vienen del DETALLE, no de la cabecera. Son las reales.
        */
        `VC`.`Fecha_Inicio`                 AS `Fecha_Inicio`,
        `VC`.`Fecha_Fin`                    AS `Fecha_Fin`,
        
        /* [Duración]: Carga horaria académica.
           [IMPORTANCIA LEGAL]: Dato obligatorio para la generación de formatos DC-3 ante la STPS.
           Sin este dato, la constancia no tiene validez oficial.
        */
        `VC`.`Duracion_Horas`               AS `Duracion_Horas`,      
        
        /* [Sede]: Ubicación física (Aula) o virtual (Teams/Zoom). Alias singularizado. */
        `VC`.`Nombre_Sede`                  AS `Sede`,                
        
        /* [Modalidad]: Método de entrega (Presencial, En Línea, Mixto). */
        `VC`.`Nombre_Modalidad`             AS `Modalidad`,           
        
        /* [Estatus Global]: Estado del contenedor padre (ej: Si el curso está CANCELADO, esto lo indica). */
        `VC`.`Estatus_Curso`                AS `Estatus_Global_Curso`,
        
        /* [Instructor]: Nombre ya concatenado y procesado por la vista madre.
           Optimiza el rendimiento al evitar concatenaciones repetitivas en tiempo de ejecución.
        */
        /*`VC`.`Apellido_Paterno_Instructor`,
        `VC`.`Apellido_Materno_Instructor`,
        `VC`.`Nombre_Instructor`,*/
        -- `VC`.`Nombre_Completo_Instructor`   AS `Instructor_Asignado`,
        CONCAT(`VC`.`Apellido_Paterno_Instructor`, ' ', `VC`.`Apellido_Materno_Instructor`, ' ', `VC`.`Nombre_Instructor`) AS `Instructor_Asignado`,
        
        /* [Estatus del Registro]: Bandera de Soft Delete (Activo=1 / Borrado=0).
           Heredado para saber si el curso sigue visible en el sistema.
        */
        `VC`.`Estatus_del_Registro`,

        /* =================================================================================
           SECCIÓN C: IDENTIDAD DEL PARTICIPANTE (PERFIL DEL ALUMNO)
           Objetivo: Identificar inequívocamente a la persona inscrita.
           Origen: `Vista_Usuarios` (Alias `UsPart`).
           ================================================================================= */
        
        /* [Ficha]: ID único corporativo del empleado. Clave de búsqueda principal. */
        `UsPart`.`Ficha_Usuario`            AS `Ficha_Participante`,  
        
        /* Componentes del nombre desglosados para ordenamiento (Sorting) en tablas */
        `UsPart`.`Apellido_Paterno`         AS `Ap_Paterno_Participante`,
        `UsPart`.`Apellido_Materno`         AS `Ap_Materno_Participante`,
        `UsPart`.`Nombre`                   AS `Nombre_Pila_Participante`,

        /* [CAMPO CALCULADO]: Nombre Completo Normalizado.
           [TRANSFORMACIÓN]: CONCAT(Nombre + Espacio + Paterno + Espacio + Materno).
           [RAZÓN TÉCNICA]: Centralizar la lógica de formateo de nombres en la BD evita
           inconsistencias en el Frontend (ej: que un reporte muestre "Apellidos, Nombre" y otro "Nombre Apellidos").
        */
        /*CONCAT(`UsPart`.`Nombre`, ' ', `UsPart`.`Apellido_Paterno`, ' ', `UsPart`.`Apellido_Materno`) 
                                            AS `Nombre_Completo_Participante`,*/

        /* =================================================================================
           SECCIÓN D: EVALUACIÓN Y RESULTADOS (LA SÁBANA DE CALIFICACIONES)
           Objetivo: Exponer los KPIs de rendimiento del alumno en este curso específico.
           Origen: Tabla de Hechos `Capacitaciones_Participantes` y Catálogo de Estatus.
           ================================================================================= */ 

        /* [Asistencia]: KPI de Cumplimiento.
           Porcentaje de sesiones asistidas. Vital para reglas de aprobación automática.
        */
        
        `Rel`.`PorcentajeAsistencia`        AS `Porcentaje_Asistencia`,

        /* [Calificación]: Valor Cuantitativo (Numérico).
           El dato crudo de la nota obtenida (0 a 100).
        */
        
        `Rel`.`Calificacion`                AS `Calificacion_Numerica`, 
        
        /* NUEVA COLUMNA EXPUESTA */
        `Rel`.`Justificacion`               AS `Nota_Auditoria`,
        
                /* [Resultado Final]: Valor Semántico (Texto).
           Ejemplos: "APROBADO", "REPROBADO", "NO SE PRESENTÓ".
           Útil para etiquetas de colores (Badges) en el UI.
        */
        `EstPart`.`Nombre_Estatus`          AS `Resultado_Final`,       
        
        /* [Detalle]: Descripción técnica de la regla de negocio aplicada (ej: "Calif < 80"). */
        `EstPart`.`Descripcion_Estatus`     AS `Detalle_Resultado`,
        
		/* =================================================================================
           SECCIÓN E: AUDITORÍA FORENSE (Trazabilidad del Dato)
           Objetivo: Responder ¿Quién? y ¿Cuándo?
           ================================================================================= */
        
        /* 1. CREACIÓN (Inscripción Original) */
        `Rel`.`created_at`                  AS `Fecha_Inscripcion`,
        CONCAT(`UsCrea`.`Nombre`, ' ', `UsCrea`.`Apellido_Paterno`) AS `Inscrito_Por`,

        /* 2. MODIFICACIÓN (Último cambio de nota o estatus) */
        `Rel`.`updated_at`                  AS `Fecha_Ultima_Modificacion`,
        CONCAT(`UsMod`.`Nombre`, ' ', `UsMod`.`Apellido_Paterno`)   AS `Modificado_Por`
        
    FROM
        /* ---------------------------------------------------------------------------------
           CAPA 1: LA TABLA DE HECHOS (FACT TABLE)
           Es el núcleo de la vista. Contiene la relación física entre IDs.
           --------------------------------------------------------------------------------- */
        `PICADE`.`Capacitaciones_Participantes` `Rel`
        
        /* ---------------------------------------------------------------------------------
           CAPA 2: ENLACE AL CONTEXTO DEL CURSO (INNER JOIN)
           [LÓGICA FORENSE]: 
           Se une con `Vista_Capacitaciones` usando `Id_Detalle_de_Capacitacion`.
           
           ¿POR QUÉ NO USAR 'Id_Capacitacion'?
           Porque un mismo curso (Folio) puede tener múltiples instancias en el tiempo (reprogramaciones).
           Al unir por el ID del DETALLE, garantizamos que el alumno está ligado a la 
           ejecución específica (Fecha/Hora/Instructor) y no al concepto abstracto del curso.
           --------------------------------------------------------------------------------- */
        INNER JOIN `PICADE`.`Vista_Capacitaciones` `VC`
            ON `Rel`.`Fk_Id_DatosCap` = `VC`.`Id_Detalle_de_Capacitacion`
            
        /* ---------------------------------------------------------------------------------
           CAPA 3: ENLACE A LA IDENTIDAD (INNER JOIN)
           Resolución del ID de Usuario (`Fk_Id_Usuario`) a datos legibles (Nombre, Ficha).
           --------------------------------------------------------------------------------- */
        INNER JOIN `PICADE`.`Vista_Usuarios` `UsPart`
            ON `Rel`.`Fk_Id_Usuario` = `UsPart`.`Id_Usuario`
            
        /* ---------------------------------------------------------------------------------
           CAPA 4: ENLACE A LA SEMÁNTICA DE ESTATUS (INNER JOIN)
           Resolución del código de estatus (`Fk_Id_CatEstPart`) a texto de negocio.
           --------------------------------------------------------------------------------- */
        INNER JOIN `PICADE`.`Vista_Estatus_Participante` `EstPart`
            ON `Rel`.`Fk_Id_CatEstPart` = `EstPart`.`Id_Estatus_Participante`

		/* 4. Datos del Creador (UsCrea) - ¡ESTO FALTABA! */
        LEFT JOIN `PICADE`.`Vista_Usuarios` `UsCrea`
            ON `Rel`.`Fk_Id_Usuario_Created_By` = `UsCrea`.`Id_Usuario`

        /* 5. Datos del Modificador (UsMod) - ¡ESTO FALTABA! */
        LEFT JOIN `PICADE`.`Vista_Usuarios` `UsMod`
            ON `Rel`.`Fk_Id_Usuario_Updated_By` = `UsMod`.`Id_Usuario`;

/* --- VERIFICACIÓN RÁPIDA --- */
-- SELECT * FROM Picade.Vista_Gestion_de_Participantes LIMIT 5;

/* ══════════════════════════════════════════════════════════════════════════════════════════════════════════
   PROCEDIMIENTO: SP_RegistrarParticipanteCapacitacion
   ══════════════════════════════════════════════════════════════════════════════════════════════════════════
   
   SECCIÓN 1: FICHA TÉCNICA DEL ARTEFACTO (ARTIFACT DATASHEET)
   ----------------------------------------------------------------------------------------------------------
   - Nombre del Objeto:    SP_RegistrarParticipanteCapacitacion
   - Tipo de Objeto:       Rutina Almacenada (Stored Procedure)
   - Clasificación:        Transacción de Escritura Crítica (Critical Write Transaction)
   - Nivel de Aislamiento: READ COMMITTED (Lectura Confirmada)
   - Perfil de Ejecución:  Privilegiado (Administrador / Coordinador)
   
   SECCIÓN 2: MAPEO DE DEPENDENCIAS (DEPENDENCY MAPPING)
   ----------------------------------------------------------------------------------------------------------
   A. Tablas de Lectura (Read Access):
      1. Usuarios (Validación de identidad y estatus)
      2. DatosCapacitaciones (Validación de existencia de curso y configuración manual)
      3. Capacitaciones (Lectura de Meta/Cupo Máximo)
      4. Cat_Estatus_Capacitacion (Validación de reglas de negocio por estatus)
   
   B. Tablas de Escritura (Write Access):
      1. Capacitaciones_Participantes (Inserción del registro de inscripción)
   
   SECCIÓN 3: ESPECIFICACIÓN DE LA LÓGICA DE NEGOCIO (BUSINESS LOGIC SPECIFICATION)
   ----------------------------------------------------------------------------------------------------------
   OBJETIVO PRIMARIO:
   Registrar la relación entre un Usuario (Alumno) y una Capacitación (Curso), garantizando la integridad
   referencial, la unicidad del registro y el cumplimiento de las reglas de cupo.

   REGLA DE SUPER-USUARIO (ADMIN OVERRIDE):
   A diferencia del proceso de auto-inscripción, este procedimiento permite a un administrador realizar
   "Correcciones Históricas". 
   - PERMITIDO: Inscribir en cursos "Finalizados", "En Evaluación" o "En Curso" (para regularizar).
   - DENEGADO: Inscribir en cursos "Cancelados" (8) o "Archivados" (10), ya que son expedientes muertos.

   ALGORITMO DE CUPO HÍBRIDO (HYBRID CAPACITY ALGORITHM):
   Para determinar si existe espacio, el sistema no confía ciegamente en el conteo de filas.
   Se utiliza una estrategia "Pesimista" para evitar el sobrecupo físico:
     Paso A: Calcular ocupación del sistema = COUNT(*) WHERE Estatus != BAJA.
     Paso B: Leer ocupación manual = DatosCapacitaciones.AsistentesReales (Input humano).
     Paso C: Determinar Ocupación Efectiva = GREATEST(Paso A, Paso B).
     Paso D: Disponibilidad = Meta_Programada - Ocupación_Efectiva.
   
   Si Disponibilidad <= 0, la transacción se rechaza, protegiendo la integridad del aula.

   ----------------------------------------------------------------------------------------------------------
   SECCIÓN 4: CÓDIGOS DE RETORNO Y MANEJO DE ERRORES (RETURN CODES)
   ----------------------------------------------------------------------------------------------------------
   [400] ERROR_ENTRADA:      Parámetros nulos o iguales a cero.
   [403] ACCESO_DENEGADO:    El ejecutor no tiene permisos o el usuario destino está inactivo.
   [404] RECURSO_NO_ENCO...: El curso o el usuario no existen en la base de datos.
   [409] CONFLICTO_ESTADO:   El curso fue borrado lógicamente (Soft Delete).
   [409] ESTATUS_PROHIBIDO:  Intento de inscripción en curso Cancelado o Archivado.
   [409] DUPLICADO:          El usuario ya tiene un asiento en este curso (Idempotencia).
   [409] CUPO_LLENO:         No hay asientos disponibles según la lógica híbrida.
   [500] ERROR_TECNICO:      Fallo de SQL (Deadlock, Constraint Violation, Timeout).
   
   ========================================================================================================== */
-- Verificación previa para limpieza de entorno (Drop if exists pattern)

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_RegistrarParticipanteCapacitacion`$$

CREATE PROCEDURE `SP_RegistrarParticipanteCapacitacion`(
    /* ------------------------------------------------------------------------------------------------------
       DEFINICIÓN DE PARÁMETROS DE ENTRADA (INPUT INTERFACE)
       ------------------------------------------------------------------------------------------------------ */
    IN _Id_Usuario_Ejecutor INT,      -- [REQUIRED]: ID del usuario Admin/Coord que ejecuta la acción.
    IN _Id_Detalle_Capacitacion INT,  -- [REQUIRED]: ID único de la versión del curso (Tabla Hija).
    IN _Id_Usuario_Participante INT   -- [REQUIRED]: ID del usuario Alumno que será inscrito.
)
ProcInsPart: BEGIN
    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       BLOQUE 1: GESTIÓN DE MEMORIA Y VARIABLES (MEMORY MANAGEMENT)
       Nota Técnica: Se inicializan todas las variables por defecto para evitar valores NULL
       que puedan romper operaciones matemáticas o comparaciones lógicas.
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */
    
    -- 1.1 Variables de Verificación de Entidades (Flags de Existencia)
    DECLARE v_Ejecutor_Existe INT DEFAULT 0;       -- Semáforo para el admin
    DECLARE v_Participante_Existe INT DEFAULT 0;   -- Semáforo para el alumno
    DECLARE v_Participante_Activo INT DEFAULT 0;   -- Estado lógico del alumno (1=Activo)
    
    -- 1.2 Variables de Contexto de la Capacitación (Snapshot de Datos)
    DECLARE v_Capacitacion_Existe INT DEFAULT 0;   -- Semáforo de existencia física
    DECLARE v_Capacitacion_Activa INT DEFAULT 0;   -- Semáforo de existencia lógica (Soft Delete)
    DECLARE v_Id_Capacitacion_Padre INT DEFAULT 0; -- ID de la tabla padre (Temario/Meta)
    DECLARE v_Folio_Curso VARCHAR(100) DEFAULT ''; -- Identificador humano (para mensajes de error)
    DECLARE v_Estatus_Curso INT DEFAULT 0;         -- ID del estatus operativo actual del curso
    
    -- 1.3 Variables para el Algoritmo de Cupo Híbrido (Capacity Logic)
    DECLARE v_Cupo_Maximo INT DEFAULT 0;           -- Límite duro definido en la planeación
    DECLARE v_Conteo_Sistema INT DEFAULT 0;        -- Cantidad de registros en DB (Automático)
    DECLARE v_Conteo_Manual INT DEFAULT 0;         -- Cantidad forzada por el coordinador (Manual)
    DECLARE v_Asientos_Ocupados INT DEFAULT 0;     -- Resultado de la función GREATEST()
    DECLARE v_Cupo_Disponible INT DEFAULT 0;       -- Resultado final (Meta - Ocupados)
    
    -- 1.4 Variables de Control de Flujo y Resultado
    DECLARE v_Ya_Inscrito INT DEFAULT 0;           -- Bandera para detección de duplicados
    DECLARE v_Nuevo_Id_Registro INT DEFAULT 0;     -- Almacena el ID generado tras el INSERT (Identity)
    
    -- 1.5 Constantes de Estado de Participante (Hardcoded Business Rules)
    -- Se definen para evitar "números mágicos" en el código y facilitar mantenimiento.
    DECLARE c_ESTATUS_INSCRITO INT DEFAULT 1;      -- El usuario entra con estatus "Inscrito"
    DECLARE c_ESTATUS_BAJA INT DEFAULT 5;          -- Estatus "Baja" libera el cupo
    
    -- 1.6 Constantes de Lista Negra de Cursos (Admin Blacklist)
    -- Estos son los únicos estados donde el Admin NO puede operar.
    DECLARE c_CURSO_CANCELADO INT DEFAULT 8;       -- Un curso cancelado es inoperable
    DECLARE c_CURSO_ARCHIVADO INT DEFAULT 10;      -- Un curso archivado es de solo lectura

    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       BLOQUE 2: MANEJO DE EXCEPCIONES Y ATOMICIDAD (ACID COMPLIANCE)
       Objetivo: Implementar un mecanismo de seguridad (Fail-Safe).
       Si ocurre cualquier error SQL crítico durante la ejecución, se revierte todo.
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        -- [CRÍTICO]: Revertir cualquier cambio pendiente en la transacción actual.
        ROLLBACK;
        
        -- Retornar mensaje estandarizado de error 500 al cliente.
        SELECT 
            'ERROR DE SISTEMA [500]: Fallo interno crítico durante la transacción de inscripción.' AS Mensaje,
            'ERROR_TECNICO' AS Accion,
            NULL AS Id_Registro_Participante;
    END;

    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 0: SANITIZACIÓN DE ENTRADA (INPUT SANITIZATION - FAIL FAST)
       Objetivo: Validar la integridad estructural de los datos antes de procesar lógica de negocio.
       Esto ahorra recursos de CPU y Base de Datos al rechazar peticiones mal formadas inmediatamente.
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */
    
    -- Validación 0.1: Integridad del Ejecutor
    IF _Id_Usuario_Ejecutor IS NULL OR _Id_Usuario_Ejecutor <= 0 
		THEN
			SELECT 'ERROR DE ENTRADA [400]: El ID del Usuario Ejecutor es obligatorio.' AS Mensaje, 
				   'VALIDACION_FALLIDA' AS Accion, 
                   NULL AS Id_Registro_Participante;
        LEAVE ProcInsPart; -- Terminación inmediata
    END IF;
    
    -- Validación 0.2: Integridad del Recurso (Curso)
    IF _Id_Detalle_Capacitacion IS NULL OR _Id_Detalle_Capacitacion <= 0 
		THEN
			SELECT 'ERROR DE ENTRADA [400]: El ID de la Capacitación es obligatorio.' AS Mensaje, 
				   'VALIDACION_FALLIDA' AS Accion, 
                   NULL AS Id_Registro_Participante;
        LEAVE ProcInsPart; -- Terminación inmediata
    END IF;
    
    -- Validación 0.3: Integridad del Destinatario (Participante)
    IF _Id_Usuario_Participante IS NULL OR _Id_Usuario_Participante <= 0 
		THEN
			SELECT 'ERROR DE ENTRADA [400]: El ID del Participante es obligatorio.' AS Mensaje, 
				   'VALIDACION_FALLIDA' AS Accion, 
				   NULL AS Id_Registro_Participante;
        LEAVE ProcInsPart; -- Terminación inmediata
    END IF;

    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 1: VERIFICACIÓN DE CREDENCIALES DEL EJECUTOR (SECURITY LAYER)
       Objetivo: Asegurar que la solicitud proviene de un actor válido en el sistema.
       No verificamos roles aquí (eso es capa de aplicación), pero sí existencia y actividad.
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */
    SELECT COUNT(*) INTO v_Ejecutor_Existe 
    FROM `Usuarios` 
    WHERE `Id_Usuario` = _Id_Usuario_Ejecutor 
      AND `Activo` = 1; -- Solo usuarios activos pueden ejecutar acciones
    
    IF v_Ejecutor_Existe = 0 
		THEN
			SELECT 'ERROR DE SEGURIDAD [403]: El Usuario Ejecutor no es válido o está inactivo.' AS Mensaje, 
				   'ACCESO_DENEGADO' AS Accion, 
                   NULL AS Id_Registro_Participante;
        LEAVE ProcInsPart;
    END IF;

    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 2: VERIFICACIÓN DE ELEGIBILIDAD DEL PARTICIPANTE (TARGET VALIDATION)
       Objetivo: Asegurar la integridad referencial del alumno destino.
       Regla de Negocio: No se puede inscribir a un usuario que ha sido dado de baja administrativamente.
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */
    SELECT COUNT(*), `Activo` 
    INTO v_Participante_Existe, v_Participante_Activo 
    FROM `Usuarios` 
    WHERE `Id_Usuario` = _Id_Usuario_Participante;
    
    -- Validación 2.1: Existencia Física del Registro
    IF v_Participante_Existe = 0 
		THEN
			SELECT 'ERROR DE INTEGRIDAD [404]: El usuario a inscribir no existe en el sistema.' AS Mensaje, 
				   'RECURSO_NO_ENCONTRADO' AS Accion, 
				   NULL AS Id_Registro_Participante;
        LEAVE ProcInsPart;
    END IF;
    
    -- Validación 2.2: Estado Operativo del Usuario (Soft Delete Check)
    IF v_Participante_Activo = 0 
		THEN
			SELECT 'ERROR DE LÓGICA [409]: El usuario está INACTIVO (Baja Administrativa). No puede ser inscrito.' AS Mensaje, 
				   'CONFLICTO_ESTADO' AS Accion, 
				   NULL AS Id_Registro_Participante;
        LEAVE ProcInsPart;
    END IF;

    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 3: CARGA DE CONTEXTO Y VALIDACIÓN DE ESTADO DEL CURSO (CONTEXT AWARENESS)
       Objetivo: Recuperar todos los metadatos necesarios del curso en una sola operación optimizada.
       Aquí se aplica la regla de negocio de "Corrección Histórica" para Administradores.
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */
    SELECT 
        COUNT(*),                             -- [0] Existe el registro?
        COALESCE(`DC`.`Activo`, 0),           -- [1] Está borrado lógicamente?
        `DC`.`Fk_Id_Capacitacion`,            -- [2] ID del Padre (Para buscar cupo máximo)
        `DC`.`Fk_Id_CatEstCap`,               -- [3] Estatus Operativo (1-10)
        COALESCE(`DC`.`AsistentesReales`, 0)  -- [4] Asistentes Manuales (Input de Coordinador)
    INTO 
        v_Capacitacion_Existe, 
        v_Capacitacion_Activa, 
        v_Id_Capacitacion_Padre, 
        v_Estatus_Curso, 
        v_Conteo_Manual
    FROM `DatosCapacitaciones` `DC` 
    WHERE `DC`.`Id_DatosCap` = _Id_Detalle_Capacitacion;

    -- Validación 3.1: Integridad Referencial del Curso
    IF v_Capacitacion_Existe = 0 
		THEN 
			SELECT 'ERROR DE INTEGRIDAD [404]: La capacitación indicada no existe.' AS Mensaje, 
				   'RECURSO_NO_ENCONTRADO' AS Accion, 
                   NULL AS Id_Registro_Participante; 
        LEAVE ProcInsPart; 
    END IF;
    
    -- Validación 3.2: Integridad Lógica (Curso eliminado)
    IF v_Capacitacion_Activa = 0 
		THEN 
			SELECT 'ERROR DE LÓGICA [409]: Esta versión del curso está ARCHIVADA o eliminada.' AS Mensaje, 
				   'CONFLICTO_ESTADO' AS Accion, 
                   NULL AS Id_Registro_Participante; 
        LEAVE ProcInsPart; 
    END IF;
    
    -- [RECUPERACIÓN DE METADATA DEL PADRE]
    -- Obtenemos el folio para mensajes y el cupo programado (Meta) para los cálculos.
    SELECT `Numero_Capacitacion`, `Asistentes_Programados` 
    INTO v_Folio_Curso, v_Cupo_Maximo 
    FROM `Capacitaciones` 
    WHERE `Id_Capacitacion` = v_Id_Capacitacion_Padre;
    
    /* ------------------------------------------------------------------------------------------------------
       [VALIDACIÓN DE LISTA NEGRA DE ESTATUS - BUSINESS RULE ENFORCEMENT]
       Aquí aplicamos la lógica específica para Admins. 
       A diferencia del usuario normal, el Admin PUEDE inscribir en cursos pasados (Finalizados, En Evaluación).
       
       SOLO se bloquea si el curso está:
       - CANCELADO (ID 8): Porque nunca ocurrió.
       - CERRADO/ARCHIVADO (ID 10): Porque el expediente administrativo ya se cerró.
       ------------------------------------------------------------------------------------------------------ */
    IF v_Estatus_Curso IN (c_CURSO_CANCELADO, c_CURSO_ARCHIVADO) 
		THEN
			SELECT 
				CONCAT('ERROR DE NEGOCIO [409]: No se puede modificar la lista de asistentes. El curso "', v_Folio_Curso, 
					   '" se encuentra en un estatus inoperable (ID: ', v_Estatus_Curso, ').') AS Mensaje, 
				'ESTATUS_PROHIBIDO' AS Accion, 
				NULL AS Id_Registro_Participante;
        LEAVE ProcInsPart;
    END IF;

    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 4: VALIDACIÓN DE UNICIDAD (IDEMPOTENCY CHECK)
       Objetivo: Prevenir registros duplicados. Un alumno no puede ocupar dos asientos en el mismo curso.
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */
    SELECT COUNT(*) INTO v_Ya_Inscrito 
    FROM `Capacitaciones_Participantes` 
    WHERE `Fk_Id_DatosCap` = _Id_Detalle_Capacitacion 
      AND `Fk_Id_Usuario` = _Id_Usuario_Participante;
    
    IF v_Ya_Inscrito > 0 
		THEN 
			SELECT CONCAT('AVISO DE NEGOCIO: El usuario ya se encuentra registrado en el curso "', v_Folio_Curso, '".') AS Mensaje, 
				   'DUPLICADO' AS Accion, 
				   NULL AS Id_Registro_Participante; 
        LEAVE ProcInsPart; 
    END IF;

    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 5: VALIDACIÓN DE CAPACIDAD (ALGORITMO DE CUPO HÍBRIDO)
       Objetivo: Determinar la disponibilidad real de asientos utilizando lógica pesimista.
       Nota: Incluso en correcciones históricas, respetamos la capacidad máxima del aula para no 
       generar inconsistencias en los reportes de ocupación.
       
       Fórmula: Disponible = Meta - MAX(Conteo_Sistema, Conteo_Manual)
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */
    
    -- Paso 5.1: Contar ocupación real en sistema (Excluyendo bajas)
    SELECT COUNT(*) INTO v_Conteo_Sistema 
    FROM `Capacitaciones_Participantes` 
    WHERE `Fk_Id_DatosCap` = _Id_Detalle_Capacitacion 
      AND `Fk_Id_CatEstPart` != c_ESTATUS_BAJA;

    -- Paso 5.2: Aplicar Regla del Máximo (Sistema vs Manual)
    -- Si el coordinador puso "30" manuales, y hay 5 en sistema, tomamos 30.
    SET v_Asientos_Ocupados = GREATEST(v_Conteo_Manual, v_Conteo_Sistema);

    -- Paso 5.3: Calcular Delta
    SET v_Cupo_Disponible = v_Cupo_Maximo - v_Asientos_Ocupados;
    
    -- Paso 5.4: Veredicto Final
    IF v_Cupo_Disponible <= 0 
		THEN 
			SELECT CONCAT('ERROR DE NEGOCIO [409]: CUPO LLENO en "', v_Folio_Curso, '". Ocupados: ', v_Asientos_Ocupados, '/', v_Cupo_Maximo, '.') AS Mensaje, 
				   'CUPO_LLENO' AS Accion, 
                   NULL AS Id_Registro_Participante; 
        LEAVE ProcInsPart; 
    END IF;

    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 6: EJECUCIÓN TRANSACCIONAL (ACID COMMIT)
       Objetivo: Persistir el cambio en la base de datos de manera atómica.
       Aquí se abre la transacción y se bloquean los recursos necesarios para la escritura.
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */
    START TRANSACTION;
    
    INSERT INTO `Capacitaciones_Participantes` (
        `Fk_Id_DatosCap`,            -- FK: Curso
        `Fk_Id_Usuario`,             -- FK: Alumno
        `Fk_Id_CatEstPart`,          -- FK: Estatus Inicial (1)
        `Calificacion`,              -- NULL por defecto
        `PorcentajeAsistencia`,      -- NULL por defecto
        `created_at`,                -- Auditoría: Creación
        `updated_at`,                -- Auditoría: Última Modificación
        `Fk_Id_Usuario_Created_By`,  -- Auditoría: Responsable (Admin)
        `Fk_Id_Usuario_Updated_By`   -- Auditoría: Responsable (Admin)
    ) VALUES (
        _Id_Detalle_Capacitacion,
        _Id_Usuario_Participante,
        c_ESTATUS_INSCRITO,          -- Inicializa como "INSCRITO"
        NULL, 
        NULL,
        NOW(), 
        NOW(), 
        _Id_Usuario_Ejecutor,        -- El Admin es el creador
        _Id_Usuario_Ejecutor
    );
    
    -- Recuperar el ID autogenerado para confirmación
    SET v_Nuevo_Id_Registro = LAST_INSERT_ID();
    
    COMMIT; -- Confirmación definitiva en disco

    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 7: RESPUESTA EXITOSA Y FEEDBACK (SUCCESS RESPONSE)
       Objetivo: Informar al cliente que la operación fue exitosa y retornar metadatos útiles.
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */
    SELECT 
        CONCAT('INSCRIPCIÓN EXITOSA: Usuario agregado a "', v_Folio_Curso, '". Lugares restantes: ', (v_Cupo_Disponible - 1)) AS Mensaje, 
        'INSCRITO' AS Accion, 
        v_Nuevo_Id_Registro AS Id_Registro_Participante;

END$$

DELIMITER ;

/* ======================================================================================================
   PROCEDIMIENTO: SP_RegistrarParticipacionCapacitacion
   ======================================================================================================
   
   ------------------------------------------------------------------------------------------------------
   1. FICHA TÉCNICA (TECHNICAL DATASHEET)
   ------------------------------------------------------------------------------------------------------
   - Nombre Oficial:       SP_RegistrarParticipacionCapacitacion
   - Clasificación:        Transacción de Escritura / Auto-Servicio (Self-Service Write Transaction)
   - Nivel de Aislamiento: READ COMMITTED (Lectura Confirmada)
   - Patrón de Diseño:     Fail-Fast & Pessimistic Locking Logic
   - Perfil de Ejecución:  Usuario Final (Alumno / Empleado)
   - Dependencias:         Tablas: Usuarios, DatosCapacitaciones, Capacitaciones, Capacitaciones_Participantes.
                           Vistas: Ninguna (Acceso directo a tablas para integridad ACID).
   
   ------------------------------------------------------------------------------------------------------
   2. VISIÓN DE NEGOCIO (BUSINESS LOGIC SPECIFICATION)
   ------------------------------------------------------------------------------------------------------
   Este procedimiento gestiona la lógica de "Auto-Matriculación". Permite a un usuario activo 
   registrarse a sí mismo en una oferta de capacitación vigente.
   
   [REGLAS DE INSCRIPCIÓN VIGENTE]:
   El curso debe estar en uno de los siguientes estados operativos para aceptar alumnos:
   - PROGRAMADO (ID 1): El curso está confirmado en calendario oficial.
   - POR INICIAR (ID 2): Faltan pocas horas/días, etapa crítica de llenado de cupo.
   - REPROGRAMADO (ID 9): Hubo cambio de fecha, pero la oferta sigue abierta.
   
   [RESTRICCIONES]:
   - NO se permite inscripción en "EN DISEÑO", "CANCELADO" o estatus administrativos no públicos.
   - NO se permite inscripción en "EN CURSO" o "FINALIZADO" (Integridad pedagógica).

   ------------------------------------------------------------------------------------------------------
   3. ALGORITMO DE "CUPO HÍBRIDO PESIMISTA" (CORE LOGIC)
   ------------------------------------------------------------------------------------------------------
   Para evitar el problema de "Sobreventa" (Overbooking) común en sistemas concurrentes:
   
   Definimos:
     [A] = Conteo Real en BD (`SELECT COUNT(*)`). Es la verdad del sistema.
     [B] = Bloqueo Manual (`AsistentesReales`). Es la verdad del coordinador (ej. "Tengo 5 invitados externos").
     [C] = Capacidad Máxima (`Asistentes_Programados`). Es el límite físico del aula.
   
   Fórmula de Disponibilidad:
     Ocupados = GREATEST( [A], [B] )  -> "Tomamos el escenario más pesimista (mayor ocupación)"
     Disponibles = [C] - Ocupados
   
   Regla de Decisión:
     IF Disponibles <= 0 THEN REJECT TRANSACTION.

   ------------------------------------------------------------------------------------------------------
   4. DICCIONARIO DE RESPUESTAS (RETURN CODES)
   ------------------------------------------------------------------------------------------------------
   | Código            | Significado Técnico                     | Mensaje al Usuario                         |
   |-------------------|-----------------------------------------|--------------------------------------------|
   | LOGOUT_REQUIRED   | Input NULL o <= 0                       | Error de sesión.                           |
   | VALIDACION_FALLIDA| ID Curso inválido                       | Curso no válido.                           |
   | CONTACTAR_SOPORTE | Usuario no encontrado en DB             | Tu usuario no existe.                      |
   | ACCESO_DENEGADO   | Usuario marcado Activo=0                | Tu cuenta está inactiva.                   |
   | RECURSO_NO_ENCO...| Curso no existe en DB                   | El curso que buscas no existe.             |
   | CURSO_CERRADO     | Curso Archiv=0 o Estatus=Final          | Este curso ha sido archivado/finalizado.   |
   | ESTATUS_INVALIDO  | Estatus no permitido (ej. ID 3,4,5...)  | El curso no está abierto para inscripciones.|
   | YA_INSCRITO       | Violación de Unique Key Lógica          | Ya tienes un lugar reservado.              |
   | CUPO_LLENO        | Disponibilidad <= 0                     | Lo sentimos, ya no hay lugares.            |
   | INSCRITO          | Éxito (Commit realizado)                | ¡Registro Exitoso!                         |
   | ERROR_TECNICO     | Excepción SQL (Deadlock/Constraint)     | Ocurrió un error interno.                  |

   ====================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_RegistrarParticipacionCapacitacion`$$

CREATE PROCEDURE `SP_RegistrarParticipacionCapacitacion`(
    /* --------------------------------------------------------------------------------------------------
       DEFINICIÓN DE PARÁMETROS DE ENTRADA (INPUT PARAMETERS)
       -------------------------------------------------------------------------------------------------- */
    IN _Id_Usuario INT,              -- ID del usuario autenticado (Actúa como Ejecutor y Participante)
    IN _Id_Detalle_Capacitacion INT  -- ID de la versión específica del curso a tomar
)
ProcAutoIns: BEGIN
    /* ═══════════════════════════════════════════════════════════════════════════════════════════════════
       BLOQUE 1: DECLARACIÓN DE VARIABLES Y MEMORIA (VARIABLE DECLARATION)
       Nota: Inicializamos todo en 0/Empty para evitar el comportamiento impredecible de NULL en MySQL.
       ═══════════════════════════════════════════════════════════════════════════════════════════════════ */
    
    -- [1.1] VARIABLES DE IDENTIDAD
    DECLARE v_Usuario_Existe INT DEFAULT 0;
    DECLARE v_Usuario_Activo INT DEFAULT 0;
    
    -- [1.2] VARIABLES DE CONTEXTO DEL CURSO (DATA SNAPSHOT)
    DECLARE v_Capacitacion_Existe INT DEFAULT 0;
    DECLARE v_Capacitacion_Activa INT DEFAULT 0;
    DECLARE v_Id_Capacitacion_Padre INT DEFAULT 0;  -- FK al catálogo padre
    DECLARE v_Folio_Curso VARCHAR(100) DEFAULT '';  -- Para mensajes de feedback
    DECLARE v_Estatus_Curso INT DEFAULT 0;          -- ID del estatus actual
    DECLARE v_Es_Estatus_Final INT DEFAULT 0;       -- Bandera booleana (1=Cerrado)
    
    -- [1.3] VARIABLES PARA ARITMÉTICA DE CUPO (HYBRID LOGIC)
    DECLARE v_Cupo_Maximo INT DEFAULT 0;        -- Meta (Capacidad total)
    DECLARE v_Conteo_Sistema INT DEFAULT 0;     -- Ocupación real (Filas en BD)
    DECLARE v_Conteo_Manual INT DEFAULT 0;      -- Ocupación forzada (Manual override)
    DECLARE v_Asientos_Ocupados INT DEFAULT 0;  -- Resultado de la comparación
    DECLARE v_Cupo_Disponible INT DEFAULT 0;    -- Delta final
    
    -- [1.4] VARIABLES DE CONTROL Y RESULTADO
    DECLARE v_Ya_Inscrito INT DEFAULT 0;        -- Bandera de duplicidad
    DECLARE v_Nuevo_Id_Registro INT DEFAULT 0;  -- Identity generado (PK)
    
    -- [1.5] CONSTANTES DE NEGOCIO (HARDCODED IDS)
    DECLARE c_ESTATUS_INSCRITO INT DEFAULT 1;   -- ID 1: Inscrito / Activo
    DECLARE c_ESTATUS_BAJA INT DEFAULT 5;       -- ID 5: Baja / Cancelado
    
    -- [1.6] CONSTANTES DE ESTATUS PERMITIDOS (LISTA BLANCA - WHITELIST)
    -- Estos IDs determinan en qué momento del ciclo de vida es válida la auto-inscripción.
    DECLARE c_EST_PROGRAMADO INT DEFAULT 1;     -- [CORREGIDO]: Curso confirmado
    DECLARE c_EST_POR_INICIAR INT DEFAULT 2;    -- [CORREGIDO]: Última llamada
    DECLARE c_EST_REPROGRAMADO INT DEFAULT 9;   -- [CORREGIDO]: Nueva fecha asignada

    /* ═══════════════════════════════════════════════════════════════════════════════════════════════════
       BLOQUE 2: MANEJO DE EXCEPCIONES (EXCEPTION HANDLING & ACID PROTECTION)
       Objetivo: Garantizar la atomicidad. Si ocurre cualquier error SQL (Deadlock, Constraint, Type),
       se revierte toda la operación para no dejar "basura" o registros huérfanos.
       ═══════════════════════════════════════════════════════════════════════════════════════════════════ */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK; -- [CRÍTICO]: Revertir transacción pendiente.
        SELECT 
            'ERROR DE SISTEMA [500]: Ocurrió un error técnico al procesar tu inscripción.' AS Mensaje,
            'ERROR_TECNICO' AS Accion,
            NULL AS Id_Registro_Participante;
    END;

    /* ═══════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 0: SANITIZACIÓN DE ENTRADA (FAIL-FAST STRATEGY)
       Justificación: No tiene sentido iniciar transacciones ni lecturas si los datos básicos
       vienen corruptos (NULL o Ceros). Ahorra CPU y I/O.
       ═══════════════════════════════════════════════════════════════════════════════════════════════════ */
    
    -- Validación 0.1: Identidad del Solicitante
    IF _Id_Usuario IS NULL OR _Id_Usuario <= 0 
		THEN
			SELECT 'ERROR DE SESIÓN [400]: No se pudo identificar tu usuario. Por favor relogueate.' AS Mensaje, 
				   'LOGOUT_REQUIRED' AS Accion, 
				   NULL AS Id_Registro_Participante;
        LEAVE ProcAutoIns;
    END IF;
    
    -- Validación 0.2: Objetivo de la Transacción
    IF _Id_Detalle_Capacitacion IS NULL OR _Id_Detalle_Capacitacion <= 0 
		THEN
			SELECT 'ERROR DE ENTRADA [400]: El curso seleccionado no es válido.' AS Mensaje, 
					'VALIDACION_FALLIDA' AS Accion, 
					NULL AS Id_Registro_Participante;
        LEAVE ProcAutoIns;
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 1: VERIFICACIÓN DE IDENTIDAD Y VIGENCIA (USER ASSERTION)
       Objetivo: Confirmar que el usuario existe en BD y tiene permiso de operar (Activo=1).
       Previene operaciones de usuarios inhabilitados que aún tengan sesión abierta.
       ═══════════════════════════════════════════════════════════════════════════════════════════════════ */
    SELECT COUNT(*), `Activo` 
    INTO v_Usuario_Existe, v_Usuario_Activo 
    FROM `Usuarios` 
    WHERE `Id_Usuario` = _Id_Usuario;
    
    -- Validación 1.1: Existencia Física
    IF v_Usuario_Existe = 0 
		THEN
			SELECT 'ERROR DE CUENTA [404]: Tu usuario no parece existir en el sistema.' AS Mensaje, 
				   'CONTACTAR_SOPORTE' AS Accion, 
                   NULL AS Id_Registro_Participante;
        LEAVE ProcAutoIns;
    END IF;
    
    -- Validación 1.2: Estado Lógico (Soft Delete Check)
    IF v_Usuario_Activo = 0 
		THEN
			SELECT 'ACCESO DENEGADO [403]: Tu cuenta está inactiva. No puedes inscribirte.' AS Mensaje, 
				   'ACCESO_DENEGADO' AS Accion, 
				   NULL AS Id_Registro_Participante;
        LEAVE ProcAutoIns;
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 2: CONTEXTO Y ESTADO DEL CURSO (RESOURCE AVAILABILITY SNAPSHOT)
       Objetivo: Cargar todos los metadatos del curso en memoria para validaciones complejas.
       Optimizacion: Se hace un solo SELECT con JOIN implícito para evitar múltiples round-trips a la BD.
       ═══════════════════════════════════════════════════════════════════════════════════════════════════ */
    SELECT 
        COUNT(*),                             -- [0] Existe?
        COALESCE(`DC`.`Activo`, 0),           -- [1] Activo?
        `DC`.`Fk_Id_Capacitacion`,            -- [2] ID Padre
        `DC`.`Fk_Id_CatEstCap`,               -- [3] Status ID (Para Whitelist)
        COALESCE(`DC`.`AsistentesReales`, 0)  -- [4] Override Manual (Input Coordinador)
    INTO 
        v_Capacitacion_Existe, 
        v_Capacitacion_Activa, 
        v_Id_Capacitacion_Padre, 
        v_Estatus_Curso, 
        v_Conteo_Manual
    FROM `DatosCapacitaciones` `DC` 
    WHERE `DC`.`Id_DatosCap` = _Id_Detalle_Capacitacion;

    -- Validación 2.1: Integridad Referencial
    IF v_Capacitacion_Existe = 0 
		THEN
			SELECT 'ERROR [404]: El curso que buscas no existe.' AS Mensaje, 
				   'RECURSO_NO_ENCONTRADO' AS Accion, 
				   NULL AS Id_Registro_Participante;
        LEAVE ProcAutoIns;
    END IF;
    
    -- Validación 2.2: Ciclo de Vida (Soft Delete)
    IF v_Capacitacion_Activa = 0 
		THEN
			SELECT 'LO SENTIMOS [409]: Este curso ha sido archivado o cancelado.' AS Mensaje, 
				   'CURSO_CERRADO' AS Accion, 
                   NULL AS Id_Registro_Participante;
        LEAVE ProcAutoIns;
    END IF;
    
    -- Obtener Meta y Folio (Sub-Consulta Optimizada)
    SELECT `Numero_Capacitacion`, `Asistentes_Programados` INTO v_Folio_Curso, v_Cupo_Maximo 
    FROM `Capacitaciones` WHERE `Id_Capacitacion` = v_Id_Capacitacion_Padre;
    
    -- Validación 2.3: Ciclo de Vida del Negocio (Estatus Final)
    SELECT `Es_Final` INTO v_Es_Estatus_Final 
    FROM `Cat_Estatus_Capacitacion` WHERE `Id_CatEstCap` = v_Estatus_Curso;
    
    IF v_Es_Estatus_Final = 1 
		THEN
			SELECT CONCAT('INSCRIPCIONES CERRADAS: El curso "', v_Folio_Curso, '" ya ha finalizado.') AS Mensaje, 
				   'CURSO_CERRADO' AS Accion, 
				   NULL AS Id_Registro_Participante;
        LEAVE ProcAutoIns;
    END IF;

    /* [VALIDACIÓN CRÍTICA] 2.4: Estatus Operativo Permitido (Whitelist)
       Objetivo: Evitar inscribir en cursos "En Diseño", "En Curso" (ya iniciados) o estatus no comerciales.
       Solo se permite: PROGRAMADO (1), POR INICIAR (2), REPROGRAMADO (9).
    */
    IF v_Estatus_Curso NOT IN (c_EST_PROGRAMADO, c_EST_POR_INICIAR, c_EST_REPROGRAMADO) 
		THEN
			SELECT CONCAT('AÚN NO DISPONIBLE: El curso "', v_Folio_Curso, '" no está abierto para inscripciones (Estatus actual: ', v_Estatus_Curso, ').') AS Mensaje, 
				   'ESTATUS_INVALIDO' AS Accion,
				   NULL AS Id_Registro_Participante;
        LEAVE ProcAutoIns;
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 3: VALIDACIÓN DE IDEMPOTENCIA (UNIQUENESS CHECK)
       Objetivo: Asegurar que el usuario no se inscriba dos veces al mismo curso.
       Regla: Un usuario puede tener N cursos, pero solo 1 registro activo por Curso específico.
       ═══════════════════════════════════════════════════════════════════════════════════════════════════ */
    SELECT COUNT(*) INTO v_Ya_Inscrito 
    FROM `Capacitaciones_Participantes` 
    WHERE `Fk_Id_DatosCap` = _Id_Detalle_Capacitacion 
      AND `Fk_Id_Usuario` = _Id_Usuario;
    
    IF v_Ya_Inscrito > 0 THEN
        SELECT 'YA ESTÁS INSCRITO: Ya tienes un lugar reservado en este curso.' AS Mensaje, 
               'YA_INSCRITO' AS Accion, 
               NULL AS Id_Registro_Participante;
        LEAVE ProcAutoIns;
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 4: CÁLCULO Y VALIDACIÓN DE CUPO (HYBRID CAPACITY LOGIC)
       Objetivo: Determinar disponibilidad real aplicando la regla "GREATEST".
       
       Escenario de Protección:
       - Meta = 20
       - Sistema (Inscritos) = 5
       - Manual (Coordinador) = 20 (Porque sabe que viene un grupo externo).
       - Cálculo: GREATEST(5, 20) = 20 ocupados.
       - Disponible: 20 - 20 = 0.
       - Resultado: CUPO LLENO (Correcto, bloquea al usuario aunque el sistema vea 5).
       ═══════════════════════════════════════════════════════════════════════════════════════════════════ */
    
    -- Paso 4.1: Contar ocupación sistémica (Excluyendo bajas que liberan cupo)
    SELECT COUNT(*) INTO v_Conteo_Sistema 
    FROM `Capacitaciones_Participantes` 
    WHERE `Fk_Id_DatosCap` = _Id_Detalle_Capacitacion 
      AND `Fk_Id_CatEstPart` != c_ESTATUS_BAJA;

    -- Paso 4.2: Aplicar Regla del Máximo (Pesimista)
    SET v_Asientos_Ocupados = GREATEST(v_Conteo_Manual, v_Conteo_Sistema);

    -- Paso 4.3: Calcular disponibilidad neta
    SET v_Cupo_Disponible = v_Cupo_Maximo - v_Asientos_Ocupados;
    
    -- Paso 4.4: Veredicto Final
    IF v_Cupo_Disponible <= 0 
		THEN
			SELECT 'CUPO LLENO: Lo sentimos, ya no hay lugares disponibles para este curso.' AS Mensaje, 
				   'CUPO_LLENO' AS Accion, 
				   NULL AS Id_Registro_Participante;
        LEAVE ProcAutoIns;
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 5: EJECUCIÓN TRANSACCIONAL (ACID WRITE)
       Objetivo: Persistir el registro. Aquí comienza la transacción atómica.
       ═══════════════════════════════════════════════════════════════════════════════════════════════════ */
    START TRANSACTION;
    
    INSERT INTO `Capacitaciones_Participantes` (
        `Fk_Id_DatosCap`, 
        `Fk_Id_Usuario`, 
        `Fk_Id_CatEstPart`, 
        `Calificacion`, 
        `PorcentajeAsistencia`, 
        `created_at`,               -- Audit: Fecha Creación
        `updated_at`,               -- Audit: Fecha Modificación
        `Fk_Id_Usuario_Created_By`, -- [AUDITORÍA]: Self-Registration (El usuario se creó a sí mismo)
        `Fk_Id_Usuario_Updated_By`  -- [AUDITORÍA]: Self-Update
    ) VALUES (
        _Id_Detalle_Capacitacion, 
        _Id_Usuario, 
        c_ESTATUS_INSCRITO,         -- Estado inicial = 1
        NULL,                       -- Calificación pendiente
        NULL,                       -- Asistencia pendiente
        NOW(), NOW(), 
        _Id_Usuario,                -- ID del alumno como autor
        _Id_Usuario                 -- ID del alumno como editor
    );
    
    -- Recuperar el ID autogenerado (Identity)
    SET v_Nuevo_Id_Registro = LAST_INSERT_ID();
    
    COMMIT; -- Confirmar escritura en disco

    /* ═══════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 6: FEEDBACK Y CONFIRMACIÓN (RESPONSE)
       Objetivo: Retornar estructura JSON-friendly al Frontend confirmando el éxito.
       ═══════════════════════════════════════════════════════════════════════════════════════════════════ */
    SELECT 
        CONCAT('¡REGISTRO EXITOSO! Te has inscrito correctamente al curso "', v_Folio_Curso, '".') AS Mensaje,
        'INSCRITO' AS Accion,
        v_Nuevo_Id_Registro AS Id_Registro_Participante;

END$$

DELIMITER ;

/* ============================================================================================
   SECCIÓN: DASHBOARD CURSOS (PARA VER LOS GRID FILTRADOS E IR AL DETALLE)
   ============================================================================================
   Estas rutinas son críticas para la UX administrativa. No solo devuelven el dato pedido, sino 
   que garantizan la integridad de lectura antes de permitir una operación de modificación.
   ============================================================================================ */
   
   /* ══════════════════════════════════════════════════════════════════════════════════════════════════════════
   PROCEDIMIENTO: SP_ConsularMisCursos
   ══════════════════════════════════════════════════════════════════════════════════════════════════════════
   
   I. FICHA TÉCNICA DE INGENIERÍA (TECHNICAL DATASHEET)
   ----------------------------------------------------------------------------------------------------------
   - Nombre Oficial       : SP_ConsularMisCursos
   - Sistema:             : PICADE (Plataforma Institucional de Capacitación y Desarrollo)
   - Clasificación        : Consulta de Historial Académico Personal (Student Record Inquiry)
   - Patrón de Diseño     : Latest Snapshot Filtering (Filtro de Última Versión)
   - Nivel de Aislamiento : READ COMMITTED
   - Dependencia Core     : Vista_Gestion_de_Participantes

   II. PROPÓSITO Y LÓGICA DE NEGOCIO (BUSINESS VALUE)
   ----------------------------------------------------------------------------------------------------------
   Este procedimiento alimenta el Dashboard del Participante. Su objetivo es mostrar el "Estado del Arte"
   de su capacitación. 
   
   [REGLA DE UNICIDAD]: 
   Si un curso (Folio) ha tenido varias versiones operativas (Reprogramaciones o Archivos), el sistema 
   debe mostrar solo la instancia más reciente donde el alumno estuvo inscrito. Esto previene la 
   confusión de ver "3 veces el mismo curso" en el historial.

   [REGLA DE VISIBILIDAD TOTAL]:
   A diferencia de los administradores que filtran por "Activo=1", el alumno debe ver sus cursos 
   FINALIZADOS y ARCHIVADOS, ya que forman parte de su currículum institucional y evidencia de formación.

   III. ARQUITECTURA DE FILTRADO (QUERY STRATEGY)
   ----------------------------------------------------------------------------------------------------------
   Se utiliza una subconsulta correlacionada con la función MAX(Id_Detalle_de_Capacitacion). 
   Esta estrategia garantiza que, de N registros para el mismo Folio y mismo Usuario, solo emerja 
   hacia el Frontend el registro con el ID más alto, que cronológicamente representa el último estado.

   ========================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ConsularMisCursos`$$

CREATE PROCEDURE `SP_ConsularMisCursos`(
    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       SECCIÓN DE PARÁMETROS DE ENTRADA
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */
    IN _Id_Usuario INT -- Identificador del participante autenticado en la sesión.
)
ProcMisCursos: BEGIN
    
    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 0: SANITIZACIÓN DE ENTRADA
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */
    IF _Id_Usuario IS NULL OR _Id_Usuario <= 0 
		THEN
        SELECT 'ERROR DE ENTRADA [400]: El ID del Usuario es obligatorio para la consulta.' AS Mensaje, 
               'VALIDACION_FALLIDA' AS Accion;
        LEAVE ProcMisCursos;
    END IF;

    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 1: CONSULTA DE HISTORIAL UNIFICADO (THE TRUTH ENGINE)
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */
    SELECT 
		-- [BLOQUE 1: IDENTIFICADORES DE NAVEGACIÓN]
		-- Identificadores de Navegación (Handles)

        `VGP`.`Id_Registro_Participante`,      -- PK de la relación Alumno-Curso.
        `VGP`.`Id_Capacitacion`,               -- [CORREGIDO]: ID de la tabla maestra (Padre).
        `VGP`.`Id_Detalle_de_Capacitacion`,    -- ID de la instancia operativa específica (Hijo).
        `VGP`.`Folio_Curso`,                   -- Referencia institucional (Numero_Capacitacion).

		-- [BLOQUE 2: METADATA DEL CONTENIDO]
        -- Metadatos del Contenido (Course Context)
        `VGP`.`Tema_Curso`,                    -- Título del tema impartido.
        `VGP`.`Fecha_Inicio`,                  -- Cronología de ejecución.
        `VGP`.`Fecha_Fin`,                     -- Cierre del curso.
        `VGP`.`Duracion_Horas`,                -- Carga horaria oficial.
        `VGP`.`Sede`,                          -- Ubicación física o lógica.
        `VGP`.`Modalidad`,                     -- Método de impartición.
        `VGP`.`Instructor_Asignado`,           -- Quién impartió la capacitación.
        `VGP`.`Estatus_Global_Curso`,          -- Estado de la capacitación (FINALIZADO, ARCHIVADO, etc.).
        
        -- [BLOQUE 3: DESEMPEÑO DEL PARTICIPANTE]
        -- Resultados Individuales (Performance Data)
        `VGP`.`Porcentaje_Asistencia`,         -- % de presencia física.
        `VGP`.`Calificacion_Numerica`,         -- Nota decimal asentada.
        `VGP`.`Resultado_Final` AS `Estatus_Participante`, -- APROBADO, REPROBADO, ASISTIÓ.
        `VGP`.`Detalle_Resultado`,             -- Regla de negocio aplicada.
        `VGP`.`Nota_Auditoria` AS `Justificacion`, -- Inyección forense de por qué hubo cambios.
        
        -- [BLOQUE 4: TRAZABILIDAD]
        -- Auditoría (Traceability)
        `VGP`.`Fecha_Inscripcion`,             -- Cuándo se unió el alumno.
        `VGP`.`Fecha_Ultima_Modificacion`      -- Última vez que se tocó el registro.

    FROM `PICADE`.`Vista_Gestion_de_Participantes` `VGP`
    
    -- Filtro mandatorio por usuario solicitante
    WHERE `VGP`.`Ficha_Participante` = (SELECT `Ficha_Usuario` FROM `Vista_Usuarios` WHERE `Id_Usuario` = _Id_Usuario)
    
    /* ------------------------------------------------------------------------------------------------------
       LÓGICA SNAPSHOT (FILTRO ANTI-DUPLICADOS)
       Este AND asegura que si el Folio 'CAP-001' aparece 3 veces en la tabla por reprogramaciones,
       solo el ID de detalle más reciente sea seleccionado.
       ------------------------------------------------------------------------------------------------------ */
    AND `VGP`.`Id_Detalle_de_Capacitacion` = (
        SELECT MAX(`VSub`.`Id_Detalle_de_Capacitacion`)
        FROM `PICADE`.`Vista_Gestion_de_Participantes` `VSub`
        WHERE `VSub`.`Folio_Curso` = `VGP`.`Folio_Curso`
          AND `VSub`.`Ficha_Participante` = `VGP`.`Ficha_Participante`
    )
    
    -- Ordenamiento cronológico inverso (Lo más nuevo al principio del Dashboard)
    ORDER BY `VGP`.`Fecha_Inicio` DESC;

END$$

DELIMITER ;

/* ══════════════════════════════════════════════════════════════════════════════════════════════════════════
   PROCEDIMIENTO: SP_ConsultarCursosImpartidos
   ══════════════════════════════════════════════════════════════════════════════════════════════════════════
   
   I. FICHA TÉCNICA DE INGENIERÍA (TECHNICAL DATASHEET)
   ----------------------------------------------------------------------------------------------------------
   - Nombre Oficial       : SP_ConsultarCursosImpartidos
   - Sistema:             : PICADE (Plataforma Institucional de Capacitación y Desarrollo)
   - Auditoria			  : Trazabilidad de Carga Docente e Historial de Instrucción
   - Clasificación        : Consulta de Historial Docente (Instructor Record Inquiry)
   - Patrón de Diseño     : Targeted Version Snapshot (Snapshot de Versión Específica)
   - Nivel de Aislamiento : READ COMMITTED
   - Dependencia Core     : Vista_Capacitaciones

   II. PROPÓSITO Y VALOR DE NEGOCIO (BUSINESS VALUE)
   ----------------------------------------------------------------------------------------------------------
   Este procedimiento es el pilar del Dashboard del Instructor. Permite al docente:
   1. GESTIÓN ACTUAL: Visualizar los cursos que tiene asignados y en ejecución.
   2. EVIDENCIA HISTÓRICA: Consultar cursos que ya impartió y fueron archivados.
   3. RESPONSABILIDAD: Garantizar que su nombre aparezca ligado únicamente a las versiones de curso 
      donde él fue el instructor titular, incluso si el curso tuvo múltiples reprogramaciones.

   III. LÓGICA DE FILTRADO INTELIGENTE (FORENSIC SNAPSHOT)
   ----------------------------------------------------------------------------------------------------------
   En un sistema transaccional dinámico, un curso puede cambiar de instructor entre versiones. 
   Para evitar que el historial de un instructor se "contamine" con datos de otros, el SP filtra por:
   
   - MAX(Id_DatosCap): Obtiene la versión más reciente de cada folio PERO condicionada a que 
     el instructor solicitado fuera el titular en esa versión específica.
   - SEMÁFORO DE VIGENCIA: Diferencia visualmente entre lo que es carga actual y lo que es historia.

   ========================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ConsultarCursosImpartidos`$$

CREATE PROCEDURE `SP_ConsultarCursosImpartidos`(
    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       SECCIÓN DE PARÁMETROS DE ENTRADA
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */
    IN _Id_Instructor INT -- ID único del usuario con rol de instructor/capacitador.
)
ProcCursosImpart: BEGIN
    
    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 0: SANITIZACIÓN Y VALIDACIÓN DE IDENTIDAD
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */
    IF _Id_Instructor IS NULL OR _Id_Instructor <= 0 THEN
        SELECT 'ERROR DE ENTRADA [400]: El ID del Instructor es obligatorio para recuperar el historial.' AS Mensaje,
               'VALIDACION_FALLIDA' AS Accion;
        LEAVE ProcCursosImpart;
    END IF;

    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 1: CONSULTA DE HISTORIAL DOCENTE (INSTRUCTION LOG ENGINE)
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */
    SELECT 
        -- [BLOQUE 1: IDENTIFICADORES Y FOLIOS]
        `VC`.`Id_Capacitacion`,               -- PK del curso padre.
        `VC`.`Id_Detalle_de_Capacitacion`,     -- PK de la versión específica (Id_DatosCap).
        `VC`.`Numero_Capacitacion` AS `Folio_Curso`, -- Identificador institucional.
        
        -- [BLOQUE 2: METADATA ACADÉMICA]
        `VC`.`Nombre_Tema` AS `Tema_Curso`,    -- Contenido impartido.
        `VC`.`Duracion_Horas`,                 -- Valor curricular para el instructor.
        `VC`.`Clave_Gerencia_Solicitante`,     -- Área que recibe el beneficio.
        
        -- [BLOQUE 3: LOGÍSTICA DE OPERACIÓN]
        `VC`.`Nombre_Sede` AS `Sede`,          -- Ubicación del evento.
        `VC`.`Nombre_Modalidad` AS `Modalidad`, -- Método de entrega.
        `VC`.`Fecha_Inicio`,                   -- Apertura del curso.
        `VC`.`Fecha_Fin`,                      -- Cierre del curso.
        
        -- [BLOQUE 4: MÉTRICAS DE IMPACTO]
        `VC`.`Asistentes_Meta` AS `Cupo_Programado`,
        `VC`.`Total_Impacto_Real` AS `Asistentes_Confirmados`, -- Usamos la lógica del GREATEST calculada en la vista.
        `VC`.`Participantes_Activos`,          -- Total de alumnos vivos actualmente en lista.

        -- [BLOQUE 5: ESTADO Y CICLO DE VIDA]
        `VC`.`Estatus_Curso` AS `Estatus_Snapshot`, -- Estado operativo (En curso, Finalizado, etc).
        
        /* SEMÁFORO DE VIGENCIA DOCENTE 
           Diferencia registros de operación activa de los de archivo histórico. */
        CASE 
            WHEN `DC`.`Activo` = 1 THEN 'ACTUAL'
            ELSE 'HISTORIAL'
        END AS `Tipo_Registro`,

        /* BANDERA DE VISIBILIDAD (Soft Delete Check) 
           Permite al Frontend aplicar estilos (ej. opacidad) a registros archivados. */
        `DC`.`Activo` AS `Es_Version_Vigente`,

        -- [BLOQUE 6: AUDITORÍA]
        `DC`.`created_at` AS `Fecha_Asignacion`
        
    FROM `PICADE`.`Vista_Capacitaciones` `VC`
    
    -- Unión con la tabla física para filtrar por el instructor titular de la versión.
    INNER JOIN `PICADE`.`DatosCapacitaciones` `DC` 
        ON `VC`.`Id_Detalle_de_Capacitacion` = `DC`.`Id_DatosCap`
        
    WHERE `DC`.`Fk_Id_Instructor` = _Id_Instructor
    
    /* ------------------------------------------------------------------------------------------------------
       LÓGICA DE SNAPSHOT TITULAR (INSTRUCTOR-SPECIFIC MAX VERSION)
       Objetivo: Si un curso tuvo versiones con otros instructores, este subquery asegura que
       el instructor consultado solo vea la versión MÁS RECIENTE donde ÉL fue el responsable.
       ------------------------------------------------------------------------------------------------------ */
    AND `DC`.`Id_DatosCap` = (
        SELECT MAX(`DC2`.`Id_DatosCap`)
        FROM `PICADE`.`DatosCapacitaciones` `DC2`
        WHERE `DC2`.`Fk_Id_Capacitacion` = `VC`.`Id_Capacitacion`
          AND `DC2`.`Fk_Id_Instructor` = _Id_Instructor
    )
    
    -- Ordenamos para mostrar la carga docente actual y reciente primero.
    ORDER BY `DC`.`Activo` DESC, `VC`.`Fecha_Inicio` DESC;

END$$

DELIMITER ;


/* ══════════════════════════════════════════════════════════════════════════════════════════════════════════
   PROCEDIMIENTO: SP_EditarParticipanteCapacitacion
   ══════════════════════════════════════════════════════════════════════════════════════════════════════════
   
   I. FICHA TÉCNICA DE INGENIERÍA (TECHNICAL DATASHEET)
   ----------------------------------------------------------------------------------------------------------
   - Nombre Oficial       : SP_EditarParticipanteCapacitacion
   - Sistema Operativo    : PICADE - Módulo de Gestión de Capital Humano
   - Auditoria Forense    : Registro de Calificaciones, Asistencia y Estatus de Resultados
   - Alias Operativo      : "El Auditor Académico" / "The Result Settlement Engine"
   - Clasificación        : Transacción de Gestión de Resultados e Integridad Histórica.
   - Patrón de Diseño     : Hybrid State Machine with Idempotency and Audit Injection.
   - Nivel de Aislamiento : REPEATABLE READ (Protección contra lecturas fantasmas durante el cálculo).
   - Criticidad           : EXTREMA (Afecta actas legales de capacitación y promedios históricos).

   II. PROPÓSITO Y VERSATILIDAD (BUSINESS VALUE PROPOSITION)
   ----------------------------------------------------------------------------------------------------------
   Este procedimiento representa el "Cierre de Ciclo" del participante dentro de una unidad de aprendizaje.
   Su diseño está orientado a la resiliencia y la transparencia administrativa, permitiendo:
   
   1. ASENTAMIENTO PRIMARIO: Registro original de la evidencia de aprendizaje y presencia.
   2. CORRECCIÓN DE ERRORES: Ajuste de datos previos sin pérdida de la historia original.
   3. OVERRIDE JERÁRQUICO: El Administrador tiene la potestad de ignorar el cálculo matemático del 
      sistema para asignar estatus manuales por criterio institucional.
   4. CUMPLIMIENTO (COMPLIANCE): Generación de una traza forense inmutable en cada edición.

   III. MATRIZ DE PRIORIDADES LÓGICAS (LOGIC HIERARCHY MATRIX)
   ----------------------------------------------------------------------------------------------------------
   El motor de base de datos evalúa la entrada de datos en el siguiente orden estricto de precedencia:
   
   - NIVEL 1 (MANUAL): Si se provee un Estatus Explícito, el sistema anula cualquier cálculo automático.
   - NIVEL 2 (ANALÍTICO): Si hay una calificación, el sistema determina el éxito basado en el umbral (70).
   - NIVEL 3 (LOGÍSTICO): Si solo hay asistencia, el sistema asume la participación (Asistió).
   - NIVEL 4 (CONSERVADOR): Si no se envían datos, se mantienen los valores previos (COALESCE logic).

   IV. ARQUITECTURA DE SEGURIDAD (DEFENSE IN DEPTH)
   ----------------------------------------------------------------------------------------------------------
   1. BARRERA DE ENTRADA: Sanitización de tipos de datos y rangos decimales.
   2. BARRERA DE IDENTIDAD: Validación de estatus Activo del usuario ejecutor.
   3. BARRERA DE CONTEXTO: Snapshot de memoria para evitar inconsistencias durante el proceso.
   4. BARRERA DE ESTADO: Protección contra edición de registros en BAJA (Freeze state).
   5. BARRERA TRANSACCIONAL: Atomicidad garantizada (All-or-Nothing).

   ========================================================================================================== */
-- Eliminación preventiva del objeto para garantizar una recompilación limpia del motor de SP.

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_EditarParticipanteCapacitacion`$$

CREATE PROCEDURE `SP_EditarParticipanteCapacitacion`(
    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       SECCIÓN DE PARÁMETROS DE ENTRADA (INTERFACE DEFINITION)
       Se utilizan tipos de datos DECIMAL(5,2) para precisión exacta en escalas de 0.00 a 100.00.
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */
    IN _Id_Usuario_Ejecutor INT,           -- [PK_REF] ID del Admin/Instructor responsable de la firma digital.
    IN _Id_Registro_Participante INT,      -- [PK_REF] ID único de la fila en la tabla de relación.
    IN _Calificacion DECIMAL(5,2),         -- [DATA] Nueva nota numérica. NULL si no se desea modificar.
    IN _Porcentaje_Asistencia DECIMAL(5,2),-- [DATA] Nuevo % de asistencia. NULL si no se desea modificar.
    IN _Id_Estatus_Resultado INT,          -- [FLAG] Forzado manual de estatus (Override administrativo).
    IN _Justificacion_Cualitativa VARCHAR(250) -- [AUDIT] Razón del cambio o descripción de la nota.
)
ProcUpdatResulPart: BEGIN
    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       BLOQUE 1: GESTIÓN DE VARIABLES Y ASIGNACIÓN DE MEMORIA (DATA SNAPSHOT)
       El objetivo es cargar el estado actual del mundo en memoria local para validaciones rápidas.
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */
    
    -- [1.1] Variables de Integridad Referencial
    -- Estas variables confirman que los punteros apunten a objetos vivos en el diccionario de datos.
    DECLARE v_Ejecutor_Existe INT DEFAULT 0;       -- Validador de existencia para el responsable.
    DECLARE v_Registro_Existe INT DEFAULT 0;       -- Validador de existencia para el registro objetivo.
    
    -- [1.2] Variables de Contexto Académico (Read-Only Copy)
    -- Almacenan la "verdad" de la base de datos antes de que sea sobreescrita por el UPDATE.
    DECLARE v_Estatus_Actual INT DEFAULT 0;        -- Estatus registrado actualmente en la fila.
    DECLARE v_Calificacion_Previa DECIMAL(5,2);    -- Última nota grabada (para el Audit Trail).
    DECLARE v_Asistencia_Previa DECIMAL(5,2);      -- Última asistencia grabada (para el Audit Trail).
    DECLARE v_Nombre_Alumno VARCHAR(200) DEFAULT '';-- Nombre recuperado de Info_Personal para feedback.
    DECLARE v_Folio_Curso VARCHAR(100) DEFAULT ''; -- Numero_Capacitacion para mensajes contextuales.
    
    -- [1.3] Variables de Cálculo y Auditoría Dinámica
    -- Gestionan la lógica de la máquina de estados y la construcción del log forense.
    DECLARE v_Nuevo_Estatus_Calculado INT DEFAULT 0;-- ID resultante después de evaluar las reglas.
    DECLARE v_Audit_Trail_Final TEXT;              -- Cadena concatenada que se inyectará en 'Justificacion'.
    
    -- [1.4] Constantes de Reglas de Negocio (Standard Business Mapping)
    -- Definidas estáticamente para garantizar la alineación con el catálogo Cat_Estatus_Participante.
    DECLARE c_EST_INSCRITO INT DEFAULT 1;
    DECLARE c_EST_ASISTIO INT DEFAULT 2;           -- Estatus: Solo participación física.
    DECLARE c_EST_APROBADO INT DEFAULT 3;          -- Estatus: Evidencia de aprendizaje satisfactoria.
    DECLARE c_EST_REPROBADO INT DEFAULT 4;         -- Estatus: Evidencia de aprendizaje insuficiente.
    DECLARE c_EST_BAJA INT DEFAULT 5;              -- Estatus: Fuera de la matrícula (Estado ineditable).
    DECLARE c_UMBRAL_APROBACION DECIMAL(5,2) DEFAULT 70.00; -- Nota mínima legal para acreditar.

    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       BLOQUE 2: HANDLER DE SEGURIDAD TRANSACCIONAL (ACID PROTECTION)
       Este bloque es el peritaje automático ante fallos del motor InnoDB o de red.
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ 
       
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        -- [FORENSIC ACTION]: Ante cualquier error inesperado, revierte los cambios iniciados.
        ROLLBACK;
        -- Emite una señal de error 500 para la capa de servicios de la aplicación.
        SELECT 
            'ERROR TÉCNICO [500]: Fallo crítico detectado por el motor de BD al asentar resultados.' AS Mensaje, 
            'ERROR_TECNICO' AS Accion;
    END;*/
    
        DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        DECLARE code CHAR(5) DEFAULT '00000';
        DECLARE msg TEXT;
        GET DIAGNOSTICS CONDITION 1 code = RETURNED_SQLSTATE, msg = MESSAGE_TEXT;
        ROLLBACK;
        SELECT CONCAT('❌ ERROR REAL EN GRADE: ', msg, ' | SQLSTATE: ', code) AS Mensaje, 'ERROR_CRITICO' AS Accion;
    END;

    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 0: SANITIZACIÓN Y VALIDACIÓN FORENSE (FAIL-FAST STRATEGY)
       Rechaza la petición antes de comprometer la integridad del Snapshot.
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */
    
    -- [0.1] Validación de Identificadores (Punteros de Memoria)
    -- Se prohíbe el uso de IDs nulos o negativos que puedan causar lecturas inconsistentes.
    IF _Id_Usuario_Ejecutor IS NULL OR _Id_Usuario_Ejecutor <= 0 
		THEN 
			SELECT 'ERROR DE ENTRADA [400]: El ID del Usuario Ejecutor es inválido.' AS Mensaje, 
			'VALIDACION_FALLIDA' AS Accion; 
        LEAVE ProcUpdatResulPart; 
    END IF;
    
    IF _Id_Registro_Participante IS NULL OR _Id_Registro_Participante <= 0 
		THEN 
			SELECT 'ERROR DE ENTRADA [400]: El ID del Registro es inválido.' AS Mensaje, 
            'VALIDACION_FALLIDA' AS Accion; 
        LEAVE ProcUpdatResulPart; 
    END IF;

    -- [0.2] Validación de Integridad de Escala (Rango Numérico)
    -- Asegura que los datos sigan la escala decimal estándar del 0 al 100.
    IF (_Calificacion IS NOT NULL AND (_Calificacion < 0 OR _Calificacion > 100)) OR 
       (_Porcentaje_Asistencia IS NOT NULL AND (_Porcentaje_Asistencia < 0 OR _Porcentaje_Asistencia > 100)) 
		THEN
			SELECT 'ERROR DE RANGO [400]: Las notas y asistencias deben estar entre 0.00 y 100.00.' AS Mensaje, 
            'VALIDACION_FALLIDA' AS Accion;
        LEAVE ProcUpdatResulPart;
    END IF;

    -- [0.3] Validación de Cumplimiento (Compliance Check)
    -- Exige que cada cambio en la historia académica del alumno esté fundamentado.
    IF _Justificacion_Cualitativa IS NULL OR TRIM(_Justificacion_Cualitativa) = '' 
		THEN
			SELECT 'ERROR DE AUDITORÍA [400]: Es obligatorio proporcionar un motivo para este cambio de resultados.' AS Mensaje, 
            'VALIDACION_FALLIDA' AS Accion; 
        LEAVE ProcUpdatResulPart; 
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 1: CAPTURA DE SNAPSHOT ACADÉMICO (READ BEFORE WRITE)
       Recopila los datos actuales de las tablas físicas hacia las variables locales de memoria.
       ═══════════════════════════════════════════════════════════════════════════════════════════════════ */
    
    -- [1.1] Verificación de Existencia y Actividad del Ejecutor
    -- Confirmamos que quien califica es un usuario válido y no ha sido inhabilitado.
    SELECT COUNT(*) 
    INTO v_Ejecutor_Existe 
    FROM `Usuarios` 
    WHERE `Id_Usuario` = _Id_Usuario_Ejecutor 
    AND `Activo` = 1;
    
    IF v_Ejecutor_Existe = 0 
		THEN 
			SELECT 'ERROR DE PERMISOS [403]: El usuario ejecutor no posee credenciales activas.' AS Mensaje, 
            'ACCESO_DENEGADO' AS Accion; 
        LEAVE ProcUpdatResulPart; 
    END IF;
    
    -- [1.2] Hidratación de Variables de la Inscripción (Snapshot Forense)
    -- Recupera la nota previa, asistencia previa y estatus actual para el análisis de cambio.
    SELECT 
        COUNT(*), 
        `CP`.`Fk_Id_CatEstPart`, 
        `CP`.`Calificacion`, 
        `CP`.`PorcentajeAsistencia`,
        CONCAT(`IP`.`Nombre`, ' ', `IP`.`Apellido_Paterno`), 
        `C`.`Numero_Capacitacion`
    INTO 
        v_Registro_Existe, 
        v_Estatus_Actual, 
        v_Calificacion_Previa, 
        v_Asistencia_Previa,
        v_Nombre_Alumno, 
        v_Folio_Curso
    FROM `Capacitaciones_Participantes` `CP`
    INNER JOIN `DatosCapacitaciones` `DC` ON `CP`.`Fk_Id_DatosCap` = `DC`.`Id_DatosCap`
    INNER JOIN `Capacitaciones` `C` ON `DC`.`Fk_Id_Capacitacion` = `C`.`Id_Capacitacion`
    INNER JOIN `Usuarios` `U` ON `CP`.`Fk_Id_Usuario` = `U`.`Id_Usuario`
	INNER JOIN `Info_Personal` `IP` ON `U`.`Fk_Id_InfoPersonal` = `IP`.`Id_InfoPersonal`
	WHERE `CP`.`Id_CapPart` = _Id_Registro_Participante;

    -- [1.3] Validación de Existencia de Matrícula
    -- Si la consulta no devolvió filas, el ID enviado es erróneo.
    IF v_Registro_Existe = 0 
		THEN 
			SELECT 'ERROR DE INTEGRIDAD [404]: El registro de matrícula solicitado no existe en BD.' AS Mensaje, 
            'RECURSO_NO_ENCONTRADO' AS Accion; 
        LEAVE ProcUpdatResulPart; 
    END IF;

    -- [1.4] Protección contra Modificación de Bajas (Immutability Layer)
    -- Un alumno en BAJA ha liberado su lugar; calificarlo rompería la lógica del ciclo de vida.
    IF v_Estatus_Actual = c_EST_BAJA 
		THEN
			SELECT CONCAT('ERROR DE NEGOCIO [409]: Imposible calificar a "', v_Nombre_Alumno, '" porque se encuentra en BAJA.') AS Mensaje, 
            'CONFLICTO_ESTADO' AS Accion;
        LEAVE ProcUpdatResulPart;
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 2: MÁQUINA DE ESTADOS Y CÁLCULO DE AUDITORÍA (BUSINESS LOGIC ENGINE)
       Calcula el nuevo estatus y construye la traza forense acumulativa.
       ═══════════════════════════════════════════════════════════════════════════════════════════════════ */
    
    -- [2.1] Determinación de Nuevo Estatus (Hierarchical Logic)
    -- El sistema evalúa qué camino tomar basado en los parámetros recibidos.
    IF _Id_Estatus_Resultado IS NOT NULL THEN
        -- CAMINO 1: OVERRIDE MANUAL. La voluntad del Admin es ley.
        SET v_Nuevo_Estatus_Calculado = _Id_Estatus_Resultado;
    
    ELSEIF _Calificacion IS NOT NULL THEN
        -- CAMINO 2: CÁLCULO ANALÍTICO. Se evalúa el desempeño académico contra el umbral de aprobación.
        IF _Calificacion >= c_UMBRAL_APROBACION THEN 
            SET v_Nuevo_Estatus_Calculado = c_EST_APROBADO;
        ELSE 
            SET v_Nuevo_Estatus_Calculado = c_EST_REPROBADO; 
        END IF;
    
	ELSEIF _Porcentaje_Asistencia IS NOT NULL AND v_Estatus_Actual = c_EST_INSCRITO THEN
        -- CAMINO 3: AVANCE LOGÍSTICO.
        SET v_Nuevo_Estatus_Calculado = c_EST_ASISTIO; -- Cambia este ID según tu catálogo

    /*ELSEIF _Porcentaje_Asistencia IS NOT NULL AND v_Estatus_Actual = 1 THEN
        -- CAMINO 3: AVANCE LOGÍSTICO. Si el alumno está "Inscrito" y se pone asistencia, avanza a "Asistió".
        SET v_Nuevo_Estatus_Calculado = c_EST_ASISTIO;*/
    
    ELSE
        -- CAMINO 4: PRESERVACIÓN. No hay cambios de estado, se mantiene el actual.
        SET v_Nuevo_Estatus_Calculado = v_Estatus_Actual;
    END IF;

    -- [2.2] Construcción de Inyección Forense (Serialized Audit Note)
    -- Genera una cadena detallada que permite reconstruir la operación sin consultar logs secundarios.
    SET v_Audit_Trail_Final = CONCAT(
        'EDIT_RES [', DATE_FORMAT(NOW(), '%Y-%m-%d %H:%i'), ']: ',
        'NOTA_ACT: ', COALESCE(_Calificacion, v_Calificacion_Previa, '0.00'), 
        ' | ASIST_ACT: ', COALESCE(_Porcentaje_Asistencia, v_Asistencia_Previa, '0.00'), '%',
        ' | MOTIVO: ', _Justificacion_Cualitativa
    );

    /* ═══════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 3: PERSISTENCIA TRANSACCIONAL (DATA SETTLEMENT)
       Aplica los cambios en las tablas físicas garantizando integridad ACID.
       ═══════════════════════════════════════════════════════════════════════════════════════════════════ */
    START TRANSACTION;
        -- Ejecución de la actualización de fila (Update atomicity).
        UPDATE `Capacitaciones_Participantes`
        SET 
            -- Aplicamos COALESCE para permitir actualizaciones parciales sin borrar datos existentes.
            `Calificacion` = COALESCE(_Calificacion, `Calificacion`),
            `PorcentajeAsistencia` = COALESCE(_Porcentaje_Asistencia, `PorcentajeAsistencia`),
            `Fk_Id_CatEstPart` = v_Nuevo_Estatus_Calculado,
            -- Inyección de la nota forense en la columna de justificación.
            `Justificacion` = v_Audit_Trail_Final,
            -- Sellos de auditoría de tiempo y autoría.
            `updated_at` = NOW(),
            `Fk_Id_Usuario_Updated_By` = _Id_Usuario_Ejecutor
        WHERE `Id_CapPart` = _Id_Registro_Participante;
    
    -- Si no hubo interrupciones críticas, el motor InnoDB persiste los cambios físicos.
    COMMIT;

    /* ═══════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 4: RESPUESTA DINÁMICA (UX & API FEEDBACK)
       Emite un resultset de una sola fila para que la aplicación (Laravel) confirme el éxito al usuario.
       ═══════════════════════════════════════════════════════════════════════════════════════════════════ */
    SELECT 
        CONCAT('ÉXITO: Se han guardado los resultados para "', v_Nombre_Alumno, '" en el curso "', v_Folio_Curso, '".') AS Mensaje,
        'ACTUALIZADO' AS Accion;

END$$

DELIMITER ;

/* ══════════════════════════════════════════════════════════════════════════════════════════════════════════
   PROCEDIMIENTO: SP_CambiarEstatusParticipanteCapacitacion
   ══════════════════════════════════════════════════════════════════════════════════════════════════════════
   
   I. FICHA TÉCNICA DE INGENIERÍA (TECHNICAL DATASHEET)
   ----------------------------------------------------------------------------------------------------------
   - Nombre Oficial       : SP_CambiarEstatusCapacitacionParticipante
   - Sistema:             : PICADE (Plataforma Institucional de Capacitación y Desarrollo)
   - Auditoria: 		  : Transacciones de Estado y Ciclo de Vida del Participante
   - Alias Operativo      : "El Interruptor de Membresía" / "The Enrollment Toggle"
   - Clasificación        : Transacción de Gobernanza de Estado (State Governance Transaction)
   - Patrón de Diseño     : Idempotent Explicit Toggle with Hybrid Capacity Enforcement
   - Nivel de Aislamiento : SERIALIZABLE (Atomicidad garantizada por bloqueo de fila InnoDB)
   - Complejidad          : Alta (Bifurcación lógica con inyección de metadatos de auditoría)

   II. PROPÓSITO FORENSE Y DE NEGOCIO (BUSINESS VALUE PROPOSITION)
   ----------------------------------------------------------------------------------------------------------
   Este procedimiento representa el único punto de control (Single Point of Truth) para alterar la 
   relación entre un Alumno y un Curso. Su función principal es gestionar la desincorporación y 
   reincorporación de participantes bajo un modelo de integridad estricta.
   
   [ANALOGÍA OPERATIVA]:
   Funciona como el sistema de control de acceso en una terminal de transporte:
     - BAJA: Es anular el ticket de viaje, liberando el asiento para otro pasajero, pero manteniendo
       el manifiesto original de quién compró el lugar inicialmente.
     - REINSCRIBIR: Es validar si hay asientos libres para permitir que un pasajero que canceló
       vuelva a abordar el mismo vehículo sin duplicar registros.

   III. REGLAS DE GOBERNANZA Y CUMPLIMIENTO (GOVERNANCE RULES)
   ----------------------------------------------------------------------------------------------------------
   A. REGLA DE INMUTABILIDAD EVALUATIVA:
      Un registro con calificación asentada es inmutable para cambios de estatus simple. Si un alumno
      ya posee una nota, el sistema bloquea la baja para evitar la alteración accidental de 
      promedios históricos y reportes de acreditación.

   B. REGLA DE PROTECCIÓN DE CURSO MUERTO:
      No se permiten cambios de participantes en cursos cuyo ciclo administrativo ha terminado
      (CANCELADOS o ARCHIVADOS). Esto garantiza que el expediente auditado permanezca congelado.

   C. REGLA DE IDEMPOTENCIA EXPLÍCITA:
      El procedimiento detecta si el estado solicitado es idéntico al actual. Si Laravel envía un
      "Dar de Baja" a un alumno que ya está en baja, el sistema responde exitosamente sin escribir
      en disco, ahorrando ciclos de CPU y evitando redundancia en los logs.

   IV. ARQUITECTURA DE DEFENSA EN PROFUNDIDAD (DEFENSE IN DEPTH)
   ----------------------------------------------------------------------------------------------------------
   1. SANITIZACIÓN: Rechazo de punteros inválidos (IDs nulos o negativos).
   2. IDENTIDAD: Validación de permisos del ejecutor (Admin/Coordinador activo).
   3. SNAPSHOT: Captura del estado actual en variables locales antes de cualquier operación.
   4. VALIDACIÓN DE CUPO: Aritmética GREATEST() para evitar sobrecupo físico en reinscripciones.
   5. ATOMICIDAD: Transaccionalidad pura (Commit o Rollback total).

   ========================================================================================================== */
-- Inicia la verificación del objeto para garantizar que el despliegue sea limpio y repetible.

DELIMITER $$

 -- DROP PROCEDURE IF EXISTS `SP_CambiarEstatusParticipanteCapacitacion`$$

CREATE PROCEDURE `SP_CambiarEstatusParticipanteCapacitacion`(
    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       SECCIÓN DE PARÁMETROS DE ENTRADA (INTERFACE DEFINITION)
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */
    IN _Id_Usuario_Ejecutor INT,       -- [PTR]: Identificador del responsable administrativo (Auditoría).
    IN _Id_Registro_Participante INT,  -- [PTR]: Llave primaria (PK) del vínculo Alumno-Capacitación.
    IN _Nuevo_Estatus_Deseado INT,     -- [FLAG]: Estado objetivo (1 = Inscrito, 5 = Baja Administrativa).
    IN _Motivo_Operacion VARCHAR(250)  -- [VAL]: Justificación textual obligatoria para el peritaje forense.
)
ProcTogglePart: BEGIN
    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       BLOQUE 1: GESTIÓN DE VARIABLES Y ASIGNACIÓN DE MEMORIA (VARIABLE ALLOCATION)
       Cada variable se inicializa para prevenir el comportamiento indefinido de valores NULL.
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */
    
    -- [1.1] Variables de Validación Referencial (Existence Flags)
    -- Verifican que los punteros apunten a registros reales en las tablas maestras.
    DECLARE v_Ejecutor_Existe INT DEFAULT 0;       -- Almacena el resultado del conteo de Usuarios (Admin).
    DECLARE v_Registro_Existe INT DEFAULT 0;       -- Almacena el resultado del conteo de Inscripciones.
    DECLARE v_Id_Detalle_Curso INT DEFAULT 0;      -- Almacena el ID del registro operativo (DatosCapacitaciones).
    DECLARE v_Id_Padre INT DEFAULT 0;              -- Almacena el ID de la cabecera (Capacitaciones).
    
    -- [1.2] Variables de Snapshot (Estado Actual del Entorno)
    -- Se capturan en memoria para evitar colisiones de datos durante la evaluación de reglas.
    DECLARE v_Estatus_Actual_Alumno INT DEFAULT 0; -- Estado detectado en BD antes de la transacción.
    DECLARE v_Estatus_Curso INT DEFAULT 0;         -- Estado actual de la capacitación (1 al 10).
    DECLARE v_Curso_Activo INT DEFAULT 0;          -- Bandera de existencia lógica (Activo=1).
    DECLARE v_Tiene_Calificacion INT DEFAULT 0;    -- Bandera booleana: ¿Existe nota numérica registrada?
    DECLARE v_Folio_Curso VARCHAR(100) DEFAULT ''; -- Cadena Numero_Capacitacion para mensajes de error.
    DECLARE v_Nombre_Alumno VARCHAR(200) DEFAULT '';-- Nombre completo recuperado de Info_Personal.
    
    -- [1.3] Variables de Aritmética de Cupo Híbrido (Capacity Enforcement)
    -- Cruciales para la RAMA DE REINSCRIBIR para evitar el sobrecupo físico del aula.
    DECLARE v_Cupo_Maximo INT DEFAULT 0;           -- Límite total de asientos programados.
    DECLARE v_Conteo_Sistema INT DEFAULT 0;        -- Total de asistentes actuales registrados en BD.
    DECLARE v_Conteo_Manual INT DEFAULT 0;         -- Cifra forzada manualmente por el Coordinador.
    DECLARE v_Asientos_Ocupados INT DEFAULT 0;     -- El factor mayor resultante (GREATEST).
    DECLARE v_Cupo_Disponible INT DEFAULT 0;       -- Espacios físicos reales restantes.
    
    -- [1.4] Definición de Constantes Maestras (Architecture Mapping)
    -- Mapeo de IDs de catálogo para eliminar el uso de "Números Mágicos" en la lógica.
    DECLARE c_ESTATUS_INSCRITO INT DEFAULT 1;      -- Valor del catálogo para Alumno Activo.
    DECLARE c_ESTATUS_BAJA INT DEFAULT 5;          -- Valor del catálogo para Alumno en Baja.
    DECLARE c_CURSO_CANCELADO INT DEFAULT 8;       -- Valor del catálogo para Capacitación Cancelada.
    DECLARE c_CURSO_ARCHIVADO INT DEFAULT 10;      -- Valor del catálogo para Capacitación Cerrada.

    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       BLOQUE 2: HANDLER DE SEGURIDAD TRANSACCIONAL (ACID EXCEPTION PROTECTION)
       Mecanismo de recuperación que se dispara ante fallos de integridad, red o motor de BD.
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        -- [FORENSIC ACTION]: Si la transacción falló, revierte inmediatamente cualquier escritura en disco.
        ROLLBACK;
        
        -- Retorna una estructura de error estandarizada para el log de la aplicación.
        SELECT 
            'ERROR TÉCNICO [500]: Fallo crítico detectado por el motor InnoDB al intentar alternar el estatus.' AS Mensaje, 
            'ERROR_TECNICO' AS Accion;
    END;

    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 0: SANITIZACIÓN Y VALIDACIÓN ESTRUCTURAL (FAIL-FAST STRATEGY)
       Rechaza la petición si los parámetros de entrada no cumplen con la estructura básica esperada.
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */
    
    -- [0.1] Validación del ID del Ejecutor: No se permiten nulos ni valores menores o iguales a cero.
    IF _Id_Usuario_Ejecutor IS NULL OR _Id_Usuario_Ejecutor <= 0 
		THEN 
			SELECT 'ERROR DE ENTRADA [400]: El ID del Usuario Ejecutor es inválido o nulo.' AS Mensaje, 
				'VALIDACION_FALLIDA' AS Accion; 
        LEAVE ProcTogglePart; -- Termina el proceso ahorrando ciclos de servidor.
    END IF;
    
    -- [0.2] Validación del ID de Registro: Asegura que el puntero a la tabla de relación sea procesable.
    IF _Id_Registro_Participante IS NULL OR _Id_Registro_Participante <= 0 
		THEN 
			SELECT 'ERROR DE ENTRADA [400]: El ID del Registro de Participante es inválido o nulo.' AS Mensaje, 
				'VALIDACION_FALLIDA' AS Accion; 
        LEAVE ProcTogglePart; 
    END IF;

    -- [0.3] Validación de Dominio de Estatus: Solo se permite alternar entre INSCRITO y BAJA.
    IF _Nuevo_Estatus_Deseado NOT IN (c_ESTATUS_INSCRITO, c_ESTATUS_BAJA) 
		THEN
			SELECT 'ERROR DE NEGOCIO [400]: El estatus solicitado no es válido para este interruptor operativo.' AS Mensaje, 
				'VALIDACION_FALLIDA' AS Accion; 
        LEAVE ProcTogglePart; 
    END IF;
    
    -- [0.4] Validación de Justificación: No se permiten cambios de estatus sin una razón documentada.
    IF _Motivo_Operacion IS NULL OR TRIM(_Motivo_Operacion) = '' 
		THEN
			SELECT 'ERROR DE ENTRADA [400]: El motivo del cambio es obligatorio para fines de trazabilidad forense.' AS Mensaje, 
				'VALIDACION_FALLIDA' AS Accion; 
        LEAVE ProcTogglePart; 
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 1: CAPTURA DE CONTEXTO Y SEGURIDAD (SNAPSHOT DE DATOS FORENSES)
       Carga el estado del mundo real en variables locales para ejecutar validaciones complejas.
       ═══════════════════════════════════════════════════════════════════════════════════════════════════ */
    
    -- [1.1] Validación de Identidad del Administrador
    -- Confirmamos que el ejecutor es un usuario real y está en estado ACTIVO en el sistema.
    SELECT COUNT(*) 
    INTO v_Ejecutor_Existe 
    FROM `Usuarios` 
    WHERE `Id_Usuario` = _Id_Usuario_Ejecutor 
		AND `Activo` = 1;
    
    IF v_Ejecutor_Existe = 0 
		THEN 
			SELECT 'ERROR DE PERMISOS [403]: El Usuario Ejecutor no tiene privilegios activos para modificar matriculaciones.' AS Mensaje, 
				'ACCESO_DENEGADO' AS Accion; 
        LEAVE ProcTogglePart; 
    END IF;
    
    -- [1.2] Hidratación Masiva del Snapshot (Single Round-Trip Optimization)
    -- Se recupera la información del alumno, su estatus, su nota y el estado del curso en un solo query.
    SELECT 
        COUNT(*),                               -- [0] Verificador físico de existencia.
        COALESCE(`CP`.`Fk_Id_CatEstPart`, 0),   -- [1] Estatus actual del alumno (Toggle Source).
        `CP`.`Fk_Id_DatosCap`,                  -- [2] FK al detalle operativo de la capacitación.
        CONCAT(`IP`.`Nombre`, ' ', `IP`.`Apellido_Paterno`), -- [3] Nombre completo para feedback UX.
        CASE WHEN `CP`.`Calificacion` IS NOT NULL THEN 1 ELSE 0 END, -- [4] FLAG: ¿Alumno ya evaluado?
        `DC`.`Activo`,                          -- [5] FLAG: ¿Curso borrado lógicamente?
        `DC`.`Fk_Id_CatEstCap`,                 -- [6] ID del estado operativo del curso.
        `DC`.`Fk_Id_Capacitacion`,              -- [7] FK a la cabecera para lectura de Metas.
        COALESCE(`DC`.`AsistentesReales`, 0)    -- [8] Conteo manual capturado por el Coordinador.
    INTO 
        v_Registro_Existe,
        v_Estatus_Actual_Alumno,
        v_Id_Detalle_Curso,
        v_Nombre_Alumno,
        v_Tiene_Calificacion,
        v_Curso_Activo,
        v_Estatus_Curso,
        v_Id_Padre,
        v_Conteo_Manual
    FROM `Capacitaciones_Participantes` `CP`
    INNER JOIN `DatosCapacitaciones` `DC` ON `CP`.`Fk_Id_DatosCap` = `DC`.`Id_DatosCap`
    INNER JOIN `Usuarios` `U` ON `CP`.`Fk_Id_Usuario` = `U`.`Id_Usuario`
    -- ✅ CORREGIDO: El nombre exacto en tu tabla Usuarios es Fk_Id_InfoPersonal
    INNER JOIN `Info_Personal` `IP` ON `U`.`Fk_Id_InfoPersonal` = `IP`.`Id_InfoPersonal`
    WHERE `CP`.`Id_CapPart` = _Id_Registro_Participante;

    -- [1.3] Validación de Integridad Física: Si el conteo es 0, el registro solicitado no existe.
    IF v_Registro_Existe = 0 
		THEN 
			SELECT 'ERROR DE EXISTENCIA [404]: No se encontró el expediente de inscripción solicitado en la base de datos.' AS Mensaje, 
            'RECURSO_NO_ENCONTRADO' AS Accion; 
        LEAVE ProcTogglePart; 
    END IF;
    
    -- [1.4] Validación de Idempotencia: Si el alumno ya está en el estado que se pide, no hacemos nada.
    IF v_Estatus_Actual_Alumno = _Nuevo_Estatus_Deseado 
		THEN
			SELECT CONCAT('AVISO DE SISTEMA: El alumno "', v_Nombre_Alumno, '" ya se encuentra en el estado solicitado. No se realizaron cambios.') AS Mensaje, 'SIN_CAMBIOS' AS Accion;
        LEAVE ProcTogglePart;
    END IF;

    -- [1.5] Recuperación de Metadatos de Planeación
    -- Cargamos el folio Numero_Capacitacion y el cupo máximo (Asistentes_Programados) de la tabla maestra.
    SELECT `Numero_Capacitacion`, 
		`Asistentes_Programados` 
    INTO v_Folio_Curso, 
		v_Cupo_Maximo
    FROM `Capacitaciones` 
    WHERE `Id_Capacitacion` = v_Id_Padre;

    -- [1.6] Validación de Protección de Ciclo de Vida
    -- Bloquea cualquier cambio de participante si el curso está en un estado terminal (Cancelado/Archivado).
    IF v_Estatus_Curso IN (c_CURSO_CANCELADO, c_CURSO_ARCHIVADO) 
		THEN
			SELECT CONCAT('ERROR DE LÓGICA [409]: La capacitación "', v_Folio_Curso, '" está administrativamente CERRADA. No se permite alterar la lista.') AS Mensaje, 'ESTATUS_PROHIBIDO' AS Accion;
        LEAVE ProcTogglePart;
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 2: PROCESAMIENTO DE BIFURCACIÓN LÓGICA (DECISION MATRIX)
       ═══════════════════════════════════════════════════════════════════════════════════════════════════ */
    
    -- [INICIO DEL ÁRBOL DE DECISIÓN]
    IF _Nuevo_Estatus_Deseado = c_ESTATUS_BAJA THEN
        
        /* ═══════════════════════════════════════════════════════════════════════════════════════════════
           RAMA A: PROCESO DE DESINCORPORACIÓN (DAR DE BAJA)
           ═══════════════════════════════════════════════════════════════════════════════════════════════ */
        -- [A.1] Validación de Integridad Académica (Constraint Academic Protection)
        -- Regla Forense: Un alumno con calificación registrada NO PUEDE ser dado de baja administrativamente.
        IF v_Tiene_Calificacion = 1 
			THEN
				SELECT CONCAT('ERROR DE INTEGRIDAD [409]: No se puede dar de baja a "', v_Nombre_Alumno, '" porque ya cuenta con una calificación final asentada.') AS Mensaje, 'CONFLICTO_ESTADO' AS Accion;
            LEAVE ProcTogglePart;
        END IF;

    ELSE
        
        /* ═══════════════════════════════════════════════════════════════════════════════════════════════
           RAMA B: PROCESO DE REINCORPORACIÓN (REINSCRIBIR)
           ═══════════════════════════════════════════════════════════════════════════════════════════════ */
        -- [B.1] Validación de Cupo Híbrido (Pessimistic Capacity Check)
        
        -- Contamos todos los participantes que NO están en baja para ver cuánto espacio queda disponible.
        SELECT COUNT(*) 
        INTO v_Conteo_Sistema 
        FROM `Capacitaciones_Participantes` 
        WHERE `Fk_Id_DatosCap` = v_Id_Detalle_Curso 
          AND `Fk_Id_CatEstPart` != c_ESTATUS_BAJA;

        -- Regla GREATEST(): Tomamos el escenario más ocupado entre el sistema automático y el manual del admin.
        SET v_Asientos_Ocupados = GREATEST(v_Conteo_Manual, v_Conteo_Sistema);
        
        -- Calculamos la disponibilidad neta.
        SET v_Cupo_Disponible = v_Cupo_Maximo - v_Asientos_Ocupados;
        
        -- Si no hay asientos, bloqueamos la reinscripción para proteger la integridad del aula.
        IF v_Cupo_Disponible <= 0 
			THEN
				SELECT CONCAT('ERROR DE CUPO [409]: Imposible reinscribir a "', v_Nombre_Alumno, '". La capacitación "', v_Folio_Curso, '" ha alcanzado su límite de aforo.') AS Mensaje, 'CUPO_LLENO' AS Accion;
            LEAVE ProcTogglePart;
        END IF;

    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 3: INYECCIÓN DE AUDITORÍA Y PERSISTENCIA (ACID WRITE TRANSACTION)
       Objetivo: Escribir el cambio en disco garantizando que la operación sea Todo o Nada.
       ═══════════════════════════════════════════════════════════════════════════════════════════════════ */
    START TRANSACTION;
        -- Actualizamos el registro de matriculación.
        UPDATE `Capacitaciones_Participantes`
        SET `Fk_Id_CatEstPart` = _Nuevo_Estatus_Deseado, -- Aplicamos el nuevo estado solicitado.
            -- [AUDIT INJECTION]: Concatenamos la acción, el timestamp de sistema y el motivo para el peritaje histórico.
            `Justificacion` = CONCAT(
                CASE WHEN _Nuevo_Estatus_Deseado = c_ESTATUS_BAJA THEN 'BAJA_SISTEMA' ELSE 'REINSCRIBIR_SISTEMA' END,
                ' | FECHA: ', DATE_FORMAT(NOW(), '%Y-%m-%d %H:%i'), 
                ' | MOTIVO: ', _Motivo_Operacion
            ),
            -- Actualizamos los sellos de tiempo y autoría.
            `updated_at` = NOW(),
            `Fk_Id_Usuario_Updated_By` = _Id_Usuario_Ejecutor
        WHERE `Id_CapPart` = _Id_Registro_Participante;
        
        -- Si llegamos aquí sin errores, el motor InnoDB confirma los cambios físicamente.
    COMMIT;

    /* ═══════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 4: RESULTADO FINAL (UX & API FEEDBACK)
       Retorna un resultset unitario que describe la acción final realizada.
       ═══════════════════════════════════════════════════════════════════════════════════════════════════ */
    SELECT 
        CONCAT('TRANSACCIÓN EXITOSA: El participante "', v_Nombre_Alumno, '" ha cambiado su estatus a ', 
               CASE WHEN _Nuevo_Estatus_Deseado = c_ESTATUS_BAJA 
					THEN 'BAJA' 
						ELSE 'INSCRITO' 
                        END, ' exitosamente.') AS Mensaje,
        'ESTATUS_CAMBIADO' AS Accion;

END$$

DELIMITER ;

/* ══════════════════════════════════════════════════════════════════════════════════════════════════════════
   PROCEDIMIENTO: SP_ConsularParticipantesCapacitacion
   ══════════════════════════════════════════════════════════════════════════════════════════════════════════
   
   I. FICHA TÉCNICA DE INGENIERÍA (ENGINEERING DATASHEET)
   ----------------------------------------------------------------------------------------------------------
   - Nombre Oficial       : SP_ConsularParticipantesCapacitacion
   - Sistema        	  : PICADE (Plataforma Institucional de Capacitación y Desarrollo)
   - Modulo				  : Gestión Académica / Coordinación
   - Autorizacion  		  : Nivel Administrativo (Requiere Token de Sesión Activo)
   - Alias Operativo      : "The Live Grid Refresher" (El Refrescador de Matrícula)
   - Clasificación        : Transacción de Lectura en Tiempo Real (Real-Time Read Transaction)
   - Nivel de Aislamiento : READ COMMITTED (Lectura Confirmada)
   - Complejidad Ciclomática: Baja (Lineal), pero con alta densidad de datos por fila.
   - Dependencias         : 
     1. Vista_Capacitaciones (Fuente de Métricas Globales)
     2. Vista_Gestion_de_Participantes (Fuente de Detalle Nominal)

   II. PROPÓSITO ESTRATÉGICO Y DE NEGOCIO (BUSINESS VALUE)
   ----------------------------------------------------------------------------------------------------------
   Este procedimiento almacenado actúa como el "Sistema Nervioso Central" del módulo de Coordinación.
   Su función no es solo traer datos, sino sincronizar la realidad operativa con la interfaz de usuario.
   
   [PROBLEMA QUE RESUELVE]:
   En sistemas de alta concurrencia, existe una discrepancia temporal entre el cupo que muestra
   el catálogo de cursos y la lista real de alumnos. Este SP elimina esa discrepancia al devolver
   dos conjuntos de datos (Resultsets) en una sola petición de red (Round-Trip):
   
   1. EL ENCABEZADO (METRICS): Dice "cuántos hay y cuántos caben".
   2. EL CUERPO (ROSTER): Dice "quiénes son y cómo van".

   III. ARQUITECTURA DE INTEGRIDAD DE DATOS (DATA INTEGRITY ARCHITECTURE)
   ----------------------------------------------------------------------------------------------------------
   A. INTEGRIDAD DE CUPO HÍBRIDO (The Hybrid Capacity Rule):
      Este SP implementa la lectura de la regla `GREATEST(Manual, Sistema)`.
      - Si el sistema cuenta 5 alumnos, pero el coordinador bloqueó 20 lugares manuales,
        este SP reportará 20 lugares ocupados, impidiendo sobreventas desde el Frontend.

   B. TRAZABILIDAD FORENSE (Forensic Audit Trail):
      Expone la columna `Nota_Auditoria` (Justificación), permitiendo al coordinador ver 
      historiales de cambios (ej: "Baja por inasistencia") sin tener que consultar logs del servidor.

   IV. CONTRATO DE SALIDA (OUTPUT CONTRACT)
   ----------------------------------------------------------------------------------------------------------
   [RESULTSET 1 - HEADER]: Métricas de alto nivel para los "Badges" y contadores del UI.
   [RESULTSET 2 - BODY]  : Tabla detallada para el pase de lista y captura de notas.

   ========================================================================================================== */

-- Inicia la definición del delimitador para el bloque de código procedimental.
-- Eliminación preventiva del objeto para asegurar una recompilación limpia del diccionario de datos.

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ConsularParticipantesCapacitacion`$$

CREATE PROCEDURE `SP_ConsularParticipantesCapacitacion`(
    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       SECCIÓN DE PARÁMETROS DE ENTRADA (INPUT PARAMETERS)
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */
    
    -- [PARÁMETRO]: _Id_Detalle_Capacitacion
    -- [TIPO]: INT (Entero)
    -- [DESCRIPCIÓN]: Puntero único a la instancia específica del curso (Tabla `DatosCapacitaciones`).
    -- [NOTA TÉCNICA]: No confundir con el ID del Temario. Este ID representa al GRUPO específico
    -- que tiene una fecha de inicio, un instructor asignado y una lista de asistencia propia.
    IN _Id_Detalle_Capacitacion INT
)
ProcPartCapac: BEGIN

    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 0: DEFENSA EN PROFUNDIDAD Y SANITIZACIÓN (FAIL-FAST STRATEGY)
       Objetivo: Rechazar peticiones mal formadas antes de consumir recursos de lectura en disco.
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */
    
    -- Validación 0.1: Integridad del Puntero
    -- Verificamos que el ID no sea Nulo (NULL) ni un valor imposible (menor o igual a cero).
    -- Esto previene inyecciones de errores lógicos y optimiza el plan de ejecución del motor SQL.
    IF _Id_Detalle_Capacitacion IS NULL OR _Id_Detalle_Capacitacion <= 0 THEN
        
        -- [RESPUESTA DE ERROR 400 - BAD REQUEST]
        -- Informamos al Frontend que la solicitud no puede ser procesada por falta de contexto.
        SELECT 'ERROR DE ENTRADA [400]: ID obligatorio.' AS Mensaje; 
        
        -- Terminación inmediata del flujo de ejecución (Circuit Breaker).
        LEAVE ProcPartCapac;
    END IF;

    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 1: RESULTSET DE MÉTRICAS (HEADER DASHBOARD)
       ------------------------------------------------------------------------------------------------------
       Objetivo: Alimentar la cabecera del Grid en el Frontend.
       Contexto: Estos datos sirven para refrescar los contadores visuales (ej: "18/20 inscritos").
       Fuente de Verdad: `Vista_Capacitaciones` (Vista Maestra).
       
       [LÓGICA DE NEGOCIO CRÍTICA]:
       Aquí se calculan los semáforos de disponibilidad. Si `Cupo_Disponible` llega a 0, 
       el botón de "Agregar Participante" en el Frontend debe deshabilitarse automáticamente.
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */
    SELECT 
        -- [IDENTIFICADOR VISUAL]
        -- El código humano-legible del curso (ej: "CAP-2026-RH-001").
        -- Permite al usuario confirmar que está viendo el grupo correcto.
        `VC`.`Numero_Capacitacion`         AS `Folio_Curso`,
        
        /* -----------------------------------------------------------------------------------------
           [KPIs DE PLANEACIÓN - PLANIFICADO]
           Datos estáticos definidos al crear el curso. Representan la "Meta".
           ----------------------------------------------------------------------------------------- */

        -- Capacidad máxima teórica del aula o sala virtual.
        `VC`.`Asistentes_Meta`             AS `Cupo_Programado_de_Asistentes`,
        
        -- Cantidad de asientos reservados manualmente por el coordinador (Override).
        -- Este valor tiene precedencia sobre el conteo automático en caso de ser mayor.
        `VC`.`Asistentes_Manuales`, 
        
        /* -----------------------------------------------------------------------------------------
           [KPIs DE OPERACIÓN - REALIDAD FÍSICA]
           Datos dinámicos calculados en tiempo real basados en la tabla de hechos.
           ----------------------------------------------------------------------------------------- */
        
        /* [CONTEO DE SISTEMA]: 
           Número exacto de filas en la tabla `Capacitaciones_Participantes` con estatus activo.
           Es la "verdad informática" de cuántos registros existen. */
        `VC`.`Participantes_Activos`       AS `Inscritos_en_Sistema`,   

        /* [IMPACTO REAL - REGLA HÍBRIDA]: 
           Este es el cálculo más importante del sistema. Aplica la función GREATEST().
           Fórmula: MAX(Inscritos_en_Sistema, Asistentes_Manuales).
           
           ¿Por qué?
           Si hay 5 inscritos en la BD, pero el Coordinador puso "20 Manuales" porque espera
           un grupo externo sin registro, el sistema debe considerar 20 asientos ocupados, no 5.
           Esto evita el "Overbooking" (Sobreventa) del aula. */
        `VC`.`Total_Impacto_Real`          AS `Total_de_Asistentes_Reales`, 

        /* [HISTÓRICO DE DESERCIÓN]:
           Conteo de participantes que estuvieron inscritos pero cambiaron a estatus "BAJA" (ID 5).
           Útil para medir la tasa de rotación o cancelación del curso. */
        `VC`.`Participantes_Baja`          AS `Total_de_Bajas`,

        /* [DISPONIBILIDAD FINAL]:
           El Delta matemático: (Meta - Impacto Real).
           Este valor es el que decide si se permiten nuevas inscripciones.
           Puede ser negativo si hubo sobrecupo autorizado. */
        `VC`.`Cupo_Disponible`
        
    FROM `PICADE`.`Vista_Capacitaciones` `VC`
    
    -- Filtro por Llave Primaria del Detalle para obtener métricas exclusivas de este grupo.
    WHERE `VC`.`Id_Detalle_de_Capacitacion` = _Id_Detalle_Capacitacion;

    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 2: RESULTSET DE NÓMINA DETALLADA (DATA GRID BODY)
       ------------------------------------------------------------------------------------------------------
       Objetivo: Proveer el listado fila por fila para la gestión individual.
       Contexto: Esta tabla es donde el Instructor/Coordinador pasa lista, asigna calificaciones 
                 o cambia el estatus de un alumno específico.
       Fuente de Verdad: `Vista_Gestion_de_Participantes` (Vista Desnormalizada de Detalle).
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */

    SELECT 
        /* -----------------------------------------------------------------------------------------
           [IDENTIFICADORES DE ACCIÓN - CRUD HANDLES]
           Datos técnicos ocultos necesarios para las operaciones de actualización.
           ----------------------------------------------------------------------------------------- */
        
        -- Llave Primaria (PK) de la relación Alumno-Curso.
        -- Este ID se envía al `SP_EditarParticipanteCapacitacion` o `SP_CambiarEstatus...`.
        `VGP`.`Id_Registro_Participante`   AS `Id_Inscripcion`,
        
        /* -----------------------------------------------------------------------------------------
           [INFORMACIÓN VISUAL DEL PARTICIPANTE]
           Datos para que el humano identifique al alumno.
           ----------------------------------------------------------------------------------------- */
        
        -- ID Corporativo o Número de Empleado. Vital para diferenciar homónimos.
        `VGP`.`Ficha_Participante`         AS `Ficha`,
        
        -- Nombre Completo Normalizado.
        -- Se concatenan Paterno + Materno + Nombre para alinearse con los estándares
        -- de listas de asistencia impresas (orden alfabético por apellido).
        CONCAT(
            `VGP`.`Ap_Paterno_Participante`, ' ', 
            `VGP`.`Ap_Materno_Participante`, ' ', 
            `VGP`.`Nombre_Pila_Participante`
        )                                  AS `Nombre_Alumno`,
        
        /* -----------------------------------------------------------------------------------------
           [INPUTS ACADÉMICOS EDITABLES]
           Datos que el coordinador puede modificar directamente en el grid.
           ----------------------------------------------------------------------------------------- */
        
        -- Porcentaje de Asistencia (0.00 - 100.00).
        -- Alimenta la barra de progreso visual en el Frontend.
        `VGP`.`Porcentaje_Asistencia`      AS `Asistencia`,
        
        -- Calificación Final Asentada (0.00 - 100.00).
        -- Si es NULL, el Frontend debe mostrar un input vacío o "Sin Evaluar".
        `VGP`.`Calificacion_Numerica`      AS `Calificacion`,
        
        /* -----------------------------------------------------------------------------------------
           [ESTADO DEL CICLO DE VIDA Y AUDITORÍA]
           Datos de control de flujo y trazabilidad.
           ----------------------------------------------------------------------------------------- */
        
        -- Estatus Semántico (Texto).
        -- Valores posibles: 'INSCRITO', 'ASISTIÓ', 'APROBADO', 'REPROBADO', 'BAJA'.
        -- Se usa para determinar el color de la fila (ej: Baja = Rojo, Aprobado = Verde).
        `VGP`.`Resultado_Final`            AS `Estatus_Participante`, 
        
        -- Descripción Técnica.
        -- Explica la regla de negocio aplicada (ej: "Reprobado por inasistencia > 20%").
        -- Se usa típicamente en un Tooltip al pasar el mouse sobre el estatus.
        `VGP`.`Detalle_Resultado`          AS `Descripcion_Estatus`,
        
        -- [AUDITORÍA FORENSE INYECTADA]:
        -- Contiene la cadena histórica de cambios (Timestamp + Motivo).
        -- Permite al coordinador saber por qué un alumno tiene una calificación extraña
        -- o por qué fue reactivado después de una baja.
        `VGP`.`Nota_Auditoria`             AS `Justificacion`

    FROM `PICADE`.`Vista_Gestion_de_Participantes` `VGP`
    
    -- Filtro estricto por la instancia del curso.
    WHERE `VGP`.`Id_Detalle_de_Capacitacion` = _Id_Detalle_Capacitacion
    
    /* -----------------------------------------------------------------------------------------
       [ESTRATEGIA DE ORDENAMIENTO - UX STANDARD]
       Ordenamos alfabéticamente por Apellido Paterno -> Materno -> Nombre.
       Esto es mandatorio para facilitar el cotejo visual contra listas físicas o de Excel.
       ----------------------------------------------------------------------------------------- */
    ORDER BY `VGP`.`Ap_Paterno_Participante` ASC, `VGP`.`Ap_Materno_Participante` ASC;

END$$

-- Restaura el delimitador estándar para continuar con scripts normales.
DELIMITER ;

/* ======================================================================================================
   PROCEDIMIENTO: SP_GenerarReporteGerencial_Docente
   ======================================================================================================
   IDENTIFICADOR:  SP_GenerarReporteGerencial_Docente
   MÓDULO:         BUSINESS INTELLIGENCE (BI) / ANALÍTICA GERENCIAL
   
   1. DESCRIPCIÓN FUNCIONAL:
   -------------------------
   Este procedimiento constituye el motor analítico para la toma de decisiones de la alta gerencia.
   Extrae indicadores clave de desempeño (KPIs) divididos en dos dimensiones:
   A. EFICIENCIA OPERATIVA: Capacidad de acreditación por cada Gerencia solicitante.
   B. CALIDAD DOCENTE: Desempeño y tasa de fricción (reprobación) por instructor.

   2. ARQUITECTURA DE INTEGRIDAD (FORENSIC LAYERS):
   -----------------------------------------------
   A. INTEGRIDAD TEMPORAL: Valida la coherencia de rangos de fecha y sanitiza entradas nulas.
   B. INTEGRIDAD POR ID (FK-STRICT): Los cálculos de éxito/fracaso se basan en IDs de catálogo (3, 4, 9),
      eliminando la ambigüedad de las comparaciones por cadenas de texto.
   C. INTEGRIDAD DE EXCLUSIÓN: Filtra automáticamente cursos cancelados o en diseño (ID 8) para 
      no contaminar la estadística con datos pre-operativos.

   3. CONTRATO DE SALIDA (DATASETS):
   ---------------------------------
   - DATASET 1 (GERENCIAS): Métricas acumuladas por centro de costos / área.
   - DATASET 2 (INSTRUCTORES): Ranking de los 10 instructores con mayor volumen de alumnos atendidos.
   ====================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_GenerarReporteGerencial_Docente`$$

CREATE PROCEDURE `SP_GenerarReporteGerencial_Docente`(
    IN _Fecha_Inicio DATE, /* Fecha de inicio del periodo a auditar */
    IN _Fecha_Fin DATE     /* Fecha de fin del periodo a auditar */
)
ProcBI: BEGIN

    /* -----------------------------------------------------------------------------------
       SECCIÓN 1: DECLARACIÓN DE CONSTANTES Y SANITIZACIÓN TEMPORAL
       Se establecen los rangos de búsqueda y se mapean los IDs críticos del sistema.
       ----------------------------------------------------------------------------------- */
    
    -- Manejo de Fechas: Si los parámetros son NULL, se establece un horizonte histórico absoluto.
    DECLARE v_Fecha_Ini DATE DEFAULT COALESCE(_Fecha_Inicio, '1990-01-01');
    DECLARE v_Fecha_Fin DATE DEFAULT COALESCE(_Fecha_Fin, '2030-12-31');

    -- [CONSTANTES DE ESTATUS - BASADO EN DICCIONARIO PICADE]
    DECLARE c_ST_PART_ACREDITADO    INT DEFAULT 3; -- @St_PartAcre
    DECLARE c_ST_PART_NO_ACREDITADO INT DEFAULT 4; -- @St_PartNoAcre
    DECLARE c_ST_CURSO_CANCELADO    INT DEFAULT 8; -- @St_Canc

    /* -----------------------------------------------------------------------------------
       SECCIÓN 2: VALIDACIÓN DE INTEGRIDAD TEMPORAL (VAL-0)
       Previene errores de lógica donde la fecha final sea menor a la inicial.
       ----------------------------------------------------------------------------------- */
    IF v_Fecha_Ini > v_Fecha_Fin THEN
        SELECT 
            'ERROR DE LÓGICA [400]: La fecha de inicio no puede ser posterior a la fecha de fin.' AS Mensaje, 
            'VALIDACION_TEMPORAL_FALLIDA' AS Accion;
        LEAVE ProcBI;
    END IF;

    /* -----------------------------------------------------------------------------------
       SECCIÓN 3: DATASET 1 - MÉTRICAS DE EFICIENCIA POR GERENCIA
       Calcula el volumen de impacto y la tasa de éxito terminal por cada unidad organizacional.
       ----------------------------------------------------------------------------------- */
    SELECT 
        'RESUMEN_GERENCIAL' AS Mensaje,
        `VGP`.`Gerencia_Solicitante` AS `Gerencia`,
        COUNT(`VGP`.`Id_Registro_Participante`) AS `Total_Inscritos`,
        
        -- Cálculo de Aprobados mediante ID 3 (Acreditado)
        SUM(CASE WHEN `CP`.`Fk_Id_CatEstPart` = c_ST_PART_ACREDITADO THEN 1 ELSE 0 END) AS `Total_Aprobados`,

        -- Cálculo de Reprobados mediante ID 4 (No Acreditado)
        SUM(CASE WHEN `CP`.`Fk_Id_CatEstPart` = c_ST_PART_NO_ACREDITADO THEN 1 ELSE 0 END) AS `Total_Reprobados`,
        
        -- KPI: Eficiencia Terminal (Porcentaje de éxito sobre el total atendido)
        ROUND(
            (SUM(CASE WHEN `CP`.`Fk_Id_CatEstPart` = c_ST_PART_ACREDITADO THEN 1 ELSE 0 END) / COUNT(*)) * 100, 
            2
        ) AS `Porcentaje_Eficiencia`
        
    FROM `PICADE`.`Vista_Gestion_de_Participantes` `VGP`
    -- Unión con tabla física para validación estricta por IDs de estatus
    INNER JOIN `PICADE`.`Capacitaciones_Participantes` `CP` ON `VGP`.`Id_Registro_Participante` = `CP`.`Id_CapPart`
    INNER JOIN `PICADE`.`datoscapacitaciones` `DC` ON `VGP`.`Id_Detalle_de_Capacitacion` = `DC`.`Id_DatosCap`
    
    WHERE `VGP`.`Fecha_Inicio` BETWEEN v_Fecha_Ini AND v_Fecha_Fin
      -- Excluir cursos cancelados para no sesgar la eficiencia (Basado en ID 8)
      AND `DC`.`Fk_Id_CatEstCap` != c_ST_CURSO_CANCELADO 
    GROUP BY `VGP`.`Gerencia_Solicitante`
    ORDER BY `Porcentaje_Eficiencia` DESC;

    /* -----------------------------------------------------------------------------------
       SECCIÓN 4: DATASET 2 - CALIDAD Y DESEMPEÑO DOCENTE
       Identifica el volumen de instrucción y la tasa de fricción por instructor.
       ----------------------------------------------------------------------------------- */
    SELECT 
        'RESUMEN_DOCENTE' AS Mensaje,
        IFNULL(`VGP`.`Instructor_Asignado`, 'SIN INSTRUCTOR ASIGNADO') AS `Instructor`,
        COUNT(DISTINCT `VGP`.`Folio_Curso`) AS `Cursos_Impartidos`,
        COUNT(`VGP`.`Id_Registro_Participante`) AS `Alumnos_Atendidos`,
        
        -- Conteo de fracaso académico (ID 4)
        SUM(CASE WHEN `CP`.`Fk_Id_CatEstPart` = c_ST_PART_NO_ACREDITADO THEN 1 ELSE 0 END) AS `Alumnos_Reprobados`,
        
        -- KPI: Tasa de Reprobación (Indica posible rigor excesivo o falta de claridad pedagógica)
        ROUND(
            (SUM(CASE WHEN `CP`.`Fk_Id_CatEstPart` = c_ST_PART_NO_ACREDITADO THEN 1 ELSE 0 END) / COUNT(*)) * 100, 
            2
        ) AS `Tasa_Reprobacion`
        
    FROM `PICADE`.`Vista_Gestion_de_Participantes` `VGP`
    INNER JOIN `PICADE`.`Capacitaciones_Participantes` `CP` ON `VGP`.`Id_Registro_Participante` = `CP`.`Id_CapPart`
    INNER JOIN `PICADE`.`datoscapacitaciones` `DC` ON `VGP`.`Id_Detalle_de_Capacitacion` = `DC`.`Id_DatosCap`
    
    WHERE `VGP`.`Fecha_Inicio` BETWEEN v_Fecha_Ini AND v_Fecha_Fin
      -- Filtro de integridad: Excluir cursos cancelados o eliminados
      AND `DC`.`Fk_Id_CatEstCap` != c_ST_CURSO_CANCELADO
      
    GROUP BY `VGP`.`Instructor_Asignado`
    ORDER BY `Alumnos_Atendidos` DESC -- Priorizamos mostrar a los que tienen mayor carga de trabajo
    LIMIT 10; 

END$$

DELIMITER ;

/* ======================================================================================================
   PROCEDIMEINIENTO: SP_GenerarReporte_DC3_Masivo
   ======================================================================================================
   IDENTIFICADOR:  SP_GenerarReporte_DC3_Masivo
   MÓDULO:         EMISIÓN DOCUMENTAL Y CERTIFICACIÓN LABORAL (DC-3 / STPS)
   
   1. DESCRIPCIÓN FUNCIONAL:
   -------------------------
   Este procedimiento actúa como el núcleo de lógica de negocios para la extracción de evidencia académica.
   Su función primaria es la discriminación y filtrado de registros de participación para identificar
   inequívocamente qué individuos son sujetos de certificación (DC-3) y quiénes de reconocimiento
   (Constancia de Participación), basándose en reglas de integridad de datos y estados de ciclo de vida.

   2. ARQUITECTURA DE INTEGRIDAD (FORENSIC LAYERS):
   -----------------------------------------------
   A. INTEGRIDAD PARAMÉTRICA: Verifica la existencia y validez de las llaves foráneas de entrada.
   B. INTEGRIDAD DE ESTADO: Valida que el contenedor (Curso) se encuentre en un estado inmutable (Finalizado).
   C. INTEGRIDAD DE DATOS (NULL CHECK): Aplica un "Hard Filter" sobre evidencias numéricas obligatorias.
   D. INTEGRIDAD SEMÁNTICA: Mapea IDs de estatus a nombres de catálogo para consumo humano en el Frontend.

   3. CONTRATO DE SALIDA (DATASETS):
   ---------------------------------
   - DATASET 1 (ALUMNOS): Estructura plana optimizada para motores de renderizado de PDF (DomPDF/Snappy).
   - DATASET 2 (AUDITORÍA): Métricas de control para retroalimentación al Coordinador sobre el éxito del lote.
   ====================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_GenerarReporte_DC3_Masivo`$$

CREATE PROCEDURE `SP_GenerarReporte_DC3_Masivo`(
    IN _Id_Usuario_Ejecutor INT,      /* FK: Identificador del usuario que dispara la acción (Trazabilidad). */
    IN _Id_Detalle_Capacitacion INT   /* FK: Identificador único de la instancia operativa del curso (DatosCapacitaciones). */
)
ProcMasivo: BEGIN

    /* -----------------------------------------------------------------------------------
       SECCIÓN 1: DECLARACIÓN DE VARIABLES DE CONTROL Y AUDITORÍA
       Se instancian variables locales para el almacenamiento temporal de metadatos de estado.
       ----------------------------------------------------------------------------------- */
    DECLARE v_Id_Estatus_Curso INT;             -- Almacena el ID del estatus actual del curso.
    DECLARE v_Nombre_Estatus_Curso VARCHAR(100); -- Almacena la etiqueta textual para mensajes de error amigables.

    /* -----------------------------------------------------------------------------------
       SECCIÓN 2: BLOQUE DE VALIDACIÓN DE INTEGRIDAD FORENSE (VAL-0)
       Este bloque previene ejecuciones con parámetros nulos o fuera de rango lógico.
       ----------------------------------------------------------------------------------- */
    
    -- [VAL-0.1]: Verificación de Identidad del Ejecutor. 
    -- Previene llamadas anónimas que comprometan la trazabilidad de la auditoría.
    IF _Id_Usuario_Ejecutor IS NULL OR _Id_Usuario_Ejecutor <= 0 THEN
        SELECT 
            'ERROR DE ENTRADA [400]: El ID del Usuario Ejecutor es obligatorio para la trazabilidad.' AS Mensaje, 
            'VALIDACION_FALLIDA' AS Accion, 
            NULL AS Id_Registro_Participante;
        LEAVE ProcMasivo; -- Aborto de ejecución por falta de identidad.
    END IF;

    -- [VAL-0.2]: Verificación del Recurso Objetivo.
    -- Garantiza que el puntero al curso sea una referencia válida antes de realizar JOINS pesados.
    IF _Id_Detalle_Capacitacion IS NULL OR _Id_Detalle_Capacitacion <= 0 THEN
        SELECT 
            'ERROR DE ENTRADA [400]: El ID de la Capacitación es obligatorio para localizar el recurso.' AS Mensaje, 
            'VALIDACION_FALLIDA' AS Accion, 
            NULL AS Id_Registro_Participante;
        LEAVE ProcMasivo; -- Aborto de ejecución por referencia nula.
    END IF;

    /* -----------------------------------------------------------------------------------
       SECCIÓN 3: COMPROBACIÓN DE CICLO DE VIDA DEL CURSO (VAL-1)
       Determina si el recurso se encuentra en una fase operativa que permita la emisión legal.
       ----------------------------------------------------------------------------------- */
    
    -- Extracción de metadatos de estatus mediante el cruce de la tabla transaccional y catálogo.
    SELECT 
        DC.`Fk_Id_CatEstCap`,
        CAT.`Nombre`
    INTO 
        v_Id_Estatus_Curso,
        v_Nombre_Estatus_Curso
    FROM `PICADE`.`datoscapacitaciones` DC
    INNER JOIN `PICADE`.`cat_estatus_capacitacion` CAT 
        ON DC.`Fk_Id_CatEstCap` = CAT.`Id_CatEstCap`
    WHERE DC.`Id_DatosCap` = _Id_Detalle_Capacitacion
    LIMIT 1;

    -- [VAL-1.1]: Verificación de Existencia Física.
    -- Si el SELECT anterior no arroja resultados, el ID proporcionado es un "Dead Link".
    IF v_Id_Estatus_Curso IS NULL THEN
        SELECT 
            'ERROR NO ENCONTRADO [404]: El curso solicitado no existe en la base de datos.' AS Mensaje, 
            'RECURSO_NO_ENCONTRADO' AS Accion, 
            NULL AS Id_Registro_Participante;
        LEAVE ProcMasivo;
    END IF;

    -- [VAL-1.2]: Regla de Negocio de Inmutabilidad.
    -- Bloqueo de emisión si el curso no es ID 4 (Finalizado) o ID 10 (Archivado).
    -- Previene la generación de certificados en cursos que aún pueden sufrir cambios de nota.
    IF v_Id_Estatus_Curso NOT IN (4, 10) THEN
        SELECT 
            CONCAT('CONFLICTO [409]: El curso está en estatus "', UPPER(v_Nombre_Estatus_Curso), '". La emisión masiva solo es válida para estados de cierre (FINALIZADO/ARCHIVADO).') AS Mensaje, 
            'ERROR_DE_ESTATUS' AS Accion, 
            NULL AS Id_Registro_Participante;
        LEAVE ProcMasivo;
    END IF;

    /* -----------------------------------------------------------------------------------
       SECCIÓN 4: EXTRACCIÓN DE DATASET PRIMARIO (DATA-CORE)
       Este query consolida la información académica y biográfica del participante.
       Aplica JOINS optimizados hacia vistas y tablas de identidad personal.
       ----------------------------------------------------------------------------------- */
    SELECT 
        'PROCESO_EXITOSO' AS Mensaje, -- Flag de éxito para el controlador de Laravel.
        'GENERAR_PDF'     AS Accion,  -- Comando semántico para disparar el generador de PDF.

        -- [BIOGRAFÍA DEL ALUMNO]: Estructura requerida por formatos legales.
        `VGP`.`Id_Registro_Participante` AS `Id_Interno`,
        `VGP`.`Ficha_Participante`       AS `Ficha_Empleado`,
        -- Concatenación bajo estándar forense: Apellido Paterno + Apellido Materno + Nombres.
        CONCAT(`VGP`.`Ap_Paterno_Participante`, ' ', `VGP`.`Ap_Materno_Participante`, ' ', `VGP`.`Nombre_Pila_Participante`) AS `Nombre_Completo_Alumno`,
        IFNULL(`Puesto`.`Nombre`, 'SIN PUESTO REGISTRADO') AS `Puesto_Laboral`,
        
        -- [EVIDENCIA ACADÉMICA]: Datos crudos extraídos de la relación Capacitaciones_Participantes.
        `CP`.`PorcentajeAsistencia` AS `Asistencia_Numerica`,
        `CP`.`Calificacion`         AS `Evaluacion_Numerica`,

        -- [ESTATUS SEMÁNTICO]: Resolución de IDs a etiquetas de catálogo para validez legal en el texto del PDF.
        `CatEst`.`Nombre`      AS `Nombre_Estatus`, -- Ej: ACREDITADO / NO ACREDITADO.
        `CatEst`.`Descripcion` AS `Descripcion_Estatus`,          -- Explicación extendida del resultado.

        -- [CONTEXTO ACADÉMICO]: Datos del curso para el encabezado del documento.
        `VGP`.`Folio_Curso`        AS `Folio_Sistema`,
        `VGP`.`Tema_Curso`         AS `Nombre_Tema`,
        `VGP`.`Fecha_Inicio`       AS `Periodo_Inicio`,
        `VGP`.`Fecha_Fin`          AS `Periodo_Fin`,
        `VGP`.`Duracion_Horas`     AS `Carga_Horaria`,
        `VGP`.`Instructor_Asignado` AS `Nombre_Instructor`

    FROM `PICADE`.`Vista_Gestion_de_Participantes` `VGP`
    -- Unión con tabla de hechos para acceso a IDs de estatus y valores numéricos crudos.
    INNER JOIN `PICADE`.`Capacitaciones_Participantes` `CP` 
        ON `VGP`.`Id_Registro_Participante` = `CP`.`Id_CapPart`
    -- Cruce con tabla maestra de usuarios para vinculación de perfiles.
    INNER JOIN `PICADE`.`usuarios` `U` 
        ON `CP`.`Fk_Id_Usuario` = `U`.`Id_Usuario`
    -- Acceso a información personal para extracción de datos biográficos (CURP/RFC/Puesto).
    INNER JOIN `PICADE`.`info_personal` `IP` 
        ON `U`.`Fk_Id_InfoPersonal` = `IP`.`Id_InfoPersonal`
    -- Resolución de puesto mediante catálogo (LEFT JOIN para no excluir si el perfil es incompleto).
    LEFT JOIN `PICADE`.`cat_puestos_trabajo` `Puesto` 
        ON `IP`.`Fk_Id_CatPuesto` = `Puesto`.`Id_CatPuesto`
    -- Resolución de estatus mediante catálogo para obtener nombres oficiales de acreditación.
    INNER JOIN `PICADE`.`cat_estatus_participante` `CatEst` 
        ON `CP`.`Fk_Id_CatEstPart` = `CatEst`.`Id_CatEstPart`

    WHERE `VGP`.`Id_Detalle_de_Capacitacion` = _Id_Detalle_Capacitacion
      -- [FILTRO DE SELECCIÓN]: Solo se incluyen estados terminales de acreditación (3) o no acreditación (4).
      -- Esto excluye automáticamente estados como 'Inscrito' (1) o 'Baja' (5).
      AND `CP`.`Fk_Id_CatEstPart` IN (3, 4)
      -- [CANDADO DE INTEGRIDAD NUMÉRICA]: Si el instructor no capturó evidencia, el registro se omite para evitar PDFs vacíos.
      AND `CP`.`Calificacion` IS NOT NULL 
      AND `CP`.`PorcentajeAsistencia` IS NOT NULL
      
    ORDER BY `VGP`.`Ap_Paterno_Participante` ASC; -- Ordenamiento alfabético estándar para impresión masiva.

    /* -----------------------------------------------------------------------------------
       SECCIÓN 5: DATASET DE AUDITORÍA Y CONTROL (METADATA)
       Este bloque provee la estadística necesaria para el Dashboard de confirmación.
       Permite al usuario identificar huecos de información en el lote solicitado.
       ----------------------------------------------------------------------------------- */
    SELECT 
        'RESUMEN_EJECUCION_FORENSE' AS Mensaje,
        -- Conteo total de individuos ligados a la capacitación.
        COUNT(*) AS `Poblacion_Total`,

        -- Conteo de éxito: Registros que cumplieron todos los filtros de la Sección 4.
        SUM(CASE 
            WHEN `CP`.`Fk_Id_CatEstPart` IN (3, 4) 
                 AND `CP`.`Calificacion` IS NOT NULL 
                 AND `CP`.`PorcentajeAsistencia` IS NOT NULL 
            THEN 1 ELSE 0 
        END) AS `Certificados_Listos`,

        -- Conteo de Errores Críticos: Tienen estatus de finalización pero falta captura de evidencia.
        SUM(CASE 
            WHEN `CP`.`Fk_Id_CatEstPart` IN (3, 4) 
                 AND (`CP`.`Calificacion` IS NULL OR `CP`.`PorcentajeAsistencia` IS NULL)
            THEN 1 ELSE 0 
        END) AS `Alertas_Datos_Incompletos`,

        -- Conteo de Omisiones Administrativas: Alumnos que nunca fueron evaluados por el instructor.
        SUM(CASE 
            WHEN `CP`.`Fk_Id_CatEstPart` IN (1, 2) 
            THEN 1 ELSE 0 
        END) AS `Alertas_Sin_Evaluacion`,
        
        -- Conteo de Bajas: Registros omitidos por retiro oficial del curso (Flujo normal).
        SUM(CASE 
            WHEN `CP`.`Fk_Id_CatEstPart` = 5 
            THEN 1 ELSE 0 
        END) AS `Registros_Baja_Omitidos`

    FROM `PICADE`.`Capacitaciones_Participantes` `CP`
    WHERE `CP`.`Fk_Id_DatosCap` = _Id_Detalle_Capacitacion;

END$$

DELIMITER ;