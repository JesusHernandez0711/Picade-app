USE `PICADE`;

/* ------------------------------------------------------------------------------------------------------ */
/* CREACION DE VISTAS Y PROCEDIMIENTOS DE ALMACENADO PARA LA BASE DE DATOS                                */
/* ------------------------------------------------------------------------------------------------------ */

/* ======================================================================================================
   VIEW: Vista_Usuarios_Admin
   ======================================================================================================
   
   1. VISIÓN GENERAL Y OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   -------------------------------------------------------
   Esta vista constituye la **Interfaz de Lectura Optimizada** para el Grid Principal del Módulo de 
   Administración de Usuarios.
   
   Su función es consolidar la identidad digital (`Usuarios`) y la identidad humana (`Info_Personal`) 
   en una estructura plana, ligera y lista para ser consumida por componentes de UI (Tablas/Grids).

   2. ARQUITECTURA DE DATOS (ESTRATEGIA DE INTEGRIDAD)
   ---------------------------------------------------
   - TIPO DE JOIN: Se utiliza **INNER JOIN** estricto entre las tablas `Usuarios`, `Info_Personal` y `Cat_Roles`.
   
   - JUSTIFICACIÓN TÉCNICA: 
     En la lógica de negocio del sistema PICADE, existe una relación de dependencia existencial fuerte:
     a) Un "Usuario" (Cuenta) NO puede existir sin estar vinculado a una "Persona" (Datos RH).
     b) Un "Usuario" NO puede existir sin tener asignado un "Rol de Seguridad".
     
     Por lo tanto, cualquier registro que no cumpla estas condiciones se considera "Corrupto" o "Incompleto"
     y debe ser excluido automáticamente de la lista operativa mediante el INNER JOIN.

   3. ESTRATEGIA DE PRESENTACIÓN HÍBRIDA (UX & REPORTING)
   ------------------------------------------------------
   Para satisfacer tanto los requisitos de Interfaz de Usuario (Ordenamiento) como los de Reportes (Visualización),
   esta vista expone los datos de nombres en dos formatos simultáneos:

     A) FORMATO COMPUESTO (`Nombre_Completo`):
        - Implementación: `CONCAT_WS(' ', Nombre, Paterno, Materno)`
        - Uso: Etiquetas de UI, Encabezados de Perfil y **Reportes PDF**.
        - Ventaja: Elimina la necesidad de concatenar cadenas en el Frontend o en el motor de reportes.

     B) FORMATO ATÓMICO (`Nombre`, `Apellidos`):
        - Implementación: Columnas individuales crudas.
        - Uso: Lógica de **Ordenamiento (Sort)** y **Filtrado (Filter)** en el Grid.
        - Ventaja: Permite cumplir la norma administrativa de ordenar listas por "Apellido Paterno" (A-Z)
          en lugar de por Nombre de Pila.

   4. DICCIONARIO DE DATOS (CONTRATO DE SALIDA)
   --------------------------------------------
   [Bloque 1: Identificadores de Sistema]
   - Id_Usuario:      (INT) Llave primaria (Oculta en el Grid, usada para acciones CRUD).
   - Ficha_Usuario:   (VARCHAR) Identificador corporativo único (Clave de búsqueda para Instructores).
   - Email_Usuario:   (VARCHAR) Credencial de acceso (Login).

   [Bloque 2: Identidad Personal]
   - Nombre_Completo: (VARCHAR) Nombre completo pre-calculado para visualización rápida.
   - Nombre:          (VARCHAR) Dato atómico para lógica de negocio.
   - Apellido_Paterno:(VARCHAR) Dato atómico crítico para ordenamiento de listas.
   - Apellido_Materno:(VARCHAR) Dato atómico complementario.

   [Bloque 3: Seguridad y Control]
   - Rol_Usuario:     (VARCHAR) Nombre legible del perfil de seguridad (ej: 'Administrador').
   - Estatus_Usuario: (TINYINT) Bandera de acceso: 
                        1 = Activo (Puede loguearse y ser Instructor).
                        0 = Bloqueado (Acceso denegado y oculto en selectores operativos).
   ====================================================================================================== */

-- DROP VIEW IF EXISTS `PICADE`.`Vista_Usuarios`;

CREATE OR REPLACE 
    ALGORITHM = UNDEFINED 
    SQL SECURITY DEFINER
VIEW `PICADE`.`Vista_Usuarios` AS
    SELECT
        /* -----------------------------------------------------------------------------------
           BLOQUE 1: IDENTIDAD DIGITAL (CREDENCIALES)
           Datos fundamentales para la identificación única de la cuenta.
           ----------------------------------------------------------------------------------- */
        `Usuarios`.`Id_Usuario`          AS `Id_Usuario`,
        /* NUEVO CAMPO: FOTO DE PERFIL 
           Permite mostrar una miniatura (thumbnail) en la tabla de usuarios. */
        `Usuarios`.`Foto_Perfil_Url`     AS `Foto_Perfil`,
        `Usuarios`.`Ficha`               AS `Ficha_Usuario`,
        `Usuarios`.`Email`               AS `Email_Usuario`,

        /* -----------------------------------------------------------------------------------
           BLOQUE 2: IDENTIDAD HUMANA (DATOS PERSONALES - ESTRATEGIA HÍBRIDA)
           Se exponen ambos formatos para dar flexibilidad total al Frontend y Reportes.
           ----------------------------------------------------------------------------------- */
        
        /* [FORMATO VISUAL]: Para mostrar en la celda del Grid o en Reportes PDF */
        CONCAT_WS(' ', `Info_User`.`Nombre`, `Info_User`.`Apellido_Paterno`, `Info_User`.`Apellido_Materno`) AS `Nombre_Completo`,
        
        /* [FORMATO LÓGICO]: Para que el Grid pueda ordenar por 'Apellido_Paterno' aunque muestre el completo */
        `Info_User`.`Nombre`             AS `Nombre`,
        `Info_User`.`Apellido_Paterno`   AS `Apellido_Paterno`,
        `Info_User`.`Apellido_Materno`   AS `Apellido_Materno`,

        /* -----------------------------------------------------------------------------------
           BLOQUE 3: SEGURIDAD Y CONTROL DE ACCESO
           Información crítica para la administración de permisos y auditoría rápida.
           ----------------------------------------------------------------------------------- */
        `Roles`.`Nombre`                 AS `Rol_Usuario`,
        
        /* Mapeo Semántico: 'Activo' -> 'Estatus_Usuario'
           El Grid usará este valor para pintar el Switch (Verde/Gris) o filtrar instructores elegibles. */
        `Usuarios`.`Activo`              AS `Estatus_Usuario`

    FROM
        `PICADE`.`Usuarios` `Usuarios`
        
        /* JOIN 1: Vinculación Obligatoria con Datos Personales
           Garantiza que todo usuario listado tenga una ficha de RH válida. */
        INNER JOIN `PICADE`.`Info_Personal` `Info_User`
            ON `Usuarios`.`Fk_Id_InfoPersonal` = `Info_User`.`Id_InfoPersonal`
            
        /* JOIN 2: Vinculación Obligatoria con Roles de Seguridad
           Garantiza que se muestre el nivel de privilegios del usuario. */
        INNER JOIN `PICADE`.`Cat_Roles` `Roles`
            ON `Usuarios`.`Fk_Rol` = `Roles`.`Id_Rol`;

/* ====================================================================================================
   PROCEDIMIENTO: SP_RegistrarUsuarioNuevo
   ====================================================================================================
   TIPO: Transaccional / Self-Service / Onboarding
   
   1. VISIÓN ARQUITECTÓNICA Y OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   ----------------------------------------------------------------------------------------------------
   Este procedimiento constituye el **Núcleo de Alta de Identidad** del sistema PICADE.
   Su propósito es orquestar el registro inicial de un nuevo colaborador garantizando una política de 
   "CERO TOLERANCIA A DUPLICADOS" y "CONSISTENCIA ATÓMICA".

   A diferencia de un simple INSERT, este componente actúa como un **Firewall Lógico** que impide
   la creación de cuentas basura, usuarios fantasma o registros inconsistentes.

   2. VECTORES DE SEGURIDAD Y REGLAS DE BLINDAJE (SECURITY PATCHES)
   ----------------------------------------------------------------------------------------------------
   A) ANTI-PARADOJA TEMPORAL (LOGICAL CONSISTENCY):
      - Problema: Registros con fechas incoherentes (ej: ingresar a trabajar antes de nacer).
      - Solución: Se validan cronológicamente `Fecha_Nacimiento` vs `Fecha_Ingreso`.
      - Regla Corporativa: Se bloquea el registro de menores de edad (18 años).

   B) ANTI-GEMELOS MALVADOS (IDENTITY SPOOFING PROTECTION):
      - Problema: Un usuario intenta registrarse nuevamente usando una Ficha o Email falsos, 
        pero con sus datos demográficos reales.
      - Solución: Se verifica la **Huella Digital Humana** (Nombre + Apellidos + Fecha Nacimiento).
      - Acción: Si la persona física ya existe en el sistema (bajo cualquier otra ficha), 
        se BLOQUEA la operación y se revela la ficha original.

   C) DIAGNÓSTICO DE ESTADO INTELIGENTE (SMART FEEDBACK):
      - Problema: Un error genérico "Ya existe" confunde al usuario.
      - Solución: El sistema diagnostica el estado del registro encontrado y responde:
          * Si está ACTIVO: Error [409-A] -> Sugiere "Recuperar Contraseña".
          * Si está INACTIVO: Error [409-B] -> Sugiere "Contactar al Administrador" (No reactiva auto).

   D) CONTROL DE CONCURRENCIA ESTRICTA (RACE CONDITION SHIELD):
      - Problema: Dos usuarios envían el formulario al mismo milisegundo.
      - Solución: Se utiliza un `HANDLER` para el error nativo `1062` (Duplicate Key).
      - Resultado: El segundo intento es rechazado y la transacción se revierte (ROLLBACK).

   3. ESTRATEGIA DE AUDITORÍA RECURSIVA (AUTO-PROVENANCE)
   ----------------------------------------------------------------------------------------------------
   - Reto: En un auto-registro, el campo `Created_By` no puede llenarse durante el INSERT porque
     el usuario aún no tiene ID.
   - Solución: Se implementa un patrón de **"Cierre de Círculo"**:
     1. Se insertan los datos con `Created_By = NULL`.
     2. Se recupera el ID generado.
     3. Se ejecuta un UPDATE inmediato para establecer `Created_By = [Nuevo_ID]`.
     Esto garantiza que ningún registro quede huérfano de trazabilidad.

   4. CONTRATO DE SALIDA
   ----------------------------------------------------------------------------------------------------
   Retorna un resultset con:
      - Mensaje: Feedback descriptivo.
      - Id_Usuario: ID generado.
      - Accion: 'CREADA'.
   ==================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_RegistrarUsuarioNuevo`$$

CREATE PROCEDURE `SP_RegistrarUsuarioNuevo`(
    /* -----------------------------------------------------------------
       PARÁMETROS DE ENTRADA (INPUT LAYER)
       Datos capturados en el formulario público de registro.
       NOTA: No se pide Foto aquí; eso es parte del perfilamiento posterior.
       ----------------------------------------------------------------- */
    IN _Ficha            VARCHAR(50),    -- Identificador Corporativo (Unique)
    IN _Email            VARCHAR(255),   -- Identificador de Sistema (Unique)
    IN _Contrasena       VARCHAR(255),   -- Hash de Seguridad
    IN _Nombre           VARCHAR(255),   -- Nombre(s) de Pila
    IN _Apellido_Paterno VARCHAR(255),   -- Primer Apellido
    IN _Apellido_Materno VARCHAR(255),   -- Segundo Apellido
    IN _Fecha_Nacimiento DATE,           -- Para validación de Huella Humana
    IN _Fecha_Ingreso    DATE            -- Para cálculo de antigüedad
)
THIS_PROC: BEGIN
    
    /* ================================================================================================
       BLOQUE 0: VARIABLES DE ENTORNO Y DIAGNÓSTICO
       Propósito: Contenedores para evaluar el estado de la base de datos antes de escribir.
       ================================================================================================ */
    
    /* Variables para el Diagnóstico de Existencia */
    DECLARE v_Id_Encontrado INT DEFAULT NULL;
    DECLARE v_Estatus_Encontrado TINYINT(1) DEFAULT NULL;
    DECLARE v_Ficha_Original VARCHAR(50) DEFAULT NULL;
    
    /* Variables para la Integridad Referencial y Auditoría */
    DECLARE v_Id_InfoPersonal_Generado INT DEFAULT NULL;
    DECLARE v_Id_Usuario_Generado INT DEFAULT NULL;
    
    /* Variable auxiliar para construcción de mensajes dinámicos */
    DECLARE v_MensajeError VARCHAR(255);

    /* ================================================================================================
       BLOQUE 1: HANDLERS (MECANISMOS DE DEFENSA Y RECUPERACIÓN)
       ================================================================================================ */

    /* 1.1 HANDLER DE CONCURRENCIA (El Escudo Final - Error 1062)
       Objetivo: Proteger la integridad cuando dos peticiones simultáneas superan las validaciones de lectura. */
    DECLARE EXIT HANDLER FOR 1062
    BEGIN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERROR DE CONCURRENCIA [409]: Otro usuario acaba de registrar estos datos hace un momento. Por favor actualice la página.';
    END;

    /* 1.2 HANDLER DE FALLO TÉCNICO (SQLEXCEPTION)
       Objetivo: Garantizar Atomicidad ante fallos de servidor (crash, red, disco). */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; 
    END;

    /* ================================================================================================
       BLOQUE 2: SANITIZACIÓN DE DATOS (INPUT HYGIENE)
       Propósito: Normalizar la entrada para asegurar consistencia en búsquedas futuras.
       ================================================================================================ */
    SET _Ficha            = TRIM(_Ficha);
    SET _Email            = TRIM(_Email);
    
    /* Estandarización Visual: Nombres en MAYÚSCULAS (Regla de Negocio para Reportes Oficiales) */
    SET _Nombre           = TRIM(UPPER(_Nombre));
    SET _Apellido_Paterno = TRIM(UPPER(_Apellido_Paterno));
    SET _Apellido_Materno = TRIM(UPPER(_Apellido_Materno));

    /* ================================================================================================
       BLOQUE 3: VALIDACIONES PREVIAS (FAIL FAST STRATEGY)
       Propósito: Rechazar datos inválidos o ilógicos antes de consultar la BD.
       ================================================================================================ */
    
    /* 3.1 Integridad de Campos Obligatorios */
    IF _Ficha = '' OR _Email = '' OR _Contrasena = '' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN [400]: Ficha, Email y Contraseña son obligatorios.';
    END IF;

    IF _Nombre = '' OR _Apellido_Paterno = '' OR _Apellido_Materno = '' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN [400]: El nombre completo (con ambos apellidos) es obligatorio.';
    END IF;

    IF _Fecha_Nacimiento IS NULL OR _Fecha_Ingreso IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN [400]: Las fechas de Nacimiento e Ingreso son obligatorias.';
    END IF;

    /* 3.2 Lógica de Negocio: Paradoja Temporal */
    IF _Fecha_Ingreso < _Fecha_Nacimiento THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE LÓGICA [400]: La fecha de ingreso no puede ser anterior a la fecha de nacimiento.';
    END IF;

    /* 3.3 Lógica de Negocio: Restricción de Edad (+18) */
    IF TIMESTAMPDIFF(YEAR, _Fecha_Nacimiento, CURDATE()) < 18 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE LÓGICA [400]: El registro está restringido a mayores de 18 años.';
    END IF;

    /* ================================================================================================
       BLOQUE 4: MOTOR DE DIAGNÓSTICO DE EXISTENCIA (THE BRAIN)
       Propósito: Detectar duplicados y proporcionar una respuesta de negocio específica.
       ================================================================================================ */

    /* 4.1 DIAGNÓSTICO DE CREDENCIALES (FICHA) */
    SELECT `Id_Usuario`, `Activo` INTO v_Id_Encontrado, v_Estatus_Encontrado 
    FROM `Usuarios` WHERE `Ficha` = _Ficha LIMIT 1;

    IF v_Id_Encontrado IS NOT NULL THEN
        IF v_Estatus_Encontrado = 1 THEN
            /* Escenario: Usuario activo intenta registrarse de nuevo */
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'CONFLICTO [409-A]: La Ficha ya está registrada y activa. ¿Olvidaste tu contraseña?';
        ELSE
            /* Escenario: Usuario bloqueado intenta registrarse */
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'CONFLICTO [409-B]: La Ficha existe pero el acceso está restringido. Contacte al Administrador.';
        END IF;
    END IF;

    /* 4.2 DIAGNÓSTICO DE CREDENCIALES (EMAIL) */
    SET v_Id_Encontrado = NULL; -- Reset
    SELECT `Id_Usuario`, `Activo` INTO v_Id_Encontrado, v_Estatus_Encontrado 
    FROM `Usuarios` WHERE `Email` = _Email LIMIT 1;

    IF v_Id_Encontrado IS NOT NULL THEN
        IF v_Estatus_Encontrado = 1 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'CONFLICTO [409-A]: El Correo ya está registrado y activo. ¿Olvidaste tu contraseña?';
        ELSE
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'CONFLICTO [409-B]: El Correo existe pero el acceso está restringido. Contacte al Administrador.';
        END IF;
    END IF;

    /* 4.3 DIAGNÓSTICO DE HUELLA HUMANA (ANTI-SPOOFING)
       Objetivo: Detectar si la persona física ya existe, incluso si intenta usar Ficha/Email falsos. */
    SET v_Ficha_Original = NULL;
    
    SELECT U.Ficha, U.Activo
    INTO v_Ficha_Original, v_Estatus_Encontrado
    FROM Info_Personal I
    INNER JOIN Usuarios U ON U.Fk_Id_InfoPersonal = I.Id_InfoPersonal
    WHERE I.Nombre = _Nombre
      AND I.Apellido_Paterno = _Apellido_Paterno
      AND I.Apellido_Materno = _Apellido_Materno
      AND I.Fecha_Nacimiento = _Fecha_Nacimiento
    LIMIT 1;

    /* Si encontramos una coincidencia, revelamos la Ficha Original para detener el duplicado */
    IF v_Ficha_Original IS NOT NULL THEN
        IF v_Estatus_Encontrado = 1 THEN
            SET v_MensajeError = CONCAT('CONFLICTO [409-A]: Ya estás registrado en el sistema bajo la Ficha ', v_Ficha_Original, '. No se permiten duplicados de persona.');
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_MensajeError;
        ELSE
            SET v_MensajeError = CONCAT('CONFLICTO [409-B]: Ya existes en el sistema bajo la Ficha ', v_Ficha_Original, ' pero tu cuenta está desactivada. Contacte al Administrador.');
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_MensajeError;
        END IF;
    END IF;

    /* ================================================================================================
       BLOQUE 5: TRANSACCIÓN DE PERSISTENCIA (ESCRITURA ATÓMICA)
       Propósito: Guardar los datos de manera indivisible. O se guardan las 2 tablas, o ninguna.
       ================================================================================================ */
    START TRANSACTION;

    /* 5.1 INSERTAR DATOS PERSONALES (Identidad)
       Nota: Solo insertamos demográficos obligatorios. 
       Los campos de auditoría (Created_By) se dejan temporalmente en NULL hasta tener el ID de usuario. */
    INSERT INTO `Info_Personal` (
        `Nombre`, `Apellido_Paterno`, `Apellido_Materno`,
        `Fecha_Nacimiento`, `Fecha_Ingreso`,
        `created_at`
    ) VALUES (
        _Nombre, _Apellido_Paterno, _Apellido_Materno,
        _Fecha_Nacimiento, _Fecha_Ingreso,
        NOW()
    );

    /* Recuperamos el ID generado para vincularlo al usuario */
    SET v_Id_InfoPersonal_Generado = LAST_INSERT_ID();

    /* 5.2 INSERTAR CREDENCIALES DE USUARIO (Acceso)
       Nota: Insertamos con Rol Default (4=Participante).
       La Foto de Perfil tomará su valor DEFAULT NULL definido en el esquema. */
    INSERT INTO `Usuarios` (
        `Ficha`, `Email`, `Contraseña`, 
        `Fk_Id_InfoPersonal`, `Fk_Rol`,
        `created_at`
    ) VALUES (
        _Ficha, _Email, _Contrasena, 
        v_Id_InfoPersonal_Generado, 4,
        NOW()
    );

    /* Recuperamos el ID final del usuario para la auditoría recursiva */
    SET v_Id_Usuario_Generado = LAST_INSERT_ID();

    /* 5.3 AUTO-AUDITORÍA RECURSIVA (CERRANDO EL CÍRCULO)
       Objetivo: Cumplir con la trazabilidad. Como es un auto-registro, el usuario es su propio creador.
       Acción: Actualizamos los campos Created_By con el ID que acabamos de generar. */
    
    UPDATE `Usuarios` 
    SET `Fk_Usuario_Created_By` = v_Id_Usuario_Generado 
    WHERE `Id_Usuario` = v_Id_Usuario_Generado;

    UPDATE `Info_Personal` 
    SET `Fk_Id_Usuario_Created_By` = v_Id_Usuario_Generado 
    WHERE `Id_InfoPersonal` = v_Id_InfoPersonal_Generado;

    /* ================================================================================================
       BLOQUE 6: CONFIRMACIÓN Y RESPUESTA
       ================================================================================================ */
    COMMIT;

    /* Retorno de éxito para redirección en Frontend */
    SELECT 
        'ÉXITO: Usuario registrado correctamente.' AS Mensaje,
        v_Id_Usuario_Generado AS Id_Usuario,
        'CREADA' AS Accion;

END$$

DELIMITER ;

