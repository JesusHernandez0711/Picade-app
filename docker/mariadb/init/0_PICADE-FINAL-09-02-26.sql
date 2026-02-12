-- MySQL Workbench Forward Engineering
-- DROP DATABASE IF EXISTS `PICADE`;

SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0;
SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0;
SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='ONLY_FULL_GROUP_BY,STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION';

-- -----------------------------------------------------
-- Schema PICADE
-- -----------------------------------------------------
-- -----------------------------------------------------
-- Schema PICADE
-- -----------------------------------------------------
CREATE SCHEMA IF NOT EXISTS `PICADE` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_spanish_ci; ;
USE `PICADE` ;

-- -----------------------------------------------------
-- Table `PICADE`.`Pais`
/* TABLA DE PAISES EXISTENTES, EL ADMINSISTRADOR PODRA HACER USO DE UN CRUD PARA CONSULTAR/REGISTRAR/ACTUALIZAR/DESACTIVAR O ELIMINAR DEFINITIVAMENTE*/
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `PICADE`.`Pais` (
  `Id_Pais` INT NOT NULL AUTO_INCREMENT,
  `Codigo` VARCHAR(50) NOT NULL,
  `Nombre` VARCHAR(255) NOT NULL,
  `Activo` TINYINT(1) NOT NULL DEFAULT 1,	-- 1 = Visible, 0 = Borrado Lógico
  `created_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP(),
  `updated_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP() ON UPDATE CURRENT_TIMESTAMP(),
  PRIMARY KEY (`Id_Pais`),
  -- BLINDAJE 1: El código (ej: 'MEX') no puede repetirse en toda la tabla
 CONSTRAINT `Uk_Codigo_Pais` UNIQUE (`Codigo`),
  -- BLINDAJE 2: El nombre (ej: 'MEXICO') no puede repetirse en toda la tabla
  CONSTRAINT `Uk_Nombre_Pais` UNIQUE (`Nombre`),
  -- Validación de integridad para el campo booleano
  CONSTRAINT `Check_Activo_Pais` CHECK (`Activo` IN (0, 1))
) ENGINE = InnoDB 
DEFAULT CHARACTER SET = utf8mb4 
COLLATE = utf8mb4_spanish_ci;

