USE `PICADE`;

/* ------------------------------------------------------------------------------------------------------ */
/* CREACION DE VISTAS Y PROCEDIMIENTOS DE ALMACENADO PARA LA BASE DE DATOS                                */
/* ------------------------------------------------------------------------------------------------------ */

/* ======================================================================================================
   VIEW: Vista_Capacitaciones
   ======================================================================================================
   
   1. OBJETIVO TÉCNICO Y DE NEGOCIO (BUSINESS GOAL)
   ------------------------------------------------
   Esta vista implementa el patrón de diseño "Flattened Master-Detail" (Maestro-Detalle Aplanado).
   Su función es unificar la estructura transaccional dividida del sistema:
     - Cabecera Administrativa (`Capacitaciones`): Datos inmutables como Folio y Gerencia.
     - Detalle Operativo (`DatosCapacitaciones`): Datos mutables como Fechas, Instructor y Estatus.

   [PROPÓSITO ESTRATÉGICO]:
   Actúa como la fuente de verdad única para:
   - El Grid Principal de Gestión de Cursos (Dashboard del Coordinador).
   - Generación de Reportes de Cumplimiento (Auditoría).
   - Validaciones de cruce de horarios (Detección de conflictos).
   
   Al consumir esta vista, el Frontend y los servicios de reporte se abstraen de la complejidad 
   de los 8 JOINs subyacentes, recibiendo una estructura de datos limpia y semántica.

   2. ARQUITECTURA DE INTEGRACIÓN (LAYERED ARCHITECTURE)
   -----------------------------------------------------
   Esta vista no consulta tablas crudas (Raw Tables) indiscriminadamente. Aplica una arquitectura 
   de capas consumiendo OTRAS VISTAS (`Vista_Usuarios`, `Vista_Organizacion`, etc.) cuando es posible.
   
   [BENEFICIOS DE ESTA ARQUITECTURA]:
   - Encapsulamiento: Si cambia la lógica de cómo se calcula el nombre completo de un usuario en 
     `Vista_Usuarios`, esta vista lo hereda automáticamente sin re-codificar.
   - Consistencia: Garantiza que el nombre de la Sede se vea igual en el módulo de Sedes y en el de Cursos.

   3. DICCIONARIO DE DATOS (OUTPUT CONTRACT)
   -----------------------------------------
   [Bloque 1: Identidad del Curso]
   - Id_Capacitacion:      (INT) PK de la Cabecera.
   - Numero_Capacitacion:  (VARCHAR) El Folio único (ej: 'CAP-2026-001').
   
   [Bloque 2: Contexto Administrativo]
   - Clave_Gerencia:       (VARCHAR) Quién solicitó/paga el curso.
   - Codigo_Tema:          (VARCHAR) Identificador académico.
   - Nombre_Tema:          (VARCHAR) Título del curso.
   - Tipo_Instruccion:     (VARCHAR) Naturaleza (Teórico/Práctico).
   - Duracion_Horas:       (INT) Carga horaria académica.
   
   [Bloque 3: Factor Humano (Instructor)]
   - Ficha_Instructor:     (VARCHAR) ID corporativo del instructor.
   - Nombre_Instructor:    (VARCHAR) Nombre completo concatenado (Nombre + Apellidos).
   
   [Bloque 4: Logística y Ejecución]
   - Fecha_Inicio/Fin:     (DATE) Ventana de tiempo de ejecución.
   - Sede:                 (VARCHAR) Ubicación física o virtual.
   - Modalidad:            (VARCHAR) Presencial/En Línea/Mixta.
   
   [Bloque 5: Métricas y Estado]
   - Estatus_Curso:        (VARCHAR) Estado actual del flujo (Programado, Finalizado, Cancelado).
   - Asistentes_Meta:      (INT) Cupo planeado (KPI).
   - Asistentes_Reales:    (INT) Cupo logrado (KPI).
   - Observaciones:        (TEXT) Notas de bitácora.
   - Registro_Activo:      (BOOL) Soft Delete flag del detalle operativo.
   ====================================================================================================== */

CREATE OR REPLACE 
    ALGORITHM = UNDEFINED 
    SQL SECURITY DEFINER
VIEW `PICADE`.`Vista_Capacitaciones` AS
    SELECT 
        /* -----------------------------------------------------------------------------------
           BLOQUE 1: IDENTIDAD NUCLEAR (HEADER DATA)
           Datos provenientes de la tabla padre `Capacitaciones`. Son inmutables durante
           la ejecución del curso.
           ----------------------------------------------------------------------------------- */
        `Cap`.`Id_Capacitacion`             AS `Id_Capacitacion`,
        `DatCap`.`Id_DatosCap`				AS `Id_Detalle_de_Capacitacion`,
        `Cap`.`Numero_Capacitacion`         AS `Numero_Capacitacion`, -- El Folio (Key de Negocio)

        /* -----------------------------------------------------------------------------------
           BLOQUE 2: CLASIFICACIÓN ORGANIZACIONAL Y ACADÉMICA
           Contexto de quién pide el curso y qué se va a enseñar.
           ----------------------------------------------------------------------------------- */
        `Org`.`Clave_Gerencia`              AS `Clave_Gerencia_Solicitante`,
        
        `Tem`.`Codigo_Tema`                 AS `Codigo_Tema`,
        `Tem`.`Nombre_Tema`                 AS `Nombre_Tema`,
        `Tem`.`Nombre_Tipo_Instruccion`     AS `Tipo_Instruccion`, -- Heredado de la vista de temas
        `Tem`.`Duracion_Horas`              AS `Duracion_Horas`,

        /* -----------------------------------------------------------------------------------
           BLOQUE 3: METAS DE ASISTENCIA (KPIs)
           Comparativa entre lo planeado (Cabecera) y lo real (Detalle).
           ----------------------------------------------------------------------------------- */
		/* --- BLOQUE 3: LÓGICA HÍBRIDA DE ASISTENCIA --- */
        `Cap`.`Asistentes_Programados`      AS `Asistentes_Meta`,
        `DatCap`.`AsistentesReales`         AS `Asistentes_Manuales`, -- Renombramos para claridad
        
        /* A) CONTADOR DE SISTEMA (Dinámico) */
        (SELECT COUNT(*) FROM `PICADE`.`Capacitaciones_Participantes` `CP` 
         WHERE `CP`.`Fk_Id_DatosCap` = `DatCap`.`Id_DatosCap` AND `CP`.`Fk_Id_CatEstPart` != 5
        )                                   AS `Participantes_Activos`,

        /* B) CONTADOR DE BAJAS */
        (SELECT COUNT(*) FROM `PICADE`.`Capacitaciones_Participantes` `CP` 
         WHERE `CP`.`Fk_Id_DatosCap` = `DatCap`.`Id_DatosCap` AND `CP`.`Fk_Id_CatEstPart` = 5
        )                                   AS `Participantes_Baja`,

        /* C) TOTAL IMPACTO REAL (LA REGLA DEL MÁXIMO) 🧠 
           Compara el dato manual vs el dato de sistema y se queda con el mayor.
           Esto resuelve tu problema de los "27 asistentes". */
        GREATEST(
            COALESCE(`DatCap`.`AsistentesReales`, 0), 
            (SELECT COUNT(*) FROM `PICADE`.`Capacitaciones_Participantes` `CP` 
             WHERE `CP`.`Fk_Id_DatosCap` = `DatCap`.`Id_DatosCap` AND `CP`.`Fk_Id_CatEstPart` != 5)
        )                                   AS `Total_Impacto_Real`,

        /* D) CUPO DISPONIBLE (Usando el Impacto Real para mayor precisión) */
        (
            `Cap`.`Asistentes_Programados` - 
            GREATEST(
                COALESCE(`DatCap`.`AsistentesReales`, 0), 
                (SELECT COUNT(*) FROM `PICADE`.`Capacitaciones_Participantes` `CP` 
                 WHERE `CP`.`Fk_Id_DatosCap` = `DatCap`.`Id_DatosCap` AND `CP`.`Fk_Id_CatEstPart` != 5)
            )
        )                                   AS `Cupo_Disponible`,

        /*`Cap`.`Asistentes_Programados`      AS `Asistentes_Meta`,
        `DatCap`.`AsistentesReales`         AS `Asistentes_Reales`,
        
		 [NUEVO] CÁLCULO EN TIEMPO REAL: Participantes Activos (Sin Bajas) 
        Nota: Usamos 'DatCap.Id_DatosCap' para correlacionar, no 'VC'   
		 A) ACTIVOS 
        (
			SELECT COUNT(*) FROM `PICADE`.`Capacitaciones_Participantes` `CP` 
			WHERE `CP`.`Fk_Id_DatosCap` = `DatCap`.`Id_DatosCap` 
            AND `CP`.`Fk_Id_CatEstPart` != 5 -- Excluir BAJA (Hardcoded ID 5)
        )                                   AS `Participantes_Activos`,

         B) BAJAS 
        (
			SELECT COUNT(*) 
            FROM `PICADE`.`Capacitaciones_Participantes` `CP` 
			WHERE `CP`.`Fk_Id_DatosCap` = `DatCap`.`Id_DatosCap` 
				AND `CP`.`Fk_Id_CatEstPart` = 5 -- Excluir BAJA (Hardcoded ID 5)
        )                                   AS `Participantes_Baja`,

         C) CUPO DISPONIBLE (Cálculo Matemático Puro) 
        (
            `Cap`.`Asistentes_Programados` - 
            (
            SELECT COUNT(*) 
            FROM `PICADE`.`Capacitaciones_Participantes` `CP` 
			WHERE `CP`.`Fk_Id_DatosCap` = `DatCap`.`Id_DatosCap` 
            AND `CP`.`Fk_Id_CatEstPart` != 5 -- Excluir BAJA (Hardcoded ID 5)
            )
        )                                   AS `Cupo_Disponible`,*/
        
        /* -----------------------------------------------------------------------------------
           BLOQUE 4: PERSONAL DOCENTE (INSTRUCTOR)
           Datos del instructor asignado en el detalle operativo actual.
           Se concatena el nombre para facilitar la visualización en reportes.
           ----------------------------------------------------------------------------------- */
        `Us`.`Ficha_Usuario`                AS `Ficha_Instructor`,
        `Us`.`Apellido_Paterno`             AS `Apellido_Paterno_Instructor`,
        `Us`.`Apellido_Materno`             AS `Apellido_Materno_Instructor`,
        `Us`.`Nombre`                       AS `Nombre_Instructor`,
        /* Campo calculado de conveniencia para grids */
        /*CONCAT(`Us`.`Nombre`, ' ', `Us`.`Apellido_Paterno`, ' ', `Us`.`Apellido_Materno`) AS `Nombre_Completo_Instructor`,
        CONCAT(`VC`.`Apellido_Paterno_Instructor`, ' ', `VC`.`Apellido_Materno_Instructor`, ' ', `VC`.`Nombre_Instructor`) AS `Instructor_Asignado`,*/

        /* -----------------------------------------------------------------------------------
           BLOQUE 5: LOGÍSTICA TEMPORAL Y ESPACIAL (OPERACIÓN)
           Datos críticos para el calendario y la logística.
           ----------------------------------------------------------------------------------- */
        `DatCap`.`Fecha_Inicio`             AS `Fecha_Inicio`,
        `DatCap`.`Fecha_Fin`                AS `Fecha_Fin`,
        
        `Sede`.`Codigo_Sedes`               AS `Codigo_Sede`,
        `Sede`.`Nombre_Sedes`               AS `Nombre_Sede`,
        
        `Moda`.`Codigo_Modalidad`           AS `Codigo_Modalidad`,
        `Moda`.`Nombre_Modalidad`           AS `Nombre_Modalidad`,

        /* -----------------------------------------------------------------------------------
           BLOQUE 6: CONTROL DE ESTADO Y CICLO DE VIDA
           El corazón del flujo de trabajo. Determina si el curso está vivo, muerto o finalizado.
           ----------------------------------------------------------------------------------- */
        `EstCap`.`Codigo_Estatus`           AS `Codigo_Estatus`, -- Útil para lógica de colores en UI (ej: CANC = Rojo)
        `EstCap`.`Nombre_Estatus`           AS `Estatus_Curso`,
        
        `DatCap`.`Observaciones`            AS `Observaciones`,
        
        /* Bandera de Soft Delete del DETALLE operativo. 
           Nota: La cabecera también tiene 'Activo', pero el detalle manda en la operación diaria. */
        `DatCap`.`Activo`                   AS `Estatus_del_Registro`

    FROM
        /* -----------------------------------------------------------------------------------
           ESTRATEGIA DE JOINs (INTEGRITY MAPPING)
           Se utiliza INNER JOIN para las relaciones obligatorias fuertes y LEFT JOIN 
           (aunque en tu diseño parece que todo es obligatorio, usamos INNER para consistencia 
           con tu query aprobado) para asegurar la integridad referencial.
           ----------------------------------------------------------------------------------- */
        
        /* 1. EL PADRE (Cabecera) */
        `PICADE`.`Capacitaciones` `Cap`
        
        /* 2. EL HIJO (Detalle Operativo) - Relación 1:1 en el contexto de un reporte plano */
        JOIN `PICADE`.`DatosCapacitaciones` `DatCap` 
            ON `Cap`.`Id_Capacitacion` = `DatCap`.`Fk_Id_Capacitacion`
        
        /* 3. INSTRUCTOR (Consumiendo Vista de Usuarios) */
        JOIN `PICADE`.`Vista_Usuarios` `Us` 
            ON `DatCap`.`Fk_Id_Instructor` = `Us`.`Id_Usuario`
        
        /* 4. ORGANIZACIÓN (Consumiendo Vista Organizacional) */
        JOIN `PICADE`.`Vista_Organizacion` `Org` 
            ON `Cap`.`Fk_Id_CatGeren` = `Org`.`Id_Gerencia`
        
        /* 5. TEMA (Consumiendo Vista Académica) */
        JOIN `PICADE`.`Vista_Temas_Capacitacion` `Tem` 
            ON `Cap`.`Fk_Id_Cat_TemasCap` = `Tem`.`Id_Tema`
        
        /* 6. SEDE (Consumiendo Vista de Infraestructura) */
        JOIN `PICADE`.`Vista_Sedes` `Sede` 
            ON `DatCap`.`Fk_Id_CatCases_Sedes` = `Sede`.`Id_Sedes`
        
        /* 7. MODALIDAD (Consumiendo Vista de Modalidad) */
        JOIN `PICADE`.`Vista_Modalidad_Capacitacion` `Moda` 
            ON `DatCap`.`Fk_Id_CatModalCap` = `Moda`.`Id_Modalidad`
        
        /* 8. ESTATUS (Consumiendo Vista de Ciclo de Vida) */
        JOIN `PICADE`.`Vista_Estatus_Capacitacion` `EstCap` 
            ON `DatCap`.`Fk_Id_CatEstCap` = `EstCap`.`Id_Estatus_Capacitacion`;

/* --- VERIFICACIÓN DE LA VISTA (QA RÁPIDO) --- */
-- SELECT * FROM Picade.Vista_Capacitaciones LIMIT 10;

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

