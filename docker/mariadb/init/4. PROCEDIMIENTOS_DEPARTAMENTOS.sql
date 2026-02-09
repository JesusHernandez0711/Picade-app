USE `PICADE`;

/* ------------------------------------------------------------------------------------------------------ */
/* CREACION DE VISTAS Y PROCEDIMIENTOS DE ALMACENADO PARA LA BASE DE DATOS*/
/* ------------------------------------------------------------------------------------------------------ */

/* ======================================================================================================
   1. VIEW: Vista_Departamentos
   ======================================================================================================
   OBJETIVO GENERAL
   ----------------
   Consolidar la información operativa de los Departamentos con su información geográfica,
   siguiendo el patrón de arquitectura modular establecido en el sistema.

   ARQUITECTURA MODULAR (DRY - Don't Repeat Yourself)
   --------------------------------------------------
   En lugar de realizar múltiples JOINs hacia las tablas de Municipio, Estado y País, 
   esta vista consume directamente `Vista_Direcciones`.
   
   Ventajas:
   1. Consistencia: La forma de mostrar una ubicación es idéntica en Centros de Trabajo y Departamentos.
   2. Mantenibilidad: Si cambia la estructura geográfica, solo se ajusta `Vista_Direcciones`.

   DECISIÓN CRÍTICA DE SEGURIDAD (LEFT JOIN)
   -----------------------------------------
   Se utiliza **LEFT JOIN** para relacionar `Cat_Departamentos` con `Vista_Direcciones`.
   
   Justificación Técnica:
   - Integridad de Visualización: Es posible que existan Departamentos históricos o migrados
     con `Fk_Id_Municipio_CatDep` nulo o inválido.
   - Si usáramos INNER JOIN, esos departamentos "huérfanos de ubicación" desaparecerían de los reportes
     y grids de administración, volviéndose invisibles e incorregibles.
   - Con LEFT JOIN, aseguramos que el Administrador vea TODOS los departamentos. Los que tengan
     problemas de ubicación mostrarán campos geográficos en NULL, facilitando su detección y corrección.

   DICCIONARIO DE DATOS (CAMPOS DEVUELTOS)
   ---------------------------------------
   [Entidad Principal: Departamento]
   - Id_Departamento:       ID único (PK) para operaciones CRUD.
   - Codigo_Departamento:   Clave interna (ej: 'DEP-RH-01').
   - Nombre_Departamento:   Nombre oficial del departamento.
   - Estatus_Departamento:  1 = Operativo, 0 = Baja Lógica.

   [Datos Geográficos - Heredados de Vista_Direcciones]
   - Codigo_Municipio, Nombre_Municipio
   - Codigo_Estado, Nombre_Estado
   - Codigo_Pais, Nombre_Pais
   ====================================================================================================== */

-- DROP VIEW IF EXISTS `PICADE`.`Vista_Departamentos`;

CREATE OR REPLACE
    ALGORITHM = UNDEFINED 
    DEFINER = `root`@`localhost` 
    SQL SECURITY DEFINER
VIEW `PICADE`.`Vista_Departamentos` AS
    SELECT 
        /* --- Datos Propios del Departamento --- */
        `Dep`.`Id_CatDep`            AS `Id_Departamento`,
        `Dep`.`Codigo`               AS `Codigo_Departamento`,
        `Dep`.`Nombre`               AS `Nombre_Departamento`, /* Corregido: Antes decía Codigo_Dep */
        `Dep`.`Direccion_Fisica`     AS `Descripcion_Direccion_Dep`,
                
        /* --- Datos Geográficos Reutilizados (Modularidad) --- */
        `Ubi`.`Codigo_Municipio`     AS `Codigo_Municipio`,
        -- `Ubi`.`Nombre_Municipio`     AS `Nombre_Municipio`,
        `Ubi`.`Codigo_Estado`        AS `Codigo_Estado`,
        -- `Ubi`.`Nombre_Estado`        AS `Nombre_Estado`,
        `Ubi`.`Codigo_Pais`          AS `Codigo_Pais`,
        -- `Ubi`.`Nombre_Pais`          AS `Nombre_Pais`,
		`Dep`.`Activo`               AS `Estatus_Departamento`
    FROM
        `PICADE`.`Cat_Departamentos` `Dep`
        /* LEFT JOIN Estratégico: Previene la desaparición de registros con ubicación corrupta */
        LEFT JOIN `PICADE`.`Vista_Direcciones` `Ubi` 
            ON `Dep`.`Fk_Id_Municipio_CatDep` = `Ubi`.`Id_Municipio`;

