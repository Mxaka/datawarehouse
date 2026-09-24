/*
Script Purpose:
    Checks that keys are unique, facts connect to dimensions, and the date
    dimension has no gaps. Every check should return NO ROWS unless it says
    otherwise.
*/

-- Check 1: dimension keys are unique -------------------------------------------------------
-- Expectation: No results
SELECT 'dim_date' AS dimension, date_key AS `key`, COUNT(*) AS n
FROM gold_layer.dim_date GROUP BY date_key HAVING COUNT(*) > 1
UNION ALL
SELECT 'dim_retailer_type', retailer_type_key, COUNT(*)
FROM gold_layer.dim_retailer_type GROUP BY retailer_type_key HAVING COUNT(*) > 1
UNION ALL
SELECT 'dim_sales_basis', sales_basis_key, COUNT(*)
FROM gold_layer.dim_sales_basis GROUP BY sales_basis_key HAVING COUNT(*) > 1
UNION ALL
SELECT 'dim_geography', geography_key, COUNT(*)
FROM gold_layer.dim_geography GROUP BY geography_key HAVING COUNT(*) > 1
UNION ALL
SELECT 'dim_rate_indicator', indicator_key, COUNT(*)
FROM gold_layer.dim_rate_indicator GROUP BY indicator_key HAVING COUNT(*) > 1;

-- Check 2: date dimension has no missing months --------------------------------------------
-- Expectation: No results
SELECT COUNT(*) AS months_present,
       TIMESTAMPDIFF(MONTH, MIN(month_start_date), MAX(month_start_date)) + 1 AS months_expected
FROM gold_layer.dim_date
HAVING COUNT(*) <> TIMESTAMPDIFF(MONTH, MIN(month_start_date), MAX(month_start_date)) + 1;

-- Check 3: facts connect to every dimension (no NULL keys) -----------------------------------
-- Expectation: No results
SELECT 'fact_retail_sales' AS fact, COUNT(*) AS rows_with_missing_key
FROM gold_layer.fact_retail_sales
WHERE date_key IS NULL OR retailer_type_key IS NULL OR sales_basis_key IS NULL
HAVING COUNT(*) > 0
UNION ALL
SELECT 'fact_cpi_headline', COUNT(*)
FROM gold_layer.fact_cpi_headline
WHERE date_key IS NULL OR geography_key IS NULL
HAVING COUNT(*) > 0
UNION ALL
SELECT 'fact_monthly_rates', COUNT(*)
FROM gold_layer.fact_monthly_rates
WHERE date_key IS NULL OR indicator_key IS NULL
HAVING COUNT(*) > 0;

-- Check 4: fact grain is unique (no duplicated key combinations) ------------------------------
-- Expectation: No results
SELECT 'fact_retail_sales' AS fact, date_key, retailer_type_key, sales_basis_key, COUNT(*) AS n
FROM gold_layer.fact_retail_sales
GROUP BY date_key, retailer_type_key, sales_basis_key
HAVING COUNT(*) > 1
UNION ALL
SELECT 'fact_cpi_headline', date_key, geography_key, NULL, COUNT(*)
FROM gold_layer.fact_cpi_headline
GROUP BY date_key, geography_key
HAVING COUNT(*) > 1
UNION ALL
SELECT 'fact_monthly_rates', date_key, indicator_key, NULL, COUNT(*)
FROM gold_layer.fact_monthly_rates
GROUP BY date_key, indicator_key
HAVING COUNT(*) > 1;

-- Check 5: gold facts hold everything silver holds for them ---------------------------------------
-- Expectation: No results
SELECT 'fact_retail_sales' AS fact, s.n AS silver_rows, g.n AS gold_rows
FROM (SELECT COUNT(*) n FROM silver_layer.statssa_retail_observations) s,
     (SELECT COUNT(*) n FROM gold_layer.fact_retail_sales) g
WHERE s.n <> g.n
UNION ALL
SELECT 'fact_cpi_headline', s.n, g.n
FROM (SELECT COUNT(*) n
      FROM silver_layer.statssa_cpi_observations o
      JOIN silver_layer.statssa_cpi_series c ON c.series_code = o.series_code AND c.product = 'All Items') s,
     (SELECT COUNT(*) n FROM gold_layer.fact_cpi_headline) g
WHERE s.n <> g.n
UNION ALL
SELECT 'fact_monthly_rates', s.n, g.n
FROM (SELECT COUNT(DISTINCT series_code, DATE_FORMAT(obs_date, '%Y-%m-01')) n
      FROM silver_layer.sarb_observations) s,
     (SELECT COUNT(*) n FROM gold_layer.fact_monthly_rates) g
WHERE s.n <> g.n;