/* ====================================================================================================
   PROCEDIMIENTO: SP_RegistrarCapacitacion
   ====================================================================================================
   
   1. FICHA TÉCNICA (TECHNICAL DATASHEET)
   --------------------------------------
   - Nombre: SP_RegistrarCapacitacion
   - Tipo: Transacción Atómica Compuesta (Atomic Composite Transaction)
   
   2. VISIÓN DE NEGOCIO (BUSINESS GOAL)
   ------------------------------------
   Este procedimiento constituye el **Motor Transaccional de Alta de Cursos** (Core Booking Engine).
   Su responsabilidad es orquestar el nacimiento de un "Expediente de Capacitación" en el sistema.
   
   A diferencia de un alta simple en un catálogo (que afecta una sola tabla), este proceso es una
   operación financiera y operativa crítica que afecta múltiples entidades simultáneamente.
   Debe garantizar que:
     A) Se reserve el presupuesto (vinculación con Gerencia).
     B) Se comprometan los recursos (Instructor y Sede).
     C) Se establezca la identidad legal del evento (Folio Único).
   
   [CRITICIDAD]: EXTREMA. 
   Es el punto de entrada único para toda la operación académica. Si este SP falla o permite datos
   corruptos, todo el módulo de asistencias, calificaciones y reportes DC-3 colapsará en cascada.

   3. ARQUITECTURA DE DEFENSA EN PROFUNDIDAD (DEFENSE IN DEPTH)
   ------------------------------------------------------------
   Este componente no confía ciegamente en el Frontend. Implementa 5 capas de seguridad concéntricas:

   CAPA 1: SANITIZACIÓN DE ENTRADA (INPUT HYGIENE)
      - Objetivo: Eliminar ruido y estandarizar datos antes de procesar.
      - Mecanismo: Aplicación forzosa de funciones `TRIM()` y `NULLIF()`.
      - Justificación: Evita que "   CAP-001  " y "CAP-001" sean tratados como folios distintos.
        Garantiza que una cadena vacía '' se trate como NULL para activar las validaciones de obligatoriedad.

   CAPA 2: VALIDACIÓN SINTÁCTICA Y DE NEGOCIO (FAIL FAST STRATEGY)
      - Objetivo: Rechazar peticiones incoherentes sin consumir ciclos de base de datos costosos.
      - Mecanismo: Bloques `IF` secuenciales que validan reglas aritméticas y lógicas.
      - Reglas Implementadas:
          * [RN-01] Integridad de Identificadores: Rechazo de IDs <= 0 (ej: -1, 0).
          * [RN-02] Rentabilidad Operativa: El `Cupo_Programado` debe ser >= 5. Menos de esto no es rentable.
          * [RN-03] Coherencia Temporal: La `Fecha_Inicio` no puede ser posterior a `Fecha_Fin`.
          * [RN-04] Completitud: Ningún campo obligatorio puede ser NULL.

   CAPA 3: VALIDACIÓN DE INTEGRIDAD REFERENCIAL EXTENDIDA ("ANTI-ZOMBIE RESOURCES")
      - Objetivo: Asegurar la vitalidad de las relaciones.
      - Problema: Un ID puede existir en la tabla foránea (Integridad Referencial Estándar), pero
        el registro puede estar "Borrado Lógicamente" (`Activo = 0`).
      - Solución: Se realizan consultas `SELECT` ligeras en tiempo real ("Just-in-Time") para verificar
        que cada recurso (Gerencia, Tema, Instructor, Sede, Modalidad, Estatus) no solo exista,
        sino que tenga su bandera `Activo = 1`.
      - Resultado: Previene la creación de cursos vinculados a sedes clausuradas o instructores dados de baja.

   CAPA 4: INTEGRIDAD DE IDENTIDAD Y CONCURRENCIA (UNIQUE IDENTITY LOCKING)
      - Objetivo: Garantizar la unicidad absoluta del Folio del Curso.
      - Problema: En un entorno de alta concurrencia, dos coordinadores pueden intentar registrar el 
        mismo folio (ej: 'CAP-2026-A01') en el mismo milisegundo.
      - Solución: Se aplica un **Bloqueo Pesimista** (`SELECT ... FOR UPDATE`) sobre la tabla padre
        antes de intentar la inserción. Esto serializa las operaciones conflictivas.
      - Resultado: El primer usuario obtiene el candado y graba; el segundo recibe un error controlado [409].

   CAPA 5: ATOMICIDAD TRANSACCIONAL (ACID COMPLIANCE)
      - Objetivo: Consistencia total. "Todo o Nada".
      - Problema: Si se inserta la Cabecera (`Capacitaciones`) pero falla la inserción del Detalle
        (`DatosCapacitaciones`) por un error de red o disco, quedaría un registro "huérfano" y corrupto.
      - Solución: Encapsulamiento en `START TRANSACTION` ... `COMMIT`.
      - Mecanismo de Recuperación: Un `EXIT HANDLER` captura cualquier excepción (`SQLEXCEPTION`) y
        ejecuta un `ROLLBACK` automático, dejando la base de datos en su estado original inmaculado.

   4. ESPECIFICACIÓN DE INTERFAZ (CONTRACT SPECIFICATION)
   ------------------------------------------------------
   [ENTRADA - INPUTS]
   Se requieren 11 parámetros estrictamente tipados. No se admiten objetos JSON ni XML; la estructura
   es plana para maximizar el rendimiento del motor SQL.

   [SALIDA - OUTPUTS]
   Retorna un Resultset de fila única (Single Row) con la confirmación de la operación:
      - `Mensaje` (VARCHAR): Texto descriptivo del éxito ("ÉXITO: Capacitación registrada...").
      - `Accion` (VARCHAR): Código de operación ('CREADA') para lógica del Frontend.
      - `Id_Capacitacion` (INT): La llave primaria interna generada (Auto-Increment).
      - `Folio` (VARCHAR): La llave de negocio confirmada.

   [CÓDIGOS DE ERROR - SQLSTATE MAPPING]
   El procedimiento normaliza los errores en códigos estándar HTTP-like para facilitar la integración API:
      - [400] Bad Request: Errores de validación sintáctica (nulos, fechas invertidas, cupo bajo).
      - [409] Conflict: Errores de integridad (Folio duplicado, Instructor inactivo/zombie).
      - [500] Internal Error: Fallos de sistema durante la escritura física.

   ==================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_RegistrarCapacitacion`$$

CREATE PROCEDURE `SP_RegistrarCapacitacion`(
    /* --------------------------------------------------------------------------------------------
       SECCIÓN A: TRAZABILIDAD Y AUDITORÍA
       Datos necesarios para cumplir con los requisitos de compliance y bitácora de cambios.
       -------------------------------------------------------------------------------------------- */
    IN _Id_Usuario_Ejecutor INT,         -- [OBLIGATORIO] ID del usuario (Admin/Coord) que ejecuta la acción.
                                         -- Se utilizará para llenar los campos `Created_By`.

    /* --------------------------------------------------------------------------------------------
       SECCIÓN B: DATOS DE CABECERA (TABLA PADRE: Capacitaciones)
       Información administrativa y financiera de alto nivel. Estos datos definen la identidad del curso.
       -------------------------------------------------------------------------------------------- */
    IN _Numero_Capacitacion VARCHAR(50), -- [OBLIGATORIO] Folio Único (Business Key). Ej: 'CAP-2026-001'.
                                         -- No puede repetirse NUNCA en el sistema.
    IN _Id_Gerencia         INT,         -- [OBLIGATORIO] Foreign Key hacia `Cat_Gerencias_Activos`.
                                         -- Representa el Centro de Costos dueño del presupuesto.
    IN _Id_Tema             INT,         -- [OBLIGATORIO] Foreign Key hacia `Cat_Temas_Capacitacion`.
                                         -- Define el contenido académico base.

    /* --------------------------------------------------------------------------------------------
       SECCIÓN C: DATOS DE DETALLE (TABLA HIJA: DatosCapacitaciones)
       Información logística y operativa de la ejecución específica.
       -------------------------------------------------------------------------------------------- */
    IN _Id_Instructor       INT,         -- [OBLIGATORIO] Foreign Key hacia `Usuarios`.
                                         -- Persona responsable de impartir la cátedra.
    IN _Id_Sede             INT,         -- [OBLIGATORIO] Foreign Key hacia `Cat_Cases_Sedes`.
                                         -- Ubicación física o virtual.
    IN _Id_Modalidad        INT,         -- [OBLIGATORIO] Foreign Key hacia `Cat_Modalidad_Capacitacion`.
                                         -- Metodología de entrega (Presencial/En Línea/Híbrido).
                                         -- Nota: Se recibe desde el Frontend, validado por el Framework.
    IN _Fecha_Inicio        DATE,        -- [OBLIGATORIO] Fecha de arranque del evento.
    IN _Fecha_Fin           DATE,        -- [OBLIGATORIO] Fecha de conclusión del evento.
    IN _Cupo_Programado     INT,         -- [OBLIGATORIO] Meta de asistencia (KPI).
                                         -- Sujeto a Regla de Negocio: Mínimo 5 pax.
    IN _Id_Estatus          INT,         -- [OBLIGATORIO] Foreign Key hacia `Cat_Estatus_Capacitacion`.
                                         -- Estado inicial del flujo (ej: 'Programado', 'En Curso').
    IN _Observaciones       TEXT         -- [OPCIONAL] Notas de bitácora inicial o contexto adicional.
                                         -- Único campo que permite nulidad semántica.
)
THIS_PROC: BEGIN

    /* ============================================================================================
       BLOQUE 0: INICIALIZACIÓN DE VARIABLES DE ENTORNO
       Definición de variables locales para el control de flujo, almacenamiento temporal de IDs
       y banderas de estado.
       ============================================================================================ */
    
    /* Identificadores */
    DECLARE v_Id_Capacitacion_Generado INT DEFAULT NULL; -- Almacenará el ID autogenerado de la Cabecera.
    
    /* Variables de Validación */
    DECLARE v_Folio_Existente VARCHAR(50) DEFAULT NULL;  -- Buffer para verificar duplicidad de folios.
    DECLARE v_Es_Activo TINYINT(1);                      -- Semáforo booleano para validación Anti-Zombie.
    
    /* Control de Excepciones */
    DECLARE v_Dup TINYINT(1) DEFAULT 0;                  -- Bandera para capturar errores de Unique Key (1062).

    /* ============================================================================================
       BLOQUE 1: DEFINICIÓN DE HANDLERS (SISTEMA DE DEFENSA)
       Configuración de las respuestas automáticas del motor de base de datos ante errores.
       ============================================================================================ */
    
    /* 1.1 HANDLER DE CONCURRENCIA (Race Condition Shield)
       [QUÉ]: Captura el error MySQL 1062 (Duplicate Entry for Key).
       [POR QUÉ]: Es la última línea de defensa si dos transacciones intentan insertar el mismo folio
       en el mismo microsegundo, superando los bloqueos de lectura.
       [ACCIÓN]: No abortar inmediatamente; marcar la bandera v_Dup=1 para manejo controlado. */
    DECLARE CONTINUE HANDLER FOR 1062 SET v_Dup = 1;

    /* 1.2 HANDLER DE FALLO CRÍTICO (System Failure Recovery)
       [QUÉ]: Captura cualquier excepción SQL genérica (SQLEXCEPTION).
       [EJEMPLOS]: Pérdida de conexión, disco lleno, violación de FK no controlada, error de sintaxis.
       [ACCIÓN]: Ejecutar ROLLBACK total para deshacer cambios parciales y RESIGNAL (propagar error). */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; 
    END;

    /* ============================================================================================
       BLOQUE 2: CAPA DE SANITIZACIÓN Y VALIDACIÓN SINTÁCTICA (FAIL FAST)
       Validación de tipos de datos, nulidad y reglas aritméticas básicas.
       Si algo falla aquí, se aborta ANTES de realizar cualquier lectura costosa a la base de datos.
       ============================================================================================ */
    
    -- 2.0 Limpieza de Strings
    -- Aplicamos TRIM para eliminar espacios accidentales. NULLIF convierte '' en NULL real.
    SET _Numero_Capacitacion = NULLIF(TRIM(_Numero_Capacitacion), '');
    SET _Observaciones       = NULLIF(TRIM(_Observaciones), '');

    -- 2.1 Validación de Obligatoriedad: FOLIO
    IF _Numero_Capacitacion IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE ENTRADA [400]: El Folio es obligatorio y no puede estar vacío.';
    END IF;

    -- 2.2 Validación de Obligatoriedad: SELECTORES (Dropdowns)
    -- Los IDs deben ser números positivos. Un valor <= 0 indica una selección inválida o "Seleccione...".
    
    IF _Id_Gerencia IS NULL OR _Id_Gerencia <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE ENTRADA [400]: Debe seleccionar una Gerencia válida.';
    END IF;

    IF _Id_Tema IS NULL OR _Id_Tema <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE ENTRADA [400]: Debe seleccionar un Tema válido.';
    END IF;

    -- 2.3 Validación de Negocio: RENTABILIDAD (Cupo Mínimo)
    -- Regla de Negocio: No es viable abrir un grupo para menos de 5 personas.
    IF _Cupo_Programado IS NULL OR _Cupo_Programado < 5 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [400]: El Cupo Programado debe ser mínimo de 5 asistentes.';
    END IF;

    -- 2.4 Validación de Obligatoriedad: INSTRUCTOR
    IF _Id_Instructor IS NULL OR _Id_Instructor <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE ENTRADA [400]: Debe seleccionar un Instructor válido.';
    END IF;

    -- 2.5 Validación de Negocio: COHERENCIA TEMPORAL (Fechas)
    -- Regla 1: Ambas fechas son obligatorias.
    IF _Fecha_Inicio IS NULL OR _Fecha_Fin IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE ENTRADA [400]: Las fechas de Inicio y Fin son obligatorias.';
    END IF;

    -- Regla 2: El tiempo es lineal. El inicio no puede ocurrir después del fin.
    IF _Fecha_Inicio > _Fecha_Fin THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE LÓGICA [400]: La Fecha de Inicio no puede ser posterior a la Fecha de Fin.';
    END IF;

    -- 2.6 Validación de Obligatoriedad: LOGÍSTICA (Sede, Modalidad, Estatus)
    IF _Id_Sede IS NULL OR _Id_Sede <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE ENTRADA [400]: Debe seleccionar una Sede válida.';
    END IF;

    IF _Id_Modalidad IS NULL OR _Id_Modalidad <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE ENTRADA [400]: Debe seleccionar una Modalidad válida.';
    END IF;

    IF _Id_Estatus IS NULL OR _Id_Estatus <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE ENTRADA [400]: Debe seleccionar un Estatus válido.';
    END IF;

    /* ============================================================================================
       BLOQUE 3: CAPA DE VALIDACIÓN DE EXISTENCIA (ANTI-ZOMBIE RESOURCES)
       Objetivo: Asegurar la Integridad Referencial Operativa.
       Verificamos contra la BD que los IDs proporcionados no solo existan, sino que estén VIVOS (Activo=1).
       ============================================================================================ */

    -- 3.1 Verificación Anti-Zombie: GERENCIA
    SET v_Es_Activo = NULL;
    SELECT `Activo` INTO v_Es_Activo FROM `Cat_Gerencias_Activos` WHERE `Id_CatGeren` = _Id_Gerencia LIMIT 1;
    
    IF v_Es_Activo IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE INTEGRIDAD [404]: La Gerencia seleccionada no existe en la base de datos.';
    END IF;
    IF v_Es_Activo = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [409]: La Gerencia seleccionada está dada de baja (Inactiva).';
    END IF;

    -- 3.2 Verificación Anti-Zombie: TEMA
    SET v_Es_Activo = NULL;
    SELECT `Activo` INTO v_Es_Activo FROM `Cat_Temas_Capacitacion` WHERE `Id_Cat_TemasCap` = _Id_Tema LIMIT 1;
    
    IF v_Es_Activo IS NULL OR v_Es_Activo = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE INTEGRIDAD [409]: El Tema seleccionado no existe o está inactivo.';
    END IF;

    -- 3.3 Verificación Anti-Zombie: INSTRUCTOR
    -- Nota: Validamos tanto la existencia del Usuario como la vigencia de su Info Personal.
    SET v_Es_Activo = NULL;
    SELECT U.Activo INTO v_Es_Activo 
    FROM Usuarios U 
    INNER JOIN Info_Personal I ON U.Fk_Id_InfoPersonal = I.Id_InfoPersonal
    WHERE U.Id_Usuario = _Id_Instructor AND I.Activo = 1 
    LIMIT 1;
    
    IF v_Es_Activo IS NULL OR v_Es_Activo = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE INTEGRIDAD [409]: El Instructor seleccionado no está activo o su cuenta ha sido suspendida.';
    END IF;

    -- 3.4 Verificación Anti-Zombie: SEDE
    SET v_Es_Activo = NULL;
    SELECT `Activo` INTO v_Es_Activo FROM `Cat_Cases_Sedes` WHERE `Id_CatCases_Sedes` = _Id_Sede LIMIT 1;
    
    IF v_Es_Activo IS NULL OR v_Es_Activo = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE INTEGRIDAD [409]: La Sede seleccionada no existe o está cerrada.';
    END IF;

    -- 3.5 Verificación Anti-Zombie: MODALIDAD
    SET v_Es_Activo = NULL;
    SELECT `Activo` INTO v_Es_Activo FROM `Cat_Modalidad_Capacitacion` WHERE `Id_CatModalCap` = _Id_Modalidad LIMIT 1;
    
    IF v_Es_Activo IS NULL OR v_Es_Activo = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE INTEGRIDAD [409]: La Modalidad seleccionada no es válida o está inactiva.';
    END IF;

    -- 3.6 Verificación Anti-Zombie: ESTATUS
    SET v_Es_Activo = NULL;
    SELECT `Activo` INTO v_Es_Activo FROM `Cat_Estatus_Capacitacion` WHERE `Id_CatEstCap` = _Id_Estatus LIMIT 1;
    
    IF v_Es_Activo IS NULL OR v_Es_Activo = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE INTEGRIDAD [409]: El Estatus seleccionado no es válido o está inactivo.';
    END IF;

    /* ============================================================================================
       BLOQUE 4: TRANSACCIÓN MAESTRA (ATOMICIDAD Y PERSISTENCIA)
       Punto de No Retorno. Si llegamos aquí, los datos son puros, válidos y consistentes.
       Iniciamos la escritura física en disco bajo un bloque transaccional ACID.
       ============================================================================================ */
    START TRANSACTION;

    /* --------------------------------------------------------------------------------------------
       PASO 4.1: BLINDAJE DE IDENTIDAD (BLOQUEO PESIMISTA)
       Verificamos la unicidad del Folio usando `FOR UPDATE`.
       Esto bloquea el índice del folio si ya existe, obligando a otras transacciones a esperar.
       Evita condiciones de carrera en la verificación de duplicados.
       -------------------------------------------------------------------------------------------- */
    SELECT `Numero_Capacitacion` INTO v_Folio_Existente
    FROM `Capacitaciones`
    WHERE `Numero_Capacitacion` = _Numero_Capacitacion
    LIMIT 1
    FOR UPDATE;

    IF v_Folio_Existente IS NOT NULL THEN
        ROLLBACK; -- Liberamos el bloqueo inmediatamente antes de salir.
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'CONFLICTO DE IDENTIDAD [409]: El FOLIO ingresado YA EXISTE en el sistema. No se permiten duplicados.';
    END IF;

    /* --------------------------------------------------------------------------------------------
       PASO 4.2: INSERCIÓN DE CABECERA (ENTIDAD PADRE)
       Insertamos los datos administrativos en la tabla `Capacitaciones`.
       -------------------------------------------------------------------------------------------- */
    INSERT INTO `Capacitaciones`
    (
        `Numero_Capacitacion`, 
        `Fk_Id_CatGeren`, 
        `Fk_Id_Cat_TemasCap`,
        `Asistentes_Programados`, 
        `Activo`, 
        `created_at`, 
        `updated_at`,
        `Fk_Id_Usuario_Cap_Created_by` -- Auditoría de creación
    )
    VALUES
    (
        _Numero_Capacitacion, 
        _Id_Gerencia, 
        _Id_Tema,
        _Cupo_Programado, 
        1,      -- Regla: Todo curso nace Activo (Visible).
        NOW(), 
        NOW(),
        _Id_Usuario_Ejecutor
    );

    /* Verificación Inmediata de Concurrencia post-INSERT */
    /* Si el Handler 1062 se disparó durante el insert anterior, abortamos. */
    IF v_Dup = 1 THEN 
        ROLLBACK; 
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE CONCURRENCIA [409]: El Folio fue registrado por otro usuario hace un instante. Por favor verifique.'; 
    END IF;
    
    /* CRÍTICO: Captura del ID generado (AUTO_INCREMENT) para vincular al Hijo */
    SET v_Id_Capacitacion_Generado = LAST_INSERT_ID();

    /* --------------------------------------------------------------------------------------------
       PASO 4.3: INSERCIÓN DE DETALLE (ENTIDAD HIJA)
       Insertamos los datos operativos en la tabla `DatosCapacitaciones`.
       Esta tabla maneja la "Instancia" o versión actual del curso (Fechas, Instructor, Estatus).
       -------------------------------------------------------------------------------------------- */
    INSERT INTO `DatosCapacitaciones`
    (
        `Fk_Id_Capacitacion`,   -- Vinculación Foreign Key con el Padre recién creado.
        `Fk_Id_Instructor`,
        `Fecha_Inicio`, 
        `Fecha_Fin`,
        `Fk_Id_CatCases_Sedes`, 
        `Fk_Id_CatModalCap`, 
        `Fk_Id_CatEstCap`,
        `AsistentesReales`, 
        `Observaciones`, 
        `Activo`, 
        `created_at`, 
        `updated_at`,
        `Fk_Id_Usuario_DatosCap_Created_by` -- Auditoría de creación del detalle.
    )
    VALUES
    (
        v_Id_Capacitacion_Generado, 
        _Id_Instructor,
        _Fecha_Inicio, 
        _Fecha_Fin,
        _Id_Sede, 
        _Id_Modalidad, 
        _Id_Estatus, -- Insertamos directamente la elección validada del usuario.
        0,           -- Regla: Asistentes Reales inicia en 0 al crear el curso.
        _Observaciones, 
        1,           -- Regla: Detalle nace Activo.
        NOW(), 
        NOW(),
        _Id_Usuario_Ejecutor
    );

    /* Validación Final de Integridad de la Transacción Compuesta */
    /* Si falló el insert del hijo (ej: FK rota no detectada), revertimos el padre. */
    IF v_Dup = 1 THEN 
        ROLLBACK; 
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA [500]: Fallo crítico en la creación del detalle operativo. Transacción revertida para mantener consistencia.'; 
    END IF;

    /* ============================================================================================
       BLOQUE 5: COMMIT Y RESPUESTA (FINALIZACIÓN EXITOSA)
       Si llegamos aquí, todo es perfecto. Confirmamos los cambios en disco y notificamos.
       ============================================================================================ */
    COMMIT;

    SELECT 
        'ÉXITO: Capacitación registrada correctamente.' AS Mensaje,
        'CREADA' AS Accion,
        v_Id_Capacitacion_Generado AS Id_Capacitacion, -- ID Interno para uso del Backend.
        _Numero_Capacitacion AS Folio;                 -- ID de Negocio para mostrar al Usuario.

END$$

DELIMITER ;

/* ============================================================================================
   SECCIÓN: DASHBOARD (PARA VER LOS GRID FILTRADOS E IR AL DETALLE)
   ============================================================================================
   Estas rutinas son críticas para la UX administrativa. No solo devuelven el dato pedido, sino 
   que garantizan la integridad de lectura antes de permitir una operación de modificación.
   ============================================================================================ */
   
   /* ====================================================================================================
   PROCEDIMIENTO: SP_Dashboard_ResumenAnual
   ====================================================================================================
   
   1. FICHA TÉCNICA (TECHNICAL DATASHEET)
   --------------------------------------
   - Nombre: SP_Dashboard_ResumenAnual
   - Tipo: Motor de Analítica Agrupada (Aggregated Analytics Engine)
   - Nivel de Aislamiento: Read Uncommitted (Para máxima velocidad en Dashboards)
   - Complejidad Computacional: O(N) optimizada por índices primarios.
   
   2. VISIÓN DE NEGOCIO (BUSINESS GOAL)
   ------------------------------------
   Este procedimiento es el corazón del **Tablero de Control Estratégico** (Dashboard).
   Su misión es transformar miles de registros operativos dispersos en **Indicadores Clave de Desempeño (KPIs)**
   agrupados por Año Fiscal.
   
   Alimenta las "Tarjetas Anuales" que permiten al Coordinador responder en 1 segundo:
     - "¿Cuál fue el volumen de operación del año pasado?"
     - "¿Qué tan eficientes fuimos?" (Finalizados vs Cancelados).
     - "¿A cuántas personas impactamos?" (Cobertura).

   3. ESTRATEGIA TÉCNICA: "HARDCODED ID OPTIMIZATION"
   --------------------------------------------------
   Para garantizar una renderización instantánea del Dashboard (< 100ms), eliminamos los JOINs 
   hacia catálogos de texto (`Cat_Estatus`) y utilizamos comparaciones numéricas directas.
   
   [MAPEO DE IDs DE ESTATUS CRÍTICOS]:
     - ID 4  = FINALIZADO (Éxito Operativo).
     - ID 8  = CANCELADO (Fallo Operativo).
     - ID 10 = CERRADO/ARCHIVADO (Cierre Administrativo).
     - RESTO = EN PROCESO (Operación Viva: Programado, En Curso, Por Iniciar, etc.).

   4. INTEGRIDAD DE DATOS: "LATEST SNAPSHOT STRATEGY"
   --------------------------------------------------
   Utiliza una subconsulta de `MAX(Id)` para asegurar que solo se contabilice la **última versión** de cada curso. Esto evita la duplicidad estadística si un curso fue editado 20 veces.

   ==================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_Dashboard_ResumenAnual`$$

CREATE PROCEDURE `SP_Dashboard_ResumenAnual`()
BEGIN
    /* ============================================================================================
       BLOQUE ÚNICO: CONSULTA ANALÍTICA MAESTRA
       No requiere parámetros. Escanea toda la historia y la agrupa por años.
       ============================================================================================ */
    SELECT 
        /* ----------------------------------------------------------------------------------------
           DIMENSIÓN TEMPORAL (AGRUPADOR PRINCIPAL)
           Define el "Contenedor" de la tarjeta (Ej: Tarjeta 2026, Tarjeta 2025).
           ---------------------------------------------------------------------------------------- */
        YEAR(`DC`.`Fecha_Inicio`)          AS `Anio_Fiscal`,
        
        /* ----------------------------------------------------------------------------------------
           KPI DE VOLUMEN (TOTAL THROUGHPUT)
           Total de folios únicos gestionados en el año, sin importar su destino final.
           ---------------------------------------------------------------------------------------- */
        COUNT(DISTINCT `Cap`.`Numero_Capacitacion`) AS `Total_Cursos_Gestionados`,
        
        /* ----------------------------------------------------------------------------------------
           KPIs DE SALUD OPERATIVA (BREAKDOWN BY STATUS ID)
           Desglose basado en reglas de negocio estrictas usando IDs fijos para velocidad.
           ---------------------------------------------------------------------------------------- */
        
        /* [KPI ÉXITO]: Cursos que concluyeron satisfactoriamente (ID 4) */
		/* [KPI ÉXITO CORREGIDO]: 
           Suma Finalizados (4) Y Archivados (10).
           Lógica: Si está archivado, es porque se finalizó correctamente. */
        SUM(CASE 
            WHEN `DC`.`Fk_Id_CatEstCap` IN (4, 10) THEN 1 
            ELSE 0 
        END) AS `Finalizados`,
        
        /* [KPI FALLO]: Cursos que se cancelaron y no ocurrieron (ID 8) */
        SUM(CASE 
            WHEN `DC`.`Fk_Id_CatEstCap` = 8 THEN 1 
            ELSE 0 
        END) AS `Cursos_Cancelados`,
        
        /* [KPI VIVO]: Cursos en cualquier etapa de ejecución o planeación.
           Lógica: Todo lo que NO sea Final(4), Cancelado(8) o Archivado(10). */
        SUM(CASE 
            WHEN `DC`.`Fk_Id_CatEstCap` NOT IN (4, 8, 10) THEN 1 
            ELSE 0 
        END) AS `Cursos_En_Proceso`,

        /* ----------------------------------------------------------------------------------------
           KPIs DE GESTIÓN ADMINISTRATIVA
           ---------------------------------------------------------------------------------------- */
        /* [KPI ARCHIVO]: Expedientes cerrados. 
           Suma:
             1. Cursos apagados globalmente (`Cap.Activo = 0`).
             2. Cursos marcados explícitamente con estatus "Cerrado/Archivado" (ID 10). */
        SUM(CASE 
            WHEN `Cap`.`Activo` = 0 OR `DC`.`Fk_Id_CatEstCap` = 10 THEN 1 
            ELSE 0 
        END) AS `Expedientes_Archivados`,
        
        /* ----------------------------------------------------------------------------------------
           KPIs DE IMPACTO (COBERTURA)
           ---------------------------------------------------------------------------------------- */
        /* Suma de personas reales que tomaron los cursos. */
        -- SUM(`DC`.`AsistentesReales`)       AS `Total_Personas_Capacitadas`,
		/* KPI IMPACTO: Lógica Híbrida (Manual vs Sistema) */
        SUM(
            GREATEST(
                COALESCE(`DC`.`AsistentesReales`, 0), 
                (
                SELECT COUNT(*)
                FROM `PICADE`.`Capacitaciones_Participantes` `CP` 
                WHERE `CP`.`Fk_Id_DatosCap` = `DC`.`Id_DatosCap` 
                AND `CP`.`Fk_Id_CatEstPart` != 5)
            )
        )                                  AS `Total_Personas_Capacitadas`,
        
        /* ----------------------------------------------------------------------------------------
           METADATA DE ACTUALIDAD
           ---------------------------------------------------------------------------------------- */
        /* Fecha del curso más lejano en el calendario para ese año. */
        MAX(`DC`.`Fecha_Fin`)              AS `Ultima_Actividad`

    FROM `PICADE`.`DatosCapacitaciones` `DC` -- Tabla Operativa (Hijo)
    
    /* JOIN con el Padre (Necesario para agrupar por Folio Único y ver el Soft Delete Global) */
    INNER JOIN `PICADE`.`Capacitaciones` `Cap` 
        ON `DC`.`Fk_Id_Capacitacion` = `Cap`.`Id_Capacitacion`
    
    /* --------------------------------------------------------------------------------------------
       FILTRO DE UNICIDAD E INTEGRIDAD (LATEST SNAPSHOT STRATEGY)
       Esta es la cláusula más crítica del reporte.
       
       PROBLEMA: Un curso puede tener 50 versiones históricas (Instructor A, luego B, luego C...).
       Si sumamos todo, triplicaríamos los números.
       
       SOLUCIÓN: Hacemos INNER JOIN con una subconsulta que extrae el MAX(ID) de cada Padre.
       EFECTO: Solo pasa a la suma la "Última Foto" conocida de cada curso.
       -------------------------------------------------------------------------------------------- */
    INNER JOIN (
        SELECT MAX(`Id_DatosCap`) as `MaxId` 
        FROM `PICADE`.`DatosCapacitaciones` 
        GROUP BY `Fk_Id_Capacitacion`
    ) `Latest` ON `DC`.`Id_DatosCap` = `Latest`.`MaxId`

    /* Agrupamiento temporal */
    GROUP BY YEAR(`DC`.`Fecha_Inicio`)
    
    /* Ordenamiento: El año más reciente (futuro o presente) aparece primero */
    ORDER BY `Anio_Fiscal` DESC;