/* ============================================================================================
   PROCEDIMIENTO: SP_RegistrarDepartamento
   ============================================================================================
   OBJETIVO
   --------
   Registrar un nuevo Departamento en el catálogo corporativo, garantizando la integridad
   referencial con su ubicación geográfica y aplicando reglas de unicidad flexibles.

   ESTRATEGIA DE IDENTIDAD (LA "TRIPLE RESTRICCIÓN")
   -------------------------------------------------
   A diferencia de los Centros de Trabajo (donde el Código es único globalmente), los 
   Departamentos siguen una lógica de identidad compuesta.
   
   La identidad única se define por la combinación exacta de tres factores:
      1. CÓDIGO (Ej: 'DEP-RH')
      2. NOMBRE (Ej: 'Recursos Humanos')
      3. MUNICIPIO (Ej: ID 45 - Villahermosa)

   ¿Por qué?
   - Esto permite que exista el departamento 'DEP-RH' en Villahermosa y TAMBIÉN el
     'DEP-RH' en Paraíso. Son entidades distintas operativamente.
   - Sin embargo, bloquea que existan DOS 'DEP-RH' en Villahermosa (Duplicado real).

   REGLAS DE NEGOCIO (EL CONTRATO)
   -------------------------------
   1. INTEGRIDAD DEL PADRE (MUNICIPIO):
      - El Departamento DEBE anclarse a un Municipio existente y ACTIVO.
      - Se aplica un BLOQUEO DE LECTURA (FOR UPDATE) al registro del Municipio durante la
        transacción para evitar que sea desactivado por otro administrador mientras
        estamos registrando hijos en él.

   2. AUTO-SANACIÓN DE DATOS (SELF-HEALING):
      - Si el sistema detecta que el departamento YA EXISTÍA pero estaba eliminado lógicamente
        (Estatus = 0), no solo lo reactiva.
      - También verifica si el usuario envió una nueva `Direccion_Fisica`. Si es así,
        ACTUALIZA ese dato al reactivar el registro.
      - Esto mantiene la base de datos fresca sin obligar al usuario a ir a "Editar" después.

   3. MANEJO DE CONCURRENCIA (RACE CONDITIONS - ERROR 1062):
      - Escenario: Dos usuarios (A y B) envían el registro del mismo departamento al mismo tiempo.
      - Ambos pasan la validación de "No existe". Ambos intentan el INSERT.
      - Uno gana. El otro recibe un error nativo de MySQL (1062 Duplicate Entry).
      - SOLUCIÓN: Usamos un HANDLER para atrapar ese error, hacer ROLLBACK silencioso,
        buscar el registro que acaba de crear el "ganador" y devolverlo como éxito.
      - Resultado: Cero errores técnicos en pantalla para el usuario final.

   RETORNO
   -------
   Devuelve una tabla con:
      - Mensaje: Texto amigable para notificación UI.
      - Id_Departamento: La llave primaria (Nueva o Reutilizada).
      - Accion: 'CREADA', 'REACTIVADA', 'REUSADA'.
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_RegistrarDepartamento`$$

CREATE PROCEDURE `SP_RegistrarDepartamento`(
    IN _Codigo           VARCHAR(50),
    IN _Nombre           VARCHAR(255),
    IN _Direccion_Fisica VARCHAR(255),
    IN _Id_Municipio     INT
)
SP: BEGIN
    /* ----------------------------------------------------------------------------------------
       VARIABLES DE ESTADO Y CONTROL
       ---------------------------------------------------------------------------------------- */
    /* Para almacenar datos del registro encontrado (si existe) */
    DECLARE v_Id_Dep     INT DEFAULT NULL;
    DECLARE v_Activo     TINYINT(1) DEFAULT NULL;
    
    /* Para validación del Padre (Municipio) */
    DECLARE v_Mun_Existe INT DEFAULT NULL;
    DECLARE v_Mun_Activo TINYINT(1) DEFAULT NULL;

    /* Bandera para control de flujo en Concurrencia */
    DECLARE v_Dup        TINYINT(1) DEFAULT 0;

    /* ----------------------------------------------------------------------------------------
       HANDLERS (MANEJO DE EXCEPCIONES)
       ---------------------------------------------------------------------------------------- */
    
    /* HANDLER 1062: Duplicate Entry
       Este es el corazón de la tolerancia a concurrencia. Si el INSERT falla por duplicado,
       el código NO se detiene; se activa la bandera v_Dup = 1 y continuamos. */
    DECLARE CONTINUE HANDLER FOR 1062
    BEGIN
        SET v_Dup = 1;
    END;

    /* HANDLER SQLEXCEPTION: Fallos Generales
       Cualquier otro error (disco lleno, desconexión, sintaxis) aborta la transacción. */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    /* ----------------------------------------------------------------------------------------
       NORMALIZACIÓN Y LIMPIEZA DE INPUTS
       ---------------------------------------------------------------------------------------- */
    SET _Codigo           = NULLIF(TRIM(_Codigo), '');
    SET _Nombre           = NULLIF(TRIM(_Nombre), '');
    SET _Direccion_Fisica = NULLIF(TRIM(_Direccion_Fisica), '');
    
    /* Protección contra IDs inválidos (0 o negativos se tratan como NULL) */
    IF _Id_Municipio <= 0 THEN SET _Id_Municipio = NULL; END IF;

    /* ----------------------------------------------------------------------------------------
       VALIDACIONES DE ENTRADA (FAIL FAST)
       ---------------------------------------------------------------------------------------- */
    IF _Codigo IS NULL OR _Nombre IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN: El Código y el Nombre son obligatorios.';
    END IF;

    IF _Id_Municipio IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN: Debe seleccionar un Municipio válido.';
    END IF;

    /* ========================================================================================
       INICIO DE LA TRANSACCIÓN
       ======================================================================================== */
    START TRANSACTION;

    /* ----------------------------------------------------------------------------------------
       PASO 1) VALIDAR INTEGRIDAD DEL PADRE (MUNICIPIO)
       ----------------------------------------------------------------------------------------
       Usamos `FOR UPDATE` para bloquear la fila del Municipio.
       Esto previene la condición de carrera donde un Admin A registra un departamento mientras
       un Admin B desactiva el municipio al mismo tiempo. */
    
    SELECT 1, `Activo` 
      INTO v_Mun_Existe, v_Mun_Activo
    FROM `Municipio`
    WHERE `Id_Municipio` = _Id_Municipio
    LIMIT 1
    FOR UPDATE;

    IF v_Mun_Existe IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE INTEGRIDAD: El Municipio seleccionado no existe en el catálogo.';
    END IF;

    IF v_Mun_Activo = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO: El Municipio seleccionado está INACTIVO. No es posible registrar nuevos Departamentos en él.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 2) VERIFICACIÓN DE EXISTENCIA (LA TRIPLE RESTRICCIÓN)
       ----------------------------------------------------------------------------------------
       Buscamos una coincidencia EXACTA de la triada: [Código + Nombre + Municipio].
       También usamos `FOR UPDATE` para serializar el acceso a este registro si ya existe. */
    
    SET v_Id_Dep = NULL;
    
    SELECT `Id_CatDep`, `Activo` 
      INTO v_Id_Dep, v_Activo
    FROM `Cat_Departamentos`
    WHERE `Codigo` = _Codigo 
      AND `Nombre` = _Nombre 
      AND `Fk_Id_Municipio_CatDep` = _Id_Municipio
    LIMIT 1 
    FOR UPDATE;

    /* SI EL REGISTRO YA EXISTE... */
    IF v_Id_Dep IS NOT NULL THEN
        
        /* CASO 2.1: Existe pero estaba eliminado lógicamente (Activo = 0) -> REACTIVAR */
        IF v_Activo = 0 THEN
            UPDATE `Cat_Departamentos` 
            SET `Activo` = 1, 
                /* Lógica de Autosanación:
                   Si el usuario envió una dirección física nueva, actualizamos el dato viejo.
                   Si envió NULL, mantenemos la dirección antigua. */
                `Direccion_Fisica` = COALESCE(_Direccion_Fisica, `Direccion_Fisica`), 
                `updated_at` = NOW() 
            WHERE `Id_CatDep` = v_Id_Dep;
            
            COMMIT; 
            SELECT 'Departamento reactivado exitosamente.' AS Mensaje, 
                   v_Id_Dep AS Id_Departamento, 
                   'REACTIVADA' AS Accion; 
            LEAVE SP;
        
        ELSE
            /* CASO 2.2: Existe y ya estaba activo -> IDEMPOTENCIA (No hacemos nada, reportamos éxito) */
            COMMIT; 
            SELECT 'El Departamento ya existe con esos datos en este Municipio.' AS Mensaje, 
                   v_Id_Dep AS Id_Departamento, 
                   'REUSADA' AS Accion; 
            LEAVE SP;
        END IF;
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 3) INSERTAR (CREACIÓN DE NUEVO REGISTRO)
       ----------------------------------------------------------------------------------------
       Si llegamos aquí, no encontramos coincidencias. Procedemos a insertar.
       Aquí podría saltar el Error 1062 si alguien insertó milisegundos antes. */
    
    SET v_Dup = 0; /* Reset de bandera */
    
    INSERT INTO `Cat_Departamentos` 
        (`Codigo`, `Nombre`, `Direccion_Fisica`, `Fk_Id_Municipio_CatDep`)
    VALUES 
        (_Codigo, _Nombre, _Direccion_Fisica, _Id_Municipio);

    /* Verificamos si la bandera v_Dup sigue en 0 (Éxito) */
    IF v_Dup = 0 THEN
        COMMIT; 
        SELECT 'Departamento registrado exitosamente.' AS Mensaje, 
               LAST_INSERT_ID() AS Id_Departamento, 
               'CREADA' AS Accion; 
        LEAVE SP;
    END IF;

    /* ========================================================================================
       PASO 4) RE-RESOLVE (MANEJO AVANZADO DE CONCURRENCIA)
       ========================================================================================
       Si llegamos aquí, v_Dup = 1. Significa que el INSERT falló por duplicado (1062).
       Otro usuario ganó la carrera. Debemos recuperar ese ID y devolverlo limpiamente. */
    
    ROLLBACK; /* Revertimos nuestra transacción fallida para limpiar bloqueos */
    
    START TRANSACTION; /* Iniciamos una nueva para buscar al ganador */
    
    SET v_Id_Dep = NULL;
    
    /* Buscamos de nuevo (ahora sí debe aparecer) */
    SELECT `Id_CatDep`, `Activo` 
      INTO v_Id_Dep, v_Activo
    FROM `Cat_Departamentos` 
    WHERE `Codigo` = _Codigo 
      AND `Nombre` = _Nombre 
      AND `Fk_Id_Municipio_CatDep` = _Id_Municipio
    LIMIT 1 
    FOR UPDATE;

    IF v_Id_Dep IS NOT NULL THEN
        /* Si el ganador estaba inactivo, lo reactivamos nosotros */
        IF v_Activo = 0 THEN
            UPDATE `Cat_Departamentos` SET `Activo` = 1, `updated_at` = NOW() WHERE `Id_CatDep` = v_Id_Dep;
            COMMIT; 
            SELECT 'Departamento reactivado (recuperado tras concurrencia).' AS Mensaje, 
                   v_Id_Dep AS Id_Departamento, 
                   'REACTIVADA' AS Accion; 
            LEAVE SP;
        END IF;

        /* Si estaba activo, simplemente lo reusamos */
        COMMIT; 
        SELECT 'Departamento ya existía (reusado tras concurrencia).' AS Mensaje, 
               v_Id_Dep AS Id_Departamento, 
               'REUSADA' AS Accion; 
        LEAVE SP;
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO FINAL: EXCEPCIÓN DE SISTEMA
       Si falló el insert por duplicado (1062) PERO luego no encontramos el registro,
       estamos ante un error de corrupción de índices o comportamiento anómalo grave. */
    SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERROR CRÍTICO DE SISTEMA: Fallo de concurrencia no recuperable (Error Fantasma). Contacte a Soporte.';

