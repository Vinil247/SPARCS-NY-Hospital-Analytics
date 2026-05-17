-- ============================================================================
-- STAGING TABLE
-- ============================================================================
BEGIN;
DROP TABLE IF EXISTS stg_sparcs_raw CASCADE;

CREATE TABLE stg_sparcs_raw (
    "Hospital Service Area" TEXT,
    "Hospital County" TEXT,
    "Operating Certificate Number" TEXT,
    "Permanent Facility Id" TEXT,
    "Facility Name" TEXT,
    "Age Group" TEXT,
    "Zip Code - 3 digits" TEXT,
    "Gender" TEXT,
    "Race" TEXT,
    "Ethnicity" TEXT,
    "Length of Stay" TEXT,
    "Type of Admission" TEXT,
    "Patient Disposition" TEXT,
    "Discharge Year" TEXT,
    "CCSR Diagnosis Code" TEXT,
    "CCSR Diagnosis Description" TEXT,
    "CCSR Procedure Code" TEXT,
    "CCSR Procedure Description" TEXT,
    "APR DRG Code" TEXT,
    "APR DRG Description" TEXT,
    "APR MDC Code" TEXT,
    "APR MDC Description" TEXT,
    "APR Severity of Illness Code" TEXT,
    "APR Severity of Illness Description" TEXT,
    "APR Risk of Mortality" TEXT,
    "APR Medical Surgical Description" TEXT,
    "Payment Typology 1" TEXT,
    "Payment Typology 2" TEXT,
    "Payment Typology 3" TEXT,
    "Birth Weight" TEXT,
    "Emergency Department Indicator" TEXT,
    "Total Charges" TEXT,
    "Total Costs" TEXT
);

-- LOAD CSV
COPY stg_sparcs_raw
FROM '/Users/vinilpatel/PyTorch/sparcsV2.csv'
WITH (FORMAT CSV, HEADER, QUOTE '"', DELIMITER ',', ENCODING 'UTF8');
COMMIT;

begin;
UPDATE stg_sparcs_raw
SET
    "Total Charges" = REPLACE(REPLACE("Total Charges", '$',''), ',', ''),
    "Total Costs" = REPLACE(REPLACE("Total Costs", '$',''), ',', '')
WHERE
    "Total Charges" ILIKE '%$%'
    OR "Total Charges" ILIKE '%,%'
    OR "Total Costs" ILIKE '%$%'
    OR "Total Costs" ILIKE '%,%';

-- Cast to numeric
ALTER TABLE stg_sparcs_raw
ALTER COLUMN "Total Charges" TYPE NUMERIC USING NULLIF("Total Charges", '')::NUMERIC,
ALTER COLUMN "Total Costs" TYPE NUMERIC USING NULLIF("Total Costs", '')::NUMERIC;


-- FIX LENGTH OF STAY (remove "+")
UPDATE stg_sparcs_raw
SET "Length of Stay" = REPLACE("Length of Stay", '+', '')
WHERE "Length of Stay" LIKE '%+%';
COMMIT;


-- Fix dim_hospital first
BEGIN;
DROP TABLE IF EXISTS dim_hospital CASCADE;
CREATE TABLE dim_hospital (
    hospital_id SERIAL PRIMARY KEY,
    permanent_facility_id TEXT,
    facility_name TEXT NOT NULL,
    hospital_county TEXT,
    hospital_service_area TEXT,
    hospital_key TEXT UNIQUE
);

INSERT INTO dim_hospital (
    permanent_facility_id, 
    facility_name, 
    hospital_county, 
    hospital_service_area, 
    hospital_key
)
SELECT DISTINCT
COALESCE("Permanent Facility Id", 'Unknown') AS permanent_facility_id,
	"Facility Name", 
	COALESCE("Hospital County", 'Unknown') AS hospital_county,
	COALESCE("Hospital Service Area", 'Unknown') AS hospital_service_area,
    MD5(CONCAT(
        COALESCE("Permanent Facility Id", ''), 
        COALESCE("Facility Name", ''),
        COALESCE("Hospital County", ''),
        COALESCE("Hospital Service Area", '')
    )) AS hospital_key
FROM stg_sparcs_raw
WHERE "Facility Name" IS NOT NULL AND "Facility Name" != '';
COMMIT;
-- Patient
Begin;
DROP TABLE IF EXISTS dim_patient CASCADE;
CREATE TABLE dim_patient (
    patient_id SERIAL PRIMARY KEY,
    age_group TEXT,
    gender TEXT,
    race TEXT,
    ethnicity TEXT,
    patient_key TEXT UNIQUE
);

INSERT INTO dim_patient (age_group, gender, race, ethnicity, patient_key)
SELECT DISTINCT
	CASE 
		WHEN "Age Group" IN ('0 to 17', '0-17') THEN '0-17'
		WHEN "Age Group" IN ('18 to 29', '18-29') THEN '18-29'
		WHEN "Age Group" IN ('30 to 49', '30-49') THEN '30-49'
		WHEN "Age Group" IN ('50 to 69', '50-69') THEN '50-69'
		WHEN "Age Group" = '70 or Older' THEN '70+'
		ELSE "Age Group" 
	END AS age_group,
    "Gender",
    "Race",
    "Ethnicity",
    MD5(CONCAT(
        COALESCE("Age Group", ''),
        COALESCE("Gender", ''),
        COALESCE("Race", ''),
        COALESCE("Ethnicity", '')
    )) AS patient_key