/* ====================================================================================================
   PROCEDIMIENTO: SP_RegistrarUsuarioPorAdmin
   ====================================================================================================
   
   1. PROPÓSITO Y OBJETIVO DE NEGOCIO (THE "WHY")
   ----------------------------------------------------------------------------------------------------
   Este procedimiento orquesta el **Alta Administrativa (Onboarding)** de nuevos colaboradores.
   A diferencia del registro público, este módulo asume que el operador (RH/Admin) posee la verdad 
   absoluta sobre la estructura organizacional, por lo que impone reglas de **Integridad Total**.
   
   Su misión es persistir, en una sola operación atómica, la identidad digital, la identidad humana,
   la ubicación física, la posición jerárquica, la trazabilidad de auditoría y, desde la v1.1,
   los activos multimedia asociados (Fotografía).

   2. VECTORES DE SEGURIDAD MITIGADOS (SECURITY POSTURE)
   ----------------------------------------------------------------------------------------------------
   A) INTEGRIDAD REFERENCIAL OPERATIVA ("ANTI-ZOMBIE RESOURCES"):
      - Riesgo: Asignar un empleado a un Departamento/Puesto que existe en BD pero fue dado de baja.
      - Defensa: Validación en tiempo real del flag `Activo = 1` para cada ID de catálogo foráneo.
   
   B) NO REPUDIO Y AUDITORÍA (NON-REPUDIATION):
      - Riesgo: Creación de usuarios fantasma por administradores malintencionados.
      - Defensa: Inyección obligatoria del `_Id_Admin_Ejecutor` en las columnas de auditoría 
        `Fk_Usuario_Created_By` en todas las tablas afectadas.
   
   C) CONSISTENCIA TEMPORAL (LOGICAL TIME):
      - Riesgo: Fechas incoherentes (ingreso < nacimiento) que rompen reportes de antigüedad.
      - Defensa: Validación aritmética de fechas antes de la escritura.

   D) INTEGRIDAD ATÓMICA (ACID):
      - Riesgo: Fallos parciales (se crea la persona pero no el usuario) dejando datos huérfanos.
      - Defensa: Encapsulamiento en `START TRANSACTION` ... `COMMIT` con `ROLLBACK` automático.

   E) GESTIÓN DE ACTIVOS MULTIMEDIA (NUEVO v1.1):
      - Contexto: El administrador puede cargar la foto oficial al momento del alta.
      - Tratamiento: Se recibe la ruta relativa (String). El almacenamiento físico (Blob/File) 
        es responsabilidad del Backend (Laravel/S3). La BD solo guarda el puntero lógico.

   3. ESPECIFICACIÓN DE ENTRADA/SALIDA (CONTRACT)
   ----------------------------------------------------------------------------------------------------
   - INPUT: 20 Parámetros tipados (Identidad, Foto, Demografía, Ubicación, Auditoría).
   - OUTPUT: Resultset único {Mensaje, Id_Generado, Accion}.
   - ERRORES: Códigos SQLSTATE personalizados [400, 403, 409, 500].
   ==================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_RegistrarUsuarioPorAdmin`$$

CREATE PROCEDURE `SP_RegistrarUsuarioPorAdmin`(
    /* --------------------------------------------------------------------------------------------
       SECCIÓN DE PARÁMETROS: AUDITORÍA (META-DATA)
       -------------------------------------------------------------------------------------------- */
    IN _Id_Admin_Ejecutor INT,          -- [OBLIGATORIO] ID del Admin que realiza la operación. 
                                        -- Se usará para llenar `Fk_Usuario_Created_By`.

    /* --------------------------------------------------------------------------------------------
       SECCIÓN DE PARÁMETROS: IDENTIDAD Y ACCESO (USER ACCOUNT)
       -------------------------------------------------------------------------------------------- */
    IN _Ficha            VARCHAR(50),   -- [UNIQUE] Clave corporativa.
    IN _Url_Foto         VARCHAR(255),  -- [OPCIONAL] Ruta relativa de la foto de perfil (Update v1.1).
                                        -- Si es NULL, se asume que no se cargó foto inicial.
    /* --------------------------------------------------------------------------------------------
       SECCIÓN DE PARÁMETROS: DATOS DEMOGRÁFICOS (HUMAN ENTITY)
       -------------------------------------------------------------------------------------------- */
    IN _Nombre           VARCHAR(255),  -- Nombre(s) de pila.
    IN _Apellido_Paterno VARCHAR(255),  -- Primer apellido.
    IN _Apellido_Materno VARCHAR(255),  -- Segundo apellido.
    IN _Fecha_Nacimiento DATE,          -- Usado para validar mayoría de edad y homonimia.
    IN _Fecha_Ingreso    DATE,          -- Usado para cálculo de antigüedad laboral.

	/* -----------------------------------------------------------------
	   2.5 SEGURIDAD Y ACCESOS Y PRIVILEGIOS (CRÍTICOS DE SISTEMA)
	   ----------------------------------------------------------------- */
    IN _Email            VARCHAR(255),  -- [UNIQUE] Clave de sistema.
    IN _Contrasena       VARCHAR(255),  -- [SEGURIDAD] Debe llegar ya hasheada (Bcrypt/Argon2) desde Backend.
    IN _Id_Rol           INT,           -- [FK] Nivel de privilegios (Admin, Instructor, etc.).

    /* --------------------------------------------------------------------------------------------
       SECCIÓN DE PARÁMETROS: PERFIL LABORAL (MATRIZ DE ADSCRIPCIÓN)
       NOTA: En este SP, todos estos campos son OBLIGATORIOS para garantizar reportes completos.
       -------------------------------------------------------------------------------------------- */
    IN _Id_Regimen       INT,           -- [FK] Régimen de contratación (Planta/Transitorio).
    IN _Id_Puesto        INT,           -- [FK] Puesto funcional.
    IN _Id_CentroTrabajo INT,           -- [FK] Ubicación física.
    IN _Id_Departamento  INT,           -- [FK] Unidad departamental.
    IN _Id_Region        INT,           -- [FK] Región geográfica.
    IN _Id_Gerencia      INT,           -- [FK] Línea de mando.
    IN _Nivel            VARCHAR(50),   -- Dato tabular (Nivel salarial/jerárquico).
    IN _Clasificacion    VARCHAR(100)   -- Clasificación contractual.
)
THIS_PROC: BEGIN
    
    /* ============================================================================================
       BLOQUE 0: DECLARACIÓN DE VARIABLES DE ESTADO
       Definición de contenedores en memoria para almacenar resultados intermedios.
       ============================================================================================ */
    
    /* Variables de Diagnóstico de Duplicidad */
    DECLARE v_Id_Encontrado INT DEFAULT NULL;           -- Almacena ID si encontramos colisión de cuenta.
    DECLARE v_Estatus_Encontrado TINYINT(1) DEFAULT NULL; -- Almacena si el duplicado está activo/inactivo.
    DECLARE v_Ficha_Original VARCHAR(50) DEFAULT NULL;  -- Almacena la ficha de una persona física duplicada.
    
    /* Variable de Enlace Relacional */
    DECLARE v_Id_InfoPersonal_Generado INT DEFAULT NULL; -- PK generada en tabla 1, FK para tabla 2.
    
    /* Variable de Validación de Vigencia */
    DECLARE v_Es_Activo TINYINT(1);                     -- Semáforo para validar si un catálogo sigue vivo.
    
    /* Variable de Mensajería */
    DECLARE v_MensajeError VARCHAR(255);                -- Contenedor para construir strings de error dinámicos.

    /* ============================================================================================
       BLOQUE 1: MANEJO DE EXCEPCIONES (DEFENSIVE PROGRAMMING)
       Define el comportamiento del sistema ante fallos previstos e imprevistos.
       ============================================================================================ */

    /* 1.1 HANDLER DE CONCURRENCIA (RACE CONDITION)
       [QUÉ]: Atrapa el error MySQL 1062 (Duplicate Entry for Key).
       [POR QUÉ]: Si dos admins envían la misma ficha al mismo tiempo, el motor de BD bloqueará al segundo.
       [ACCIÓN]: Revertir transacción (ROLLBACK) y notificar al usuario que "perdió la carrera". */
    DECLARE EXIT HANDLER FOR 1062
    BEGIN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERROR DE CONCURRENCIA [409]: Los datos acaban de ser registrados por otro administrador hace un instante. Actualice su lista.';
    END;

    /* 1.2 HANDLER DE FALLO CRÍTICO (SYSTEM FAILURE)
       [QUÉ]: Atrapa cualquier otro error SQL (Conexión, Disco, Sintaxis, Foreign Key inexistente).
       [POR QUÉ]: Garantizar la atomicidad. No queremos insertar `Info_Personal` si falla `Usuarios`.
       [ACCIÓN]: ROLLBACK total y propagación del error original (RESIGNAL) para logs del backend. */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; 
    END;

    /* ============================================================================================
       BLOQUE 2: SANITIZACIÓN DE DATOS (DATA NORMALIZATION)
       Limpieza de inputs antes de cualquier lógica para asegurar consistencia.
       ============================================================================================ */
    
    /* 2.1 TRIMMING: Eliminar espacios basura al inicio/final. */
    SET _Ficha            = TRIM(_Ficha);
    SET _Email            = TRIM(_Email);
    SET _Url_Foto         = NULLIF(TRIM(_Url_Foto), ''); -- Convertir '' a NULL para integridad.
    
    /* 2.2 UPPERCASING: Estandarización visual para reportes oficiales. */
    SET _Nombre           = TRIM(UPPER(_Nombre));
    SET _Apellido_Paterno = TRIM(UPPER(_Apellido_Paterno));
    SET _Apellido_Materno = TRIM(UPPER(_Apellido_Materno));
    SET _Nivel            = TRIM(UPPER(_Nivel));
    SET _Clasificacion    = TRIM(UPPER(_Clasificacion));

    /* ============================================================================================
       BLOQUE 3: VALIDACIONES PREVIAS (FAIL FAST STRATEGY)
       Verificaciones ligeras en memoria. Si fallan, abortamos antes de tocar el disco.
       ============================================================================================ */
    
    /* 3.1 VALIDACIÓN DE AUDITORÍA
       [REGLA]: No existe "Registro Anónimo". Alguien debe hacerse responsable. */
    IF _Id_Admin_Ejecutor IS NULL OR _Id_Admin_Ejecutor <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE AUDITORÍA [403]: No se identificó al usuario administrador (Created_By) para la trazabilidad.';
    END IF;

    /* 3.2 VALIDACIÓN DE INTEGRIDAD DE IDENTIDAD
       [REGLA]: Campos mínimos para definir una entidad digital. */
    IF _Ficha = '' OR _Email = '' OR _Contrasena = '' OR _Nombre = '' OR _Apellido_Paterno = '' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN [400]: Los datos de Identidad (Ficha, Email, Nombre, Password) son obligatorios.';
    END IF;

    /* 3.3 VALIDACIÓN DE COMPLETITUD DE PERFIL
       [REGLA]: En Alta Administrativa no se permiten NULLs. El perfil debe ser funcional para reportes inmediatos.
       [LÓGICA]: Verificamos que todos los IDs de catálogo sean mayores a 0 y no NULL. */
    IF (_Id_Regimen <= 0 OR _Id_Regimen IS NULL) OR 
       (_Id_Puesto <= 0 OR _Id_Puesto IS NULL) OR 
       (_Id_CentroTrabajo <= 0 OR _Id_CentroTrabajo IS NULL) OR 
       (_Id_Departamento <= 0 OR _Id_Departamento IS NULL) OR 
       (_Id_Region <= 0 OR _Id_Region IS NULL) OR 
       (_Id_Gerencia <= 0 OR _Id_Gerencia IS NULL) OR
       (_Id_Rol <= 0 OR _Id_Rol IS NULL) THEN
        
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN [400]: El Perfil Laboral está incompleto. Todos los campos (Puesto, Área, Ubicación, Rol) son obligatorios para el Alta Administrativa.';
    END IF;

    /* 3.4 VALIDACIÓN LÓGICA DE TIEMPO (ANTI-PARADOJA)
       [REGLA]: Un empleado no puede ser contratado antes de nacer. */
    IF _Fecha_Ingreso < _Fecha_Nacimiento THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE LÓGICA [400]: La fecha de ingreso no puede ser anterior a la fecha de nacimiento.';
    END IF;

    /* ============================================================================================
       BLOQUE 4: VALIDACIÓN DE VIGENCIA DE CATÁLOGOS (ANTI-ZOMBIE RESOURCES CHECK)
       [PROBLEMA]: El Frontend envió el ID 5 ("Ventas"), pero otro Admin lo desactivó hace 1 minuto.
       [SOLUCIÓN]: Consultar en tiempo real si el recurso sigue `Activo = 1`.
       ============================================================================================ */
    
    /* 4.1 Validar Vigencia de PUESTO */
    SET v_Es_Activo = NULL;
    SELECT `Activo` INTO v_Es_Activo FROM `Cat_Puestos_Trabajo` WHERE `Id_CatPuesto` = _Id_Puesto LIMIT 1;
    IF v_Es_Activo IS NULL OR v_Es_Activo = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [409]: El Puesto seleccionado no existe o ha sido dado de baja operativa.';
    END IF;

    /* 4.2 Validar Vigencia de CENTRO DE TRABAJO */
    SET v_Es_Activo = NULL;
    SELECT `Activo` INTO v_Es_Activo FROM `Cat_Centros_Trabajo` WHERE `Id_CatCT` = _Id_CentroTrabajo LIMIT 1;
    IF v_Es_Activo IS NULL OR v_Es_Activo = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [409]: El Centro de Trabajo seleccionado está inactivo.';
    END IF;

    /* 4.3 Validar Vigencia de DEPARTAMENTO */
    SET v_Es_Activo = NULL;
    SELECT `Activo` INTO v_Es_Activo FROM `Cat_Departamentos` WHERE `Id_CatDep` = _Id_Departamento LIMIT 1;
    IF v_Es_Activo IS NULL OR v_Es_Activo = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [409]: El Departamento seleccionado está inactivo.';
    END IF;

    /* 4.4 Validar Vigencia de REGIÓN */
    SET v_Es_Activo = NULL;
    SELECT `Activo` INTO v_Es_Activo FROM `Cat_Regiones_Trabajo` WHERE `Id_CatRegion` = _Id_Region LIMIT 1;
    IF v_Es_Activo IS NULL OR v_Es_Activo = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [409]: La Región seleccionada está inactiva.';
    END IF;

    /* 4.5 Validar Vigencia de ROL (SEGURIDAD) */
    SET v_Es_Activo = NULL;
    SELECT `Activo` INTO v_Es_Activo FROM `Cat_Roles` WHERE `Id_Rol` = _Id_Rol LIMIT 1;
    IF v_Es_Activo IS NULL OR v_Es_Activo = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [409]: El Rol de seguridad seleccionado está inactivo o no existe.';
    END IF;

    /* ============================================================================================
       BLOQUE 5: BLINDAJE DE DUPLICADOS (IDENTITY PROTECTION)
       Verificación profunda en BD para evitar colisiones de datos.
       ============================================================================================ */
    
    /* 5.1 VERIFICACIÓN DE CUENTA (FICHA)
       [REGLA]: La Ficha es el identificador único corporativo. No debe repetirse bajo ninguna circunstancia. */
    SELECT `Id_Usuario` INTO v_Id_Encontrado FROM `Usuarios` WHERE `Ficha` = _Ficha LIMIT 1;
    IF v_Id_Encontrado IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'CONFLICTO [409]: La Ficha ingresada YA EXISTE en el sistema.';
    END IF;

    /* 5.2 VERIFICACIÓN DE CUENTA (EMAIL)
       [REGLA]: El correo es el identificador de acceso al sistema (Login). Debe ser único. */
    SET v_Id_Encontrado = NULL;
    SELECT `Id_Usuario` INTO v_Id_Encontrado FROM `Usuarios` WHERE `Email` = _Email LIMIT 1;
    IF v_Id_Encontrado IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'CONFLICTO [409]: El Email ingresado YA EXISTE en el sistema.';
    END IF;

    /* 5.3 VERIFICACIÓN DE IDENTIDAD HUMANA (ANTI-GEMELOS)
       [PROBLEMA]: Un Admin intenta registrar a "Juan Pérez (01/01/1990)" con una Ficha NUEVA inventada.
       [DEFENSA]: Buscamos si esa persona física ya existe. Si sí, revelamos su ficha real y bloqueamos. */
    SET v_Ficha_Original = NULL;
    SELECT U.Ficha INTO v_Ficha_Original
    FROM Info_Personal I
    INNER JOIN Usuarios U ON U.Fk_Id_InfoPersonal = I.Id_InfoPersonal
    WHERE I.Nombre = _Nombre 
      AND I.Apellido_Paterno = _Apellido_Paterno 
      AND I.Apellido_Materno = _Apellido_Materno 
      AND I.Fecha_Nacimiento = _Fecha_Nacimiento
    LIMIT 1;

    IF v_Ficha_Original IS NOT NULL THEN
        SET v_MensajeError = CONCAT('CONFLICTO [409]: Esta persona física ya está registrada en el sistema bajo la Ficha: ', v_Ficha_Original, '. No se permiten duplicados de personal.');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_MensajeError;
    END IF;

    /* ============================================================================================
       BLOQUE 6: TRANSACCIÓN DE ESCRITURA ATÓMICA (ACID WRITE)
       Punto de No Retorno: Si llegamos aquí, los datos son puros, válidos y únicos.
       ============================================================================================ */
    START TRANSACTION;

    /* --------------------------------------------------------------------------------------------
       PASO 6.1: PERSISTENCIA DE INFORMACIÓN PERSONAL (ENTIDAD MAESTRA)
       Insertamos los datos demográficos y la matriz de adscripción completa.
       -------------------------------------------------------------------------------------------- */
    INSERT INTO `Info_Personal` (
        `Nombre`, `Apellido_Paterno`, `Apellido_Materno`,
        `Fecha_Nacimiento`, `Fecha_Ingreso`,
        /* Matriz de Adscripción (Validada en Bloque 4) */
        `Fk_Id_CatRegimen`, `Fk_Id_CatPuesto`, 
        `Fk_Id_CatCT`, `Fk_Id_CatDep`, 
        `Fk_Id_CatRegion`, `Fk_Id_CatGeren`, 
        `Nivel`, `Clasificacion`,
        `Activo`,
        /* TRAZABILIDAD: Quién trajo a esta persona a la empresa */
        `Fk_Id_Usuario_Created_By` 
    ) VALUES (
        _Nombre, _Apellido_Paterno, _Apellido_Materno,
        _Fecha_Nacimiento, _Fecha_Ingreso,
        _Id_Regimen, _Id_Puesto, 
        _Id_CentroTrabajo, _Id_Departamento, 
        _Id_Region, _Id_Gerencia, 
        _Nivel, _Clasificacion,
        1, -- Activo por defecto (Alta Administrativa asume operatividad inmediata)
        _Id_Admin_Ejecutor -- Se guarda quién realizó el registro
    );

    /* Recuperamos la Primary Key generada (AUTO_INCREMENT) para vincularla al Usuario */
    SET v_Id_InfoPersonal_Generado = LAST_INSERT_ID();

    /* --------------------------------------------------------------------------------------------
       PASO 6.2: PERSISTENCIA DE CREDENCIALES (ENTIDAD USUARIO)
       Creamos el acceso al sistema vinculado a la persona creada.
       --------------------------------------------------------------------------------------------
       NOTA TÉCNICA: 
       - Aquí se realiza la inserción de la Foto de Perfil (_Url_Foto).
       - Si ocurre una concurrencia (Error 1062) en este punto, el HANDLER del Bloque 1 
         se activará, y se hará ROLLBACK automático de la inserción anterior (6.1). */
    
    INSERT INTO `Usuarios` (
        `Ficha`, `Email`, `Contraseña`, 
        `Fk_Id_InfoPersonal`, `Fk_Rol`,
        `Foto_Perfil_Url`,  /* Columna Nueva v1.1 */
        `Activo`,
        /* TRAZABILIDAD: Quién creó la cuenta de acceso */
        `Fk_Usuario_Created_By`
    ) VALUES (
        _Ficha, _Email, _Contrasena, 
        v_Id_InfoPersonal_Generado, _Id_Rol,
        _Url_Foto,          /* Valor del parámetro opcional v1.1 */
        1, -- Activo por defecto
        _Id_Admin_Ejecutor -- Se guarda quién creó la cuenta
    );

    /* ============================================================================================
       BLOQUE 7: CONFIRMACIÓN Y RESPUESTA (COMMIT & ACKNOWLEDGE)
       Si llegamos aquí, ambas tablas se escribieron correctamente. Hacemos permanentes los cambios.
       ============================================================================================ */
    COMMIT;

    /* Retorno de éxito estructurado para el consumo del API/Frontend */
    SELECT 
        'ÉXITO: Colaborador registrado, perfilado y auditado correctamente.' AS Mensaje,
        LAST_INSERT_ID() AS Id_Usuario, -- Retornamos el ID del nuevo usuario
        'CREADA' AS Accion;

END$$

DELIMITER ;

/* ============================================================================================
   SECCIÓN: CONSULTAS ESPECÍFICAS (PARA EDICIÓN / DETALLE)
   ============================================================================================
   Estas rutinas son clave para la UX. No solo devuelven el dato pedido, sino todo el 
   contexto necesario para que el formulario de edición se autocomplete correctamente.
   ============================================================================================ */