END$$

DELIMITER ;

/* ============================================================================================
   SECCIÓN: CONSULTAS ESPECÍFICAS (PARA EDICIÓN / DETALLE)
   ============================================================================================
   Estas rutinas son clave para la UX. No solo devuelven el dato pedido, sino todo el 
   contexto jerárquico necesario para que el formulario de edición se autocomplete.
   ============================================================================================ */
   
/* ============================================================================================
   PROCEDIMIENTO: SP_ConsultarDepartamentoEspecifico
   ============================================================================================
   OBJETIVO DE NEGOCIO
   -------------------
   Recuperar la "Hoja de Vida" completa de un Departamento para dos casos de uso principales:
   1. Visualización de Detalle (Modal o Pantalla de Información).
   2. Precarga del Formulario de Edición (Update).

   EL RETO TÉCNICO (RECONSTRUCCIÓN JERÁRQUICA INVERSA)
   ---------------------------------------------------
   En la base de datos, el Departamento es una entidad "hoja" que solo conoce a su padre inmediato:
   el Municipio (`Fk_Id_Municipio_CatDep`).
   
   Sin embargo, en la pantalla de edición, la interfaz de usuario (UI) presenta tres selectores 
   dependientes (Dropdowns en Cascada):
      [ Seleccione País ]  ->  [ Seleccione Estado ]  ->  [ Seleccione Municipio ]
   
   Si el Backend solo devolviera el `Id_Municipio`, el Frontend no sabría qué País ni qué Estado 
   seleccionar automáticamente en los dos primeros niveles.
   
   SOLUCIÓN:
   Este SP reconstruye la cadena genealógica hacia atrás (Hijo -> Padre -> Abuelo -> Bisabuelo)
   para entregar todos los IDs necesarios en una sola consulta eficiente.

   ESTRATEGIA DE INTEGRIDAD (POR QUÉ USAR LEFT JOIN)
   -------------------------------------------------
   Se ha decidido utilizar `LEFT JOIN` para enlazar la cadena geográfica (Municipio -> Estado -> País).
   
   ¿Por qué no INNER JOIN?
   - Robustez ante Datos Corruptos: En sistemas legados o tras migraciones masivas, es posible
     que un Departamento tenga un ID de Municipio que ya no existe (huérfano) o sea NULL.
   - Si usáramos INNER JOIN, ese registro desaparecería de la consulta, haciendo imposible abrir
     su formulario de edición para CORREGIRLO.
   - Con LEFT JOIN, recuperamos los datos del Departamento incluso si su ubicación está rota.
     Los campos geográficos vendrán en NULL, alertando visualmente que se requiere reparación.

   DICCIONARIO DE DATOS (OUTPUT)
   -----------------------------
   A) Datos de Identidad:
      - Id_Departamento, Codigo, Nombre, Dirección Física, Estatus.
   
   B) Datos de Contexto Geográfico (IDs):
      - Id_Pais, Id_Estado, Id_Municipio (Vitales para `value=""` en los <select>).
   
   C) Datos Visuales (Labels):
      - Nombre_Pais, Nombre_Estado, Nombre_Municipio (Para contexto humano).

   VALIDACIONES PREVIAS
   --------------------
   - Validación defensiva de parámetros (Id Nulo o <= 0).
   - Verificación de existencia rápida (Fail Fast) antes de ejecutar los Joins.
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ConsultarDepartamentoEspecifico`$$

CREATE PROCEDURE `SP_ConsultarDepartamentoEspecifico`(
    IN _Id_CatDep INT
)
BEGIN
    /* ----------------------------------------------------------------------------------------
       1. VALIDACIÓN DE ENTRADA (DEFENSIVE PROGRAMMING)
       Evitamos desperdiciar ciclos de CPU si el parámetro es basura.
       ---------------------------------------------------------------------------------------- */
    IF _Id_CatDep IS NULL OR _Id_CatDep <= 0 THEN
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'ERROR DE SISTEMA: El ID del Departamento es inválido.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       2. VALIDACIÓN DE EXISTENCIA (FAIL FAST)
       Verificamos rápido contra el índice primario si el registro existe.
       Si no existe, abortamos antes de hacer los JOINs costosos.
       ---------------------------------------------------------------------------------------- */
    IF NOT EXISTS (SELECT 1 FROM `Cat_Departamentos` WHERE `Id_CatDep` = _Id_CatDep) THEN
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'ERROR DE NEGOCIO: El Departamento solicitado no existe o fue eliminado.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       3. CONSULTA PRINCIPAL (RECONSTRUCCIÓN JERÁRQUICA)
       ---------------------------------------------------------------------------------------- */
    SELECT 
        /* --- BLOQUE A: DATOS PROPIOS DEL DEPARTAMENTO --- */
        `Dep`.`Id_CatDep`            AS `Id_Departamento`,
        `Dep`.`Codigo`               AS `Codigo_Departamento`,
        `Dep`.`Nombre`               AS `Nombre_Departamento`,
        `Dep`.`Direccion_Fisica`     AS `Descripcion_Direccion_Dep`,

        /* --- BLOQUE B: JERARQUÍA GEOGRÁFICA (IDs para Lógica de UI) --- */
        /* Estos campos son los que el Frontend bindeará a los ng-model o v-model de los Selects */
        `Mun`.`Id_Municipio`,
        /* --- BLOQUE C: JERARQUÍA GEOGRÁFICA (Nombres para Visualización) --- */
        /* Contexto visual para el usuario ("Ah, este es el de Villahermosa, Tabasco") */
        `Mun`.`Codigo`               AS `Codigo_Municipio`,
        `Mun`.`Nombre`               AS `Nombre_Municipio`,
        --  `Mun`.`Activo`               AS `Estatus_Municipio`,

        `Edo`.`Id_Estado`,
        `Edo`.`Codigo`               AS `Codigo_Estado`,
        `Edo`.`Nombre`               AS `Nombre_Estado`,
        
        `Pais`.`Id_Pais`,        
        `Pais`.`Codigo`              AS `Codigo_Pais`,
        `Pais`.`Nombre`              AS `Nombre_Pais`,
        
        `Dep`.`Activo`               AS `Estatus_Departamento`,
        `Dep`.`created_at`,
        `Dep`.`updated_at`
        
    FROM `Cat_Departamentos` `Dep`
    
    /* LEFT JOIN 1: Intentamos obtener el Municipio (Padre directo) */
    /* Si falla, Mun.* será NULL, pero tendremos los datos de Dep */
    LEFT JOIN `Municipio` `Mun` 
        ON `Dep`.`Fk_Id_Municipio_CatDep` = `Mun`.`Id_Municipio`
    
    /* LEFT JOIN 2: Si tenemos Municipio, intentamos obtener su Estado (Abuelo) */
    LEFT JOIN `Estado` `Edo`    
        ON `Mun`.`Fk_Id_Estado` = `Edo`.`Id_Estado`
    
    /* LEFT JOIN 3: Si tenemos Estado, intentamos obtener su País (Bisabuelo) */
    LEFT JOIN `Pais` `Pais`     
        ON `Edo`.`Fk_Id_Pais` = `Pais`.`Id_Pais`

    WHERE `Dep`.`Id_CatDep` = _Id_CatDep
    LIMIT 1;

