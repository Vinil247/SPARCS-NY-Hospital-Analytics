-- #### Query 1.1: Regional Market Leaders
-- Which hospitals dominate patient volume in each region, and what is their cost profile?
WITH ranked_facilities AS (
    SELECT
        h.hospital_service_area AS region,
        h.facility_name,
        COUNT(*) AS total_encounters,
        ROUND(AVG(f.total_costs)::numeric, 2) AS avg_cost_per_case,
        ROUND(AVG(f.length_of_stay)::numeric, 1) AS avg_los,
        DENSE_RANK() OVER (
            PARTITION BY h.hospital_service_area
            ORDER BY COUNT(*) DESC
        ) AS regional_volume_rank
    FROM fact_hospital_encounter f
    JOIN dim_hospital h ON f.hospital_id = h.hospital_id
    WHERE f.has_complete_data = TRUE
    GROUP BY h.hospital_service_area, h.facility_name
    HAVING COUNT(*) >= 100
)
SELECT *
FROM ranked_facilities
WHERE regional_volume_rank <= 5
ORDER BY region, regional_volume_rank;


-- #### Query 1.2: Regional Cost Positioning Bands
-- Which hospitals are meaningfully high-cost or low-cost relative to regional peers?
WITH hospital_metrics AS (
    SELECT
        h.hospital_service_area AS region,
        h.facility_name,
        COUNT(*) AS encounters,
        AVG(f.total_costs) AS avg_hospital_cost
    FROM fact_hospital_encounter f
    JOIN dim_hospital h ON f.hospital_id = h.hospital_id
    WHERE f.has_complete_data = TRUE
    GROUP BY 1, 2
    HAVING COUNT(*) >= 100
),
regional_thresholds AS (
    SELECT 
        region,
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY avg_hospital_cost) AS p25,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY avg_hospital_cost) AS p75
    FROM hospital_metrics
    GROUP BY region
)
SELECT
    m.region,
    m.facility_name,
    m.encounters,
    ROUND(m.avg_hospital_cost::numeric, 2) AS avg_cost,
    CASE
        WHEN m.avg_hospital_cost >= t.p75 THEN 'High Cost'
        WHEN m.avg_hospital_cost <= t.p25 THEN 'Low Cost'
        ELSE 'Mid Cost'
    END AS cost_position
FROM hospital_metrics m
JOIN regional_thresholds t ON m.region = t.region
ORDER BY m.region, m.avg_hospital_cost;


--#### Query 1.3: Regional Market Share
-- How concentrated is patient demand within each region?
WITH share_calculation AS (
    SELECT
        h.hospital_service_area AS region,
        h.facility_name,
        COUNT(*) AS hospital_volume,
        ROUND(
            100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY h.hospital_service_area), 2
			) AS market_share_pct,
        DENSE_RANK() OVER (
            PARTITION BY h.hospital_service_area
            ORDER BY COUNT(*) DESC
        ) AS regional_rank
    FROM fact_hospital_encounter f
    JOIN dim_hospital h ON f.hospital_id = h.hospital_id
    WHERE f.has_complete_data = TRUE
    GROUP BY 1, 2
    HAVING COUNT(*) >= 100
)
SELECT * FROM share_calculation 
WHERE regional_rank <= 10
ORDER BY region, regional_rank;