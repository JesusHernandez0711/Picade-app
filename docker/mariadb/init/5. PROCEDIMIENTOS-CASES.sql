USE `PICADE`;

/* ------------------------------------------------------------------------------------------------------ */
/* CREACION DE VISTAS Y PROCEDIMIENTOS DE ALMACENADO PARA LA BASE DE DATOS*/
/* ------------------------------------------------------------------------------------------------------ */

/* ======================================================================================================
   1. VIEW: Vista_Sedes
   ======================================================================================================
   OBJETIVO GENERAL
   ----------------
   Consolidar el inventario de Sedes (Centros de Adiestramiento, Seguridad, Ecología y Supervivencia - CASES)
   con su ubicación geográfica y capacidad instalada, sirviendo como la fuente de verdad única para
   la administración y visualización operativa.

   ARQUITECTURA MODULAR (DRY)
   --------------------------
   Esta vista implementa el patrón de reutilización al hacer JOIN con `Vista_Direcciones`.
   Esto abstrae la complejidad de la jerarquía geográfica (Municipio -> Estado -> País) y garantiza
   que cualquier cambio en la lógica de direcciones se propague automáticamente aquí.

   DECISIÓN CRÍTICA DE DISEÑO (LEFT JOIN)
   --------------------------------------
   Se utiliza **LEFT JOIN** para relacionar `Cat_Cases_Sedes` con `Vista_Direcciones`.

   Justificación Técnica:
   - Integridad de Visualización (Safety Net): Aunque la tabla define `Fk_Id_Municipio` como NOT NULL,
     es posible que en el futuro un municipio sea eliminado o desactivado, dejando a la sede "huérfana"
     de ubicación lógica.
   - Si usáramos INNER JOIN, esas sedes desaparecerían silenciosamente de los reportes.
   - Con LEFT JOIN, aseguramos que el Administrador vea TODAS las sedes existentes. Las que tengan
     problemas de ubicación mostrarán NULL en los campos geográficos (Nombre_Municipio, etc.),
     facilitando la detección de anomalías.

   DICCIONARIO DE DATOS (CAMPOS DEVUELTOS)
   ---------------------------------------
   [Entidad Principal: Sede / CASES]
   - Id_Sedes:                   ID único (PK).
   - Codigo_Sedes:               Clave interna (ej: 'CASES-01'). Puede ser NULL en datos históricos.
   - Nombre_Sedes:               Nombre oficial descriptivo.
   - Descripcion_Direccion_Sedes: Dirección física detallada (Calle, Número).

   [Infraestructura / Capacidad Instalada]
   - Capacidad_Total_Sedes:      Aforo máximo de personas.
   - Aulas, Salas, Alberca, CampoPracticas_Escenario, Muelle_Entrenamiento_Botes, BoteSalvavida_Capacidad.
     * Estos campos permiten filtrar qué sedes tienen ciertos recursos (ej: "Buscar sedes con Alberca").

   [Datos Geográficos - Heredados de Vista_Direcciones]
   - Codigo_Municipio, Nombre_Municipio
   - Codigo_Estado, Nombre_Estado
   - Codigo_Pais, Nombre_Pais

   [Metadatos]
   - Estatus_Sede:               1 = Operativo, 0 = Baja Lógica.
   ====================================================================================================== */

-- DROP VIEW IF EXISTS `PICADE`.`Vista_Sedes`;

CREATE OR REPLACE
    ALGORITHM = UNDEFINED 
    SQL SECURITY DEFINER
VIEW `PICADE`.`Vista_Sedes` AS
    SELECT 
        /* --- Datos de Identidad --- */
        `Cases`.`Id_CatCases_Sedes`          AS `Id_Sedes`,
        `Cases`.`Codigo`                     AS `Codigo_Sedes`,
        `Cases`.`Nombre`                     AS `Nombre_Sedes`,
        `Cases`.`DescripcionDireccion`       AS `Descripcion_Direccion_Sedes`,
        
        /* --- Datos de Infraestructura (Inventario) --- */
        `Cases`.`Capacidad_Total`            AS `Capacidad_Total_Sedes`,
        /*`Cases`.`Aulas`,
        `Cases`.`Salas`,
        `Cases`.`Alberca`,
        `Cases`.`CampoPracticas_Escenario`,
        `Cases`.`Muelle_Entrenamiento_Botes`,
        `Cases`.`BoteSalvavida_Capacidad`,*/

        /* --- Datos Geográficos Reutilizados (Modularidad) --- */
        `Ubi`.`Codigo_Municipio`,
        `Ubi`.`Nombre_Municipio`,
        `Ubi`.`Codigo_Estado`,
        -- `Ubi`.`Nombre_Estado`,
        `Ubi`.`Codigo_Pais`,
        -- `Ubi`.`Nombre_Pais`,
        
        /* --- Metadatos de Control --- */
        `Cases`.`Activo`                     AS `Estatus_Sede`
    FROM
        `PICADE`.`Cat_Cases_Sedes` `Cases`
        /* LEFT JOIN Estratégico: Garantiza visibilidad total incluso con fallos geográficos */
        LEFT JOIN `PICADE`.`Vista_Direcciones` `Ubi` 
            ON `Cases`.`Fk_Id_Municipio` = `Ubi`.`Id_Municipio`;