END$$

DELIMITER ;

/* ====================================================================================================
   PROCEDIMIENTO: SP_ObtenerMatrizPICADE_
   ====================================================================================================
   
   1. FICHA TÉCNICA (TECHNICAL DATASHEET)
   --------------------------------------
   - Nombre Oficial:      SP_ObtenerMatrizPICADE
   - Tipo:                Procedimiento de Lectura Masiva (Bulk Read)
   - Nivel de Aislamiento: READ COMMITTED (Lectura Confirmada)
   - Complejidad:         O(N) sobre índices agrupados (Alta Eficiencia)
   - Dependencias:        Vista_Capacitaciones, Capacitaciones, DatosCapacitaciones
   
   2. VISIÓN DE NEGOCIO (BUSINESS GOAL)
   ------------------------------------
   Este procedimiento es el **Corazón del Dashboard Operativo**. Su misión es proyectar la "Verdad Única"
   sobre el estado de la capacitación en la empresa.
   
   Resuelve el problema de la "Ambigüedad Histórica": En un sistema donde los cursos cambian de fecha,
   instructor o estatus múltiples veces, este SP garantiza que el Coordinador vea SIEMPRE Y SOLO
   la versión final vigente, ignorando los borradores o versiones previas.

   3. ARQUITECTURA DE SOLUCIÓN: "RAW DATA DELIVERY"
   ------------------------------------------------
   A diferencia de sistemas legados que incrustan HTML o lógica de colores en SQL, este SP es agnóstico.
   - NO devuelve: "Botón Rojo" o "Clase CSS".
   - SÍ devuelve: "Activo = 0" (El dato crudo).
   
   Esto permite que Laravel (Backend) y Vue (Frontend) decidan cómo pintar la interfaz sin tener que
   modificar la Base de Datos ante cambios cosméticos.

   4. MAPA DE SALIDA (OUTPUT CONTRACT)
   -----------------------------------
   - Datos de Navegación: IDs ocultos para que el Frontend sepa qué editar.
   - Datos Humanos:       Textos legibles (Folio, Tema, Instructor).
   - Banderas Lógicas:    Flags binarios (1/0) para el motor de decisiones de Laravel.
   ==================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ObtenerMatrizPICADE`$$

CREATE PROCEDURE `SP_ObtenerMatrizPICADE`(
    /* ------------------------------------------------------------------------------------------------
       PARÁMETROS DE ENTRADA (INPUT LAYER)
       ------------------------------------------------------------------------------------------------
       Se reciben tipos estrictos para evitar inyección SQL y garantizar integridad de filtros.
       ------------------------------------------------------------------------------------------------ */
    IN _Id_Gerencia INT,  -- [OPCIONAL] Filtro Organizacional. Si es NULL/0, se asume "Vista Global".
    IN _Fecha_Min   DATE, -- [OBLIGATORIO] Límite inferior del rango temporal (Inclusive).
    IN _Fecha_Max   DATE  -- [OBLIGATORIO] Límite superior del rango temporal (Inclusive).
)
THIS_PROC: BEGIN

    /* ============================================================================================
       FASE 0: PROGRAMACIÓN DEFENSIVA (DEFENSIVE CODING BLOCK)
       Objetivo: Validar la coherencia de la petición antes de consumir recursos del servidor.
       ============================================================================================ */
    
    /* 0.1 Integridad de Parametrización */
    /* Regla: El motor de reportes no puede adivinar fechas. Deben ser explícitas. */
    IF _Fecha_Min IS NULL OR _Fecha_Max IS NULL THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: Las fechas de inicio y fin son obligatorias para delimitar el reporte.';
    END IF;

    /* 0.2 Coherencia Temporal (Anti-Paradoja) */
    /* Regla: El tiempo es lineal. El inicio no puede ocurrir después del fin. */
    IF _Fecha_Min > _Fecha_Max THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERROR DE LÓGICA [400]: Rango de fechas inválido. La fecha de inicio es posterior a la fecha de fin.';
    END IF;

    /* ============================================================================================
       FASE 1: PROYECCIÓN DE DATOS (DATA PROJECTION LAYER)
       Objetivo: Seleccionar y etiquetar las columnas que consumirá el API de Laravel.
       ============================================================================================ */
    SELECT 
       
        /* ------------------------------------------------------------------
           GRUPO A: LLAVES DE NAVEGACIÓN (CONTEXTO TÉCNICO)
           Estos datos NO se muestran al usuario, pero son las "balas" que disparan los botones.
           ------------------------------------------------------------------ */
        `VC`.`Id_Capacitacion`,            -- ID Padre (Expediente). Útil para trazabilidad.
        `VC`.`Id_Detalle_de_Capacitacion`, -- ID Hijo (Versión). CRÍTICO: Es el payload del botón "Editar".
        
        /* ------------------------------------------------------------------
           GRUPO B: DATOS VISUALES (CAPA DE PRESENTACIÓN)
           Información humana que llena las celdas de la tabla.
           ------------------------------------------------------------------ */
        `VC`.`Numero_Capacitacion`         AS `Folio`,      -- Identificador único visual (ej: CAP-2026-001)
        `VC`.`Clave_Gerencia_Solicitante`  AS `Gerencia`,   -- Cliente interno (ej: GSPSST)
        `VC`.`Nombre_Tema`                 AS `Tema`,       -- Título del curso
        `VC`.`Duracion_Horas`			   AS `Duracion`,
        `VC`.`Ficha_Instructor`,
        /*`VC`.`Nombre_Instructor`           AS `Instructor`, -- Responsable de la ejecución
        `Us`.`Ficha_Usuario`                AS `Ficha_Instructor`,
        `Us`.`Apellido_Paterno_Instructor`             AS `Apellido_Paterno_Instructor`,
        `Us`.`Apellido_Materno_Instructor`             AS `Apellido_Materno_Instructor`,
        `Us`.`Nombre_Instructor`                       AS `Nombre_Instructor`,*/
        CONCAT(`VC`.`Apellido_Paterno_Instructor`, ' ', `VC`.`Apellido_Materno_Instructor`, ' ', `VC`.`Nombre_Instructor`) AS `Instructor`,

        `VC`.`Nombre_Sede`                 AS `Sede`,       -- Lugar de ejecución
		`VC`.`Nombre_Modalidad`            AS `Modalidad`,
        
		/* ------------------------------------------------------------------
		   GRUPO C: METADATOS TEMPORALES
           Usados por el Frontend para agrupar visualmente (ej: Encabezados de Mes).
		------------------------------------------------------------------ */
        
		`VC`.`Fecha_Inicio`,                                -- Día 1 del curso
		`VC`.`Fecha_Fin`,                                   -- Día N del curso

         YEAR(`VC`.`Fecha_Inicio`)          AS `Anio`,       -- Año Fiscal
		MONTHNAME(`VC`.`Fecha_Inicio`)     AS `Mes`, -- Etiqueta legible (Enero, Febrero...)
        
        /* ------------------------------------------------------------------
           GRUPO D: ANALÍTICA (KPIs)
           Métricas rápidas para visualización en el grid.
           ------------------------------------------------------------------ 
        /* -----------------------------------------------------------------------------------------
           [KPIs DE PLANEACIÓN - PLANIFICADO]
           Datos estáticos definidos al crear el curso. Representan la "Meta".
           ----------------------------------------------------------------------------------------- */

        -- Capacidad máxima teórica del aula o sala virtual.
        `VC`.`Asistentes_Meta`             AS `Cupo_Programado_de_Asistentes`,
        
        -- Cantidad de asientos reservados manualmente por el coordinador (Override).
        -- Este valor tiene precedencia sobre el conteo automático en caso de ser mayor.
        -- `VC`.`Asistentes_Manuales`, 
        
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
        `VC`.`Cupo_Disponible`,
        
        /* ------------------------------------------------------------------
           GRUPO E: ESTADO VISUAL
           Textos pre-calculados en la Vista para mostrar al usuario.
           ------------------------------------------------------------------ */
        `VC`.`Estatus_Curso`               AS `Estatus_Texto`, -- (ej: "FINALIZADO", "CANCELADO")

        `VC`.`Observaciones`               AS `Bitacora_Notas`,           -- Justificación de esta versión

        /* ------------------------------------------------------------------
           GRUPO F: BANDERAS LÓGICAS (LOGIC FLAGS - CRITICAL)
           Aquí reside la inteligencia arquitectónica. Entregamos el estado físico puro.
           Laravel usará esto para: if (Estatus_Del_Registro == 1 && User->isAdmin()) { ... }
           ------------------------------------------------------------------ */
        `Cap`.`Activo`                     AS `Estatus_Del_Registro` -- 1 = Expediente Vivo / 0 = Archivado (Soft Delete)

    /* ============================================================================================
       FASE 2: ORIGEN DE DATOS Y RELACIONES (RELATIONAL ASSEMBLY)
       Objetivo: Construir el objeto de datos uniendo las entidades normalizadas.
       ============================================================================================ */
    FROM `PICADE`.`Vista_Capacitaciones` `VC`
    
    /* [JOIN 1 - JERARQUÍA PADRE]: Conexión con el Expediente Maestro (`Capacitaciones`).
       Necesario para conocer el estatus global (`Activo`) y la Gerencia dueña del proceso. */
    INNER JOIN `PICADE`.`Capacitaciones` `Cap` 
        ON `VC`.`Id_Capacitacion` = `Cap`.`Id_Capacitacion`

    /* [JOIN 2 - FILTRO DE ACTUALIDAD]: "MAX ID SNAPSHOT STRATEGY"
       ------------------------------------------------------------------------------------
       PROBLEMA: La tabla `DatosCapacitaciones` es un log histórico. Un curso puede tener 
       10 versiones (cambios de fecha, instructor, etc).
       
       SOLUCIÓN: Hacemos un JOIN contra una subconsulta que obtiene SOLO el ID más alto (MAX)
       agrupado por curso. Esto actúa como un filtro natural que descarta automáticamente 
       todo el historial obsoleto, dejando solo la "Foto Final".
       ------------------------------------------------------------------------------------ */
    INNER JOIN (
        SELECT Id_DatosCap, Activo 
        FROM `PICADE`.`DatosCapacitaciones`
        WHERE Id_DatosCap IN (
            SELECT MAX(Id_DatosCap) 
            FROM `PICADE`.`DatosCapacitaciones` 
            GROUP BY Fk_Id_Capacitacion
        )
    ) `Latest_Row` ON `VC`.`Id_Detalle_de_Capacitacion` = `Latest_Row`.`Id_DatosCap`

    /* ============================================================================================
       FASE 3: MOTOR DE FILTRADO (FILTERING ENGINE)
       Objetivo: Aplicar las reglas de negocio solicitadas por el usuario desde el Dashboard.
       ============================================================================================ */
    WHERE 
        /* 3.1 FILTRO ORGANIZACIONAL (JERÁRQUICO)
           Lógica: Si `_Id_Gerencia` es 0 o NULL, la condición se vuelve TRUE globalmente, 
           mostrando todos los registros (Modo Director). Si tiene valor, filtra exacto. */
        (_Id_Gerencia IS NULL OR _Id_Gerencia <= 0 OR `Cap`.`Fk_Id_CatGeren` = _Id_Gerencia)
        
        AND 
        
        /* 3.2 FILTRO DE RANGO TEMPORAL (CRONOLÓGICO)
           Lógica: Filtra estrictamente por la fecha de inicio.
           Nota: Laravel ya calculó las fechas exactas (Trimestre, Semestre, Año) antes de llamar. */
        (`VC`.`Fecha_Inicio` BETWEEN _Fecha_Min AND _Fecha_Max)

    /* ============================================================================================
       FASE 4: ORDENAMIENTO Y PRESENTACIÓN (UX SORTING)
       Objetivo: Definir el orden visual inicial para optimizar la lectura del usuario.
       ============================================================================================ */
    /* Regla UX: "Lo urgente primero". Ordenamos descendente por fecha para que los cursos
       más recientes o futuros aparezcan en la parte superior de la tabla. */
    ORDER BY `VC`.`Fecha_Inicio` DESC;

END$$

DELIMITER ;

/* ====================================================================================================
   PROCEDIMIENTO: SP_BuscadorGlobalPICADE_
   ====================================================================================================

   ----------------------------------------------------------------------------------------------------
   I. CONTEXTO OPERATIVO Y PROPÓSITO (THE "WHAT" & "FOR WHOM")
   ----------------------------------------------------------------------------------------------------
   [QUÉ ES]: 
   Es el "Sabueso" del sistema. Un motor de búsqueda global diseñado para localizar expedientes
   perdidos en el tiempo, ignorando los filtros de Año Fiscal o Gerencia que limitan al dashboard.

   [EL PROBLEMA QUE RESUELVE]: 
   El "Punto Ciego Histórico". Cuando un usuario busca un folio (ej: "CAP-2022") estando en la vista
   del 2026, el grid normal no lo encuentra. Este SP escanea TODA la base de datos para hallarlo.

   [SOLUCIÓN ARQUITECTÓNICA - "MIRROR OUTPUT STRATEGY"]: 
   Este SP devuelve EXACTAMENTE la misma estructura de columnas (nombres y tipos) que el procedimiento
   maestro `SP_ObtenerMatrizPICADE`.
   - Beneficio: El Frontend (Vue/Laravel) puede reutilizar el mismo componente visual (Tabla/Card)
     para mostrar los resultados, sin necesitar adaptadores o mapeos adicionales.

   ----------------------------------------------------------------------------------------------------
   II. ESTRATEGIA DE INTEGRIDAD (DATA CONSISTENCY)
   ----------------------------------------------------------------------------------------------------
   [PATRÓN "MAX ID SNAPSHOT"]:
   Igual que la Matriz, utiliza una subconsulta de `MAX(Id)` para ignorar el historial de ediciones
   y devolver únicamente la versión vigente del curso encontrado.

   ----------------------------------------------------------------------------------------------------
   III. CONTRATO DE INTERFAZ (INPUT/OUTPUT)
   ----------------------------------------------------------------------------------------------------
   - INPUT: 
     * _TerminoBusqueda (VARCHAR): Fragmento de texto (min 2 chars).
   
   - OUTPUT (Clave para Laravel):
     * Anio: Dato crítico (GPS) para que el Frontend decida si muestra el registro o 
       sugiere una redirección (ej: "Ir al Dashboard 2022").
   ==================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_BuscadorGlobalPICADE`$$

CREATE PROCEDURE `SP_BuscadorGlobalPICADE`(
    IN _TerminoBusqueda VARCHAR(50) -- Input del usuario (Folio, Gerencia o Tema)
)
THIS_PROC: BEGIN

    /* ============================================================================================
       FASE 0: PROGRAMACIÓN DEFENSIVA (DEFENSIVE CODING BLOCK)
       Propósito: Proteger al servidor de consultas costosas o vacías.
       ============================================================================================ */
    IF LENGTH(_TerminoBusqueda) < 3 THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ADVERTENCIA DE SEGURIDAD [400]: El término de búsqueda debe tener al menos 3 caracteres.';
    END IF;

    /* ============================================================================================
       FASE 1: PROYECCIÓN DE DATOS (DATA PROJECTION LAYER)
       Objetivo: Seleccionar y etiquetar las columnas que consumirá el API de Laravel.
       ============================================================================================ */
    SELECT 
       
        /* ------------------------------------------------------------------
           GRUPO A: LLAVES DE NAVEGACIÓN (CONTEXTO TÉCNICO)
           Estos datos NO se muestran al usuario, pero son las "balas" que disparan los botones.
           ------------------------------------------------------------------ */
        `VC`.`Id_Capacitacion`,            -- ID Padre (Expediente). Útil para trazabilidad.
        `VC`.`Id_Detalle_de_Capacitacion`, -- ID Hijo (Versión). CRÍTICO: Es el payload del botón "Editar".
        
        /* ------------------------------------------------------------------
           GRUPO B: DATOS VISUALES (CAPA DE PRESENTACIÓN)
           Información humana que llena las celdas de la tabla.
           ------------------------------------------------------------------ */
        `VC`.`Numero_Capacitacion`         AS `Folio`,      -- Identificador único visual (ej: CAP-2026-001)
        `VC`.`Clave_Gerencia_Solicitante`  AS `Gerencia`,   -- Cliente interno (ej: GSPSST)
        `VC`.`Nombre_Tema`                 AS `Tema`,       -- Título del curso
        `VC`.`Duracion_Horas`			   AS `Duracion`,
        
        `VC`.`Ficha_Instructor`,
        /*`VC`.`Nombre_Instructor`           AS `Instructor`, -- Responsable de la ejecución
        `Us`.`Ficha_Usuario`                AS `Ficha_Instructor`,
        `Us`.`Apellido_Paterno_Instructor`             AS `Apellido_Paterno_Instructor`,
        `Us`.`Apellido_Materno_Instructor`             AS `Apellido_Materno_Instructor`,
        `Us`.`Nombre_Instructor`                       AS `Nombre_Instructor`,
        `VC`.`Nombre_Instructor`           AS `Instructor`, -- Responsable de la ejecución*/
        CONCAT(`VC`.`Apellido_Paterno_Instructor`, ' ', `VC`.`Apellido_Materno_Instructor`, ' ', `VC`.`Nombre_Instructor`) AS `Instructor`,

        
        `VC`.`Nombre_Sede`                 AS `Sede`,       -- Lugar de ejecución
		`VC`.`Nombre_Modalidad`            AS `Modalidad`,
        
		/* ------------------------------------------------------------------
		   GRUPO C: METADATOS TEMPORALES
           Usados por el Frontend para agrupar visualmente (ej: Encabezados de Mes).
		------------------------------------------------------------------ */
        
		`VC`.`Fecha_Inicio`,                                -- Día 1 del curso
		`VC`.`Fecha_Fin`,                                   -- Día N del curso

         YEAR(`VC`.`Fecha_Inicio`)          AS `Anio`,       -- Año Fiscal
		MONTHNAME(`VC`.`Fecha_Inicio`)     AS `Mes`, -- Etiqueta legible (Enero, Febrero...)
        
        /* ------------------------------------------------------------------
           GRUPO D: ANALÍTICA (KPIs)
           Métricas rápidas para visualización en el grid.
           ------------------------------------------------------------------ 
        /* -----------------------------------------------------------------------------------------
           [KPIs DE PLANEACIÓN - PLANIFICADO]
           Datos estáticos definidos al crear el curso. Representan la "Meta".
           ----------------------------------------------------------------------------------------- */

        -- Capacidad máxima teórica del aula o sala virtual.
        `VC`.`Asistentes_Meta`             AS `Cupo_Programado_de_Asistentes`,
        
        -- Cantidad de asientos reservados manualmente por el coordinador (Override).
        -- Este valor tiene precedencia sobre el conteo automático en caso de ser mayor.
        -- `VC`.`Asistentes_Manuales`, 
        
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
        `VC`.`Cupo_Disponible`,
        
        /* ------------------------------------------------------------------
           GRUPO E: ESTADO VISUAL
           Textos pre-calculados en la Vista para mostrar al usuario.
           ------------------------------------------------------------------ */
        `VC`.`Estatus_Curso`               AS `Estatus_Texto`, -- (ej: "FINALIZADO", "CANCELADO")

        `VC`.`Observaciones`               AS `Bitacora_Notas`,           -- Justificación de esta versión

        /* ------------------------------------------------------------------
           GRUPO F: BANDERAS LÓGICAS (LOGIC FLAGS - CRITICAL)
           Aquí reside la inteligencia arquitectónica. Entregamos el estado físico puro.
           Laravel usará esto para: if (Estatus_Del_Registro == 1 && User->isAdmin()) { ... }
           ------------------------------------------------------------------ */
        `Cap`.`Activo`                     AS `Estatus_Del_Registro` -- 1 = Expediente Vivo / 0 = Archivado (Soft Delete)

    /* ============================================================================================
       FASE 2: ORIGEN DE DATOS Y RELACIONES (RELATIONAL ASSEMBLY)
       Propósito: Ensamblar la vista maestra asegurando integridad histórica.
       ============================================================================================ */
    FROM `PICADE`.`Vista_Capacitaciones` `VC`
    
    /* [JOIN 1]: ENLACE CON PADRE (Para leer Estatus Global `Cap.Activo`) */
    INNER JOIN `PICADE`.`Capacitaciones` `Cap` 
        ON `VC`.`Id_Capacitacion` = `Cap`.`Id_Capacitacion`

    /* [JOIN 2]: FILTRO DE ACTUALIDAD (MAX ID SNAPSHOT)
       Evita traer versiones obsoletas del mismo folio. Solo la última foto es válida. */
    INNER JOIN (
        SELECT MAX(Id_DatosCap) as MaxId 
        FROM `PICADE`.`DatosCapacitaciones` 
        GROUP BY Fk_Id_Capacitacion
    ) `Latest_Row` ON `VC`.`Id_Detalle_de_Capacitacion` = `Latest_Row`.MaxId

    /* ============================================================================================
       FASE 3: MOTOR DE BÚSQUEDA GLOBAL (SEARCH ENGINE)
       Propósito: Escanear múltiples vectores sin restricción de fechas.
       ============================================================================================ */
    WHERE 
        (
            /* Vector 1: Identidad del Curso */
            `VC`.`Numero_Capacitacion` LIKE CONCAT('%', _TerminoBusqueda, '%')
            OR
            /* Vector 2: Cliente Interno */
            `VC`.`Clave_Gerencia_Solicitante` LIKE CONCAT('%', _TerminoBusqueda, '%')
            OR
            /* Vector 3: Contenido Académico */
            `VC`.`Codigo_Tema` LIKE CONCAT('%', _TerminoBusqueda, '%')
        )

    /* ============================================================================================
       FASE 4: ORDENAMIENTO (UX SORTING)
       Propósito: Priorizar lo más reciente para aumentar la relevancia del hallazgo.
       ============================================================================================ */
    ORDER BY `VC`.`Fecha_Inicio` DESC;
    /* NOTA: Se eliminó el LIMIT para permitir auditorías exhaustivas si es necesario. */

END$$

DELIMITER ;

