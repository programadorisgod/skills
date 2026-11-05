-- =============================================================================
-- 00. ESQUEMA Y GENERADOR DE DATOS DE PRUEBA (SQL Server 2017+)
-- Base de datos genérica para simulación de escenarios de alto rendimiento
-- =============================================================================

-- 1. Crear base de datos de pruebas (si no existe)
IF DB_ID('TiendaDemo') IS NULL
BEGIN
    CREATE DATABASE TiendaDemo
    COLLATE Modern_Spanish_CI_AS;
END
GO

USE TiendaDemo;
GO

-- 2. Limpieza de tablas previas (en orden de dependencias)
DROP TABLE IF EXISTS dbo.Envios;
DROP TABLE IF EXISTS dbo.PagosOrden;
DROP TABLE IF EXISTS dbo.DetalleOrden;
DROP TABLE IF EXISTS dbo.Ordenes;
DROP TABLE IF EXISTS dbo.Productos;
DROP TABLE IF EXISTS dbo.Clientes;
GO

-- 3. Definición de Tablas Maestras

CREATE TABLE dbo.Clientes (
    ClienteId INT IDENTITY(1,1) NOT NULL,
    CodigoCliente VARCHAR(20) COLLATE database_default NOT NULL,
    RazonSocial VARCHAR(150) COLLATE database_default NOT NULL,
    TipoCliente VARCHAR(30) COLLATE database_default NOT NULL CONSTRAINT DF_Clientes_Tipo DEFAULT ('REGULAR'),
    Ciudad VARCHAR(50) COLLATE database_default NOT NULL,
    Activo BIT NOT NULL CONSTRAINT DF_Clientes_Activo DEFAULT (1),
    FechaRegistro DATETIME2(0) NOT NULL CONSTRAINT DF_Clientes_Fecha DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_Clientes PRIMARY KEY CLUSTERED (ClienteId),
    CONSTRAINT UQ_Clientes_Codigo UNIQUE NONCLUSTERED (CodigoCliente)
);
GO

CREATE TABLE dbo.Productos (
    ProductoId INT IDENTITY(1,1) NOT NULL,
    CodigoSKU VARCHAR(30) COLLATE database_default NOT NULL,
    NombreProducto VARCHAR(120) COLLATE database_default NOT NULL,
    Categoria VARCHAR(50) COLLATE database_default NOT NULL,
    PrecioUnitario DECIMAL(18,2) NOT NULL,
    StockActual INT NOT NULL CONSTRAINT DF_Productos_Stock DEFAULT (0),
    CONSTRAINT PK_Productos PRIMARY KEY CLUSTERED (ProductoId),
    CONSTRAINT UQ_Productos_SKU UNIQUE NONCLUSTERED (CodigoSKU)
);
GO

CREATE TABLE dbo.Ordenes (
    OrdenId BIGINT IDENTITY(1,1) NOT NULL,
    NumeroOrden VARCHAR(30) COLLATE database_default NOT NULL,
    ClienteId INT NOT NULL,
    FechaOrden DATETIME2(0) NOT NULL,
    TotalOrden DECIMAL(18,2) NOT NULL,
    SaldoPendiente DECIMAL(18,2) NOT NULL,
    EstadoOrden VARCHAR(20) COLLATE database_default NOT NULL, -- 'PENDIENTE', 'PAGADA', 'EN_DISPUTA', 'ANULADA'
    CanalVenta VARCHAR(20) COLLATE database_default NOT NULL CONSTRAINT DF_Ordenes_Canal DEFAULT ('ONLINE'),
    FechaActualizacion DATETIME2(0) NOT NULL CONSTRAINT DF_Ordenes_Update DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_Ordenes PRIMARY KEY CLUSTERED (OrdenId),
    CONSTRAINT FK_Ordenes_Clientes FOREIGN KEY (ClienteId) REFERENCES dbo.Clientes(ClienteId)
);
GO

CREATE TABLE dbo.DetalleOrden (
    DetalleId BIGINT IDENTITY(1,1) NOT NULL,
    OrdenId BIGINT NOT NULL,
    ProductoId INT NOT NULL,
    Cantidad INT NOT NULL,
    PrecioUnitario DECIMAL(18,2) NOT NULL,
    Subtotal AS (Cantidad * PrecioUnitario) PERSISTED,
    CONSTRAINT PK_DetalleOrden PRIMARY KEY CLUSTERED (DetalleId),
    CONSTRAINT FK_Detalle_Ordenes FOREIGN KEY (OrdenId) REFERENCES dbo.Ordenes(OrdenId),
    CONSTRAINT FK_Detalle_Productos FOREIGN KEY (ProductoId) REFERENCES dbo.Productos(ProductoId)
);
GO

CREATE TABLE dbo.PagosOrden (
    PagoId BIGINT IDENTITY(1,1) NOT NULL,
    OrdenId BIGINT NOT NULL,
    FechaPago DATETIME2(0) NOT NULL,
    MontoPagado DECIMAL(18,2) NOT NULL,
    MetodoPago VARCHAR(30) COLLATE database_default NOT NULL, -- 'TARJETA', 'TRANSFERENCIA', 'EFECTIVO'
    EstadoPago VARCHAR(20) COLLATE database_default NOT NULL CONSTRAINT DF_Pagos_Estado DEFAULT ('APROBADO'),
    CONSTRAINT PK_PagosOrden PRIMARY KEY CLUSTERED (PagoId),
    CONSTRAINT FK_Pagos_Ordenes FOREIGN KEY (OrdenId) REFERENCES dbo.Ordenes(OrdenId)
);
GO

