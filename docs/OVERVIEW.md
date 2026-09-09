# What this project is actually for

Read this before the code. Everything in the repo exists to solve one of the four problems
below, and if you can say these out loud you can defend the whole build.

---

## 1. The business

A property & casualty insurer sells **policies** through **brokers**. When something goes
wrong, the customer files a **claim**. Premium comes in, claims go out, and the entire
business rests on one question:

> **Are we charging enough for the risk we're taking on?**

That's the **loss ratio** — claims paid divided by premium earned. Under 100% and the
book is profitable before expenses. Over it and you're selling money.

Four groups need it cut differently:

| Who | What they ask | When |
|---|---|---|
| **Underwriting** | Loss ratio by product, region, broker — where is pricing wrong? | Monthly |
| **Claims** | How many open, how old, what's reserved? | Daily |
| **Finance** | Total exposure and earned premium for the close | Month end |
| **Broker management** | Which brokers bring profitable business, not just volume? | Quarterly |

The operational systems that run the business can answer none of these. They're built to
process one transaction at a time, not to sum two years of them by product.

---

## 2. The four hard problems

These are what make this an engineering job rather than a `GROUP BY`.

### Problem 1 — policies change, and reports must not

A policy isn't static. Premiums get adjusted mid-term, status moves from active to
lapsed, coverage gets endorsed. In this data, **602 of 5,000 policies changed** across two
weeks.

If you store one row per policy and overwrite it, **last quarter's loss ratio changes
every time somebody amends a policy.** Finance closes the books in April and gets a
different number in May, with no way to explain the difference. Nobody can tell whether
the business moved or the data did.

**Solved by:** SCD Type 2 in `silver_policies`. One row per policy *per version*, each
stamped with the window it was true for. 5,000 policies become 5,602 rows.

### Problem 2 — a claim belongs to the policy as it was *then*

A claim filed in June, against a policy whose premium changed in August, must be measured
against June's premium. Join it to today's premium and you've restated history.

**Solved by:** the point-in-time join in `fct_claim`:

```sql
on  c.policy_id  = p.policy_natural_key
and c.claim_date between p.valid_from and p.valid_to
```

This is the payoff of problem 1. SCD2 without a point-in-time join is just storage.

### Problem 3 — source systems send bad data, constantly

Not hypothetically. In this source:

| Defect | Count |
|---|---|
| Unparseable claim dates (`N/A`, `0000-00-00`, `2026-13-45`, `31/12/2025`) | 259 |
| Duplicate claim IDs from re-exports | 60 |
| Duplicate broker row | 1 |
| Duplicate policies within a single extract | 25 per file |
| Claims pointing at policy IDs that don't exist | 129 |
| Status spellings of 4 real values | 12 |

**The wrong answer is to drop the bad rows.** Then your claim count is quietly short and
nobody knows why.

**Solved by:** Bronze keeps everything as sent. Silver conforms what it can, **recovers**
what looks broken but isn't (55 of those dates were `DD/MM/YYYY` — real dates in the wrong
format), and **flags** what it can't fix so nothing downstream has to guess.

### Problem 4 — loads fail silently, and that's the dangerous one

A job can report success having brought half the file. Everything downstream agrees with
everything else. Every test passes. The warehouse reports half a business and looks
perfectly healthy doing it.

**Solved by:** control totals that arrive **with the data**, and get checked against what
landed. Row count and hash total, the way a real batch interface sends a trailer record.

This is the same check run at Caplin Point in 2018 against plant systems, and at Tokio
Marine today blocking promotion between layers. **Three industries, one habit.**

---

## 3. Why three layers

Not ceremony. Each one has a rule, and the rules are what make the thing debuggable.

| Layer | Rule | Why |
|---|---|---|
| **Bronze** | Change nothing. Strings only, no dedupe, no filtering | Once you've cleaned it you can no longer prove what the source sent. When a number is wrong in six months, this is how you tell whether it came in broken or you broke it |
| **Silver** | Conform, dedupe, type — and flag what you couldn't fix | One place where "what does this mess mean" is decided, on the record |
| **Gold** | Shape for the question being asked | Facts and dimensions the BI tool reads. Nothing here parses raw text |

**Tests live at the layer that makes the guarantee.** `unique` on Bronze claim IDs is a
**warning** — Bronze promises fidelity, not uniqueness. The same test on Silver is a hard
**error**, because Silver does promise it. A check that fires on every build forever is a
check the team switches off.

---

## 4. The gates, and what each one is actually afraid of

| Gate | The failure it's watching for |
|---|---|
| `assert_source_control_total` | **A silent partial load.** The only check anchored outside the warehouse |
| `assert_claims_reconcile` | Rows or money lost between Silver and Gold |
| `assert_scd2_windows_do_not_overlap` | Two versions valid on the same day — every measure silently doubles |
| `assert_claims_match_a_policy` | The join breaking, as distinct from rows going missing |

**The last one exists because the first two weren't enough.** The reconciliation gate
passed while all 12,000 claims failed to join — a `LEFT JOIN` that matches nothing
preserves row counts and sums perfectly. A gate only guards what it measures.

---

## 5. What's still missing

**The warehouse can't yet answer the question in section 1.**

`fct_claim` holds claims. `dim_policy` holds premium. Nothing joins them into a loss
ratio. Right now the model answers *"what claims exist"* but not *"are we pricing
correctly"* — which is the reason the business would fund it.

The missing piece is a Gold mart at the grain of **policy version × month**, carrying
earned premium and incurred claims, so loss ratio can be sliced by product, region and
broker. That's the next build, and it's what Power BI would sit on.

---

## 6. Saying it in one breath

> "It's a warehouse for P&C insurance — policies, claims, brokers. The real problem is
> that policies change, so if you overwrite them, last quarter's numbers change too and
> nobody can reproduce a report. So policies are SCD Type 2, and claims join to the
> version that was in force on the claim date rather than today's version.
>
> The other half is that source systems send bad data and failed loads look like
> successful ones. So Bronze keeps everything exactly as sent, Silver conforms it and
> flags what it can't fix, and there's a control total from the source that has to tie
> before anything gets promoted."
