# insurance-medallion-dbt

*Context for Claude Code. Part of the DE Portfolio at `~/Desktop/DE Portfolio 2026/`.*

## What this is

Bronze → Silver → Gold warehouse for P&C insurance data, in dbt on BigQuery. A port of
`../snowflake-medallion` onto the stack named in Procom req 330459 (BigQuery + dbt +
Power BI), built to learn the tools using a domain Mahesh already knows.

**Stack:** dbt 1.11 · dbt-bigquery 1.12 · BigQuery project `af-delinquency-de-2026`,
dataset `insurance_medallion`, Montreal region
**GitHub:** private

## Running it

```bash
gcloud auth application-default login   # if credentials expired
dbt build --profiles-dir .
```

Expect `PASS≈40 WARN=2 ERROR=0`. The two warnings are deliberate Bronze duplicates.

## Know this before working on it

- **Stage 5 finally ships here.** The reconciliation gate has been claimed on the resume
  and in the `snowflake-medallion` GitHub description since 1 Sep and had never run. It
  runs on every build in this project.
- **The blind-spot story is the most valuable thing in the repo.** The first build passed
  every test while all 12,000 claims failed to join — a LEFT JOIN matching nothing
  preserves row counts and sums, so the reconciliation gate saw nothing wrong. Read the
  "what went wrong" section of the README before touching the gates.
- **Bronze does not cast.** Strings only. Don't "tidy" it.
- Expected counts are in the README. Check every build against them, not against green.

## House rules

- One instruction at a time. Write it and explain *why*; Mahesh runs it and reports back.
- Compute expected numbers from the source **before** running anything.
- Don't commit secrets. `profiles.yml` uses oauth, no keys — keep it that way.