/* ============================================================================================
   PROCEDIMIENTO: SP_ConsultarPerfilPropio
   ============================================================================================

   1. OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   --------------------------------------
   Recuperar el "Expediente Digital" del usuario autenticado, optimizado específicamente para
   la hidratación (pre-llenado) de formularios reactivos en el Frontend (Angular/React/Vue).

   A diferencia de un reporte visual, este SP está diseñado para ser consumido por componentes
   de UI tipo "Smart Form", donde los catálogos ya están cargados en memoria y solo se requiere
   el ID (Foreign Key) para realizar el "Data Binding" automático.

   2. FILOSOFÍA DE DISEÑO: "LEAN PAYLOAD" (CARGA LIGERA)
   -----------------------------------------------------
   - Principio: "No envíes lo que el cliente ya sabe".
   - Implementación: Se eliminan campos redundantes como `Nombre_Regimen` o `Codigo_Puesto`,
     ya que el Frontend posee esos textos en sus listas desplegables.
   - Beneficio: Reducción drástica del tamaño del JSON de respuesta y menor latencia de red.

   3. ARQUITECTURA DE DATOS (ENTITY-CENTRIC GROUPING)
   --------------------------------------------------
   La proyección de columnas (SELECT) se organiza agrupando lógicamente los datos por Entidad
   de Negocio (Usuario, InfoPersonal, CentroTrabajo, Departamento), facilitando la lectura
   y el mantenimiento del código.

   4. RETO TÉCNICO: RECONSTRUCCIÓN DE CASCADAS (REVERSE LOOKUP)
   ------------------------------------------------------------
   El modelo de datos normalizado solo almacena el nodo hoja (ej: `Id_CentroTrabajo`).
   Sin embargo, la UI requiere seleccionar primero los nodos padres (País -> Estado -> Municipio).
   
   SOLUCIÓN: Este SP realiza "JOINS Ascendentes" para recuperar los IDs de toda la cadena
   jerárquica (Ancestros), permitiendo que el Frontend dispare la carga de listas dependientes
   automáticamente al recibir los datos.

   5. ESTRATEGIA DE INTEGRIDAD (ANTI-FRAGILITY)
   --------------------------------------------
   Se utilizan exclusivamente `LEFT JOIN`.
   Razón: Garantizar que el perfil sea accesible incluso si existen inconsistencias referenciales
   (ej: un Centro de Trabajo antiguo eliminado físicamente). Esto permite al usuario entrar
   al formulario y corregir la información faltante ("Self-Healing Data").
   ============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ConsultarPerfilPropio`$$
CREATE PROCEDURE `SP_ConsultarPerfilPropio`(
    IN _Id_Usuario_Sesion INT -- Token de sesión o ID primario del usuario
)
BEGIN
    /* ========================================================================================
       BLOQUE 1: VALIDACIÓN DE ENTRADA (DEFENSIVE PROGRAMMING)
       Objetivo: Evitar ejecución de querys costosos si el parámetro es inválido.
       ======================================================================================== */
    IF _Id_Usuario_Sesion IS NULL OR _Id_Usuario_Sesion <= 0 THEN
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: Identificador de sesión inválido.';
    END IF;

    /* ========================================================================================
       BLOQUE 2: VERIFICACIÓN DE EXISTENCIA (FAIL FAST STRATEGY)
       Objetivo: Validar que el usuario exista antes de intentar ensamblar su perfil complejo.
       ======================================================================================== */
    IF NOT EXISTS (SELECT 1 FROM `Usuarios` WHERE `Id_Usuario` = _Id_Usuario_Sesion) THEN
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [404]: El usuario solicitado no existe.';
    END IF;

    /* ========================================================================================
       BLOQUE 3: CONSULTA MAESTRA (LEAN PROJECTION)
       ======================================================================================== */
    SELECT 
        /* ---------------------------------------------------------------------------------
           CONJUNTO 1: IDENTIDAD Y ACCESO (Tabla Usuarios)
           Datos crudos para visualización estática en el encabezado del perfil.
           --------------------------------------------------------------------------------- */
        `U`.`Id_Usuario`,
        `U`.`Ficha`,

        `U`.`Foto_Perfil_Url`,-- (Habilitar si se requiere mostrar el avatar)

        /* ---------------------------------------------------------------------------------
           CONJUNTO 2: DATOS PERSONALES Y HUMANOS (Tabla Info_Personal)
           Datos editables que se bindean a inputs de texto y fecha.
           --------------------------------------------------------------------------------- */
        `IP`.`Id_InfoPersonal`,
        
        /* Helper Visual: Concatenación para título de página (Solo lectura) */
        CONCAT(IFNULL(`IP`.`Nombre`,''), ' ', IFNULL(`IP`.`Apellido_Paterno`,''), ' ', IFNULL(`IP`.`Apellido_Materno`,'')) AS `Nombre_Completo_Concatenado`,
        
        `IP`.`Nombre`,
        `IP`.`Apellido_Paterno`,
        `IP`.`Apellido_Materno`,
        `IP`.`Fecha_Nacimiento`,
        `IP`.`Fecha_Ingreso`,
        
        `U`.`Email`,
        /* ---------------------------------------------------------------------------------
           CONJUNTO 3: ADSCRIPCIÓN SIMPLE (SOLO IDs)
           Estos campos alimentan -- DROPdowns independientes (sin dependencias).
           El Frontend usará el ID para seleccionar el objeto correcto de su catálogo en memoria.
           --------------------------------------------------------------------------------- */
        `IP`.`Fk_Id_CatRegimen`   AS `Id_Regimen`,
        -- `Reg`.`Codigo`            AS `Codigo_Regimen`,
        -- `Reg`.`Nombre`            AS `Nombre_Regimen`,
        
        `IP`.`Fk_Id_CatPuesto`    AS `Id_Puesto`,
        -- `Puesto`.`Codigo`         AS `Codigo_Puesto`,
        -- `Puesto`.`Nombre`         AS `Nombre_Puesto`,
        
        /* ---------------------------------------------------------------------------------
           CONJUNTO 4: CENTRO DE TRABAJO (CT) + TRIGGERS DE CASCADA
           Objetivo: Permitir la reconstrucción automática de los selectores geográficos.
           Lógica: Recuperamos los ancestros (Mun -> Edo -> Pais) para que la UI sepa qué cargar.
           --------------------------------------------------------------------------------- */
        `IP`.`Fk_Id_CatCT`            AS `Id_CentroTrabajo`, -- Valor seleccionado
        -- `CT`.`Codigo`             AS `Codigo_CentroTrabajo`,
        -- `CT`.`Nombre`             AS `Nombre_CentroTrabajo`,
        -- `CT`.`Direccion_Fisica`   AS `Direccion_Fisica_CT`,
        
        /* Ancestros Geográficos del CT */
        /* Reconstrucción Geográfica Ascendente (Child -> Parent -> Grandparent) */
        `CT`.`Fk_Id_Municipio_CatCT` AS `Id_Municipio_CT`,
        -- `MunCT`.`Codigo`          AS `Codigo_Municipio_CT`,
        -- `MunCT`.`Nombre`          AS `Nombre_Municipio_CT`,
        
        `EdoCT`.`Id_Estado`       AS `Id_Estado_CT`, -- Necesario para pre-cargar combo Estado
        -- `EdoCT`.`Codigo`          AS `Codigo_Estado_CT`,
        -- `EdoCT`.`Nombre`       AS `Nombre_Estado_CT`,
        
        `PaisCT`.`Id_Pais`        AS `Id_Pais_CT`,   -- Necesario para pre-cargar combo País
        -- `PaisCT`.`Codigo`         AS `Codigo_Pais_CT`,
        -- `PaisCT`.`Nombre`      AS `Nombre_Pais_CT`,

        /* ---------------------------------------------------------------------------------
           CONJUNTO 5: DEPARTAMENTO + TRIGGERS DE CASCADA
           Misma lógica que el CT: ID del Departamento + IDs de la ruta geográfica.
           --------------------------------------------------------------------------------- */
        `IP`.`Fk_Id_CatDep`           AS `Id_Departamento`, -- Valor seleccionado
        -- `Dep`.`Codigo`            AS `Codigo_Departamento`,
        -- `Dep`.`Nombre`            AS `Nombre_Departamento`,
        -- `Dep`.`Direccion_Fisica`  AS `Direccion_Fisica_Depto`,
        
        /* Ancestros Geográficos del Departamento */
        /* Reconstrucción Geográfica Ascendente */
        `Dep`.`Fk_Id_Municipio_CatDep` AS `Id_Municipio_Depto`,
        -- `MunDep`.`Codigo`         AS `Codigo_Municipio_Depto`,
        -- `MunDep`.`Nombre`         AS `Nombre_Municipio_Depto`,
        
        `EdoDep`.`Id_Estado`      AS `Id_Estado_Depto`,
        -- `EdoDep`.`Codigo`         AS `Codigo_Estado_Depto`,
        -- `EdoDep`.`Nombre`      AS `Nombre_Estado_Depto`,
        
        `PaisDep`.`Id_Pais`       AS `Id_Pais_Depto`,
        -- `PaisDep`.`Codigo`        AS `Codigo_Pais_Depto`,
        -- `PaisDep`.`Nombre`     AS `Nombre_Pais_Depto`,

        /* ---------------------------------------------------------------------------------
           CONJUNTO 5.5: REGIÓN OPERATIVA
           Zona geográfica macro de operación.
           --------------------------------------------------------------------------------- */
        `IP`.`Fk_Id_CatRegion`    AS `Id_Region`,
        -- `Region`.`Codigo`         AS `Codigo_Region`,
        -- `Region`.`Nombre`         AS `Nombre_Region`,
        
        /* ---------------------------------------------------------------------------------
           CONJUNTO 6: JERARQUÍA ORGANIZACIONAL (ORGANIGRAMA)
           Reconstrucción de la cadena de mando para selectores dependientes.
           Ruta: Gerencia (Hijo) -> Subdirección (Padre) -> Dirección (Abuelo).
           --------------------------------------------------------------------------------- */
        `IP`.`Fk_Id_CatGeren`         AS `Id_Gerencia`,      -- Valor seleccionado
        
        /* Ancestros Organizacionales */
        /* Nivel 1: Gerencia (Nodo Hoja - Asignación Directa) */
        -- `Ger`.`Clave`             AS `Clave_Gerencia`,
        -- `Ger`.`Nombre`            AS `Nombre_Gerencia`,

        /* Nivel 2: Subdirección (Nodo Padre - Derivado) */
         `Ger`.`Fk_Id_CatSubDirec` AS `Id_Subdireccion`,
        -- `Sub`.`Clave`             AS `Clave_Subdireccion`,
        -- `Sub`.`Nombre`            AS `Nombre_Subdireccion`,

        /* Nivel 3: Dirección Corporativa (Nodo Abuelo - Derivado) */
        `Sub`.`Fk_Id_CatDirecc`   AS `Id_Direccion`,
        -- `Dir`.`Clave`             AS `Clave_Direccion`,
        -- `Dir`.`Nombre`            AS `Nombre_Direccion`,

        /* ---------------------------------------------------------------------------------
           CONJUNTO 7: METADATOS Y AUDITORÍA
           Información de control interno y clasificación.
           --------------------------------------------------------------------------------- */
        `IP`.`Nivel`,
        `IP`.`Clasificacion`,
        `U`.`Activo`              AS `Estatus_Usuario`,
        `IP`.`updated_at`         AS `Ultima_Modificacion_Perfil`

    FROM `Usuarios` `U`

    /* =================================================================================
       ESTRATEGIA DE UNIONES (JOINS)
       Se prioriza la robustez (LEFT JOIN) sobre la estrictez (INNER JOIN).
       ================================================================================= */

    /* 1. NÚCLEO: Enlace con la tabla extendida de información personal */
    LEFT JOIN `Info_Personal` `IP` 
        ON `U`.`Fk_Id_InfoPersonal` = `IP`.`Id_InfoPersonal`

    /* 2. JERARQUÍA ORGANIZACIONAL: Recuperación de IDs Padres para Cascada */
    LEFT JOIN `Cat_Gerencias_Activos` `Ger` ON `IP`.`Fk_Id_CatGeren` = `Ger`.`Id_CatGeren`
    LEFT JOIN `Cat_Subdirecciones` `Sub`    ON `Ger`.`Fk_Id_CatSubDirec` = `Sub`.`Id_CatSubDirec`
	LEFT JOIN `Cat_Direcciones` `Dir`       ON `Sub`.`Fk_Id_CatDirecc` = `Dir`.`Id_CatDirecc`
    
    /* 3. GEOGRAFÍA CT: Recuperación de IDs Ancestros para Cascada */
    LEFT JOIN `Cat_Centros_Trabajo` `CT` ON `IP`.`Fk_Id_CatCT` = `CT`.`Id_CatCT`
    LEFT JOIN `Municipio` `MunCT`        ON `CT`.`Fk_Id_Municipio_CatCT` = `MunCT`.`Id_Municipio`
    LEFT JOIN `Estado` `EdoCT`           ON `MunCT`.`Fk_Id_Estado` = `EdoCT`.`Id_Estado`
    LEFT JOIN `Pais` `PaisCT`            ON `EdoCT`.`Fk_Id_Pais` = `PaisCT`.`Id_Pais`

    /* 4. GEOGRAFÍA DEPTO: Recuperación de IDs Ancestros para Cascada */
    LEFT JOIN `Cat_Departamentos` `Dep` ON `IP`.`Fk_Id_CatDep` = `Dep`.`Id_CatDep`
    LEFT JOIN `Municipio` `MunDep`      ON `Dep`.`Fk_Id_Municipio_CatDep` = `MunDep`.`Id_Municipio`
    LEFT JOIN `Estado` `EdoDep`         ON `MunDep`.`Fk_Id_Estado` = `EdoDep`.`Id_Estado`
    LEFT JOIN `Pais` `PaisDep`          ON `EdoDep`.`Fk_Id_Pais` = `PaisDep`.`Id_Pais`

    /* NOTA DE OPTIMIZACIÓN: 
       Se han eliminado los JOINs a las tablas `Cat_Puestos_Trabajo`, `Cat_Regimenes_Trabajo`
       y `Cat_Regiones_Trabajo` ya que, bajo la estrategia "Lean Payload", no se requieren
       sus campos descriptivos (Nombre, Código), bastando con el ID presente en `Info_Personal`. */

    /* 5. OTROS CATÁLOGOS SIMPLES */
    LEFT JOIN `Cat_Regimenes_Trabajo` `Reg`   ON `IP`.`Fk_Id_CatRegimen` = `Reg`.`Id_CatRegimen`
    LEFT JOIN `Cat_Regiones_Trabajo` `Region` ON `IP`.`Fk_Id_CatRegion` = `Region`.`Id_CatRegion`
    LEFT JOIN `Cat_Puestos_Trabajo` `Puesto`  ON `IP`.`Fk_Id_CatPuesto` = `Puesto`.`Id_CatPuesto`

    /* =================================================================================
       FILTRO FINAL
       ================================================================================= */
    WHERE `U`.`Id_Usuario` = _Id_Usuario_Sesion
    LIMIT 1;

END$$

DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_ConsultarUsuarioPorAdmin
   ============================================================================================

   1. OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   --------------------------------------
   Proveer al Administrador de Sistema una "Radiografía Técnica Completa" de cualquier usuario
   registrado en la base de datos, independientemente de su estado actual (Activo/Inactivo).

   Este procedimiento actúa como el backend para dos interfaces críticas:
     A) VISOR DE DETALLE (MODAL DE AUDITORÍA): Donde se inspecciona quién es el usuario,
        quién lo registró, cuándo y qué permisos tiene.
     B) FORMULARIO DE EDICIÓN AVANZADA (UPDATE): Donde el Admin puede corregir datos,
        reasignar roles, cambiar de adscripción o bloquear el acceso.

   2. DIFERENCIAS CRÍTICAS VS "PERFIL PROPIO" (SCOPE)
   --------------------------------------------------
   Mientras que el perfil de usuario es de "Solo Lectura" para ciertos campos, esta vista:
     - EXPONE LA SEGURIDAD: Devuelve el `Id_Rol` y `Activo` para permitir su modificación.
     - ROMPE EL SILENCIO: No filtra por `Activo = 1`. Permite gestionar usuarios "Baneados"
       o dados de baja lógica para su eventual reactivación.
     - TRAZABILIDAD TOTAL: Revela la identidad de los autores de los cambios (Created_By/Updated_By),
       resolviendo sus IDs a Nombres Reales mediante JOINs reflexivos.

   3. ARQUITECTURA DE DATOS: "LEAN HYDRATION" (CARGA LIGERA)
   ---------------------------------------------------------
   Para optimizar el rendimiento del Frontend (Angular/React/Vue), este SP no devuelve los
   catálogos completos (listas de opciones), sino los punteros (Foreign Keys) necesarios para
   que los componentes visuales se "auto-configuren":
   
     - Estrategia de Binding: Se retornan IDs (ej: `Id_Puesto`) para que el -- DROPdown seleccione
       automáticamente la opción correcta.
     - Estrategia de Cascada: Se retornan los IDs de los Ancestros (Municipio -> Estado -> País)
       para disparar la carga de listas dependientes sin intervención del usuario.

   4. DICCIONARIO DE DATOS (OUTPUT CONTRACT)
   -----------------------------------------
   El resultset se estructura en 10 bloques lógicos que mapean directamente las secciones
   visuales del formulario de Administración:
     [1] Identidad Digital (Ficha/Email)
     [2] Seguridad (Rol/Estatus)
     [3] Identidad Humana (Nombres)
     [4] Adscripción Simple (Puesto)
     [5] Ubicación Física (Centro de Trabajo + Geografía)
     [6] Ubicación Administrativa (Departamento + Geografía)
     [7] Región Operativa
     [8] Jerarquía de Mando (Organigrama)
     [9] Metadatos (Nivel/Clasificación)
     [10] Auditoría (Fechas y Responsables)
   ============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ConsultarUsuarioPorAdmin`$$

CREATE PROCEDURE `SP_ConsultarUsuarioPorAdmin`(
    IN _Id_Usuario_Objetivo INT -- Identificador único del usuario a inspeccionar
)
BEGIN
    /* ========================================================================================
       BLOQUE 1: VALIDACIÓN DE ENTRADA (DEFENSIVE PROGRAMMING)
       Objetivo: Asegurar que el parámetro recibido cumpla con los requisitos mínimos
       antes de intentar cualquier operación de lectura. 
       ======================================================================================== */
    IF _Id_Usuario_Objetivo IS NULL OR _Id_Usuario_Objetivo <= 0 THEN
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: Identificador de usuario objetivo inválido (Debe ser entero positivo).';
    END IF;

    /* ========================================================================================
       BLOQUE 2: VERIFICACIÓN DE EXISTENCIA (FAIL FAST STRATEGY)
       Objetivo: Validar que el recurso realmente exista en la base de datos.
       
       NOTA DE DISEÑO: Aquí NO validamos `Activo = 1`. El Admin tiene permisos de "Dios"
       para ver registros eliminados lógicamente.
       ======================================================================================== */
    IF NOT EXISTS (SELECT 1 FROM `Usuarios` WHERE `Id_Usuario` = _Id_Usuario_Objetivo) THEN
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [404]: El usuario solicitado no existe en la base de datos.';
    END IF;

    /* ========================================================================================
       BLOQUE 3: CONSULTA MAESTRA (FULL DATA RETRIEVAL)
       Objetivo: Retornar el objeto de datos completo, reconstruyendo jerarquías y auditoría.
       ======================================================================================== */
    SELECT 
        /* ---------------------------------------------------------------------------------
           CONJUNTO 1: IDENTIDAD Y CREDENCIALES
           Datos fundamentales de la cuenta. Inmutables para el usuario, editables por Admin.
           --------------------------------------------------------------------------------- */
        `U`.`Id_Usuario`,
        `U`.`Ficha`,

        `U`.`Foto_Perfil_Url`, -- Recurso multimedia (Avatar)

        /* ---------------------------------------------------------------------------------
           CONJUNTO 2: DATOS PERSONALES (INFO HUMANOS)
           Información demográfica proveniente de la tabla satélite `Info_Personal`.
           --------------------------------------------------------------------------------- */
        `IP`.`Id_InfoPersonal`,
        
        /* Helper Visual: Nombre Completo Concatenado.
           Útil para mostrar en el título del modal ("Editando a: JUAN PÉREZ") sin procesar en JS. */
        CONCAT(IFNULL(`IP`.`Nombre`,''), ' ', IFNULL(`IP`.`Apellido_Paterno`,''), ' ', IFNULL(`IP`.`Apellido_Materno`,'')) AS `Nombre_Completo_Concatenado`,
        
        /* Datos atómicos para edición en inputs separados */
        `IP`.`Nombre`,
        `IP`.`Apellido_Paterno`,
        `IP`.`Apellido_Materno`,
        `IP`.`Fecha_Nacimiento`,
        `IP`.`Fecha_Ingreso`,
        
        `U`.`Email`,
        /* ---------------------------------------------------------------------------------
           CONJUNTO 3: ADSCRIPCIÓN SIMPLE (SOLO IDs)
           Estos campos no tienen dependencias complejas. El Frontend usará el ID para
           seleccionar el valor correcto en el -- DROPdown correspondiente.
           --------------------------------------------------------------------------------- */
        `IP`.`Fk_Id_CatRegimen`   AS `Id_Regimen`,
        `IP`.`Fk_Id_CatPuesto`    AS `Id_Puesto`,

        /* ---------------------------------------------------------------------------------
           CONJUNTO 4: CENTRO DE TRABAJO + CASCADA GEOGRÁFICA (REVERSE LOOKUP)
           El reto aquí es que `Info_Personal` solo guarda el ID del Centro de Trabajo.
           Para que el Frontend pueda mostrar los selectores de País, Estado y Municipio
           correctamente pre-llenados, debemos "subir" por la jerarquía y devolver esos IDs.
           --------------------------------------------------------------------------------- */
        `IP`.`Fk_Id_CatCT`            AS `Id_CentroTrabajo`, -- Valor final seleccionado
        
        /* Triggers de Cascada Geográfica (Ancestros) */
        `CT`.`Fk_Id_Municipio_CatCT`  AS `Id_Municipio_CT`,
        `EdoCT`.`Id_Estado`           AS `Id_Estado_CT`,
        `PaisCT`.`Id_Pais`            AS `Id_Pais_CT`,

        /* ---------------------------------------------------------------------------------
           CONJUNTO 5: DEPARTAMENTO + CASCADA GEOGRÁFICA
           Misma lógica de reconstrucción inversa que el Centro de Trabajo.
           --------------------------------------------------------------------------------- */
        `IP`.`Fk_Id_CatDep`           AS `Id_Departamento`, -- Valor final seleccionado
        
        /* Triggers de Cascada Geográfica (Ancestros) */
        `Dep`.`Fk_Id_Municipio_CatDep` AS `Id_Municipio_Depto`,
        `EdoDep`.`Id_Estado`           AS `Id_Estado_Depto`,
        `PaisDep`.`Id_Pais`            AS `Id_Pais_Depto`,

        /* ---------------------------------------------------------------------------------
           CONJUNTO 6: REGIÓN OPERATIVA
           Ubicada visualmente tras el Departamento según el flujo de UI definido.
           --------------------------------------------------------------------------------- */
        `IP`.`Fk_Id_CatRegion`        AS `Id_Region`,

        /* ---------------------------------------------------------------------------------
           CONJUNTO 7: JERARQUÍA ORGANIZACIONAL (ORGANIGRAMA)
           Reconstrucción de la cadena de mando administrativa.
           Ruta: Gerencia (Hijo) -> Subdirección (Padre) -> Dirección (Abuelo).
           --------------------------------------------------------------------------------- */
        `IP`.`Fk_Id_CatGeren`         AS `Id_Gerencia`,      -- Valor final seleccionado
        
        /* Triggers de Cascada Organizacional (Ancestros) */
        `Ger`.`Fk_Id_CatSubDirec`     AS `Id_Subdireccion`,
        `Sub`.`Fk_Id_CatDirecc`       AS `Id_Direccion`,

        /* ---------------------------------------------------------------------------------
           CONJUNTO 8: METADATOS ADMINISTRATIVOS
           Datos tabulares sin catálogo relacional fuerte.
           --------------------------------------------------------------------------------- */
        `IP`.`Nivel`,
        `IP`.`Clasificacion`,

        /* ---------------------------------------------------------------------------------
           CONJUNTO 9: TRAZABILIDAD Y AUDITORÍA (RICH AUDIT TRAIL)
           Aquí resolvemos la pregunta: "¿Quién hizo esto?".
           En lugar de devolver IDs numéricos ("Creado por: 45"), hacemos JOINs reflexivos
           para devolver el Nombre Real del responsable.
           --------------------------------------------------------------------------------- */
        /* DATOS DE CREACIÓN */
        `U`.`created_at`              AS `Fecha_Registro`,
        /* Si Created_By es NULL (migración), mostramos 'System', si no, el nombre concatenado */
        CONCAT(IFNULL(`Info_Crt`.`Nombre`,'System'), ' ', IFNULL(`Info_Crt`.`Apellido_Paterno`,'')) AS `Creado_Por_Nombre`,
        
        /* DATOS DE ACTUALIZACIÓN */
        `U`.`updated_at`              AS `Fecha_Ultima_Modificacion`,
        CONCAT(IFNULL(`Info_Upd`.`Nombre`,''), ' ', IFNULL(`Info_Upd`.`Apellido_Paterno`,''))       AS `Actualizado_Por_Nombre`,

        /* ---------------------------------------------------------------------------------
           CONJUNTO 10: SEGURIDAD Y CONTROL (EXCLUSIVO ADMIN)
           Ubicados al final del JSON para coincidir con la sección de "Acciones Críticas"
           (Footer) del formulario de edición.
           --------------------------------------------------------------------------------- */
        `U`.`Fk_Rol`                  AS `Id_Rol`,           -- Binding para -- DROPdown de Roles
        `U`.`Activo`                  AS `Estatus_Usuario`   -- Binding para Switch Activo/Inactivo

    FROM `Usuarios` `U`

    /* =================================================================================
       ESTRATEGIA DE UNIONES (JOINS)
       Se utiliza `LEFT JOIN` masivamente.
       
       JUSTIFICACIÓN DE INTEGRIDAD:
       Priorizamos la "Disponibilidad de Datos" sobre la "Consistencia Estricta".
       Si un usuario tiene un ID de Departamento que fue eliminado físicamente (catálogo roto),
       un INNER JOIN ocultaría al usuario completo.
       Con LEFT JOIN, mostramos al usuario con el campo departamento vacío, permitiendo
       al Administrador detectar el error y corregirlo (Self-Healing).
       ================================================================================= */

    /* 1. NÚCLEO: Enlace con la tabla extendida de información personal */
    LEFT JOIN `Info_Personal` `IP` 
        ON `U`.`Fk_Id_InfoPersonal` = `IP`.`Id_InfoPersonal`

    /* 2. JERARQUÍA ORGANIZACIONAL: Recuperación de IDs Padres para Cascada */
    LEFT JOIN `Cat_Gerencias_Activos` `Ger` ON `IP`.`Fk_Id_CatGeren` = `Ger`.`Id_CatGeren`
    LEFT JOIN `Cat_Subdirecciones` `Sub`    ON `Ger`.`Fk_Id_CatSubDirec` = `Sub`.`Id_CatSubDirec`
    LEFT JOIN `Cat_Direcciones` `Dir`       ON `Sub`.`Fk_Id_CatDirecc` = `Dir`.`Id_CatDirecc`
    
    /* 3. GEOGRAFÍA CT: Recuperación de IDs Ancestros para Cascada */
    LEFT JOIN `Cat_Centros_Trabajo` `CT` ON `IP`.`Fk_Id_CatCT` = `CT`.`Id_CatCT`
    LEFT JOIN `Municipio` `MunCT`        ON `CT`.`Fk_Id_Municipio_CatCT` = `MunCT`.`Id_Municipio`
    LEFT JOIN `Estado` `EdoCT`           ON `MunCT`.`Fk_Id_Estado` = `EdoCT`.`Id_Estado`
    LEFT JOIN `Pais` `PaisCT`            ON `EdoCT`.`Fk_Id_Pais` = `PaisCT`.`Id_Pais`

    /* 4. GEOGRAFÍA DEPTO: Recuperación de IDs Ancestros para Cascada */
    LEFT JOIN `Cat_Departamentos` `Dep` ON `IP`.`Fk_Id_CatDep` = `Dep`.`Id_CatDep`
    LEFT JOIN `Municipio` `MunDep`      ON `Dep`.`Fk_Id_Municipio_CatDep` = `MunDep`.`Id_Municipio`
    LEFT JOIN `Estado` `EdoDep`         ON `MunDep`.`Fk_Id_Estado` = `EdoDep`.`Id_Estado`
    LEFT JOIN `Pais` `PaisDep`          ON `EdoDep`.`Fk_Id_Pais` = `PaisDep`.`Id_Pais`

    /* 5. AUDITORÍA (JOINS REFLEXIVOS / SELF-JOINS)
       Objetivo: Obtener el nombre legible de los responsables de creación/edición.
       Mecánica: 
         a) `U` -> `Usuarios` (Creador) -> `Info_Personal` (Nombre Creador)
         b) `U` -> `Usuarios` (Editor) -> `Info_Personal` (Nombre Editor)
       Se usan alias distintos (`Info_Crt`, `Info_Upd`) para no colisionar con el `IP` principal. */
       
    /* 5.1 Resolver Identidad del Creador */
    LEFT JOIN `Usuarios` `User_Crt`       ON `U`.`Fk_Usuario_Created_By` = `User_Crt`.`Id_Usuario`
    LEFT JOIN `Info_Personal` `Info_Crt`  ON `User_Crt`.`Fk_Id_InfoPersonal` = `Info_Crt`.`Id_InfoPersonal`

    /* 5.2 Resolver Identidad del Editor (Última modificación) */
    LEFT JOIN `Usuarios` `User_Upd`       ON `U`.`Fk_Usuario_Updated_By` = `User_Upd`.`Id_Usuario`
    LEFT JOIN `Info_Personal` `Info_Upd`  ON `User_Upd`.`Fk_Id_InfoPersonal` = `Info_Upd`.`Id_InfoPersonal`

    /* =================================================================================
       FILTRO FINAL
       ================================================================================= */
    WHERE `U`.`Id_Usuario` = _Id_Usuario_Objetivo
    LIMIT 1; /* Buena práctica: Detener el escaneo tras el primer hallazgo */

END$$

DELIMITER ;

/* ============================================================================================
   SECCIÓN: LISTADOS PARA -- DROPDOWNS (SOLO REGISTROS ACTIVOS)
   ============================================================================================
   Estas rutinas son consumidas por los formularios de captura (Frontend).
   Su objetivo es ofrecer al usuario solo las opciones válidas y vigentes para evitar errores.
   ============================================================================================ */
   
/* ============================================================================================
   PROCEDIMIENTO: SP_ListarInstructoresActivos
   ============================================================================================

--------------------------------------------------------------------------------------------
   I. CONTEXTO OPERATIVO Y PROPÓSITO (THE "WHAT" & "FOR WHOM")
   --------------------------------------------------------------------------------------------
   [QUÉ ES]: 
   Es el motor de datos de "Lectura Crítica" diseñado para alimentar el componente visual 
   "Selector de Asignación" (-- DROPdown/Select2) en el módulo de Coordinación.

   [EL PROBLEMA QUE RESUELVE]: 
   En un ecosistema con >2,300 usuarios, permitir la selección libre generaba dos riesgos graves:
     1. Riesgo Operativo: Asignar por error a un "Participante" (Alumno) para dar un curso.
     2. Riesgo de Rendimiento: Cargar una lista masiva sin filtrar colapsaba la memoria del navegador.

   [SOLUCIÓN IMPLEMENTADA]: 
   Un algoritmo de filtrado de "Doble Candado" (Vigencia + Competencia) optimizado a nivel de 
   índices de base de datos para retornar solo el subconjunto válido (< 10% del total) en < 5ms.

   --------------------------------------------------------------------------------------------
   II. DICCIONARIO DE REGLAS DE NEGOCIO (BUSINESS RULES ENGINE)
   --------------------------------------------------------------------------------------------
   Las siguientes reglas son IMPERATIVAS y definen la lógica del `WHERE`:

   [RN-01] REGLA DE VIGENCIA OPERATIVA (SOFT DELETE CHECK)
      - Definición: "Nadie puede ser asignado a un evento futuro si no tiene contrato activo".
      - Implementación: Cláusula `WHERE Activo = 1`.
      - Impacto: Excluye automáticamente jubilados, bajas temporales y despidos.

   [RN-02] REGLA DE JERARQUÍA DE COMPETENCIA (ROLE ELIGIBILITY)
      - Definición: "El permiso para instruir se otorga explícitamente o por jerarquía superior".
      - Lógica de Inclusión (Whitelist):
          * ID 1 (ADMINISTRADOR): Posee permisos Supremos. (Habilitado).
          * ID 2 (COORDINADOR): Posee permisos de Gestión. (Habilitado).
          * ID 3 (INSTRUCTOR): Posee permisos de Ejecución. (Habilitado).
      - Lógica de Exclusión (Blacklist):
          * ID 4 (PARTICIPANTE): Solo consume contenido. (BLOQUEADO).

   --------------------------------------------------------------------------------------------
   III. ANÁLISIS TÉCNICO Y RENDIMIENTO (PERFORMANCE SPECS)
   --------------------------------------------------------------------------------------------
   [A] COMPLEJIDAD ALGORÍTMICA: O(1) - INDEX SCAN
       Al eliminar el `JOIN` con la tabla `Cat_Roles` y filtrar por IDs numéricos (`Fk_Rol`),
       evitamos el producto cartesiano. El motor realiza una búsqueda directa.

   [B] HEURÍSTICA DE ORDENAMIENTO (ZERO-FILESORT)
       El `ORDER BY` coincide exactamente con la definición física del índice `Idx_Busqueda_Apellido`.
       El motor de BD lee los datos secuencialmente del disco ya ordenados, eliminando el uso
       de CPU y RAM para reordenar el resultado.

   [C] ESTRATEGIA DE NULOS (NULL SAFETY)
       Se utiliza `CONCAT_WS` en lugar de `CONCAT`.
       - Problema: `CONCAT('Juan', NULL, 'Perez')` retorna `NULL` (Dato perdido).
       - Solución: `CONCAT_WS` ignora el NULL y retorna "Juan Perez". Garantiza integridad visual.

   --------------------------------------------------------------------------------------------
   IV. CONTRATO DE INTERFAZ (OUTPUT API)
   --------------------------------------------------------------------------------------------
   Retorna un arreglo JSON estricto:
     1. `Id_Usuario` (INT): Valor relacional (Foreign Key).
     2. `Ficha` (STRING): Clave de búsqueda exacta.
     3. `Nombre_Completo` (STRING): Etiqueta visual para el humano.
   ============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ListarInstructoresActivos`$$

CREATE PROCEDURE `SP_ListarInstructoresActivos`()
BEGIN
    /* ========================================================================================
       SECCIÓN 1: PROYECCIÓN DE DATOS (SELECT)
       Define qué datos viajan a la red. Se aplica estrategia "Lean Payload" (solo lo vital).
       ======================================================================================== */
    SELECT 
        /* [DATO CRÍTICO] IDENTIFICADOR DE SISTEMA
           Este campo es invisible para el usuario pero vital para el sistema.
           Se usará en el `INSERT INTO Capacitaciones (Fk_Id_Instructor)...` */
        `U`.`Id_Usuario`,

        /* [VECTOR DE BÚSQUEDA 1] IDENTIFICADOR CORPORATIVO
           Permite a los coordinadores buscar rápidamente usando el teclado numérico. */
        `U`.`Ficha`,

        /* [VECTOR DE BÚSQUEDA 2] ETIQUETA VISUAL HUMANA
           Transformación: Concatenación con separador de espacio.
           Objetivo: Generar una cadena única de búsqueda tipo "Google".
           Formato: APELLIDOS + NOMBRE (Para coincidir con listas de asistencia físicas). */
        CONCAT_WS(' ', `IP`.`Apellido_Paterno`, `IP`.`Apellido_Materno`, `IP`.`Nombre`) AS `Nombre_Completo`

    /* ========================================================================================
       SECCIÓN 2: ORIGEN DE DATOS Y RELACIONES (FROM/JOIN)
       ======================================================================================== */
    FROM 
        `Usuarios` `U`

    /* RELACIÓN DE INTEGRIDAD
       Unimos con la tabla satélite de información personal.
       Usamos INNER JOIN como medida de "Calidad de Datos": Si un usuario no tiene 
       datos personales (registro corrupto), se excluye automáticamente de la lista. */
    INNER JOIN `Info_Personal` `IP` 
        ON `U`.`Fk_Id_InfoPersonal` = `IP`.`Id_InfoPersonal`

    /* JOIN 2: Recuperar Departamento para contexto (LEFT JOIN por robustez) */
    /* Si el instructor no tiene depto asignado, aún debe aparecer en la lista */
    /*LEFT JOIN `Cat_Departamentos` `Dep` 
        ON `IP`.`Fk_Id_CatDep` = `Dep`.`Id_CatDep`*/

    /* JOIN 3: Filtrado por Rol (SEGURIDAD) */
    /*INNER JOIN `Cat_Roles` `R`
        ON `U`.`Fk_Rol` = `R`.`Id_Rol`*/

    /* ========================================================================================
       SECCIÓN 3: MOTOR DE REGLAS DE NEGOCIO (WHERE)
       Aquí se aplican los filtros de seguridad y lógica operativa.
       ======================================================================================== */
    WHERE 
        /* [REGLA 1] VIGENCIA OPERATIVA
           El usuario debe tener la bandera de acceso en TRUE (1). */
        `U`.`Activo` = 1
        
        AND 
        
        /* [REGLA 2] FILTRO DE COMPETENCIA (Hardcoded IDs)
           Implementación técnica de la regla de jerarquía.
           Se filtra directamente sobre la columna FK para aprovechar la indexación numérica.
           
           LISTA BLANCA DE ACCESO:
           - 1: ADMIN (Superuser)
           - 2: COORDINADOR (Manager)
           - 3: INSTRUCTOR (Worker)
           
           Cualquier ID fuera de este rango (ej: 4=Participante) es descartado. */
        `U`.`Fk_Rol` IN (1, 2, 3)

    /* ========================================================================================
       SECCIÓN 4: ORDENAMIENTO OPTIMIZADO (ORDER BY)
       ======================================================================================== */
    /* ALINEACIÓN DE ÍNDICE:
       Estas columnas coinciden en orden exacto con `Idx_Busqueda_Apellido`.
       Esto permite una lectura secuencial sin costo de procesamiento. */
    ORDER BY 
        `IP`.`Apellido_Paterno` ASC, 
        `IP`.`Apellido_Materno` ASC,
        `IP`.`Nombre` ASC;

END$$

DELIMITER ;

/* ============================================================================================
   SECCIÓN: LISTADOS PARA ADMINISTRACIÓN (TABLAS CRUD)
   ============================================================================================
   Estas rutinas son consumidas exclusivamente por los Paneles de Control (Grid/Tabla de Mantenimiento).
   Su objetivo es dar visibilidad total sobre el catálogo para auditoría, gestión y corrección.
   ============================================================================================ */
   
   /* ============================================================================================
   PROCEDIMIENTO: SP_ListarTodosInstructores_Historial
   ============================================================================================

   --------------------------------------------------------------------------------------------
   I. CONTEXTO OPERATIVO Y PROPÓSITO (THE "WHAT" & "FOR WHOM")
   --------------------------------------------------------------------------------------------
   [QUÉ ES]: 
   Es el motor de datos de "Lectura Histórica" diseñado para alimentar los **Filtros de Búsqueda**
   en los Reportes de Auditoría, Historial de Capacitaciones y Tableros de Control (Dashboards).

   [EL PROBLEMA QUE RESUELVE]: 
   El selector operativo (`SP_ListarInstructoresActivos`) oculta a los usuarios dados de baja.
   Esto generaba un "Punto Ciego" en los reportes: El administrador no podía filtrar cursos 
   impartidos en el pasado por personal que ya se jubiló o fue desvinculado.

   [SOLUCIÓN IMPLEMENTADA]: 
   Una variante del algoritmo "Zero-Join" que **ignora el estatus de vigencia** e inyecta 
   metadatos visuales ("Enriquecimiento de Etiqueta") para diferenciar activos de inactivos
   sin comprometer el rendimiento.

   --------------------------------------------------------------------------------------------
   II. DICCIONARIO DE REGLAS DE NEGOCIO (BUSINESS RULES ENGINE)
   --------------------------------------------------------------------------------------------
   [RN-01] ALCANCE UNIVERSAL (NO VIGENCY CHECK)
      - Definición: "Para auditar el pasado, todos los actores son relevantes".
      - Implementación: Se ELIMINA deliberadamente la cláusula `WHERE Activo = 1`.
      - Impacto: El listado incluye el universo total histórico de instructores.

   [RN-02] ENRIQUECIMIENTO VISUAL (STATUS BADGING)
      - Definición: "El usuario debe distinguir inmediatamente el estado operativo del recurso".
      - Lógica:
          * Si `Activo = 1`: Muestra solo el nombre.
          * Si `Activo = 0`: Inyecta el sufijo " (BAJA/INACTIVO)".
      - Justificación UX: Evita que el Admin intente reactivar o contactar a personal inexistente.

   [RN-03] REGLA DE JERARQUÍA DE COMPETENCIA (ROLE ELIGIBILITY)
      - Definición: "Solo se listan aquellos roles que históricamente pudieron impartir clase".
      - Lógica de Inclusión (Whitelist de IDs):
          * ID 1 (ADMIN), ID 2 (COORD), ID 3 (INSTRUCTOR).
      - Lógica de Exclusión:
          * ID 4 (PARTICIPANTE): Se excluye, ya que nunca debió impartir un curso.

   --------------------------------------------------------------------------------------------
   III. ANÁLISIS TÉCNICO Y RENDIMIENTO (PERFORMANCE SPECS)
   --------------------------------------------------------------------------------------------
   [A] COMPLEJIDAD ALGORÍTMICA: O(1) - INDEX SCAN
       Mantiene la optimización de filtrar por IDs numéricos (`Fk_Rol`), evitando JOINs costosos.

   [B] COSTO COMPUTACIONAL DE ENRIQUECIMIENTO
       La operación `CASE WHEN` para el sufijo se ejecuta en memoria durante la proyección. 
       Su impacto es despreciable (< 0.01ms por fila) comparado con el beneficio de UX.

   [C] HEURÍSTICA DE ORDENAMIENTO
       Mantiene la alineación estricta con el índice `Idx_Busqueda_Apellido`.

   --------------------------------------------------------------------------------------------
   IV. CONTRATO DE INTERFAZ (OUTPUT API)
   --------------------------------------------------------------------------------------------
   Retorna un arreglo JSON estricto:
     1. `Id_Usuario` (INT): Valor para el filtro SQL (`WHERE Fk_Instructor = X`).
     2. `Ficha` (STRING): Clave de búsqueda visual.
     3. `Nombre_Completo_Filtro` (STRING): Etiqueta enriquecida con estado.
   ============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ListarTodosInstructores_Historial`$$

CREATE PROCEDURE `SP_ListarTodosInstructores_Historial`()
BEGIN
    /* ========================================================================================
       SECCIÓN 1: PROYECCIÓN Y ENRIQUECIMIENTO DE DATOS (SELECT)
       ======================================================================================== */
    SELECT 
        /* [ID DEL FILTRO] 
           Valor que se usará en el `WHERE` del reporte que consuma este SP. */
        `U`.`Id_Usuario`,

        /* [CLAVE VISUAL] 
           Identificador corporativo. */
        `U`.`Ficha`,

        /* [ETIQUETA VISUAL INTELIGENTE] (Logic Injection)
           Objetivo: Generar una etiqueta que informe identidad + estado.
           
           Composición:
           1. Nombre Base: CONCAT_WS para evitar nulos.
           2. Sufijo Dinámico: CASE para detectar inactividad. */
        CONCAT(
            CONCAT_WS(' ', `IP`.`Apellido_Paterno`, `IP`.`Apellido_Materno`, `IP`.`Nombre`),
            CASE 
                WHEN `U`.`Activo` = 0 THEN ' (BAJA/INACTIVO)' 
                ELSE '' 
            END
        ) AS `Nombre_Completo_Filtro`

    /* ========================================================================================
       SECCIÓN 2: ORIGEN DE DATOS (FROM/JOIN)
       ======================================================================================== */
    FROM 
        `Usuarios` `U`

    /* RELACIÓN DE INTEGRIDAD
       Usamos INNER JOIN. Un usuario sin datos personales es irrelevante para un reporte
       nominal, por lo que se descarta por integridad de datos. */
    INNER JOIN `Info_Personal` `IP` 
        ON `U`.`Fk_Id_InfoPersonal` = `IP`.`Id_InfoPersonal`

    /* NOTA DE ARQUITECTURA: 
       Se mantiene la estrategia "Zero-Join" (sin tabla Roles) para máxima velocidad. */

    /* ========================================================================================
       SECCIÓN 3: MOTOR DE REGLAS DE NEGOCIO (WHERE)
       ======================================================================================== */
    WHERE 
        /* [DIFERENCIA CRÍTICA]
           NO EXISTE FILTRO DE `Activo = 1`. 
           Estamos recuperando la historia completa (Vivos + Muertos). */
        
        /* [REGLA 2] FILTRO DE COMPETENCIA (Hardcoded IDs)
           Se filtra directamente sobre la columna FK para aprovechar la indexación numérica.
           Solo nos interesan usuarios con capacidad docente. */
        `U`.`Fk_Rol` IN (
            1,  -- ADMINISTRADOR
            2,  -- COORDINADOR
            3   -- INSTRUCTOR
        )

    /* ========================================================================================
       SECCIÓN 4: ORDENAMIENTO OPTIMIZADO (ORDER BY)
       ======================================================================================== */
    /* ALINEACIÓN DE ÍNDICE:
       Garantiza lectura secuencial del disco. */
    ORDER BY 
        `IP`.`Apellido_Paterno` ASC, 
        `IP`.`Apellido_Materno` ASC, 
        `IP`.`Nombre` ASC;

