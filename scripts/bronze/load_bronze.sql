/*
Script Purpose:
    Truncates the bronze_layer tables and loads them from the CSV files.

    This is a plain script, NOT a stored procedure: MySQL does not allow
    LOAD DATA inside stored routines.

Before you run it:
    1. Run scripts/ingest/statssa_to_csv.py so the two CSV files exist.
    2. Edit the two paths below. The file name in LOAD DATA must be a literal
       string, so replace the base path in both statements. Use forward
       slashes, even on Windows, e.g. 'C:/Users/you/dwh/datasets/source_statssa/...'
    3. Enable LOCAL INFILE (server: SET GLOBAL local_infile = 1; Workbench
       connection: Advanced > Others > OPT_LOCAL_INFILE=1).
*/

SELECT '>> Loading bronze_layer.statssa_series' AS message;
TRUNCATE TABLE bronze_layer.statssa_series;
LOAD DATA INFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/statssa_series.csv'
INTO TABLE bronze_layer.statssa_series
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES;

SELECT '>> Loading bronze_layer.statssa_values' AS message;
TRUNCATE TABLE bronze_layer.statssa_values;
LOAD DATA INFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/statssa_values.csv'
INTO TABLE bronze_layer.statssa_values
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES;

-- Row counts to record as your baseline
SELECT 'bronze_layer.statssa_series' AS table_name, COUNT(*) AS row_count FROM bronze_layer.statssa_series
UNION ALL
SELECT 'bronze_layer.statssa_values', COUNT(*) FROM bronze_layer.statssa_values;

SELECT '>> Loading bronze_layer.sarb_series' AS message;
TRUNCATE TABLE bronze_layer.sarb_series;
LOAD DATA INFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/sarb_series.csv'
INTO TABLE bronze_layer.sarb_series
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES;

SELECT '>> Loading bronze_layer.sarb_observations' AS message;
TRUNCATE TABLE bronze_layer.sarb_observations;
LOAD DATA INFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/sarb_observations.csv'
INTO TABLE bronze_layer.sarb_observations
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES;

SELECT 'bronze_layer.sarb_series' AS table_name, COUNT(*) AS row_count FROM bronze_layer.sarb_series
UNION ALL
SELECT 'bronze_layer.sarb_observations', COUNT(*) FROM bronze_layer.sarb_observations;