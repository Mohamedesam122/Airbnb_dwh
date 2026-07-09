

INSERT INTO gold.fact_listings (
    city_key, room_type_key, host_key, day_type_key,
    price, person_capacity, bedrooms, cleanliness_rating,
    guest_satisfaction_overall, dist, metro_dist, lat, lng,
    attr_index, attr_index_norm, rest_index, rest_index_norm
)
SELECT
    dcity.city_key,
    drt.room_type_key,
    dh.host_key,
    ddt.day_type_key,

    m.[realSum]                    AS price,
    m.person_capacity,
    m.bedrooms,
    m.cleanliness_rating,
    m.guest_satisfaction_overall,
    m.dist,
    m.metro_dist,
    m.lat,
    m.lng,
    m.attr_index,
    m.attr_index_norm,
    m.rest_index,
    m.rest_index_norm

FROM silver.master_dataset m

JOIN gold.dim_country dc
    ON dc.country = m.country

JOIN gold.dim_city dcity
    ON dcity.city = m.city
   AND dcity.country_key = dc.country_key

JOIN gold.dim_room_type drt
    ON drt.room_type = m.room_type
   AND drt.room_shared = m.room_shared
   AND drt.room_private = m.room_private

JOIN gold.dim_host dh
    ON dh.host_is_superhost = m.host_is_superhost
   AND dh.is_multi_listing = CASE WHEN m.multi = 1 THEN 1 ELSE 0 END
   AND dh.is_business_listing = CASE WHEN m.biz = 1 THEN 1 ELSE 0 END

JOIN gold.dim_day_type ddt
    ON ddt.day_type = m.day_type;
GO

-- ---------------------------------------------------------------------
-- Quick sanity check after loading: row counts should match between
-- the silver source and the gold fact table (barring any rows dropped
-- due to nulls in a join key -- investigate if these don't match).
-- ---------------------------------------------------------------------
-- SELECT
--     (SELECT COUNT(*) FROM silver.master_dataset) AS silver_row_count,
--     (SELECT COUNT(*) FROM gold.fact_listings)     AS gold_row_count;
