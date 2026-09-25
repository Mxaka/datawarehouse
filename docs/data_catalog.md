# Data Catalog: Gold Layer

The gold layer is the business-ready star schema, built as MySQL views over
`silver`. This catalog describes each object as actually built — see
`scripts/gold/ddl_gold.sql` for the exact SQL.

Two subject areas share one date dimension:

- **Retail sales and prices** (from Stats SA) — `fact_retail_sales`, `fact_cpi_headline`
- **Interest and exchange rates** (from SARB) — `fact_monthly_rates`

---

## gold_layer.dim_date

One row per calendar month, spanning every source. Built as a recursive CTE
over the earliest and latest month across Stats SA (already month-level) and
SARB (daily, rolled up to the first of its month) — so a month with SARB data
but no Stats SA release yet, or vice versa, still gets a row.

| Column | Type | Description |
|---|---|---|
| `date_key` | INT | Surrogate key, `YYYYMM` as a number (e.g. `202609`) |
| `month_start_date` | DATE | First day of the month |
| `year_number` | INT | |
| `quarter_number` | INT | 1–4 |
| `month_number` | INT | 1–12 |
| `month_name` | VARCHAR | e.g. `'September'` |

**Range (as loaded):** January 2002 to September 2026 (297 rows), driven by
Stats SA's retail totals at the early end and SARB's latest download at the
late end.

## gold_layer.dim_retailer_type

One row per Stats SA retail dealer type, plus the total.

| Column | Type | Description |
|---|---|---|
| `retailer_type_key` | INT | Surrogate key. `'All retailers'` is always key 1 |
| `retailer_type_name` | VARCHAR | e.g. `'General dealers'`, `'All retailers'` |

**Rows:** 8 (7 dealer types + the total).

## gold_layer.dim_sales_basis

The four ways Stats SA publishes each retail figure.

| Column | Type | Description |
|---|---|---|
| `sales_basis_key` | INT | Surrogate key |
| `price_basis` | VARCHAR | `'Current prices'` or `'Constant prices'` |
| `adjustment` | VARCHAR | `'Actual'` or `'Seasonally adjusted'` |
| `unit` | VARCHAR | `'R million'` |

**Rows:** 4 (2 × 2 combinations).

## gold_layer.dim_geography

Geographies that have a headline (`'All Items'`) CPI series: the 9 provinces,
rural areas, and the total country.

| Column | Type | Description |
|---|---|---|
| `geography_key` | INT | Surrogate key. `'Total country'` is always key 1 |
| `geography_name` | VARCHAR | e.g. `'Western Cape'`, `'Total country'` |

**Rows:** 11.

## gold_layer.dim_rate_indicator

One row per SARB series downloaded.

| Column | Type | Description |
|---|---|---|
| `indicator_key` | INT | Surrogate key |
| `series_code` | VARCHAR | SARB's code, e.g. `MMRD002A` (from the source file name) |
| `indicator_name` | VARCHAR | SARB's own label, e.g. `'SARB Policy Rate'`, `'Prime lending rate'` |
| `unit` | VARCHAR | `'Percent'` for rates, `'ZAR per unit'` for exchange rates — inferred from the code prefix (`MM` vs `EXC`), since SARB's JSON has no unit field |

**Naming note:** `MMRD002A` is labelled `"SARB Policy Rate"` in the live API,
not `"repo rate"`. Same underlying rate (set by the Monetary Policy Committee
to hit the inflation target); the API's own label is stored as-is.

**Rows:** 3, as currently downloaded (repo/policy rate, prime rate, one rand
exchange rate — Euro at the time of writing; see `docs/DATASOURCES.md` for
swapping in the US Dollar rate).

---

## gold_layer.fact_retail_sales

Grain: one row per month × retailer type × sales basis.

| Column | Type | Description |
|---|---|---|
| `date_key` | INT | FK → `dim_date` |
| `retailer_type_key` | INT | FK → `dim_retailer_type` |
| `sales_basis_key` | INT | FK → `dim_sales_basis` |
| `sales_rm` | DECIMAL(18,3) | Retail sales value, R million |