CREATE TABLE dbo.Envios (
    EnvioId BIGINT IDENTITY(1,1) NOT NULL,
    OrdenId BIGINT NOT NULL,
    GuiaDespacho VARCHAR(50) COLLATE database_default NOT NULL,
    EstadoEnvio VARCHAR(25) COLLATE database_default NOT NULL, -- 'PREPARANDO', 'EN_TRANSITO', 'ENTREGADO'
    FechaDespacho DATETIME2(0) NULL,
    FechaEntregaEstimada DATETIME2(0) NULL,
    CONSTRAINT PK_Envios PRIMARY KEY CLUSTERED (EnvioId),
    CONSTRAINT FK_Envios_Ordenes FOREIGN KEY (OrdenId) REFERENCES dbo.Ordenes(OrdenId)
);
GO

-- 4. Creación de Índices Estratégicos
CREATE NONCLUSTERED INDEX IX_Ordenes_Fecha_Numero 
ON dbo.Ordenes (FechaOrden DESC, NumeroOrden DESC)
INCLUDE (ClienteId, TotalOrden, SaldoPendiente, EstadoOrden);

CREATE NONCLUSTERED INDEX IX_Ordenes_Estado_Saldo
ON dbo.Ordenes (EstadoOrden, SaldoPendiente)
INCLUDE (FechaOrden, NumeroOrden, ClienteId);

CREATE NONCLUSTERED INDEX IX_DetalleOrden_OrdenId
ON dbo.DetalleOrden (OrdenId)
INCLUDE (ProductoId, Cantidad, Subtotal);

CREATE NONCLUSTERED INDEX IX_PagosOrden_OrdenId
ON dbo.PagosOrden (OrdenId)
INCLUDE (MontoPagado, FechaPago, MetodoPago);
GO

-- =============================================================================
-- 5. Semilla de Datos Sintéticos para Benchmarking (100.000 Órdenes)
-- =============================================================================
SET NOCOUNT ON;

-- Clientes
INSERT INTO dbo.Clientes (CodigoCliente, RazonSocial, TipoCliente, Ciudad)
VALUES 
('CLI0001', 'Corporacion Omega S.A.', 'VIP_PLATINUM', 'Bogota'),
('CLI0002', 'Distribuidora Andina Ltda', 'CORPORATIVO', 'Medellin'),
('CLI0003', 'Servicios Globales SAS', 'REGULAR', 'Cali'),
('CLI0004', 'Comercializadora Norte', 'REGULAR', 'Barranquilla'),
('CLI0005', 'Inversiones del Valle', 'VIP_PLATINUM', 'Pereira');

-- Productos
INSERT INTO dbo.Productos (CodigoSKU, NombreProducto, Categoria, PrecioUnitario, StockActual)
VALUES 
('SKU-TECH-001', 'Laptop Pro 16 pulg', 'TECNOLOGIA', 1500.00, 150),
('SKU-TECH-002', 'Monitor UltraWide 34', 'TECNOLOGIA', 450.00, 80),
('SKU-OFF-001', 'Silla Ergonomica Premium', 'OFICINA', 280.00, 200),
('SKU-OFF-002', 'Escritorio Elevable Motor', 'OFICINA', 620.00, 60),
('SKU-ACC-001', 'Teclado Mecanico Inalambrico', 'ACCESORIOS', 95.00, 400);

-- Generar 100.000 órdenes de prueba mediante CTE recursivo / cross join
WITH Tally AS (
    SELECT TOP (100000) 
        ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS N
    FROM sys.all_objects a
    CROSS JOIN sys.all_objects b
)
INSERT INTO dbo.Ordenes (NumeroOrden, ClienteId, FechaOrden, TotalOrden, SaldoPendiente, EstadoOrden, CanalVenta)
SELECT 
    'ORD-' + CAST(2025000000 + N AS VARCHAR(20)),
    (N % 5) + 1,
    DATEADD(MINUTE, -N, '2026-11-05 15:00:00'),
    CAST(100.00 + (N % 1500) AS DECIMAL(18,2)),
    -- Solo el 2% tiene estado 'EN_DISPUTA' con saldo pendiente (alta selectividad para Row Goal)
    CASE 
        WHEN N % 50 = 0 THEN CAST(100.00 + (N % 1500) AS DECIMAL(18,2)) 
        ELSE 0.00 
    END,
    CASE 
        WHEN N % 50 = 0 THEN 'EN_DISPUTA'
        WHEN N % 10 = 0 THEN 'PENDIENTE'
        ELSE 'PAGADA'
    END,
    CASE WHEN N % 2 = 0 THEN 'ONLINE' ELSE 'RETAIL' END
FROM Tally;
GO

PRINT 'Esquema y datos sintéticos de TiendaDemo creados correctamente.';
GO
