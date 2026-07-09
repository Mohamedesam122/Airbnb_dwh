-- =====================================================================
-- 3_gold_layer / 05_sample_analysis_queries.sql   (Microsoft SQL Server / T-SQL)
-- ---------------------------------------------------------------------
-- A handful of ready-to-run queries against the star schema. Useful
-- for (a) sanity-checking the gold layer loaded correctly, and
-- (b) as a starting point for the Power BI visuals in 4_powerbi_dashboard/.
-- =====================================================================

-- 1. Average price by city (weekday vs weekend), ranked highest first.
SELECT
    dcity.city,
    ddt.day_type,
    ROUND(AVG(f.price), 2)  AS avg_price,
    COUNT(*)                AS listing_count
FROM gold.fact_listings f
JOIN gold.dim_city dcity     ON dcity.city_key = f.city_key
JOIN gold.dim_day_type ddt   ON ddt.day_type_key = f.day_type_key
GROUP BY dcity.city, ddt.day_type
ORDER BY avg_price DESC;
GO

-- 2. Average price by room type.
SELECT
    drt.room_type,
    ROUND(AVG(f.price), 2)  AS avg_price,
    COUNT(*)                AS listing_count
FROM gold.fact_listings f
JOIN gold.dim_room_type drt ON drt.room_type_key = f.room_type_key
GROUP BY drt.room_type
ORDER BY avg_price DESC;
GO

-- 3. Does superhost status correlate with higher guest satisfaction / price?
SELECT
    dh.host_is_superhost,
    ROUND(AVG(f.price), 2)                          AS avg_price,
    ROUND(AVG(f.guest_satisfaction_overall), 2)      AS avg_satisfaction,
    COUNT(*)                                         AS listing_count
FROM gold.fact_listings f
JOIN gold.dim_host dh ON dh.host_key = f.host_key
GROUP BY dh.host_is_superhost;
GO

-- 4. Country-level view: average listing price vs. cost of living /
--    happiness score -- the core "does a pricier country actually
--    correlate with a happier/more expensive country" question.
SELECT
    dc.country,
    dc.cost_of_living_index,
    dc.happiness_score,
    dc.gdp_per_capita,
    ROUND(AVG(f.price), 2)  AS avg_listing_price,
    COUNT(*)                AS listing_count
FROM gold.fact_listings f
JOIN gold.dim_city dcity  ON dcity.city_key = f.city_key
JOIN gold.dim_country dc  ON dc.country_key = dcity.country_key
GROUP BY dc.country, dc.cost_of_living_index, dc.happiness_score, dc.gdp_per_capita
ORDER BY avg_listing_price DESC;
GO

-- 5. Price per person capacity, by city -- a rough "value for money" metric.
SELECT
    dcity.city,
    ROUND(AVG(f.price / NULLIF(f.person_capacity, 0)), 2) AS avg_price_per_guest
FROM gold.fact_listings f
JOIN gold.dim_city dcity ON dcity.city_key = f.city_key
GROUP BY dcity.city
ORDER BY avg_price_per_guest DESC;
GO

-- 6. Distance from city centre vs. price -- sanity check that closer
--    listings tend to cost more (a common expectation worth verifying).
--    SQL Server has no built-in CORR() aggregate (unlike Postgres), so
--    Pearson's correlation coefficient is computed manually here:
--        r = (n*SUM(xy) - SUM(x)*SUM(y))
--            / SQRT( (n*SUM(x^2) - SUM(x)^2) * (n*SUM(y^2) - SUM(y)^2) )
SELECT
    dcity.city,
    ROUND(
        (agg.n * agg.sum_xy - agg.sum_x * agg.sum_y)
        / NULLIF(
            SQRT(
                (agg.n * agg.sum_x2 - POWER(agg.sum_x, 2))
                * (agg.n * agg.sum_y2 - POWER(agg.sum_y, 2))
            ), 0
          ),
        3
    ) AS dist_price_correlation
FROM (
    SELECT
        f.city_key,
        COUNT(*)                     AS n,
        SUM(f.dist)                  AS sum_x,
        SUM(f.price)                 AS sum_y,
        SUM(f.dist * f.price)        AS sum_xy,
        SUM(POWER(f.dist, 2))        AS sum_x2,
        SUM(POWER(f.price, 2))       AS sum_y2
    FROM gold.fact_listings f
    GROUP BY f.city_key
) agg
JOIN gold.dim_city dcity ON dcity.city_key = agg.city_key
ORDER BY dist_price_correlation;
GO

-- 7. Row-count reconciliation check (see also the commented query at
--    the bottom of 04_load_fact_table.sql).
SELECT
    (SELECT COUNT(*) FROM gold.dim_country)   AS country_count,
    (SELECT COUNT(*) FROM gold.dim_city)      AS city_count,
    (SELECT COUNT(*) FROM gold.dim_room_type) AS room_type_count,
    (SELECT COUNT(*) FROM gold.dim_host)      AS host_profile_count,
    (SELECT COUNT(*) FROM gold.dim_day_type)  AS day_type_count,
    (SELECT COUNT(*) FROM gold.fact_listings) AS fact_row_count;
GO