/* ====================================================================================================
   PROCEDIMEINTO: SP_Dashboard_ResumenGerencial_
   ====================================================================================================

   ----------------------------------------------------------------------------------------------------
   I. CONTEXTO OPERATIVO Y PROPÓSITO
   ----------------------------------------------------------------------------------------------------
   [QUÉ ES]: 
   Motor de analítica segmentada por Unidades de Negocio (Gerencias).
   Genera las "Micro-Tarjetas" que aparecen sobre el Grid Principal cuando se selecciona un año.

   [OBJETIVO DE NEGOCIO]: 
   Responder instantáneamente: "¿Quién está capacitándose más este año?" y "¿Quién tiene más cancelaciones?".
   
   [INTERACCIÓN UI]:
   Cada tarjeta devuelta contiene el `Id_Gerencia`. Al dar clic en una tarjeta, el Frontend debe:
   1. Tomar ese ID.
   2. Recargar `SP_ObtenerMatrizPICADE` pasando ese ID como filtro.

   ----------------------------------------------------------------------------------------------------
   II. ESTRATEGIA TÉCNICA
   ----------------------------------------------------------------------------------------------------
   - "Time-Boxed Analytics": A diferencia del resumen anual, este reporte es sensible al contexto temporal.
     Solo calcula métricas dentro de la ventana de tiempo solicitada (ej: Año Fiscal Actual).
   - "Hardcoded ID Optimization": Uso de IDs fijos (4=Fin, 8=Canc) para velocidad extrema.
   - "Latest Snapshot": Filtra duplicados históricos para no inflar los números de las gerencias.

   ----------------------------------------------------------------------------------------------------
   III. CONTRATO DE INTERFAZ
   ----------------------------------------------------------------------------------------------------
   - INPUT: _Fecha_Min, _Fecha_Max (Define el "Tablero" actual).
   - OUTPUT: Lista de Gerencias con sus KPIs, ordenada por volumen de operación (Mayor a menor).
   ==================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_Dashboard_ResumenGerencial`$$

CREATE PROCEDURE `SP_Dashboard_ResumenGerencial`(
    IN _Fecha_Min DATE, -- Inicio del Periodo (ej: '2026-01-01')
    IN _Fecha_Max DATE  -- Fin del Periodo    (ej: '2026-12-31')
)
THIS_PROC: BEGIN

/* ============================================================================================
   FASE 0: PROGRAMACIÓN DEFENSIVA
   ============================================================================================ */
   
	-- Validación 1: Campos obligatorios
	IF _Fecha_Min IS NULL OR _Fecha_Max IS NULL THEN
		SIGNAL SQLSTATE '45000' 
		SET MESSAGE_TEXT = 'ERROR [400]: Se requiere un rango de fechas para calcular el resumen gerencial.';
	END IF;

	-- Validación 2: Anti-Paradoja Temporal (NUEVA)
	IF _Fecha_Min > _Fecha_Max THEN
		SIGNAL SQLSTATE '45000' 
		SET MESSAGE_TEXT = 'ERROR [400]: La fecha de inicio no puede ser posterior a la fecha de fin.';
	END IF;

    /* ============================================================================================
       FASE 1: CÁLCULO DE KPIs POR GERENCIA
       ============================================================================================ */
    SELECT 
        /* --- IDENTIDAD DE LA TARJETA (Para el Click en UI) --- */
        `Ger`.`Id_CatGeren`                AS `Id_Filtro`,   -- El ID que se enviará a la Matriz
        `Ger`.`Clave`                      AS `Clave_Gerencia`,
        `Ger`.`Nombre`                     AS `Nombre_Gerencia`, -- (Opcional, si es muy largo usar Clave)

        /* --- KPI: VOLUMEN OPERATIVO --- */
        COUNT(DISTINCT `Cap`.`Numero_Capacitacion`) AS `Total_Cursos`,

        /* --- KPI: DESGLOSE DE SALUD (SEMAFORIZACIÓN) --- */
        /* Verdes: Finalizados (ID 4)  
           Suma Finalizados (4) Y Archivados (10).
           Lógica: Si está archivado, es porque se finalizó correctamente. */
        SUM(CASE 
            WHEN `DC`.`Fk_Id_CatEstCap` IN (4, 10) THEN 1 
            ELSE 0 
        END) AS `Finalizados`,
        
        /* Rojos: Cancelados (ID 8) */
        SUM(CASE WHEN `DC`.`Fk_Id_CatEstCap` = 8 THEN 1 ELSE 0 END) AS `Cancelados`,
        
        /* Azules/Amarillos: En Proceso (Ni Fin, Ni Canc, Ni Arch) */
        SUM(CASE WHEN `DC`.`Fk_Id_CatEstCap` NOT IN (4, 8, 10) THEN 1 ELSE 0 END) AS `En_Proceso`,

        /* --- KPI: IMPACTO HUMANO --- */
        -- SUM(`DC`.`AsistentesReales`)       AS `Personas_Impactadas`
        SUM(
            GREATEST(
                COALESCE(`DC`.`AsistentesReales`, 0), 
                (
				SELECT COUNT(*) 
                FROM `PICADE`.`Capacitaciones_Participantes` `CP` 
				WHERE `CP`.`Fk_Id_DatosCap` = `DC`.`Id_DatosCap`
                AND `CP`.`Fk_Id_CatEstPart` != 5)
            )
        )                                  AS `Personas_Impactadas`

    /* ============================================================================================
       FASE 2: ORIGEN DE DATOS (JOINS & SNAPSHOT)
       ============================================================================================ */
    FROM `PICADE`.`DatosCapacitaciones` `DC`

    /* Join con Padre para obtener la Gerencia */
    INNER JOIN `PICADE`.`Capacitaciones` `Cap` 
        ON `DC`.`Fk_Id_Capacitacion` = `Cap`.`Id_Capacitacion`

    /* Join con Catálogo de Gerencias (Para obtener Clave y Nombre) */
    INNER JOIN `PICADE`.`Cat_Gerencias_Activos` `Ger` 
        ON `Cap`.`Fk_Id_CatGeren` = `Ger`.`Id_CatGeren`

    /* Join de Unicidad (Latest Snapshot) */
    INNER JOIN (
        SELECT MAX(`Id_DatosCap`) as `MaxId` 
        FROM `PICADE`.`DatosCapacitaciones` 
        GROUP BY `Fk_Id_Capacitacion`
    ) `Latest` ON `DC`.`Id_DatosCap` = `Latest`.`MaxId`

    /* ============================================================================================
       FASE 3: FILTRADO Y AGRUPACIÓN
       ============================================================================================ */
    WHERE 
        /* Solo mostramos gerencias que tuvieron actividad en ESTE periodo */
        (`DC`.`Fecha_Inicio` BETWEEN _Fecha_Min AND _Fecha_Max)
        
        /* Opcional: Si quieres excluir expedientes archivados globalmente, descomenta esto: */
        -- AND `Cap`.`Activo` = 1 

    GROUP BY 
        `Ger`.`Id_CatGeren`, 
        `Ger`.`Clave`, 
        `Ger`.`Nombre`

    /* ============================================================================================
       FASE 4: ORDENAMIENTO (UX)
       ============================================================================================ */
    /* Las gerencias con más carga de trabajo aparecen primero (Izquierda a Derecha en UI) */
    ORDER BY `Total_Cursos` DESC;

END$$

DELIMITER ;

/* ============================================================================================
   SECCIÓN: CONSULTAS ESPECÍFICAS (PARA EDICIÓN / DETALLE)
   ============================================================================================
   Estas rutinas son críticas para la UX administrativa. No solo devuelven el dato pedido, sino 
   que garantizan la integridad de lectura antes de permitir una operación de modificación.
   ============================================================================================ */
   
   /* ====================================================================================================
   PROCEDIMIENTO: SP_ConsultarCapacitacionEspecifica_
   ====================================================================================================
   
   1. FICHA TÉCNICA (TECHNICAL DATASHEET)
   --------------------------------------
   - Tipo de Artefacto:  Procedimiento Almacenado de Recuperación Compuesta (Composite Retrieval SP)
   - Patrón de Diseño:   "Master-Detail-History Aggregation" (Agregación Maestro-Detalle-Historia)
   - Nivel de Aislamiento: READ COMMITTED (Lectura Confirmada)
   
   2. VISIÓN DE NEGOCIO (BUSINESS VALUE PROPOSITION)
   -------------------------------------------------
   Este procedimiento actúa como el "Motor de Reconstrucción Forense" del sistema. 
   Su objetivo es materializar el estado exacto de una capacitación en un punto específico del tiempo ("Snapshot").
   
   Soluciona tres necesidades críticas del Coordinador Académico en una sola transacción:
     A) Consciencia Situacional (Header): ¿Qué es este curso y en qué estado se encuentra hoy?
     B) Gestión de Capital Humano (Body): ¿Quiénes asistieron exactamente a ESTA versión del curso?
     C) Auditoría de Trazabilidad (Footer): ¿Quién modificó el curso, cuándo y por qué razón?

   3. ESTRATEGIA DE AUDITORÍA (FORENSIC IDENTITY STRATEGY)
   -------------------------------------------------------
   Implementa una "Doble Verificación de Identidad" para distinguir responsabilidades:
     - Autor Intelectual (Origen): Se extrae de la tabla Padre (`Capacitaciones`). Revela quién creó el folio.
     - Autor Material (Versión): Se extrae de la tabla Hija (`DatosCapacitaciones`). Revela quién hizo el último cambio.

   4. INTERFAZ DE SALIDA (MULTI-RESULTSET CONTRACT)
   ------------------------------------------------
   El SP devuelve 3 tablas secuenciales (Rowsets) optimizadas para consumo por PDO/Laravel:
     [SET 1 - HEADER]: Metadatos del Curso + Banderas de Estado + Auditoría de Origen/Edición.
     [SET 2 - BODY]:   Lista Nominal de Participantes vinculados a esta versión.
     [SET 3 - FOOTER]: Historial de Versiones (Log cronológico inverso).
   ==================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ConsultarCapacitacionEspecifica`$$

CREATE PROCEDURE `SP_ConsultarCapacitacionEspecifica`(
    /* ------------------------------------------------------------------------------------------------
       PARÁMETROS DE ENTRADA (INPUT CONTRACT)
       ------------------------------------------------------------------------------------------------
       [CRÍTICO]: Se recibe el ID del DETALLE (Hijo/Versión), NO del Padre. 
       Esto habilita la funcionalidad de "Máquina del Tiempo". Si el usuario selecciona una versión 
       antigua en el historial, este ID permite reconstruir el curso tal como era en el pasado.
       ------------------------------------------------------------------------------------------------ */
    IN _Id_Detalle_Capacitacion INT -- Puntero primario (PK) a la tabla `DatosCapacitaciones`.
)
THIS_PROC: BEGIN

    /* ------------------------------------------------------------------------------------------------
       DECLARACIÓN DE VARIABLES DE ENTORNO (CONTEXT VARIABLES)
       Contenedores temporales para mantener la integridad referencial durante la ejecución.
       ------------------------------------------------------------------------------------------------ */
    DECLARE v_Id_Padre_Capacitacion INT; -- Almacena el ID de la Carpeta Maestra para agrupar el historial.

    /* ================================================================================================
       BLOQUE 1: DEFENSA EN PROFUNDIDAD Y VALIDACIÓN (FAIL FAST STRATEGY)
       Objetivo: Proteger el motor de base de datos rechazando peticiones incoherentes antes de procesar.
       ================================================================================================ */
    
    /* 1.1 Validación de Integridad de Tipos (Type Safety Check) */
    /* Evitamos la ejecución de planes de consulta costosos si el input es nulo o negativo. */
    IF _Id_Detalle_Capacitacion IS NULL OR _Id_Detalle_Capacitacion <= 0 THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: El Identificador de la capacitación es inválido.';
    END IF;

    /* 1.2 Descubrimiento Jerárquico (Parent Discovery Logic) */
    /* Buscamos a qué "Expediente" (Padre) pertenece esta "Hoja" (Versión). 
       Utilizamos una consulta optimizada por índice primario para obtener el `Fk_Id_Capacitacion`. */
    SELECT `Fk_Id_Capacitacion` INTO v_Id_Padre_Capacitacion
    FROM `DatosCapacitaciones`
    WHERE `Id_DatosCap` = _Id_Detalle_Capacitacion
    LIMIT 1;

    /* 1.3 Verificación de Existencia (404 Not Found Handling) */
    /* Si la variable sigue siendo NULL después del SELECT, significa que el registro no existe físicamente.
       Lanzamos un error semántico para informar al Frontend y detener la ejecución. */
    IF v_Id_Padre_Capacitacion IS NULL THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [404]: La capacitación solicitada no existe en los registros.';
    END IF;

    /* ================================================================================================
       BLOQUE 2: RESULTSET 1 - CONTEXTO OPERATIVO Y AUDITORÍA (HEADER)
       Objetivo: Entregar los datos maestros del curso unificando Padre e Hijo.
       Complejidad: Media (Múltiples JOINs para resolución de identidades).
       ================================================================================================ */
       
    SELECT 
        /* -----------------------------------------------------------
           GRUPO A: IDENTIDAD DEL EXPEDIENTE (INMUTABLES - TABLA PADRE)
           Datos que definen la esencia del curso y no cambian con las ediciones.
           ----------------------------------------------------------- */
        `VC`.`Id_Capacitacion`,             -- ID Interno del Padre (Para referencias)
        `VC`.`Id_Detalle_de_Capacitacion`,  -- ID de la versión que estamos viendo (PK Actual)
        `VC`.`Numero_Capacitacion`         AS `Folio`,     -- Llave de Negocio (ej: CAP-2026-001)
        `VC`.`Clave_Gerencia_Solicitante`  AS `Gerencia`,  -- Dueño del Presupuesto (Cliente Interno)
        `VC`.`Nombre_Tema`                 AS `Tema`,      -- Materia Académica
        `VC`.`Tipo_Instruccion`            AS `Tipo_de_Capacitacion`, -- Clasificación (Teórico/Práctico)
        `VC`.`Duracion_Horas`              AS `Duracion`,  -- Metadata Académica

        /* -----------------------------------------------------------
           GRUPO B: CONFIGURACIÓN OPERATIVA (MUTABLES - TABLA HIJA)
           Datos logísticos que pueden cambiar en cada versión.
           Se entregan pares ID + TEXTO para "hidratar" los formularios de edición (v-model).
           ----------------------------------------------------------- */
        /* [Recurso Humano] */
        `DC`.`Fk_Id_Instructor`            AS `Id_Instructor_Selected`, -- ID para el Select
        -- `VC`.`Nombre_Completo_Instructor`  AS `Instructor`,             -- Texto para leer
        `VC`.`Ficha_Instructor`,
        CONCAT(IFNULL(`VC`.`Nombre_Instructor`,''), ' ', IFNULL(`VC`.`Apellido_Paterno_Instructor`,''), ' ', IFNULL(`VC`.`Apellido_Materno_Instructor`,'')) AS `Instructor`,
        
        /* [Infraestructura] */
        `DC`.`Fk_Id_CatCases_Sedes`        AS `Id_Sede_Selected`,
        `VC`.`Nombre_Sede`                 AS `Sede`,
        
        /* [Metodología] */
        `DC`.`Fk_Id_CatModalCap`           AS `Id_Modalidad_Selected`,
        `VC`.`Nombre_Modalidad`            AS `Modalidad`,
        
        /* -----------------------------------------------------------
           GRUPO C: DATOS DE EJECUCIÓN (ESCALARES)
           Valores directos para visualización o edición.
           ----------------------------------------------------------- */
        `DC`.`Fecha_Inicio`,
        `DC`.`Fecha_Fin`,

        /* [KPIs de Cobertura] 
        `VC`.`Asistentes_Meta`             AS `Cupo_Programado_de_Asistentes`,
        `VC`.`Asistentes_Manuales`, -- El campo que pueden editar*/
        
        /* [OPTIMIZACIÓN]: Dato directo de la vista       
		/* [NUEVO] CAMPOS DIRECTOS DE LA VISTA 
        `VC`.`Participantes_Activos`       AS `Inscritos_en_Sistema`,   -- El dato automático
        `VC`.`Total_Impacto_Real`          AS `Total_de_Asistentes_Reales`,         -- El resultado final (GREATEST)
        `VC`.`Participantes_Baja` 		   AS `Total_de_Bajas`,
        `VC`.`Cupo_Disponible`,*/
        
		/* ------------------------------------------------------------------
           GRUPO D: ANALÍTICA (KPIs)
           Métricas rápidas para visualización en el grid.
           ------------------------------------------------------------------ 
        /* -----------------------------------------------------------------------------------------
           [KPIs DE PLANEACIÓN - PLANIFICADO]
           Datos estáticos definidos al crear el curso. Representan la "Meta".
           ----------------------------------------------------------------------------------------- */

        -- Capacidad máxima teórica del aula o sala virtual.
        `VC`.`Asistentes_Meta`             AS `Cupo_Programado_de_Asistentes`,
        
        -- Cantidad de asientos reservados manualmente por el coordinador (Override).
        -- Este valor tiene precedencia sobre el conteo automático en caso de ser mayor.
        -- `VC`.`Asistentes_Manuales`, 
        
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
        `VC`.`Cupo_Disponible`,
        
		/* [Ciclo de Vida] */
        `DC`.`Fk_Id_CatEstCap`             AS `Id_Estatus_Selected`,
        `VC`.`Estatus_Curso`               AS `Estatus_del_Curso`,
        -- `VC`.`Codigo_Estatus`              AS `Codigo_Estatus_Global`, -- Meta-dato para colorear badges en UI

        `DC`.`Observaciones`               AS `Bitacora_Notas`, -- Justificación técnica del cambio
        
        /* -----------------------------------------------------------
           GRUPO D: BANDERAS DE LÓGICA DE NEGOCIO (RAW STATE FLAGS)
           [IMPORTANTE]: El SP no decide si se puede editar. Entrega el estado crudo.
           Laravel usará esto: if (Registro=1 AND Detalle=1 AND Rol=Coord) -> AllowEdit.
           ----------------------------------------------------------- */
        `Cap`.`Activo`                     AS `Estatus_Del_Registro`,  -- 1 = Expediente Vivo / 0 = Archivado Globalmente
        `DC`.`Activo`                      AS `Estatus_Del_Detalle`,   -- 1 = Versión Vigente / 0 = Versión Histórica (Snapshot)

        /* -----------------------------------------------------------
           GRUPO E: AUDITORÍA FORENSE DIFERENCIADA (ORIGEN VS VERSIÓN ACTUAL)
           Aquí aplicamos la lógica de "Quién hizo qué" separando los momentos.
           ----------------------------------------------------------- */
        
        /* [MOMENTO 1: EL ORIGEN] - Datos provenientes de la Tabla PADRE (`Capacitaciones`) */
        /* ¿Cuándo nació el folio CAP-202X? */
        `Cap`.`created_at`                 AS `Fecha_Creacion_Original`,
        
        /* ¿Quién creó el folio? (Join Manual hacia el creador del Padre) */
        CONCAT(IFNULL(`IP_Creator`.`Nombre`,''), ' ', IFNULL(`IP_Creator`.`Apellido_Paterno`,'')) AS `Creado_Originalmente_Por`,

        /* [MOMENTO 2: LA VERSIÓN] - Datos provenientes de la Tabla HIJA (`DatosCapacitaciones`) */
        /* ¿Cuándo se guardó esta modificación específica? */
        `DC`.`created_at`                  AS `Fecha_Ultima_Modificacion`, 
        
        /* ¿Quién firmó esta modificación? (Join hacia el creador del Hijo) */
        CONCAT(IFNULL(`IP_Editor`.`Nombre`,''), ' ', IFNULL(`IP_Editor`.`Apellido_Paterno`,'')) AS `Ultima_Actualizacion_Por`

    /* ------------------------------------------------------------------------------------------------
       ORIGEN DE DATOS Y ESTRATEGIA DE VINCULACIÓN (JOIN STRATEGY)
       ------------------------------------------------------------------------------------------------ */
    FROM `PICADE`.`DatosCapacitaciones` `DC` -- [FUENTE PRIMARIA]: El detalle específico solicitado
    
    /* JOIN 1: VISTA MAESTRA (Abstraction Layer) */
    /* Usamos la vista para obtener nombres pre-formateados y evitar repetir lógica de concatenación */
    INNER JOIN `PICADE`.`Vista_Capacitaciones` `VC` 
        ON `DC`.`Id_DatosCap` = `VC`.`Id_Detalle_de_Capacitacion`
    
    /* JOIN 2: TABLA PADRE (Source of Truth) */
    /* Vital para obtener el Estatus Global y los datos de auditoría de creación original */
    INNER JOIN `PICADE`.`Capacitaciones` `Cap`      
        ON `DC`.`Fk_Id_Capacitacion` = `Cap`.`Id_Capacitacion`
    
    /* JOIN 3: RESOLUCIÓN DE AUDITORÍA (EDITOR) */
    /* Conectamos la FK del HIJO (`DatosCapacitaciones`) con Usuarios -> InfoPersonal */
    LEFT JOIN `PICADE`.`Usuarios` `U_Editor`        
        ON `DC`.`Fk_Id_Usuario_DatosCap_Created_by` = `U_Editor`.`Id_Usuario`
    LEFT JOIN `PICADE`.`Info_Personal` `IP_Editor`  
        ON `U_Editor`.`Fk_Id_InfoPersonal` = `IP_Editor`.`Id_InfoPersonal`

    /* JOIN 4: RESOLUCIÓN DE AUDITORÍA (CREADOR) */
    /* Conectamos la FK del PADRE (`Capacitaciones`) con Usuarios -> InfoPersonal */
    LEFT JOIN `PICADE`.`Usuarios` `U_Creator`       
        ON `Cap`.`Fk_Id_Usuario_Cap_Created_by` = `U_Creator`.`Id_Usuario`
    LEFT JOIN `PICADE`.`Info_Personal` `IP_Creator` 
        ON `U_Creator`.`Fk_Id_InfoPersonal` = `IP_Creator`.`Id_InfoPersonal`
    
    /* FILTRO MAESTRO */
    WHERE `DC`.`Id_DatosCap` = _Id_Detalle_Capacitacion;

    /* ================================================================================================
       BLOQUE 3: RESULTSET 2 - NÓMINA DE PARTICIPANTES (BODY)
       Objetivo: Listar a las personas vinculadas estrictamente a ESTA versión del curso.
       Nota: Si estamos viendo una versión histórica, veremos a los alumnos tal como estaban en ese momento.
       Fuente: `Vista_Gestion_de_Participantes` (Vista optimizada para gestión escolar).
       ================================================================================================ */
    
    SELECT
    
        /* -----------------------------------------------------------------------------------------
           [IDENTIFICADORES DE ACCIÓN - CRUD HANDLES]
           Datos técnicos ocultos necesarios para las operaciones de actualización.
           ----------------------------------------------------------------------------------------- */
        
        -- Llave Primaria (PK) de la relación Alumno-Curso.
        -- Este ID se envía al `SP_EditarParticipanteCapacitacion` o `SP_CambiarEstatus...`.
        `Id_Registro_Participante`    AS `Id_Inscripcion`,      -- PK para operaciones CRUD sobre el alumno

        /* -----------------------------------------------------------------------------------------
           [INFORMACIÓN VISUAL DEL PARTICIPANTE]
           Datos para que el humano identifique al alumno.
           ----------------------------------------------------------------------------------------- */
        
        -- ID Corporativo o Número de Empleado. Vital para diferenciar homónimos.
        `Ficha_Participante`          AS `Ficha`,

        -- Nombre Completo Normalizado.
        -- Se concatenan Paterno + Materno + Nombre para alinearse con los estándares
        -- de listas de asistencia impresas (orden alfabético por apellido).
        /* Nombre formateado estilo lista de asistencia oficial (Paterno Materno Nombre) */
        CONCAT(
			`Ap_Paterno_Participante`, ' ',
            `Ap_Materno_Participante`, ' ', 
            `Nombre_Pila_Participante`) AS `Nombre_Alumno`,

        /* -----------------------------------------------------------------------------------------
           [INPUTS ACADÉMICOS EDITABLES]
           Datos que el coordinador puede modificar directamente en el grid.
           ----------------------------------------------------------------------------------------- */
        
        -- Porcentaje de Asistencia (0.00 - 100.00).
        -- Alimenta la barra de progreso visual en el Frontend.
        `Porcentaje_Asistencia`       AS `Asistencia`,          -- 0-100%

        -- Calificación Final Asentada (0.00 - 100.00).
        -- Si es NULL, el Frontend debe mostrar un input vacío o "Sin Evaluar".
        `Calificacion_Numerica`       AS `Calificacion`,        -- 0-10

        /* -----------------------------------------------------------------------------------------
           [ESTADO DEL CICLO DE VIDA Y AUDITORÍA]
           Datos de control de flujo y trazabilidad.
           ----------------------------------------------------------------------------------------- */
        
        -- Estatus Semántico (Texto).
        -- Valores posibles: 'INSCRITO', 'ASISTIÓ', 'APROBADO', 'REPROBADO', 'BAJA'.
        -- Se usa para determinar el color de la fila (ej: Baja = Rojo, Aprobado = Verde).
        `Resultado_Final`             AS `Estatus_Alumno`,      -- Texto: Aprobado/Reprobado/Baja

        -- Descripción Técnica.
        -- Explica la regla de negocio aplicada (ej: "Reprobado por inasistencia > 20%").
        -- Se usa típicamente en un Tooltip al pasar el mouse sobre el estatus.
        `Detalle_Resultado`           AS `Descripcion_Estatus`,  -- Tooltip explicativo
        
        -- [AUDITORÍA FORENSE INYECTADA]:
        -- Contiene la cadena histórica de cambios (Timestamp + Motivo).
        -- Permite al coordinador saber por qué un alumno tiene una calificación extraña
        -- o por qué fue reactivado después de una baja.
        /* [NUEVO] Agregamos la justificación para verla en la tabla */
        `Nota_Auditoria`              AS `Justificacion`

    FROM `PICADE`.`Vista_Gestion_de_Participantes`
	
    -- Filtro estricto por la instancia del curso.
    WHERE `Id_Detalle_de_Capacitacion` = _Id_Detalle_Capacitacion

    /* -----------------------------------------------------------------------------------------
       [ESTRATEGIA DE ORDENAMIENTO - UX STANDARD]
       Ordenamos alfabéticamente por Apellido Paterno -> Materno -> Nombre.
       Esto es mandatorio para facilitar el cotejo visual contra listas físicas o de Excel.
       ----------------------------------------------------------------------------------------- */
    /* ORDENAMIENTO ESTRICTO: Alfabético por Apellido Paterno para facilitar el pase de lista */
    ORDER BY `Ap_Paterno_Participante` ASC, `Ap_Materno_Participante` ASC, `Nombre_Pila_Participante` ASC;

    /* ================================================================================================
       BLOQUE 4: RESULTSET 3 - LÍNEA DE TIEMPO HISTÓRICA (FOOTER)
       Objetivo: Reconstruir la historia completa del expediente (Padre) para navegación forense.
       Lógica: Busca a todos los "Hermanos" (registros que comparten el mismo Padre) y los ordena.
       ================================================================================================ */
    SELECT 
        /* Identificadores Técnicos para Navegación */
        `H_VC`.`Id_Detalle_de_Capacitacion` AS `Id_Version_Historica`, -- ID que se enviará al recargar este SP
        
        /* Momento exacto del cambio (Timestamp) */
        -- `H_VC`.`Fecha_Creacion_Detalle`     AS `Fecha_Movimiento`,
        `H_DC`.`created_at`                 AS `Fecha_Movimiento`,

        
        /* Responsable del Cambio (Auditoría Histórica) */
        /* Obtenido mediante JOINs manuales en este bloque */
        CONCAT(IFNULL(`H_IP`.`Apellido_Paterno`,''), ' ', IFNULL(`H_IP`.`Nombre`,'')) AS `Responsable_Cambio`,
        
        /* Razón del Cambio (El "Por qué") */
        `H_VC`.`Observaciones`              AS `Justificacion_Cambio`,
        
        /* Snapshot de Datos Clave (Para previsualización rápida en la lista) */
        -- `H_VC`.`Nombre_Completo_Instructor` AS `Instructor_En_Ese_Momento`,
        CONCAT(IFNULL(`H_VC`.`Nombre_Instructor`,''), ' ', IFNULL(`H_VC`.`Apellido_Paterno_Instructor`,''), ' ', IFNULL(`H_VC`.`Apellido_Materno_Instructor`,'')) AS `Instructor_En_Ese_Momento`,
        `H_VC`.`Nombre_Sede`                AS `Sede_En_Ese_Momento`,
        `H_VC`.`Estatus_Curso`              AS `Estatus_En_Ese_Momento`,
        `H_VC`.`Fecha_Inicio`               AS `Fecha_Inicio_Programada`,
        `H_VC`.`Fecha_Fin`                  AS `Fecha_Fin_Programada`,
        
        /* --- UX MARKER (MARCADOR DE POSICIÓN) --- */
        /* Compara el ID de la fila histórica con el ID solicitado al inicio del SP.
           Si coinciden, devuelve 1. Esto permite al Frontend pintar la fila de color (ej: "Usted está aquí"). */
        CASE 
            WHEN `H_VC`.`Id_Detalle_de_Capacitacion` = _Id_Detalle_Capacitacion THEN 1 
            ELSE 0 
        END                                 AS `Es_Version_Visualizada`,
        
        /* Bandera de Vigencia Real (Solo la última versión tendrá 1, el resto 0) */
        `H_VC`.`Estatus_del_Registro`       AS `Es_Vigente`

    FROM `PICADE`.`Vista_Capacitaciones` `H_VC`
    
    /* JOIN MANUAL PARA AUDITORÍA HISTÓRICA */
    /* Necesario porque la Vista no expone los IDs de usuario creador por defecto.
       Vamos a las tablas físicas para recuperar quién creó cada versión antigua. */
    LEFT JOIN `PICADE`.`DatosCapacitaciones` `H_DC` 
        ON `H_VC`.`Id_Detalle_de_Capacitacion` = `H_DC`.`Id_DatosCap`
    LEFT JOIN `PICADE`.`Usuarios` `H_U`             
        ON `H_DC`.`Fk_Id_Usuario_DatosCap_Created_by` = `H_U`.`Id_Usuario`
    LEFT JOIN `PICADE`.`Info_Personal` `H_IP`       
        ON `H_U`.`Fk_Id_InfoPersonal` = `H_IP`.`Id_InfoPersonal`
    
    /* FILTRO DE AGRUPACIÓN: Trae a todos los registros vinculados al mismo PADRE descubierto en el Bloque 1 */
    WHERE `H_VC`.`Id_Capacitacion` = v_Id_Padre_Capacitacion 
    
    /* ORDENAMIENTO: Cronológico Inverso (Lo más reciente arriba) para lectura natural */
    ORDER BY `H_VC`.`Id_Detalle_de_Capacitacion` DESC;

