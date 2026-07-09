
INSERT INTO gold.dim_country (
    country, cost_of_living_index, rent_index, groceries_index,
    restaurant_price_index, happiness_score, gdp_per_capita
)
SELECT DISTINCT
    m.country,
    m.Cost_of_Living_Index,
    m.Rent_Index,
    m.Groceries_Index,
    m.Restaurant_Price_Index,
    m.happiness_score,
    m.gdp_per_capita
FROM silver.master_dataset m
WHERE m.country IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 FROM gold.dim_country dc WHERE dc.country = m.country
  );
GO

-- ---------------------------------------------------------------------
-- dim_city
-- One row per distinct (city, country) pair.
-- ---------------------------------------------------------------------
INSERT INTO gold.dim_city (city, country_key)
SELECT DISTINCT
    m.city,
    dc.country_key
FROM silver.master_dataset m
JOIN gold.dim_country dc
    ON dc.country = m.country
WHERE m.city IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 FROM gold.dim_city existing
      WHERE existing.city = m.city
        AND existing.country_key = dc.country_key
  );
GO

-- ---------------------------------------------------------------------
-- dim_room_type
-- ---------------------------------------------------------------------
INSERT INTO gold.dim_room_type (room_type, room_shared, room_private)
SELECT DISTINCT
    m.room_type,
    m.room_shared,
    m.room_private
FROM silver.master_dataset m
WHERE m.room_type IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 FROM gold.dim_room_type existing
      WHERE existing.room_type = m.room_type
        AND existing.room_shared = m.room_shared
        AND existing.room_private = m.room_private
  );
GO

-- ---------------------------------------------------------------------
-- dim_host
-- multi / biz in the source data are 0/1 integers; normalize to BIT.
-- ---------------------------------------------------------------------
INSERT INTO gold.dim_host (host_is_superhost, is_multi_listing, is_business_listing)
SELECT DISTINCT
    m.host_is_superhost,
    CASE WHEN m.multi = 1 THEN 1 ELSE 0 END,
    CASE WHEN m.biz = 1 THEN 1 ELSE 0 END
FROM silver.master_dataset m
WHERE NOT EXISTS (
    SELECT 1 FROM gold.dim_host existing
    WHERE existing.host_is_superhost = m.host_is_superhost
      AND existing.is_multi_listing = CASE WHEN m.multi = 1 THEN 1 ELSE 0 END
      AND existing.is_business_listing = CASE WHEN m.biz = 1 THEN 1 ELSE 0 END
);
GO

-- ---------------------------------------------------------------------
-- dim_day_type
-- ---------------------------------------------------------------------
INSERT INTO gold.dim_day_type (day_type)
SELECT DISTINCT m.day_type
FROM silver.master_dataset m
WHERE m.day_type IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 FROM gold.dim_day_type d WHERE d.day_type = m.day_type
  );
GO