END$$

DELIMITER ;

/* ============================================================================================
   SECCIÓN: LISTADOS PARA DROPDOWNS (SOLO REGISTROS ACTIVOS)
   ============================================================================================
   Estas rutinas son consumidas por los formularios de captura (Frontend).
   Su objetivo es ofrecer al usuario solo las opciones válidas y vigentes.
   ============================================================================================ */

/* ============================================================================================
   PROCEDIMIENTO: SP_ListarDepActivos
   ============================================================================================
   OBJETIVO
   --------
   Obtener la lista de Departamentos disponibles para ser asignados en formularios 
   (Ej: Alta de Empleado, Asignación de Activos).

   CASOS DE USO
   ------------
   - Dropdown simple o Autocomplete en formularios donde se requiere seleccionar el departamento.

   REGLAS DE NEGOCIO (EL CONTRATO)
   -------------------------------
   1. FILTRO DE ESTATUS PROPIO: Solo devuelve departamentos con `Activo = 1`.
   2. FILTRO DE INTEGRIDAD JERÁRQUICA (CANDADO PADRE):
      - Un departamento solo es "seleccionable" si su Municipio padre TAMBIÉN está activo.
      - Si el municipio fue dado de baja (ej: cierre de operaciones en esa ciudad), 
        sus departamentos deben desaparecer de la lista disponible, aunque sigan en Activo=1.
   
   ORDENAMIENTO
   ------------
   - Alfabético por Nombre para facilitar la búsqueda visual.

   RETORNO
   -------
   - Id_CatDep (Value)
   - Codigo (Texto auxiliar)
   - Nombre (Label)
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ListarDepActivos`$$

CREATE PROCEDURE `SP_ListarDepActivos`()
BEGIN
    SELECT 
        `Dep`.`Id_CatDep`, 
        `Dep`.`Codigo`, 
        `Dep`.`Nombre`
    FROM `Cat_Departamentos` `Dep`
    /* JOIN para validar el estatus del padre (Municipio) */
    INNER JOIN `Municipio` `Mun` 
        ON `Dep`.`Fk_Id_Municipio_CatDep` = `Mun`.`Id_Municipio`
    WHERE 
        `Dep`.`Activo` = 1
        AND `Mun`.`Activo` = 1 /* CANDADO: Solo mostrar si el Municipio está operativo */
    ORDER BY 
        `Dep`.`Nombre` ASC;
END$$

DELIMITER ;

/* ============================================================================================
   SECCIÓN: LISTADOS PARA ADMINISTRACIÓN (TABLAS CRUD)
   ============================================================================================
   Estas rutinas son consumidas por los Paneles de Control (Grid/Tabla de Mantenimiento).
   Su objetivo es dar visibilidad total sobre el catálogo para auditoría y gestión.
   ============================================================================================ */
   
