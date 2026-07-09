

IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'gold')
BEGIN
    EXEC('CREATE SCHEMA gold');
END
GO

-- ---------------------------------------------------------------------
-- dim_country
-- One row per country. Holds the country-level features pulled in
-- during the silver layer (cost of living, rent, groceries, restaurant
-- prices, happiness score, GDP per capita) -- including the Vatican
-- City row that was backfilled with Italy's scraped values.
-- ---------------------------------------------------------------------
IF OBJECT_ID('gold.dim_country', 'U') IS NOT NULL
    DROP TABLE gold.dim_country;
GO

CREATE TABLE gold.dim_country (
    country_key             INT IDENTITY(1,1) PRIMARY KEY,
    country                 VARCHAR(100) NOT NULL,
    cost_of_living_index    NUMERIC(6,2),
    rent_index               NUMERIC(6,2),
    groceries_index          NUMERIC(6,2),
    restaurant_price_index   NUMERIC(6,2),
    happiness_score           NUMERIC(5,3),
    gdp_per_capita             NUMERIC(6,3),
    CONSTRAINT UQ_dim_country_country UNIQUE (country)
);
GO

-- ---------------------------------------------------------------------
-- dim_city
-- One row per city. Links back to its country so city-level and
-- country-level analysis can both be sliced from the same fact table.
-- ---------------------------------------------------------------------
IF OBJECT_ID('gold.dim_city', 'U') IS NOT NULL
    DROP TABLE gold.dim_city;
GO

CREATE TABLE gold.dim_city (
    city_key      INT IDENTITY(1,1) PRIMARY KEY,
    city          VARCHAR(100) NOT NULL,
    country_key   INT NOT NULL,
    CONSTRAINT FK_dim_city_country FOREIGN KEY (country_key)
        REFERENCES gold.dim_country (country_key),
    CONSTRAINT UQ_dim_city UNIQUE (city, country_key)
);
GO

-- ---------------------------------------------------------------------
-- dim_room_type
-- One row per distinct room type configuration.
-- ---------------------------------------------------------------------
IF OBJECT_ID('gold.dim_room_type', 'U') IS NOT NULL
    DROP TABLE gold.dim_room_type;
GO

CREATE TABLE gold.dim_room_type (
    room_type_key   INT IDENTITY(1,1) PRIMARY KEY,
    room_type       VARCHAR(50) NOT NULL,
    room_shared     BIT NOT NULL,
    room_private    BIT NOT NULL,
    CONSTRAINT UQ_dim_room_type UNIQUE (room_type, room_shared, room_private)
);
GO

-- ---------------------------------------------------------------------
-- dim_host
-- One row per distinct host profile combination (superhost status,
-- whether the listing is part of a multi-listing host, whether the
-- host operates as a business). If richer host-level detail is
-- scraped later (host tenure, response rate, etc.), extend this table.
-- ---------------------------------------------------------------------
IF OBJECT_ID('gold.dim_host', 'U') IS NOT NULL
    DROP TABLE gold.dim_host;
GO

CREATE TABLE gold.dim_host (
    host_key                 INT IDENTITY(1,1) PRIMARY KEY,
    host_is_superhost        BIT NOT NULL,
    is_multi_listing         BIT NOT NULL,
    is_business_listing      BIT NOT NULL,
    CONSTRAINT UQ_dim_host UNIQUE (host_is_superhost, is_multi_listing, is_business_listing)
);
GO

-- ---------------------------------------------------------------------
-- dim_day_type
-- Small lookup table: weekday vs weekend. Kept as its own dimension
-- (rather than a flag on the fact table) so it's easy to add more
-- granular date attributes later if real booking dates are ever added.
-- ---------------------------------------------------------------------
IF OBJECT_ID('gold.dim_day_type', 'U') IS NOT NULL
    DROP TABLE gold.dim_day_type;
GO

CREATE TABLE gold.dim_day_type (
    day_type_key   INT IDENTITY(1,1) PRIMARY KEY,
    day_type       VARCHAR(10) NOT NULL,   -- 'weekday' or 'weekend'
    CONSTRAINT UQ_dim_day_type UNIQUE (day_type)
);
GO