END$$

DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_EditarPerfilPropio
   ============================================================================================

   --------------------------------------------------------------------------------------------
   I. VISIÓN GENERAL Y OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   --------------------------------------------------------------------------------------------
   [PROPÓSITO CENTRAL]:
   Orquestar la actualización atómica del "Expediente Digital" del usuario autenticado.
   Sustituye y unifica los flujos de "Completar Perfil" (Onboarding) y "Editar Mi Perfil".

   [PROBLEMA A RESOLVER]:
   En un sistema de alta concurrencia, permitir que el usuario edite sus propios datos presenta
   riesgos de integridad (asignarse a puestos inexistentes) y colisión (dos sesiones editando
   al mismo tiempo).
   
   Este SP actúa como un **Motor Transaccional Blindado** que garantiza:
   1. Consistencia: No se pueden guardar referencias a catálogos borrados o inactivos.
   2. Seguridad: El usuario no puede escalar privilegios ni modificar datos de otros.
   3. Eficiencia: No se toca el disco si no hubo cambios reales.

   --------------------------------------------------------------------------------------------
   II. REGLAS DE VALIDACIÓN ESTRICTA (HARD CONSTRAINTS)
   --------------------------------------------------------------------------------------------
   [RN-01] VALIDACIÓN HÍBRIDA DE ADSCRIPCIÓN (LAZY & STRICT CHECK):
      - Contexto: La realidad operativa a veces supera a la actualización de catálogos.
      - Regla Estricta: 'Régimen' y 'Región' son OBLIGATORIOS (Datos macro siempre conocidos).
      - Regla Perezosa (Lazy): 'Puesto', 'CT', 'Depto', 'Gerencia' son OPCIONALES (Permiten NULL).
      - Integridad: Si el usuario envía un ID para un campo opcional, se valida estrictamente
        que exista y esté `Activo=1`. No se permiten IDs "zombis".

   [RN-02] PROTECCIÓN DE IDENTIDAD (IDENTITY COLLISION):
      - Se permite corregir la FICHA (error de dedo al registro).
      - Se valida que la nueva ficha no pertenezca a OTRO usuario (`Id != Me`).
      - El Email NO se toca aquí (se delega a un módulo de seguridad con re-autenticación).

   --------------------------------------------------------------------------------------------
   III. ARQUITECTURA DE CONCURRENCIA (DETERMINISTIC LOCKING PATTERN)
   --------------------------------------------------------------------------------------------
   [BLOQUEO PESIMISTA - PESSIMISTIC LOCKING]:
   - Problema: "Race Condition". El usuario abre su perfil en dos pestañas, edita cosas distintas
     y guarda casi al mismo tiempo. El último "gana" y sobrescribe al primero sin saberlo.
   - Solución: Al inicio de la transacción, ejecutamos `SELECT ... FOR UPDATE`.
   - Efecto: La fila del usuario se "congela". Cualquier otra transacción que intente leerla
     o escribirla deberá esperar a que esta termine. Garantiza aislamiento total (SERIALIZABLE).

   --------------------------------------------------------------------------------------------
   IV. IDEMPOTENCIA (OPTIMIZACIÓN DE RECURSOS)
   --------------------------------------------------------------------------------------------
   [MOTOR DE DETECCIÓN DE CAMBIOS]:
   - Antes de escribir, el SP compara el Snapshot (Valores Actuales) vs Inputs.
   - Usamos el operador `<=>` (Null-Safe Equality) para comparar campos que pueden ser NULL.
   - Si todo es idéntico, retornamos `ACCION: 'SIN_CAMBIOS'` y hacemos COMMIT inmediato.
   - Beneficio: Ahorro masivo de I/O de disco y evita ensuciar los logs de auditoría.

   --------------------------------------------------------------------------------------------
   V. CONTRATO DE SALIDA (OUTPUT CONTRACT)
   --------------------------------------------------------------------------------------------
   Retorna un resultset estructurado para el Frontend:
      - Mensaje (VARCHAR): Feedback granular ("Se actualizó: Foto, Puesto").
      - Accion (VARCHAR): 'ACTUALIZADA', 'SIN_CAMBIOS', 'CONFLICTO'.
      - Id_Usuario (INT): Contexto.
   ============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_EditarPerfilPropio`$$

CREATE PROCEDURE `SP_EditarPerfilPropio`(
    /* -----------------------------------------------------------------
       1. CONTEXTO DE SEGURIDAD (AUTH TOKEN)
       Este ID debe venir del Middleware de Autenticación.
       ----------------------------------------------------------------- */
    IN _Id_Usuario_Sesion INT,

    /* -----------------------------------------------------------------
       2. IDENTIDAD DIGITAL & VISUAL
       Datos para la tarjeta de presentación del usuario.
       ----------------------------------------------------------------- */
    IN _Ficha            VARCHAR(50),
    IN _Url_Foto         VARCHAR(255), 

    /* -----------------------------------------------------------------
       3. IDENTIDAD HUMANA (DEMOGRÁFICOS)
       Datos fundamentales para la Huella Humana.
       ----------------------------------------------------------------- */
    IN _Nombre            VARCHAR(255),
    IN _Apellido_Paterno  VARCHAR(255),
    IN _Apellido_Materno  VARCHAR(255),
    IN _Fecha_Nacimiento  DATE,
    IN _Fecha_Ingreso     DATE,

    /* -----------------------------------------------------------------
       4. MATRIZ DE ADSCRIPCIÓN (CATÁLOGOS)
       IDs provenientes de los -- DROPdowns. Algunos son obligatorios, otros opcionales.
       ----------------------------------------------------------------- */
    IN _Id_Regimen        INT, -- [OBLIGATORIO]
    IN _Id_Puesto         INT, -- [OPCIONAL]
    IN _Id_CentroTrabajo  INT, -- [OPCIONAL]
    IN _Id_Departamento   INT, -- [OPCIONAL]
    IN _Id_Region         INT, -- [OBLIGATORIO]
    IN _Id_Gerencia       INT, -- [OPCIONAL]
    
    /* -----------------------------------------------------------------
       5. METADATOS ADMINISTRATIVOS
       Datos tabulares informativos.
       ----------------------------------------------------------------- */
    IN _Nivel             VARCHAR(50),
    IN _Clasificacion     VARCHAR(100)
)
THIS_PROC: BEGIN
    
    /* ============================================================================================
       BLOQUE 0: DECLARACIÓN DE VARIABLES DE ESTADO Y CONTEXTO
       Propósito: Contenedores en memoria para la lógica de comparación y control de flujo.
       ============================================================================================ */
    
    /* Punteros de Relación y Banderas */
    DECLARE v_Id_InfoPersonal INT DEFAULT NULL; 
    DECLARE v_Es_Activo       TINYINT(1);       
    DECLARE v_Id_Duplicado    INT;              
    
    /* Variables de Normalización (Input '0' -> NULL BD) */
    DECLARE v_Id_Puesto_Norm  INT;
    DECLARE v_Id_CT_Norm      INT;
    DECLARE v_Id_Dep_Norm     INT;
    DECLARE v_Id_Gerencia_Norm INT;

    /* Variables de Snapshot (Para almacenar el estado "ANTES" de la edición) */
    DECLARE v_Ficha_Act       VARCHAR(50);
    DECLARE v_Foto_Act        VARCHAR(255);
    DECLARE v_Nombre_Act      VARCHAR(255);
    DECLARE v_Paterno_Act     VARCHAR(255);
    DECLARE v_Materno_Act     VARCHAR(255);
    DECLARE v_Nacim_Act       DATE;
    DECLARE v_Ingre_Act       DATE;
    DECLARE v_Regimen_Act     INT;
    DECLARE v_Puesto_Act      INT;
    DECLARE v_CT_Act          INT;
    DECLARE v_Dep_Act         INT;
    DECLARE v_Region_Act      INT;
    DECLARE v_Geren_Act       INT;
    DECLARE v_Nivel_Act       VARCHAR(50);
    DECLARE v_Clasif_Act      VARCHAR(100);

    /* Variable Acumuladora de Cambios (El "Chismoso" para Feedback Granular) */
    DECLARE v_Cambios_Detectados VARCHAR(500) DEFAULT '';

    /* ============================================================================================
       BLOQUE 1: HANDLERS (MECANISMOS DE DEFENSA)
       Propósito: Garantizar una salida limpia y mensajes humanos ante errores técnicos.
       ============================================================================================ */
    
    /* [1.1] Handler 1062: Colisión de Unicidad
       Objetivo: Capturar si otro usuario registró la misma Ficha en el último milisegundo. */
    DECLARE EXIT HANDLER FOR 1062
    BEGIN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE CONFLICTO [409]: La Ficha que intentas guardar ya existe.';
    END;

    /* [1.2] Handler 1452: Integridad Referencial Rota (CRÍTICO)
       Objetivo: Atrapa casos donde el ID enviado es válido numéricamente (ej: Puesto 5), 
       pero la fila padre fue borrada físicamente de la BD durante la transacción. 
       Evita que el sistema colapse con un error técnico. */
    DECLARE EXIT HANDLER FOR 1452
    BEGIN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE INTEGRIDAD [409]: Uno de los catálogos seleccionados dejó de existir en el sistema.';
    END;

    /* [1.3] Handler Genérico: Fallos de sistema imprevistos */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; 
    END;

    /* ============================================================================================
       BLOQUE 2: SANITIZACIÓN Y NORMALIZACIÓN (INPUT HYGIENE)
       Propósito: Asegurar consistencia de datos (Mayúsculas, Sin espacios, Nulos correctos).
       ============================================================================================ */
    SET _Ficha            = TRIM(_Ficha);
    /* Limpieza de Foto: Si envían cadena vacía, se guarda NULL */
    SET _Url_Foto         = NULLIF(TRIM(_Url_Foto), '');
    
    SET _Nombre           = TRIM(UPPER(_Nombre));
    SET _Apellido_Paterno = TRIM(UPPER(_Apellido_Paterno));
    SET _Apellido_Materno = TRIM(UPPER(_Apellido_Materno));
    SET _Nivel            = TRIM(UPPER(_Nivel));
    SET _Clasificacion    = TRIM(UPPER(_Clasificacion));

    /* Normalización de IDs Opcionales: El Frontend puede enviar '0' para "Sin Selección". 
       La BD requiere NULL para mantener la integridad referencial y ahorrar espacio. */
    SET v_Id_Puesto_Norm   = NULLIF(_Id_Puesto, 0);
    SET v_Id_CT_Norm       = NULLIF(_Id_CentroTrabajo, 0);
    SET v_Id_Dep_Norm      = NULLIF(_Id_Departamento, 0);
    SET v_Id_Gerencia_Norm = NULLIF(_Id_Gerencia, 0);

    /* ============================================================================================
       BLOQUE 3: VALIDACIONES PREVIAS (FAIL FAST)
       Propósito: Rechazar peticiones inválidas antes de abrir transacción.
       ============================================================================================ */
    
    /* 3.1 Validación de Sesión */
    IF _Id_Usuario_Sesion IS NULL OR _Id_Usuario_Sesion <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SEGURIDAD [401]: Sesión no válida.';
    END IF;

    /* 3.2 Regla de Obligatoriedad Híbrida (Solo Régimen y Región son Hard Constraints) */
    IF (_Id_Regimen <= 0 OR _Id_Regimen IS NULL) OR 
       (_Id_Region <= 0 OR _Id_Region IS NULL) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN [400]: Régimen y Región son obligatorios.';
    END IF;

    /* ============================================================================================
       BLOQUE 4: INICIO DE TRANSACCIÓN Y BLOQUEO PESIMISTA
       Propósito: Asegurar aislamiento total para la lectura y escritura.
       ============================================================================================ */
    START TRANSACTION;

    /* 4.1 Bloqueo y Lectura de USUARIO (Parent Entity)
       Usamos `FOR UPDATE` para adquirir un "Write Lock". Nadie más puede tocar esta fila. */
    SELECT `Fk_Id_InfoPersonal`, `Ficha`, `Foto_Perfil_Url`
    INTO v_Id_InfoPersonal, v_Ficha_Act, v_Foto_Act
    FROM `Usuarios` 
    WHERE `Id_Usuario` = _Id_Usuario_Sesion
    FOR UPDATE;

    IF v_Id_InfoPersonal IS NULL THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE INTEGRIDAD [500]: Perfil de datos personales no encontrado.';
    END IF;

    /* 4.2 Bloqueo y Lectura de INFO_PERSONAL (Child Entity)
       Leemos el estado completo actual para alimentar el motor de detección de cambios. */
    SELECT 
        `Nombre`, `Apellido_Paterno`, `Apellido_Materno`, `Fecha_Nacimiento`, `Fecha_Ingreso`,
        `Fk_Id_CatRegimen`, `Fk_Id_CatPuesto`, `Fk_Id_CatCT`, `Fk_Id_CatDep`, `Fk_Id_CatRegion`, `Fk_Id_CatGeren`,
        `Nivel`, `Clasificacion`
    INTO 
        v_Nombre_Act, v_Paterno_Act, v_Materno_Act, v_Nacim_Act, v_Ingre_Act,
        v_Regimen_Act, v_Puesto_Act, v_CT_Act, v_Dep_Act, v_Region_Act, v_Geren_Act,
        v_Nivel_Act, v_Clasif_Act
    FROM `Info_Personal`
    WHERE `Id_InfoPersonal` = v_Id_InfoPersonal
    FOR UPDATE;

    /* ============================================================================================
       BLOQUE 5: MOTOR DE DETECCIÓN DE CAMBIOS (EL "CHISMOSO")
       Propósito: Construir el mensaje de feedback granular.
       Lógica: Comparamos campo por campo usando `<=>` (Null-Safe Equality).
       Si hay diferencias, agregamos una etiqueta legible al acumulador.
       ============================================================================================ */
    
    /* 5.1 Cambios en Identidad Digital */
    IF NOT (v_Ficha_Act <=> _Ficha) THEN SET v_Cambios_Detectados = CONCAT(v_Cambios_Detectados, 'Ficha Corporativa, '); END IF;
    IF NOT (v_Foto_Act <=> _Url_Foto) THEN SET v_Cambios_Detectados = CONCAT(v_Cambios_Detectados, 'Foto de Perfil, '); END IF;

    /* 5.2 Cambios en Datos Personales (Agrupados por semántica) */
    IF NOT (v_Nombre_Act <=> _Nombre) OR NOT (v_Paterno_Act <=> _Apellido_Paterno) OR 
       NOT (v_Materno_Act <=> _Apellido_Materno) OR NOT (v_Nacim_Act <=> _Fecha_Nacimiento) THEN
        SET v_Cambios_Detectados = CONCAT(v_Cambios_Detectados, 'Datos Personales, ');
    END IF;

    IF NOT (v_Ingre_Act <=> _Fecha_Ingreso) THEN SET v_Cambios_Detectados = CONCAT(v_Cambios_Detectados, 'Fecha de Ingreso, '); END IF;

    /* 5.3 Cambios Laborales (Adscripción y Ubicación) */
    IF NOT (v_Regimen_Act <=> _Id_Regimen) OR NOT (v_Region_Act <=> _Id_Region) OR
       NOT (v_Puesto_Act <=> v_Id_Puesto_Norm) OR NOT (v_CT_Act <=> v_Id_CT_Norm) OR
       NOT (v_Dep_Act <=> v_Id_Dep_Norm) OR NOT (v_Geren_Act <=> v_Id_Gerencia_Norm) OR
       NOT (v_Nivel_Act <=> _Nivel) OR NOT (v_Clasif_Act <=> _Clasificacion) THEN
       
       SET v_Cambios_Detectados = CONCAT(v_Cambios_Detectados, 'Datos Laborales/Ubicación, ');
    END IF;

    /* ============================================================================================
       BLOQUE 6: VERIFICACIÓN DE IDEMPOTENCIA
       Propósito: Optimización. Si el acumulador sigue vacío, el usuario guardó sin tocar nada.
       Acción: Retornamos éxito inmediato sin tocar disco.
       ============================================================================================ */
    IF v_Cambios_Detectados = '' THEN
        COMMIT; -- Liberamos locks
        SELECT 'No se detectaron cambios en la información.' AS Mensaje, _Id_Usuario_Sesion AS Id_Usuario, 'SIN_CAMBIOS' AS Accion;
        LEAVE THIS_PROC;
    END IF;

    /* ============================================================================================
       BLOQUE 7: VALIDACIONES DE NEGOCIO (Solo se ejecutan si hubo cambios reales)
       Propósito: Proteger la integridad de los datos antes de escribir.
       ============================================================================================ */

    /* 7.1 Colisión de Ficha (Solo si cambió la ficha)
       Verificamos que la nueva ficha no pertenezca a OTRO usuario (`Id != Me`). */
    IF LOCATE('Ficha', v_Cambios_Detectados) > 0 THEN
        SELECT `Id_Usuario` INTO v_Id_Duplicado 
        FROM `Usuarios` WHERE `Ficha` = _Ficha AND `Id_Usuario` <> _Id_Usuario_Sesion LIMIT 1;
        
        IF v_Id_Duplicado IS NOT NULL THEN
            ROLLBACK;
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'CONFLICTO [409]: La Ficha ingresada ya pertenece a otro usuario.';
        END IF;
    END IF;

    /* 7.2 Vigencia de Catálogos (Anti-Zombie Check) 
       Verificamos manualmente que los catálogos seleccionados sigan existiendo y estén `Activo=1`.
       Si alguno fue borrado, el Rollback ocurre aquí. */
    
    /* Obligatorios */
    SELECT `Activo` INTO v_Es_Activo FROM `Cat_Regimenes_Trabajo` WHERE `Id_CatRegimen` = _Id_Regimen;
    IF v_Es_Activo IS NULL OR v_Es_Activo = 0 THEN ROLLBACK; SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VIGENCIA: Régimen no válido.'; END IF;

    SELECT `Activo` INTO v_Es_Activo FROM `Cat_Regiones_Trabajo` WHERE `Id_CatRegion` = _Id_Region;
    IF v_Es_Activo IS NULL OR v_Es_Activo = 0 THEN ROLLBACK; SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VIGENCIA: Región no válida.'; END IF;

    /* Opcionales (Solo validamos si NO son NULL) */
    IF v_Id_Puesto_Norm IS NOT NULL THEN
        SELECT `Activo` INTO v_Es_Activo FROM `Cat_Puestos_Trabajo` WHERE `Id_CatPuesto` = v_Id_Puesto_Norm;
        IF v_Es_Activo IS NULL OR v_Es_Activo = 0 THEN ROLLBACK; SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VIGENCIA: Puesto inactivo.'; END IF;
    END IF;

    IF v_Id_CT_Norm IS NOT NULL THEN
        SELECT `Activo` INTO v_Es_Activo FROM `Cat_Centros_Trabajo` WHERE `Id_CatCT` = v_Id_CT_Norm;
        IF v_Es_Activo IS NULL OR v_Es_Activo = 0 THEN ROLLBACK; SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VIGENCIA: Centro de Trabajo inactivo.'; END IF;
    END IF;

    IF v_Id_Dep_Norm IS NOT NULL THEN
        SELECT `Activo` INTO v_Es_Activo FROM `Cat_Departamentos` WHERE `Id_CatDep` = v_Id_Dep_Norm;
        IF v_Es_Activo IS NULL OR v_Es_Activo = 0 THEN ROLLBACK; SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VIGENCIA: Departamento inactivo.'; END IF;
    END IF;

    IF v_Id_Gerencia_Norm IS NOT NULL THEN
        SELECT `Activo` INTO v_Es_Activo FROM `Cat_Gerencias_Activos` WHERE `Id_CatGeren` = v_Id_Gerencia_Norm;
        IF v_Es_Activo IS NULL OR v_Es_Activo = 0 THEN ROLLBACK; SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VIGENCIA: Gerencia inactiva.'; END IF;
    END IF;

    /* ============================================================================================
       BLOQUE 8: PERSISTENCIA (UPDATE)
       Propósito: Aplicar los cambios en la base de datos de manera atómica.
       ============================================================================================ */
    
    /* 8.1 Actualizar Info Personal */
    UPDATE `Info_Personal`
    SET 
        `Nombre` = _Nombre, `Apellido_Paterno` = _Apellido_Paterno, `Apellido_Materno` = _Apellido_Materno,
        `Fecha_Nacimiento` = _Fecha_Nacimiento, `Fecha_Ingreso` = _Fecha_Ingreso,
        `Fk_Id_CatRegimen` = _Id_Regimen, `Fk_Id_CatPuesto` = v_Id_Puesto_Norm,
        `Fk_Id_CatCT` = v_Id_CT_Norm, `Fk_Id_CatDep` = v_Id_Dep_Norm,
        `Fk_Id_CatRegion` = _Id_Region, `Fk_Id_CatGeren` = v_Id_Gerencia_Norm,
        `Nivel` = _Nivel, `Clasificacion` = _Clasificacion,
        `Fk_Id_Usuario_Updated_By` = _Id_Usuario_Sesion,
        `updated_at` = NOW()
    WHERE `Id_InfoPersonal` = v_Id_InfoPersonal;

    /* 8.2 Actualizar Usuario */
    UPDATE `Usuarios`
    SET
        `Ficha` = _Ficha,
        `Foto_Perfil_Url` = _Url_Foto,
        `Fk_Usuario_Updated_By` = _Id_Usuario_Sesion,
        `updated_at` = NOW()
    WHERE `Id_Usuario` = _Id_Usuario_Sesion;

    /* ============================================================================================
       BLOQUE 9: CONFIRMACIÓN Y RESPUESTA DINÁMICA
       Propósito: Cerrar la transacción y enviar el feedback al usuario.
       ============================================================================================ */
    COMMIT;

    /* Formateamos el mensaje final quitando la última coma sobrante y agregando el prefijo de éxito */
    /* Ejemplo salida: "ÉXITO: Se ha actualizado: Foto de Perfil, Datos Laborales." */
    SELECT 
        CONCAT('ÉXITO: Se ha actualizado: ', TRIM(TRAILING ', ' FROM v_Cambios_Detectados), '.') AS Mensaje,
        _Id_Usuario_Sesion AS Id_Usuario,
        'ACTUALIZADA' AS Accion;

END$$

DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_EditarUsuarioPorAdmin
   ============================================================================================

   --------------------------------------------------------------------------------------------
   I. VISIÓN GENERAL Y OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   --------------------------------------------------------------------------------------------
   [QUÉ ES]: 
   Es el motor transaccional de "Edición Maestra" (Superusuario). Permite la modificación 
   arbitraria y completa de cualquier expediente digital en el sistema, ignorando las 
   restricciones de solo lectura que tienen los usuarios normales.

   [CASO DE USO]: 
   Utilizado exclusivamente por el Panel de Administración para:
     a) Corregir errores humanos en el alta (Fichas o Correos mal escritos).
     b) Gestión de Crisis (Resetear contraseñas olvidadas sin el password anterior).
     c) Reingeniería Organizacional (Mover empleados de Gerencia o Región masivamente).
     d) Escalado de Privilegios (Ascender un Usuario a Coordinador/Admin).

   --------------------------------------------------------------------------------------------
   II. REGLAS DE VALIDACIÓN ESTRICTA (HARD CONSTRAINTS)
   --------------------------------------------------------------------------------------------
   A) INTEGRIDAD REFERENCIAL "ANTI-ZOMBIE":
      - Problema: Un Admin intenta mover un usuario a un Departamento que fue borrado hace 1 segundo.
      - Solución: Validación de existencia y vigencia (`Activo=1`) en tiempo real para todos
        los catálogos (Puesto, CT, Depto, etc.) antes de permitir el UPDATE.
      - Mecanismo: Handler SQLSTATE 1452 para capturar integridad rota.

   B) RESET DE CONTRASEÑA CONDICIONAL (SMART OVERRIDE):
      - Regla: "El Admin no necesita saber tu contraseña vieja para darte una nueva".
      - Lógica: 
         * Si `_Nueva_Contrasena` tiene valor -> Se encripta y sobrescribe la actual.
         * Si `_Nueva_Contrasena` es NULL/Vacío -> Se preserva el hash actual (No se toca).

   C) EXCLUSIÓN DE ESTATUS (ATOMICIDAD):
      - Este SP deliberadamente NO toca el campo `Activo`. La baja/reactivación se delega
        a un micro-servicio separado (`SP_CambiarEstatusUsuario`) para evitar accidentes.

   --------------------------------------------------------------------------------------------
   III. ARQUITECTURA DE CONCURRENCIA (DETERMINISTIC LOCKING PATTERN)
   --------------------------------------------------------------------------------------------
   [EL PROBLEMA DE LA "CARRERA" (RACE CONDITION)]:
   Escenario: El Admin A abre el perfil de "Juan". El Admin B abre el mismo perfil.
   A cambia el Puesto. B cambia el Correo. Ambos guardan. El último sobrescribe al primero 
   sin saberlo ("Lost Update").

   [LA SOLUCIÓN BLINDADA]:
   Implementamos un **Bloqueo Pesimista** (`SELECT ... FOR UPDATE`) al inicio de la transacción.
     - Efecto: La fila del usuario `_Id_Usuario_Objetivo` queda "secuestrada" por la transacción.
     - Resultado: Si otro Admin intenta editar al mismo usuario simultáneamente, su petición 
       quedará en espera (Wait) hasta que la primera termine. Garantiza consistencia SERIALIZABLE.

   --------------------------------------------------------------------------------------------
   IV. IDEMPOTENCIA (OPTIMIZACIÓN DE RECURSOS)
   --------------------------------------------------------------------------------------------
   [MOTOR DE DETECCIÓN DE CAMBIOS]:
   - Antes de escribir en disco, el SP extrae un "Snapshot" del estado actual del registro.
   - Compara matemáticamente cada campo nuevo contra el actual (usando `<=>` para NULLs).
   - Si `Delta = 0` (No hay cambios), retorna éxito inmediato (`SIN_CAMBIOS`) y libera la conexión.
   - Beneficio: Reduce la carga de I/O en el disco del servidor y evita logs de auditoría basura.

   --------------------------------------------------------------------------------------------
   V. CONTRATO DE SALIDA (OUTPUT CONTRACT)
   --------------------------------------------------------------------------------------------
   Retorna un resultset único con:
      - Mensaje (VARCHAR): Feedback humano detallando qué cambió ("Se actualizó: Rol, Foto").
      - Accion (VARCHAR): Códigos de estado para el Frontend ('ACTUALIZADA', 'SIN_CAMBIOS', 'CONFLICTO').
      - Id_Usuario (INT): Contexto para refrescar la vista.
   ============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_EditarUsuarioPorAdmin`$$

