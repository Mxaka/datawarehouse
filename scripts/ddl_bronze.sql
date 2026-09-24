/*
Script Purpose:
    Bronze keeps source data as delivered. Every column is text (or the plain
    sequence number), so nothing can fail or be silently changed on load.

    Stats SA time series files are flattened by scripts/ingestion/statssa_to_csv.py
    into two CSVs, one for series descriptions and one for the values:

      bronze.statssa_series   one row per series; columns h01..h25 are the file's
                              own header lines (H01 = publication, H03 = series
                              code, H24 = "Start: 2008 01", and so on)
      bronze.statssa_values   one row per value; obs_seq counts 1, 2, 3 ... from
                              the series start date

    SARB time series files (already JSON, flattened by scripts/ingestion/sarb_to_csv.py)
    follow the same pattern:

      bronze.sarb_series        one row per series: code (from the file name),
                                the SARB-given name, and its description
      bronze.sarb_observations  one row per daily observation: code, date, value
===============================================================================
*/

DROP TABLE IF EXISTS bronze_layer.statssa_series;
CREATE TABLE bronze_layer.statssa_series (
    h01 VARCHAR(50),    -- publication code, e.g. P6242_1, P0141
    h02 VARCHAR(100),   -- publication title
    h03 VARCHAR(50),    -- series code
    h04 VARCHAR(255),   -- retail: 'Type of dealer' or 'Total'; CPI: product name
    h05 VARCHAR(255),   -- retail: dealer type name; CPI: analytic series name
    h06 VARCHAR(255),
    h13 VARCHAR(255),   -- CPI: geography
    h15 VARCHAR(100),   -- retail: price basis
    h16 VARCHAR(100),   -- retail: actual or seasonally adjusted
    h17 VARCHAR(100),   -- unit
    h18 VARCHAR(100),   -- CPI: base period
    h23 VARCHAR(100),   -- release
    h24 VARCHAR(100),   -- start, e.g. 'Start: 2008 01'
    h25 VARCHAR(100)    -- frequency
);

DROP TABLE IF EXISTS bronze_layer.statssa_values;
CREATE TABLE bronze_layer.statssa_values (
    publication VARCHAR(50),
    series_code VARCHAR(50),
    obs_seq     INT,
    obs_value   VARCHAR(50)
);

-- SARB (South African Reserve Bank) time series ---------------------------------
DROP TABLE IF EXISTS bronze_layer.sarb_series;
CREATE TABLE bronze_layer.sarb_series (
    series_code     VARCHAR(50),   -- from the file name, e.g. MMRD002A
    timeseries_name VARCHAR(255),  -- SARB's own series name, e.g. 'SARB Policy Rate'
    description     VARCHAR(500)
);

DROP TABLE IF EXISTS bronze_layer.sarb_observations;
CREATE TABLE bronze_layer.sarb_observations (
    series_code VARCHAR(50),
    obs_date    VARCHAR(20),   -- 'YYYY-MM-DD', kept as text in bronze
    obs_value   VARCHAR(50)
);