/* ============================================================================================
   PROCEDIMIENTO: SP_RegistrarSede
   ============================================================================================
   OBJETIVO DE NEGOCIO
   -------------------
   Registrar una nueva Sede (CASES) en el catálogo corporativo, gestionando integralmente:
     1. Identidad Administrativa (Código y Nombre únicos).
     2. Ubicación Geográfica (Integridad con Municipios).
     3. Capacidad Instalada (Inventario de infraestructura).

   REGLAS CRÍTICAS (EL CONTRATO DE INTEGRIDAD)
   -------------------------------------------
   A) IDENTIDAD GLOBAL (DOBLE UNICIDAD):
      La tabla `Cat_Cases_Sedes` tiene dos restricciones UNIQUE fuertes:
      1. `Uk_Codigo`: No pueden existir dos sedes con el mismo Código (ej: 'CASES-01').
      2. `Uk_Nombre`: No pueden existir dos sedes con el mismo Nombre (ej: 'CASES PARAISO').
      
      Estrategia de Resolución:
      - Primero buscamos por CÓDIGO (Regla Primaria).
      - Si no existe, buscamos por NOMBRE (Regla Secundaria).
      - Si encontramos coincidencia cruzada (ej: Nombre existe pero con otro Código), 
        se lanza un ERROR DE CONFLICTO para evitar corrupción de datos.

   B) INTEGRIDAD DEL PADRE (UBICACIÓN):
      - Una Sede no puede existir en el vacío. Debe estar anclada a un MUNICIPIO ACTIVO.
      - Se aplica BLOQUEO PESIMISTA (`FOR UPDATE`) al registro del Municipio.
      - Esto evita la condición de carrera donde un Administrador desactiva el Municipio 
        en el preciso instante en que estamos registrando una Sede en él.

   C) MANEJO DE INVENTARIO (SANITIZACIÓN DE NULOS):
      - Los campos de infraestructura (Aulas, Salas, Albercas, etc.) son contadores.
      - Regla: "La ausencia de dato equivale a cero".
      - El SP intercepta cualquier `NULL` enviado por el Frontend y lo convierte a `0` 
        antes de guardar. Esto garantiza que las sumas y reportes futuros no fallen.

   D) CONCURRENCIA AVANZADA (EL PATRÓN "RE-RESOLVE"):
      - Problema: Dos usuarios envían el registro de la misma Sede simultáneamente.
        Ambos pasan las validaciones de lectura (SELECT). Ambos intentan INSERT.
        Uno gana, el otro falla con Error 1062 (Duplicate Key).
      - Solución: 
        1. Atrapamos el error 1062 con un HANDLER.
        2. Hacemos ROLLBACK silencioso.
        3. Iniciamos nueva transacción y buscamos el registro que acaba de crear el "ganador".
        4. Devolvemos éxito ('REUSADA' o 'REACTIVADA') en lugar de un error técnico.

   RESULTADO
   ---------
   Retorna una tabla con:
     - Mensaje: Feedback legible para el usuario.
     - Id_Sede: El ID del registro (nuevo o recuperado).
     - Accion: 'CREADA', 'REACTIVADA', 'REUSADA'.
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_RegistrarSede`$$
CREATE PROCEDURE `SP_RegistrarSede`(
    /* -----------------------------------------------------------------
       PARÁMETROS DE ENTRADA
       ----------------------------------------------------------------- */
    /* BLOQUE 1: IDENTIDAD Y UBICACIÓN (Datos Obligatorios) */
    IN _Codigo               VARCHAR(50),   -- Clave única (ej: 'CASES-TAB-01')
    IN _Nombre               VARCHAR(255),  -- Nombre descriptivo único
    IN _DescripcionDireccion VARCHAR(255),  -- Dirección física (Calle/Número)
    IN _Id_Municipio         INT,           -- FK hacia Municipio
    
    /* BLOQUE 2: INFRAESTRUCTURA (Inventario Variable - Opcionales)
       Nota: Si el frontend envía NULL, se asume 0. */
    IN _Capacidad_Total      INT,
    IN _Aulas                TINYINT,
    IN _Salas                TINYINT,
    IN _Alberca              TINYINT,
    IN _CampoPracticas       TINYINT,
    IN _Muelle               TINYINT,
    IN _BotesCapacidad       TINYINT
)
SP: BEGIN
    /* ========================================================================================
       VARIABLES DE TRABAJO
       ======================================================================================== */
    /* Para almacenar el estado del registro si ya existe */
    DECLARE v_Id_Sede INT DEFAULT NULL;
    DECLARE v_Activo  TINYINT(1) DEFAULT NULL;
    DECLARE v_Nombre  VARCHAR(255) DEFAULT NULL;
    DECLARE v_Codigo  VARCHAR(50) DEFAULT NULL;
    
    /* Para validación del Padre (Municipio) */
    DECLARE v_Mun_Existe INT DEFAULT NULL;
    DECLARE v_Mun_Activo TINYINT(1) DEFAULT NULL;
    
    /* Bandera para control de flujo en Concurrencia (Error 1062) */
    DECLARE v_Dup TINYINT(1) DEFAULT 0;

    /* ========================================================================================
       HANDLERS (MANEJO DE EXCEPCIONES TÉCNICAS)
       ======================================================================================== */
    
    /* HANDLER 1062: Duplicate Entry
       Este es el corazón de la tolerancia a concurrencia. Si el INSERT falla por duplicado,
       el código NO se detiene; se activa la bandera v_Dup = 1 y continuamos hacia el bloque de resolución. */
    DECLARE CONTINUE HANDLER FOR 1062 
    BEGIN
        SET v_Dup = 1;
    END;

    /* HANDLER SQLEXCEPTION: Fallos Generales
       Cualquier otro error (disco lleno, desconexión, sintaxis) aborta la transacción inmediatamente. */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; 
    END;

    /* ========================================================================================
       PARTE 1: NORMALIZACIÓN Y SANITIZACIÓN DE INPUTS
       ======================================================================================== */
    
    /* 1.1 Limpieza de Strings (Trim de espacios) */
    SET _Codigo               = NULLIF(TRIM(_Codigo), '');
    SET _Nombre               = NULLIF(TRIM(_Nombre), '');
    SET _DescripcionDireccion = NULLIF(TRIM(_DescripcionDireccion), '');
    
    /* 1.2 Sanitización de Infraestructura (Lógica de Negocio: NULL -> 0)
       Esto asegura que la tabla siempre tenga valores numéricos válidos (NOT NULL DEFAULT 0). */
    SET _Capacidad_Total = IFNULL(_Capacidad_Total, 0);
    SET _Aulas           = IFNULL(_Aulas, 0);
    SET _Salas           = IFNULL(_Salas, 0);
    SET _Alberca         = IFNULL(_Alberca, 0);
    SET _CampoPracticas  = IFNULL(_CampoPracticas, 0);
    SET _Muelle          = IFNULL(_Muelle, 0);
    SET _BotesCapacidad  = IFNULL(_BotesCapacidad, 0);

    /* ========================================================================================
       PARTE 2: VALIDACIONES DE ENTRADA (FAIL FAST)
       ======================================================================================== */
    
    /* Regla: El Código es Obligatorio (Llave de búsqueda rápida) */
    IF _Codigo IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN: El CÓDIGO de la Sede es obligatorio.';
    END IF;

    /* Regla: El Nombre es Obligatorio (Identidad humana) */
    IF _Nombre IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN: El NOMBRE de la Sede es obligatorio.';
    END IF;

    /* Regla: La Ubicación es Obligatoria */
    IF _Id_Municipio IS NULL OR _Id_Municipio <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN: Debe seleccionar un MUNICIPIO válido.';
    END IF;

    /* ========================================================================================
       INICIO DE LA TRANSACCIÓN
       ======================================================================================== */
    START TRANSACTION;

    /* ----------------------------------------------------------------------------------------
       PASO 3: VALIDAR INTEGRIDAD DEL MUNICIPIO (PADRE)
       ----------------------------------------------------------------------------------------
       Usamos `FOR UPDATE` para bloquear la fila del Municipio.
       Esto previene la condición de carrera donde un usuario desactiva el municipio
       mientras nosotros intentamos registrar una sede en él. */
    
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
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO: El Municipio seleccionado está INACTIVO. No se pueden registrar Sedes en una ubicación cerrada.'; 
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 4: RESOLVER POR CÓDIGO (REGLA DE UNICIDAD PRIMARIA)
       ----------------------------------------------------------------------------------------
       Buscamos si el Código (_Codigo) ya existe en la base de datos.
       Constraint implicado: `Uk_Codigo_CatCases_Sedes` */
    
    SET v_Id_Sede = NULL;
    
    SELECT `Id_CatCases_Sedes`, `Nombre`, `Activo` 
    INTO v_Id_Sede, v_Nombre, v_Activo
    FROM `Cat_Cases_Sedes` 
    WHERE `Codigo` = _Codigo 
    LIMIT 1 
    FOR UPDATE; -- Bloqueamos para evitar cambios simultáneos

    /* CASO 4.1: EL CÓDIGO YA EXISTE */
    IF v_Id_Sede IS NOT NULL THEN
        
        /* Validación de Consistencia de Identidad:
           Si el código existe, el Nombre TAMBIÉN debe coincidir.
           Si el código es igual pero el nombre es diferente, es un CONFLICTO DE DATOS. */
        IF v_Nombre <> _Nombre THEN
            SIGNAL SQLSTATE '45000' 
                SET MESSAGE_TEXT = 'ERROR DE CONFLICTO: El CÓDIGO ingresado ya existe pero pertenece a una Sede con diferente NOMBRE. Verifique sus datos.';
        END IF;
        
        /* Autosanación: Reactivar si estaba borrado lógicamente */
        IF v_Activo = 0 THEN
            UPDATE `Cat_Cases_Sedes`
            SET `Activo` = 1,
                `DescripcionDireccion`       = COALESCE(_DescripcionDireccion, `DescripcionDireccion`),
                /* AL REACTIVAR, ACTUALIZAMOS EL INVENTARIO CON LOS DATOS NUEVOS */
                `Capacidad_Total`            = _Capacidad_Total,
                `Aulas`                      = _Aulas,
                `Salas`                      = _Salas,
                `Alberca`                    = _Alberca,
                `CampoPracticas_Escenario`   = _CampoPracticas,
                `Muelle_Entrenamiento_Botes` = _Muelle,
                `BoteSalvavida_Capacidad`    = _BotesCapacidad,
                `updated_at`                 = NOW()
            WHERE `Id_CatCases_Sedes` = v_Id_Sede;
            
            COMMIT; 
            SELECT 'Sede reactivada y actualizada exitosamente' AS Mensaje, v_Id_Sede AS Id_Sedes, 'REACTIVADA' AS Accion; 
            LEAVE SP;
        ELSE
            /* Si ya existe y está activa -> Idempotencia (No hacemos nada, reportamos éxito) */
            COMMIT; 
            SELECT 'La Sede ya se encuentra registrada y activa.' AS Mensaje, v_Id_Sede AS Id_Sedes, 'REUSADA' AS Accion; 
            LEAVE SP;
        END IF;
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 5: RESOLVER POR NOMBRE (REGLA DE UNICIDAD SECUNDARIA)
       ----------------------------------------------------------------------------------------
       Si llegamos aquí, el CÓDIGO es nuevo (no existe).
       Ahora verificamos: ¿Ya existe una Sede con ese NOMBRE?
       Constraint implicado: `Uk_Nombre_CatCases_Sedes` */
    
    SET v_Id_Sede = NULL;
    
    SELECT `Id_CatCases_Sedes`, `Codigo`
    INTO v_Id_Sede, v_Codigo
    FROM `Cat_Cases_Sedes` 
    WHERE `Nombre` = _Nombre 
    LIMIT 1 
    FOR UPDATE;

    /* CASO 5.1: EL NOMBRE YA EXISTE (Pero con otro Código, o no estaríamos aquí) */
    IF v_Id_Sede IS NOT NULL THEN
        /* Esto es un CONFLICTO DE IDENTIDAD grave.
           Significa que intentas registrar "CASES PARAISO" con el código "X", 
           pero ya existe "CASES PARAISO" con el código "Y". */
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'ERROR DE CONFLICTO: El NOMBRE ingresado ya existe asociado a otro CÓDIGO diferente. No se permiten nombres duplicados.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 6: INSERTAR (CREACIÓN DE NUEVO REGISTRO)
       ----------------------------------------------------------------------------------------
       Si pasamos las validaciones anteriores, el registro es nuevo y válido.
       Procedemos a insertar. Aquí podría saltar el Error 1062 si hay una "Race Condition". */
    
    SET v_Dup = 0; -- Reiniciamos bandera
    
    INSERT INTO `Cat_Cases_Sedes`
    (
        `Codigo`, 
        `Nombre`, 
        `DescripcionDireccion`, 
        `Fk_Id_Municipio`,
        /* Campos de Infraestructura */
        `Capacidad_Total`, 
        `Aulas`, 
        `Salas`, 
        `Alberca`, 
        `CampoPracticas_Escenario`, 
        `Muelle_Entrenamiento_Botes`, 
        `BoteSalvavida_Capacidad`
    )
    VALUES
    (
        _Codigo, 
        _Nombre, 
        _DescripcionDireccion, 
        _Id_Municipio,
        _Capacidad_Total, 
        _Aulas, 
        _Salas, 
        _Alberca, 
        _CampoPracticas, 
        _Muelle, 
        _BotesCapacidad
    );

    /* Verificamos si la inserción fue exitosa (v_Dup sigue en 0) */
    IF v_Dup = 0 THEN
        COMMIT; 
        SELECT 'Sede registrada exitosamente' AS Mensaje, LAST_INSERT_ID() AS Id_Sedes, 'CREADA' AS Accion; 
        LEAVE SP;
    END IF;

    /* ========================================================================================
       PASO 7: RE-RESOLVE (MANEJO AVANZADO DE CONCURRENCIA - ERROR 1062)
       ========================================================================================
       Si llegamos aquí, v_Dup = 1.
       Significa que entre nuestros SELECTs (Paso 4/5) y nuestro INSERT (Paso 6), 
       OTRO usuario insertó el registro.
       
       Estrategia: 
       1. ROLLBACK para limpiar la transacción fallida.
       2. START TRANSACTION nueva.
       3. Buscar el registro "ganador" y devolverlo limpiamente. */
    
    ROLLBACK;
    
    START TRANSACTION;
    
    /* Intentamos recuperar por CÓDIGO (Regla más fuerte) */
    SET v_Id_Sede = NULL;
    
    SELECT `Id_CatCases_Sedes`, `Activo`, `Nombre` 
    INTO v_Id_Sede, v_Activo, v_Nombre
    FROM `Cat_Cases_Sedes` 
    WHERE `Codigo` = _Codigo 
    LIMIT 1 
    FOR UPDATE;
    
    IF v_Id_Sede IS NOT NULL THEN
        /* Validación paranoica: Asegurar que el registro que ganó sea consistente */
        IF v_Nombre <> _Nombre THEN
             SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR CRÍTICO DE SISTEMA: Concurrencia detectada con conflicto de datos (Nombres distintos).';
        END IF;

        /* Si el ganador estaba inactivo, aprovechamos para reactivarlo */
        IF v_Activo = 0 THEN
            UPDATE `Cat_Cases_Sedes` 
            SET `Activo` = 1, `updated_at` = NOW() 
            WHERE `Id_CatCases_Sedes` = v_Id_Sede;
            
            COMMIT; 
            SELECT 'Sede reactivada (recuperada tras concurrencia)' AS Mensaje, v_Id_Sede AS Id_Sedes, 'REACTIVADA' AS Accion; 
            LEAVE SP;
        END IF;
        
        /* Si ya estaba activo, simplemente lo retornamos */
        COMMIT; 
        SELECT 'Sede ya existía (reusada tras concurrencia)' AS Mensaje, v_Id_Sede AS Id_Sedes, 'REUSADA' AS Accion; 
        LEAVE SP;
    END IF;

    /* Si falló por 1062 pero no encontramos el registro (caso extremadamente raro) */
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
   PROCEDIMIENTO: SP_ConsultarSedeEspecifica
   ============================================================================================
   AUTOR: Tu Equipo de Desarrollo / Gemini
   FECHA: 2026

   OBJETIVO DE NEGOCIO
   -------------------
   Recuperar la "Hoja de Vida" completa de una Sede (CASES) para dos casos de uso críticos:
   1. Visualización de Detalle (Ficha Técnica completa con inventario detallado).
   2. Precarga del Formulario de Edición (Update).

   EL RETO TÉCNICO (RECONSTRUCCIÓN JERÁRQUICA INVERSA)
   ---------------------------------------------------
   En el modelo de datos normalizado, la Sede (`Cat_Cases_Sedes`) es una entidad que se vincula 
   geográficamente solo a nivel de MUNICIPIO (`Fk_Id_Municipio`).
   
   Sin embargo, la Interfaz de Usuario (UI) para la edición requiere desplegar selectores
   dependientes (Cascading Dropdowns) para permitir al usuario cambiar la ubicación:
      [ Seleccione País ]  ->  [ Seleccione Estado ]  ->  [ Seleccione Municipio ]
   
   Si el Backend solo devolviera el `Id_Municipio`, el Frontend no sabría qué País ni qué Estado 
   pre-seleccionar automáticamente, rompiendo la experiencia de usuario.
   
   SOLUCIÓN:
   Este SP realiza una "Reconstrucción Jerárquica Inversa" (Hijo -> Padre -> Abuelo -> Bisabuelo)
   realizando los JOINs ascendentes (Sede -> Municipio -> Estado -> País) para entregar
   los 3 IDs necesarios (Id_Pais, Id_Estado, Id_Municipio) en una sola consulta eficiente.

   ESTRATEGIA DE INTEGRIDAD (POR QUÉ USAR LEFT JOIN)
   -------------------------------------------------
   Se ha decidido utilizar `LEFT JOIN` para enlazar la cadena geográfica.
   
   Justificación Técnica:
   - Robustez ante Datos Migrados o Corruptos: En una carga masiva histórica, es posible que
     una Sede tenga un ID de Municipio que ya no existe (huérfano) o sea inválido.
   - Si usáramos INNER JOIN, ese registro desaparecería de la consulta, haciendo imposible 
     abrir su formulario de edición para CORREGIRLO.
   - Con LEFT JOIN, recuperamos los datos de la Sede (Nombre, Inventario) incluso si su 
     ubicación está rota. Los campos geográficos vendrán en NULL, permitiendo al usuario
     seleccionar una nueva ubicación válida y salvar el registro.

   DICCIONARIO DE DATOS (OUTPUT)
   -----------------------------
   A) Datos de Identidad:
      - Id_Sede, Codigo, Nombre, Dirección Física, Estatus.
   
   B) Datos de Infraestructura (Inventario Variable):
      - Capacidad_Total, Aulas, Salas, Alberca, Campos, Muelles, Botes.
      - Estos valores son vitales para llenar los inputs numéricos del formulario.
   
   C) Contexto Geográfico (IDs y Etiquetas):
      - IDs: Id_Pais, Id_Estado, Id_Municipio (Para el `value=""` de los <select>).
      - Nombres: Para contexto visual en la UI ("Ah, esta sede está en Veracruz").

   VALIDACIONES PREVIAS
   --------------------
   - Validación defensiva de parámetros (Id Nulo o <= 0).
   - Verificación de existencia rápida (Fail Fast) antes de ejecutar los Joins costosos.
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ConsultarSedeEspecifica`$$
CREATE PROCEDURE `SP_ConsultarSedeEspecifica`(
    IN _Id_Sede INT
)
BEGIN
    /* ----------------------------------------------------------------------------------------
       1. VALIDACIÓN DE ENTRADA (DEFENSIVE PROGRAMMING)
       Evitamos desperdiciar ciclos de CPU y conexiones si el parámetro recibido es basura.
       ---------------------------------------------------------------------------------------- */
    IF _Id_Sede IS NULL OR _Id_Sede <= 0 THEN
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'ERROR DE SISTEMA: El ID de la Sede es inválido.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       2. VALIDACIÓN DE EXISTENCIA (FAIL FAST)
       Verificamos rápido contra el índice primario si el registro existe.
       Si no existe, abortamos inmediatamente con un mensaje de negocio claro, antes de 
       intentar hacer JOINs complejos.
       ---------------------------------------------------------------------------------------- */
    IF NOT EXISTS (SELECT 1 FROM `Cat_Cases_Sedes` WHERE `Id_CatCases_Sedes` = _Id_Sede) THEN
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'ERROR DE NEGOCIO: La Sede solicitada no existe o fue eliminada.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       3. CONSULTA PRINCIPAL (RECONSTRUCCIÓN JERÁRQUICA + INVENTARIO)
       ---------------------------------------------------------------------------------------- */
    SELECT 
        /* --- BLOQUE A: DATOS DE IDENTIDAD --- */
        `S`.`Id_CatCases_Sedes`      AS `Id_Sede`,
        `S`.`Codigo`                 AS `Codigo_Sede`,
        `S`.`Nombre`                 AS `Nombre_Sede`,
        `S`.`DescripcionDireccion`   AS `Direccion_Fisica`,

        /* --- BLOQUE B: DATOS DE INFRAESTRUCTURA (INVENTARIO DETALLADO) --- */
        /* Estos campos alimentan los inputs numéricos del formulario.
           Al ser columnas NOT NULL DEFAULT 0, siempre retornarán un entero válido. */
        `S`.`Capacidad_Total`,
        `S`.`Aulas`,
        `S`.`Salas`,
        `S`.`Alberca`,
        `S`.`CampoPracticas_Escenario`   AS `Campos_Practica`,
        `S`.`Muelle_Entrenamiento_Botes` AS `Muelles`,
        `S`.`BoteSalvavida_Capacidad`    AS `Capacidad_Botes`,

        /* --- BLOQUE C: JERARQUÍA GEOGRÁFICA (IDs para Lógica de UI) --- */
        /* Estos campos son los que el Frontend bindeará a los ng-model o v-model de los Selects.
           Si la ubicación está rota, vendrán en NULL. */
        /* --- BLOQUE D: JERARQUÍA GEOGRÁFICA (Nombres para Visualización) --- */
        /* Contexto visual para que el usuario confirme la ubicación actual */
        `Mun`.`Id_Municipio`,
        `Mun`.`Nombre`               AS `Nombre_Municipio`,
        
        `Edo`.`Id_Estado`,    /* Vital para pre-seleccionar el Dropdown de Estado */
        `Edo`.`Nombre`               AS `Nombre_Estado`,
        
        `Pais`.`Id_Pais`,     /* Vital para pre-seleccionar el Dropdown de País */
        `Pais`.`Nombre`              AS `Nombre_Pais`,

        /* --- BLOQUE E: METADATOS Y AUDITORÍA --- */
        `S`.`Activo`                 AS `Estatus_Sede`,
        `S`.`created_at`,
        `S`.`updated_at`

    FROM `Cat_Cases_Sedes` `S`
    
    /* LEFT JOIN 1: Intentamos obtener el Municipio (Padre directo) */
    /* Usamos LEFT JOIN para permitir cargar la ficha incluso si el ID de municipio es inválido */
    LEFT JOIN `Municipio` `Mun` 
        ON `S`.`Fk_Id_Municipio` = `Mun`.`Id_Municipio`
    
    /* LEFT JOIN 2: Si tenemos Municipio, intentamos obtener su Estado (Abuelo) */
    LEFT JOIN `Estado` `Edo`    
        ON `Mun`.`Fk_Id_Estado` = `Edo`.`Id_Estado`
    
    /* LEFT JOIN 3: Si tenemos Estado, intentamos obtener su País (Bisabuelo) */
    LEFT JOIN `Pais` `Pais`      
        ON `Edo`.`Fk_Id_Pais` = `Pais`.`Id_Pais`

    WHERE `S`.`Id_CatCases_Sedes` = `_Id_Sede`
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
   PROCEDIMIENTO: SP_ListarSedesActivas
   ============================================================================================
   OBJETIVO
   --------
   Obtener la lista de Sedes (CASES) disponibles para ser asignadas en operaciones
   (Ej: Programación de Cursos, Asignación de Instructores, Reportes).

   CASOS DE USO
   ------------
   - Dropdown "Seleccione Sede" en el formulario de creación de Cursos.
   - Filtros de búsqueda en reportes operativos.

   REGLAS DE NEGOCIO (EL CONTRATO)
   -------------------------------
   1. FILTRO DE ESTATUS PROPIO: 
      - Solo devuelve Sedes con `Activo = 1`.
      - Las Sedes dadas de baja lógica quedan ocultas para evitar errores operativos.

   2. FILTRO DE INTEGRIDAD JERÁRQUICA (CANDADO PADRE):
      - Una Sede solo es "seleccionable" si su Municipio padre TAMBIÉN está activo.
      - Lógica: "No puedes programar un curso en una Sede si la ciudad entera (Municipio) 
        está cerrada o inactiva en el sistema".
      - Esto evita inconsistencias donde se usa una ubicación geográfica prohibida.

   ORDENAMIENTO
   ------------
   - Alfabético por Nombre para facilitar la búsqueda visual rápida en el selector.

   RETORNO (DICCIONARIO)
   ---------------------
   - Id_CatCases_Sedes (Value del Option): El ID real para la FK.
   - Codigo (Texto auxiliar): Clave interna (ej: 'CASES-01').
   - Nombre (Label del Option): El nombre humano de la sede.
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ListarSedesActivas`$$
CREATE PROCEDURE `SP_ListarSedesActivas`()
BEGIN
    SELECT 
        `S`.`Id_CatCases_Sedes`, 
        `S`.`Codigo`, 
        `S`.`Nombre`
    FROM `Cat_Cases_Sedes` `S`
    
    /* JOIN ESTRATÉGICO: Validar el estatus del padre (Municipio) */
    INNER JOIN `Municipio` `Mun` 
        ON `S`.`Fk_Id_Municipio` = `Mun`.`Id_Municipio`
        
    WHERE 
        `S`.`Activo` = 1          /* La Sede debe estar operativa */
        AND `Mun`.`Activo` = 1    /* CANDADO: El Municipio debe estar operativo */
        
    ORDER BY 
        `S`.`Nombre` ASC;
