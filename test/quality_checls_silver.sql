/*
Script Purpose:
    Checks consistency, completeness and validity of the silver tables.
    Run after: CALL silver.load_silver();
    Every check should return NO ROWS unless it says otherwise.
*/

-- Check 1: every bronze value reached silver (retail and CPI) ------------------
-- Expectation: No results
SELECT 'retail' AS source, b.n AS bronze_rows, s.n AS silver_rows
FROM (SELECT COUNT(*) n FROM bronze_layer.statssa_values WHERE publication = 'P6242_1') b,
     (SELECT COUNT(*) n FROM silver_layer.statssa_retail_observations) s
WHERE b.n <> s.n
UNION ALL
SELECT 'cpi', b.n, s.n
FROM (SELECT COUNT(*) n FROM bronze_layer.statssa_values WHERE publication = 'P0141') b,
     (SELECT COUNT(*) n FROM silver_layer.statssa_cpi_observations) s
WHERE b.n <> s.n;

-- Check 2: every bronze series reached silver -----------------------------------
-- Expectation: No results
SELECT h01 AS publication, h03 AS series_code
FROM bronze_layer.statssa_series
WHERE (h01 = 'P6242_1' AND TRIM(h03) NOT IN (SELECT series_code FROM silver_layer.statssa_retail_series))
   OR (h01 = 'P0141'   AND TRIM(h03) NOT IN (SELECT series_code FROM silver_layer.statssa_cpi_series));

-- Check 3: bronze values whose series is unknown (would have been dropped) ---------
-- Expectation: No results
SELECT DISTINCT publication, series_code
FROM bronze_layer.statssa_values
WHERE (publication = 'P6242_1' AND TRIM(series_code) NOT IN (SELECT series_code FROM silver_layer.statssa_retail_series))
   OR (publication = 'P0141'   AND TRIM(series_code) NOT IN (SELECT series_code FROM silver_layer.statssa_cpi_series));

-- Check 4: no series without a parsed start date or standard label -----------------
-- Expectation: No results
SELECT series_code, start_date, price_basis, adjustment
FROM silver_layer.statssa_retail_series
WHERE start_date IS NULL OR price_basis = 'n/a' OR adjustment = 'n/a'
UNION ALL
SELECT series_code, start_date, NULL, NULL
FROM silver_layer.statssa_cpi_series
WHERE start_date IS NULL;

-- Check 5: no gaps in any series (months present = months from first to last) ------
-- Expectation: No results
SELECT 'retail' AS source, series_code, COUNT(*) AS months_present,
       TIMESTAMPDIFF(MONTH, MIN(period), MAX(period)) + 1 AS months_expected
FROM silver_layer.statssa_retail_observations
GROUP BY series_code
HAVING COUNT(*) <> TIMESTAMPDIFF(MONTH, MIN(period), MAX(period)) + 1
UNION ALL
SELECT 'cpi', series_code, COUNT(*), TIMESTAMPDIFF(MONTH, MIN(period), MAX(period)) + 1
FROM silver_layer.statssa_cpi_observations
GROUP BY series_code
HAVING COUNT(*) <> TIMESTAMPDIFF(MONTH, MIN(period), MAX(period)) + 1;

-- Check 6: retail series and headline CPI series all end in the latest month ----------------
-- Expectation: No results
SELECT 'retail' AS source, series_code, MAX(period) AS last_period
FROM silver_layer.statssa_retail_observations
GROUP BY series_code
HAVING MAX(period) <> (SELECT MAX(period) FROM silver_layer.statssa_retail_observations)
UNION ALL
SELECT 'cpi', o.series_code, MAX(o.period)
FROM silver_layer.statssa_cpi_observations o
JOIN silver_layer.statssa_cpi_series s ON s.series_code = o.series_code AND s.product = 'All Items'
GROUP BY o.series_code
HAVING MAX(o.period) <> (SELECT MAX(period) FROM silver_layer.statssa_cpi_observations);

