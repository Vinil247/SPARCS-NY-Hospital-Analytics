-- #### Query 2.1: The Clinical Severity Benchmark
-- How does patient complexity scale resource consumption?
-- cost data follows clinical logic across severity levels.

SELECT 
    c.severity_label,
    COUNT(*) AS total_cases,
    ROUND(AVG(f.total_costs)::numeric, 2) AS avg_cost,
    ROUND(AVG(f.length_of_stay)::numeric, 1) AS avg_los,
    ROUND(AVG(f.total_costs / NULLIF(f.length_of_stay, 0))::numeric, 2) AS avg_daily_intensity,
    ROUND(100.0 * AVG(CASE WHEN f.has_procedure THEN 1 ELSE 0 END)::numeric, 1) AS procedure_rate_pct
FROM fact_hospital_encounter f
JOIN dim_clinical c ON f.clinical_id = c.clinical_id
WHERE f.has_complete_data = TRUE
GROUP BY c.severity_label
ORDER BY 
    CASE c.severity_label 
        WHEN 'High Severity' THEN 1 
        WHEN 'Low-Moderate Severity' THEN 2
		else 3
    END;


-- #### Query 2.2: Diagnosis Financial Ranking
-- Which clinical conditions represent the highest total spend for NYS?
-- Rank diagnoses by both Volume (demand) and Total Spend (burden).

WITH diagnosis_stats AS (
    SELECT 
        c.apr_drg_description AS diagnosis,
		severity_label as severity,
        COUNT(*) AS total_cases,
        ROUND(AVG(f.total_costs)::numeric, 2) AS avg_cost,
        ROUND(SUM(f.total_costs) / 1e6, 2) AS total_spend_millions
    FROM fact_hospital_encounter f
    JOIN dim_clinical c ON f.clinical_id = c.clinical_id
    WHERE f.has_complete_data = TRUE
    GROUP BY 1,2
)
SELECT 
    diagnosis,
	severity,
    total_cases,
    avg_cost,
    total_spend_millions,
    RANK() OVER (ORDER BY total_spend_millions DESC) AS financial_impact_rank,
    RANK() OVER (ORDER BY total_cases DESC) AS volume_rank
FROM diagnosis_stats
ORDER BY financial_impact_rank
LIMIT 20;


-- #### Query 2.3: Surgical vs. Medical Outcomes
-- What is the cost-outcome trade-off for surgical intervention?
-- The "Cost Premium" of surgery vs medical management.

WITH case_type_comparison AS (
    SELECT 
        f.has_procedure,
        COUNT(*) AS total_cases,
        ROUND(AVG(f.total_costs)::numeric, 2) AS avg_cost,
        ROUND(AVG(f.length_of_stay)::numeric, 1) AS avg_los,
        ROUND(AVG(CASE WHEN a.patient_disposition LIKE '%Home%' THEN 1.0 ELSE 0.0 END) * 100, 2) AS home_discharge_rate
    FROM fact_hospital_encounter f
    JOIN dim_admission a ON f.admission_id = a.admission_id
    WHERE f.has_complete_data = TRUE
    GROUP BY f.has_procedure
)
SELECT 
    CASE WHEN has_procedure THEN 'Surgical' ELSE 'Medical' END AS case_type,
    total_cases,
    avg_cost,
    avg_los,
    home_discharge_rate,
    COALESCE(ROUND(avg_cost - LAG(avg_cost) OVER (ORDER BY has_procedure), 2), 0.00) AS surgical_cost_premium
FROM case_type_comparison;

/*
This suggests that while Surgery costs $16.8k more and keeps patients in the hospital 1.8 days longer,
it doesn't significantly change the immediate likelihood of a patient going home.
*/