FROM stg_sparcs_raw
WHERE "Age Group" IS NOT NULL;
commit;

-- Clinical
BEGIN;
DROP TABLE IF EXISTS dim_clinical CASCADE;

CREATE TABLE dim_clinical (
    clinical_id SERIAL PRIMARY KEY,
    apr_drg_code TEXT,
    ccsr_diagnosis_code TEXT,
    apr_severity_code TEXT,
    ccsr_diagnosis_description TEXT,
    apr_drg_description TEXT,
    severity_label TEXT,
    clinical_key TEXT UNIQUE
);

INSERT INTO dim_clinical (
    apr_drg_code, 
    ccsr_diagnosis_code, 
    apr_severity_code,
    ccsr_diagnosis_description, 
    apr_drg_description, 
    severity_label, 
    clinical_key
)
SELECT 
    "APR DRG Code",
    "CCSR Diagnosis Code",
    "APR Severity of Illness Code",
    MAX("CCSR Diagnosis Description") as ccsr_diagnosis_description,
    MAX("APR DRG Description") as apr_drg_description,
    
    CASE 
        WHEN "APR Severity of Illness Code" IN ('3','4') THEN 'High Severity'
        WHEN "APR Severity of Illness Code" IN ('0','1','2') THEN 'Low-Moderate Severity'
        ELSE 'Unknown'
    END as severity_label,
    MD5(CONCAT(
        COALESCE("APR DRG Code", ''),
        COALESCE("CCSR Diagnosis Code", ''),
        COALESCE("APR Severity of Illness Code", '')
    )) AS clinical_key
FROM stg_sparcs_raw
WHERE "APR DRG Code" IS NOT NULL
GROUP BY 
    "APR DRG Code", 
    "CCSR Diagnosis Code", 
    "APR Severity of Illness Code";

COMMIT;

-- Payment
BEGIN;
DROP TABLE IF EXISTS dim_payment CASCADE;
CREATE TABLE dim_payment (
    payment_id SERIAL PRIMARY KEY,
    payment_typology TEXT,
    payer_category TEXT,
    payment_key TEXT UNIQUE
);

INSERT INTO dim_payment(payment_typology, payer_category, payment_key)
SELECT DISTINCT
    "Payment Typology 1",
	CASE
	    WHEN "Payment Typology 1" LIKE '%Medicare%' THEN 'Medicare'
	    WHEN "Payment Typology 1" LIKE '%Medicaid%' THEN 'Medicaid'
	
	    WHEN "Payment Typology 1" LIKE '%Private%' 
	      OR "Payment Typology 1" LIKE '%Commercial%' 
	      OR "Payment Typology 1" LIKE '%Blue Cross%' 
	      OR "Payment Typology 1" LIKE '%Managed Care%' THEN 'Private'
	
	    WHEN "Payment Typology 1" LIKE '%Self%' THEN 'Self-Pay'
	
	    WHEN "Payment Typology 1" LIKE '%Federal%' 
	      OR "Payment Typology 1" LIKE '%State%' 
	      OR "Payment Typology 1" LIKE '%Local%' 
	      OR "Payment Typology 1" LIKE '%VA%' 
	      OR "Payment Typology 1" LIKE '%Corrections%' THEN 'Government'
    	ELSE 'Other'
	END,
    MD5("Payment Typology 1")
FROM stg_sparcs_raw
WHERE "Payment Typology 1" IS NOT NULL;
COMMIT;

-- Admission
BEGIN;
DROP TABLE IF EXISTS dim_admission CASCADE;
CREATE TABLE dim_admission (
    admission_id SERIAL PRIMARY KEY,
    type_of_admission TEXT,
    patient_disposition TEXT,
    is_emergency BOOLEAN,
    admission_key TEXT UNIQUE
);

INSERT INTO dim_admission (type_of_admission, patient_disposition, is_emergency, admission_key)
SELECT DISTINCT
    "Type of Admission",
    "Patient Disposition",
    ("Emergency Department Indicator" = 'Y'),
    MD5(CONCAT(
        "Type of Admission",
        "Patient Disposition",
        ("Emergency Department Indicator" = 'Y')
    ))
FROM stg_sparcs_raw
WHERE "Type of Admission" IS NOT NULL;
COMMIT;

-- ============================================================================
-- FACT TABLE
-- ============================================================================
BEGIN;
DROP TABLE IF EXISTS fact_hospital_encounter CASCADE;

