# Insurance Medallion — dbt on BigQuery

A Bronze → Silver → Gold warehouse for P&C insurance policy, claims and broker data,
built in dbt on Google BigQuery. Same domain and same medallion shape as the Snowflake
version of this project — rebuilt on a different stack to learn where the two differ.

```
seeds (raw CSV)
   │
   ▼
BRONZE   as sent. no casting, no dedupe, no filtering.
   │     union of two policy extracts, extract_date preserved
   ▼
SILVER   typed, conformed, deduped.  SCD Type 2 on policies.
   │
   ▼
GOLD     dim_policy (SCD2) · dim_broker · dim_date · fct_claim
   │
   ▼
two reconciliation gates
```

## The numbers

Every one of these was computed from the source **before** the build ran, then checked
against the warehouse afterwards. That is the method, not a formality — see "what went
wrong" below.

| | |
|---|---|
| Policies | 5,000 distinct, across two extracts (2026-08-01, 2026-08-15) |
| Policies that changed | **602** — premium in 602, status in 448 |
| `dim_policy` rows | **5,602** = 5,000 + 602 second versions |
| Claims | 12,060 raw → **12,000** after dedupe |
| Brokers | 51 raw → **50** after dedupe |
| Unparseable claim dates | 259 → 55 recovered, **204** genuinely null |

## The layer rules

**Bronze does not cast.** Everything stays a string, nothing is deduped, nothing is
filtered. The only additions are `_source_file` and `_loaded_at`, underscore-prefixed so
they can never collide with a source column. Once you've cleaned data in Bronze you can
no longer prove what the source actually sent.

**Tests live at the layer that makes the guarantee.** `unique` on `bronze_claims.claim_id`
is set to **warn** — Bronze promises fidelity, not uniqueness, and those 60 duplicates are
real and should be reported every build. The same test on `silver_claims.claim_id` is a
hard **error**, because Silver does promise it. A test that never fires is a test nobody
reads.

**Silver flags what it couldn't fix.** 259 claim dates are unparseable. 55 of them read
`31/12/2025` — a real date in `DD/MM/YYYY`, recovered by a `parse_date` fallback rather
than binned. The remaining 204 get `claim_date_is_valid = false` so nothing downstream has
to guess whether a null date is missing or was mangled.

## SCD Type 2

`silver_policies` builds version history from the two extracts using a hash of the tracked
attributes — the same idea Data Vault calls a hashdiff. Comparing four columns with OR-ed
inequalities breaks on NULLs, because `NULL != NULL` isn't true.

`fct_claim` then does a **point-in-time join**:

```sql
on  c.policy_id  = p.policy_natural_key
and c.claim_date between p.valid_from and p.valid_to
```

A claim from 5 August joins to the premium in force on 5 August. Join to `is_current`
instead and every historical report silently restates itself whenever a policy changes.

## The gates

| Test | Guards against |
|---|---|
| `assert_claims_reconcile` | Rows or amounts lost between Silver and Gold |
| `assert_scd2_windows_do_not_overlap` | Overlapping validity windows — a claim matching two versions and doubling every measure |
| `assert_claims_match_a_policy` | Claims with a good date that still fail to join |

## What went wrong, and why it's the best thing in this repo

The first build passed with `PASS=39 WARN=2 ERROR=0`. Every test green, both gates
satisfied. **And every single one of the 12,000 claims had failed to join to a policy.**

The reconciliation gate compares row counts and total amount between Silver and Gold. A
`LEFT JOIN` that matches nothing preserves both perfectly — 12,000 rows in, 12,000 out,
every amount intact. The gate was working exactly as written and reported success while
the central join of the warehouse was returning nothing.

The cause: `valid_from` on the first version of each policy was stamped as the first
extract date, 2026-08-01. The claims go back to 2024. Nothing older than the first
snapshot could fall inside any window.

Two fixes. The first version's `valid_from` is now floored to `1900-01-01`, so the
dimension can serve history that predates the first extract. And a third gate was added
that measures **match rate** rather than volume.

The lesson is the second one. **A gate only guards what it measures.** Counting rows
proves you didn't lose anything; it says nothing about whether the join worked.

## Run it

```bash
pip install dbt-bigquery
gcloud auth application-default login
dbt seed  --profiles-dir .
dbt build --profiles-dir .
```

Free tier covers this comfortably — about 17,000 rows total against 1 TB/month of query
and 10 GB of storage.

## CI

`.github/workflows/dbt.yml` runs on every pull request: `dbt parse` to prove every model
compiles and every `ref()` resolves, plus a check that no model ships without a
description. It does **not** run a full build — that needs warehouse credentials, and a
service account key in a repo secret is a real credential with real blast radius. Full
builds run locally.