END$$

DELIMITER ;

/* ====================================================================================================
   PROCEDIMIENTO: SP_EditarCapacitacion
   ====================================================================================================
   
   SECCIÓN 1: FICHA TÉCNICA DEL ARTEFACTO (ARTIFACT DATASHEET)
   ----------------------------------------------------------------------------------------------------
   - Nombre Lógico:      Motor de Versionado y Edición Forense de Cursos
   - Tipo de Artefacto:  Procedimiento Almacenado de Transacción Compuesta (Composite Transaction SP)
   - Nivel de Aislamiento: SERIALIZABLE (Implícito por bloqueos de escritura en InnoDB)
   - Patrón de Diseño:   "Append-Only Ledger with State Relinking" 
     (Libro Mayor de Solo Agregación con Re-enlace de Estado)

   SECCIÓN 2: VISIÓN DE NEGOCIO Y ESPECIFICACIÓN LÓGICA (BUSINESS VALUE & LOGIC)
   ----------------------------------------------------------------------------------------------------
   Este procedimiento actúa como el "Motor de Versionado Forense". Su objetivo es permitir la modificación
   de las condiciones operativas de un curso SIN DESTRUIR LA EVIDENCIA HISTÓRICA.
   
   [PRINCIPIO DE INMUTABILIDAD]:
   En lugar de sobrescribir el registro actual (UPDATE destructivo), este motor implementa el siguiente ciclo:
     1. Validación Forense: Verifica que la versión a editar sea la VIGENTE (Activo=1) usando "Optimistic Locking".
     2. Versionado (Branching): Crea una nueva versión "Hija" en `DatosCapacitaciones` con los cambios.
     3. Archivado (Soft Delete): Marca la versión anterior como "Histórica" (Activo=0).
     4. Re-enlace (Relinking): Mueve masivamente los punteros de los alumnos inscritos hacia la nueva versión,
        garantizando la integridad referencial y optimizando el espacio (evita duplicidad).

   SECCIÓN 3: ESTRATEGIA DE DEFENSA CONTRA CORRUPCIÓN (ANTI-CORRUPTION LAYER)
   ----------------------------------------------------------------------------------------------------
   Implementa un blindaje de triple nivel para garantizar la integridad:
     - Nivel 1 (Integridad del Padre): Verifica existencia del expediente maestro antes de crear ramas.
     - Nivel 2 (Integridad del Historial): Protege contra condiciones de carrera. Si alguien más archivó
       la versión 1 milisegundo antes, la operación se bloquea para evitar ramas huérfanas.
     - Nivel 3 (Integridad de los Hijos): Ejecuta un RE-ENLACE transaccional (Atomic Relinking). 
       Si el curso tiene 50 alumnos, los 50 se mueven atómicamente; si uno falla, falla todo.

   SECCIÓN 4: ARQUITECTURA DE DATOS (DEPENDENCY & I/O MAPPING)
   ----------------------------------------------------------------------------------------------------
   [DEPENDENCIAS]:
     - Entrada (Padres): DatosCapacitaciones, Capacitaciones, Usuarios, Catálogos.
     - Salida (Afectadas): DatosCapacitaciones (INSERT/UPDATE), Capacitaciones_Participantes (UPDATE).
   
   [MAPA DE ENTRADA - UX SYNCHRONIZATION]:
     Los parámetros siguen el flujo visual:
     [0] Contexto Técnico (IDs) -> [1] Configuración (Recursos) -> [2] Tiempo -> [3] Métricas.

   [CÓDIGOS DE RETORNO]:
     - EXITOSO: ID Nueva Versión + Feedback con conteo de alumnos movidos.
     - ERRORES: 404 (No existe), 409 (No vigente/Conflicto), 400 (Datos inválidos).
   ==================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_EditarCapacitacion`$$

CREATE PROCEDURE `SP_EditarCapacitacion`(
    /* --------------------------------------------------------------------------------------------
       [GRUPO 0]: CONTEXTO TÉCNICO Y DE AUDITORÍA
       Datos invisibles para el usuario pero vitales para la integridad del sistema.
       -------------------------------------------------------------------------------------------- */
    IN _Id_Version_Anterior INT,       -- Puntero a la versión que se está visualizando/editando (Origen).
    IN _Id_Usuario_Editor   INT,       -- ID del usuario que firma legalmente este cambio.

    /* --------------------------------------------------------------------------------------------
       [GRUPO 1]: CONFIGURACIÓN OPERATIVA (MUTABLES ESTRUCTURALES)
       Datos que definen la "Forma" del curso.
       -------------------------------------------------------------------------------------------- */
    IN _Id_Instructor       INT,       -- Nuevo Recurso Humano responsable.
    IN _Id_Sede             INT,       -- Nueva Ubicación física/virtual.
    IN _Id_Modalidad        INT,       -- Nuevo Formato de entrega.
    IN _Id_Estatus          INT,       -- Nuevo Estado del flujo (ej: De 'Programado' a 'Reprogramado').

    /* --------------------------------------------------------------------------------------------
       [GRUPO 2]: DATOS DE EJECUCIÓN (MUTABLES TEMPORALES)
       Datos que definen el "Tiempo y Razón" del curso.
       -------------------------------------------------------------------------------------------- */
    IN _Fecha_Inicio        DATE,      -- Nueva fecha de arranque.
    IN _Fecha_Fin           DATE,      -- Nueva fecha de cierre.
    
    /* --------------------------------------------------------------------------------------------
       [GRUPO 3]: RESULTADOS (MÉTRICAS)
       Datos cuantitativos post-operativos.
       -------------------------------------------------------------------------------------------- */
    IN _Asistentes_Reales   INT,       -- Ajuste manual del conteo de asistencia (si aplica).
    IN _Observaciones       TEXT       -- [CRÍTICO]: Justificación forense del cambio. Es OBLIGATORIA.
)
THIS_PROC: BEGIN

    /* --------------------------------------------------------------------------------------------
       DECLARACIÓN DE VARIABLES DE ENTORNO (CONTEXT VARIABLES)
       Contenedores temporales para mantener el estado durante la transacción.
       -------------------------------------------------------------------------------------------- */
    DECLARE v_Id_Padre INT;            -- Almacena el ID del Expediente Maestro (Invariable).
    DECLARE v_Nuevo_Id INT;            -- Almacenará el ID generado para la nueva versión.
    DECLARE v_Es_Activo TINYINT(1);    -- Semáforo booleano para validaciones Anti-Zombie.
    DECLARE v_Version_Es_Vigente TINYINT(1); -- Bandera de estado de la versión origen.
    
    -- [AUDITORÍA]: Variable para capturar el conteo real de alumnos movidos antes del COMMIT.
    DECLARE v_Total_Movidos INT DEFAULT 0;

    /* --------------------------------------------------------------------------------------------
       HANDLER DE SEGURIDAD (FAIL-SAFE MECHANISM)
       En caso de cualquier error técnico (disco lleno, desconexión, FK rota), se ejecuta
       un ROLLBACK total para dejar la base de datos en su estado original inmaculado.
       -------------------------------------------------------------------------------------------- */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; 
    END;

    /* ============================================================================================
       BLOQUE 0: SANITIZACIÓN Y VALIDACIONES LÓGICAS (PRE-FLIGHT CHECK)
       Objetivo: Validar la coherencia de los datos antes de tocar la estructura.
       ============================================================================================ */
    
    /* 0.1 Limpieza de Strings */
    -- QUÉ: Elimina espacios en blanco y convierte cadenas vacías en NULL.
    -- PARA QUÉ: Evitar guardar basura o espacios invisibles en la base de datos.
    SET _Observaciones = NULLIF(TRIM(_Observaciones), '');

    /* 0.2 Validación Temporal (Time Integrity) */
    -- QUÉ: Verifica que la fecha de inicio sea menor o igual a la de fin.
    -- POR QUÉ: El tiempo es lineal. Un evento no puede terminar antes de empezar.
    IF _Fecha_Inicio > _Fecha_Fin THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE LÓGICA [400]: Fechas inválidas. La fecha de inicio es posterior a la fecha de fin.';
    END IF;

    /* 0.3 Validación de Justificación (Forensic Compliance) */
    -- QUÉ: Exige que el campo Observaciones tenga contenido.
    -- POR QUÉ: En un sistema auditado, no se permite alterar la historia sin documentar la razón ("Why").
    IF _Observaciones IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE AUDITORÍA [400]: La justificación (Observaciones) es obligatoria para realizar un cambio de versión.';
    END IF;

    /* ============================================================================================
       BLOQUE 1: VALIDACIÓN DE INTEGRIDAD ESTRUCTURAL (EL BLINDAJE)
       Objetivo: Evitar la corrupción del árbol genealógico del curso (Relación Padre-Hijo).
       ============================================================================================ */

    /* 1.1 Descubrimiento del Contexto (Parent & State Discovery) */
    -- QUÉ: Busca quién es el padre y en qué estado está la versión que queremos editar.
    -- CÓMO: Consulta directa por ID Primario (Index Look-up).
    SELECT `Fk_Id_Capacitacion`, `Activo` 
    INTO v_Id_Padre, v_Version_Es_Vigente
    FROM `DatosCapacitaciones` 
    WHERE `Id_DatosCap` = _Id_Version_Anterior 
    LIMIT 1;

    /* 1.2 Verificación de Existencia (404 Handling) */
    -- QUÉ: Valida si la consulta anterior encontró algo.
    -- PARA QUÉ: Evitar errores de referencia nula más adelante.
    IF v_Id_Padre IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR CRÍTICO [404]: La versión que intenta editar no existe en los registros. Por favor refresque su navegador.';
    END IF;

    /* 1.3 Verificación de Vigencia (Concurrency Protection) */
    -- QUÉ: Verifica que la versión sea la "Cabeza de Rama" actual (Activo=1).
    -- POR QUÉ: Previene condiciones de carrera (Race Conditions). Si dos usuarios editan al mismo tiempo,
    -- el primero gana y el segundo recibe este error para evitar crear ramas paralelas (bifurcaciones).
    IF v_Version_Es_Vigente = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'CONFLICTO DE INTEGRIDAD [409]: La versión que intenta editar YA NO ES VIGENTE. Alguien más modificó este curso recientemente. Por favor actualice la página para ver la última versión.';
    END IF;

    /* ============================================================================================
       BLOQUE 2: VALIDACIÓN DE RECURSOS (ANTI-ZOMBIE RESOURCES CHECK)
       Objetivo: Asegurar que no se asignen recursos (Instructores, Sedes) dados de baja.
       Se realizan consultas puntuales para verificar `Activo = 1` en cada catálogo.
       ============================================================================================ */
    
    /* 2.1 Verificación de Instructor */
    -- QUÉ: Valida que el Instructor exista y esté activo en la tabla de Usuarios e InfoPersonal.
    SELECT I.Activo INTO v_Es_Activo 
    FROM Usuarios U 
    INNER JOIN Info_Personal I ON U.Fk_Id_InfoPersonal = I.Id_InfoPersonal 
    WHERE U.Id_Usuario = _Id_Instructor LIMIT 1;
    
    IF v_Es_Activo IS NULL OR v_Es_Activo = 0 THEN 
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [409]: El Instructor seleccionado está inactivo o ha sido dado de baja.'; 
    END IF;

    /* 2.2 Verificación de Sede */
    -- QUÉ: Valida el catálogo de Sedes.
    SELECT `Activo` INTO v_Es_Activo FROM `Cat_Cases_Sedes` WHERE `Id_CatCases_Sedes` = _Id_Sede LIMIT 1;
    IF v_Es_Activo IS NULL OR v_Es_Activo = 0 THEN 
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [409]: La Sede seleccionada está clausurada o inactiva.'; 
    END IF;

    /* 2.3 Verificación de Modalidad */
    -- QUÉ: Valida el catálogo de Modalidades.
    SELECT `Activo` INTO v_Es_Activo FROM `Cat_Modalidad_Capacitacion` WHERE `Id_CatModalCap` = _Id_Modalidad LIMIT 1;
    IF v_Es_Activo IS NULL OR v_Es_Activo = 0 THEN 
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [409]: La Modalidad seleccionada no es válida actualmente.'; 
    END IF;

    /* 2.4 Verificación de Estatus */
    -- QUÉ: Valida el catálogo de Estatus.
    SELECT `Activo` INTO v_Es_Activo FROM `Cat_Estatus_Capacitacion` WHERE `Id_CatEstCap` = _Id_Estatus LIMIT 1;
    IF v_Es_Activo IS NULL OR v_Es_Activo = 0 THEN 
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [409]: El Estatus seleccionado está obsoleto o inactivo.'; 
    END IF;

    /* ============================================================================================
       BLOQUE 3: TRANSACCIÓN MAESTRA (ATOMIC WRITING)
       Punto de No Retorno. Iniciamos la escritura física en disco.
       ============================================================================================ */
    START TRANSACTION;

    /* --------------------------------------------------------------------------------------------
       PASO 3.1: CREACIÓN DE LA NUEVA VERSIÓN (VERSIONING)
       Insertamos la nueva realidad operativa (`DatosCapacitaciones`) vinculada al mismo Padre.
       -------------------------------------------------------------------------------------------- */
    INSERT INTO `DatosCapacitaciones` (
        `Fk_Id_Capacitacion`, `Fk_Id_Instructor`, `Fk_Id_CatCases_Sedes`, `Fk_Id_CatModalCap`, 
        `Fk_Id_CatEstCap`, `Fecha_Inicio`, `Fecha_Fin`, `Observaciones`, `AsistentesReales`, 
        `Activo`, `Fk_Id_Usuario_DatosCap_Created_by`, `created_at`, `updated_at`
    ) VALUES (
        v_Id_Padre, 
        _Id_Instructor, 
        _Id_Sede, 
        _Id_Modalidad, 
        _Id_Estatus, 
        _Fecha_Inicio, 
        _Fecha_Fin, 
        _Observaciones, 
        IFNULL(_Asistentes_Reales, 0), 
        1,                                           -- [REGLA]: La nueva versión nace VIVA (Vigente).
        _Id_Usuario_Editor,  
        NOW(), 
        NOW()
    );

    /* Captura crítica del ID generado para la migración de hijos */
    -- QUÉ: Obtenemos el ID autogenerado (Auto-Increment) de la inserción anterior.
    -- PARA QUÉ: Para usarlo como Foreign Key al mover a los participantes.
    SET v_Nuevo_Id = LAST_INSERT_ID();

    /* --------------------------------------------------------------------------------------------
       PASO 3.2: ARCHIVADO DE LA VERSIÓN ANTERIOR (HISTORICAL ARCHIVING)
       Marcamos la versión origen como "Histórica" (Activo=0).
       Esto garantiza que siempre exista UNA SOLA versión vigente por curso.
       -------------------------------------------------------------------------------------------- */
    UPDATE `DatosCapacitaciones` 
    SET `Activo` = 0 
    WHERE `Id_DatosCap` = _Id_Version_Anterior;

    /* --------------------------------------------------------------------------------------------
       PASO 3.3: ACTUALIZACIÓN DE HUELLA EN EL PADRE (GLOBAL AUDIT TRAIL)
       El expediente maestro (`Capacitaciones`) debe saber que fue modificado hoy.
       - Updated_by: Se actualiza al editor actual.
       - Created_by: SE RESPETA INTACTO (Autor Intelectual original).
       -------------------------------------------------------------------------------------------- */
    UPDATE `Capacitaciones`
    SET 
        `Fk_Id_Usuario_Cap_Updated_by` = _Id_Usuario_Editor,
        `updated_at` = NOW()
    WHERE `Id_Capacitacion` = v_Id_Padre;

    /* ============================================================================================
       BLOQUE 4: MIGRACIÓN DE NIETOS (ESTRATEGIA: ATOMIC RELINKING 🚀)
       Objetivo: Preservar la integridad de los participantes y su historial académico.
       
       [CAMBIO DE PARADIGMA]: ATOMIC RELINKING
       Anteriormente se usaba "Clonación" (INSERT SELECT). Ahora se usa "Re-enlace" (UPDATE).
       - Se actualiza el puntero `Fk_Id_DatosCap` de todos los alumnos inscritos en la versión anterior.
       - Los alumnos viajan a la nueva versión conservando sus calificaciones e historial.
       - Se evita la duplicidad de registros (Zero-Duplication Policy), manteniendo la base de datos ligera.
       ============================================================================================ */
    
    -- QUÉ: Ejecuta un UPDATE masivo sobre la tabla de participantes.
    -- CÓMO: Busca todos los registros que apuntaban a la versión vieja (`_Id_Version_Anterior`)
    --       y los redirige a la nueva versión (`v_Nuevo_Id`).
    -- CUÁNDO: Dentro de la misma transacción, asegurando consistencia atómica.
    UPDATE `Capacitaciones_Participantes`
    SET 
        `Fk_Id_DatosCap` = v_Nuevo_Id,           -- Apuntamos a la NUEVA versión
        `updated_at` = NOW(),                    -- Registramos el momento del movimiento
        `Fk_Id_Usuario_Updated_By` = _Id_Usuario_Editor -- Registramos quién autorizó el cambio
    WHERE `Fk_Id_DatosCap` = _Id_Version_Anterior;

    -- [AUDITORÍA]: Capturamos el conteo exacto de afectados ANTES del Commit.
    -- POR QUÉ: Porque el COMMIT resetea el contador ROW_COUNT a 0. Necesitamos esta evidencia.
    SET v_Total_Movidos = ROW_COUNT();

    /* ============================================================================================
       BLOQUE 5: COMMIT Y CONFIRMACIÓN
       Si llegamos aquí, la operación fue atómica y exitosa.
       ============================================================================================ */
    -- QUÉ: Escribe permanentemente los cambios en disco.
    COMMIT;
    
    /* Retorno de resultados para el Frontend */
    -- QUÉ: Devuelve un Result Set con metadata de la operación.
    -- PARA QUÉ: Para que la interfaz de usuario sepa qué pasó y pueda mostrar una notificación.
    SELECT 
        v_Nuevo_Id AS `New_Id_Detalle`,
        'EXITO'    AS `Status_Message`,
        CONCAT('Versión actualizada exitosamente. Se movieron ', v_Total_Movidos, ' expedientes de alumnos a la nueva versión (Sin duplicados).') AS `Feedback`;