-- -----------------------------------------------------
-- Table `PICADE`.`Estado`
/* TABLA DE ESTADOS EXISTENTES ASIGNADOS A UN PAIS DE LA TABLA PAIS, EL ADMINSISTRADOR PODRA HACER USO DE UN CRUD PARA 
CONSULTAR/REGISTRAR/ACTUALIZAR/DESACTIVAR O ELIMINAR DEFINITIVAMENTE*/
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `PICADE`.`Estado` (
  `Id_Estado` INT NOT NULL AUTO_INCREMENT,
  `Codigo` VARCHAR(50) NOT NULL,
  `Nombre` VARCHAR(255) NOT NULL,
  `Fk_Id_Pais` INT NOT NULL,	-- Llave foránea hacia País
  `Activo` TINYINT(1) NOT NULL DEFAULT 1,	-- 1 = Visible, 0 = Borrado Lógico
  `created_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP(),
  `updated_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP() ON UPDATE CURRENT_TIMESTAMP(),
  PRIMARY KEY (`Id_Estado`),
	-- BLINDAJE 1: No repetir Código en el mismo País (ej: 'BC' en México solo una vez)
  CONSTRAINT `Uk_Estado_Codigo_Pais` UNIQUE (`Codigo`, `Fk_Id_Pais`),
	-- BLINDAJE 2: No repetir Nombre en el mismo País (ej: 'TABASCO' en México solo una vez)
  CONSTRAINT `Uk_Estado_Nombre_Pais` UNIQUE (`Nombre`, `Fk_Id_Pais`),
	-- Validación de integridad para el campo booleano
  CONSTRAINT `Check_Activo_Estado` CHECK (`Activo` IN (0, 1)),
  INDEX `Idx_Perf_Edo_Pais` (`Fk_Id_Pais`),
	-- Para Listar Estados por País (Filtrando solo activos)
	INDEX `Idx_Perf_Estado_Pais_Activo` (`Fk_Id_Pais`, `Activo`),
  CONSTRAINT `Fk_Id_Pais_Estado`
    FOREIGN KEY (`Fk_Id_Pais`)
    REFERENCES `PICADE`.`Pais` (`Id_Pais`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION
) ENGINE = InnoDB 
DEFAULT CHARACTER SET = utf8mb4 
COLLATE = utf8mb4_spanish_ci;

-- -----------------------------------------------------
-- Table `PICADE`.`Municipio`
/* TABLA DE MUNICIPIOS EXISTENTES ASIGNADOS A UN ESTADO DE LA TABLA ESTADO, EL ADMINSISTRADOR PODRA HACER USO DE UN CRUD PARA 
CONSULTAR/REGISTRAR/ACTUALIZAR/DESACTIVAR O ELIMINAR DEFINITIVAMENTE*/
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `PICADE`.`Municipio` (
  `Id_Municipio` INT NOT NULL AUTO_INCREMENT,
  `Codigo` VARCHAR(50) NULL,	-- Puede ser NULL si no tiene clave oficial
  `Nombre` VARCHAR(255) NOT NULL,
  `Fk_Id_Estado` INT NOT NULL,	-- Llave foránea hacia Estado
  `Activo` TINYINT(1) NOT NULL DEFAULT 1,	-- 1 = Visible, 0 = Borrado Lógico
  `created_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP(),
  `updated_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP() ON UPDATE CURRENT_TIMESTAMP(),
  PRIMARY KEY (`Id_Municipio`),
	-- BLINDAJE 1: No repetir Código en el mismo Estado (ej: '001' en Tabasco solo una vez)
  CONSTRAINT `Uk_Municipio_Codigo_Estado` UNIQUE (`Codigo`, `Fk_Id_Estado`),
	-- BLINDAJE 2: No repetir Nombre en el mismo Estado (ej: 'CENTRO' en Tabasco solo una vez)
  CONSTRAINT `Uk_Municipio_Estado` UNIQUE (`Nombre`, `Fk_Id_Estado`),
    -- Validación de integridad para el campo booleano
  CONSTRAINT `Check_Activo_Municipio` CHECK (`Activo` IN (0, 1)),
	INDEX `Idx_Perf_Mun_Edo` (`Fk_Id_Estado`),
    -- Para Listar Municipios por Estado (Filtrando solo activos)
	INDEX `Idx_Perf_Municipio_Estado_Activo` (`Fk_Id_Estado`, `Activo`),
  CONSTRAINT `Fk_Id_Estado_Municipio`
    FOREIGN KEY (`Fk_Id_Estado`)
    REFERENCES `PICADE`.`Estado` (`Id_Estado`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION
) ENGINE = InnoDB 
DEFAULT CHARACTER SET = utf8mb4 
COLLATE = utf8mb4_spanish_ci;

-- -----------------------------------------------------
-- Table `PICADE`.`Centros_Trabajo`
/* CATALOGO DE CENTROS DE TRABAJO EXISTENTES EN LA EMPRESA PEMEX, NORMALMENTE PERTENECEN A UN DEPARTAMENTO PERO LA MAYORIA NO TIENE ASIGNADA UNA 
ACTUALMENTE POR LO QUE SE MANEJA APARTE POR EL MOMENTO PARA SU POSTERIOR IMPLEMENTACION, EL ADMINSISTRADOR PODRA HACER USO DE UN CRUD PARA 
CONSULTAR/REGISTRAR/ACTUALIZAR/DESACTIVAR O ELIMINAR DEFINITIVAMENTE*/
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `PICADE`.`Cat_Centros_Trabajo` (
  `Id_CatCT` INT NOT NULL AUTO_INCREMENT,
  `Codigo` VARCHAR(50) NOT NULL,
  `Nombre` VARCHAR(255) NOT NULL,
  `Direccion_Fisica` VARCHAR(255) NULL,
  `Fk_Id_Municipio_CatCT` INT NULL,
  `Activo` TINYINT(1) NOT NULL DEFAULT 1,
  `created_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP(),
  `updated_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP() ON UPDATE CURRENT_TIMESTAMP(),
  PRIMARY KEY (`Id_CatCT`),
	/* BLINDAJE 1: El Código es único en todo el universo PEMEX */
  CONSTRAINT `Uk_Codigo_CatCT` UNIQUE (`Codigo`),
	/* BLINDAJE 2: El Nombre no se repite en el mismo Municipio 
     (Ej: Solo un "HOSPITAL REGIONAL" en "VILLAHERMOSA") */
  CONSTRAINT `Uk_Nombre_Municipio_CT` UNIQUE (`Nombre`, `Fk_Id_Municipio_CatCT`),
	-- Validación de integridad para el campo booleano
  CONSTRAINT `Check_Activo_CatCT` CHECK (`Activo` IN (0, 1)),
  INDEX `Idx_Perf_CT_Mun` (`Fk_Id_Municipio_CatCT`),
  CONSTRAINT `Fk_Id_Municipio_CatCT`
    FOREIGN KEY (`Fk_Id_Municipio_CatCT`)
    REFERENCES `PICADE`.`Municipio` (`Id_Municipio`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION
) ENGINE = InnoDB 
DEFAULT CHARACTER SET = utf8mb4 
COLLATE = utf8mb4_spanish_ci;

-- -----------------------------------------------------
-- Table `PICADE`.`Cat_Departamentos`
/* CATALOGO DE DEPARTAMENTOS EXISTENTES EN LA EMPRESA PEMEX, NORMALMENTE PERTENECEN A UNA GERENCIA PERO LA MAYORIA NO TIENE ASIGNADA UNA ACTUALMENTE
POR LO QUE SE MANEJA APARTE POR EL MOMENTO PARA SU POSTERIOR IMPLEMENTACION, EL ADMINSISTRADOR PODRA HACER USO DE UN CRUD PARA 
CONSULTAR/REGISTRAR/ACTUALIZAR/DESACTIVAR O ELIMINAR DEFINITIVAMENTE*/
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `PICADE`.`Cat_Departamentos` (
  `Id_CatDep` INT NOT NULL AUTO_INCREMENT,
  `Codigo` VARCHAR(50) NOT NULL,
  `Nombre` VARCHAR(255) NOT NULL,
  /* NUEVO CAMPO: Para calle, número, colonia, etc. */
  `Direccion_Fisica` VARCHAR(255) NULL,
  `Fk_Id_Municipio_CatDep` INT NULL,
  `Activo` TINYINT(1) NOT NULL DEFAULT 1,
  `created_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP(),
  `updated_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP() ON UPDATE CURRENT_TIMESTAMP(),
  PRIMARY KEY (`Id_CatDep`),
	-- CONSTRAINT `Uk_Codigo_CatDep` UNIQUE (`Codigo`),
	/* Ponemos: La Triple Restricción */
  CONSTRAINT `Uk_Identidad_Departamento` UNIQUE (`Codigo`, `Nombre`, `Fk_Id_Municipio_CatDep`),
  	-- Validación de integridad para el campo booleano
  CONSTRAINT `Check_Activo_CatDep` CHECK (`Activo` IN (0, 1)),
	INDEX `Idx_Perf_Dep_Mun` (`Fk_Id_Municipio_CatDep`),
	-- Optimiza SP_ListarDepActivos
	INDEX `Idx_Perf_Depto_Orden` (`Activo`, `Nombre`),
  CONSTRAINT `Fk_Id_Municipio_CatDep`
    FOREIGN KEY (`Fk_Id_Municipio_CatDep`)
    REFERENCES `PICADE`.`Municipio` (`Id_Municipio`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION
) ENGINE = InnoDB 
DEFAULT CHARACTER SET = utf8mb4 
COLLATE = utf8mb4_spanish_ci;

-- -----------------------------------------------------
-- Table `PICADE`.`Cat_Direcciones`
/* CATALOGO DE DIRECCIONES EXISTENTES EN LA EMPRESA PEMEX, EL ADMINSISTRADOR PODRA HACER USO DE UN CRUD PARA CONSULTAR/REGISTRAR/ACTUALIZAR/DESACTIVAR 
O ELIMINAR DEFINITIVAMENTE*/
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `PICADE`.`Cat_Direcciones` (
  `Id_CatDirecc` INT NOT NULL AUTO_INCREMENT,
  `Clave` VARCHAR(50) NULL,
  `Nombre` VARCHAR(255) NOT NULL,
  `Activo` TINYINT(1) NOT NULL DEFAULT 1,
  `created_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP(),
  `updated_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP() ON UPDATE CURRENT_TIMESTAMP(),
  PRIMARY KEY (`Id_CatDirecc`),
    -- BLINDAJE 1: El código (ej: 'MEX') no puede repetirse en toda la tabla
 CONSTRAINT `Uk_Clave_CatDirecc` UNIQUE (`Clave`),
  -- BLINDAJE 2: El nombre (ej: 'MEXICO') no puede repetirse en toda la tabla
  CONSTRAINT `Uk_Nombre_CatDirecc` UNIQUE (`Nombre`),
  -- Validación de integridad para el campo booleano
  CONSTRAINT `Check_Activo_CatDirecc` CHECK (`Activo` IN (0, 1))
) ENGINE = InnoDB 
DEFAULT CHARACTER SET = utf8mb4 
COLLATE = utf8mb4_spanish_ci;

-- -----------------------------------------------------
-- Table `PICADE`.`Subdirecciones`
/* CATALOGO DE SUBDIRECCIONES ASIGNADAS A UNA GERENCIA EN LA EMPRESA PEMEX, EL ADMINSISTRADOR PODRA HACER USO DE UN CRUD PARA CONSULTAR/REGISTRAR/ACTUALIZAR/DESACTIVAR 
O ELIMINAR DEFINITIVAMENTE*/
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `PICADE`.`Cat_Subdirecciones` (
  `Id_CatSubDirec` INT NOT NULL AUTO_INCREMENT,
  `Fk_Id_CatDirecc` INT NOT NULL,
  `Clave` VARCHAR(50) NULL,
  `Nombre` VARCHAR(255) NOT NULL,
  `Activo` TINYINT(1) NOT NULL DEFAULT 1,
  `created_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP(),
  `updated_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP() ON UPDATE CURRENT_TIMESTAMP(),
  PRIMARY KEY (`Id_CatSubDirec`),
	-- BLINDAJE 1: El código (ej: 'STEP') no puede repetirse en toda la tabla
  CONSTRAINT `Uk_CatSubDirec_Clave_CatDirecc` UNIQUE (`Clave`,`Fk_Id_CatDirecc`),
	-- BLINDAJE 2: El nombre (ej: 'SUBDIRECCION TECNICA DE EXPLORACION Y EXTRACCION') no puede repetirse en toda la tabla
  CONSTRAINT `Uk_CatSubDirec_Nombre_CatDirecc` UNIQUE (`Nombre`, `Fk_Id_CatDirecc`),
	-- Validación de integridad para el campo booleano
  CONSTRAINT `Check_Activo_CatSubDirec` CHECK (`Activo` IN (0, 1)),
	INDEX `Idx_Perf_Sub_Dir` (`Fk_Id_CatDirecc`),
	-- Para Listar Subdirecciones por Dirección
	INDEX `Idx_Perf_Sub_Dir_Activo` (`Fk_Id_CatDirecc`, `Activo`),
  CONSTRAINT `Fk_Id_Direccion_CatSubDirec`
    FOREIGN KEY (`Fk_Id_CatDirecc`)
    REFERENCES `PICADE`.`Cat_Direcciones` (`Id_CatDirecc`)
	ON DELETE NO ACTION
    ON UPDATE NO ACTION
) ENGINE = InnoDB 
DEFAULT CHARACTER SET = utf8mb4 
COLLATE = utf8mb4_spanish_ci;

-- -----------------------------------------------------
-- Table `PICADE`.`Cat_Gerencias_Activos`
/* CATALOGO DE GERENCIAS ASIGNADAS A UNA SUBGERENCIA EN LA EMPRESA PEMEX, EL ADMINSISTRADOR PODRA HACER USO DE UN CRUD PARA CONSULTAR/REGISTRAR/ACTUALIZAR/DESACTIVAR 
O ELIMINAR DEFINITIVAMENTE*/
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `PICADE`.`Cat_Gerencias_Activos` (
  `Id_CatGeren` INT NOT NULL AUTO_INCREMENT,
  `Fk_Id_CatSubDirec` INT NOT NULL,
  `Clave` VARCHAR(50) NULL,
  `Nombre` VARCHAR(255) NOT NULL,
  `Activo` TINYINT(1) NOT NULL DEFAULT 1,
  `created_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP(),
  `updated_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP() ON UPDATE CURRENT_TIMESTAMP(),
  PRIMARY KEY (`Id_CatGeren`),
	-- BLINDAJE 1: El código (ej: 'GATEE') no puede repetirse en toda la tabla
  CONSTRAINT `Uk_CatGeren_Clave_CatSubDirec` UNIQUE (`Clave`,`Fk_Id_CatSubDirec`),
	-- BLINDAJE 2: El nombre (ej: 'GERENCIA DE ASEGURAMIENTO TECNICO DE EXPLORACION Y EXTRACCION') no puede repetirse en toda la tabla
  CONSTRAINT `Uk_CatGeren_Nombre_CatSubDirec` UNIQUE (`Nombre`, `Fk_Id_CatSubDirec`),
	-- Validación de integridad para el campo booleano
  CONSTRAINT `Check_Activo_CatGeren` CHECK (`Activo` IN (0, 1)),
	INDEX `Idx_Perf_Ger_Sub` (`Fk_Id_CatSubDirec`),
	-- Para Listar Gerencias por Subdirección
	INDEX `Idx_Perf_Geren_Sub_Activo` (`Fk_Id_CatSubDirec`, `Activo`),
  CONSTRAINT `Fk_Id_CatSubDirec_CatGeren`
    FOREIGN KEY (`Fk_Id_CatSubDirec`)
    REFERENCES `PICADE`.`Cat_Subdirecciones` (`Id_CatSubDirec`)
	ON DELETE NO ACTION
    ON UPDATE NO ACTION
) ENGINE = InnoDB 
DEFAULT CHARACTER SET = utf8mb4 
COLLATE = utf8mb4_spanish_ci;

-- -----------------------------------------------------
-- Table `PICADE`.`Cat_Regimenes_Trabajo`
/* CATALOGOS DE REGIMENES DE TRABAJO EXISTENTES EN LA EMPRESA PEMEX, EL ADMINSISTRADOR PODRA HACER USO DE UN CRUD PARA CONSULTAR/REGISTRAR/ACTUALIZAR/DESACTIVAR 
O ELIMINAR DEFINITIVAMENTE*/
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `PICADE`.`Cat_Regimenes_Trabajo` (
  `Id_CatRegimen` INT NOT NULL AUTO_INCREMENT,
  `Codigo` VARCHAR(50) NULL,  -- Nuevo Campo (Obligatorio y Único
  `Nombre` VARCHAR(255) NOT NULL,
  `Descripcion` VARCHAR(255) NULL,
  `Activo` TINYINT(1) NOT NULL DEFAULT 1,
  `created_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP(),
  `updated_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP() ON UPDATE CURRENT_TIMESTAMP(),
  PRIMARY KEY (`Id_CatRegimen`),
	-- BLINDAJE 1: El código (ej: 'CONF') no puede repetirse en toda la tabla
  CONSTRAINT `Uk_Codigo_CatRegimen` UNIQUE (`Codigo`),
	-- BLINDAJE 2: El nombre (ej: 'REGIMEN DE CONFIANZA') no puede repetirse en toda la tabla
  CONSTRAINT `Uk_Nombre_CatRegimen` UNIQUE (`Nombre`),
	-- Validación de integridad para el campo booleano
  CONSTRAINT `Check_Activo_CatRegimen` CHECK (`Activo` IN (0, 1)),
	-- Optimiza SP_ListarRegimenesActivos
	INDEX `Idx_Perf_Regimen_Orden` (`Activo`, `Nombre`)
) ENGINE = InnoDB 
DEFAULT CHARACTER SET = utf8mb4 
COLLATE = utf8mb4_spanish_ci;

-- -----------------------------------------------------
-- Table `PICADE`.`Cat_Regiones`
/* CATALOGO DE REGIONES EXISTENTES EN LA EMPRESA PEMEX, EL ADMINSISTRADOR PODRA HACER USO DE UN CRUD PARA CONSULTAR/REGISTRAR/ACTUALIZAR/DESACTIVAR 
O ELIMINAR DEFINITIVAMENTE*/
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `PICADE`.`Cat_Regiones_Trabajo` (
  `Id_CatRegion` INT NOT NULL AUTO_INCREMENT,
  `Codigo` VARCHAR(50) NULL,  -- Nuevo Campo (Obligatorio y Único
  `Nombre` VARCHAR(255) NOT NULL,
  `Descripcion` VARCHAR(255) NULL,
  `Activo` TINYINT(1) NOT NULL DEFAULT 1,
  `created_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP(),
  `updated_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP() ON UPDATE CURRENT_TIMESTAMP(),
  PRIMARY KEY (`Id_CatRegion`),
  	-- BLINDAJE 1: El código (ej: 'Altamira') no puede repetirse en toda la tabla
  CONSTRAINT `Uk_Codigo_CatRegion` UNIQUE (`Codigo`),
	-- BLINDAJE 2: El nombre (ej: 'Region Alramira') no puede repetirse en toda la tabla
  CONSTRAINT `Uk_Nombre_CatRegion` UNIQUE (`Nombre`),
  	-- Validación de integridad para el campo booleano
  CONSTRAINT `Check_Activo_CatRegion` CHECK (`Activo` IN (0, 1)),
	-- Optimiza SP_ListarCTActivos
	INDEX `Idx_Perf_CT_Orden` (`Activo`, `Nombre`)
) ENGINE = InnoDB 
DEFAULT CHARACTER SET = utf8mb4 
COLLATE = utf8mb4_spanish_ci;

-- -----------------------------------------------------
-- Table `PICADE`.`Cat_PuestosTrabajo`
/* CATALOGO DE PUESTOS DE TRABAJO EXISTENTES EN LA EMPRESA PEMEX, NORMALMENTE PERTENECEN A UN CENTRO DE TRABAJO PERO LA MAYORIA NO TIENE ASIGNADO 
UNO ACTUALMENTE POR LO QUE SE MANEJA APARTE POR EL MOMENTO PARA SU POSTERIOR IMPLEMENTACION, EL ADMINSISTRADOR PODRA HACER USO DE UN CRUD PARA 
CONSULTAR/REGISTRAR/ACTUALIZAR/DESACTIVAR O ELIMINAR DEFINITIVAMENTE*/
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `PICADE`.`Cat_Puestos_Trabajo` (
  `Id_CatPuesto` INT NOT NULL AUTO_INCREMENT,
  `Codigo` VARCHAR(50) NULL,  -- Nuevo Campo (Obligatorio y Único
  `Nombre` VARCHAR(255) NOT NULL,
  `Descripcion` VARCHAR(255) NULL,
  `Activo` TINYINT(1) NOT NULL DEFAULT 1,
  `created_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP(),
  `updated_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP() ON UPDATE CURRENT_TIMESTAMP(),
  PRIMARY KEY (`Id_CatPuesto`),
  	-- BLINDAJE 1: El código (ej: 'ET "A"') no puede repetirse en toda la tabla
  CONSTRAINT `Uk_Codigo_CatPuesto` UNIQUE (`Codigo`),
	-- BLINDAJE 2: El nombre (ej: 'Especialista Tecnico "A"') no puede repetirse en toda la tabla
  CONSTRAINT `Uk_Nombre_CatPuesto` UNIQUE (`Nombre`),
  	-- Validación de integridad para el campo booleano
  CONSTRAINT `Check_Activo_CatPuesto` CHECK (`Activo` IN (0, 1)),
	-- Optimiza SP_ListarPuestosActivos
	INDEX `Idx_Perf_Puesto_Orden` (`Activo`, `Nombre`)
) ENGINE = InnoDB 
DEFAULT CHARACTER SET = utf8mb4 
COLLATE = utf8mb4_spanish_ci;

-- -----------------------------------------------------
-- Table `PICADE`.`Info_Personal`
/* TABLA DE ALMACENAMIENTO DE LOS DATOS PERSONALES DE CADA USUARIO Y TIENE UNA RELACION 1:1 CON ELLA PARA SU CONSULTA/REGISTRO/ACTUALIZACION O DESACTIVACION
POR EL PROPIO USUARIO O EL ADMINISTRADOR*/
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `PICADE`.`Info_Personal` (
  `Id_InfoPersonal` INT NOT NULL AUTO_INCREMENT,
  `Nombre` VARCHAR(255) NOT NULL,
  `Apellido_Paterno` VARCHAR(255) NOT NULL,
  `Apellido_Materno` VARCHAR(255) NOT NULL,
  -- `CURP` VARCHAR(21) NULL,
  -- `RFC` VARCHAR(21) NULL,
  `Fecha_Nacimiento` DATE NULL,
  `Fecha_Ingreso` DATE NULL,
  `Fk_Id_CatRegimen` INT NULL,
  `Fk_Id_CatPuesto` INT NULL,
  `Fk_Id_CatCT` INT NULL,
  `Fk_Id_CatDep` INT NULL,
  `Fk_Id_CatRegion` INT NULL,
  `Fk_Id_CatGeren` INT NULL,
  `Nivel` VARCHAR(50) NULL,
  `Clasificacion` VARCHAR(100) NULL,
  `Activo` TINYINT(1) NOT NULL DEFAULT 1,
  `Fk_Id_Usuario_Created_By` INT NULL,
  `Fk_Id_Usuario_Updated_By` INT NULL,
  `created_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP(),
  `updated_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP() ON UPDATE CURRENT_TIMESTAMP(),
  PRIMARY KEY (`Id_InfoPersonal`),
	/* Restricciones */
	/* Ponemos: La Cuadruple Restricción:
		Esta restricción será usada para evitar que cualquier persona Registre un usuario nuevo 2 o más veces */
  CONSTRAINT `Uk_Huella_Humana` UNIQUE (`Nombre`, `Apellido_Paterno`, `Apellido_Materno`, `Fecha_Nacimiento`),
	-- Validación de integridad para el campo booleano
  CONSTRAINT `Check_Activo_InfoPersonal` CHECK (`Activo` IN (0, 1)),
	/* Índices */
    INDEX `Idx_Busqueda_Apellido` (`Apellido_Paterno`, `Apellido_Materno`, `Nombre`),
	-- INDEX `Idx_DatosPersonas_NombreCompleto` (`Nombre`, `Apellido_Paterno`, `Apellido_Materno`),
	INDEX `Idx_Id_CatRegimen_InfoPersonal` (`Fk_Id_CatRegimen`),
	INDEX `Idx_Id_CatPuesto_InfoPersonal` (`Fk_Id_CatPuesto`),
	INDEX `Idx_Id_CatCT_InfoPersonal` (`Fk_Id_CatCT`),
	INDEX `Idx_Id_CatDep_InfoPersonal` (`Fk_Id_CatDep`),
	INDEX `Idx_Id_CatRegion_InfoPersonal` (`Fk_Id_CatRegion`),
	INDEX `Idx_Id_CatGeren_InfoPersonal` (`Fk_Id_CatGeren`),
	/* Llaves Foráneas de Catálogos (Resumido) */
  CONSTRAINT `Fk_Id_CatRegimen_InfoPersonal`
    FOREIGN KEY (`Fk_Id_CatRegimen`)
    REFERENCES `PICADE`.`Cat_Regimenes_Trabajo` (`Id_CatRegimen`)
	ON DELETE NO ACTION
    ON UPDATE NO ACTION,
  CONSTRAINT `Fk_Id_CatPuesto_InfoPersonal`
    FOREIGN KEY (`Fk_Id_CatPuesto`)
    REFERENCES `PICADE`.`Cat_Puestos_Trabajo` (`Id_CatPuesto`)
	ON DELETE NO ACTION
    ON UPDATE NO ACTION,
  CONSTRAINT `Fk_Id_CatCT_InfoPersonal`
    FOREIGN KEY (`Fk_Id_CatCT`)
    REFERENCES `PICADE`.`Cat_Centros_Trabajo` (`Id_CatCT`)
	ON DELETE NO ACTION
    ON UPDATE NO ACTION,
  CONSTRAINT `Fk_Id_CatDep_InfoPersonal`
    FOREIGN KEY (`Fk_Id_CatDep`)
    REFERENCES `PICADE`.`Cat_Departamentos` (`Id_CatDep`)
	ON DELETE NO ACTION
    ON UPDATE NO ACTION,
  CONSTRAINT `Fk_Id_CatRegion_InfoPersonal`
    FOREIGN KEY (`Fk_Id_CatRegion`)
    REFERENCES `PICADE`.`Cat_Regiones_Trabajo` (`Id_CatRegion`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION,
  CONSTRAINT `Fk_Id_CatGeren_InfoPersonal`
    FOREIGN KEY (`Fk_Id_CatGeren`)
    REFERENCES `PICADE`.`Cat_Gerencias_Activos` (`Id_CatGeren`)
	ON DELETE NO ACTION
    ON UPDATE NO ACTION,
    /* --- NUEVA LLAVE FORÁNEA DE AUDITORÍA --- */
  CONSTRAINT `Fk_InfoPersonal_CreatedBy` 
    FOREIGN KEY (`Fk_Id_Usuario_Created_By`) 
    REFERENCES `PICADE`.`Usuarios` (`Id_Usuario`)
	ON DELETE SET NULL 
    ON UPDATE CASCADE,
    CONSTRAINT `Fk_InfoPersonal_UpdatedBy`
    FOREIGN KEY (`Fk_Id_Usuario_Updated_By`)
    REFERENCES `Usuarios`(`Id_Usuario`)
    ON DELETE SET NULL 
    ON UPDATE CASCADE
) ENGINE = InnoDB 
DEFAULT CHARACTER SET = utf8mb4 
COLLATE = utf8mb4_spanish_ci;

-- -----------------------------------------------------
-- Table `PICADE`.`Roles`
/* TABLA DE LOS ROLES EXISTENTES EN EL SISTEMA QUE MANEJARAN LOS PERMISOS Y LAS VISTAS DE CADA USUARIO,
EL ADMINISTRADOR PODRA HACER USO DE UN CRUD PARA CONSULTAR/REGISTRAR/ACTUALIZAR/DESACTIVAR 
O ELIMINAR DEFINITIVAMENTE DE UN USUARIO*/
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `PICADE`.`Cat_Roles` (
  `Id_Rol` INT NOT NULL AUTO_INCREMENT,
  `Codigo` VARCHAR(50) NULL,  -- Nuevo Campo (Obligatorio y Único
  `Nombre` VARCHAR(255) NOT NULL,
  `Descripcion` VARCHAR(255) NULL,
  `Activo` TINYINT(1) NOT NULL DEFAULT 1,
  `created_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP(),
  `updated_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP() ON UPDATE CURRENT_TIMESTAMP(),
  PRIMARY KEY (`Id_Rol`),
  	-- BLINDAJE 1: El código (ej: 'Admin') no puede repetirse en toda la tabla
  CONSTRAINT `Uk_Codigo_Rol` UNIQUE (`Codigo`),
    -- BLINDAJE 2: El nombre (ej: 'Administrador') no puede repetirse en toda la tabla
  CONSTRAINT `Uk_Nombre_Rol` UNIQUE (`Nombre`),
  	-- Validación de integridad para el campo booleano
  CONSTRAINT `Check_Activo_Rol` CHECK (`Activo` IN (0, 1))
) ENGINE = InnoDB 
DEFAULT CHARACTER SET = utf8mb4 
COLLATE = utf8mb4_spanish_ci;

-- -----------------------------------------------------
-- Table `PICADE`.`Usuarios`
/* TABLA DE REGISTRO DE LOS USUARIOS LIGADA A LA INFORMACION DE USUARIO Y POR LA CUAL SE LLEVARA EL CONTROL DE SABER QUE PERSONA HA IMPARTIDO 
UNA CAPACITACION O HA SIDO PARTICIPANTE EN ELLA ASI, CONTIENE EL ROL QUE TENDRA EL USUARIO Y LE LLEVARA A LAS VISTAS MANEJADAS POR EL FRAMEWORK,
CADA USUARIO TIENE UNA RELACION 1:1 CON LA TABLA InfoPersonal PORQUE UNA PERSONA SOLO PODRA TENER UN USUARIO UNICO Y SE IDENTIFICARA POR SU
FICHA DE USUARIO UNICA*/
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `PICADE`.`Usuarios` (
  `Id_Usuario` INT NOT NULL AUTO_INCREMENT,
  `Ficha` VARCHAR(50) NOT NULL,
  `Email` VARCHAR(255) NOT NULL,
  `Foto_Perfil_Url` VARCHAR(255) NULL DEFAULT NULL,
  `Contraseña` VARCHAR(255) NOT NULL,
  `Fk_Id_InfoPersonal` INT NOT NULL,
  `Fk_Rol` INT NOT NULL DEFAULT 4,
  `Activo` TINYINT(1) NOT NULL DEFAULT 1,
  /* Auditoría */
  `Fk_Usuario_Created_By` INT NULL,
  `Fk_Usuario_Updated_By` INT NULL,
  `created_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP(),
  `updated_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP() ON UPDATE CURRENT_TIMESTAMP(),
  -- 👇 AGREGA ESTA COLUMNA (Es tipo TIMESTAMP y acepta NULL)
  `email_verified_at` TIMESTAMP NULL DEFAULT NULL,  
  -- 👇 AQUÍ ESTÁ LA LÍNEA MÁGICA. AL SER 'NULL', NO ROMPE EL CSV NI LOS SPs.
  `remember_token` VARCHAR(255) NULL,
  PRIMARY KEY (`Id_Usuario`),
    /* Restricciones */
	-- BLINDAJE 1: La ficha (ej: '316211') no puede repetirse en toda la tabla
  CONSTRAINT `Uk_Ficha_Usuarios` UNIQUE (`Ficha`),
	-- BLINDAJE 2: El Correo electronico (ej: 'NORMA.ALICIA.TORRES@PEMEX.COM') no puede repetirse en toda la tabla
  CONSTRAINT `Uk_Email_Usuarios` UNIQUE (`Email`),
	-- Validación de integridad para el campo booleano
  CONSTRAINT `Check_Activo_Usuarios` CHECK (`Activo` IN (0, 1)),
    /* Índices */
	-- INDEX `Idx_Usuario_Email` (`Email`),
	INDEX `Idx_Id_InfoPersonal_Usuario` (`Fk_Id_InfoPersonal`),
	INDEX `Idx_Id_Rol_Usuario` (`Fk_Rol`),
	/* Permite filtrar rápido: "Dame todos los Admins Activos" */
	INDEX `Idx_Perf_Rol_Activo` (`Fk_Rol`, `Activo`),
    /* Llaves Foráneas de Catálogos y Relaciones */
  CONSTRAINT `Fk_Id_InfoPersonal_Usuario`
    FOREIGN KEY (`Fk_Id_InfoPersonal`)
    REFERENCES `PICADE`.`Info_Personal` (`Id_InfoPersonal`)
	ON DELETE NO ACTION
    ON UPDATE NO ACTION,
  CONSTRAINT `Fk_Id_Rol_Usuario`
    FOREIGN KEY (`Fk_Rol`)
    REFERENCES `PICADE`.`Cat_Roles` (`Id_Rol`)
	ON DELETE NO ACTION
    ON UPDATE NO ACTION,
  CONSTRAINT `Fk_Usuario_CreatedBy`
	FOREIGN KEY (`Fk_Usuario_Created_By`) 
    REFERENCES `Usuarios`(`Id_Usuario`)
    ON DELETE SET NULL 
    ON UPDATE CASCADE,
    CONSTRAINT `Fk_Usuarios_UpdatedBy`
    FOREIGN KEY (`Fk_Usuario_Updated_By`) REFERENCES `Usuarios`(`Id_Usuario`)
    ON DELETE SET NULL 
    ON UPDATE CASCADE
) ENGINE = InnoDB 
DEFAULT CHARACTER SET = utf8mb4 
COLLATE = utf8mb4_spanish_ci;

-- -----------------------------------------------------
-- Table `PICADE`.`Cat_Estatus_Capacitacion`
/* CATALOGO DE LOS ESTATUS QUE PUEDE TENER UNA CAPACITACION, EL ADMINSISTRADOR PODRA HACER USO DE UN CRUD PARA CONSULTAR/REGISTRAR/ACTUALIZAR/DESACTIVAR 
O ELIMINAR DEFINITIVAMENTE*/
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `PICADE`.`Cat_Estatus_Capacitacion` (
  `Id_CatEstCap` INT NOT NULL AUTO_INCREMENT,
  `Codigo` VARCHAR(50) NULL,  -- Nuevo Campo (Obligatorio y Único
  `Nombre` VARCHAR(255) NOT NULL,
  `Descripcion` VARCHAR(255) NULL,
  `Es_Final` TINYINT(1) NOT NULL DEFAULT 0,
  `Activo` TINYINT(1) NOT NULL DEFAULT 1,
  `created_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP(),
  `updated_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP() ON UPDATE CURRENT_TIMESTAMP(),
  PRIMARY KEY (`Id_CatEstCap`),
  	-- BLINDAJE 1: El código (ej: 'Fin') no puede repetirse en toda la tabla
  CONSTRAINT `Uk_Codigo_CatEstCap` UNIQUE (`Codigo`),
	-- BLINDAJE 2: El nombre (ej: 'Finalizado') no puede repetirse en toda la tabla
  CONSTRAINT `Uk_Nombre_CatEstCap` UNIQUE (`Nombre`),
	/* 1. Validar que Es_Final solo sea 0 o 1 */
  CONSTRAINT `Check_EsFinal_CatEstCap` CHECK (`Es_Final` IN (0, 1)),
	/* 2. Validar que Activo solo sea 0 o 1 */
  CONSTRAINT `Check_Activo_CatEstCap` CHECK (`Activo` IN (0, 1))
) ENGINE = InnoDB 
DEFAULT CHARACTER SET = utf8mb4 
COLLATE = utf8mb4_spanish_ci;

-- -----------------------------------------------------
-- Table `PICADE`.`Cat_Modalidad_Capacitacion`
/* CATALOGO DE MODALIDAD DE LAS CAPACITACIONES, EL ADMINSISTRADOR PODRA HACER USO DE UN CRUD PARA CONSULTAR/REGISTRAR/ACTUALIZAR/DESACTIVAR 
O ELIMINAR DEFINITIVAMENTE*/
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `PICADE`.`Cat_Modalidad_Capacitacion` (
  `Id_CatModalCap` INT NOT NULL AUTO_INCREMENT,
  `Codigo` VARCHAR(50) NULL,  -- Nuevo Campo (Obligatorio y Único
  `Nombre` VARCHAR(255) NOT NULL,
  `Descripcion` VARCHAR(255) NULL,
  `Activo` TINYINT(1) NOT NULL DEFAULT 1,
  `created_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP(),
  `updated_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP() ON UPDATE CURRENT_TIMESTAMP(),
  PRIMARY KEY (`Id_CatModalCap`),
  	-- BLINDAJE 1: El código (ej: 'Online') no puede repetirse en toda la tabla
  CONSTRAINT `Uk_Codigo_CatModalCap` UNIQUE (`Codigo`),
	-- BLINDAJE 2: El nombre (ej: 'Modalidad Vitual') no puede repetirse en toda la tabla
  CONSTRAINT `Uk_Nombre_CatModalCap` UNIQUE (`Nombre`),
  	-- Validación de integridad para el campo booleano
  CONSTRAINT `Check_Activo_CatModalCap` CHECK (`Activo` IN (0, 1))
) ENGINE = InnoDB 
DEFAULT CHARACTER SET = utf8mb4 
COLLATE = utf8mb4_spanish_ci;

-- -----------------------------------------------------
-- Table `PICADE`.`Cat_Cases_Sedes`
/* CATALOGO DE SEDES O CENTROS DE ADIESTRAMIENTO, SEGURIDAD ECOLOGIA Y SUPERVIVENCIA USADOS PARA LAS CAPACITACIONES,
EL ADMINSISTRADOR PODRA HACER USO DE UN CRUD PARA CONSULTAR/REGISTRAR/ACTUALIZAR/DESACTIVAR ELIMINAR DEFINITIVAMENTE*/
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `PICADE`.`Cat_Cases_Sedes` (
  `Id_CatCases_Sedes` INT NOT NULL AUTO_INCREMENT,
  `Codigo` VARCHAR(50) NULL,
  `Nombre` VARCHAR(255) NOT NULL,
	/* 2. INFRAESTRUCTURA (Inventario Variable)
     - TINYINT UNSIGNED: Acepta números de 0 a 255 (no negativos).
     - NOT NULL DEFAULT 0: Si el usuario no captura nada (ej: no tiene alberca), 
       se guarda un 0 automáticamente. Esto soluciona tu problema de variedad. */
  `Aulas`                      TINYINT UNSIGNED NOT NULL DEFAULT 0,
  `Salas`                      TINYINT UNSIGNED NOT NULL DEFAULT 0,
  `Alberca`                    TINYINT UNSIGNED NOT NULL DEFAULT 0,
  `CampoPracticas_Escenario`   TINYINT UNSIGNED NOT NULL DEFAULT 0,
  `Muelle_Entrenamiento_Botes` TINYINT UNSIGNED NOT NULL DEFAULT 0,
  `BoteSalvavida_Capacidad`    TINYINT UNSIGNED NOT NULL DEFAULT 0,
	/* Capacidad Total: Puede ser la suma de lo anterior o un dato manual */
  `Capacidad_Total`            INT UNSIGNED NOT NULL DEFAULT 0,
  `DescripcionDireccion` VARCHAR(255) NULL,
  `Fk_Id_Municipio` INT NOT NULL,
  `Activo` TINYINT(1) NOT NULL DEFAULT 1,
  `created_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP(),
  `updated_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP() ON UPDATE CURRENT_TIMESTAMP(),
  PRIMARY KEY (`Id_CatCases_Sedes`),
	/* A) UNICIDAD GLOBAL: No puede repetirse el Código en toda la tabla */
  	/* BLINDAJE 1: El Código es único en todo el universo CASES_EL_CASTAÑO */
  CONSTRAINT `Uk_Codigo_CatCases_Sedes` UNIQUE (`Codigo`),
	/* B) UNICIDAD GLOBAL: No puede repetirse el Nombre en toda la tabla */
  	/* BLINDAJE 2: El Nombre no se repite en el universo
     (Ej: Solo un "CENTRO DE ADIESTRAMIENTO EN SEGURIDAD ECOLOGIA Y SOBREVIVENCIA EL CASTAÑO") */
  CONSTRAINT `Uk_Nombre_CatCases_Sedes` UNIQUE (`Nombre`),
	-- Validación de integridad para el campo booleano
  CONSTRAINT `Check_Activo_CatCases_Sedes` CHECK (`Activo` IN (0, 1)),
  CONSTRAINT `Fk_Id_Municipio_CatCases_Sedes`
    FOREIGN KEY (`Fk_Id_Municipio`)
    REFERENCES `PICADE`.`Municipio` (`Id_Municipio`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION
) ENGINE = InnoDB 
DEFAULT CHARACTER SET = utf8mb4 
COLLATE = utf8mb4_spanish_ci;

-- -----------------------------------------------------
-- Table `PICADE`.`Cat_Tipos_Instruccion_Cap`
/* CATALOGO DE TIPOS DE CAPACITACIONES POSIBLES A REALIZAR, EL ADMINSISTRADOR PODRA HACER USO DE UN CRUD PARA CONSULTAR/REGISTRAR/ACTUALIZAR/DESACTIVAR 
O ELIMINAR DEFINITIVAMENTE*/
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `PICADE`.`Cat_Tipos_Instruccion_Cap` (
  `Id_CatTipoInstCap` INT NOT NULL AUTO_INCREMENT,
  `Nombre` VARCHAR(255) NOT NULL,
  `Descripcion` VARCHAR(255) NULL,
  `Activo` TINYINT(1) NOT NULL DEFAULT 1,
  `created_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP(),
  `updated_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP() ON UPDATE CURRENT_TIMESTAMP(),
  PRIMARY KEY (`Id_CatTipoInstCap`),
  CONSTRAINT `Uk_Nombre_CatTipoInstCap` UNIQUE (`Nombre`),
  	-- Validación de integridad para el campo booleano
  CONSTRAINT `Check_Activo_CatTipoInstCap` CHECK (`Activo` IN (0, 1))
  	-- INDEX `Idx_Nombre_CatTipoInstCap` (`Nombre`)
) ENGINE = InnoDB 
DEFAULT CHARACTER SET = utf8mb4 
COLLATE = utf8mb4_spanish_ci;

-- -----------------------------------------------------
-- Table `PICADE`.`Cat_Temas_Capacitacion`
/* CATALOGO DE CAPACITACIONES QUE SE PUEDEN LLEVAR A CABO, EL ADMINSISTRADOR PODRA HACER USO DE UN CRUD PARA CONSULTAR/REGISTRAR/ACTUALIZAR/DESACTIVAR 
O ELIMINAR DEFINITIVAMENTE*/
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `PICADE`.`Cat_Temas_Capacitacion` (
  `Id_Cat_TemasCap` INT NOT NULL AUTO_INCREMENT,
  `Codigo` VARCHAR(50) NULL,
  `Nombre` VARCHAR(255) NOT NULL,
  `Descripcion` VARCHAR(255) NULL,
  /* SMALLINT UNSIGNED: 
     1. Evita negativos (UNSIGNED).
     2. Permite hasta 65,535 horas (TINYINT solo llega a 255).
     3. DEFAULT 0: Facilita sumas en reportes (evita NULL + 5 = NULL). */
  `Duracion_Horas` SMALLINT UNSIGNED NULL DEFAULT NULL,
  `Fk_Id_CatTipoInstCap` INT NULL,
  `Activo` TINYINT(1) NOT NULL DEFAULT 1,
  `created_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP(),
  `updated_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP() ON UPDATE CURRENT_TIMESTAMP(),
  PRIMARY KEY (`Id_Cat_TemasCap`),
  CONSTRAINT `Uk_Nombre_Cat_TemasCap` UNIQUE (`Nombre`),
  CONSTRAINT `Check_Activo_Cat_TemasCap` CHECK (`Activo` IN (0, 1)),
	INDEX `Idx_Id_Id_CatTipoInstCap_Cat_TemasCap` (`Fk_Id_CatTipoInstCap`),
  CONSTRAINT `Fk_Id_Id_CatTipoInstCap_Cat_TemasCap`
    FOREIGN KEY (`Fk_Id_CatTipoInstCap`)
    REFERENCES `PICADE`.`Cat_Tipos_Instruccion_Cap` (`Id_CatTipoInstCap`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION
) ENGINE = InnoDB 
DEFAULT CHARACTER SET = utf8mb4 
COLLATE = utf8mb4_spanish_ci;

-- -----------------------------------------------------
-- Table `PICADE`.`Capacitaciones`
/* TABLA DE REGISTRO DE NUEVAS CAPACITACIONES SE USA PARA REGISTRAR UNA NUEVA CAPACITACION Y INICIAR EL HISTORIAL DE ESTA PARA MAS TARDE HACERLES
CAMBIO CON LA TABLA DEL HISTORIAL DE CAPACITACIONES Y PODER LLEVAR UN REGISTRO CON CUALES DATOS FUERON REGISTRADOS Y CUALES FUERON LOS REALES ESTO
PARA CUANDO SE GENERE EL REPORTE SACAR ESTADISTICAS Y GRAFICAS DE ESTAS*/
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `PICADE`.`Capacitaciones` (
  `Id_Capacitacion` INT NOT NULL AUTO_INCREMENT,
  `Numero_Capacitacion` VARCHAR(50) NOT NULL,
  `Fk_Id_CatGeren` INT NOT NULL,
  `Fk_Id_Cat_TemasCap` INT NOT NULL,
  `Asistentes_Programados` INT NOT NULL,
  `Activo` TINYINT(1) NOT NULL DEFAULT 1,
  `Fk_Id_Usuario_Cap_Created_by` INT NULL,
  `Fk_Id_Usuario_Cap_Updated_by` INT NULL,
  `created_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP(),
  `updated_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP() ON UPDATE CURRENT_TIMESTAMP(),
  PRIMARY KEY (`Id_Capacitacion`),
  CONSTRAINT `Uk_NumeroCapacitacion_Cap` UNIQUE (`Numero_Capacitacion`),
  CONSTRAINT `Check_Activo_Cap` CHECK (`Activo` IN (0, 1)),
	INDEX `Idx_Id_CatGeren_Cap` (`Fk_Id_CatGeren`),
	INDEX `Idx_Id_Cat_TemasCap_Cap` (`Fk_Id_Cat_TemasCap`),
	INDEX `Idx_Id_Usuario_Create_Cap` (`Fk_Id_Usuario_Cap_Created_by`),
	INDEX `Idx_Id_Usuario_Update_Cap` (`Fk_Id_Usuario_Cap_Updated_by`),
  CONSTRAINT `Fk_Id_CatGeren_Cap`
    FOREIGN KEY (`Fk_Id_CatGeren`)
    REFERENCES `PICADE`.`Cat_Gerencias_Activos` (`Id_CatGeren`)
	ON DELETE NO ACTION
    ON UPDATE NO ACTION,
  CONSTRAINT `Fk_Id_Cat_TemasCap_Cap`
    FOREIGN KEY (`Fk_Id_Cat_TemasCap`)
    REFERENCES `PICADE`.`Cat_Temas_Capacitacion` (`Id_Cat_TemasCap`)
	ON DELETE NO ACTION
    ON UPDATE NO ACTION,
  CONSTRAINT `Fk_Id_Usuario_Created_Cap`
    FOREIGN KEY (`Fk_Id_Usuario_Cap_Created_by`)
    REFERENCES `PICADE`.`Usuarios` (`Id_Usuario`)
    ON DELETE SET NULL 
    ON UPDATE CASCADE,
  CONSTRAINT `Fk_Id_Usuario_Updated_Cap`
    FOREIGN KEY (`Fk_Id_Usuario_Cap_Updated_by`)
    REFERENCES `PICADE`.`Usuarios` (`Id_Usuario`)
    ON DELETE SET NULL 
    ON UPDATE CASCADE
) ENGINE = InnoDB 
DEFAULT CHARACTER SET = utf8mb4 
COLLATE = utf8mb4_spanish_ci;

-- -----------------------------------------------------
-- Table `PICADE`.`DatosCapacitaciones`
/* TABLA INTERMEDIA PARA ALMACENAR EL HISTORIAL LAS CAPACITACIONES, SE USA PARA LLEVAR UN CONTROL DE QUE CAMBIOS SE HAN REALIZADO DESDE SU REGISTRO
INICIAL POR LOS CAMBIOS QUE SE PUEDEN HACER, DESDE CAMBIAR AL INSTRUCTOR, FECHAS DE INICIO Y FINALIZACION,
LA UBICACION DONDE SE IMPARTIRA, LA MODALIDAD, CAMBIAR EL ESTATUS EN EL QUE SE ENCUENTRA, ASIGNAR UN NUMERO DE ASISTENTES REALES PARA CONTRASTAR
CONTRA LOS QUE FUERON REGISTRADOS INICIALMENTE, Y LAS OBSERVACIONES EN CADA CAMBIO REALIZADO.
*/
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `PICADE`.`DatosCapacitaciones` (
  `Id_DatosCap` INT NOT NULL AUTO_INCREMENT,
  `Fk_Id_Capacitacion` INT NOT NULL,
  `Fk_Id_Instructor` INT NOT NULL,
  `Fecha_Inicio` DATE NOT NULL,
  `Fecha_Fin` DATE NOT NULL,
  `Fk_Id_CatCases_Sedes` INT NOT NULL,
  `Fk_Id_CatModalCap` INT NOT NULL,
  `Fk_Id_CatEstCap` INT NOT NULL,
  `AsistentesReales` TINYINT (3) NULL,
  `Observaciones` VARCHAR(255) NULL,
  `Activo` TINYINT(1) NOT NULL DEFAULT 1,
  `Fk_Id_Usuario_DatosCap_Created_by` INT NULL,
  `Fk_Id_Usuario_DatosCap_Updated_by` INT NULL,
  `created_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP(),
  `updated_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP() ON UPDATE CURRENT_TIMESTAMP(),
  PRIMARY KEY (`Id_DatosCap`),
  CONSTRAINT `Check_Fechas_Validas`
	CHECK (`Fecha_Inicio` <= `Fecha_Fin`),
  CONSTRAINT `Check_Activo_DatosCap` CHECK (`Activo` IN (0, 1)),
	INDEX `Idx_Id_Capacitacion_DatosCap` (`Fk_Id_Capacitacion`),
	INDEX `Idx_Id_Instructor_DatosCap` (`Fk_Id_Instructor`),
	INDEX `Idx_Fechas_DatosCap` (`Fecha_Inicio`, `Fecha_Fin`),
	INDEX `Idx_Id_CatCases_Sedes_DatosCap` (`Fk_Id_CatCases_Sedes`),
	INDEX `Idx_Id_CatModalCap_DatosCap` (`Fk_Id_CatModalCap`),
	INDEX `Idx_Id_CatEstCap_DatosCap` (`Fk_Id_CatEstCap`),
	INDEX `Idx_Id_Usuario_Create_DatosCap` (`Fk_Id_Usuario_DatosCap_Created_by`),
	INDEX `Idx_Id_Usuario_Update_DatosCap` (`Fk_Id_Usuario_DatosCap_Updated_by`),
	-- Buscar capacitaciones por Instructor y Fecha (Saber qué cursos dio alguien)
	INDEX `Idx_Perf_Instructor_Fechas` (`Fk_Id_Instructor`, `Fecha_Inicio`),
	-- Buscar capacitaciones por Rango de Fechas (Para reportes mensuales)
	-- (Nota: Ya tenías un índice de fechas, pero este ayuda a filtrar por Estatus también)
	INDEX `Idx_Perf_Cap_Fechas_Estatus` (`Activo`, `Fecha_Inicio`, `Fecha_Fin`),
  CONSTRAINT `Fk_Id_Capacitacion_DatosCap`
    FOREIGN KEY (`Fk_Id_Capacitacion`)
    REFERENCES `PICADE`.`Capacitaciones` (`Id_Capacitacion`)
	ON DELETE NO ACTION
    ON UPDATE NO ACTION,
  CONSTRAINT `Fk_Id_Instructor_DatosCap`
    FOREIGN KEY (`Fk_Id_Instructor`)
    REFERENCES `PICADE`.`Usuarios` (`Id_Usuario`)
	ON DELETE NO ACTION
    ON UPDATE NO ACTION,
  CONSTRAINT `Fk_Id_CatCases_Sedes_DatosCap`
    FOREIGN KEY (`Fk_Id_CatCases_Sedes`)
    REFERENCES `PICADE`.`Cat_Cases_Sedes` (`Id_CatCases_Sedes`)
	ON DELETE NO ACTION
    ON UPDATE NO ACTION,
  CONSTRAINT `Fk_Id_CatModalCap_DatosCap`
    FOREIGN KEY (`Fk_Id_CatModalCap`)
    REFERENCES `PICADE`.`Cat_Modalidad_Capacitacion` (`Id_CatModalCap`)
	ON DELETE NO ACTION
    ON UPDATE NO ACTION,
  CONSTRAINT `Fk_Id_CatEstCap_DatosCap`
    FOREIGN KEY (`Fk_Id_CatEstCap`)
    REFERENCES `PICADE`.`Cat_Estatus_Capacitacion` (`Id_CatEstCap`)
	ON DELETE NO ACTION
    ON UPDATE NO ACTION,
  CONSTRAINT `Fk_Id_Usuario_Created_DatosCap`
    FOREIGN KEY (`Fk_Id_Usuario_DatosCap_Created_by`)
    REFERENCES `PICADE`.`Usuarios` (`Id_Usuario`)
    ON DELETE SET NULL 
    ON UPDATE CASCADE,
  CONSTRAINT `Fk_Id_Usuario_Updated_DatosCap`
    FOREIGN KEY (`Fk_Id_Usuario_DatosCap_Updated_by`)
    REFERENCES `PICADE`.`Usuarios` (`Id_Usuario`)
	ON DELETE SET NULL 
    ON UPDATE CASCADE
) ENGINE = InnoDB 
DEFAULT CHARACTER SET = utf8mb4 
COLLATE = utf8mb4_spanish_ci;

-- -----------------------------------------------------
-- Table `PICADE`.`Cat_Estatus_Participante`
/* CATALOGO DE LOS TIPOS DE ESTATUS EXISTENTES PARA TABLA INTERMEDIA DEL HISTORIAL DE CAPACITACIONES DE LOS ASISTENTES A ESTAS,
EL ADMINISTRADOR PODRA HACER USO DE UN CRUD PARA CONSULTAR/REGISTRAR/ACTUALIZAR/DESACTIVAR O ELIMINAR DEFINITIVAMENTE*/
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `PICADE`.`Cat_Estatus_Participante` (
  `Id_CatEstPart` INT NOT NULL AUTO_INCREMENT,
  `Codigo` VARCHAR(50) NULL,  -- Nuevo Campo (Obligatorio y Único
  `Nombre` VARCHAR(255) NOT NULL,
  `Descripcion` VARCHAR(255) NULL,
  `Activo` TINYINT(1) NOT NULL DEFAULT 1,
  `created_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP(),
  `updated_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP() ON UPDATE CURRENT_TIMESTAMP(),
  PRIMARY KEY (`Id_CatEstPart`),
  	-- BLINDAJE 1: El código (ej: 'N/A') no puede repetirse en toda la tabla
  CONSTRAINT `Uk_Codigo_CatEstPart` UNIQUE (`Codigo`),
      -- BLINDAJE 2: El nombre (ej: 'No Aprobado') no puede repetirse en toda la tabla
  CONSTRAINT `Uk_Nombre_CatEstPart` UNIQUE (`Nombre`),
  	-- Validación de integridad para el campo booleano
  CONSTRAINT `Check_Activo_CatEstPart` CHECK (`Activo` IN (0, 1))
) ENGINE = InnoDB 
DEFAULT CHARACTER SET = utf8mb4 
COLLATE = utf8mb4_spanish_ci;

-- -----------------------------------------------------
-- Table `PICADE`.`Capacitaciones_Participantes`
/* TABLA INTERMEDIA PARA ALMACENAR LAS RELACIONES ENTRE USUARIOS Y LAS CAPACITACIONES A LAS QUE HAN ASISTIDO COMO CAPACITADOS,
CONTIENE LOS DATOS COMO SU PORCENTAJE DE ASISTENCIA, CALIFICACION FINAL Y EL ESTATUS EN QUE SE ENCUENTRA SU PROCESO,
DE ESTA SE PODRA CONSULTAR SU HISTORIAL
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `PICADE`.`Capacitaciones_Participantes` (
  `Id_CapPart` INT NOT NULL AUTO_INCREMENT,
  `Fk_Id_DatosCap` INT NOT NULL,
  `Fk_Id_Usuario` INT NOT NULL,
  `Fk_Id_CatEstPart` INT NOT NULL,
  `PorcentajeAsistencia` DECIMAL(5,2) NULL DEFAULT NULL,
  `Calificacion` DECIMAL(5,2) NULL DEFAULT NULL,
  `created_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP(),
  `updated_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP() ON UPDATE CURRENT_TIMESTAMP(),
  PRIMARY KEY (`Id_CapPart`),
  CONSTRAINT `Uk_DatosCap_Usuario_CapPart` UNIQUE (`Fk_Id_DatosCap`, `Fk_Id_Usuario`),
  CONSTRAINT `Check_Porcentaje_Valido`
	CHECK (`PorcentajeAsistencia` >= 0 
    AND `PorcentajeAsistencia` <= 100),
	INDEX `Idx_Id_DatosCap_CapPart` (`Fk_Id_DatosCap`), 
	INDEX `Idx_Id_Usuario_CapPart` (`Fk_Id_Usuario`),
	INDEX `Idx_Id_CatEstPart_CapPart` (`Fk_Id_CatEstPart`),
	-- Buscar historial de un usuario específico (Para ver 'Mis Cursos')
	-- Este índice ayuda a ordenar por fecha el historial de un alumno
	INDEX `Idx_Perf_Historial_Alumno` (`Fk_Id_Usuario`, `created_at`),
  CONSTRAINT `Fk_Id_DatosCap_CapPart`
    FOREIGN KEY (`Fk_Id_DatosCap`)
    REFERENCES `PICADE`.`DatosCapacitaciones` (`Id_DatosCap`)
	ON DELETE NO ACTION
    ON UPDATE NO ACTION,
  CONSTRAINT `Fk_Id_Usuario_CapPart`
    FOREIGN KEY (`Fk_Id_Usuario`)
    REFERENCES `PICADE`.`Usuarios` (`Id_Usuario`)
	ON DELETE NO ACTION
    ON UPDATE NO ACTION,
  CONSTRAINT `Fk_Id_CatEstPart_CapPart`
    FOREIGN KEY (`Fk_Id_CatEstPart`)
    REFERENCES `PICADE`.`Cat_Estatus_Participante` (`Id_CatEstPart`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION
) ENGINE = InnoDB 
DEFAULT CHARACTER SET = utf8mb4 
COLLATE = utf8mb4_spanish_ci;*/

-- -----------------------------------------------------
-- Table `PICADE`.`Capacitaciones_Participantes`
/* TABLA INTERMEDIA (FACT TABLE)
   Almacena la relación N:M entre Capacitaciones y Usuarios (Participantes).
   
   FUNCIONALIDADES:
   1. Historial Académico: Guarda Calificación y Asistencia.
   2. Gestión de Cupo: Controla quién ocupa asiento mediante Estatus.
   3. Auditoría Forense: Rastrea QUIÉN inscribió y QUIÉN modificó cada registro.
*/
-- -----------------------------------------------------

-- DROP TABLE IF EXISTS `PICADE`.`Capacitaciones_Participantes`;

CREATE TABLE IF NOT EXISTS `PICADE`.`Capacitaciones_Participantes` (
  `Id_CapPart` INT NOT NULL AUTO_INCREMENT,
  
  /* RELACIONES PRINCIPALES */
  `Fk_Id_DatosCap` INT NOT NULL COMMENT 'Referencia a la versión específica del curso',
  `Fk_Id_Usuario` INT NOT NULL COMMENT 'El alumno/participante',
  `Fk_Id_CatEstPart` INT NOT NULL COMMENT 'Estatus (Inscrito, Baja, Aprobado, etc)',
  
  
  /* DATOS ACADÉMICOS */
  `PorcentajeAsistencia` DECIMAL(5,2) NULL DEFAULT NULL,
  `Calificacion` DECIMAL(5,2) NULL DEFAULT NULL,
  
  `Justificacion` VARCHAR(253) NULL COMMENT 'Campo polimórfico para justificar Bajas, Reinscripciones o Cambios de Nota',
  
  /* AUDITORÍA TEMPORAL (CUÁNDO) */
  `created_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP(),
  `updated_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP() ON UPDATE CURRENT_TIMESTAMP(),
  
  /* AUDITORÍA DE ACTORES (QUIÉN) - NUEVAS COLUMNAS */
  `Fk_Id_Usuario_Created_By` INT NULL COMMENT 'Usuario que realizó la inscripción original',
  `Fk_Id_Usuario_Updated_By` INT NULL COMMENT 'Último usuario que modificó datos o estatus',

  /* RESTRICCIONES Y LLAVES */
  PRIMARY KEY (`Id_CapPart`),
  
  /* Evitar duplicados: Un usuario solo puede estar una vez en una versión específica */
  CONSTRAINT `Uk_DatosCap_Usuario_CapPart` UNIQUE (`Fk_Id_DatosCap`, `Fk_Id_Usuario`),
  
  /* Validación de datos: Asistencia entre 0 y 100 */
  CONSTRAINT `Check_Porcentaje_Valido`
    CHECK (`PorcentajeAsistencia` >= 0 AND `PorcentajeAsistencia` <= 100),

  /* ÍNDICES DE RENDIMIENTO */
  INDEX `Idx_Id_DatosCap_CapPart` (`Fk_Id_DatosCap`), 
  INDEX `Idx_Id_Usuario_CapPart` (`Fk_Id_Usuario`),
  INDEX `Idx_Id_CatEstPart_CapPart` (`Fk_Id_CatEstPart`),
  
  /* Índice compuesto para "Mis Cursos" (Busca por usuario y ordena por fecha) */
  INDEX `Idx_Perf_Historial_Alumno` (`Fk_Id_Usuario`, `created_at`),

  /* LLAVES FORÁNEAS PRINCIPALES */
  CONSTRAINT `Fk_Id_DatosCap_CapPart`
    FOREIGN KEY (`Fk_Id_DatosCap`)
    REFERENCES `PICADE`.`DatosCapacitaciones` (`Id_DatosCap`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION,
    
  CONSTRAINT `Fk_Id_Usuario_CapPart`
    FOREIGN KEY (`Fk_Id_Usuario`)
    REFERENCES `PICADE`.`Usuarios` (`Id_Usuario`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION,
    
  CONSTRAINT `Fk_Id_CatEstPart_CapPart`
    FOREIGN KEY (`Fk_Id_CatEstPart`)
    REFERENCES `PICADE`.`Cat_Estatus_Participante` (`Id_CatEstPart`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION,

  /* LLAVES FORÁNEAS DE AUDITORÍA (NUEVAS) */
  CONSTRAINT `Fk_CapPart_CreatedBy`
    FOREIGN KEY (`Fk_Id_Usuario_Created_By`)
    REFERENCES `PICADE`.`Usuarios` (`Id_Usuario`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION,

  CONSTRAINT `Fk_CapPart_UpdatedBy`
    FOREIGN KEY (`Fk_Id_Usuario_Updated_By`)
    REFERENCES `PICADE`.`Usuarios` (`Id_Usuario`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION

) ENGINE = InnoDB 
DEFAULT CHARACTER SET = utf8mb4 
COLLATE = utf8mb4_spanish_ci;

SET SQL_MODE=@OLD_SQL_MODE;
SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS;
SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS;
