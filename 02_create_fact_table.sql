-- =====================================================================
-- 3_gold_layer / 02_create_fact_table.sql   (Microsoft SQL Server / T-SQL)
-- ---------------------------------------------------------------------
-- Creates the central fact table for the Airbnb European Cities star
-- schema. Grain: one row per individual Airbnb listing observation
-- (a listing is observed once as 'weekday' pricing and once as
-- 'weekend' pricing, per the source dataset's structure).
--
-- Run this AFTER 01_create_dimensions.sql.
-- =====================================================================

IF OBJECT_ID('gold.fact_listings', 'U') IS NOT NULL
    DROP TABLE gold.fact_listings;
GO

CREATE TABLE gold.fact_listings (
    listing_key                 BIGINT IDENTITY(1,1) PRIMARY KEY,

    -- Foreign keys to dimensions
    city_key                    INT NOT NULL,
    room_type_key                INT NOT NULL,
    host_key                     INT NOT NULL,
    day_type_key                 INT NOT NULL,

    -- Core measure
    price                         NUMERIC(10,2) NOT NULL,   -- source column: realSum

    -- Listing attributes / measures
    person_capacity               NUMERIC(4,1),
    bedrooms                      INT,
    cleanliness_rating             NUMERIC(4,2),
    guest_satisfaction_overall      NUMERIC(5,2),

    -- Location / distance measures
    dist                          NUMERIC(8,4),   -- distance to city centre (km)
    metro_dist                    NUMERIC(8,4),   -- distance to nearest metro (km)
    lat                           NUMERIC(9,6),
    lng                           NUMERIC(9,6),

    -- Index-style measures carried from the source dataset
    attr_index                    NUMERIC(10,4),
    attr_index_norm                NUMERIC(10,4),
    rest_index                    NUMERIC(10,4),
    rest_index_norm                NUMERIC(10,4),

    CONSTRAINT FK_fact_listings_city
        FOREIGN KEY (city_key) REFERENCES gold.dim_city (city_key),
    CONSTRAINT FK_fact_listings_room_type
        FOREIGN KEY (room_type_key) REFERENCES gold.dim_room_type (room_type_key),
    CONSTRAINT FK_fact_listings_host
        FOREIGN KEY (host_key) REFERENCES gold.dim_host (host_key),
    CONSTRAINT FK_fact_listings_day_type
        FOREIGN KEY (day_type_key) REFERENCES gold.dim_day_type (day_type_key)
);
GO

-- Helpful indexes for the query patterns Power BI / analysts will use most:
-- filtering and grouping by city, room type, and day type.
CREATE INDEX idx_fact_listings_city      ON gold.fact_listings (city_key);
CREATE INDEX idx_fact_listings_roomtype  ON gold.fact_listings (room_type_key);
CREATE INDEX idx_fact_listings_daytype   ON gold.fact_listings (day_type_key);
CREATE INDEX idx_fact_listings_host      ON gold.fact_listings (host_key);
GO