END$$

DELIMITER ;

/* ====================================================================================================
   PROCEDIMIENTO: SP_CambiarEstatusCapacitacion
   ====================================================================================================
   
   ==========================================================================================================
      I. FICHA TÉCNICA DE INGENIERÍA (TECHNICAL DATASHEET)                                             
   ---------------------------------------------------------------------------------------------------------- 
      Nombre Oficial       : SP_CambiarEstatusCapacitacion                                             
      Alias Operativo      : "El Interruptor Maestro" / "The Toggle Switch"                                             
      Clasificación        : Transacción de Gobernanza de Ciclo de Vida                                
                             (Lifecycle Governance Transaction)                                         
      Patrón de Diseño     : "Explicit Toggle Switch with State Validation & Audit Injection"          
      Criticidad           : ALTA (Afecta la visibilidad global del expediente en todo el sistema)     
      Nivel de Aislamiento : SERIALIZABLE (Implícito por el manejo de transacciones atómicas)          
      Complejidad Ciclomática: Media (4 caminos de ejecución principales)                              
   
	==========================================================================================================
      II. PROPÓSITO FORENSE Y DE NEGOCIO (BUSINESS VALUE PROPOSITION)                                  
	----------------------------------------------------------------------------------------------------------
                                                                                                        
      Este procedimiento actúa como el "Interruptor Maestro de Visibilidad" del expediente.            
      Su función NO es eliminar datos (DELETE físico está prohibido en el sistema), sino               
      controlar la disponibilidad lógica del curso mediante el patrón Soft Delete/Restore.             
                                                                                                        
      [ANALOGÍA OPERATIVA]:                                                                            
      Imagina un archivo físico en un archivero. Este SP es el encargado de:                           
        - ARCHIVAR: Mover el expediente del archivero "ACTIVO" al archivero "HISTÓRICO".               
        - RESTAURAR: Sacar el expediente del archivero "HISTÓRICO" y regresarlo al "ACTIVO".           
      En ningún caso se destruye el expediente; solo se cambia su ubicación lógica.                    
                                                                                                        
      [DIFERENCIA CON VERSIÓN 1.0]:                                                                    
      La versión anterior funcionaba como un "toggle automático" que infería la acción                 
      basándose en el estado actual. La versión 2.0 requiere que el usuario EXPLÍCITAMENTE             
      indique si desea Archivar (0) o Restaurar (1), eliminando ambigüedad y errores de UX.            
                                                                                                        
	==========================================================================================================
      III. REGLAS DE ORO DEL ARCHIVADO - GOVERNANCE RULES                                              
	----------------------------------------------------------------------------------------------------------

      A. PRINCIPIO DE FINALIZACIÓN (COMPLETION PRINCIPLE)                                              
      ───────────────────────────────────────────────────────────────────────────────────────────────  
         [REGLA]: No se permite archivar un curso que está "Vivo" (operativamente activo).             
                                                                                                        
         [MECANISMO]: El sistema verifica la bandera `Es_Final` del catálogo de estatus.               
                      Solo los estatus con Es_Final = 1 son archivables.                               
                                                                                                        
         [ESTATUS ARCHIVABLES (Es_Final = 1)]:                                                         
           ┌─────────────────┬───────────┬─────────────────────────────────────────────────┐           
           │ Estatus         │ Es_Final  │ Justificación                                   │           
           ├─────────────────┼───────────┼─────────────────────────────────────────────────┤           
           │ FINALIZADO      │     1     │ Ciclo de vida completado exitosamente           │           
           │ CANCELADO       │     1     │ Curso abortado antes de ejecutarse              │           
           │ ARCHIVADO       │     1     │ Ya está archivado (idempotencia)                │           
           └─────────────────┴───────────┴─────────────────────────────────────────────────┘           
                                                                                                        
         [ESTATUS NO ARCHIVABLES (Es_Final = 0)]:                                                      
           ┌─────────────────┬───────────┬─────────────────────────────────────────────────┐           
           │ Estatus         │ Es_Final  │ Razón de Bloqueo                                │           
           ├─────────────────┼───────────┼─────────────────────────────────────────────────┤           
           │ PROGRAMADO      │     0     │ Curso aún no ha sido autorizado                 │           
           │ POR INICIAR     │     0     │ Curso autorizado, esperando fecha de inicio     │           
           │ REPROGRAMADO    │     0     │ Curso con cambios pendientes de confirmar       │           
           │ EN CURSO        │     0     │ Curso en ejecución activa                       │           
           │ EN EVALUACIÓN   │     0     │ Curso terminado, calificaciones pendientes      │           
           │ ACREDITADO      │     0     │ Curso aprobado, pendiente de cierre formal      │           
           │ NO ACREDITADO   │     0     │ Curso reprobado, pendiente de cierre formal     │           
           └─────────────────┴───────────┴─────────────────────────────────────────────────┘           
                                                                                                        
         [JUSTIFICACIÓN DE NEGOCIO]:                                                                   
         Archivar un curso "vivo" causaría su desaparición del Dashboard Operativo,                    
         generando confusión en el Coordinador y potencialmente perdiendo el seguimiento               
         de un curso que aún requiere atención administrativa.                                         
                                                                                                        
      B. PRINCIPIO DE CASCADA (CASCADE PRINCIPLE)                                                      
      ───────────────────────────────────────────────────────────────────────────────────────────────  
         [REGLA]: La acción de Archivar/Restaurar es atómica y jerárquica.                             
                                                                                                        
         [MECANISMO]: Al modificar el estado del Padre (`Capacitaciones`), se debe                     
                      modificar SIMULTÁNEAMENTE el estado del Hijo vigente (`DatosCapacitaciones`).    
                                                                                                        
         [RAZÓN TÉCNICA]:                                                                              
         Las vistas del sistema (`Vista_Capacitaciones`) utilizan INNER JOIN entre Padre e Hijo.       
         Si solo se apaga el Padre pero el Hijo sigue activo (o viceversa), el registro                
         aparecería en un estado inconsistente o "fantasma" en ciertas consultas.                      
                                                                                                        
      C. PRINCIPIO DE TRAZABILIDAD AUTOMÁTICA (AUDIT INJECTION STRATEGY)                               
      ───────────────────────────────────────────────────────────────────────────────────────────────  
         [REGLA]: Cada acción de archivado debe dejar una huella indeleble en el registro.             
                                                                                                        
         [MECANISMO]: Al archivar, el sistema inyecta automáticamente una "Nota de Sistema"            
                      en el campo `Observaciones` del detalle operativo (`DatosCapacitaciones`).       
                                                                                                        
         [FORMATO DE LA NOTA INYECTADA]:                                                               
         ┌──────────────────────────────────────────────────────────────────────────────────────────┐  
         │ [SISTEMA]: La capacitación con folio CAP-2026-001 de la Gerencia GER-FINANZAS,          │  
         │ fue archivada el 2026-01-15 14:30 porque alcanzó el fin de su ciclo de vida.            │  
         └──────────────────────────────────────────────────────────────────────────────────────────┘  
                                                                                                        
         [OBJETIVO FORENSE]:                                                                           
         Que cualquier auditor futuro (interno o externo) pueda determinar:                            
           1. QUÉ se archivó (Folio).                                                                  
           2. DE QUIÉN era (Gerencia responsable).                                                     
           3. CUÁNDO se archivó (Timestamp exacto).                                                    
           4. POR QUÉ se archivó (Fin del ciclo de vida).                                              
                                                                                                        
      D. PRINCIPIO DE IDEMPOTENCIA (IDEMPOTENCY GUARANTEE)                                             
      ───────────────────────────────────────────────────────────────────────────────────────────────  
         [REGLA]: Ejecutar la misma operación múltiples veces produce el mismo resultado.              
                                                                                                        
         [MECANISMO]: Antes de ejecutar cualquier UPDATE, el SP verifica si el expediente              
                      YA está en el estado solicitado. Si es así, retorna un mensaje informativo       
                      sin realizar cambios ni generar errores.                                         
                                                                                                        
         [EJEMPLO]:                                                                                    
           - Usuario llama: SP_CambiarEstatusCapacitacion(123, 1, 0) -- Archivar                       
           - El expediente 123 ya está archivado (Activo = 0).                                         
           - Resultado: "La Capacitación ya se encuentra en el estado ARCHIVADO."                      
           - Acción: SIN_CAMBIOS (no se escribe nada en la BD).                                        
                                                                                                        
	==========================================================================================================
      IV. ARQUITECTURA DE DEFENSA EN PROFUNDIDAD (DEFENSE IN DEPTH)                                    
	----------------------------------------------------------------------------------------------------------
    
      El procedimiento implementa 5 capas de seguridad concéntricas:                                                                                                      
                                                                                                        
      CAPA 1 - VALIDACIÓN DE INPUTS (INPUT SANITIZATION)                                               
      ────────────────────────────────────────────────────                                             
        • Objetivo: Rechazar datos basura antes de procesar.                                           
        • Validaciones:                                                                                
          - _Id_Capacitacion: NOT NULL, > 0                                                            
          - _Id_Usuario_Ejecutor: NOT NULL, > 0                                                        
          - _Nuevo_Estatus: NOT NULL, IN (0, 1)                                                        
        • Error: SQLSTATE 45000 con código [400] Bad Request.                                          
                                                                                                        
      CAPA 2 - VERIFICACIÓN DE EXISTENCIA (EXISTENCE CHECK)                                            
      ───────────────────────────────────────────────────────                                          
        • Objetivo: Confirmar que el expediente existe en la BD.                                       
        • Mecanismo: SELECT sobre `Capacitaciones` con el ID proporcionado.                            
        • Error: SQLSTATE 45000 con código [404] Not Found.                                            
                                                                                                        
      CAPA 3 - IDEMPOTENCIA (IDEMPOTENCY CHECK)                                                        
      ──────────────────────────────────────────                                                       
        • Objetivo: Evitar operaciones redundantes.                                                    
        • Mecanismo: Comparar estado actual vs estado solicitado.                                      
        • Resultado si iguales: Retorno informativo sin cambios.                                       
                                                                                                        
      CAPA 4 - VALIDACIÓN DE REGLAS DE NEGOCIO (BUSINESS RULES)                                        
      ──────────────────────────────────────────────────────────                                       
        • Objetivo: Aplicar restricciones del dominio de negocio.                                      
        • Regla: Solo estatus con Es_Final = 1 pueden archivarse.                                      
        • Error: SQLSTATE 45000 con código [409] Conflict.                                             
                                                                                                        
      CAPA 5 - ATOMICIDAD TRANSACCIONAL (ACID COMPLIANCE)                                              
      ─────────────────────────────────────────────────────                                            
        • Objetivo: Garantizar consistencia total (Todo o Nada).                                       
        • Mecanismo: START TRANSACTION + COMMIT/ROLLBACK.                                              
        • Handler: EXIT HANDLER FOR SQLEXCEPTION ejecuta ROLLBACK automático.                          
                                                                                                        
	==========================================================================================================
      V. CASOS DE USO Y EJEMPLOS (USE CASES & EXAMPLES)                                              
	----------------------------------------------------------------------------------------------------------

      [CASO 1: ARCHIVADO EXITOSO]                                                                      
      ────────────────────────────                                                                     
        Contexto: Curso CAP-2026-001 está en estatus FINALIZADO (Es_Final = 1).                        
        Llamada:  CALL SP_CambiarEstatusCapacitacion(123, 1, 0);                                       
        Resultado:                                                                                     
          ┌────────────────┬──────────────────────────────────────────┬──────────────────┐             
          │ Nuevo_Estado   │ Mensaje                                  │ Accion           │             
          ├────────────────┼──────────────────────────────────────────┼──────────────────┤             
          │ ARCHIVADO      │ Expediente archivado y nota de auditoría │ ESTATUS_CAMBIADO │             
          │                │ registrada.                              │                  │             
          └────────────────┴──────────────────────────────────────────┴──────────────────┘             
                                                                                                        
      [CASO 2: ARCHIVADO BLOQUEADO]                                                                    
      ─────────────────────────────                                                                    
        Contexto: Curso CAP-2026-002 está en estatus EN CURSO (Es_Final = 0).                          
        Llamada:  CALL SP_CambiarEstatusCapacitacion(124, 1, 0);                                       
        Resultado: ERROR                                                                               
          ┌──────────────────────────────────────────────────────────────────────────────────────────┐ 
          │ ACCIÓN DENEGADA [409]: No se puede archivar un curso activo.                            │ 
          │ El estatus actual es "EN CURSO", el cual se considera OPERATIVO (No Final).             │ 
          │ Debe finalizar o cancelar la capacitación antes de archivarla.                          │ 
          └──────────────────────────────────────────────────────────────────────────────────────────┘ 
                                                                                                        
      [CASO 3: RESTAURACIÓN EXITOSA]                                                                   
      ───────────────────────────────                                                                  
        Contexto: Curso CAP-2026-001 está archivado (Activo = 0).                                      
        Llamada:  CALL SP_CambiarEstatusCapacitacion(123, 1, 1);                                       
        Resultado:                                                                                     
          ┌────────────────┬──────────────────────────────────────────┬──────────────────┐             
          │ Nuevo_Estado   │ Mensaje                                  │ Accion           │             
          ├────────────────┼──────────────────────────────────────────┼──────────────────┤             
          │ RESTAURADO     │ Expediente restaurado exitosamente.      │ ESTATUS_CAMBIADO │             
          └────────────────┴──────────────────────────────────────────┴──────────────────┘             
                                                                                                        
      [CASO 4: OPERACIÓN IDEMPOTENTE]                                                                  
      ────────────────────────────────                                                                 
        Contexto: Curso CAP-2026-001 ya está archivado (Activo = 0).                                   
        Llamada:  CALL SP_CambiarEstatusCapacitacion(123, 1, 0);  -- Intenta archivar de nuevo         
        Resultado:                                                                                     
          ┌─────────────────────────────────────────────────────────────────┬──────────────┐           
          │ Mensaje                                                         │ Accion       │           
          ├─────────────────────────────────────────────────────────────────┼──────────────┤           
          │ AVISO: La Capacitación "CAP-2026-001" ya se encuentra en el     │ SIN_CAMBIOS  │           
          │ estado solicitado (ARCHIVADO).                                  │              │           
          └─────────────────────────────────────────────────────────────────┴──────────────┘           

   ==================================================================================================== */
   
   /* ---------------------------------------------------------------------------------------------------
   LIMPIEZA PREVENTIVA (IDEMPOTENT DROP)
   ---------------------------------------------------------------------------------------------------
   [OBJETIVO]: Eliminar cualquier versión anterior del SP antes de recrearlo.
   [JUSTIFICACIÓN]: MySQL no soporta CREATE OR REPLACE PROCEDURE, por lo que debemos usar DROP + CREATE.
   [SEGURIDAD]: El IF EXISTS previene errores si el SP no existe previamente.
   --------------------------------------------------------------------------------------------------- */

DELIMITER $$
-- DROP PROCEDURE IF EXISTS `SP_CambiarEstatusCapacitacion`$$
CREATE PROCEDURE `SP_CambiarEstatusCapacitacion`(
    /* ===============================================================================================
       SECCIÓN DE PARÁMETROS DE ENTRADA (INPUT PARAMETERS SECTION)
       ===============================================================================================
       
       Esta sección define el "Contrato de Interfaz" del procedimiento.
       Cada parámetro está documentado con su tipo, obligatoriedad y propósito.
       
       [PRINCIPIO DE DISEÑO]: Explicit Input over Implicit Inference
       En lugar de inferir la acción del estado actual (como en v1.0), requerimos que
       el llamador indique EXPLÍCITAMENTE qué acción desea realizar.
       =============================================================================================== */
    
    /* -----------------------------------------------------------------------------------------------
       PARÁMETRO 1: _Id_Capacitacion
       -----------------------------------------------------------------------------------------------
       [TIPO DE DATO]    : INT (Entero de 32 bits con signo)
       [OBLIGATORIEDAD]  : REQUERIDO (NOT NULL, > 0)
       [DESCRIPCIÓN]     : Identificador único del Expediente Maestro (tabla `Capacitaciones`).
       [ORIGEN DEL VALOR]: El Frontend obtiene este ID cuando el usuario selecciona una fila
                           en el Grid del Dashboard o en el resultado de una búsqueda.
       [RELACIÓN FK]     : Apunta a `Capacitaciones.Id_Capacitacion` (PRIMARY KEY).
       [VALIDACIÓN]      : 
         - No puede ser NULL (se rechaza con error [400]).
         - No puede ser <= 0 (los IDs autogenerados siempre son positivos).
       [EJEMPLO]         : 123 (ID interno), NO confundir con el Folio (ej: 'CAP-2026-001').
       ----------------------------------------------------------------------------------------------- */
    IN _Id_Capacitacion     INT,
    
    /* -----------------------------------------------------------------------------------------------
       PARÁMETRO 2: _Id_Usuario_Ejecutor
       -----------------------------------------------------------------------------------------------
       [TIPO DE DATO]    : INT (Entero de 32 bits con signo)
       [OBLIGATORIEDAD]  : REQUERIDO (NOT NULL, > 0)
       [DESCRIPCIÓN]     : Identificador del usuario que ejecuta la operación de archivado/restauración.
       [PROPÓSITO FORENSE]: Este valor se utiliza para poblar los campos de auditoría:
         - `Capacitaciones.Fk_Id_Usuario_Cap_Updated_by`
         - `DatosCapacitaciones.Fk_Id_Usuario_DatosCap_Updated_by`
       [ORIGEN DEL VALOR]: El Backend (Laravel) extrae este ID de la sesión autenticada del usuario.
       [RELACIÓN FK]     : Apunta a `Usuarios.Id_Usuario` (PRIMARY KEY).
       [VALIDACIÓN]      : 
         - No puede ser NULL (se rechaza con error [400]).
         - No puede ser <= 0 (los IDs autogenerados siempre son positivos).
       [NOTA DE SEGURIDAD]: El Backend DEBE validar que el usuario tenga permisos de Coordinador o Admin
                            antes de llamar a este SP. El SP no valida roles internamente.
       ----------------------------------------------------------------------------------------------- */
    IN _Id_Usuario_Ejecutor INT,
    
    /* -----------------------------------------------------------------------------------------------
       PARÁMETRO 3: _Nuevo_Estatus
       -----------------------------------------------------------------------------------------------
       [TIPO DE DATO]    : TINYINT (Entero de 8 bits: 0-255, usamos solo 0 y 1)
       [OBLIGATORIEDAD]  : REQUERIDO (NOT NULL, IN (0, 1))
       [DESCRIPCIÓN]     : Indicador EXPLÍCITO de la acción a realizar.
       [DOMINIO DE VALORES]:
         ┌───────┬────────────────┬──────────────────────────────────────────────────────────────┐
         │ Valor │ Acción         │ Efecto                                                       │
         ├───────┼────────────────┼──────────────────────────────────────────────────────────────┤
         │   0   │ ARCHIVAR       │ Cambia Activo=0 en Padre e Hijo. Inyecta nota de auditoría.  │
         │       │ (Soft Delete)  │ El expediente desaparece del Dashboard Operativo.            │
         ├───────┼────────────────┼──────────────────────────────────────────────────────────────┤
         │   1   │ RESTAURAR      │ Cambia Activo=1 en Padre e Hijo.                             │
         │       │ (Undelete)     │ El expediente reaparece en el Dashboard Operativo.           │
         └───────┴────────────────┴──────────────────────────────────────────────────────────────┘
       [JUSTIFICACIÓN DEL CAMBIO v1.0 → v2.0]:
         La versión 1.0 usaba un "toggle" implícito: si estaba activo, lo archivaba; si estaba
         archivado, lo restauraba. Esto generaba confusión en la UX porque el usuario no sabía
         qué iba a pasar al presionar el botón. La v2.0 requiere intención explícita.
       [VALIDACIÓN]      : 
         - No puede ser NULL (se rechaza con error [400]).
         - Solo acepta 0 o 1 (cualquier otro valor genera error [400]).
       ----------------------------------------------------------------------------------------------- */
    IN _Nuevo_Estatus       TINYINT
)
/* ===================================================================================================
   ETIQUETA DEL PROCEDIMIENTO (PROCEDURE LABEL)
   ===================================================================================================
   [NOMBRE]: THIS_PROC
   [PROPÓSITO]: Permite usar `LEAVE THIS_PROC;` para salir del procedimiento de forma controlada
                sin ejecutar el resto del código. Es más limpio que usar múltiples RETURN o flags.
   [USO]: Se utiliza en el bloque de Idempotencia para salir anticipadamente cuando no hay cambios.
   =================================================================================================== */
