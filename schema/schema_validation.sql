-- ============================================================================
-- FINAL VALIDATION: Fact Table Integrity & Metrics
-- ============================================================================

-- 1. Check row counts match staging
SELECT 
    'Staging Table' AS table_name, 
    COUNT(*) AS total_rows 
FROM stg_sparcs_raw
UNION ALL
SELECT 
    'Fact Table', 
    COUNT(*) 
FROM fact_hospital_encounter;

--"table_name"	"total_rows"
--"Fact Table"	2135260
--"Staging Table"	2135260

-- 2. Check for NULL foreign keys (should all be 0)
SELECT
    COUNT(CASE WHEN hospital_id IS NULL THEN 1 END) AS null_hospital_id,
    COUNT(CASE WHEN patient_id IS NULL THEN 1 END) AS null_patient_id,
    COUNT(CASE WHEN clinical_id IS NULL THEN 1 END) AS null_clinical_id,
    COUNT(CASE WHEN payment_id IS NULL THEN 1 END) AS null_payment_id,
    COUNT(CASE WHEN admission_id IS NULL THEN 1 END) AS null_admission_id
FROM fact_hospital_encounter;
--"null_hospital_id"	"null_patient_id"	"null_clinical_id"	"null_payment_id"	"null_admission_id"
--0	0	0	0	0

-- 3. Check for duplicates in dimensions (should return 0 rows)
SELECT 'dim_hospital' AS table_name, hospital_key, COUNT(*) 
FROM dim_hospital GROUP BY hospital_key HAVING COUNT(*) > 1
UNION ALL
SELECT 'dim_patient', patient_key, COUNT(*) 
FROM dim_patient GROUP BY patient_key HAVING COUNT(*) > 1
UNION ALL
SELECT 'dim_clinical', clinical_key, COUNT(*) 
FROM dim_clinical GROUP BY clinical_key HAVING COUNT(*) > 1
UNION ALL
SELECT 'dim_payment', payment_key, COUNT(*) 
FROM dim_payment GROUP BY payment_key HAVING COUNT(*) > 1
UNION ALL
SELECT 'dim_admission', admission_key, COUNT(*) 
FROM dim_admission GROUP BY admission_key HAVING COUNT(*) > 1;
-- no rows 

-- 4. Check uniqueness of encounters in fact table
SELECT 
    COUNT(*) AS total_fact_rows,
    COUNT(DISTINCT hospital_id || '-' || patient_id || '-' || clinical_id || '-' || admission_id) AS unique_encounters
FROM fact_hospital_encounter;
--"total_fact_rows"	"unique_encounters"
--2135260	1174866

-- 5. Quick statistics on charges/costs
SELECT
    COUNT(*) AS total_rows,
    MIN(total_charges) AS min_charges,
    MAX(total_charges) AS max_charges,
    ROUND(AVG(total_charges), 2) AS avg_charges,
    MIN(total_costs) AS min_costs,
    MAX(total_costs) AS max_costs,
    ROUND(AVG(total_costs), 2) AS avg_costs,
    MIN(cost_per_day) AS min_cost_per_day,
    MAX(cost_per_day) AS max_cost_per_day,
    ROUND(AVG(cost_per_day), 2) AS avg_cost_per_day
FROM fact_hospital_encounter;

--"total_rows"	"min_charges"	"max_charges"	"avg_charges"	"min_costs"	"max_costs"	"avg_costs"	"min_cost_per_day"	"max_cost_per_day"	"avg_cost_per_day"
--2135260	0.34	17935752.00	72834.98	0.15	12392868.33	21895.11	0.03	1803167.99	4696.13

-- 6. Sample check: top 5 combinations of hospital + patient age + clinical category
SELECT 
    h.facility_name,
    p.age_group,
    c.apr_drg_description,
    COUNT(*) AS encounter_count,
    ROUND(AVG(f.total_costs), 2) AS avg_cost
FROM fact_hospital_encounter f
JOIN dim_hospital h ON f.hospital_id = h.hospital_id
JOIN dim_patient p ON f.patient_id = p.patient_id
JOIN dim_clinical c ON f.clinical_id = c.clinical_id
GROUP BY h.facility_name, p.age_group, c.apr_drg_description
ORDER BY encounter_count DESC
LIMIT 5;

--"facility_name"	"age_group"	"apr_drg_description"	"encounter_count"	"avg_cost"
--"Cohen Children's Medical Center"	"0 to 17"	"NEONATE BIRTH WEIGHT > 2499 GRAMS, NORMAL NEWBORN OR NEONATE WITH OTHER PROBLEM"	6540	3389.89
--"New York-Presbyterian Hospital - New York Weill Cornell Center"	"0 to 17"	"NEONATE BIRTH WEIGHT > 2499 GRAMS, NORMAL NEWBORN OR NEONATE WITH OTHER PROBLEM"	6060	1377.75
--"North Shore University Hospital"	"0 to 17"	"NEONATE BIRTH WEIGHT > 2499 GRAMS, NORMAL NEWBORN OR NEONATE WITH OTHER PROBLEM"	5908	2834.73
--"Mount Sinai Hospital"	"0 to 17"	"NEONATE BIRTH WEIGHT > 2499 GRAMS, NORMAL NEWBORN OR NEONATE WITH OTHER PROBLEM"	5858	1646.63
--"Maimonides Medical Center"	"0 to 17"	"NEONATE BIRTH WEIGHT > 2499 GRAMS, NORMAL NEWBORN OR NEONATE WITH OTHER PROBLEM"	5258	3434.00