CREATE TABLE fact_hospital_encounter (
    encounter_id SERIAL PRIMARY KEY,
    hospital_id INT NOT NULL REFERENCES dim_hospital(hospital_id),
    patient_id INT NOT NULL REFERENCES dim_patient(patient_id),
    clinical_id INT NOT NULL REFERENCES dim_clinical(clinical_id),
    payment_id INT REFERENCES dim_payment(payment_id),
    admission_id INT NOT NULL REFERENCES dim_admission(admission_id),
    discharge_year INT,
    length_of_stay INT,
    total_charges NUMERIC(15,2),
    total_costs NUMERIC(15,2),
    cost_per_day NUMERIC(15,2),
    has_procedure BOOLEAN,
    has_complete_data BOOLEAN
);

INSERT INTO fact_hospital_encounter (
    hospital_id, patient_id, clinical_id, payment_id, admission_id,
    discharge_year, length_of_stay, total_charges, total_costs,
    cost_per_day, has_procedure, has_complete_data
)
SELECT
    h.hospital_id,
    p.patient_id,
    c.clinical_id,
    pa.payment_id,
    a.admission_id,
    CAST(r."Discharge Year" AS INT),
    CAST(r."Length of Stay" AS INT),
    r."Total Charges",
    r."Total Costs",
    CASE 
        WHEN CAST(r."Length of Stay" AS INT) > 0
        THEN ROUND(r."Total Costs" / CAST(r."Length of Stay" AS INT), 2)
        ELSE NULL
    END,
	CASE 
    	WHEN r."CCSR Procedure Code" IS NULL 
		OR r."CCSR Procedure Code" IN ('', 'nan', 'NaN', 'N/A')
   	 	THEN FALSE
    ELSE TRUE
	END,
    r."Total Charges" IS NOT NULL AND r."Total Costs" IS NOT NULL
FROM stg_sparcs_raw r

JOIN dim_hospital h 
    ON MD5(CONCAT(
		COALESCE(r."Permanent Facility Id", ''), 
		COALESCE(r."Facility Name", ''), 
		COALESCE(r."Hospital County", ''), 
		COALESCE(r."Hospital Service Area", '')
	)) = h.hospital_key
JOIN dim_patient p
    ON MD5(CONCAT(
		COALESCE(r."Age Group", ''),
		COALESCE(r."Gender", ''),
		COALESCE(r."Race", ''),
		COALESCE(r."Ethnicity", '')
	)) = p.patient_key
LEFT JOIN dim_payment pa 
    ON MD5(r."Payment Typology 1") = pa.payment_key
JOIN dim_admission a
    ON MD5(CONCAT(
			r."Type of Admission",
			r."Patient Disposition", 
			(r."Emergency Department Indicator" = 'Y')
		)) = a.admission_key

JOIN dim_clinical c
    ON MD5(CONCAT(
        COALESCE(r."APR DRG Code", ''),
        COALESCE(r."CCSR Diagnosis Code", ''),
        COALESCE(r."APR Severity of Illness Code", '')
    )) = c.clinical_key

WHERE r."Total Charges" IS NOT NULL AND r."Total Costs" IS NOT NULL;
COMMIT;

-- ============================================================================
-- INDEXES
-- ============================================================================

CREATE INDEX idx_fact_hospital ON fact_hospital_encounter(hospital_id);
CREATE INDEX idx_fact_clinical ON fact_hospital_encounter(clinical_id);
CREATE INDEX idx_fact_year ON fact_hospital_encounter(discharge_year);
CREATE INDEX idx_fact_costs ON fact_hospital_encounter(total_costs);

-- ============================================================================
-- VALIDATION
-- ============================================================================

-- Check for duplicates
SELECT 'Check for duplicate business keys:' as check_name;

SELECT 'dim_hospital' as table_name, hospital_key, COUNT(*) 
FROM dim_hospital GROUP BY hospital_key HAVING COUNT(*) > 1
UNION ALL
SELECT 'dim_patient', patient_key, COUNT(*) 
FROM dim_patient GROUP BY patient_key HAVING COUNT(*) > 1
UNION ALL  
SELECT 'dim_clinical', clinical_key, COUNT(*) 
FROM dim_clinical GROUP BY clinical_key HAVING COUNT(*) > 1;

-- Final row counts
SELECT 'Row count verification:' as check_name;

SELECT 
    'Staging Table' AS table_name, 
    COUNT(*) AS total_rows 
FROM stg_sparcs_raw
UNION ALL
SELECT 
    'Fact Table', 
    COUNT(*) 
FROM fact_hospital_encounter;

-- Sample data preview
SELECT 'Sample data from fact table:' as check_name;
SELECT 
    h.facility_name,
    p.age_group,
    c.apr_drg_description,
    COUNT(*) as encounter_count,
    ROUND(AVG(f.total_costs), 2) as avg_cost
FROM fact_hospital_encounter f
JOIN dim_hospital h ON f.hospital_id = h.hospital_id
JOIN dim_patient p ON f.patient_id = p.patient_id  
JOIN dim_clinical c ON f.clinical_id = c.clinical_id
GROUP BY h.facility_name, p.age_group, c.apr_drg_description
ORDER BY encounter_count DESC
LIMIT 5;

