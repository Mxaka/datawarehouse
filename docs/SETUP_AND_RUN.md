# Setup and Run Guide

## Prerequisites

- **MySQL Server 8.0 or later** and **MySQL Workbench**. Check the version with `SELECT VERSION();`
- **Python 3.8+** (no packages needed)
- This repo on disk, with the two Stats SA **ASCII** files unzipped into `datasets/source_statssa/`
- `LOAD DATA INFILE` enabled on the server and in your Workbench connection:
  1. `SHOW VARIABLES LIKE 'local_infile';` If it's `OFF`, run `SET GLOBAL local_infile = 1;` (needs admin rights)
  2. In Workbench, edit your connection → Advanced tab → add `OPT_LOCAL_INFILE=1` under "Others"
  3. Disconnect and reconnect
- Only if you load SARB JSON with `LOAD_FILE`: run `SHOW VARIABLES LIKE 'secure_file_priv';` and keep the JSON files in that folder. Your account also needs the `FILE` privilege

## Run order

| Step | What | Notes |
|---|---|---|
| 0a | `python ingestion/statssa_to_csv.py "datasets/ASCII_RTS.txt" "datasets/ASCII_CPI.txt"` | Creates `statssa_series.csv` and `statssa_values.csv` |
| 0b | `python ingestion/download_sarb.py` then `python ingestion/sarb_to_csv.py datasets/source_sarb/*.json` | Downloads SARB series, then creates `sarb_series.csv` and `sarb_observations.csv` |
| 1 | `scripts/init_database.sql` | Drops and recreates the `bronze_layer`, `silver_layer` and `gold_layer` databases. **Deletes everything in them** |
| 2 | `scripts/bronze/ddl_bronze.sql` | Creates the bronze tables |
| 3 | `scripts/bronze/load_bronze.sql` | **Edit all four file paths first** (forward slashes, e.g. `C:/Users/you/dwh/datasets/source_statssa/statssa_series.csv`) — two for Stats SA, two for SARB. A plain script, not a procedure |
| 4 | `scripts/silver/ddl_silver.sql` | Creates the silver tables |
| 5 | `scripts/silver/load_silver.sql` | Creates the procedure, then run `CALL silver_layer.load_silver();` |
| 6 | `scripts/gold/ddl_gold.sql` | Creates the gold views (no load step) |
| 7 | `tests/quality_checks_silver.sql` | Checks 7, 10 and 15 return rows on purpose (see below) |
| 8 | `tests/quality_checks_gold.sql` | Every check should return no rows |

Run each file with **Execute Script** (the lightning bolt), not "Execute current statement", or only the first statement will run. Files containing procedures use `DELIMITER`, which Workbench's SQL editor understands.

## Expected row counts (Stats SA, July 2026 release)

Measured by running these exact scripts on MySQL 8.0 against the uploaded files. A later Stats SA release will have more months.

| Table | Rows | Notes |
|---|---|---|
| `bronze_layer.statssa_series` | 816 | 32 retail + 784 CPI |
| `bronze_layer.statssa_values` | 176,864 | 7,928 retail + 168,936 CPI |
| `bronze_layer.sarb_series` | 3 | One per downloaded series |
| `bronze_layer.sarb_observations` | 75 | 25 business days × 3 series (your window will differ) |
| `silver_layer.statssa_retail_series` | 32 | |
| `silver_layer.statssa_retail_observations` | 7,928 | Equals bronze |
| `silver_layer.statssa_cpi_series` | 784 | |
| `silver_layer.statssa_cpi_observations` | 168,936 | Equals bronze |
| `silver_layer.sarb_series` | 3 | |
| `silver_layer.sarb_observations` | 75 | Equals bronze |
| `gold_layer.dim_date` | 297 | January 2002 to September 2026 (extended by SARB's later dates) |
| `gold_layer.dim_retailer_type` | 8 | 7 types plus 'All retailers' |
| `gold_layer.dim_sales_basis` | 4 | Current/Constant × Actual/Seasonally adjusted |
| `gold_layer.dim_geography` | 11 | |
| `gold_layer.dim_rate_indicator` | 3 | One per SARB series |
| `gold_layer.fact_retail_sales` | 7,928 | |
| `gold_layer.fact_cpi_headline` | 2,453 | 11 geographies × 223 months |
| `gold_layer.fact_monthly_rates` | 6 | 3 series × 2 months in the sample data |

## What the quality checks should show

- **Silver checks 1 to 6, 8, 9, 11 to 14:** no rows
- **Silver check 7:** exactly 2 rows, `CPS51100` and `CPS51200`, the two CPI analytic series that stop in December 2024. This is a property of the source data
- **Silver check 10:** 4 rows (the standard price basis and adjustment labels)
- **Silver check 15:** one row per SARB series (informational — compare the date range to what you downloaded)
- **Gold checks 1 to 5:** no rows

## Try it: a first analytical query

```sql
-- SARB monthly averages by indicator
SELECT ri.indicator_name, d.month_start_date, f.avg_value, f.month_end_value, ri.unit
FROM gold_layer.fact_monthly_rates f
JOIN gold_layer.dim_rate_indicator ri ON ri.indicator_key = f.indicator_key
JOIN gold_layer.dim_date d ON d.date_key = f.date_key
ORDER BY ri.indicator_name, d.month_start_date;
```

```sql
-- Total retail sales (current prices, actual) next to headline CPI, by month
SELECT d.month_start_date,
       f.sales_rm       AS retail_sales_rm,
       c.cpi_index      AS cpi_total_country
FROM gold_layer.fact_retail_sales f
JOIN gold_Layer.dim_date d          ON d.date_key = f.date_key
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

## Re-running

Bronze and silver loads truncate their tables first, so `load_bronze.sql` followed by `CALL silver_layer.load_silver();` can be repeated. Gold is views, so it refreshes automatically. Only `init_database.sql` wipes everything.

## Reading the output

Procedures in MySQL don't have `PRINT`. `silver_layer.load_silver` returns a summary of row counts as a result tab. If something fails, it shows an error tab and then stops with the error (`RESIGNAL`), so a failure is never mistaken for a finished load. Still compare row counts after each load.

## Common errors

| Error | Likely cause |
|---|---|
| Loading local data is disabled | `local_infile` is off on the server or `OPT_LOCAL_INFILE=1` is missing from the connection |
| The MySQL server is running with the `--secure-file-priv` option | File is outside the `secure_file_priv` folder (affects `LOAD_FILE` and `LOAD DATA INFILE` without `LOCAL`) |
| `LOAD DATA` not allowed in stored procedures | Move it into a plain script |
| File not found in `LOAD DATA` | The path in `load_bronze.sql` still says `C:/PATH/TO/REPO`, or uses backslashes |
| `Incorrect DECIMAL value` from `silver_layer.load_silver` | A bronze value isn't a number. If you opened a CSV in a Windows editor and it changed the line endings to `\r\n`, regenerate the CSVs with `statssa_to_csv.py` |