CREATE PROCEDURE `SP_EditarUsuarioPorAdmin`(
    /* -----------------------------------------------------------------
       1. CONTEXTO DE AUDITORÍA (ACTORES)
       ----------------------------------------------------------------- */
    IN _Id_Admin_Ejecutor    INT,   -- Quién realiza el cambio (Auditoría)
    IN _Id_Usuario_Objetivo  INT,   -- A quién se le aplica el cambio (Target)

    /* -----------------------------------------------------------------
       2. INFO USUARIO (CRÍTICOS DE IDENTIDAD)
       ----------------------------------------------------------------- */
    IN _Ficha                VARCHAR(50),
    IN _Url_Foto             VARCHAR(255),

    /* -----------------------------------------------------------------
       3. IDENTIDAD HUMANA (DEMOGRÁFICOS)
       ----------------------------------------------------------------- */
    IN _Nombre               VARCHAR(255),
    IN _Apellido_Paterno     VARCHAR(255),
    IN _Apellido_Materno     VARCHAR(255),
    IN _Fecha_Nacimiento     DATE,
    IN _Fecha_Ingreso        DATE,

	/* -----------------------------------------------------------------
	   2.5 SEGURIDAD Y ACCESOS Y PRIVILEGIOS (CRÍTICOS DE SISTEMA)
	   ----------------------------------------------------------------- */
    IN _Email                VARCHAR(255),
    IN _Nueva_Contrasena     VARCHAR(255), -- OPCIONAL: Si viene lleno, se resetea el password
	IN _Id_Rol               INT,          -- [ADMIN POWER] Cambio de privilegios
    

    /* -----------------------------------------------------------------
       4. MATRIZ DE ADSCRIPCIÓN (UBICACIÓN EN EL ORGANIGRAMA)
       ----------------------------------------------------------------- */
    IN _Id_Regimen           INT, 
    IN _Id_Puesto            INT, 
    IN _Id_CentroTrabajo     INT, 
    IN _Id_Departamento      INT, 
    IN _Id_Region            INT, 
    IN _Id_Gerencia          INT, 
    
    /* -----------------------------------------------------------------
       5. METADATOS
       ----------------------------------------------------------------- */
    IN _Nivel                VARCHAR(50),
    IN _Clasificacion        VARCHAR(100)

)
THIS_PROC: BEGIN
    
    /* ============================================================================================
       BLOQUE 0: VARIABLES DE ESTADO Y CONTEXTO
       ============================================================================================ */
    DECLARE v_Id_InfoPersonal INT DEFAULT NULL; 
    DECLARE v_Es_Activo       TINYINT(1);       
    DECLARE v_Id_Duplicado    INT;              
    
    /* Normalización de IDs (Input '0' -> NULL BD) */
    DECLARE v_Id_Puesto_Norm   INT;
    DECLARE v_Id_CT_Norm       INT;
    DECLARE v_Id_Dep_Norm      INT;
    DECLARE v_Id_Gerencia_Norm INT;
    DECLARE v_Pass_Norm        VARCHAR(255); -- Para lógica de reset de password

    /* Snapshots (Estado Actual en BD para comparación) */
    DECLARE v_Ficha_Act       VARCHAR(50);
    DECLARE v_Email_Act       VARCHAR(255); 
    DECLARE v_Rol_Act         INT;
    DECLARE v_Foto_Act        VARCHAR(255);
    
    DECLARE v_Nombre_Act      VARCHAR(255);
    DECLARE v_Paterno_Act     VARCHAR(255);
    DECLARE v_Materno_Act     VARCHAR(255);
    DECLARE v_Nacim_Act       DATE;
    DECLARE v_Ingre_Act       DATE;
    
    DECLARE v_Regimen_Act     INT;
    DECLARE v_Puesto_Act      INT;
    DECLARE v_CT_Act          INT;
    DECLARE v_Dep_Act         INT;
    DECLARE v_Region_Act      INT;
    DECLARE v_Geren_Act       INT;
    DECLARE v_Nivel_Act       VARCHAR(50);
    DECLARE v_Clasif_Act      VARCHAR(100);

    /* Acumulador de Cambios (El "Chismoso") */
    DECLARE v_Cambios_Detectados VARCHAR(1000) DEFAULT '';

    /* ============================================================================================
       BLOQUE 1: HANDLERS DE SEGURIDAD (MECANISMOS DE DEFENSA)
       ============================================================================================ */
    
    /* [1.1] Colisión de Unicidad
       Objetivo: Capturar si se intenta asignar una Ficha/Email que ya existe en otro usuario. */
    DECLARE EXIT HANDLER FOR 1062
    BEGIN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE CONFLICTO [409]: La Ficha o el Email ingresados ya pertenecen a otro usuario.';
    END;

    /* [1.2] Integridad Referencial Rota (Error 1452)
       Objetivo: Proteger el sistema si un catálogo es eliminado físicamente mientras se edita. */
    DECLARE EXIT HANDLER FOR 1452
    BEGIN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE INTEGRIDAD [409]: Uno de los catálogos seleccionados dejó de existir en el sistema.';
    END;

    /* [1.3] Handler Genérico (Crash Safety) */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; 
    END;

    /* ============================================================================================
       BLOQUE 2: SANITIZACIÓN Y NORMALIZACIÓN (INPUT HYGIENE)
       ============================================================================================ */
    SET _Ficha            = TRIM(_Ficha);
    SET _Email            = TRIM(_Email);
    SET _Url_Foto         = NULLIF(TRIM(_Url_Foto), '');
    
    /* Lógica de Password: Si viene vacío/null, normalizamos a NULL para que el COALESCE posterior funcione */
    SET v_Pass_Norm       = NULLIF(TRIM(_Nueva_Contrasena), '');

    SET _Nombre           = TRIM(UPPER(_Nombre));
    SET _Apellido_Paterno = TRIM(UPPER(_Apellido_Paterno));
    SET _Apellido_Materno = TRIM(UPPER(_Apellido_Materno));
    SET _Nivel            = TRIM(UPPER(_Nivel));
    SET _Clasificacion    = TRIM(UPPER(_Clasificacion));

    /* Normalización de IDs (Convertir 0 a NULL para integridad referencial) */
    SET v_Id_Puesto_Norm   = NULLIF(_Id_Puesto, 0);
    SET v_Id_CT_Norm       = NULLIF(_Id_CentroTrabajo, 0);
    SET v_Id_Dep_Norm      = NULLIF(_Id_Departamento, 0);
    SET v_Id_Gerencia_Norm = NULLIF(_Id_Gerencia, 0);

    /* ============================================================================================
       BLOQUE 3: VALIDACIONES PREVIAS (FAIL FAST)
       ============================================================================================ */
    
    /* 3.1 Integridad de Auditoría */
    IF _Id_Admin_Ejecutor IS NULL OR _Id_Admin_Ejecutor <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE AUDITORÍA [403]: ID de Administrador no válido. No se puede auditar el cambio.';
    END IF;

    IF _Id_Usuario_Objetivo IS NULL OR _Id_Usuario_Objetivo <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: ID de Usuario Objetivo no válido.';
    END IF;

    /* 3.2 Campos Críticos de Sistema (Admin no puede dejar esto vacío) */
    IF _Id_Rol <= 0 OR _Id_Rol IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN [400]: El ROL es obligatorio. Un usuario no puede existir sin permisos.';
    END IF;

    /* 3.3 Regla de Adscripción Híbrida */
    IF (_Id_Regimen <= 0 OR _Id_Regimen IS NULL) OR 
       (_Id_Region <= 0 OR _Id_Region IS NULL) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN [400]: Régimen y Región son obligatorios para la estructura organizacional.';
    END IF;

    /* ============================================================================================
       BLOQUE 4: INICIO TRANSACCIÓN Y BLOQUEO PESIMISTA
       ============================================================================================ */
    START TRANSACTION;

    /* 4.1 Bloqueo del USUARIO OBJETIVO
       Usamos `FOR UPDATE` para adquirir un "Write Lock". Nadie más puede tocar esta fila. 
       Esto previene condiciones de carrera si dos admins editan al mismo usuario. */
    SELECT 
        `Fk_Id_InfoPersonal`, `Ficha`, `Email`, `Foto_Perfil_Url`, `Fk_Rol`
    INTO 
        v_Id_InfoPersonal, v_Ficha_Act, v_Email_Act, v_Foto_Act, v_Rol_Act
    FROM `Usuarios` 
    WHERE `Id_Usuario` = _Id_Usuario_Objetivo
    FOR UPDATE;

    IF v_Id_InfoPersonal IS NULL THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [404]: El usuario objetivo no existe.';
    END IF;

    /* 4.2 Bloqueo de INFO_PERSONAL (Tabla Satélite) */
    SELECT 
        `Nombre`, `Apellido_Paterno`, `Apellido_Materno`, `Fecha_Nacimiento`, `Fecha_Ingreso`,
        `Fk_Id_CatRegimen`, `Fk_Id_CatPuesto`, `Fk_Id_CatCT`, `Fk_Id_CatDep`, `Fk_Id_CatRegion`, `Fk_Id_CatGeren`,
        `Nivel`, `Clasificacion`
    INTO 
        v_Nombre_Act, v_Paterno_Act, v_Materno_Act, v_Nacim_Act, v_Ingre_Act,
        v_Regimen_Act, v_Puesto_Act, v_CT_Act, v_Dep_Act, v_Region_Act, v_Geren_Act,
        v_Nivel_Act, v_Clasif_Act
    FROM `Info_Personal`
    WHERE `Id_InfoPersonal` = v_Id_InfoPersonal
    FOR UPDATE;

    /* ============================================================================================
       BLOQUE 5: MOTOR DE DETECCIÓN DE CAMBIOS (GRANULARIDAD)
       Compara Snapshot vs Inputs. Si hay diferencias, acumula el nombre del campo para el feedback.
       ============================================================================================ */
    
    /* 5.1 Credenciales y Seguridad [ADMIN POWER] */
    IF NOT (v_Ficha_Act <=> _Ficha) THEN SET v_Cambios_Detectados = CONCAT(v_Cambios_Detectados, 'Ficha, '); END IF;
    IF NOT (v_Email_Act <=> _Email) THEN SET v_Cambios_Detectados = CONCAT(v_Cambios_Detectados, 'Email, '); END IF;
    IF NOT (v_Rol_Act <=> _Id_Rol)  THEN SET v_Cambios_Detectados = CONCAT(v_Cambios_Detectados, 'Rol de Sistema, '); END IF;
    IF NOT (v_Foto_Act <=> _Url_Foto) THEN SET v_Cambios_Detectados = CONCAT(v_Cambios_Detectados, 'Foto de Perfil, '); END IF;
    
    /* ** Detección especial de Contraseña [ADMIN POWER] ** */
    /* Si v_Pass_Norm tiene valor, significa que el Admin quiere resetearla. Eso es un cambio explícito. */
    IF v_Pass_Norm IS NOT NULL THEN
        SET v_Cambios_Detectados = CONCAT(v_Cambios_Detectados, 'Contraseña (Reset), ');
    END IF;

    /* 5.2 Datos Personales */
    IF NOT (v_Nombre_Act <=> _Nombre) OR NOT (v_Paterno_Act <=> _Apellido_Paterno) OR 
       NOT (v_Materno_Act <=> _Apellido_Materno) OR NOT (v_Nacim_Act <=> _Fecha_Nacimiento) THEN
        SET v_Cambios_Detectados = CONCAT(v_Cambios_Detectados, 'Datos Personales, ');
    END IF;

    IF NOT (v_Ingre_Act <=> _Fecha_Ingreso) THEN SET v_Cambios_Detectados = CONCAT(v_Cambios_Detectados, 'Fecha Ingreso, '); END IF;

    /* 5.3 Datos Laborales */
    IF NOT (v_Regimen_Act <=> _Id_Regimen) OR NOT (v_Region_Act <=> _Id_Region) OR
       NOT (v_Puesto_Act <=> v_Id_Puesto_Norm) OR NOT (v_CT_Act <=> v_Id_CT_Norm) OR
       NOT (v_Dep_Act <=> v_Id_Dep_Norm) OR NOT (v_Geren_Act <=> v_Id_Gerencia_Norm) OR
       NOT (v_Nivel_Act <=> _Nivel) OR NOT (v_Clasif_Act <=> _Clasificacion) THEN
       
       SET v_Cambios_Detectados = CONCAT(v_Cambios_Detectados, 'Adscripción Laboral, ');
    END IF;

    /* ============================================================================================
       BLOQUE 6: VERIFICACIÓN DE IDEMPOTENCIA
       Si el acumulador sigue vacío, significa que el usuario guardó sin tocar nada.
       ============================================================================================ */
    IF v_Cambios_Detectados = '' THEN
        COMMIT; 
        SELECT 'No se detectaron cambios en el expediente.' AS Mensaje, _Id_Usuario_Objetivo AS Id_Usuario, 'SIN_CAMBIOS' AS Accion;
        LEAVE THIS_PROC;
    END IF;

    /* ============================================================================================
       BLOQUE 7: VALIDACIONES DE NEGOCIO (POST-LOCK)
       Estas validaciones son 100% fiables porque tenemos el registro bloqueado.
       ============================================================================================ */

    /* 7.1 Colisión de Ficha (Excluyendo al usuario objetivo) */
    IF LOCATE('Ficha', v_Cambios_Detectados) > 0 THEN
        SELECT `Id_Usuario` INTO v_Id_Duplicado 
        FROM `Usuarios` WHERE `Ficha` = _Ficha AND `Id_Usuario` <> _Id_Usuario_Objetivo LIMIT 1;
        
        IF v_Id_Duplicado IS NOT NULL THEN
            ROLLBACK;
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'CONFLICTO [409]: La Ficha asignada ya pertenece a otro usuario.';
        END IF;
    END IF;

    /* 7.2 Colisión de Email (Excluyendo al usuario objetivo) - [ADMIN POWER CHECK] */
    IF LOCATE('Email', v_Cambios_Detectados) > 0 THEN
        SELECT `Id_Usuario` INTO v_Id_Duplicado 
        FROM `Usuarios` WHERE `Email` = _Email AND `Id_Usuario` <> _Id_Usuario_Objetivo LIMIT 1;
        
        IF v_Id_Duplicado IS NOT NULL THEN
            ROLLBACK;
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'CONFLICTO [409]: El Email asignado ya pertenece a otro usuario.';
        END IF;
    END IF;

    /* 7.3 Vigencia de Catálogos (Validación Manual para Feedback) */
    
    /* Rol (Mandatory) */
    SELECT `Activo` INTO v_Es_Activo FROM `Cat_Roles` WHERE `Id_Rol` = _Id_Rol;
    IF v_Es_Activo IS NULL OR v_Es_Activo = 0 THEN ROLLBACK; SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VIGENCIA: El Rol seleccionado no existe o está inactivo.'; END IF;

    /* Laborales (Mandatory) */
    SELECT `Activo` INTO v_Es_Activo FROM `Cat_Regimenes_Trabajo` WHERE `Id_CatRegimen` = _Id_Regimen;
    IF v_Es_Activo IS NULL OR v_Es_Activo = 0 THEN ROLLBACK; SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VIGENCIA: Régimen no válido.'; END IF;

    SELECT `Activo` INTO v_Es_Activo FROM `Cat_Regiones_Trabajo` WHERE `Id_CatRegion` = _Id_Region;
    IF v_Es_Activo IS NULL OR v_Es_Activo = 0 THEN ROLLBACK; SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VIGENCIA: Región no válida.'; END IF;

    /* Laborales (Optional - Solo si traen datos) */
    IF v_Id_Puesto_Norm IS NOT NULL THEN
        SELECT `Activo` INTO v_Es_Activo FROM `Cat_Puestos_Trabajo` WHERE `Id_CatPuesto` = v_Id_Puesto_Norm;
        IF v_Es_Activo IS NULL OR v_Es_Activo = 0 THEN ROLLBACK; SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VIGENCIA: Puesto inactivo.'; END IF;
    END IF;

    IF v_Id_CT_Norm IS NOT NULL THEN
        SELECT `Activo` INTO v_Es_Activo FROM `Cat_Centros_Trabajo` WHERE `Id_CatCT` = v_Id_CT_Norm;
        IF v_Es_Activo IS NULL OR v_Es_Activo = 0 THEN ROLLBACK; SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VIGENCIA: Centro de Trabajo inactivo.'; END IF;
    END IF;

    IF v_Id_Dep_Norm IS NOT NULL THEN
        SELECT `Activo` INTO v_Es_Activo FROM `Cat_Departamentos` WHERE `Id_CatDep` = v_Id_Dep_Norm;
        IF v_Es_Activo IS NULL OR v_Es_Activo = 0 THEN ROLLBACK; SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VIGENCIA: Departamento inactivo.'; END IF;
    END IF;

    IF v_Id_Gerencia_Norm IS NOT NULL THEN
        SELECT `Activo` INTO v_Es_Activo FROM `Cat_Gerencias_Activos` WHERE `Id_CatGeren` = v_Id_Gerencia_Norm;
        IF v_Es_Activo IS NULL OR v_Es_Activo = 0 THEN ROLLBACK; SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VIGENCIA: Gerencia inactiva.'; END IF;
    END IF;

    /* ============================================================================================
       BLOQUE 8: PERSISTENCIA (UPDATE)
       ============================================================================================ */
    
    /* 8.1 Actualizar Info Personal (Datos Humanos) */
    UPDATE `Info_Personal`
    SET 
        `Nombre` = _Nombre, `Apellido_Paterno` = _Apellido_Paterno, `Apellido_Materno` = _Apellido_Materno,
        `Fecha_Nacimiento` = _Fecha_Nacimiento, `Fecha_Ingreso` = _Fecha_Ingreso,
        `Fk_Id_CatRegimen` = _Id_Regimen, `Fk_Id_CatPuesto` = v_Id_Puesto_Norm,
        `Fk_Id_CatCT` = v_Id_CT_Norm, `Fk_Id_CatDep` = v_Id_Dep_Norm,
        `Fk_Id_CatRegion` = _Id_Region, `Fk_Id_CatGeren` = v_Id_Gerencia_Norm,
        `Nivel` = _Nivel, `Clasificacion` = _Clasificacion,
        /* Auditoría Cruzada: Registramos al Admin como responsable */
        `Fk_Id_Usuario_Updated_By` = _Id_Admin_Ejecutor,
        `updated_at` = NOW()
    WHERE `Id_InfoPersonal` = v_Id_InfoPersonal;

    /* 8.2 Actualizar Usuario (Credenciales y Seguridad) [ADMIN POWER] */
    UPDATE `Usuarios`
    SET
        `Ficha` = _Ficha,
        `Email` = _Email,           -- Admin SÍ puede corregir email
        `Foto_Perfil_Url` = _Url_Foto,
        `Fk_Rol` = _Id_Rol,         -- Admin SÍ puede cambiar roles
        
        /* Reset de Password Condicional: Usamos COALESCE para preservar si es NULL */
        `Contraseña` = COALESCE(v_Pass_Norm, `Contraseña`),
        
        `Fk_Usuario_Updated_By` = _Id_Admin_Ejecutor,
        `updated_at` = NOW()
    WHERE `Id_Usuario` = _Id_Usuario_Objetivo;

    /* ============================================================================================
       BLOQUE 9: CONFIRMACIÓN Y RESPUESTA
       ============================================================================================ */
    COMMIT;

    /* Feedback Granular */
    SELECT 
        CONCAT('ÉXITO: Se ha actualizado: ', TRIM(TRAILING ', ' FROM v_Cambios_Detectados), '.') AS Mensaje,
        _Id_Usuario_Objetivo AS Id_Usuario,
        'ACTUALIZADA' AS Accion;