END$$

DELIMITER ;

/* ============================================================================================
   SECCIÓN: LISTADOS PARA ADMINISTRACIÓN (TABLAS CRUD)
   ============================================================================================
   Estas rutinas son consumidas por los Paneles de Control (Grid/Tabla de Mantenimiento).
   Su objetivo es dar visibilidad total sobre el catálogo para auditoría, gestión y corrección.
   ============================================================================================ */

/* ============================================================================================
   PROCEDIMIENTO: SP_ListarSedesAdmin
   ============================================================================================
   OBJETIVO
   --------
   Obtener el inventario completo de Sedes (CASES), incluyendo identidad, ubicación y estatus,
   para alimentar el Panel de Administración (Grid CRUD).

   CASOS DE USO
   ------------
   - Pantalla principal del Módulo "Administrar Sedes/CASES".
   - Auditoría: Permite identificar qué sedes están operativas, cuáles están dadas de baja,
     y detectar registros con problemas de ubicación (huérfanos).

   DIFERENCIA CRÍTICA CON EL LISTADO OPERATIVO (DROPDOWN)
   ------------------------------------------------------
   1. SP_ListarSedesActivas (Dropdown): 
      - Filtra estrictamente `Activo = 1`.
      - Aplica "Candado Jerárquico": Oculta la Sede si su Municipio está inactivo.
   
   2. SP_ListarSedesAdmin (ESTE): 
      - Devuelve TODO (Activos e Inactivos).
      - IGNORA el candado del Municipio. El Administrador debe poder ver la Sede aunque su 
        municipio esté inactivo o roto, precisamente para poder entrar a editarla y arreglarla.

   ARQUITECTURA (USO DE VISTA)
   ---------------------------
   Se apoya en `Vista_Sedes` para:
   1. Abstraer la complejidad de los JOINs geográficos (Municipio -> Estado -> País).
   2. Seguridad de Visualización: La vista usa `LEFT JOIN`. Si una Sede tiene un ID de 
      municipio corrupto, la vista devuelve el registro con la ubicación en NULL.
      Esto garantiza que no existan "registros fantasma" invisibles para el administrador.

   ORDENAMIENTO ESTRATÉGICO
   ------------------------
   1. Por Estatus (DESC): Los Activos (1) aparecen primero para acceso rápido. 
      Los Inactivos (0) quedan al final.
   2. Por Nombre (ASC): Orden alfabético secundario para facilitar la búsqueda visual.

   RETORNO
   -------
   Devuelve todas las columnas proyectadas por `Vista_Sedes`:
   - Identidad: Id, Código (S/C), Nombre.
   - Ubicación Física: Dirección.
   - Ubicación Geográfica: Municipio, Estado, País.
   - Infraestructura: Capacidad Total (Resumen).
   - Metadatos: Estatus.
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ListarSedesAdmin`$$
CREATE PROCEDURE `SP_ListarSedesAdmin`()
BEGIN
    SELECT * FROM `Vista_Sedes` 
    ORDER BY 
        `Estatus_Sede` DESC,  -- Prioridad visual a lo operativo
        `Nombre_Sedes` ASC;
END$$

DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_EditarSede
   ============================================================================================
   OBJETIVO DE NEGOCIO
   -------------------
   Modificar la información integral de una Sede (CASES), permitiendo actualizar:
     - Identidad Administrativa (Código y Nombre).
     - Ubicación Geográfica (Mudanza de Municipio/Estado).
     - Capacidad Instalada (Actualización de inventario de Aulas, Botes, etc.).

   ARQUITECTURA DE INTEGRIDAD Y CONCURRENCIA
   -----------------------------------------
   1. BLOQUEO PESIMISTA (Pessimistic Locking):
      - Ejecutamos `SELECT ... FOR UPDATE` sobre el registro de la Sede al inicio de la transacción.
      - Esto "congela" la fila, impidiendo que otro administrador la elimine o edite 
        mientras nosotros validamos los nuevos datos.

   2. VALIDACIÓN GEOGRÁFICA ATÓMICA:
      - Aunque la Sede solo guarda `Fk_Id_Municipio`, el frontend envía la cadena completa:
        `Id_Pais`, `Id_Estado` e `Id_Municipio`.
      - Realizamos un `STRAIGHT_JOIN` de validación para asegurar que:
        a) El Municipio pertenece al Estado.
        b) El Estado pertenece al País.
        c) Los tres niveles están ACTIVOS (1).
      - Bloqueamos el Municipio destino para evitar que se desactive durante el guardado.

   3. INTEGRIDAD DE DUPLICADOS (Exclusión del Propio ID):
      - Verificamos unicidad Global del Código (`Uk_Codigo`).
      - Verificamos unicidad Global del Nombre (`Uk_Nombre`).
      - CRUCIAL: Siempre agregamos `AND Id_CatCases_Sedes <> _Id_Sede` en los checks.
        (Es legal que yo me llame igual a mí mismo, pero ilegal que me llame como mi vecino).

   4. MANEJO DE INVENTARIO (SANITIZACIÓN):
      - Si el usuario borra un input numérico en el frontend (envía NULL), 
        el SP lo convierte a `0` automáticamente antes de comparar o guardar.
      - Esto mantiene la integridad aritmética de la base de datos.

   5. DETECCIÓN DE "SIN CAMBIOS" (Idempotencia):
      - Comparamos TODOS los campos (Identidad + Ubicación + Inventario).
      - Si todo es idéntico, retornamos éxito inmediato sin tocar el disco duro (ahorro de I/O).

   6. MANEJO DE "RACE CONDITIONS" (Error 1062):
      - Si a pesar de los chequeos, otro usuario inserta un duplicado en el último milisegundo,
        el UPDATE fallará con error 1062.
      - Capturamos ese error y devolvemos una respuesta controlada ("CONFLICTO").

   RESULTADO
   ---------
   Retorna tabla con:
     - Mensaje: Feedback para usuario.
     - Accion: 'ACTUALIZADA', 'SIN_CAMBIOS', 'CONFLICTO'.
     - Datos de contexto para refrescar la UI.
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_EditarSede`$$
CREATE PROCEDURE `SP_EditarSede`(
    /* Identidad */
    IN _Id_Sede              INT,           -- ID del registro a editar
    IN _Nuevo_Codigo         VARCHAR(50),
    IN _Nuevo_Nombre         VARCHAR(255),
    IN _Nueva_Dir_Fisica     VARCHAR(255),  -- Puede ser NULL
    
    /* Ubicación (Para validación jerárquica) */
    IN _Nuevo_Id_Pais        INT, 
    IN _Nuevo_Id_Estado      INT, 
    IN _Nuevo_Id_Municipio   INT,           -- El dato real (FK)
    
    /* Infraestructura (Inventario - Si es NULL se asume 0) */
    IN _Cap_Total            INT,
    IN _Aulas                TINYINT,
    IN _Salas                TINYINT,
    IN _Alberca              TINYINT,
    IN _CampoPracticas       TINYINT,
    IN _Muelle               TINYINT,
    IN _BotesCap             TINYINT
)
SP: BEGIN
    /* ========================================================================================
       PARTE 0: VARIABLES DE ESTADO (SNAPSHOTS)
       ======================================================================================== */
    /* Variables para guardar la "foto" de cómo está el registro AHORA */
    DECLARE v_Cod_Act       VARCHAR(50);
    DECLARE v_Nom_Act       VARCHAR(255);
    DECLARE v_Dir_Act       VARCHAR(255);
    DECLARE v_Mun_Act       INT;
    
    /* Variables de Inventario Actual */
    DECLARE v_Cap_Act       INT;
    DECLARE v_Aulas_Act     TINYINT;
    DECLARE v_Salas_Act     TINYINT;
    DECLARE v_Alb_Act       TINYINT;
    DECLARE v_Camp_Act      TINYINT;
    DECLARE v_Muelle_Act    TINYINT;
    DECLARE v_Botes_Act     TINYINT;

    /* Variables de Control */
    DECLARE v_Existe        INT DEFAULT NULL;
    DECLARE v_DupId         INT DEFAULT NULL;
    DECLARE v_Dup           TINYINT(1) DEFAULT 0; -- Bandera 1062
    
    /* Para reporte de conflictos */
    DECLARE v_Id_Conflicto  INT DEFAULT NULL;
    DECLARE v_Campo_Error   VARCHAR(50) DEFAULT NULL;

    /* ========================================================================================
       PARTE 1: HANDLERS (CONTROL DE ERRORES)
       ======================================================================================== */
    
    /* 1062: Duplicate entry. No abortamos, marcamos bandera para manejarlo al final. */
    DECLARE CONTINUE HANDLER FOR 1062 SET v_Dup = 1;
    
    /* SQLEXCEPTION: Fallo técnico grave. Abortamos todo. */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;

    /* ========================================================================================
       PARTE 2: NORMALIZACIÓN Y SANITIZACIÓN
       ======================================================================================== */
    /* 2.1 Strings */
    SET _Nuevo_Codigo     = NULLIF(TRIM(_Nuevo_Codigo), '');
    SET _Nuevo_Nombre     = NULLIF(TRIM(_Nuevo_Nombre), '');
    SET _Nueva_Dir_Fisica = NULLIF(TRIM(_Nueva_Dir_Fisica), '');
    
    /* 2.2 IDs Geográficos (0 o negativos -> NULL) */
    IF _Nuevo_Id_Pais <= 0      THEN SET _Nuevo_Id_Pais = NULL;      END IF;
    IF _Nuevo_Id_Estado <= 0    THEN SET _Nuevo_Id_Estado = NULL;    END IF;
    IF _Nuevo_Id_Municipio <= 0 THEN SET _Nuevo_Id_Municipio = NULL; END IF;
    
    /* 2.3 Inventario (NULL -> 0) */
    /* Esta conversión es vital para poder comparar contra la BD (que tiene DEFAULT 0) */
    SET _Cap_Total      = IFNULL(_Cap_Total, 0);
    SET _Aulas          = IFNULL(_Aulas, 0);
    SET _Salas          = IFNULL(_Salas, 0);
    SET _Alberca        = IFNULL(_Alberca, 0);
    SET _CampoPracticas = IFNULL(_CampoPracticas, 0);
    SET _Muelle         = IFNULL(_Muelle, 0);
    SET _BotesCap       = IFNULL(_BotesCap, 0);

    /* ========================================================================================
       PARTE 3: VALIDACIONES BÁSICAS (FAIL FAST)
       ======================================================================================== */
    IF _Id_Sede IS NULL OR _Id_Sede <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA: ID de Sede inválido.';
    END IF;

    IF _Nuevo_Codigo IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN: El CÓDIGO es obligatorio.';
    END IF;

    IF _Nuevo_Nombre IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN: El NOMBRE es obligatorio.';
    END IF;

    IF _Nuevo_Id_Pais IS NULL OR _Nuevo_Id_Estado IS NULL OR _Nuevo_Id_Municipio IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN: La ubicación geográfica está incompleta.';
    END IF;

    /* ========================================================================================
       PARTE 4: INICIO DE TRANSACCIÓN
       ======================================================================================== */
    START TRANSACTION;

    /* ----------------------------------------------------------------------------------------
       PASO 1: LEER Y BLOQUEAR EL REGISTRO ACTUAL
       ----------------------------------------------------------------------------------------
       - `FOR UPDATE`: Bloqueamos la Sede para asegurar exclusividad en la edición.
       - Leemos TODOS los campos (incluyendo inventario) para la comparación "Sin Cambios". */
    
    SELECT 
        Codigo, Nombre, DescripcionDireccion, Fk_Id_Municipio,
        Capacidad_Total, Aulas, Salas, Alberca, CampoPracticas_Escenario, Muelle_Entrenamiento_Botes, BoteSalvavida_Capacidad
    INTO 
        v_Cod_Act, v_Nom_Act, v_Dir_Act, v_Mun_Act,
        v_Cap_Act, v_Aulas_Act, v_Salas_Act, v_Alb_Act, v_Camp_Act, v_Muelle_Act, v_Botes_Act
    FROM `Cat_Cases_Sedes`
    WHERE `Id_CatCases_Sedes` = _Id_Sede
    LIMIT 1
    FOR UPDATE;

    IF v_Cod_Act IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE CONCURRENCIA: La Sede que intenta editar ya no existe (fue eliminada por otro usuario).';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 2: VALIDACIÓN GEOGRÁFICA ATÓMICA
       ----------------------------------------------------------------------------------------
       - Verificamos que País -> Estado -> Municipio sea una cadena válida.
       - Bloqueamos el Municipio destino para que no se desactive mientras guardamos. */
    
    SET v_Existe = NULL;
    
    SELECT 1 INTO v_Existe
    FROM `Pais` P
    STRAIGHT_JOIN `Estado` E ON E.Fk_Id_Pais = P.Id_Pais
    STRAIGHT_JOIN `Municipio` M ON M.Fk_Id_Estado = E.Id_Estado
    WHERE P.Id_Pais = _Nuevo_Id_Pais       AND P.Activo = 1
      AND E.Id_Estado = _Nuevo_Id_Estado   AND E.Activo = 1
      AND M.Id_Municipio = _Nuevo_Id_Municipio AND M.Activo = 1
    LIMIT 1 
    FOR UPDATE; -- Bloqueo del municipio destino

    IF v_Existe IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE INTEGRIDAD: La ubicación seleccionada es incoherente o contiene elementos inactivos.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 3: DETECCIÓN DE "SIN CAMBIOS" (OPTIMIZACIÓN)
       ----------------------------------------------------------------------------------------
       - Comparamos valores actuales vs nuevos.
       - Usamos `<=>` para campos nulables (Dirección).
       - Comparamos todos los números del inventario. */
       
    IF v_Cod_Act = _Nuevo_Codigo 
       AND v_Nom_Act = _Nuevo_Nombre 
       AND (v_Dir_Act <=> _Nueva_Dir_Fisica) 
       AND v_Mun_Act = _Nuevo_Id_Municipio
       /* Comparación de Inventario */
       AND v_Cap_Act = _Cap_Total 
       AND v_Aulas_Act = _Aulas 
       AND v_Salas_Act = _Salas
       AND v_Alb_Act = _Alberca 
       AND v_Camp_Act = _CampoPracticas 
       AND v_Muelle_Act = _Muelle 
       AND v_Botes_Act = _BotesCap THEN
       
       COMMIT; -- Liberar locks
       SELECT 'No se detectaron cambios en la información.' AS Mensaje, 
              'SIN_CAMBIOS' AS Accion, 
              _Id_Sede AS Id_Sede;
       LEAVE SP;
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 4: PRE-CHECK DE DUPLICADOS (Excluyendo al propio ID)
       ---------------------------------------------------------------------------------------- */
    
    /* 4.1. Conflicto Global de CÓDIGO */
    SET v_DupId = NULL;
    
    SELECT `Id_CatCases_Sedes` INTO v_DupId FROM `Cat_Cases_Sedes`
    WHERE `Codigo` = _Nuevo_Codigo 
      AND `Id_CatCases_Sedes` <> _Id_Sede -- Excluirme a mí mismo
    LIMIT 1 FOR UPDATE;
    
    IF v_DupId IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE DUPLICIDAD: El CÓDIGO ingresado ya pertenece a otra Sede.';
    END IF;

    /* 4.2. Conflicto Global de NOMBRE */
    SET v_DupId = NULL;
    
    SELECT `Id_CatCases_Sedes` INTO v_DupId FROM `Cat_Cases_Sedes`
    WHERE `Nombre` = _Nuevo_Nombre 
      AND `Id_CatCases_Sedes` <> _Id_Sede -- Excluirme a mí mismo
    LIMIT 1 FOR UPDATE;
    
    IF v_DupId IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE DUPLICIDAD: El NOMBRE ingresado ya pertenece a otra Sede.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 5: EJECUCIÓN DEL UPDATE (CRÍTICO)
       ----------------------------------------------------------------------------------------
       - Reseteamos v_Dup a 0.
       - Actualizamos Identidad, Ubicación e Inventario. */
       
    SET v_Dup = 0;

    UPDATE `Cat_Cases_Sedes`
    SET `Codigo`               = _Nuevo_Codigo,
        `Nombre`               = _Nuevo_Nombre,
        `DescripcionDireccion` = _Nueva_Dir_Fisica,
        `Fk_Id_Municipio`      = _Nuevo_Id_Municipio,
        /* Actualización de Infraestructura */
        `Capacidad_Total`            = _Cap_Total,
        `Aulas`                      = _Aulas,
        `Salas`                      = _Salas,
        `Alberca`                    = _Alberca,
        `CampoPracticas_Escenario`   = _CampoPracticas,
        `Muelle_Entrenamiento_Botes` = _Muelle,
        `BoteSalvavida_Capacidad`    = _BotesCap,
        `updated_at`                 = NOW()
    WHERE `Id_CatCases_Sedes` = _Id_Sede;

    /* ----------------------------------------------------------------------------------------
       PASO 6: MANEJO DE CONCURRENCIA (SI HUBO ERROR 1062)
       ----------------------------------------------------------------------------------------
       - Si v_Dup = 1, el Handler saltó. Hacemos Rollback y diagnosticamos. */
       
    IF v_Dup = 1 THEN
        ROLLBACK;
        
        SET v_Id_Conflicto = NULL;
        
        /* Diagnóstico: ¿Fue el Código? */
        SELECT `Id_CatCases_Sedes` INTO v_Id_Conflicto FROM `Cat_Cases_Sedes`
        WHERE `Codigo` = _Nuevo_Codigo AND `Id_CatCases_Sedes` <> _Id_Sede LIMIT 1;
        
        IF v_Id_Conflicto IS NOT NULL THEN 
            SET v_Campo_Error = 'CODIGO';
        ELSE 
            /* Si no fue código, fue el Nombre */
            SET v_Campo_Error = 'NOMBRE';
            SELECT `Id_CatCases_Sedes` INTO v_Id_Conflicto FROM `Cat_Cases_Sedes`
            WHERE `Nombre` = _Nuevo_Nombre AND `Id_CatCases_Sedes` <> _Id_Sede LIMIT 1;
        END IF;

        SELECT 'Error de Concurrencia: Conflicto detectado al guardar.' AS Mensaje,
               'CONFLICTO' AS Accion, 
               v_Campo_Error AS Campo, 
               v_Id_Conflicto AS Id_Conflicto;
        LEAVE SP;
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 7: CONFIRMACIÓN EXITOSA
       ---------------------------------------------------------------------------------------- */
    COMMIT;
    
    SELECT 'Sede actualizada correctamente.' AS Mensaje, 
           'ACTUALIZADA' AS Accion, 
           _Id_Sede AS Id_Sede, 
           _Nuevo_Id_Municipio AS Id_Municipio_Nuevo;