THIS_PROC: BEGIN

    /* ===============================================================================================
       BLOQUE 0: DECLARACIÓN DE VARIABLES DE ENTORNO (ENVIRONMENT VARIABLES DECLARATION)
       ===============================================================================================
       
       [PROPÓSITO]:
       Definir todos los contenedores de memoria que el procedimiento utilizará durante su ejecución.
       MySQL requiere que TODAS las variables DECLARE se definan ANTES de cualquier otra instrucción.
       
       [ESTRATEGIA DE NOMENCLATURA]:
       Todas las variables locales usan el prefijo `v_` para distinguirlas de:
         - Parámetros de entrada (prefijo `_`)
         - Columnas de tablas (sin prefijo)
       
       [CATEGORÍAS DE VARIABLES]:
         1. Variables de Estado del Padre (Parent State Variables)
         2. Variables de Estado del Hijo (Child State Variables)
         3. Variables de Reglas de Negocio (Business Rule Variables)
         4. Variables de Auditoría (Audit Variables)
       =============================================================================================== */
    
    /* -----------------------------------------------------------------------------------------------
       CATEGORÍA 1: VARIABLES DE ESTADO DEL PADRE (PARENT STATE VARIABLES)
       ----------------------------------------------------------------------------------------------- */
    
    /* [VARIABLE]: v_Estado_Actual_Padre
       [TIPO]    : TINYINT(1) - Booleano (0 o 1)
       [PROPÓSITO]: Almacenar el valor actual del campo `Capacitaciones.Activo`.
       [USO]     : 
         - Determinar si el expediente está actualmente ACTIVO (1) o ARCHIVADO (0).
         - Comparar con `_Nuevo_Estatus` para verificar idempotencia.
       [FLUJO DE DATOS]: SELECT `Activo` INTO v_Estado_Actual_Padre FROM `Capacitaciones`... */
    DECLARE v_Estado_Actual_Padre TINYINT(1); 
    
    /* -----------------------------------------------------------------------------------------------
       CATEGORÍA 2: VARIABLES DE ESTADO DEL HIJO (CHILD STATE VARIABLES)
       ----------------------------------------------------------------------------------------------- */
    
    /* [VARIABLE]: v_Id_Ultimo_Detalle
       [TIPO]    : INT - Entero de 32 bits
       [PROPÓSITO]: Almacenar el ID de la versión VIGENTE del detalle operativo (`DatosCapacitaciones`).
       [CONTEXTO]: Un expediente padre puede tener múltiples versiones hijas (historial de cambios).
                   Solo la última versión (MAX(Id_DatosCap)) es la "vigente".
       [USO]     : 
         - Saber cuál registro hijo actualizar cuando se archive/restaure.
         - Inyectar la nota de auditoría en el detalle correcto.
       [FLUJO DE DATOS]: SELECT MAX(`Id_DatosCap`) INTO v_Id_Ultimo_Detalle FROM `DatosCapacitaciones`... */
    DECLARE v_Id_Ultimo_Detalle INT;           
    
    /* -----------------------------------------------------------------------------------------------
       CATEGORÍA 3: VARIABLES DE REGLAS DE NEGOCIO (BUSINESS RULE VARIABLES)
       ----------------------------------------------------------------------------------------------- */
    
    /* [VARIABLE]: v_Es_Estatus_Final
       [TIPO]    : TINYINT(1) - Booleano (0 o 1)
       [PROPÓSITO]: Almacenar la bandera `Es_Final` del catálogo de estatus (`Cat_Estatus_Capacitacion`).
       [REGLA DE NEGOCIO]:
         - Es_Final = 1: El estatus es TERMINAL (FINALIZADO, CANCELADO, ARCHIVADO). SE PUEDE ARCHIVAR.
         - Es_Final = 0: El estatus es OPERATIVO (PROGRAMADO, EN CURSO, etc.). NO SE PUEDE ARCHIVAR.
       [USO]     : Validar si el archivado está permitido según las reglas de gobernanza.
       [FLUJO DE DATOS]: SELECT `Es_Final` INTO v_Es_Estatus_Final FROM `Cat_Estatus_Capacitacion`... */
    DECLARE v_Es_Estatus_Final TINYINT(1);
    
    /* [VARIABLE]: v_Nombre_Estatus
       [TIPO]    : VARCHAR(50) - Cadena de texto de hasta 50 caracteres
       [PROPÓSITO]: Almacenar el nombre legible del estatus actual (ej: "EN CURSO", "FINALIZADO").
       [USO]     : Construir mensajes de error descriptivos que ayuden al usuario a entender
                   por qué su solicitud de archivado fue rechazada.
       [EJEMPLO DE USO EN MENSAJE]:
         "El estatus actual es 'EN CURSO', el cual se considera OPERATIVO (No Final)."
       [FLUJO DE DATOS]: SELECT `Nombre` INTO v_Nombre_Estatus FROM `Cat_Estatus_Capacitacion`... */
    DECLARE v_Nombre_Estatus VARCHAR(50);
    
    /* -----------------------------------------------------------------------------------------------
       CATEGORÍA 4: VARIABLES DE AUDITORÍA (AUDIT VARIABLES)
       ----------------------------------------------------------------------------------------------- */
    
    /* [VARIABLE]: v_Folio
       [TIPO]    : VARCHAR(50) - Cadena de texto de hasta 50 caracteres
       [PROPÓSITO]: Almacenar el Folio/Número de Capacitación (ej: "CAP-2026-001").
       [USO]     : 
         - Incluir en el mensaje de idempotencia para que el usuario sepa qué curso se verificó.
         - Incluir en la nota de auditoría inyectada al archivar.
       [CONTEXTO]: El Folio es la "Llave de Negocio" que los usuarios reconocen. El Id interno
                   es solo para uso técnico.
       [FLUJO DE DATOS]: SELECT `Numero_Capacitacion` INTO v_Folio FROM `Capacitaciones`... */
    DECLARE v_Folio VARCHAR(50);
    
    /* [VARIABLE]: v_Clave_Gerencia
       [TIPO]    : VARCHAR(50) - Cadena de texto de hasta 50 caracteres
       [PROPÓSITO]: Almacenar la Clave de la Gerencia responsable del curso (ej: "GER-FINANZAS").
       [USO]     : Incluir en la nota de auditoría para identificar el área organizacional afectada.
       [CONTEXTO FORENSE]: En una auditoría, es crítico saber no solo QUÉ curso se archivó,
                           sino también DE QUIÉN era la responsabilidad de ese curso.
       [FLUJO DE DATOS]: SELECT `Clave` INTO v_Clave_Gerencia FROM `Cat_Gerencias_Activos`... */
    DECLARE v_Clave_Gerencia VARCHAR(50);
    
    /* [VARIABLE]: v_Mensaje_Auditoria
       [TIPO]    : TEXT - Cadena de texto de longitud variable (hasta 65,535 caracteres)
       [PROPÓSITO]: Almacenar el mensaje formateado que se inyectará en el campo `Observaciones`.
       [FORMATO DEL MENSAJE]:
         "[SISTEMA]: La capacitación con folio {FOLIO} de la Gerencia {GERENCIA}, 
          fue archivada el {FECHA} porque alcanzó el fin de su ciclo de vida."
       [USO]     : Concatenar con las observaciones existentes al archivar para dejar evidencia.
       [NOTA]    : Se usa TEXT en lugar de VARCHAR porque el mensaje puede ser largo y además
                   se concatena con observaciones previas que también pueden ser extensas. */
    DECLARE v_Mensaje_Auditoria TEXT;

    /* ===============================================================================================
       BLOQUE 1: HANDLER DE EXCEPCIONES (EXCEPTION HANDLER - FAIL-SAFE MECHANISM)
       ===============================================================================================
       
       [PROPÓSITO]:
       Definir el comportamiento del sistema ante errores inesperados (excepciones SQL).
       Este es el "Airbag" del procedimiento: si algo sale mal, revierte todo y no deja datos corruptos.
       
       [PRINCIPIO ACID]:
       Este handler garantiza la "Atomicidad" de la transacción. Si cualquier parte falla,
       TODO se revierte, dejando la base de datos exactamente como estaba antes del CALL.
       
       [TIPOS DE ERRORES CAPTURADOS]:
         - Errores de disco (ej: tablespace lleno)
         - Errores de conexión (ej: timeout)
         - Violaciones de FK no anticipadas
         - Errores de sintaxis en SQL dinámico
         - Cualquier otro SQLEXCEPTION no manejado específicamente
       
       [COMPORTAMIENTO]:
         1. ROLLBACK: Revierte todos los cambios pendientes de la transacción actual.
         2. RESIGNAL: Re-lanza la excepción original para que el llamador (Backend) la capture.
       
       [NOTA TÉCNICA]:
       Usamos EXIT HANDLER (termina el SP inmediatamente) en lugar de CONTINUE HANDLER
       (seguiría ejecutando) porque ante un error de sistema no tiene sentido continuar.
       =============================================================================================== */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        /* -------------------------------------------------------------------------------------
           PASO 1: ROLLBACK DE EMERGENCIA
           -------------------------------------------------------------------------------------
           [ACCIÓN]  : Deshacer todos los cambios realizados desde el último START TRANSACTION.
           [EFECTO]  : Los UPDATEs a `Capacitaciones` y `DatosCapacitaciones` se revierten.
           [GARANTÍA]: La BD queda en el estado exacto en que estaba antes del CALL.
           ------------------------------------------------------------------------------------- */
        ROLLBACK; 
        
        /* -------------------------------------------------------------------------------------
           PASO 2: PROPAGACIÓN DEL ERROR (RESIGNAL)
           -------------------------------------------------------------------------------------
           [ACCIÓN]  : Re-lanzar la excepción original sin modificarla.
           [PROPÓSITO]: Permitir que el Backend (Laravel) capture el error y lo maneje
                        apropiadamente (logging, notificación al usuario, etc.).
           [ALTERNATIVA NO USADA]: Podríamos usar SIGNAL para generar un error personalizado,
                        pero perderíamos información valiosa del error original (código, mensaje).
           ------------------------------------------------------------------------------------- */
        RESIGNAL; 
    END;

    /* ===============================================================================================
       BLOQUE 2: CAPA 1 - VALIDACIÓN DE PARÁMETROS DE ENTRADA (INPUT VALIDATION - FAIL FAST)
       ===============================================================================================
       
       [PROPÓSITO]:
       Rechazar peticiones con datos inválidos ANTES de realizar cualquier operación costosa
       (SELECTs a la BD, transacciones, etc.).
       
       [FILOSOFÍA - FAIL FAST]:
       "Falla rápido, falla ruidosamente". Es mejor rechazar inmediatamente una petición
       malformada que descubrir el error después de haber hecho trabajo innecesario.
       
       [PRINCIPIO DE DEFENSA EN PROFUNDIDAD]:
       Aunque el Frontend y el Backend DEBERÍAN validar estos datos antes de llamar al SP,
       no confiamos ciegamente en ellos. El SP es la última línea de defensa.
       
       [VALIDACIONES REALIZADAS]:
         1. _Id_Capacitacion: NOT NULL y > 0
         2. _Id_Usuario_Ejecutor: NOT NULL y > 0
         3. _Nuevo_Estatus: NOT NULL y IN (0, 1)
       =============================================================================================== */
    
    /* -----------------------------------------------------------------------------------------------
       VALIDACIÓN 2.1: INTEGRIDAD DEL ID DE CAPACITACIÓN
       ----------------------------------------------------------------------------------------------- */
    /* [REGLA]     : El ID del expediente debe ser un entero positivo válido.
       [CASOS RECHAZADOS]:
         - NULL: El Frontend no envió el parámetro o lo envió vacío.
         - 0: Valor por defecto que indica "ningún registro seleccionado".
         - Negativos: Imposibles en una columna AUTO_INCREMENT.
       [CÓDIGO DE ERROR]: [400] Bad Request - Datos de entrada inválidos.
       [ACCIÓN DEL CLIENTE]: Debe verificar que se haya seleccionado un registro válido. */
    IF _Id_Capacitacion IS NULL OR _Id_Capacitacion <= 0 THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: El ID de la Capacitación es inválido o nulo. Verifique que haya seleccionado un registro válido del listado.';
    END IF;

    /* -----------------------------------------------------------------------------------------------
       VALIDACIÓN 2.2: INTEGRIDAD DEL ID DE USUARIO EJECUTOR
       ----------------------------------------------------------------------------------------------- */
    /* [REGLA]     : El ID del usuario auditor debe ser un entero positivo válido.
       [CASOS RECHAZADOS]:
         - NULL: El Backend no extrajo correctamente el ID de la sesión.
         - 0 o negativos: Valores imposibles para un usuario autenticado.
       [CÓDIGO DE ERROR]: [400] Bad Request - Datos de entrada inválidos.
       [IMPLICACIÓN]: Sin este ID, no podemos registrar quién realizó la acción (auditoría rota).
       [ACCIÓN DEL CLIENTE]: El Backend debe verificar la sesión del usuario antes de llamar. */
    IF _Id_Usuario_Ejecutor IS NULL OR _Id_Usuario_Ejecutor <= 0 THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: El ID del Usuario Ejecutor es obligatorio para la auditoría. Verifique la sesión del usuario autenticado.';
    END IF;

    /* -----------------------------------------------------------------------------------------------
       VALIDACIÓN 2.3: INTEGRIDAD Y DOMINIO DEL NUEVO ESTATUS
       ----------------------------------------------------------------------------------------------- */
    /* [REGLA]     : El parámetro de acción debe ser explícitamente 0 (Archivar) o 1 (Restaurar).
       [CASOS RECHAZADOS]:
         - NULL: El Frontend no especificó qué acción realizar.
         - Valores distintos de 0 o 1: Dominio no permitido (ej: 2, -1, 99).
       [CÓDIGO DE ERROR]: [400] Bad Request - Datos de entrada inválidos.
       [JUSTIFICACIÓN v2.0]: Este parámetro es NUEVO. Reemplaza el comportamiento "toggle" de v1.0
                             que infería la acción. Ahora requerimos intención explícita.
       [ACCIÓN DEL CLIENTE]: El Frontend debe enviar 0 para archivar o 1 para restaurar. */
    IF _Nuevo_Estatus IS NULL OR _Nuevo_Estatus NOT IN (0, 1) THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERROR DE LÓGICA [400]: El campo "Nuevo Estatus" es obligatorio y solo acepta valores binarios: 0 (Archivar) o 1 (Restaurar). Verifique el valor enviado.';
    END IF;

    /* ===============================================================================================
       BLOQUE 3: CAPA 2 - RECUPERACIÓN DE CONTEXTO Y VERIFICACIÓN DE EXISTENCIA
       ===============================================================================================
       
       [PROPÓSITO]:
       Obtener toda la información necesaria sobre el expediente ANTES de tomar decisiones.
       Esto incluye:
         1. Verificar que el expediente existe (protección contra IDs fantasma).
         2. Obtener el estado actual del Padre (Activo/Archivado).
         3. Obtener metadatos para auditoría (Folio, Gerencia).
       
       [ESTRATEGIA - SINGLE QUERY OPTIMIZATION]:
       En lugar de hacer múltiples SELECTs pequeños, consolidamos todo en una sola consulta
       con JOIN para minimizar los round-trips a la base de datos.
       
       [BLOQUEO DE LECTURA]:
       Esta consulta NO usa FOR UPDATE porque solo estamos leyendo. El bloqueo pesimista
       se aplicará más adelante dentro de la transacción si es necesario.
       =============================================================================================== */
    
    /* -----------------------------------------------------------------------------------------------
       CONSULTA 3.1: RADIOGRAFÍA DEL PADRE + DATOS DE AUDITORÍA
       -----------------------------------------------------------------------------------------------
       [OBJETIVO]    : Obtener el estado actual y los datos de identificación del expediente.
       [TABLAS]      : 
         - `Capacitaciones` (Padre): Estado actual, Folio.
         - `Cat_Gerencias_Activos` (Catálogo): Clave de la gerencia para auditoría.
       [JOIN]        : INNER JOIN porque la FK de gerencia es obligatoria (no puede haber huérfanos).
       [LIMIT 1]     : Optimización. Aunque el ID es único, LIMIT evita scans innecesarios.
       [INTO]        : Carga los resultados en variables locales para uso posterior.
       ----------------------------------------------------------------------------------------------- */
    SELECT 
        `Cap`.`Activo`,              -- Estado actual del expediente (1=Activo, 0=Archivado)
        `Cap`.`Numero_Capacitacion`, -- Folio para mensajes y auditoría
        `Ger`.`Clave`                -- Clave de gerencia para nota de auditoría
    INTO 
        v_Estado_Actual_Padre,       -- Variable: Estado actual
        v_Folio,                     -- Variable: Folio
        v_Clave_Gerencia             -- Variable: Gerencia
    FROM `Capacitaciones` `Cap`
    /* -----------------------------------------------------------------------------------------
       JOIN CON CATÁLOGO DE GERENCIAS
       -----------------------------------------------------------------------------------------
       [TIPO]   : INNER JOIN (obligatorio)
       [RAZÓN]  : Todo expediente DEBE tener una gerencia asignada (FK NOT NULL).
       [TABLA]  : Cat_Gerencias_Activos - Catálogo maestro de gerencias.
       [COLUMNA]: Clave - Identificador de negocio de la gerencia (ej: "GER-FINANZAS").
       ----------------------------------------------------------------------------------------- */
    INNER JOIN `Cat_Gerencias_Activos` `Ger` 
        ON `Cap`.`Fk_Id_CatGeren` = `Ger`.`Id_CatGeren`
    WHERE `Cap`.`Id_Capacitacion` = _Id_Capacitacion 
    LIMIT 1;

    /* -----------------------------------------------------------------------------------------------
       VALIDACIÓN 3.2: VERIFICACIÓN DE EXISTENCIA (404 NOT FOUND)
       -----------------------------------------------------------------------------------------------
       [REGLA]     : Si el SELECT no encontró registros, v_Estado_Actual_Padre será NULL.
       [CAUSA PROBABLE]:
         - El ID proporcionado nunca existió en la base de datos.
         - El registro fue eliminado físicamente (caso raro, DELETE está prohibido).
         - Error de sincronización entre Frontend y BD (cache desactualizado).
       [CÓDIGO DE ERROR]: [404] Not Found - Recurso no encontrado.
       [ACCIÓN DEL CLIENTE]: Refrescar la lista y seleccionar un registro válido.
       ----------------------------------------------------------------------------------------------- */
    IF v_Estado_Actual_Padre IS NULL THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [404]: La Capacitación solicitada no existe en el catálogo maestro. Es posible que haya sido eliminada o que el ID sea incorrecto. Por favor, actualice su listado.';
    END IF;

    /* ===============================================================================================
       BLOQUE 4: CAPA 3 - VERIFICACIÓN DE IDEMPOTENCIA
       ===============================================================================================
       
       [PROPÓSITO]:
       Evitar operaciones redundantes que no tendrían efecto en la base de datos.
       
       [DEFINICIÓN DE IDEMPOTENCIA]:
       Una operación es idempotente si ejecutarla múltiples veces produce el mismo resultado
       que ejecutarla una sola vez. En este contexto:
         - Archivar un expediente ya archivado = Sin cambios.
         - Restaurar un expediente ya activo = Sin cambios.
       
       [BENEFICIOS]:
         1. Evita escrituras innecesarias en la BD (optimización de I/O).
         2. Evita generar notas de auditoría duplicadas.
         3. Proporciona feedback claro al usuario sobre el estado actual.
       
       [COMPORTAMIENTO]:
       Si el estado actual ya coincide con el solicitado, el SP:
         1. Retorna un mensaje informativo (no un error).
         2. Sale anticipadamente con `LEAVE THIS_PROC`.
         3. NO ejecuta ningún UPDATE ni transacción.
       =============================================================================================== */
    IF v_Estado_Actual_Padre = _Nuevo_Estatus THEN
        /* -------------------------------------------------------------------------------------
           CONSTRUCCIÓN DEL MENSAJE DE IDEMPOTENCIA
           -------------------------------------------------------------------------------------
           [OBJETIVO]: Informar al usuario que no hubo cambios y por qué.
           [FORMATO] : Incluye el folio para que el usuario confirme que es el registro correcto.
           [TONO]    : Informativo (AVISO), no de error. No es un problema, solo una observación.
           ------------------------------------------------------------------------------------- */
        SELECT 
            CONCAT(
                'AVISO: La Capacitación "', v_Folio, '" ya se encuentra en el estado solicitado (', 
                IF(_Nuevo_Estatus = 1, 'ACTIVO', 'ARCHIVADO'), 
                '). No se realizaron cambios.'
            ) AS Mensaje, 
            'SIN_CAMBIOS' AS Accion;
        
        /* -------------------------------------------------------------------------------------
           SALIDA ANTICIPADA (EARLY EXIT)
           -------------------------------------------------------------------------------------
           [ACCIÓN]  : Terminar la ejecución del SP inmediatamente.
           [EFECTO]  : No se ejecuta ningún código posterior (transacción, UPDATEs, etc.).
           [NOTA]    : Esto es más limpio que usar flags booleanos y condicionales anidados.
           ------------------------------------------------------------------------------------- */
        LEAVE THIS_PROC;
    END IF;

    /* ===============================================================================================
       BLOQUE 5: RECUPERACIÓN DE DATOS DEL HIJO (DETALLE OPERATIVO)
       ===============================================================================================
       
       [PROPÓSITO]:
       Obtener información del registro hijo vigente (`DatosCapacitaciones`) que necesitamos para:
         1. Validar reglas de negocio (Es_Final).
         2. Saber qué registro actualizar.
         3. Inyectar la nota de auditoría.
       
       [CONTEXTO - ARQUITECTURA PADRE-HIJO]:
       Un expediente (`Capacitaciones`) puede tener múltiples versiones (`DatosCapacitaciones`).
       Cada vez que se edita un curso, se crea una nueva versión y se archiva la anterior.
       Solo la última versión (MAX ID) es la "vigente".
       
       [ESTRATEGIA - LATEST SNAPSHOT]:
       Usamos ORDER BY Id_DatosCap DESC LIMIT 1 para obtener siempre la versión más reciente.
       =============================================================================================== */
    SELECT 
        `DC`.`Id_DatosCap`,    -- ID del detalle vigente (para UPDATE posterior)
        `CatEst`.`Es_Final`,   -- Bandera de seguridad (¿Se puede archivar?)
        `CatEst`.`Nombre`      -- Nombre del estatus (para mensajes de error)
    INTO 
        v_Id_Ultimo_Detalle,   -- Variable: ID del hijo vigente
        v_Es_Estatus_Final,    -- Variable: Bandera Es_Final
        v_Nombre_Estatus       -- Variable: Nombre del estatus
    FROM `DatosCapacitaciones` `DC`
    /* -----------------------------------------------------------------------------------------
       JOIN CON CATÁLOGO DE ESTATUS
       -----------------------------------------------------------------------------------------
       [TIPO]   : INNER JOIN (obligatorio)
       [RAZÓN]  : Todo detalle DEBE tener un estatus asignado (FK NOT NULL).
       [TABLA]  : Cat_Estatus_Capacitacion - Catálogo maestro de estados del ciclo de vida.
       [COLUMNAS EXTRAÍDAS]:
         - Es_Final: Bandera que indica si el estatus permite archivado.
         - Nombre: Texto legible del estatus para mensajes de error.
       ----------------------------------------------------------------------------------------- */
    INNER JOIN `Cat_Estatus_Capacitacion` `CatEst` 
        ON `DC`.`Fk_Id_CatEstCap` = `CatEst`.`Id_CatEstCap`
    WHERE `DC`.`Fk_Id_Capacitacion` = _Id_Capacitacion
    /* -----------------------------------------------------------------------------------------
       ORDENAMIENTO PARA OBTENER LA VERSIÓN MÁS RECIENTE
       -----------------------------------------------------------------------------------------
       [ESTRATEGIA]: Los IDs son AUTO_INCREMENT, por lo que el ID más alto = versión más nueva.
       [ORDER BY]  : Descendente para que el primero sea el más reciente.
       [LIMIT 1]   : Solo necesitamos la versión vigente, no el historial completo.
       ----------------------------------------------------------------------------------------- */
    ORDER BY `DC`.`Id_DatosCap` DESC 
    LIMIT 1;

    /* ===============================================================================================
       BLOQUE 6: INICIO DE TRANSACCIÓN (ACID COMPLIANCE)
       ===============================================================================================
       
       [PROPÓSITO]:
       Iniciar un contexto transaccional que garantice atomicidad en las operaciones siguientes.
       
       [PRINCIPIO ACID - ATOMICIDAD]:
       Todas las operaciones dentro de esta transacción se ejecutan como una unidad indivisible:
         - O TODAS se completan exitosamente (COMMIT).
         - O NINGUNA se aplica (ROLLBACK).
       
       [OPERACIONES PROTEGIDAS]:
         1. UPDATE a `Capacitaciones` (Padre).
         2. UPDATE a `DatosCapacitaciones` (Hijo).
       
       [ESCENARIO DE FALLO]:
       Si el UPDATE al Padre tiene éxito pero el UPDATE al Hijo falla (ej: disco lleno),
       el ROLLBACK revierte AMBOS cambios, evitando inconsistencias.
       =============================================================================================== */
    START TRANSACTION;

    /* ===============================================================================================
       BLOQUE 7: MOTOR DE DECISIÓN - BIFURCACIÓN POR ACCIÓN SOLICITADA
       ===============================================================================================
       
       [PROPÓSITO]:
       Ejecutar la lógica específica según la acción solicitada:
         - _Nuevo_Estatus = 0: Ejecutar flujo de ARCHIVADO.
         - _Nuevo_Estatus = 1: Ejecutar flujo de RESTAURACIÓN.
       
       [ESTRUCTURA]:
       IF-ELSE con dos ramas mutuamente excluyentes.
       =============================================================================================== */

    /* ===========================================================================================
       RAMA A: FLUJO DE ARCHIVADO (_Nuevo_Estatus = 0)
       ===========================================================================================
       [OBJETIVO]: Cambiar el expediente de ACTIVO a ARCHIVADO (Soft Delete).
       [VALIDACIÓN REQUERIDA]: El estatus actual debe tener Es_Final = 1.
       [ACCIONES]:
         1. Validar regla de negocio (Es_Final = 1).
         2. Construir nota de auditoría.
         3. Apagar Padre (Activo = 0).
         4. Apagar Hijo + Inyectar nota (Activo = 0, Observaciones += nota).
       =========================================================================================== */
    IF _Nuevo_Estatus = 0 THEN
        
        /* ---------------------------------------------------------------------------------------
           PASO 7.A.1: CAPA 4 - VALIDACIÓN DE REGLAS DE NEGOCIO (BUSINESS RULES ENFORCEMENT)
           ---------------------------------------------------------------------------------------
           [REGLA]        : Solo se pueden archivar cursos con estatus TERMINAL (Es_Final = 1).
           [JUSTIFICACIÓN]: Archivar un curso "vivo" (en ejecución) lo haría desaparecer del
                            Dashboard sin haber completado su ciclo de vida, generando confusión.
           [ESTATUS PERMITIDOS]: FINALIZADO, CANCELADO, ARCHIVADO (Es_Final = 1).
           [ESTATUS BLOQUEADOS]: PROGRAMADO, EN CURSO, EVALUACIÓN, etc. (Es_Final = 0).
           --------------------------------------------------------------------------------------- */
        IF v_Es_Estatus_Final = 0 OR v_Es_Estatus_Final IS NULL THEN
            /* -----------------------------------------------------------------------------------
               ROLLBACK PREVENTIVO
               -----------------------------------------------------------------------------------
               [ACCIÓN] : Revertir la transacción antes de lanzar el error.
               [RAZÓN]  : Aunque no hemos hecho UPDATEs aún, es buena práctica cerrar la
                          transacción limpiamente antes de terminar el SP.
               ----------------------------------------------------------------------------------- */
            ROLLBACK;
            
            /* -----------------------------------------------------------------------------------
               CONSTRUCCIÓN DE MENSAJE DE ERROR DESCRIPTIVO
               -----------------------------------------------------------------------------------
               [OBJETIVO]: Dar al usuario información ACCIONABLE sobre cómo resolver el problema.
               [CONTENIDO]:
                 - Qué falló: "No se puede archivar un curso activo."
                 - Por qué: El estatus actual ("EN CURSO") es operativo, no final.
                 - Cómo resolverlo: "Debe finalizar o cancelar la capacitación antes."
               ----------------------------------------------------------------------------------- */
            SET @ErrorMsg = CONCAT(
                'ACCIÓN DENEGADA [409]: No se puede archivar un curso activo. ',
                'El estatus actual es "', v_Nombre_Estatus, '", el cual se considera OPERATIVO (No Final). ',
                'Debe finalizar o cancelar la capacitación antes de archivarla.'
            );
            
            /* -----------------------------------------------------------------------------------
               LANZAMIENTO DE EXCEPCIÓN CONTROLADA
               -----------------------------------------------------------------------------------
               [SQLSTATE 45000]: Código estándar para errores definidos por el usuario.
               [MESSAGE_TEXT] : El mensaje construido arriba.
               [EFECTO]       : El SP termina inmediatamente. El Backend captura este error.
               ----------------------------------------------------------------------------------- */
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = @ErrorMsg;
        END IF;

        /* ---------------------------------------------------------------------------------------
           PASO 7.A.2: CONSTRUCCIÓN DE NOTA DE AUDITORÍA (AUDIT EVIDENCE PREPARATION)
           ---------------------------------------------------------------------------------------
           [PROPÓSITO]: Crear el texto que se inyectará en el campo Observaciones.
           [DATOS INCLUIDOS]:
             - Folio del curso (identificación).
             - Gerencia responsable (contexto organizacional).
             - Fecha y hora exacta (timestamp forense).
             - Motivo del archivado (justificación estándar).
           [FORMATO]: Texto plano con prefijo "[SISTEMA]:" para distinguirlo de notas manuales.
           --------------------------------------------------------------------------------------- */
        SET v_Mensaje_Auditoria = CONCAT(
            ' [SISTEMA]: La capacitación con folio ', v_Folio, 
            ' de la Gerencia ', v_Clave_Gerencia, 
            ', fue archivada el ', DATE_FORMAT(NOW(), '%Y-%m-%d %H:%i'), 
            ' porque alcanzó el fin de su ciclo de vida.'
        );

        /* ---------------------------------------------------------------------------------------
           PASO 7.A.3: CAPA 5 - EJECUCIÓN DE ARCHIVADO EN CASCADA (CASCADE SOFT DELETE)
           ---------------------------------------------------------------------------------------
           [ESTRATEGIA]: Actualizar Padre primero, luego Hijo.
           [RAZÓN DEL ORDEN]: Si fallara el UPDATE al Hijo, el ROLLBACK revertiría el Padre.
                              No importa el orden técnicamente, pero Padre→Hijo es más intuitivo.
           --------------------------------------------------------------------------------------- */
        
        /* -----------------------------------------------------------------------------------
           PASO 7.A.3.1: ARCHIVADO DEL PADRE (EXPEDIENTE MAESTRO)
           -----------------------------------------------------------------------------------
           [TABLA]   : Capacitaciones
           [CAMBIOS] :
             - Activo = 0: Marca el expediente como archivado (invisible en vistas operativas).
             - Fk_Id_Usuario_Cap_Updated_by: Registra quién realizó la acción (auditoría).
             - updated_at = NOW(): Registra cuándo se realizó la acción (timestamp).
           [FILTRO]  : WHERE Id_Capacitacion = _Id_Capacitacion (solo este expediente).
           ----------------------------------------------------------------------------------- */
        UPDATE `Capacitaciones` 
        SET 
            `Activo` = 0,                                        -- Soft Delete: Ocultar expediente
            `Fk_Id_Usuario_Cap_Updated_by` = _Id_Usuario_Ejecutor, -- Auditoría: Quién
            `updated_at` = NOW()                                  -- Auditoría: Cuándo
        WHERE `Id_Capacitacion` = _Id_Capacitacion;

        /* -----------------------------------------------------------------------------------
           PASO 7.A.3.2: ARCHIVADO DEL HIJO + INYECCIÓN DE NOTA (DETALLE OPERATIVO)
           -----------------------------------------------------------------------------------
           [TABLA]   : DatosCapacitaciones
           [CAMBIOS] :
             - Activo = 0: Marca la versión como archivada.
             - Fk_Id_Usuario_DatosCap_Updated_by: Registra quién realizó la acción.
             - updated_at = NOW(): Registra cuándo se realizó la acción.
             - Observaciones: CONCATENA la nota de auditoría con las observaciones existentes.
           [FILTRO]  : WHERE Id_DatosCap = v_Id_Ultimo_Detalle (solo la versión vigente).
           [NOTA SOBRE CONCAT_WS]:
             - WS = "With Separator". Agrega el separador SOLO si ambos valores no son NULL.
             - Separador '\n\n': Doble salto de línea para separar visualmente la nota.
             - Si Observaciones era NULL, solo quedará la nota de auditoría (sin separador).
           ----------------------------------------------------------------------------------- */
        UPDATE `DatosCapacitaciones` 
        SET 
            `Activo` = 0,                                                -- Soft Delete: Ocultar versión
            `Fk_Id_Usuario_DatosCap_Updated_by` = _Id_Usuario_Ejecutor,   -- Auditoría: Quién
            `updated_at` = NOW(),                                         -- Auditoría: Cuándo
            `Observaciones` = CONCAT_WS('\n\n', `Observaciones`, v_Mensaje_Auditoria) -- Inyección de nota
        WHERE `Id_DatosCap` = v_Id_Ultimo_Detalle;

        /* -----------------------------------------------------------------------------------
           PASO 7.A.4: CONFIRMACIÓN DE TRANSACCIÓN (COMMIT)
           -----------------------------------------------------------------------------------
           [ACCIÓN] : Hacer permanentes todos los cambios de esta transacción.
           [EFECTO] : Los UPDATEs se escriben definitivamente en disco.
           [PUNTO DE NO RETORNO]: Después del COMMIT, no hay ROLLBACK posible.
           ----------------------------------------------------------------------------------- */
        COMMIT;
        
        /* -----------------------------------------------------------------------------------
           PASO 7.A.5: RETORNO DE CONFIRMACIÓN AL CLIENTE
           -----------------------------------------------------------------------------------
           [FORMATO] : Resultset de fila única con 3 columnas.
           [USO]     : El Backend/Frontend usa estos valores para actualizar la UI.
           ----------------------------------------------------------------------------------- */
        SELECT 
            'ARCHIVADO' AS `Nuevo_Estado`,                                    -- Estado resultante
            'Expediente archivado y nota de auditoría registrada.' AS `Mensaje`, -- Feedback
            'ESTATUS_CAMBIADO' AS Accion;                                     -- Código de acción

    /* ===========================================================================================
       RAMA B: FLUJO DE RESTAURACIÓN (_Nuevo_Estatus = 1)
       ===========================================================================================
       [OBJETIVO]: Cambiar el expediente de ARCHIVADO a ACTIVO (Undelete).
       [VALIDACIÓN REQUERIDA]: Ninguna adicional. Si está archivado, siempre se puede restaurar.
       [ACCIONES]:
         1. Encender Padre (Activo = 1).
         2. Encender Hijo (Activo = 1).
       [NOTA]: No se inyecta nota de auditoría en la restauración. El timestamp en updated_at
               y el updated_by son suficientes para rastrear la acción.
       =========================================================================================== */
    ELSE
        /* ---------------------------------------------------------------------------------------
           PASO 7.B.1: RESTAURACIÓN DEL PADRE (EXPEDIENTE MAESTRO)
           ---------------------------------------------------------------------------------------
           [TABLA]   : Capacitaciones
           [CAMBIOS] :
             - Activo = 1: Reactiva el expediente (visible en vistas operativas nuevamente).
             - Fk_Id_Usuario_Cap_Updated_by: Registra quién realizó la restauración.
             - updated_at = NOW(): Registra cuándo se realizó la restauración.
           --------------------------------------------------------------------------------------- */
        UPDATE `Capacitaciones` 
        SET 
            `Activo` = 1,                                        -- Undelete: Mostrar expediente
            `Fk_Id_Usuario_Cap_Updated_by` = _Id_Usuario_Ejecutor, -- Auditoría: Quién
            `updated_at` = NOW()                                  -- Auditoría: Cuándo
        WHERE `Id_Capacitacion` = _Id_Capacitacion;

        /* ---------------------------------------------------------------------------------------
           PASO 7.B.2: RESTAURACIÓN DEL HIJO (DETALLE OPERATIVO)
           ---------------------------------------------------------------------------------------
           [TABLA]   : DatosCapacitaciones
           [CAMBIOS] :
             - Activo = 1: Reactiva la versión vigente.
             - Fk_Id_Usuario_DatosCap_Updated_by: Registra quién realizó la restauración.
             - updated_at = NOW(): Registra cuándo se realizó la restauración.
           [NOTA]    : NO se modifican las Observaciones. La nota de archivado anterior permanece
                       como evidencia histórica de que el expediente estuvo archivado.
           --------------------------------------------------------------------------------------- */
        UPDATE `DatosCapacitaciones` 
        SET 
            `Activo` = 1,                                                -- Undelete: Mostrar versión
            `Fk_Id_Usuario_DatosCap_Updated_by` = _Id_Usuario_Ejecutor,   -- Auditoría: Quién
            `updated_at` = NOW()                                          -- Auditoría: Cuándo
        WHERE `Id_DatosCap` = v_Id_Ultimo_Detalle;

        /* ---------------------------------------------------------------------------------------
           PASO 7.B.3: CONFIRMACIÓN DE TRANSACCIÓN (COMMIT)
           --------------------------------------------------------------------------------------- */
        COMMIT;
        
        /* ---------------------------------------------------------------------------------------
           PASO 7.B.4: RETORNO DE CONFIRMACIÓN AL CLIENTE
           --------------------------------------------------------------------------------------- */
        SELECT 
            'RESTAURADO' AS `Nuevo_Estado`,                       -- Estado resultante
            'Expediente restaurado exitosamente.' AS `Mensaje`,   -- Feedback
            'ESTATUS_CAMBIADO' AS Accion;                         -- Código de acción

    END IF;
    /* ===========================================================================================
       FIN DEL MOTOR DE DECISIÓN
       =========================================================================================== */

