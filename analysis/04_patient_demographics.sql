-- #### Query 4.1: Demographic Volume & Outcome Matrix
-- What are the baseline outcomes for different age and gender groups?
SELECT 
    p.age_group,
    p.gender,
    COUNT(*) AS total_cases,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_total,
    ROUND(AVG(f.length_of_stay)::numeric, 1) AS avg_los,
    ROUND(100.0 * AVG(CASE WHEN a.patient_disposition ILIKE '%Expired%' THEN 1 ELSE 0 END)::numeric, 2) AS mortality_rate_pct,
    ROUND(100.0 * AVG(CASE WHEN a.patient_disposition ILIKE '%Home%' THEN 1 ELSE 0 END)::numeric, 2) AS home_discharge_pct
FROM fact_hospital_encounter f
JOIN dim_patient p ON f.patient_id = p.patient_id
JOIN dim_admission a ON f.admission_id = a.admission_id
WHERE f.has_complete_data = TRUE
GROUP BY p.age_group, p.gender
ORDER BY p.age_group, p.gender;


--#### Query 4.2: Severity-Adjusted Equity Analysis
-- Does race impact length of stay after controlling for clinical severity?
WITH severity_benchmarks AS (
    SELECT 
        c.severity_label,
        AVG(f.length_of_stay) AS benchmark_avg_los
    FROM fact_hospital_encounter f
    JOIN dim_clinical c ON f.clinical_id = c.clinical_id
    WHERE f.has_complete_data = TRUE
    GROUP BY c.severity_label
)
SELECT 
    p.race,
    c.severity_label,
    COUNT(*) AS total_cases,
    ROUND(AVG(f.length_of_stay)::numeric, 2) AS group_avg_los,
    ROUND(sb.benchmark_avg_los::numeric, 2) AS benchmark_los,
    ROUND((AVG(f.length_of_stay) - sb.benchmark_avg_los)::numeric, 2) AS los_variance
FROM fact_hospital_encounter f
JOIN dim_patient p ON f.patient_id = p.patient_id
JOIN dim_clinical c ON f.clinical_id = c.clinical_id
JOIN severity_benchmarks sb ON c.severity_label = sb.severity_label
WHERE f.has_complete_data = TRUE AND p.race IS NOT NULL
GROUP BY p.race, c.severity_label, sb.benchmark_avg_los
HAVING COUNT(*) >= 100
ORDER BY c.severity_label, los_variance DESC;


-- #### Query 4.3: Admission Source vs. Outcome Success
-- Does the entry point of care (Emergency vs Elective) predict discharge success?
SELECT 
    a.type_of_admission,
    COUNT(*) AS total_cases,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_admissions,
    ROUND(AVG(f.total_costs)::numeric, 2) AS avg_cost,
    ROUND(100.0 * AVG(CASE WHEN a.patient_disposition LIKE '%Home%' THEN 1 ELSE 0 END)::numeric, 1) AS home_discharge_rate_pct
FROM fact_hospital_encounter f
JOIN dim_admission a ON f.admission_id = a.admission_id
WHERE f.has_complete_data = TRUE
GROUP BY a.type_of_admission
ORDER BY home_discharge_rate_pct DESC;