/* ============================================================================================
   PROCEDIMIENTO: SP_ListarDepAdmin
   ============================================================================================
   OBJETIVO
   --------
   Obtener el inventario completo de Departamentos para el Panel de Administración (Grid CRUD).
   
   CASOS DE USO
   ------------
   - Pantalla principal del Módulo "Administrar Departamentos".
   - Auditoría: Permite ver qué departamentos existen, cuáles están inactivos y su ubicación.
   
   DIFERENCIA CON EL LISTADO DE DROPDOWNS
   --------------------------------------
   - `SP_ListarDepActivos`: Solo devuelve Activos (1) y aplica candados jerárquicos (si el 
     Municipio está inactivo, el departamento no sale).
   - `SP_ListarDepAdmin` (ESTE): Devuelve TODO (Activos e Inactivos) y muestra el registro
     aunque su Municipio padre esté inactivo o roto. Esto es vital para que el administrador
     pueda ver el problema y corregirlo.

   ARQUITECTURA (USO DE VISTA)
   ---------------------------
   Se apoya en `Vista_Departamentos` para:
   1. Abstraer la complejidad de los JOINs geográficos.
   2. Mostrar nombres legibles (Municipio, Estado, País) en lugar de solo IDs numéricos.
   3. Garantizar que si se cambia la lógica de visualización en la vista, el Grid se actualiza solo.

   ORDENAMIENTO ESTRATÉGICO
   ------------------------
   1. Por Estatus (DESC): Los Activos (1) aparecen primero. Los Inactivos (0) al final.
   2. Por Nombre (ASC): Orden alfabético secundario para facilitar la búsqueda visual.

   RETORNO
   -------
   Devuelve todas las columnas de la vista:
   - Identidad: Id, Código, Nombre.
   - Ubicación Física: Dirección (Calle/Num).
   - Ubicación Geográfica: Municipio, Estado, País (Nombres).
   - Metadatos: Estatus.
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ListarDepAdmin`$$
CREATE PROCEDURE `SP_ListarDepAdmin`()
BEGIN
    SELECT * FROM `Vista_Departamentos` 
    ORDER BY 
        `Estatus_Departamento` DESC, -- Prioridad visual a lo operativo
        `Nombre_Departamento` ASC;
END$$

DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_EditarDepartamento
   ============================================================================================
   AUTOR: Tu Equipo de Desarrollo / Gemini
   FECHA: 2025

   OBJETIVO DE NEGOCIO
   -------------------
   Actualizar la información operativa y ubicación de un Departamento existente.
   
   Este procedimiento no es un simple UPDATE; es un motor de validación que garantiza
   que la base de datos nunca quede en un estado inconsistente, incluso bajo condiciones
   de estrés (múltiples usuarios editando al mismo tiempo) o errores de capa de usuario.

   ARQUITECTURA DE INTEGRIDAD (POR QUÉ HACEMOS LO QUE HACEMOS)
   -----------------------------------------------------------
   
   1. VALIDACIÓN GEOGRÁFICA ATÓMICA (La Regla del "Lugar Imposible"):
      - Problema: Un usuario malintencionado o un bug en el Frontend podría enviar un ID de 
        Municipio que existe (ej: "Centro"), pero con un ID de Estado que no le corresponde 
        (ej: "Veracruz").
      - Solución: Realizamos un `STRAIGHT_JOIN` forzado entre País -> Estado -> Municipio.
      - Resultado: Solo permitimos el cambio si la cadena jerárquica es PERFECTA y si los
        tres niveles están ACTIVOS (1). Si el municipio "existe" pero su estado fue dado 
        de baja, la operación se bloquea.

   2. LA "TRIPLE RESTRICCIÓN" (Identidad Compuesta):
      - A diferencia de los Centros de Trabajo, la unicidad de un Departamento es compleja.
      - Regla: La combinación (Código + Nombre + Municipio) debe ser ÚNICA.
      - Escenario: 
         * Se permite 'DEP-RH' en Villahermosa y 'DEP-RH' en Paraíso.
         * Se bloquea 'DEP-RH' en Villahermosa si ya existe otro registro con esos mismos datos.
      - Implementación: Se realiza un "Pre-Check" excluyendo al propio ID (`Id <> _Id_CatDep`)
        para detectar colisiones antes de intentar escribir.

   3. BLOQUEO PESIMISTA (Pessimistic Locking):
      - Usamos `SELECT ... FOR UPDATE` al inicio.
      - Esto "congela" la fila del departamento. Nadie más puede editarla ni eliminarla
        hasta que terminemos. Esto evita el problema de "Lost Update" (dos usuarios sobreescribiéndose).

   4. IDEMPOTENCIA ("SIN CAMBIOS"):
      - Si los datos nuevos son idénticos a los actuales (incluyendo el manejo de NULLs en la dirección),
        el SP detecta que no hay trabajo que hacer.
      - Retorna éxito inmediato sin tocar el disco duro (ahorro de I/O) y sin ensuciar los logs de auditoría.

   5. MANEJO DE "RACE CONDITIONS" (Error 1062):
      - A pesar de los Pre-Checks, existe una probabilidad de 0.01% de que otro usuario inserte
        el duplicado justo en el milisegundo entre nuestro SELECT y nuestro UPDATE.
      - El `DECLARE HANDLER FOR 1062` actúa como red de seguridad final, capturando el error
        nativo de MySQL y traduciéndolo a un mensaje de negocio ("CONFLICTO") que la UI puede entender.

   RETORNO (TABLA DE RESULTADOS)
   -----------------------------
   - Mensaje: Feedback legible para el usuario.
   - Accion: 
       * 'ACTUALIZADA' (Cambio exitoso)
       * 'SIN_CAMBIOS' (No se tocó la BD)
       * 'CONFLICTO'   (Error de duplicidad/concurrencia)
   - Datos de Contexto: IDs para refrescar la vista del cliente.
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_EditarDepartamento`$$
CREATE PROCEDURE `SP_EditarDepartamento`(
    IN _Id_CatDep          INT,           -- Llave Primaria del registro a editar
    IN _Nuevo_Codigo       VARCHAR(50),   -- Nuevo Código (ej: 'DEP-001')
    IN _Nuevo_Nombre       VARCHAR(255),  -- Nuevo Nombre (ej: 'Recursos Humanos')
    IN _Nueva_Direccion    VARCHAR(255),  -- Nueva Dirección Física descriptiva
    IN _Nuevo_Id_Pais      INT,           -- Contexto para validación geográfica
    IN _Nuevo_Id_Estado    INT,           -- Contexto para validación geográfica
    IN _Nuevo_Id_Municipio INT            -- El dato real (FK) que se persistirá
)
SP: BEGIN
    /* ========================================================================================
       PARTE 0: VARIABLES DE ESTADO (SNAPSHOTS)
       ======================================================================================== */
    /* Almacenan cómo está el registro AHORA (antes de editarlo) */
    DECLARE v_Codigo_Act    VARCHAR(50)  DEFAULT NULL;
    DECLARE v_Nombre_Act    VARCHAR(255) DEFAULT NULL;
    DECLARE v_Dir_Act       VARCHAR(255) DEFAULT NULL;
    DECLARE v_Mun_Act       INT          DEFAULT NULL;

    /* Variables auxiliares de control */
    DECLARE v_Existe        INT          DEFAULT NULL;
    DECLARE v_DupId         INT          DEFAULT NULL;
    DECLARE v_Dup           TINYINT(1)   DEFAULT 0; -- Bandera de error 1062

    /* Variables para reporte de conflictos */
    DECLARE v_Id_Conflicto  INT          DEFAULT NULL;

    /* ========================================================================================
       PARTE 1: HANDLERS (CONTROL DE ERRORES TÉCNICOS)
       ======================================================================================== */
    
    /* HANDLER 1062: Duplicate entry
       Si el UPDATE falla porque rompe el UNIQUE INDEX, no abortamos.
       Marcamos la bandera v_Dup = 1 y dejamos que el flujo llegue a la sección de manejo de errores. */
    DECLARE CONTINUE HANDLER FOR 1062
    BEGIN
        SET v_Dup = 1;
    END;

    /* HANDLER SQLEXCEPTION:
       Cualquier otro error (sintaxis, conexión, disco lleno) provoca un aborto seguro (ROLLBACK). */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    /* ========================================================================================
       PARTE 2: NORMALIZACIÓN Y LIMPIEZA DE INPUTS
       ======================================================================================== */
    SET _Nuevo_Codigo    = NULLIF(TRIM(_Nuevo_Codigo), '');
    SET _Nuevo_Nombre    = NULLIF(TRIM(_Nuevo_Nombre), '');
    SET _Nueva_Direccion = NULLIF(TRIM(_Nueva_Direccion), '');

    /* Protección contra IDs inválidos (0 o negativos se convierten en NULL) */
    IF _Nuevo_Id_Pais <= 0      THEN SET _Nuevo_Id_Pais = NULL;      END IF;
    IF _Nuevo_Id_Estado <= 0    THEN SET _Nuevo_Id_Estado = NULL;    END IF;
    IF _Nuevo_Id_Municipio <= 0 THEN SET _Nuevo_Id_Municipio = NULL; END IF;

    /* ========================================================================================
       PARTE 3: VALIDACIONES BÁSICAS (FAIL FAST)
       Evitamos abrir transacciones si los datos mínimos no están presentes.
       ======================================================================================== */
    IF _Id_CatDep IS NULL OR _Id_CatDep <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA: El ID del Departamento es inválido.';
    END IF;

    IF _Nuevo_Codigo IS NULL OR _Nuevo_Nombre IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN: El Código y el Nombre son obligatorios.';
    END IF;

    IF _Nuevo_Id_Pais IS NULL OR _Nuevo_Id_Estado IS NULL OR _Nuevo_Id_Municipio IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN: Debe seleccionar la ubicación completa (País, Estado y Municipio).';
    END IF;

    /* ========================================================================================
       PARTE 4: INICIO DE LA TRANSACCIÓN
       ======================================================================================== */
    START TRANSACTION;

    /* ----------------------------------------------------------------------------------------
       PASO 1: LEER Y BLOQUEAR EL REGISTRO ACTUAL
       ----------------------------------------------------------------------------------------
       Aplicamos `FOR UPDATE` para adquirir un "Write Lock" sobre la fila.
       Esto asegura que nadie más pueda modificar este departamento mientras nosotros decidimos qué hacer. */
    
    SET v_Codigo_Act = NULL;
    SET v_Nombre_Act = NULL; 
    SET v_Dir_Act = NULL; 
    SET v_Mun_Act = NULL;

    SELECT `Codigo`, `Nombre`, `Direccion_Fisica`, `Fk_Id_Municipio_CatDep`
      INTO v_Codigo_Act, v_Nombre_Act, v_Dir_Act, v_Mun_Act
    FROM `Cat_Departamentos`
    WHERE `Id_CatDep` = _Id_CatDep
    LIMIT 1
    FOR UPDATE;

    IF v_Codigo_Act IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE CONCURRENCIA: El Departamento que intenta editar ya no existe (fue eliminado por otro usuario).';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 2: VALIDACIÓN ATÓMICA DE JERARQUÍA GEOGRÁFICA
       ----------------------------------------------------------------------------------------
       Validamos la cadena completa: País -> Estado -> Municipio.
       También bloqueamos la fila del Municipio destino para evitar que se desactive durante el guardado. */
    
    SET v_Existe = NULL;

    SELECT 1 INTO v_Existe
    FROM `Pais` P
    STRAIGHT_JOIN `Estado` E ON E.`Fk_Id_Pais` = P.`Id_Pais`
    STRAIGHT_JOIN `Municipio` M ON M.`Fk_Id_Estado` = E.`Id_Estado`
    WHERE P.`Id_Pais` = _Nuevo_Id_Pais       AND P.`Activo` = 1
      AND E.`Id_Estado` = _Nuevo_Id_Estado   AND E.`Activo` = 1
      AND M.`Id_Municipio` = _Nuevo_Id_Municipio AND M.`Activo` = 1
    LIMIT 1
    FOR UPDATE; /* Bloqueamos el municipio destino */

    IF v_Existe IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE INTEGRIDAD: La ubicación seleccionada es inconsistente (El Municipio no pertenece al Estado/País) o contiene elementos inactivos.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 3: DETECCIÓN DE "SIN CAMBIOS" (OPTIMIZACIÓN)
       ----------------------------------------------------------------------------------------
       Comparamos campo por campo. Usamos `<=>` (Null-Safe Equality) para `Direccion_Fisica`
       porque puede ser NULL y `NULL = NULL` da NULL (falso), pero `NULL <=> NULL` da TRUE. */
    
    IF v_Codigo_Act = _Nuevo_Codigo 
       AND v_Nombre_Act = _Nuevo_Nombre 
       AND (v_Dir_Act <=> _Nueva_Direccion)
       AND (v_Mun_Act <=> _Nuevo_Id_Municipio) THEN
       
       COMMIT; -- Liberamos el lock inmediatamente
       
       SELECT 'No se detectaron cambios en la información.' AS Mensaje, 
              'SIN_CAMBIOS' AS Accion, 
              _Id_CatDep AS Id_Departamento;
       LEAVE SP;
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 4: PRE-CHECK DE DUPLICADOS (LA TRIPLE RESTRICCIÓN)
       ----------------------------------------------------------------------------------------
       Buscamos si YA EXISTE otro registro (`Id <> _Id_CatDep`) que coincida con la nueva Triada.
       Esto previene el error 1062 proactivamente para dar un mensaje claro. */
    
    SET v_DupId = NULL;

    SELECT `Id_CatDep` INTO v_DupId
    FROM `Cat_Departamentos`
    WHERE `Codigo` = _Nuevo_Codigo
      AND `Nombre` = _Nuevo_Nombre
      AND `Fk_Id_Municipio_CatDep` = _Nuevo_Id_Municipio
      AND `Id_CatDep` <> _Id_CatDep -- CRUCIAL: Excluirme a mí mismo
    LIMIT 1
    FOR UPDATE; -- Bloqueamos al conflictivo para que no cambie mientras validamos

    IF v_DupId IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE DUPLICIDAD: Ya existe otro Departamento con ese mismo CÓDIGO y NOMBRE en el MUNICIPIO seleccionado.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 5: EJECUCIÓN DEL UPDATE (CRÍTICO)
       ----------------------------------------------------------------------------------------
       Si pasamos todas las validaciones, intentamos escribir.
       Aquí puede ocurrir el error 1062 si hay una "Race Condition" perfecta. */
    
    SET v_Dup = 0; -- Reset de bandera antes del intento

    UPDATE `Cat_Departamentos`
    SET `Codigo` = _Nuevo_Codigo,
        `Nombre` = _Nuevo_Nombre,
        `Direccion_Fisica` = _Nueva_Direccion,
        `Fk_Id_Municipio_CatDep` = _Nuevo_Id_Municipio
        /* `updated_at` se actualiza automáticamente por definición de tabla */
    WHERE `Id_CatDep` = _Id_CatDep;

    /* ----------------------------------------------------------------------------------------
       PASO 6: MANEJO DE COLISIÓN (SI HUBO ERROR 1062)
       ----------------------------------------------------------------------------------------
       Si v_Dup se activó, significa que el UPDATE falló.
       Hacemos Rollback y buscamos quién causó el conflicto para reportarlo al Frontend. */
    
    IF v_Dup = 1 THEN
        ROLLBACK;
        
        SET v_Id_Conflicto = NULL;

        /* Buscamos el ID del registro que tiene nuestros datos */
        SELECT `Id_CatDep` INTO v_Id_Conflicto
        FROM `Cat_Departamentos`
        WHERE `Codigo` = _Nuevo_Codigo 
          AND `Nombre` = _Nuevo_Nombre
          AND `Fk_Id_Municipio_CatDep` = _Nuevo_Id_Municipio
          AND `Id_CatDep` <> _Id_CatDep
        LIMIT 1;

        SELECT 'Error de Concurrencia: Otro usuario guardó datos idénticos mientras usted editaba.' AS Mensaje,
               'CONFLICTO' AS Accion,
               'TRIADA_IDENTIDAD' AS Campo,
               v_Id_Conflicto AS Id_Conflicto;
        LEAVE SP;
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 7: CONFIRMACIÓN EXITOSA
       ---------------------------------------------------------------------------------------- */
    COMMIT;

    SELECT 'Departamento actualizado correctamente.' AS Mensaje,
           'ACTUALIZADA' AS Accion,
           _Id_CatDep AS Id_Departamento,
           _Nuevo_Id_Municipio AS Id_Municipio_Nuevo,
           v_Mun_Act AS Id_Municipio_Anterior;

