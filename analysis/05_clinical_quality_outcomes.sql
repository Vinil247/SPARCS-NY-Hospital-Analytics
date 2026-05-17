-- #### Query 5.1: Mortality Rate by Clinical Condition
-- Which diagnoses present the highest clinical risk across the state?
-- Note: Results reflect condition severity, not hospital performance
SELECT 
    c.apr_drg_description AS diagnosis,
    c.severity_label,
    COUNT(*) AS total_cases,
    -- Mortality defined as 'Expired' in patient disposition
    ROUND(100.0 * AVG(CASE WHEN a.patient_disposition LIKE '%Expired%' THEN 1 ELSE 0 END)::numeric, 2) AS mortality_rate_pct,
    ROUND(AVG(f.total_costs)::numeric, 2) AS avg_cost_per_case
FROM fact_hospital_encounter f
JOIN dim_clinical c ON f.clinical_id = c.clinical_id
JOIN dim_admission a ON f.admission_id = a.admission_id
WHERE f.has_complete_data = TRUE
GROUP BY c.apr_drg_description, c.severity_label
HAVING COUNT(*) >= 100
ORDER BY mortality_rate_pct DESC
LIMIT 15;

/*
Morality are concentrated in a small number of extremely severe conditions, where outcomes are driven by medical complexity rather than hospital quality.
*/


-- #### Query 5.2: Facility-Level Quality Scorecard
-- Which high-volume hospitals demonstrate the best life-saving and discharge outcomes?
-- "hard" outcomes (mortality) vs. "functional" outcomes (home discharge).
-- Note: Results are heavily influenced by facility specialization and patient acuity
SELECT 
    h.facility_name,
    COUNT(*) AS total_cases,
    ROUND(100.0 * AVG(CASE WHEN a.patient_disposition LIKE '%Expired%' THEN 1 ELSE 0 END)::numeric, 2) AS mortality_rate_pct,
    ROUND(100.0 * AVG(CASE WHEN a.patient_disposition LIKE '%Home%' THEN 1 ELSE 0 END)::numeric, 2) AS home_discharge_rate_pct,
    ROUND(AVG(f.length_of_stay)::numeric, 1) AS avg_los
FROM fact_hospital_encounter f
JOIN dim_hospital h ON f.hospital_id = h.hospital_id
JOIN dim_admission a ON f.admission_id = a.admission_id
WHERE f.has_complete_data = TRUE
GROUP BY h.facility_name
HAVING COUNT(*) >= 1000 
ORDER BY mortality_rate_pct ASC
LIMIT 20;

/*
Facilities with near-zero mortality and high home-discharge rates are primarily
specialty, rehabilitation, or behavioral health centers, reflecting lower-acuity patient populations rather than superior clinical performance.
*/


-- #### Query 5.3: Post-Acute Care Transfer Analysis
-- Which facilities have high rates of transfer to Skilled Nursing Facilities (SNF)?
-- patients who require continued institutional care, often a proxy for high-acuity or slower recovery.
-- Note: SNF transfers indicate recovery needs, not mortality or care failure

SELECT 
    h.facility_name,
    COUNT(*) AS total_cases,
    ROUND(100.0 * AVG(CASE WHEN a.patient_disposition LIKE '%Skilled Nursing%' THEN 1 ELSE 0 END)::numeric, 1) AS snf_transfer_pct,
    ROUND(AVG(f.length_of_stay)::numeric, 1) AS avg_los
FROM fact_hospital_encounter f
JOIN dim_hospital h ON f.hospital_id = h.hospital_id
JOIN dim_admission a ON f.admission_id = a.admission_id
WHERE f.has_complete_data = TRUE
GROUP BY h.facility_name
HAVING COUNT(*) >= 500
ORDER BY snf_transfer_pct DESC
LIMIT 15;

/*
Hospitals with higher SNF transfer rates tend to manage patients who require extended recovery or ongoing institutional care,
reflecting post-acute needs rather than poor clinical outcomes.”
*/