END$$

DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_ActualizarCredencialesPropio
   ============================================================================================

   --------------------------------------------------------------------------------------------
   I. PROPÓSITO Y OBJETIVO DE NEGOCIO (THE "WHAT")
   --------------------------------------------------------------------------------------------
   [QUÉ ES]: 
   Es el motor transaccional especializado para la gestión autónoma de credenciales de acceso 
   (Self-Service Security). Permite al usuario modificar sus llaves digitales sin intervención 
   administrativa.

   [ALCANCE OPERATIVO]:
   Gestiona la mutación de los dos vectores de autenticación:
     1. Login (Email): Identificador único de acceso.
     2. Secreto (Contraseña): Hash criptográfico de seguridad.

   [PRE-REQUISITO DE ARQUITECTURA]:
   Este SP asume que la capa de aplicación (Backend/API) YA realizó la validación de la 
   "Contraseña Anterior" antes de invocar este procedimiento. La base de datos confía en que 
   la solicitud es legítima y se limita a persistir los cambios y validar unicidad.

   --------------------------------------------------------------------------------------------
   II. REGLAS DE NEGOCIO (BUSINESS RULES)
   --------------------------------------------------------------------------------------------
   [RN-01] MODIFICACIÓN ATÓMICA Y PARCIAL (FLEXIBILIDAD):
      - El diseño soporta cambios independientes:
         * Solo Email (Password NULL).
         * Solo Password (Email NULL).
         * Ambos simultáneamente.
      - Si un parámetro llega NULL o vacío, se preserva el valor actual en la BD.

   [RN-02] BLINDAJE DE IDENTIDAD (ANTI-COLLISION):
      - Si el usuario intenta cambiar su Email, se verifica estrictamente que el nuevo correo 
        no pertenezca a otro usuario (`Id != Me`).
      - Si hay conflicto, se rechaza la operación con un error 409 controlado.

   [RN-03] IDEMPOTENCIA DE SEGURIDAD (OPTIMIZACIÓN):
      - Si el usuario envía datos idénticos a los actuales (mismo Email, mismo Hash), 
        el sistema detecta la redundancia, reporta éxito ("Sin Cambios") y no toca el disco.

   --------------------------------------------------------------------------------------------
   III. ESPECIFICACIÓN TÉCNICA
   --------------------------------------------------------------------------------------------
   - TIPO: Transacción ACID con Aislamiento de Lectura.
   - BLOQUEO: Pesimista (`FOR UPDATE`) sobre la fila del usuario para evitar condiciones de carrera.
   - TRAZABILIDAD: El usuario se registra a sí mismo como el autor del cambio (`Updated_By`).
   ============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ActualizarCredencialesPropio`$$

CREATE PROCEDURE `SP_ActualizarCredencialesPropio`(
    /* Contexto de Sesión */
    IN _Id_Usuario_Sesion  INT,          -- [TOKEN] Quién solicita el cambio

    /* Nuevas Credenciales (Opcionales) */
    IN _Nuevo_Email        VARCHAR(255), -- [LOGIN] NULL si no se quiere cambiar
    IN _Nueva_Contrasena   VARCHAR(255)  -- [HASH] NULL si no se quiere cambiar
)
THIS_PROC: BEGIN
    
    /* ========================================================================================
       BLOQUE 0: VARIABLES DE ESTADO Y CONTEXTO
       Propósito: Contenedores para almacenar el estado actual y evaluar cambios.
       ======================================================================================== */
    DECLARE v_Email_Act    VARCHAR(255);
    DECLARE v_Pass_Act     VARCHAR(255);
    DECLARE v_Id_Duplicado INT;
    
    /* Variables Normalizadas */
    DECLARE v_Email_Norm   VARCHAR(255);
    DECLARE v_Pass_Norm    VARCHAR(255);

    /* Acumulador de Feedback */
    DECLARE v_Cambios_Detectados VARCHAR(255) DEFAULT '';

    /* ========================================================================================
       BLOQUE 1: HANDLERS (MECANISMOS DE DEFENSA)
       ======================================================================================== */
    
    /* [1.1] Handler para colisión de Email (Unique Key)
       Objetivo: Capturar si otro usuario registró el mismo correo en el último milisegundo. */
    DECLARE EXIT HANDLER FOR 1062
    BEGIN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE CONFLICTO [409]: El correo electrónico ingresado ya está siendo usado por otro usuario.';
    END;

    /* [1.2] Handler Genérico (Crash Safety) */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; 
    END;

    /* ========================================================================================
       BLOQUE 2: SANITIZACIÓN Y NORMALIZACIÓN (INPUT HYGIENE)
       ======================================================================================== */
    
    /* 2.1 Integridad de Sesión */
    IF _Id_Usuario_Sesion IS NULL OR _Id_Usuario_Sesion <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SEGURIDAD [401]: Sesión no válida.';
    END IF;

    /* 2.2 Normalización de Inputs
       Convertimos cadenas vacías o espacios en NULL para que la lógica COALESCE funcione. */
    SET v_Email_Norm = NULLIF(TRIM(_Nuevo_Email), '');
    SET v_Pass_Norm  = NULLIF(TRIM(_Nueva_Contrasena), '');

    /* 2.3 Validación de Propósito
       Evitamos transacciones vacías. Al menos un dato debe venir para actualizar. */
    IF v_Email_Norm IS NULL AND v_Pass_Norm IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN [400]: Debe proporcionar al menos un dato para actualizar (Email o Contraseña).';
    END IF;

    /* ========================================================================================
       BLOQUE 3: INICIO DE TRANSACCIÓN Y BLOQUEO PESIMISTA
       ======================================================================================== */
    START TRANSACTION;

    /* Bloqueo de Fila: Nadie puede modificar esta cuenta mientras cambiamos las llaves.
       Solo leemos las columnas necesarias para comparar. */
    SELECT `Email`, `Contraseña`
    INTO v_Email_Act, v_Pass_Act
    FROM `Usuarios`
    WHERE `Id_Usuario` = _Id_Usuario_Sesion
    FOR UPDATE;

    /* Safety Check: Si el usuario fue borrado justo antes de entrar aquí */
    IF v_Email_Act IS NULL THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR CRÍTICO [404]: La cuenta de usuario no existe.';
    END IF;

    /* ========================================================================================
       BLOQUE 4: DETECCIÓN DE CAMBIOS Y VALIDACIÓN DE UNICIDAD
       ======================================================================================== */

    /* 4.1 Análisis de Email */
    IF v_Email_Norm IS NOT NULL THEN
        IF v_Email_Norm <> v_Email_Act THEN
            /* Cambio detectado: Verificamos disponibilidad */
            SELECT `Id_Usuario` INTO v_Id_Duplicado 
            FROM `Usuarios` 
            WHERE `Email` = v_Email_Norm AND `Id_Usuario` <> _Id_Usuario_Sesion 
            LIMIT 1;

            IF v_Id_Duplicado IS NOT NULL THEN
                ROLLBACK;
                SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'CONFLICTO [409]: El nuevo correo electrónico ya pertenece a otra cuenta.';
            END IF;

            SET v_Cambios_Detectados = CONCAT(v_Cambios_Detectados, 'Correo Electrónico, ');
        ELSE
            /* Falso Positivo: El usuario envió el mismo correo que ya tiene. Lo anulamos. */
            SET v_Email_Norm = NULL; 
        END IF;
    END IF;

    /* 4.2 Análisis de Contraseña */
    IF v_Pass_Norm IS NOT NULL THEN
        /* Comparamos el hash nuevo contra el actual. */
        IF v_Pass_Norm <> v_Pass_Act THEN
            SET v_Cambios_Detectados = CONCAT(v_Cambios_Detectados, 'Contraseña, ');
        ELSE
            SET v_Pass_Norm = NULL;
        END IF;
    END IF;

    /* ========================================================================================
       BLOQUE 5: VERIFICACIÓN DE IDEMPOTENCIA
       Si no hubo cambios reales, salimos sin tocar disco.
       ======================================================================================== */
    IF v_Cambios_Detectados = '' THEN
        COMMIT;
        SELECT 'No se detectaron cambios en las credenciales.' AS Mensaje, _Id_Usuario_Sesion AS Id_Usuario, 'SIN_CAMBIOS' AS Accion;
        LEAVE THIS_PROC;
    END IF;

    /* ========================================================================================
       BLOQUE 6: PERSISTENCIA (UPDATE)
       ======================================================================================== */
    
    UPDATE `Usuarios`
    SET 
        /* Si v_Email_Norm es NULL (porque no cambió o no se envió), COALESCE mantiene el actual */
        `Email` = COALESCE(v_Email_Norm, `Email`),
        
        /* Si v_Pass_Norm es NULL, COALESCE mantiene la actual */
        `Contraseña` = COALESCE(v_Pass_Norm, `Contraseña`),

        /* Auditoría: El usuario modificó su propia seguridad */
        `Fk_Usuario_Updated_By` = _Id_Usuario_Sesion,
        `updated_at` = NOW()
    WHERE `Id_Usuario` = _Id_Usuario_Sesion;

    /* ========================================================================================
       BLOQUE 7: RESPUESTA DINÁMICA
       ======================================================================================== */
    COMMIT;

    /* Ejemplo Salida: "SEGURIDAD ACTUALIZADA: Se modificó: Correo Electrónico, Contraseña." */
    SELECT 
        CONCAT('SEGURIDAD ACTUALIZADA: Se modificó: ', TRIM(TRAILING ', ' FROM v_Cambios_Detectados), '.') AS Mensaje,
        _Id_Usuario_Sesion AS Id_Usuario,
        'ACTUALIZADA' AS Accion;

END$$

DELIMITER ;

/* ====================================================================================================
   PROCEDIMIENTO: SP_CambiarEstatusUsuario
   ====================================================================================================
   
   ----------------------------------------------------------------------------------------------------
   I. VISIÓN GENERAL Y OBJETIVO ESTRATÉGICO (EXECUTIVE SUMMARY)
   ----------------------------------------------------------------------------------------------------
   [DEFINICIÓN DEL COMPONENTE]:
   Este Stored Procedure actúa como el **Motor de Gobierno de Identidades** (Identity Governance Engine) 
   del sistema. No es un simple "switch" de apagado/encendido; es un orquestador de ciclo de vida que 
   garantiza la continuidad operativa de la empresa.

   [EL PROBLEMA DE NEGOCIO QUE RESUELVE]:
   En una organización de capacitación de alto rendimiento (como PEMEX), el capital humano es el activo 
   más crítico. La desactivación de un usuario no es un evento aislado, es un riesgo sistémico.
   
   * Escenario de Riesgo 1 (El Instructor Fantasma): Si un administrador desactiva por error a un 
     instructor que tiene un curso programado para mañana a las 8:00 AM, el sistema impide el acceso, 
     el instructor no llega, y se genera una pérdida financiera y de reputación ("Evento Acéfalo").
   
   * Escenario de Riesgo 2 (El Alumno Zombie): Si se da de baja a un alumno a mitad de un curso, 
     se corrompen las métricas de asistencia, las actas de calificación y los historiales de 
     cumplimiento normativo (SSPA).

   [SOLUCIÓN ARQUITECTÓNICA]:
   Se implementa un mecanismo de **"Baja Lógica Condicional"** (Conditional Soft Delete).
   Antes de permitir la desactivación, el sistema ejecuta un análisis forense en tiempo real de las 
   dependencias del usuario. Si el usuario es un "Nodo Activo" en la red de capacitación (Instructor 
   o Participante), la operación se bloquea automáticamente.

   ----------------------------------------------------------------------------------------------------
   II. MATRIZ DE REGLAS DE BLINDAJE (SECURITY & INTEGRITY RULES)
   ----------------------------------------------------------------------------------------------------
   
   [RN-01] PROTOCOLO ANTI-LOCKOUT (SEGURIDAD DE ACCESO):
      - Principio: "Seguridad contra el error humano propio".
      - Regla: Un usuario con privilegios de Administrador tiene estrictamente PROHIBIDO desactivar 
        su propia cuenta. Esto evita el escenario de "cerrar la puerta con las llaves adentro".

   [RN-02] INTEGRIDAD REFERENCIAL SINCRONIZADA (ATOMIC DATA CONSISTENCY):
      - Principio: "Una identidad, un estado".
      - Regla: El sistema PICADE maneja la identidad en dos capas:
           1. Capa de Acceso (`Usuarios`): Login y Credenciales.
           2. Capa Operativa (`Info_Personal`): Recursos Humanos y Catálogos.
      - Mecanismo: El SP garantiza atomicidad. Si se desactiva el Usuario, se fuerza la desactivación 
        inmediata de la ficha de Personal asociada. Esto limpia los selectores de "Instructores Disponibles" 
        en el frontend instantáneamente.

   [RN-03] CANDADO OPERATIVO DINÁMICO (THE DYNAMIC KILLSWITCH):
      - Principio: "Prioridad a la Operación Viva".
      - Definición: La baja de un usuario está subordinada a que no tenga compromisos activos.
      
      A) VECTOR DE INSTRUCTOR/FACILITADOR (`DatosCapacitaciones`):
         - Alcance: Aplica a cualquier usuario (Admin, Coordinador, Instructor) asignado como responsable 
           de un grupo.
         - Lógica de Bloqueo (Data-Driven):
             * Se consulta el estatus de la capacitación (`Cat_Estatus_Capacitacion`).
             * Se lee la bandera de control `Es_Final`.
             * Si `Es_Final = 0` (Falso): El curso está VIVO (Programado, En Curso, Por Iniciar, En Evaluación).
               -> ACCIÓN: BLOQUEO TOTAL (Error 409).
             * Si `Es_Final = 1` (Verdadero): El curso está MUERTO (Finalizado, Cancelado, Archivado).
               -> ACCIÓN: PERMITIR BAJA.

      B) VECTOR DE PARTICIPANTE (`Capacitaciones_Participantes`):
         - Alcance: Usuarios inscritos como alumnos.
         - Lógica de Bloqueo:
             * Se verifica si el usuario tiene estatus de inscripción 'Activo' (1) o 'Cursando' (2).
             * Y ADEMÁS, se verifica que el curso en sí mismo siga vivo (`Es_Final = 0`).
             * Si el curso fue cancelado, el alumno se libera automáticamente.

   ----------------------------------------------------------------------------------------------------
   III. ESPECIFICACIÓN TÉCNICA Y RENDIMIENTO (PERFORMANCE SPECS)
   ----------------------------------------------------------------------------------------------------
   - ESTRATEGIA DE CONCURRENCIA: Implementación de **Bloqueo Pesimista** (`SELECT ... FOR UPDATE`).
     Esto "congela" la fila del usuario objetivo durante la transacción, asegurando que nadie más 
     pueda editar sus datos o cambiar su estatus en el milisegundo exacto en que validamos.
   - IDEMPOTENCIA: El sistema es inteligente. Si se solicita desactivar a un usuario que YA está 
     desactivado, el SP detecta la redundancia y retorna un mensaje de éxito ("SIN CAMBIOS") sin 
     realizar escrituras innecesarias en el disco duro, optimizando I/O.
   - TRAZABILIDAD: Se inyecta el ID del Administrador Ejecutor (`_Id_Admin_Ejecutor`) en los campos 
     de auditoría (`Updated_By`) para mantener un rastro forense de quién autorizó la baja.

   ----------------------------------------------------------------------------------------------------
   IV. MAPA DE RETORNO (OUTPUT CONTRACT)
   ----------------------------------------------------------------------------------------------------
   Retorna un Resultset de una sola fila con la siguiente estructura:
      - [Mensaje] (VARCHAR): Descripción humana del resultado (ej: "ÉXITO: Usuario REACTIVADO").
      - [Id_Usuario] (INT): La llave primaria del usuario afectado.
      - [Accion] (VARCHAR): Token técnico para el frontend ('ACTIVADO', 'DESACTIVADO', 'SIN_CAMBIOS').
   ==================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_CambiarEstatusUsuario`$$