END$$

DELIMITER ;

/* ====================================================================================================
   PROCEDIMIENTO: SP_EliminarCapacitacion (HARD DELETE / BORRADO FÍSICO)
   ====================================================================================================
   
   1. FICHA TÉCNICA DE INGENIERÍA (TECHNICAL DATASHEET)
   ----------------------------------------------------
   - Nombre Oficial:      SP_EliminarCapacitacion
   - Clasificación:       Operación Destructiva de Alto Riesgo (High-Risk Destructive Operation).
   - Tipo:                Physical Delete (DELETE FROM...).
   - Nivel de Seguridad:  CRÍTICO (Requiere validación de "Hoja Limpia").
   - Aislamiento:         Serializable (vía Pessimistic Locking).

   2. PROPÓSITO Y REGLAS DE NEGOCIO (BUSINESS RULES)
   -------------------------------------------------
   Este procedimiento elimina PERMANENTEMENTE un expediente de capacitación y todo su historial de versiones
   de la base de datos. A diferencia del "Archivado" (Soft Delete), esta acción destruye los datos y
   libera el Folio.
   
   [CASO DE USO EXCLUSIVO]: 
   Corrección de errores de captura inmediata (ej: "Creé el curso duplicado por error hace 5 minutos
   y nadie se ha inscrito aún").

   [REGLA DE INTEGRIDAD ACADÉMICA - "EL ESCUDO DE ALUMNOS"]:
   Es estrictamente PROHIBIDO eliminar un curso si existe al menos un (1) participante vinculado a 
   cualquiera de sus versiones (detalles), ya sean vigentes, pasadas o archivadas.
   
   - Validación: Se escanea la tabla `Capacitaciones_Participantes` a través de todos los hijos.
   - Si hay alumnos: Se ABORTA la operación con Error 409 (Conflicto de Dependencia).
     * Razón: Borrar el curso dejaría huérfanos los registros académicos, diplomas o constancias DC-3.
   
   - Si NO hay alumnos: Se procede a la DESTRUCCIÓN EN CASCADA.
     * Paso 1: Eliminar Hijos (DatosCapacitaciones - Versiones).
     * Paso 2: Eliminar Padre (Capacitaciones - Expediente).

   3. ESTRATEGIA DE CONCURRENCIA (ACID)
   ------------------------------------
   Utiliza `SELECT ... FOR UPDATE` para bloquear el expediente padre al inicio de la transacción.
   Esto evita que, mientras el sistema verifica si hay alumnos, otro usuario inscriba a un alumno
   en el último milisegundo (Race Condition).

   ==================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_EliminarCapacitacion`$$

CREATE PROCEDURE `SP_EliminarCapacitacion`(
    /* -----------------------------------------------------------------
       PARÁMETROS DE ENTRADA
       ----------------------------------------------------------------- */
    IN _Id_Capacitacion INT -- [OBLIGATORIO] ID del Expediente Padre a destruir.
)
THIS_PROC: BEGIN

    /* ========================================================================================
       BLOQUE 0: VARIABLES DE DIAGNÓSTICO Y CONTEXTO
       ======================================================================================== */
    
    /* Variable para almacenar el conteo de alumnos (Dependencias críticas) */
    DECLARE v_Total_Alumnos INT DEFAULT 0; 
    
    /* Variable para almacenar el Folio y mostrarlo en el mensaje de éxito */
    DECLARE v_Folio VARCHAR(50);
    
    /* Bandera de existencia para el bloqueo pesimista */
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
        SET MESSAGE_TEXT = 'BLOQUEO DE SISTEMA [1451]: Integridad Referencial Estricta detectada. La base de datos impidió la eliminación física porque existen vínculos en tablas del sistema (FK) no contempladas en la validación de negocio.'; 
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
    IF _Id_Capacitacion IS NULL OR _Id_Capacitacion <= 0 THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: El Identificador de Capacitación proporcionado es inválido o nulo.';
    END IF;
    
    /* ========================================================================================
       BLOQUE 3: INICIO DE TRANSACCIÓN Y BLOQUEO DE SEGURIDAD
       ======================================================================================== */
    START TRANSACTION;

    /* ----------------------------------------------------------------------------------------
       PASO 3.1: VERIFICACIÓN DE EXISTENCIA Y BLOQUEO (FOR UPDATE)
       
       Objetivo: "Secuestrar" el registro padre (`Capacitaciones`).
       Efecto: Nadie puede inscribir alumnos, editar versiones o cambiar estatus de este curso
       mientras nosotros realizamos el análisis forense de eliminación.
       ---------------------------------------------------------------------------------------- */
    SELECT 1, `Numero_Capacitacion` 
    INTO v_Existe, v_Folio
    FROM `Capacitaciones`
    WHERE `Id_Capacitacion` = _Id_Capacitacion
    FOR UPDATE;

    /* Validación 404 */
    IF v_Existe IS NULL THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [404]: El curso que intenta eliminar no existe o ya fue borrado.';
    END IF;

    /* ========================================================================================
       BLOQUE 4: EL ESCUDO DE INTEGRIDAD (VALIDACIÓN DE DEPENDENCIAS)
       ======================================================================================== */
    
    /* ----------------------------------------------------------------------------------------
       PASO 4.1: ESCANEO DE "NIETOS" (ALUMNOS/PARTICIPANTES)
       
       Lógica de Negocio:
       Buscamos si existen registros en `Capacitaciones_Participantes` (Nietos) que estén
       vinculados a cualquier `DatosCapacitaciones` (Hijos) que pertenezca a este Padre.
       
       Criterio Estricto:
       NO filtramos por estatus. Si un alumno reprobó hace 2 años en una versión archivada,
       eso cuenta como historia académica y BLOQUEA el borrado.
       ---------------------------------------------------------------------------------------- */
    SELECT COUNT(*) INTO v_Total_Alumnos
    FROM `Capacitaciones_Participantes` `CP`
    INNER JOIN `DatosCapacitaciones` `DC` ON `CP`.`Fk_Id_DatosCap` = `DC`.`Id_DatosCap`
    WHERE `DC`.`Fk_Id_Capacitacion` = _Id_Capacitacion;

    /* [PUNTO DE BLOQUEO]: Si el contador es mayor a 0, detenemos todo. */
    IF v_Total_Alumnos > 0 THEN
        ROLLBACK; -- Liberamos el bloqueo del padre inmediatamente.
        
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ACCIÓN DENEGADA [409]: Imposible eliminar. Existen participantes/alumnos registrados en el historial de este curso (incluso en versiones anteriores). Borrarlo destruiría su historial académico. Utilice la opción de "ARCHIVAR" en su lugar.';
    END IF;

    /* ========================================================================================
       BLOQUE 5: EJECUCIÓN DE LA DESTRUCCIÓN (CASCADE DELETE SEQUENCE)
       Si llegamos aquí, el curso está "limpio" (sin alumnos). Procedemos a borrar.
       ======================================================================================== */
    
    /* ----------------------------------------------------------------------------------------
       PASO 5.1: ELIMINAR HIJOS (DETALLES/VERSIONES)
       Borramos primero la tabla hija para respetar la jerarquía de llaves foráneas manual.
       Esto elimina todas las versiones (fechas, instructores anteriores) del curso.
       ---------------------------------------------------------------------------------------- */
    DELETE FROM `DatosCapacitaciones` 
    WHERE `Fk_Id_Capacitacion` = _Id_Capacitacion;

    /* ----------------------------------------------------------------------------------------
       PASO 5.2: ELIMINAR PADRE (EXPEDIENTE MAESTRO)
       Borramos la cabecera administrativa. Esto libera el Folio para ser reutilizado si se desea.
       ---------------------------------------------------------------------------------------- */
    DELETE FROM `Capacitaciones` 
    WHERE `Id_Capacitacion` = _Id_Capacitacion;

    /* ========================================================================================
       BLOQUE 6: CONFIRMACIÓN Y RESPUESTA
       ======================================================================================== */
    
    /* Confirmamos la transacción atómica */
    COMMIT;

    /* Retorno de Feedback al usuario */
    SELECT 
        'ELIMINADO' AS `Estado_Final`,
        CONCAT('El expediente con folio "', v_Folio, '" ha sido eliminado permanentemente del sistema, junto con todo su historial de versiones.') AS `Mensaje`,
        _Id_Capacitacion AS `Id_Eliminado`;

END$$

DELIMITER ;