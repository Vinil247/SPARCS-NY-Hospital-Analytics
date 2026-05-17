-- #### Query 3.1: Statewide Payer Concentration & Cost Burden
-- Business Question: Which payers represent the highest financial volume and unit cost?
-- Spend across Medicare, Medicaid, and Private insurance.
SELECT 
    p.payer_category,
    COUNT(*) AS total_encounters,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS market_share_pct,
    ROUND(AVG(f.total_costs)::numeric, 2) AS avg_unit_cost,
    ROUND(SUM(f.total_costs) / 1e6, 2) AS total_spend_millions
FROM fact_hospital_encounter f
JOIN dim_payment p ON f.payment_id = p.payment_id
WHERE f.has_complete_data = TRUE
GROUP BY p.payer_category
ORDER BY total_spend_millions DESC;



-- #### Query 3.2: Payer Cost Variance vs. Benchmark
-- Which payers are associated with higher-than-average clinical resource consumption?
-- each payer's average cost against the statewide baseline.
--- “This reflects patient acuity differences, not necessarily payer-driven cost inflation.”

WITH payer_stats AS (
    SELECT
        p.payer_category,
        AVG(f.total_costs) AS payer_avg_cost,
        COUNT(*) AS category_count
    FROM fact_hospital_encounter f
    JOIN dim_payment p ON f.payment_id = p.payment_id
    WHERE f.has_complete_data = TRUE
    GROUP BY p.payer_category
),
statewide AS (
    SELECT AVG(total_costs) AS weighted_benchmark
    FROM fact_hospital_encounter
    WHERE has_complete_data = TRUE
)
SELECT
    payer_category,
    ROUND(payer_avg_cost::numeric, 2) AS avg_cost,
    ROUND(weighted_benchmark::numeric, 2) AS benchmark,
    ROUND(100.0 * (payer_avg_cost - weighted_benchmark) / weighted_benchmark, 2) AS pct_variance
FROM payer_stats, statewide
ORDER BY pct_variance DESC;


-- #### Query 3.3: Facility Payer Mix Pivot
-- What is the insurance profile of the state's largest hospitals?
-- dependency on government vs. private payers
SELECT 
    h.facility_name,
    COUNT(*) AS total_cases,
    ROUND(100.0 * SUM(CASE WHEN p.payer_category = 'Medicare' THEN 1 ELSE 0 END) / COUNT(*), 1) AS medicare_pct,
    ROUND(100.0 * SUM(CASE WHEN p.payer_category = 'Medicaid' THEN 1 ELSE 0 END) / COUNT(*), 1) AS medicaid_pct,
	ROUND(100.0 * SUM(CASE WHEN p.payer_category = 'Private' THEN 1 ELSE 0 END) / COUNT(*), 1) AS private_pct,
    ROUND(100.0 * SUM(CASE WHEN p.payer_category = 'Self-Pay' THEN 1 ELSE 0 END) / COUNT(*), 1) AS self_pay_pct,
	ROUND(100.0 * SUM(CASE WHEN p.payer_category = 'Government' THEN 1 ELSE 0 END) / COUNT(*), 1) AS government_pct,
	ROUND(100.0 * SUM(CASE WHEN p.payer_category = 'Other' THEN 1 ELSE 0 END) / COUNT(*), 1) AS other_pay_pct
FROM fact_hospital_encounter f
JOIN dim_hospital h ON f.hospital_id = h.hospital_id
JOIN dim_payment p ON f.payment_id = p.payment_id
WHERE f.has_complete_data = TRUE
GROUP BY h.facility_name
HAVING COUNT(*) >= 500
ORDER BY total_cases DESC
LIMIT 20;