-- Check 7: CPI series that end before the latest month (informational) -----------------------
SELECT o.series_code, s.analytic_series, MAX(o.period) AS last_period
FROM silver_layer.statssa_cpi_observations o
JOIN silver_layer.statssa_cpi_series s ON s.series_code = o.series_code
GROUP BY o.series_code, s.analytic_series
HAVING MAX(o.period) < (SELECT MAX(period) FROM silver_layer.statssa_cpi_observations);

-- Check 8: values are positive -----------------------------------------------------------
-- Expectation: No results
SELECT 'retail' AS source, series_code, period, sales_value AS value
FROM silver_layer.statssa_retail_observations WHERE sales_value <= 0
UNION ALL
SELECT 'cpi', series_code, period, cpi_index
FROM silver_layer.statssa_cpi_observations WHERE cpi_index <= 0;

-- Check 9: the seven retailer types add up to the total (actual values) -------------------
-- Stats SA rounds each series to whole R million, so allow a small rounding gap.
-- Expectation: No results
WITH detail AS (
    SELECT o.period, s.price_basis, SUM(o.sales_value) AS sum_types
    FROM silver_layer.statssa_retail_observations o
    JOIN silver_layer.statssa_retail_series s ON s.series_code = o.series_code
    WHERE s.adjustment = 'Actual' AND s.retailer_type <> 'All retailers'
    GROUP BY o.period, s.price_basis
), total AS (
    SELECT o.period, s.price_basis, o.sales_value AS total_value
    FROM silver_layer.statssa_retail_observations o
    JOIN silver_layer.statssa_retail_series s ON s.series_code = o.series_code
    WHERE s.adjustment = 'Actual' AND s.retailer_type = 'All retailers'
)
SELECT d.period, d.price_basis, d.sum_types, t.total_value,
       d.sum_types - t.total_value AS difference
FROM detail d
JOIN total t ON t.period = d.period AND t.price_basis = d.price_basis
WHERE ABS(d.sum_types - t.total_value) > 5;

-- Check 10: standardised labels (informational) ----------------------------------------------
-- Expectation: 4 rows (Current/Constant prices x Actual/Seasonally adjusted)
SELECT DISTINCT price_basis, adjustment, unit
FROM silver_layer.statssa_retail_series
ORDER BY price_basis, adjustment;

-- Check 11: SARB — every bronze value reached silver, per series ------------------------
-- Expectation: No results
SELECT b.series_code, b.n AS bronze_rows, COALESCE(s.n, 0) AS silver_rows
FROM (SELECT series_code, COUNT(*) n FROM bronze_layer.sarb_observations GROUP BY series_code) b
LEFT JOIN (SELECT series_code, COUNT(*) n FROM silver_layer.sarb_observations GROUP BY series_code) s
       ON s.series_code = b.series_code
WHERE b.n <> COALESCE(s.n, 0);

-- Check 12: SARB — no duplicate (series, date) rows ---------------------------------------
-- Expectation: No results (the primary key already enforces this; kept as a direct check)
SELECT series_code, obs_date, COUNT(*) AS n
FROM silver_layer.sarb_observations
GROUP BY series_code, obs_date
HAVING COUNT(*) > 1;

-- Check 13: SARB — interest rates in a plausible range (0 to 30 percent) -------------------
-- Expectation: No results
SELECT s.series_code, s.indicator_name, o.obs_date, o.obs_value
FROM silver_layer.sarb_observations o
JOIN silver_layer.sarb_series s ON s.series_code = o.series_code
WHERE s.unit = 'Percent' AND (o.obs_value < 0 OR o.obs_value > 30);

-- Check 14: SARB — exchange rates are positive ------------------------------------------------
-- Expectation: No results
SELECT s.series_code, s.indicator_name, o.obs_date, o.obs_value
FROM silver_layer.sarb_observations o
JOIN silver_layer.sarb_series s ON s.series_code = o.series_code
WHERE s.unit = 'ZAR per unit' AND o.obs_value <= 0;

-- Check 15: SARB — date range and count per series (informational) -------------------------
-- Expectation: one row per series; compare first/last dates to what you downloaded
SELECT series_code, MIN(obs_date) AS first_date, MAX(obs_date) AS last_date, COUNT(*) AS n
FROM silver_layer.sarb_observations
GROUP BY series_code;