END$$

DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_CambiarEstatusDepartamento
   ============================================================================================
   OBJETIVO DE NEGOCIO
   -------------------
   Gestionar el Ciclo de Vida (Lifecycle) de un Departamento mediante el mecanismo de
   "Baja Lógica" (Soft Delete).
   
   Esto permite "apagar" un departamento sin perder su historial, pero evitando que
   se utilice en nuevas operaciones.

   ARQUITECTURA DE INTEGRIDAD (EL MODELO DE "DOBLE CANDADO")
   ---------------------------------------------------------
   Este SP implementa una defensa bidireccional para mantener la coherencia de la base de datos:

   1. CANDADO ASCENDENTE (AL ACTIVAR):
      - Principio: "Un hijo no puede vivir si su padre está muerto".
      - Validación: Si intentas reactivar un Departamento, el sistema verifica que su
        MUNICIPIO (Padre) esté ACTIVO.
      - Escenario evitado: Que aparezca un departamento disponible en un municipio que la
        empresa ya cerró operativamente.

   2. CANDADO DESCENDENTE (AL DESACTIVAR):
      - Principio: "No puedes demoler un edificio con gente adentro".
      - Validación: Si intentas desactivar un Departamento, el sistema verifica que NO
        existan EMPLEADOS ACTIVOS (`Info_Personal`) asignados a él.
      - Escenario evitado: Empleados "huérfanos" cuyo departamento desaparece de los reportes,
        rompiendo la cadena de mando.

   ESTRATEGIA DE CONCURRENCIA (BLOQUEO PESIMISTA)
   ----------------------------------------------
   - Problema: ¿Qué pasa si un Admin A activa el Departamento justo en el mismo milisegundo
     en que un Admin B desactiva el Municipio?
   - Solución: `SELECT ... FOR UPDATE`.
   - Efecto: Bloqueamos la fila del Departamento Y la del Municipio en una sola operación atómica.
     Esto serializa las transacciones y garantiza que la decisión se tome con datos frescos.

   RETORNO
   -------
   - Mensaje: Texto claro para la UI (Feedback de éxito o bloqueo).
   - Datos de Estado: El valor anterior y el nuevo, útil para actualizar interruptores en la UI.
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_CambiarEstatusDepartamento`$$
CREATE PROCEDURE `SP_CambiarEstatusDepartamento`(
    IN _Id_CatDep INT,
    IN _Nuevo_Estatus TINYINT -- 1 = Activo, 0 = Inactivo
)
BEGIN
    /* ========================================================================================
       VARIABLES DE ESTADO Y CONTROL
       ======================================================================================== */
    /* Bandera de existencia del registro */
    DECLARE v_Existe INT DEFAULT NULL;
    
    /* Estado actual del Departamento (para verificar idempotencia) */
    DECLARE v_Activo_Actual TINYINT(1) DEFAULT NULL;
    
    /* Contexto del Padre (Municipio) para el Candado Ascendente */
    DECLARE v_Id_Municipio INT DEFAULT NULL;
    DECLARE v_Municipio_Activo TINYINT(1) DEFAULT NULL;

    /* Auxiliar para búsqueda de dependencias (Hijos) */
    DECLARE v_Tmp INT DEFAULT NULL;

    /* ========================================================================================
       HANDLERS (MANEJO DE ERRORES)
       ======================================================================================== */
    /* Si ocurre cualquier error técnico (SQL), deshacemos cambios y propagamos el error */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; 
    END;

    /* ========================================================================================
       VALIDACIONES BÁSICAS (DEFENSIVE PROGRAMMING)
       ======================================================================================== */
    IF _Id_CatDep IS NULL OR _Id_CatDep <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA: ID de Departamento inválido.';
    END IF;

    IF _Nuevo_Estatus NOT IN (0, 1) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA: Estatus inválido (solo se permite 0 o 1).';
    END IF;

    /* ========================================================================================
       INICIO DE TRANSACCIÓN
       ======================================================================================== */
    START TRANSACTION;

    /* ----------------------------------------------------------------------------------------
       PASO 1: LECTURA Y BLOQUEO DE CONTEXTO (SNAPSHOT)
       ----------------------------------------------------------------------------------------
       Aquí ocurre la magia de la concurrencia:
       1. Buscamos el Departamento.
       2. Hacemos LEFT JOIN al Municipio (LEFT porque podría ser NULL en datos legados).
       3. FOR UPDATE: Congela ambas filas. Nadie puede modificar el Municipio ni el Departamento
          hasta que nosotros terminemos. */
    
    SELECT 
        1,
        `Dep`.`Activo`, 
        `Dep`.`Fk_Id_Municipio_CatDep`, 
        `Mun`.`Activo`
    INTO 
        v_Existe,
        v_Activo_Actual, 
        v_Id_Municipio, 
        v_Municipio_Activo
    FROM `Cat_Departamentos` `Dep`
    LEFT JOIN `Municipio` `Mun` ON `Dep`.`Fk_Id_Municipio_CatDep` = `Mun`.`Id_Municipio`
    WHERE `Dep`.`Id_CatDep` = _Id_CatDep 
    LIMIT 1
    FOR UPDATE;

    /* Validación de existencia */
    IF v_Existe IS NULL THEN 
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO: El Departamento no existe.'; 
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 2: IDEMPOTENCIA (DETECCIÓN DE "SIN CAMBIOS")
       ----------------------------------------------------------------------------------------
       Si el usuario pide "Activar" algo que ya está "Activo", no tiene sentido gastar
       recursos de base de datos (I/O, Logs). Retornamos éxito inmediato. */
    
    IF v_Activo_Actual = _Nuevo_Estatus THEN
        COMMIT; -- Liberamos locks inmediatamente
        
        SELECT CASE 
            WHEN _Nuevo_Estatus = 1 THEN 'Sin cambios: El Departamento ya se encontraba Activo.'
            ELSE 'Sin cambios: El Departamento ya se encontraba Inactivo.'
        END AS Mensaje,
        v_Activo_Actual AS Activo_Anterior,
        _Nuevo_Estatus AS Activo_Nuevo;
        
    ELSE
        /* ====================================================================================
           SI EL ESTADO VA A CAMBIAR, EJECUTAMOS LAS REGLAS DE NEGOCIO
           ==================================================================================== */

        /* ------------------------------------------------------------------------------------
           PASO 3: REGLA DE ACTIVACIÓN (CANDADO ASCENDENTE)
           "Para revivir al hijo, el padre debe estar vivo".
           ------------------------------------------------------------------------------------ */
        IF _Nuevo_Estatus = 1 THEN
            /* Solo validamos si tiene un municipio asignado (Id no nulo) */
            IF v_Id_Municipio IS NOT NULL THEN
                /* Si el municipio existe pero está marcado como inactivo (0) */
                IF v_Municipio_Activo = 0 THEN
                    SIGNAL SQLSTATE '45000' 
                        SET MESSAGE_TEXT = 'BLOQUEO JERÁRQUICO: No se puede ACTIVAR el Departamento porque su MUNICIPIO está INACTIVO. Debe activar primero el Municipio.';
                END IF;
            END IF;
        END IF;

        /* ------------------------------------------------------------------------------------
           PASO 4: REGLA DE DESACTIVACIÓN (CANDADO DESCENDENTE)
           "No puedes cerrar la oficina si hay gente trabajando dentro".
           ------------------------------------------------------------------------------------ */
        IF _Nuevo_Estatus = 0 THEN
            SET v_Tmp = NULL;
            
            /* Buscamos dependencias en Info_Personal.
               IMPORTANTE: Solo nos importan los empleados con `Activo = 1`.
               Si hay empleados históricos (inactivos), no bloqueamos la baja del departamento. */
            SELECT 1 INTO v_Tmp
            FROM `Info_Personal` 
            WHERE `Fk_Id_CatDep` = _Id_CatDep 
              AND `Activo` = 1 
            LIMIT 1;

            IF v_Tmp IS NOT NULL THEN
                 SIGNAL SQLSTATE '45000' 
                    SET MESSAGE_TEXT = 'BLOQUEO DE INTEGRIDAD: El Departamento tiene PERSONAL ACTIVO asignado. Por favor, reasigne o desactive al personal antes de dar de baja este departamento.';
            END IF;
        END IF;

        /* ------------------------------------------------------------------------------------
           PASO 5: EJECUCIÓN DEL CAMBIO (PERSISTENCIA)
           ------------------------------------------------------------------------------------ */
        UPDATE `Cat_Departamentos` 
        SET `Activo` = _Nuevo_Estatus, 
            `updated_at` = NOW() 
        WHERE `Id_CatDep` = _Id_CatDep;
        
        COMMIT; 
        
        /* ------------------------------------------------------------------------------------
           PASO 6: RESPUESTA FINAL AL CLIENTE
           ------------------------------------------------------------------------------------ */
        SELECT CASE 
            WHEN _Nuevo_Estatus = 1 THEN 'Departamento Reactivado Exitosamente.'
            ELSE 'Departamento Desactivado (Baja Lógica) Correctamente.'
        END AS Mensaje,
        v_Activo_Actual AS Activo_Anterior,
        _Nuevo_Estatus AS Activo_Nuevo;
        
    END IF;
END$$

DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_EliminarDepartamentoFisico
   ============================================================================================
   OBJETIVO
   --------
   Eliminar DEFINITIVAMENTE (Hard Delete) un registro de la tabla `Cat_Departamentos`.
   
   ADVERTENCIA DE USO (PELIGRO)
   ----------------------------
   Este procedimiento es destructivo e irreversible. 
   - NO debe usarse para la operación diaria estándar (para eso existe la "Baja Lógica" con 
     `SP_CambiarEstatusDepartamento`).
   - SU ÚNICO CASO DE USO VÁLIDO es la depuración administrativa inmediata: 
     Por ejemplo, corregir errores de captura humana (se creó un departamento duplicado por 
     error y se detectó al instante, antes de que tuviera movimientos).

   CANDADOS DE SEGURIDAD (INTEGRIDAD REFERENCIAL)
   ----------------------------------------------
   1. VALIDACIÓN DE DEPENDENCIA HISTÓRICA (El Candado de Auditoría):
      - Regla: No basta con validar si hay empleados "Activos".
      - Si hubo un empleado hace 5 años asignado a este departamento (y hoy está inactivo),
        borrar el departamento rompería el historial laboral de esa persona en los reportes.
      - Por tanto, validamos si existe CUALQUIER registro en `Info_Personal` (Activo o Inactivo).
      - Si existe historial -> ERROR BLOQUEANTE ("ERROR CRÍTICO"). Se obliga a usar Baja Lógica.

   2. LA RED DE SEGURIDAD FINAL (HANDLER 1451):
      - MySQL tiene sus propios constraints (Foreign Keys).
      - Si en el futuro agregas nuevas tablas que apunten a Departamentos (ej: `Inventario_Activos`)
        y olvidas agregar la validación manual aquí, el motor de BD lanzará el error 1451.
      - Este SP atrapa ese error técnico y devuelve un mensaje controlado y amigable 
        ("No se puede eliminar por vínculos..."), evitando "pantallazos" de error SQL al usuario.

   CONCURRENCIA
   ------------
   - Se usa una transacción para asegurar que la verificación de existencia y el borrado
     ocurran en un contexto aislado. Al ser una operación atómica de DELETE, 
     el bloqueo de fila (Row Lock) es gestionado nativamente por el motor InnoDB.

   RESULTADO
   ---------
   - Mensaje de confirmación o error de integridad explicativo.
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_EliminarDepartamentoFisico`$$
CREATE PROCEDURE `SP_EliminarDepartamentoFisico`(
    IN _Id_CatDep INT
)
BEGIN
    /* ----------------------------------------------------------------------------------------
       HANDLERS (MANEJO DE EXCEPCIONES TÉCNICAS)
       ---------------------------------------------------------------------------------------- */
    
    /* HANDLER 1451: Foreign Key Constraint Fails
       Este es el "Paracaídas". Si intentamos borrar y resulta que había una tabla hija 
       (que olvidamos validar manualmente o que se agregó después al sistema) apuntando a este ID, 
       MySQL lanzará el error 1451.
       Aquí lo atrapamos para que la UI no reciba un error críptico de SQL. */
    DECLARE EXIT HANDLER FOR 1451 
    BEGIN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'BLOQUEO DE INTEGRIDAD (FK): No es posible eliminar el Departamento porque existen registros históricos vinculados a él en otras tablas del sistema.';
    END;

    /* HANDLER GENERAL: Para errores de disco, conexión, etc. */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; 
    END;

    /* ----------------------------------------------------------------------------------------
       1. VALIDACIONES PREVIAS
       ---------------------------------------------------------------------------------------- */
    IF _Id_CatDep IS NULL OR _Id_CatDep <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA: El ID de Departamento es inválido.';
    END IF;

    /* Verificamos si existe antes de intentar nada para dar un mensaje preciso */
    IF NOT EXISTS(SELECT 1 FROM `Cat_Departamentos` WHERE `Id_CatDep` = _Id_CatDep) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO: El Departamento que intenta eliminar no existe.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       2. CANDADO DE NEGOCIO: INFO_PERSONAL (EMPLEADOS)
       ----------------------------------------------------------------------------------------
       Buscamos en TODO el historial (`Info_Personal`).
       Nota: NO filtramos por `Activo = 1`. 
       Razón: Si borramos un departamento que tuvo empleados en el pasado (ahora inactivos),
       dejaríamos registros huérfanos y reportes históricos rotos ("Empleado X trabajó en NULL"). */
    
    IF EXISTS(
        SELECT 1 
        FROM `Info_Personal` 
        WHERE `Fk_Id_CatDep` = _Id_CatDep 
        LIMIT 1
    ) THEN
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'ERROR CRÍTICO: No se puede eliminar el Departamento. Existe historial de PERSONAL (Activo o Inactivo) vinculado a este registro. Utilice la opción "Desactivar".';
    END IF;

    /* ----------------------------------------------------------------------------------------
       3. EJECUCIÓN DEL BORRADO
       ----------------------------------------------------------------------------------------
       Si llegamos aquí, el registro pasó las validaciones manuales.
       Procedemos a intentar el DELETE dentro de una transacción. */
    START TRANSACTION;
    
    /* Intentamos borrar. Si hay alguna FK oculta no validada arriba, 
       saltará el Handler 1451 definido al inicio y hará Rollback automático. */
    DELETE FROM `Cat_Departamentos` 
    WHERE `Id_CatDep` = _Id_CatDep;
    
    COMMIT;

    /* ----------------------------------------------------------------------------------------
       4. CONFIRMACIÓN
       ---------------------------------------------------------------------------------------- */
    SELECT 'El Departamento ha sido eliminado permanentemente de la base de datos.' AS Mensaje;

END$$

DELIMITER ;