END$$

DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_CambiarEstatusSede
   ============================================================================================
   OBJETIVO DE NEGOCIO
   -------------------
   Gestionar el Ciclo de Vida (Lifecycle) de una Sede (CASES) mediante el mecanismo de
   "Baja Lógica" (Soft Delete).
   
   Esto permite "apagar" una Sede sin eliminar su historial de cursos, pero evitando que
   se utilice en nuevas programaciones operativas.

   ARQUITECTURA DE INTEGRIDAD (EL MODELO DE "DOBLE CANDADO")
   ---------------------------------------------------------
   Este procedimiento implementa una defensa bidireccional para garantizar la coherencia
   de la base de datos ante cambios de estado:

   1. CANDADO ASCENDENTE (AL ACTIVAR - "UPSTREAM CHECK"):
      - Principio: "Una sucursal no puede operar si la ciudad está clausurada".
      - Regla de Negocio: Si intentas REACTIVAR una Sede (Activo=1), el sistema verifica 
        estrictamente que su MUNICIPIO Padre esté también ACTIVO.
      - Escenario evitado: Que aparezca disponible una Sede en un Municipio que la empresa
        ya cerró operativamente.

   2. CANDADO DESCENDENTE (AL DESACTIVAR - "DOWNSTREAM CHECK"):
      - Principio: "No puedes demoler la escuela con los alumnos adentro".
      - Regla de Negocio: Si intentas DESACTIVAR una Sede (Activo=0), el sistema debe verificar
        que NO existan cursos o capacitaciones programadas y activas en esa ubicación.
      - Escenario evitado: Cursos "huérfanos" cuya sede desaparece de los reportes, rompiendo
        la trazabilidad operativa.

   ESTRATEGIA DE CONCURRENCIA (BLOQUEO PESIMISTA / PESSIMISTIC LOCKING)
   --------------------------------------------------------------------
   - Problema: ¿Qué sucede si el Administrador A activa la Sede justo en el mismo milisegundo
     en que el Administrador B desactiva el Municipio? Se crearía una inconsistencia.
   - Solución: Utilizamos `SELECT ... FOR UPDATE` al inicio de la transacción.
   - Efecto: Esto "congela" (bloquea para escritura) tanto la fila de la Sede como la fila 
     del Municipio en una operación atómica. Esto serializa las transacciones y garantiza 
     que la decisión se tome siempre con datos frescos y estables.

   RETORNO
   -------
   Devuelve una tabla con:
     - Mensaje: Texto claro para la UI (Feedback de éxito o razón del bloqueo).
     - Activo_Anterior / Activo_Nuevo: Datos útiles para auditar el cambio o actualizar switches en UI.
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_CambiarEstatusSede`$$
CREATE PROCEDURE `SP_CambiarEstatusSede`(
    IN _Id_Sede       INT,     -- ID de la Sede a modificar
    IN _Nuevo_Estatus TINYINT  -- 1 = Activo (Visible), 0 = Inactivo (Oculto/Borrado Lógico)
)
BEGIN
    /* ========================================================================================
       PARTE 0: VARIABLES DE ESTADO Y CONTROL
       ======================================================================================== */
    /* Bandera para validar si el registro existe antes de proceder */
    DECLARE v_Existe INT DEFAULT NULL;
    
    /* Estado actual de la Sede (vital para verificar idempotencia: "Si ya está así, no hagas nada") */
    DECLARE v_Activo_Actual TINYINT(1) DEFAULT NULL;
    
    /* Contexto del Padre (Municipio) para aplicar el Candado Ascendente */
    DECLARE v_Id_Municipio INT DEFAULT NULL;
    DECLARE v_Municipio_Activo TINYINT(1) DEFAULT NULL;

    /* Auxiliar para búsqueda de dependencias (Hijos/Cursos) */
    DECLARE v_Tmp INT DEFAULT NULL;

    /* ========================================================================================
       PARTE 1: HANDLERS (MANEJO DE ERRORES TÉCNICOS)
       ======================================================================================== */
    /* Handler Genérico: Si ocurre cualquier error SQL (conexión, deadlock, sintaxis), 
       deshacemos cualquier cambio pendiente (ROLLBACK) y propagamos el error original (RESIGNAL) 
       para que el Backend sepa qué pasó. */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; 
    END;

    /* ========================================================================================
       PARTE 2: VALIDACIONES BÁSICAS (DEFENSIVE PROGRAMMING)
       ======================================================================================== */
    /* Evitamos abrir transacciones costosas si los parámetros de entrada son basura */
    IF _Id_Sede IS NULL OR _Id_Sede <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA: El ID de la Sede es inválido.';
    END IF;

    IF _Nuevo_Estatus NOT IN (0, 1) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA: Estatus inválido (solo se permite 0 o 1).';
    END IF;

    /* ========================================================================================
       PARTE 3: INICIO DE TRANSACCIÓN Y BLOQUEO
       ======================================================================================== */
    START TRANSACTION;

    /* ----------------------------------------------------------------------------------------
       PASO 1: LECTURA Y BLOQUEO DE CONTEXTO (SNAPSHOT)
       ----------------------------------------------------------------------------------------
       Aquí ocurre la magia de la concurrencia y la seguridad.
       1. Buscamos la Sede por su ID.
       2. Hacemos LEFT JOIN al Municipio (LEFT es más robusto por si la integridad referencial 
          estuviera rota en datos legacy).
       3. CLAUSULA `FOR UPDATE`: Esto es crítico. Bloquea las filas encontradas.
          - Nadie puede eliminar la Sede mientras decidimos.
          - Nadie puede desactivar el Municipio mientras decidimos. */
    
    SELECT 
        1,
        `S`.`Activo`, 
        `S`.`Fk_Id_Municipio`, 
        `Mun`.`Activo`
    INTO 
        v_Existe,
        v_Activo_Actual, 
        v_Id_Municipio, 
        v_Municipio_Activo
    FROM `Cat_Cases_Sedes` `S`
    LEFT JOIN `Municipio` `Mun` ON `S`.`Fk_Id_Municipio` = `Mun`.`Id_Municipio`
    WHERE `S`.`Id_CatCases_Sedes` = _Id_Sede 
    LIMIT 1
    FOR UPDATE;

    /* Verificación de existencia */
    IF v_Existe IS NULL THEN 
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO: La Sede solicitada no existe.'; 
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 2: IDEMPOTENCIA (OPTIMIZACIÓN "SIN CAMBIOS")
       ----------------------------------------------------------------------------------------
       Si el usuario pide "Activar" algo que ya está "Activo", no tiene sentido gastar
       recursos de base de datos (I/O, Logs de transacción). Retornamos éxito inmediato. */
    
    IF v_Activo_Actual = _Nuevo_Estatus THEN
        COMMIT; -- Liberamos los locks inmediatamente
        
        SELECT CASE 
            WHEN _Nuevo_Estatus = 1 THEN 'Sin cambios: La Sede ya se encontraba Activa.'
            ELSE 'Sin cambios: La Sede ya se encontraba Inactiva.'
        END AS Mensaje,
        v_Activo_Actual AS Activo_Anterior,
        _Nuevo_Estatus AS Activo_Nuevo;
        
    ELSE
        /* ====================================================================================
           SI EL ESTADO VA A CAMBIAR, EJECUTAMOS LAS REGLAS DE NEGOCIO (LOS CANDADOS)
           ==================================================================================== */

        /* ------------------------------------------------------------------------------------
           PASO 3: REGLA DE ACTIVACIÓN (CANDADO ASCENDENTE)
           "El hijo no puede vivir si el padre está muerto."
           ------------------------------------------------------------------------------------ */
        IF _Nuevo_Estatus = 1 THEN
            /* Verificamos el estado del Municipio Padre */
            IF v_Id_Municipio IS NOT NULL THEN
                /* Si el municipio existe pero está marcado como inactivo (0) -> BLOQUEO */
                IF v_Municipio_Activo = 0 THEN
                    SIGNAL SQLSTATE '45000' 
                        SET MESSAGE_TEXT = 'BLOQUEO JERÁRQUICO: No se puede ACTIVAR la Sede porque su MUNICIPIO está INACTIVO. Debe activar primero el Municipio correspondiente.';
                END IF;
            ELSE
                /* Caso borde: La Sede no tiene municipio (Integridad de datos rota).
                   Aunque la tabla tiene FK NOT NULL, si llegara a pasar (por manipulación directa),
                   impedimos la activación hasta que se arregle. */
                 SIGNAL SQLSTATE '45000' 
                        SET MESSAGE_TEXT = 'ERROR DE INTEGRIDAD: La Sede no tiene un Municipio válido asignado. Edite la Sede para corregir su ubicación antes de activarla.';
            END IF;
        END IF;

        /* ------------------------------------------------------------------------------------
           PASO 4: REGLA DE DESACTIVACIÓN (CANDADO DESCENDENTE)
           "No puedes cerrar la instalación si hay operaciones en curso."
           ------------------------------------------------------------------------------------ */
        IF _Nuevo_Estatus = 0 THEN
            SET v_Tmp = NULL;
            
            /* [NOTA DE ARQUITECTURA]: 
               Aquí se debe validar contra la tabla de `Capacitaciones` o `Cursos`.
               Como esa tabla se definirá en el siguiente sprint, dejamos la estructura lógica preparada.
               
               Lógica Futura:
               SELECT 1 INTO v_Tmp FROM `Cursos` WHERE `Fk_Id_Sede` = _Id_Sede AND `Estatus` = 'EN_CURSO' LIMIT 1;
               IF v_Tmp IS NOT NULL THEN SIGNAL ERROR... END IF;
            */
            
            /* Por el momento, si no hay hijos definidos, permitimos la desactivación */
        END IF;

        /* ------------------------------------------------------------------------------------
           PASO 5: EJECUCIÓN DEL CAMBIO (PERSISTENCIA)
           ------------------------------------------------------------------------------------
           Si pasamos todos los candados, procedemos a actualizar el registro. */
           
        UPDATE `Cat_Cases_Sedes` 
        SET `Activo` = _Nuevo_Estatus, 
            `updated_at` = NOW() -- Actualizamos la auditoría temporal
        WHERE `Id_CatCases_Sedes` = _Id_Sede;
        
        COMMIT; -- Confirmamos la transacción y liberamos locks
        
        /* ------------------------------------------------------------------------------------
           PASO 6: RESPUESTA FINAL AL CLIENTE
           ------------------------------------------------------------------------------------ */
        SELECT CASE 
            WHEN _Nuevo_Estatus = 1 THEN 'Sede Reactivada Exitosamente.'
            ELSE 'Sede Desactivada (Baja Lógica) Correctamente.'
        END AS Mensaje,
        v_Activo_Actual AS Activo_Anterior,
        _Nuevo_Estatus AS Activo_Nuevo;
        
    END IF;
END$$

DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_EliminarSedeFisica
   ============================================================================================
   AUTOR: Tu Equipo de Desarrollo / Gemini
   FECHA: 2026

   1. OBJETIVO DE NEGOCIO
   ----------------------
   Eliminar DEFINITIVAMENTE (Hard Delete) un registro del catálogo de Sedes (`Cat_Cases_Sedes`).
   Esta acción retira físicamente la fila de la base de datos, liberando espacio y referencias.

   2. ALCANCE Y RIESGOS (ADVERTENCIA)
   ----------------------------------
   - Tipo de Operación: DESTRUCTIVA e IRREVERSIBLE.
   - Caso de Uso: Mantenimiento correctivo (ej: eliminar un registro duplicado creado por error
     hoy mismo) o depuración administrativa.
   - Restricción: NO debe usarse para la operación diaria. Para retirar una Sede del uso común
     sin perder su historial, se debe usar `SP_CambiarEstatusSede` (Baja Lógica).

   3. ARQUITECTURA DE SEGURIDAD (INTEGRIDAD REFERENCIAL)
   -----------------------------------------------------
   Para evitar la corrupción de la base de datos ("Registros Huérfanos"), implementamos una
   defensa en capas:

   CAPA A: VALIDACIÓN MANUAL DE DEPENDENCIAS (Mejora de UX)
   - Antes de intentar borrar, el SP consulta proactivamente las tablas hijas críticas
     (como `Capacitaciones` o `Cursos`).
   - ¿Por qué? MySQL por defecto lanza un error genérico (Error 1451) si falla una FK.
     Validando manualmente, podemos devolver un mensaje específico: "No se puede borrar porque
     hay cursos programados", guiando al usuario a la solución correcta.

   CAPA B: HANDLER DE LLAVE FORÁNEA (Red de Seguridad)
   - Si se agregan nuevas tablas al sistema en el futuro (ej: `Inventario_Mobiliario`) y
     olvidamos actualizar este SP, el intento de borrado fallará a nivel de Motor de BD.
   - Implementamos un `DECLARE EXIT HANDLER FOR 1451` para atrapar ese error crítico,
     hacer ROLLBACK y devolver un mensaje controlado en lugar de una excepción de sistema.

   4. CONCURRENCIA Y ACID
   ----------------------
   - Atomicidad: Todo el proceso ocurre dentro de una `TRANSACCIÓN`. O se borra todo, o nada.
   - Bloqueo: Al ejecutar el `DELETE`, el motor InnoDB aplica automáticamente un "Row Lock"
     (Bloqueo de Fila) exclusivo, impidiendo que otros procesos lean o escriban en esa Sede
     hasta que confirmemos (COMMIT).

   RESULTADO
   ---------
   - Mensaje: Confirmación de éxito o explicación detallada del bloqueo.
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_EliminarSedeFisica`$$
CREATE PROCEDURE `SP_EliminarSedeFisica`(
    IN _Id_Sede INT  -- Identificador único de la Sede a eliminar
)
BEGIN
    /* ========================================================================================
       SECCIÓN 1: HANDLERS (MANEJO ROBUSTO DE EXCEPCIONES)
       ======================================================================================== */
    
    /* 1.1 HANDLER DE INTEGRIDAD REFERENCIAL (Error 1451)
       Objetivo: Actuar como "paracaídas" de seguridad.
       Escenario: Intentamos borrar la Sede, pero existe una tabla hija (desconocida o nueva)
       que tiene un registro apuntando a este ID. El motor de BD bloquea el borrado.
       Acción: Hacemos Rollback y traducimos el error técnico a un mensaje de negocio. */
    DECLARE EXIT HANDLER FOR 1451 
    BEGIN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'BLOQUEO DE INTEGRIDAD (FK): El sistema ha impedido el borrado porque existen registros históricos (probablemente Cursos, Inventarios o Bitácoras) vinculados a esta Sede. Utilice la opción "Desactivar" para mantener el historial.';
    END;

    /* 1.2 HANDLER GENÉRICO (SQLEXCEPTION)
       Objetivo: Capturar errores de infraestructura.
       Escenario: Fallo de disco, pérdida de conexión, timeout de transacción.
       Acción: Limpieza inmediata (Rollback) y re-lanzamiento del error para logs. */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; 
    END;

    /* ========================================================================================
       SECCIÓN 2: VALIDACIONES PREVIAS (DEFENSIVE PROGRAMMING)
       ======================================================================================== */
    
    /* 2.1 Validación de Parámetro
       Evitamos operaciones si el ID es nulo o negativo. */
    IF _Id_Sede IS NULL OR _Id_Sede <= 0 THEN
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'ERROR DE SISTEMA: El identificador de la Sede es inválido.';
    END IF;

    /* 2.2 Validación de Existencia (Fail Fast)
       Verificamos si el registro existe antes de verificar dependencias.
       Esto permite dar un mensaje de error preciso ("No existe") en lugar de uno confuso. */
    IF NOT EXISTS(SELECT 1 FROM `Cat_Cases_Sedes` WHERE `Id_CatCases_Sedes` = _Id_Sede) THEN
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'ERROR DE NEGOCIO: La Sede que intenta eliminar no existe en el catálogo.';
    END IF;

    /* ========================================================================================
       SECCIÓN 3: CANDADOS DE NEGOCIO (PRE-VALIDACIÓN DE DEPENDENCIAS)
       ========================================================================================
       Aquí implementamos la lógica de negocio para proteger la coherencia de los datos.
       Buscamos explícitamente en las tablas hijas conocidas. */
    
    /* [NOTA DE IMPLEMENTACIÓN FUTURA]
       Cuando se cree el módulo de "Programación de Cursos" o "Capacitaciones", 
       se debe descomentar y ajustar el siguiente bloque. 
       
       Objetivo: Si una Sede tiene Cursos (activos o pasados), NO se puede borrar, 
       porque los reportes de esos cursos fallarían al intentar mostrar dónde se impartieron.
    */
    
    /* IF EXISTS(SELECT 1 FROM `Capacitaciones` WHERE `Fk_Id_Sede` = _Id_Sede LIMIT 1) THEN
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'ERROR CRÍTICO: No se puede eliminar la Sede porque tiene historial de CAPACITACIONES asociadas. El borrado rompería los reportes históricos.';
    END IF;
    */

    /* ========================================================================================
       SECCIÓN 4: EJECUCIÓN DEL BORRADO (ZONA CRÍTICA)
       ========================================================================================
       Si el flujo llega a este punto, significa que:
       1. El registro existe.
       2. No tiene dependencias bloqueantes conocidas.
       Es seguro proceder con la destrucción del dato. */
    
    START TRANSACTION;
    
    /* Ejecutamos el DELETE.
       - En este momento, InnoDB adquiere un bloqueo exclusivo (X-Lock) sobre la fila.
       - Si hubiese una FK oculta no detectada arriba, aquí saltará el Handler 1451. */
    DELETE FROM `Cat_Cases_Sedes` 
    WHERE `Id_CatCases_Sedes` = _Id_Sede;
    
    /* Confirmamos los cambios de forma permanente */
    COMMIT;

    /* ========================================================================================
       SECCIÓN 5: RESPUESTA
       ======================================================================================== */
    SELECT 'La Sede ha sido eliminada permanentemente de la base de datos.' AS Mensaje;

END$$

DELIMITER ;