**Source:** `silver_layer.statssa_retail_observations` joined to
`silver_layer.statssa_retail_series` for its retailer type and sales basis.
**Rows:** 7,928 — equal to silver's row count; every observation reaches gold_layer.

## gold_layer.fact_cpi_headline

Grain: one row per month × geography, for the headline (`'All Items'`) CPI
series only. All 784 CPI series (including the analytic ones, like CPI for
pensioners) are still in `silver_layer.statssa_cpi_observations` — this fact is
scoped to the ones most useful for a first analytical query.

| Column | Type | Description |
|---|---|---|
| `date_key` | INT | FK → `dim_date` |
| `geography_key` | INT | FK → `dim_geography` |
| `cpi_index` | DECIMAL(12,3) | Index value, December 2024 = 100 |

**Source:** `silver_layer.statssa_cpi_observations` filtered to `product = 'All Items'`.
**Rows:** 2,453 (11 geographies × 223 months).

## gold_layer.fact_monthly_rates

Grain: one row per month × SARB indicator, rolled up from SARB's daily data.

| Column | Type | Description |
|---|---|---|
| `date_key` | INT | FK → `dim_date` |
| `indicator_key` | INT | FK → `dim_rate_indicator` |
| `avg_value` | DECIMAL(12,4) | Mean of the days observed that month |
| `month_end_value` | DECIMAL(12,4) | Value on the latest observed day of the month |

**Two measures, deliberately:** `avg_value` smooths a month's daily
movements; `month_end_value` is the single point-in-time figure most people
mean by "the rate that month." SARB publishes business days only, so
`avg_value` is a business-day average, not a calendar-day one, and
`month_end_value` is the true calendar month-end value only once SARB has
published through to that day.

**Source:** `silver_layer.sarb_observations`, using window functions
(`AVG() OVER`, `ROW_NUMBER() OVER`) rather than `GROUP BY`, so both measures
come from the same partition without a self-join.
**Rows:** matches the distinct (series, month) count in silver — 6 with the
current sample data (3 series × 2 months).

---

## Known data characteristics

Found while building and testing this layer — worth knowing before you query
it or explain it in the demo:

- **Retailer types reconcile to the total within rounding.** The 7 retailer
  types sum to `'All retailers'` within R2 million in every month (Stats SA
  rounds each published series independently). `test/quality_checls_silver.sql`
  check 9 enforces this.
- **Two CPI analytic series end early.** `CPS51100` and `CPS51200` (regulated
  and non-regulated administered prices) stop in December 2024, while every
  other series runs to the latest release. Confirmed against the source file
  — not a load error. Silver check 7 documents this; neither series feeds
  `fact_cpi_headline`.
- **SARB's daily data is business days only.** No weekend or public holiday
  rows — `fact_monthly_rates.avg_value` reflects that.

## Sample query

```sql
-- Total retail sales (current prices, actual) next to headline CPI, by month
SELECT d.month_start_date,
       f.sales_rm       AS retail_sales_rm,
       c.cpi_index      AS cpi_total_country
FROM gold_layer.fact_retail_sales f
JOIN gold_layer.dim_date d          ON d.date_key = f.date_key
JOIN gold_layer.dim_retailer_type r ON r.retailer_type_key = f.retailer_type_key
                             AND r.retailer_type_name = 'All retailers'
JOIN gold_layer.dim_sales_basis b   ON b.sales_basis_key = f.sales_basis_key
                             AND b.price_basis = 'Current prices' AND b.adjustment = 'Actual'
JOIN gold_layer.fact_cpi_headline c ON c.date_key = f.date_key
JOIN gold_layer.dim_geography g     ON g.geography_key = c.geography_key
                             AND g.geography_name = 'Total country'
ORDER BY d.month_start_date DESC
LIMIT 12;
```

See `docs/SETUP_AND_RUN.md` for more sample queries, including the SARB
monthly rates query.