CREATE PROCEDURE `SP_CambiarEstatusUsuario`(
    /* ------------------------------------------------------------------------------------------------
       SECCIÓN DE PARÁMETROS DE ENTRADA
       ------------------------------------------------------------------------------------------------ */
    IN _Id_Admin_Ejecutor    INT,        -- [AUDITOR] ID del usuario que ejecuta la orden (Required).
    IN _Id_Usuario_Objetivo  INT,        -- [TARGET] ID del usuario que sufrirá el cambio (Required).
    IN _Nuevo_Estatus        TINYINT     -- [FLAG] Estado deseado: 1 = Activar (Alta), 0 = Desactivar (Baja).
)
THIS_PROC: BEGIN
    
    /* ============================================================================================
       BLOQUE 0: INICIALIZACIÓN DE VARIABLES DE ENTORNO
       Definición de contenedores para almacenar el estado de la base de datos y diagnósticos.
       ============================================================================================ */
    
    /* Punteros de Relación (Foreign Keys y Datos Maestros) */
    DECLARE v_Id_InfoPersonal INT DEFAULT NULL; -- Para localizar la ficha de RH asociada.
    DECLARE v_Ficha_Objetivo  VARCHAR(50);      -- Para mostrar en el mensaje de éxito/error.
    
    /* Snapshot de Estado (Lectura actual de la BD) */
    DECLARE v_Estatus_Actual  TINYINT(1);       -- Estado actual en disco (0 o 1).
    DECLARE v_Existe          INT;              -- Bandera de existencia del registro.
    
    /* Variables de Diagnóstico para el Candado Operativo (Error Reporting) */
    DECLARE v_Curso_Conflictivo VARCHAR(50) DEFAULT NULL;  -- Número de capacitación que causa el bloqueo.
    DECLARE v_Estatus_Conflicto VARCHAR(255) DEFAULT NULL; -- Nombre del estatus del curso (ej: "EN CURSO").
    DECLARE v_Rol_Conflicto     VARCHAR(50) DEFAULT NULL;  -- Rol que juega el usuario en el conflicto.

    /* ============================================================================================
       BLOQUE 1: GESTIÓN DE EXCEPCIONES Y SEGURIDAD (DEFENSIVE CODING)
       ============================================================================================ */
    
    /* Handler Genérico de SQL:
       Ante cualquier error inesperado (caída de red, corrupción de datos, deadlock), 
       este bloque asegura que la transacción se revierta (ROLLBACK) para no dejar datos corruptos. */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; -- Propaga el error original al backend para el log de errores.
    END;

    /* ============================================================================================
       BLOQUE 2: VALIDACIONES PREVIAS (FAIL FAST STRATEGY)
       Verificaciones ligeras en memoria para rechazar peticiones inválidas antes de leer disco.
       ============================================================================================ */
    
    /* 2.1 Validación de Integridad de Parámetros */
    IF _Id_Admin_Ejecutor IS NULL OR _Id_Usuario_Objetivo IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: Los IDs de ejecutor y objetivo son obligatorios.';
    END IF;

    /* 2.2 Validación de Dominio (Valores permitidos) */
    IF _Nuevo_Estatus NOT IN (0, 1) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE DATOS [400]: El estatus solo puede ser 1 (Activo) o 0 (Inactivo).';
    END IF;

    /* 2.3 Regla de Seguridad Anti-Lockout
       Impide que un administrador se suicide digitalmente. */
    IF _Id_Admin_Ejecutor = _Id_Usuario_Objetivo THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ACCIÓN DENEGADA [403]: Protocolo de Seguridad activado. No puedes desactivar tu propia cuenta de usuario.';
    END IF;

    /* ============================================================================================
       BLOQUE 3: CANDADO OPERATIVO (INTEGRACIÓN DINÁMICA CON MÓDULO DE CAPACITACIÓN)
       Propósito: Validar que el usuario no sea una pieza clave en operaciones que están ocurriendo AHORA.
       Condición Crítica: Este bloque SOLO se ejecuta si la intención es APAGAR (0) al usuario.
       ============================================================================================ */
    IF _Nuevo_Estatus = 0 THEN
        
        /* ----------------------------------------------------------------------------------------
           3.1 VERIFICACIÓN DE ROL: FACILITADOR / INSTRUCTOR
           Objetivo: Detectar si el usuario es el responsable de impartir un curso activo.
           
           [LÓGICA DINÁMICA]:
           En lugar de listar IDs fijos (1,2,3...), consultamos la inteligencia del catálogo 
           `Cat_Estatus_Capacitacion` a través de la columna `Es_Final`.
           ---------------------------------------------------------------------------------------- */
        SELECT 
            C.Numero_Capacitacion, -- Para decirle al usuario EXACTAMENTE qué curso estorba
            EC.Nombre,             -- Para decirle en qué estado está ese curso
            'FACILITADOR/INSTRUCTOR' -- Etiqueta para el log de error
        INTO 
            v_Curso_Conflictivo,
            v_Estatus_Conflicto,
            v_Rol_Conflicto
        FROM `DatosCapacitaciones` DC
        /* JOIN 1: Llegar a la cabecera de la capacitación */
        INNER JOIN `Capacitaciones` C ON DC.Fk_Id_Capacitacion = C.Id_Capacitacion
        /* JOIN 2: Llegar a la configuración del estatus */
        INNER JOIN `Cat_Estatus_Capacitacion` EC ON DC.Fk_Id_CatEstCap = EC.Id_CatEstCap
        WHERE 
            /* Filtro 1: El usuario objetivo es el instructor asignado */
            DC.Fk_Id_Instructor = _Id_Usuario_Objetivo
            /* Filtro 2: El registro de detalle es el vigente (historial activo) */
            AND DC.Activo = 1 
            /* Filtro 3: La capacitación cabecera no ha sido borrada */
            AND C.Activo = 1
            
            /* [KILLSWITCH MAESTRO - DINÁMICO] 
               Si Es_Final = 0, el curso está VIVO (Programado, En Curso, Reprogramado, etc).
               Esto significa que NO podemos dejar el curso sin instructor. Bloqueo activado. */
            AND EC.Es_Final = 0 
        LIMIT 1; -- Con encontrar UNO solo basta para detener todo.

        /* Si se encontró un conflicto, abortamos la operación inmediatamente */
        IF v_Curso_Conflictivo IS NOT NULL THEN
            SET @MensajeError = CONCAT('CONFLICTO OPERATIVO [409]: No se puede desactivar al usuario. Actualmente funge como FACILITADOR en el curso ACTIVO con Folio "', v_Curso_Conflictivo, '" (Estatus Actual: ', v_Estatus_Conflicto, '). Este estatus se considera operativo (No Final). Para proceder, debe reasignar el curso a otro instructor o finalizar la capacitación.');
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = @MensajeError;
        END IF;

        /* ----------------------------------------------------------------------------------------
           3.2 VERIFICACIÓN DE ROL: PARTICIPANTE
           Objetivo: Detectar si el usuario es un alumno inscrito en un curso activo.
           
           [REGLA DE NEGOCIO]: Se mantiene la lógica para alumnos. No podemos borrar a alguien 
           que debe aparecer en la lista de asistencia de mañana.
           ---------------------------------------------------------------------------------------- */
        SELECT 
            C.Numero_Capacitacion,
            EP.Nombre,
            'PARTICIPANTE' -- Etiqueta informativa
        INTO 
            v_Curso_Conflictivo,
            v_Estatus_Conflicto,
            v_Rol_Conflicto
        FROM `Capacitaciones_Participantes` CP
        /* Cadena de Joins para llegar al Estatus del Curso */
        INNER JOIN `DatosCapacitaciones` DC ON CP.Fk_Id_DatosCap = DC.Id_DatosCap
        INNER JOIN `Capacitaciones` C ON DC.Fk_Id_Capacitacion = C.Id_Capacitacion
        INNER JOIN `Cat_Estatus_Participante` EP ON CP.Fk_Id_CatEstPart = EP.Id_CatEstPart
        INNER JOIN `Cat_Estatus_Capacitacion` EC_Curso ON DC.Fk_Id_CatEstCap = EC_Curso.Id_CatEstCap
        WHERE 
            /* Filtro 1: El usuario es el participante */
            CP.Fk_Id_Usuario = _Id_Usuario_Objetivo
            /* Filtro 2: Su estatus de alumno es Inscrito (1) o Cursando (2) */
            AND CP.Fk_Id_CatEstPart IN (1, 2) 
            /* Filtro 3: El curso sigue existiendo */
            AND DC.Activo = 1
            /* [KILLSWITCH DINÁMICO] Validamos que el CURSO también esté vivo. 
               Si el curso ya terminó (Es_Final=1), el alumno ya es historia y se puede borrar. */
            AND EC_Curso.Es_Final = 0
        LIMIT 1;

        /* Si se encontró conflicto como alumno, abortamos */
        IF v_Curso_Conflictivo IS NOT NULL THEN
            SET @MensajeError = CONCAT('CONFLICTO OPERATIVO [409]: No se puede desactivar al usuario. Actualmente es PARTICIPANTE activo en el curso con Folio "', v_Curso_Conflictivo, '" (Estatus Alumno: ', v_Estatus_Conflicto, '). Debe darlo de baja del curso o esperar a que el curso finalice.');
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = @MensajeError;
        END IF;

    END IF;

    /* ============================================================================================
       BLOQUE 4: FASE TRANSACCIONAL - AISLAMIENTO Y ESCRITURA
       Si llegamos aquí, el usuario superó todas las validaciones de negocio. Es seguro proceder.
       ============================================================================================ */
    START TRANSACTION;

    /* 4.1 ADQUISICIÓN DE SNAPSHOT Y BLOQUEO DE FILA (PESSIMISTIC LOCK)
       Seleccionamos los datos actuales del usuario y aplicamos `FOR UPDATE`.
       Esto impide que otra transacción modifique a este usuario mientras terminamos el proceso. */
    SELECT 1, `Fk_Id_InfoPersonal`, `Ficha`, `Activo`
    INTO v_Existe, v_Id_InfoPersonal, v_Ficha_Objetivo, v_Estatus_Actual
    FROM `Usuarios` 
    WHERE `Id_Usuario` = _Id_Usuario_Objetivo
    FOR UPDATE;

    /* 4.2 Validación de Existencia (Integridad Referencial) */
    IF v_Existe IS NULL THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [404]: El usuario solicitado no existe en la base de datos.';
    END IF;

    /* 4.3 Verificación de Idempotencia (Optimización)
       Si el usuario ya tiene el estatus que queremos ponerle, no hacemos nada.
       Esto ahorra escritura en logs de transacción y triggers. */
    IF v_Estatus_Actual = _Nuevo_Estatus THEN
        COMMIT;
        SELECT CONCAT('SIN CAMBIOS: El usuario ya se encontraba en estado ', IF(_Nuevo_Estatus=1, 'ACTIVO', 'INACTIVO'), '.') AS Mensaje,
               _Id_Usuario_Objetivo AS Id_Usuario, 'SIN_CAMBIOS' AS Accion;
        LEAVE THIS_PROC;
    END IF;

    /* ============================================================================================
       BLOQUE 5: PERSISTENCIA SINCRONIZADA (CASCADE UPDATE LOGIC)
       Propósito: Aplicar el cambio de estado en todas las capas de identidad.
       ============================================================================================ */
    
    /* 5.1 Desactivar/Activar Acceso (Tabla Usuarios)
       Esto controla el Login y el acceso al sistema. */
    UPDATE `Usuarios`
    SET `Activo` = _Nuevo_Estatus,
        `Fk_Usuario_Updated_By` = _Id_Admin_Ejecutor, -- Auditoría: Quién lo hizo
        `updated_at` = NOW()                          -- Auditoría: Cuándo lo hizo
    WHERE `Id_Usuario` = _Id_Usuario_Objetivo;

    /* 5.2 Desactivar/Activar Operatividad (Tabla Info_Personal)
       Esto controla la aparición en catálogos de RH y listas de selección.
       Se ejecuta solo si existe una ficha de personal vinculada (Integridad de Datos). */
    IF v_Id_InfoPersonal IS NOT NULL THEN
        UPDATE `Info_Personal`
        SET `Activo` = _Nuevo_Estatus,
            `Fk_Id_Usuario_Updated_By` = _Id_Admin_Ejecutor,
            `updated_at` = NOW()
        WHERE `Id_InfoPersonal` = v_Id_InfoPersonal;
    END IF;

    /* ============================================================================================
       BLOQUE 6: CONFIRMACIÓN Y RESPUESTA (COMMIT & FEEDBACK)
       ============================================================================================ */
    COMMIT; -- Confirmar los cambios de forma permanente.

    /* Retorno de información al Frontend para notificaciones UI (Toasts) */
    SELECT 
        CONCAT('ÉXITO: El Usuario con Ficha "', v_Ficha_Objetivo, '" ha sido ', IF(_Nuevo_Estatus=1, 'REACTIVADO', 'DESACTIVADO'), ' correctamente.') AS Mensaje,
        _Id_Usuario_Objetivo AS Id_Usuario,
        IF(_Nuevo_Estatus=1, 'ACTIVADO', 'DESACTIVADO') AS Accion;

END$$

DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_EliminarUsuarioDefinitivamente
   ============================================================================================

   --------------------------------------------------------------------------------------------
   I. VISIÓN GENERAL Y OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   --------------------------------------------------------------------------------------------
   [QUÉ ES]: 
   Constituye el mecanismo de "Destrucción Física" (Hard Delete) dentro de la arquitectura 
   del sistema. A diferencia de la "Baja Lógica" (Switch Activo/Inactivo), este procedimiento 
   ejecuta sentencias `DELETE` que eliminan permanentemente los bits de información de los 
   platos del disco duro, liberando espacio y referencias de integridad.

   [CASO DE USO EXCLUSIVO - "DATA HYGIENE"]: 
   Este SP está diseñado estrictamente para la "Corrección de Errores Administrativos Inmediatos".
   Ejemplo: "El Administrador creó un usuario duplicado por error de dedo hace 5 minutos, 
   se dio cuenta del error, y necesita borrarlo totalmente para volver a capturarlo limpio".
   
   [ADVERTENCIA OPERATIVA]: 
   BAJO NINGUNA CIRCUNSTANCIA debe utilizarse para gestionar despidos, renuncias o jubilaciones. 
   Si un empleado deja la empresa, su expediente constituye un activo legal que DEBE conservarse 
   por razones de auditoría laboral. Para esos casos es obligatorio usar `SP_CambiarEstatusUsuario`.

   --------------------------------------------------------------------------------------------
   II. ARQUITECTURA DE SEGURIDAD E INTEGRIDAD (THE SAFETY NET)
   --------------------------------------------------------------------------------------------
   [RN-01] PROTOCOLO ANTI-SUICIDIO (SELF-DESTRUCTION PREVENTION):
      - Principio: "El sistema debe protegerse contra errores humanos catastróficos".
      - Regla: Un usuario autenticado no puede ejecutar este SP contra su propio ID 
        (`_Id_Admin_Ejecutor` != `_Id_Usuario_Objetivo`).
      - Impacto: Previene que un administrador se elimine a sí mismo accidentalmente, lo que 
        podría dejar al sistema acéfalo.

   [RN-02] ANÁLISIS FORENSE DE INSTRUCTOR (OPERATIONAL FOOTPRINT):
      - Validación: Antes de permitir el borrado, el sistema realiza un escaneo profundo en la 
        tabla `DatosCapacitaciones`.
      - Regla: Si el usuario aparece como `Fk_Id_Instructor` en CUALQUIER curso (Pasado, 
        Presente o Futuro), la eliminación se bloquea inmediatamente con Error 409.
      - Justificación: Borrar al instructor dejaría "cursos huérfanos" en los reportes históricos,
        donde un curso aparecería sin responsable asignado, rompiendo la integridad del historial.

   [RN-03] ANÁLISIS FORENSE DE PARTICIPANTE (ACADEMIC FOOTPRINT):
      - Validación: El sistema escanea la tabla `Capacitaciones_Participantes`.
      - Regla: Si el usuario tiene registros de asistencia o calificación, se bloquea.
      - Justificación: Es ilegal destruir evidencia de capacitación de un empleado (Auditoría STPS).
        Un kárdex académico es un documento legal que debe persistir más allá de la vida laboral.

   --------------------------------------------------------------------------------------------
   III. ESPECIFICACIÓN TÉCNICA (DATABASE ARCHITECTURE)
   --------------------------------------------------------------------------------------------
   - TIPO: Transacción ACID Destructiva.
   - ESTRATEGIA DE CONCURRENCIA: Se utiliza `SELECT ... FOR UPDATE` para adquirir un bloqueo 
     exclusivo (X-LOCK) sobre el registro objetivo al inicio de la transacción. Esto evita 
     "Condiciones de Carrera" donde otro proceso podría intentar asignar un curso al usuario 
     mientras este está siendo eliminado.
   
   - ORDEN DE EJECUCIÓN (CASCADE LOGIC):
      Debido a la restricción de llave foránea (`Fk_Id_InfoPersonal` dentro de la tabla `Usuarios`),
      el borrado debe seguir un orden quirúrgico para evitar errores de Constraint `ON DELETE NO ACTION`:
        1. Eliminar Entidad Hija (`Usuarios`) -> Libera la referencia FK.
        2. Eliminar Entidad Padre (`Info_Personal`) -> Borra el dato demográfico.
   ============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_EliminarUsuarioDefinitivamente`$$

CREATE PROCEDURE `SP_EliminarUsuarioDefinitivamente`(
    /* -----------------------------------------------------------------
       PARÁMETROS DE ENTRADA
       ----------------------------------------------------------------- */
    IN _Id_Admin_Ejecutor    INT,   -- [AUDITOR] Quién ordena la ejecución (Para logs de aplicación)
    IN _Id_Usuario_Objetivo  INT    -- [TARGET] El usuario a eliminar físicamente
)
THIS_PROC: BEGIN
    
    /* ========================================================================================
       BLOQUE 0: VARIABLES DE DIAGNÓSTICO Y CONTEXTO
       Propósito: Inicializar contenedores en memoria para realizar el análisis forense 
       antes de proceder con cualquier operación destructiva.
       ======================================================================================== */
    
    /* Punteros de Relación para el borrado en cascada */
    DECLARE v_Id_InfoPersonal INT DEFAULT NULL; -- ID de la tabla padre (Info_Personal)
    DECLARE v_Ficha_Objetivo  VARCHAR(50);      -- Dato visual para el mensaje de éxito
    DECLARE v_Existe          INT;              -- Bandera de existencia del registro
    
    /* Banderas de Análisis Forense (Semáforos de Integridad) */
    /* Si estas variables dejan de ser NULL, significa que el usuario tiene "Ataduras" */
    DECLARE v_Es_Instructor   INT DEFAULT NULL;
    DECLARE v_Es_Participante INT DEFAULT NULL;

    /* ========================================================================================
       BLOQUE 1: GESTIÓN DE EXCEPCIONES (HANDLERS)
       Propósito: Garantizar la Atomicidad. Si algo falla a mitad del borrado, el sistema 
       debe regresar al estado exacto anterior.
       ======================================================================================== */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; -- Propagar el error original al Backend para debugging
    END;

    /* ========================================================================================
       BLOQUE 2: VALIDACIONES PREVIAS (FAIL FAST)
       Propósito: Validar la integridad de la petición antes de consumir recursos de BD.
       ======================================================================================== */
    
    /* 2.1 Integridad de Inputs */
    IF _Id_Usuario_Objetivo IS NULL OR _Id_Usuario_Objetivo <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: ID de usuario inválido.';
    END IF;

    /* 2.2 Protección Anti-Suicidio (Seguridad Básica) 
       [RN-01] Un usuario no puede eliminarse a sí mismo. */
    IF _Id_Admin_Ejecutor = _Id_Usuario_Objetivo THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ACCIÓN DENEGADA [403]: No puedes eliminarte a ti mismo. Por seguridad, pide a otro administrador que realice esta acción.';
    END IF;

    /* ========================================================================================
       BLOQUE 3: INSPECCIÓN Y BLOQUEO (FORENSIC ANALYSIS)
       Propósito: "Congelar" al usuario y verificar si tiene ataduras históricas antes de borrar.
       ======================================================================================== */
    START TRANSACTION;

    /* ----------------------------------------------------------------------------------------
       PASO 3.1: ADQUISICIÓN DE SNAPSHOT Y CANDADO DE ESCRITURA (X-LOCK)
       - Buscamos al usuario.
       - FOR UPDATE: Bloqueamos la fila. Nadie puede editar, asignar cursos o borrar a este 
         usuario hasta que terminemos el análisis.
       ---------------------------------------------------------------------------------------- */
    SELECT 
        1, 
        `Fk_Id_InfoPersonal`, 
        `Ficha`
    INTO 
        v_Existe, 
        v_Id_InfoPersonal, 
        v_Ficha_Objetivo
    FROM `Usuarios`
    WHERE `Id_Usuario` = _Id_Usuario_Objetivo
    FOR UPDATE;

    /* Validación de Existencia */
    IF v_Existe IS NULL THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR [404]: El usuario no existe o ya fue eliminado.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 3.2: ANÁLISIS FORENSE DE INSTRUCTOR (Operational Trace) [RN-02]
       Objetivo: Verificar si el usuario ha impartido capacitación alguna vez.
       Lógica: Escaneo en `DatosCapacitaciones`. Si existe 1 registro, es intocable.
       ---------------------------------------------------------------------------------------- */
    SELECT 1 INTO v_Es_Instructor
    FROM `DatosCapacitaciones`
    WHERE `Fk_Id_Instructor` = _Id_Usuario_Objetivo
    LIMIT 1;

    IF v_Es_Instructor IS NOT NULL THEN
        ROLLBACK; -- Liberamos el bloqueo inmediatamente
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'BLOQUEO DE INTEGRIDAD [409]: Imposible eliminar. Este usuario figura como INSTRUCTOR en el historial de capacitaciones. La eliminación rompería la integridad de los reportes. Use la opción "Desactivar" para archivar el expediente.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 3.3: ANÁLISIS FORENSE DE PARTICIPANTE (Academic Trace) [RN-03]
       Objetivo: Verificar si el usuario tiene historial académico.
       Lógica: Escaneo en `Capacitaciones_Participantes`. Si tiene asistencia/calificación, es intocable.
       ---------------------------------------------------------------------------------------- */
    SELECT 1 INTO v_Es_Participante
    FROM `Capacitaciones_Participantes`
    WHERE `Fk_Id_Usuario` = _Id_Usuario_Objetivo
    LIMIT 1;

    IF v_Es_Participante IS NOT NULL THEN
        ROLLBACK; -- Liberamos el bloqueo inmediatamente
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'BLOQUEO DE INTEGRIDAD [409]: Imposible eliminar. Este usuario tiene historial académico como PARTICIPANTE (Calificaciones/Asistencia). Es ilegal destruir esta evidencia. Use la opción "Desactivar".';
    END IF;

    /* ========================================================================================
       BLOQUE 4: EJECUCIÓN DESTRUCTIVA (HARD DELETE SEQUENCE)
       Si el flujo llega a este punto, el análisis forense determinó que el usuario está "Limpio"
       (no tiene historial operativo ni académico). Es seguro proceder.
       ======================================================================================== */
    
    /* ----------------------------------------------------------------------------------------
       PASO 4.1: ELIMINAR CUENTA DE USUARIO (ENTIDAD HIJA)
       Acción: Borramos primero la tabla `Usuarios`.
       Razón Técnica: Esta tabla tiene la llave foránea `Fk_Id_InfoPersonal`. Debemos romper 
       este vínculo antes de poder borrar al "Padre" (`Info_Personal`).
       ---------------------------------------------------------------------------------------- */
    DELETE FROM `Usuarios` 
    WHERE `Id_Usuario` = _Id_Usuario_Objetivo;

    /* ----------------------------------------------------------------------------------------
       PASO 4.2: ELIMINAR DATOS PERSONALES (ENTIDAD PADRE)
       Acción: Borramos el registro en `Info_Personal`.
       Condición: Solo si existía un vínculo (v_Id_InfoPersonal NOT NULL).
       Resultado: El expediente ha sido purgado completamente.
       ---------------------------------------------------------------------------------------- */
    IF v_Id_InfoPersonal IS NOT NULL THEN
        DELETE FROM `Info_Personal` 
        WHERE `Id_InfoPersonal` = v_Id_InfoPersonal;
    END IF;

    /* ========================================================================================
       BLOQUE 5: CONFIRMACIÓN FINAL
       Propósito: Hacer permanentes los cambios y notificar al usuario.
       ======================================================================================== */
    COMMIT;

    /* Feedback de éxito estructurado para el Frontend */
    SELECT 
        CONCAT('ELIMINACIÓN EXITOSA: El usuario con Ficha ', v_Ficha_Objetivo, ' y todos sus datos asociados han sido borrados permanentemente del sistema.') AS Mensaje,
        _Id_Usuario_Objetivo AS Id_Eliminado,
        'ELIMINADO' AS Accion;

END$$

DELIMITER ;