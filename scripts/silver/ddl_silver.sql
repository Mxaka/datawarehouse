/*
Script Purpose:
    Silver holds cleansed, typed data. Series descriptions and observations are
    split per publication, so each table has meaningful column names.
    dwh_create_date is a technical column recording when the row was loaded.
*/

-- Retail trade sales (P6242.1) ------------------------------------------------
DROP TABLE IF EXISTS silver_layer.statssa_retail_series;
CREATE TABLE silver_layer.statssa_retail_series (
    series_code     VARCHAR(50)  NOT NULL PRIMARY KEY,
    retailer_type   VARCHAR(255) NOT NULL,   -- 'All retailers' for the totals
    price_basis     VARCHAR(30)  NOT NULL,   -- Current prices / Constant prices
    adjustment      VARCHAR(30)  NOT NULL,   -- Actual / Seasonally adjusted
    unit            VARCHAR(30)  NOT NULL,
    start_date      DATE         NOT NULL,
    dwh_create_date DATETIME DEFAULT CURRENT_TIMESTAMP
);

DROP TABLE IF EXISTS silver_layer.statssa_retail_observations;
CREATE TABLE silver_layer.statssa_retail_observations (
    series_code     VARCHAR(50)   NOT NULL,
    period          DATE          NOT NULL,  -- first day of the month
    sales_value     DECIMAL(18,3) NOT NULL,
    dwh_create_date DATETIME DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (series_code, period)
);

-- Consumer Price Index (P0141) --------------------------------------------------
DROP TABLE IF EXISTS silver_layer.statssa_cpi_series;
CREATE TABLE silver_layer.statssa_cpi_series (
    series_code     VARCHAR(50)  NOT NULL PRIMARY KEY,
    product         VARCHAR(255) NOT NULL,   -- e.g. 'All Items'
    analytic_series VARCHAR(255),            -- NULL unless it is an analytic series
    geography       VARCHAR(100) NOT NULL,
    index_base      VARCHAR(50)  NOT NULL,   -- e.g. 'Dec 2024 = 100'
    start_date      DATE         NOT NULL,
    dwh_create_date DATETIME DEFAULT CURRENT_TIMESTAMP
);

DROP TABLE IF EXISTS silver_layer.statssa_cpi_observations;
CREATE TABLE silver_layer.statssa_cpi_observations (
    series_code     VARCHAR(50)   NOT NULL,
    period          DATE          NOT NULL,
    cpi_index       DECIMAL(12,3) NOT NULL,
    dwh_create_date DATETIME DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (series_code, period)
);

-- SARB (South African Reserve Bank) -----------------------------------------------
DROP TABLE IF EXISTS silver_layer.sarb_series;
CREATE TABLE silver_layer.sarb_series (
    series_code     VARCHAR(50)  NOT NULL PRIMARY KEY,
    indicator_name  VARCHAR(255) NOT NULL,   -- SARB's series name, e.g. 'SARB Policy Rate'
    description     VARCHAR(500),
    unit            VARCHAR(30)  NOT NULL,   -- 'Percent' for rates, 'ZAR per unit' for exchange rates
    dwh_create_date DATETIME DEFAULT CURRENT_TIMESTAMP
);

DROP TABLE IF EXISTS silver_layer.sarb_observations;
CREATE TABLE silver.sarb_observations (
    series_code     VARCHAR(50)   NOT NULL,
    obs_date        DATE          NOT NULL,
    obs_value       DECIMAL(12,4) NOT NULL,
    dwh_create_date DATETIME DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (series_code, obs_date)
);