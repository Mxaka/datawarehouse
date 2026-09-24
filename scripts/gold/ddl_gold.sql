/*
Script Purpose:
    Gold is the business-ready star schema, built as views over silver.

      gold_layer.dim_date           one row per month
      gold_layer.dim_retailer_type  one row per retailer type (plus 'All retailers')
      gold_layer.dim_sales_basis    price basis x adjustment (Current/Constant x Actual/Seasonally adjusted)
      gold_layer.dim_geography      geographies that have a headline CPI series
      gold_layer.fact_retail_sales  month x retailer type x sales basis   (R million)
      gold_layer.fact_cpi_headline  month x geography, 'All Items' CPI index

    Facts use LEFT JOINs to the dimensions, so a missing dimension row shows up
    as a NULL key in tests/quality_checks_gold.sql instead of silently dropping rows.

      gold_layer.dim_rate_indicator one row per SARB series (repo/policy rate, prime rate,
                              the chosen rand exchange rate)
      gold_layer.fact_monthly_rates month x indicator, rolled up from SARB's daily data:
                              avg_value (mean of the days observed that month) and
                              month_end_value (the last observed day's value)
*/

CREATE OR REPLACE VIEW gold_layer.dim_date AS
WITH RECURSIVE all_months AS (
    SELECT period FROM silver_layer.statssa_retail_observations
    UNION ALL
    SELECT period FROM silver_layer.statssa_cpi_observations
    UNION ALL
    SELECT DATE_FORMAT(obs_date, '%Y-%m-01') FROM silver_layer.sarb_observations
),
months AS (
    SELECT MIN(period) AS month_start FROM all_months
    UNION ALL
    SELECT DATE_ADD(month_start, INTERVAL 1 MONTH)
    FROM months
    WHERE month_start < (SELECT MAX(period) FROM all_months)
)
SELECT
    CAST(DATE_FORMAT(month_start, '%Y%m') AS UNSIGNED) AS date_key,
    month_start                                        AS month_start_date,
    YEAR(month_start)                                  AS year_number,
    QUARTER(month_start)                               AS quarter_number,
    MONTH(month_start)                                 AS month_number,
    MONTHNAME(month_start)                             AS month_name
FROM months;

-- Dimension: Retailer type ------------------------------------------------------
CREATE OR REPLACE VIEW gold_layer.dim_retailer_type AS
SELECT
    ROW_NUMBER() OVER (ORDER BY (retailer_type = 'All retailers') DESC, retailer_type) AS retailer_type_key,
    retailer_type AS retailer_type_name
FROM (SELECT DISTINCT retailer_type FROM silver_layer.statssa_retail_series) t;

-- Dimension: Sales basis ---------------------------------------------------------
CREATE OR REPLACE VIEW gold_layer.dim_sales_basis AS
SELECT
    ROW_NUMBER() OVER (ORDER BY price_basis, adjustment) AS sales_basis_key,
    price_basis,
    adjustment,
    unit
FROM (SELECT DISTINCT price_basis, adjustment, unit FROM silver_layer.statssa_retail_series) t;

-- Dimension: Geography (CPI) ----------------------------------------------------
CREATE OR REPLACE VIEW gold_layer.dim_geography AS
SELECT
    ROW_NUMBER() OVER (ORDER BY (geography = 'Total country') DESC, geography) AS geography_key,
    geography AS geography_name
FROM (SELECT DISTINCT geography FROM silver_layer.statssa_cpi_series WHERE product = 'All Items') t;

-- Fact: Retail sales --------------------------------------------------------------
CREATE OR REPLACE VIEW gold_layer.fact_retail_sales AS
SELECT
    d.date_key,
    rt.retailer_type_key,
    sb.sales_basis_key,
    o.sales_value AS sales_rm
FROM silver_layer.statssa_retail_observations o
JOIN silver_layer.statssa_retail_series s          ON s.series_code = o.series_code
LEFT JOIN gold_layer.dim_date d                    ON d.month_start_date = o.period
LEFT JOIN gold_layer.dim_retailer_type rt          ON rt.retailer_type_name = s.retailer_type
LEFT JOIN gold_layer.dim_sales_basis sb            ON sb.price_basis = s.price_basis
                                            AND sb.adjustment = s.adjustment
                                            AND sb.unit = s.unit;

-- Fact: Headline CPI ----------------------------------------------------------------
CREATE OR REPLACE VIEW gold_layer.fact_cpi_headline AS
SELECT
    d.date_key,
    g.geography_key,
    o.cpi_index
FROM silver_layer.statssa_cpi_observations o
JOIN silver_layer.statssa_cpi_series s             ON s.series_code = o.series_code
                                            AND s.product = 'All Items'
LEFT JOIN gold_layer.dim_date d                    ON d.month_start_date = o.period
LEFT JOIN gold_layer.dim_geography g               ON g.geography_name = s.geography;

-- Dimension: Rate indicator (SARB) ----------------------------------------------
CREATE OR REPLACE VIEW gold_layer.dim_rate_indicator AS
SELECT
    ROW_NUMBER() OVER (ORDER BY series_code) AS indicator_key,
    series_code,
    indicator_name,
    unit
FROM silver_layer.sarb_series;

CREATE OR REPLACE VIEW gold_layer.fact_monthly_rates AS
WITH monthly AS (
    SELECT series_code,
           DATE_FORMAT(obs_date, '%Y-%m-01') AS month_start_date,
           obs_value,
           obs_date,
           AVG(obs_value) OVER (PARTITION BY series_code, DATE_FORMAT(obs_date, '%Y-%m-01'))
               AS avg_value,
           ROW_NUMBER() OVER (PARTITION BY series_code, DATE_FORMAT(obs_date, '%Y-%m-01')
                               ORDER BY obs_date DESC) AS rn
    FROM silver_layer.sarb_observations
)
SELECT
    d.date_key,
    ri.indicator_key,
    ROUND(m.avg_value, 4) AS avg_value,
    m.obs_value            AS month_end_value
FROM monthly m
LEFT JOIN gold_layer.dim_date d           ON d.month_start_date = m.month_start_date
LEFT JOIN gold_layer.dim_rate_indicator ri ON ri.series_code = m.series_code
WHERE m.rn = 1;