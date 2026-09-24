/*
Script Purpose:
    Truncates the silver layer tables and reloads them from bronze, cleansing as it goes.

Transformations:
    - Trim text and standardise labels (price basis, adjustment)
    - Totals become retailer_type 'All retailers'
    - Stats SA value lines carry no dates: period = series start date
      ('Start: 2008 01' in the header) + (obs_seq - 1) months
    - Text values are cast to DECIMAL
    - Empty text becomes NULL (CPI analytic series name)
    - SARB unit is inferred from the code prefix (MM = Percent, EXC = ZAR per unit),
      since SARB's own JSON does not include a unit field

Usage:
    CALL silver_layer.load_silver();
*/

DELIMITER $$

DROP PROCEDURE IF EXISTS silver_layer.load_silver$$

CREATE PROCEDURE silver_layer.load_silver()
BEGIN
    DECLARE v_batch_start DATETIME;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_no = MYSQL_ERRNO, @err_msg = MESSAGE_TEXT;
        SELECT '=== ERROR DURING SILVER LOAD ===' AS message,
               @err_no AS error_number, @err_msg AS error_message;
        RESIGNAL;
    END;

    SET v_batch_start = NOW();

    -- Retail: series ----------------------------------------------------------
    TRUNCATE TABLE silver_layer.statssa_retail_series;
    INSERT INTO silver_layer.statssa_retail_series
        (series_code, retailer_type, price_basis, adjustment, unit, start_date)
    SELECT
        TRIM(h03),
        CASE WHEN TRIM(h04) = 'Total' THEN 'All retailers' ELSE TRIM(h05) END,
        CASE TRIM(h15) WHEN 'At current prices'  THEN 'Current prices'
                       WHEN 'At constant prices' THEN 'Constant prices'
                       ELSE 'n/a' END,
        CASE TRIM(h16) WHEN 'Actual values'              THEN 'Actual'
                       WHEN 'Seasonally adjusted values' THEN 'Seasonally adjusted'
                       ELSE 'n/a' END,
        -- The ASCII file has no unit line; the Excel version says 'R million' for every series
        COALESCE(NULLIF(TRIM(h17), ''), 'R million'),
        STR_TO_DATE(CONCAT(TRIM(SUBSTRING_INDEX(h24, ':', -1)), ' 01'), '%Y %m %d')
    FROM bronze_layer.statssa_series
    WHERE TRIM(h01) = 'P6242_1';

    -- Retail: observations ------------------------------------------------------
    TRUNCATE TABLE silver_layer.statssa_retail_observations;
    INSERT INTO silver_layer.statssa_retail_observations (series_code, period, sales_value)
    SELECT v.series_code,
           DATE_ADD(s.start_date, INTERVAL v.obs_seq - 1 MONTH),
           CAST(v.obs_value AS DECIMAL(18,3))
    FROM bronze_layer.statssa_values v
    JOIN silver_layer.statssa_retail_series s ON s.series_code = TRIM(v.series_code)
    WHERE v.publication = 'P6242_1';

    -- CPI: series ---------------------------------------------------------------
    TRUNCATE TABLE silver_layer.statssa_cpi_series;
    INSERT INTO silver_layer.statssa_cpi_series
        (series_code, product, analytic_series, geography, index_base, start_date)
    SELECT
        TRIM(h03),
        TRIM(h04),
        NULLIF(TRIM(h05), ''),
        TRIM(h13),
        TRIM(h18),
        STR_TO_DATE(CONCAT(TRIM(SUBSTRING_INDEX(h24, ':', -1)), ' 01'), '%Y %m %d')
    FROM bronze_layer.statssa_series
    WHERE TRIM(h01) = 'P0141';

    -- CPI: observations --------------------------------------------------------
    TRUNCATE TABLE silver_layer.statssa_cpi_observations;
    INSERT INTO silver_layer.statssa_cpi_observations (series_code, period, cpi_index)
    SELECT v.series_code,
           DATE_ADD(s.start_date, INTERVAL v.obs_seq - 1 MONTH),
           CAST(v.obs_value AS DECIMAL(12,3))
    FROM bronze_layer.statssa_values v
    JOIN silver_layer.statssa_cpi_series s ON s.series_code = TRIM(v.series_code)
    WHERE v.publication = 'P0141';


    TRUNCATE TABLE silver_layer.sarb_series;
    INSERT INTO silver_layer.sarb_series (series_code, indicator_name, description, unit)
    SELECT
        TRIM(series_code),
        TRIM(timeseries_name),
        NULLIF(TRIM(description), ''),
        CASE WHEN LEFT(TRIM(series_code), 3) = 'EXC' THEN 'ZAR per unit' ELSE 'Percent' END
    FROM bronze_layer.sarb_series;

    -- SARB: observations ------------------------------------------------------------
    TRUNCATE TABLE silver_layer.sarb_observations;
    INSERT INTO silver_layer.sarb_observations (series_code, obs_date, obs_value)
    SELECT TRIM(v.series_code),
           STR_TO_DATE(v.obs_date, '%Y-%m-%d'),
           CAST(v.obs_value AS DECIMAL(12,4))
    FROM bronze_layer.sarb_observations v
    JOIN silver_layer.sarb_series s ON s.series_code = TRIM(v.series_code);

    -- Summary ---------------------------------------------------------------------
    SELECT CONCAT('Silver layer load finished in ', TIMESTAMPDIFF(SECOND, v_batch_start, NOW()), ' seconds') AS message;
    SELECT 'silver_layer.statssa_retail_series' AS table_name, COUNT(*) AS row_count FROM silver_layer.statssa_retail_series
    UNION ALL SELECT 'silver_layer.statssa_retail_observations', COUNT(*) FROM silver_layer.statssa_retail_observations
    UNION ALL SELECT 'silver_layer.statssa_cpi_series', COUNT(*) FROM silver_layer.statssa_cpi_series
    UNION ALL SELECT 'silver_layer.statssa_cpi_observations', COUNT(*) FROM silver_layer.statssa_cpi_observations
    UNION ALL SELECT 'silver_layer.sarb_series', COUNT(*) FROM silver_layer.sarb_series
    UNION ALL SELECT 'silver_layer.sarb_observations', COUNT(*) FROM silver_layer.sarb_observations;
END$$

DELIMITER ;