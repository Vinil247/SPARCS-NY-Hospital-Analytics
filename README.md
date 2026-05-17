# NYS Hospital Analytics

Analyzed 8.5M NY hospital discharge records to trace how costs, clinical severity, race, and regional market structure interact — finding that high-severity stays drive costs through length, not daily intensity; that Black patients average nearly one extra day in the hospital at the same severity level; and that regional markets are dominated by a single high-cost academic center.

## Structure

```
├── schema/
│   ├── star_schema.sql        — Full ETL: staging → 5 dimensions → fact table
│   └── schema_validation.sql  — Row count & referential integrity checks
└── analysis/
    ├── 01_executive_market_overview.sql    — Regional volume, cost bands, market share
    ├── 02_clinical_operations.sql          — Severity benchmarks, diagnosis costs, surgical vs medical
    ├── 03_financial_payer_mix.sql          — Payer concentration, cost variance, facility mix
    ├── 04_patient_demographics.sql         — Demographics, equity analysis, admission source
    └── 05_clinical_quality_outcomes.sql    — Mortality, facility scorecard, SNF transfer analysis
```

## Key Findings

- **Cost follows severity, but through length, not daily intensity** — High Severity cases cost 2.7x more and stay 5 days longer, yet their daily cost is *lower*. The extra spend comes from drawn-out stays, not expensive daily treatment.
- **Race predicts length of stay after controlling for severity** — Black/African American patients average nearly one extra hospital day compared to White patients at the same severity level (555K High Severity cases).
- **Regional markets are winner-take-most** — The top academic medical center in each region captures 2-3x the volume of the next hospital and charges significantly more per case, reflecting a high-acuity referral funnel.

## Schema

Star schema with `fact_hospital_encounter` at the center, joined to five dimensions: `dim_hospital`, `dim_patient`, `dim_clinical`, `dim_payment`, `dim_admission`. Built with surrogate keys, MD5 business key hashes, deduplication, and referential integrity constraints.

## Data Source

New York State SPARCS (Statewide Planning and Research Cooperative System) hospital discharge data.

## Running

1. Update the `COPY` path in `schema/star_schema.sql` to point to your SPARCS CSV export
2. Run the full script (staging → dimensions → fact → indexes)
3. Optionally run `schema/schema_validation.sql` to verify integrity
4. Explore the `analysis/` queries against your loaded fact table
