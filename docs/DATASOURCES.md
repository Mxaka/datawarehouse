# Data Sources

Two real South African publishers, both aggregated (no personal data): Stats SA (retail sales and consumer prices) and the SARB (interest rates and the rand). Together they let you ask: *how does retail spending move with prices, interest rates and the rand?*

## 1. Stats SA: Retail trade sales (P6242.1)

| | |
|---|---|
| Download | Stats SA "Time series data" page, `P6242.1 Retail trade sales (New time series) from January 2002_202607.zip`, **ASCII** version (the Excel version is only used for checking) |
| Release | July 2026, monthly |
| Content | 32 series: 7 retailer types plus a total, each in four flavours (current or constant prices, actual or seasonally adjusted). Unit: R million |
| Coverage | Totals from January 2002 (295 months); current-price retailer types from January 2005; constant-price retailer types from January 2008 |
| Folder | `datasets/source_statssa/` |

## 2. Stats SA: Consumer Price Index, COICOP (P0141)

| | |
|---|---|
| Download | `P0141 CPI(COICOP) from Jan 2008 (202607).zip`, **ASCII** version |
| Release | July 2026, monthly, index with December 2024 = 100 |
| Content | 784 series: products by geography (nine provinces, rural areas, total country) plus analytic series such as CPI for pensioners |
| Coverage | Mostly January 2008 to July 2026 (223 months) |
| Used in gold | Headline `All Items` for the 11 geographies. Bronze and silver hold all 784 series |

## What the Stats SA files look like

The ASCII files are not tables. Each series is a **block**: header lines (`H01: P6242_1`, `H03: con_S621C`, `H24: Start: 2008 01` and so on) followed by one value per line, with **no dates on the value lines**. The Excel files are wide (one row per series, one column per month such as `MO012008`).

`ingestion/statssa_to_csv.py` flattens the ASCII blocks into two CSVs that MySQL can load, without interpreting anything. Silver then works out each month from the header start date plus the value's position.

**Verified:** for both publications, every value and month derived this way matches the Excel files exactly (7,928 retail and 168,936 CPI values), with no gaps.

## Things worth knowing (found in the real data)

- The ASCII retail file has no unit line. The Excel version says `R million` for every series, and silver uses that
- The seven retailer types add up to the total within R2 million (rounding) for actual values in every month, and silver checks this
- Two analytic CPI series (`CPS51100` regulated prices, `CPS51200` administered prices that are not regulated) stop in December 2024 while everything else runs to July 2026. They match the Stats SA file exactly, so it is a property of the source. They are not used in gold
- Attribution: Stats SA's copyright notice requires acknowledging Stats SA as the source and stating that the analysis is your own processing of the data

## 3. SARB Web API

| | |
|---|---|
| Base | `https://custom.resbank.co.za/SarbWebApi/` |
| Pattern | `WebIndicators/Shared/GetTimeseriesObservations/{TimeseriesCode}` returns one series as JSON |
| Series to use | Repo rate `MMRD002A`, prime lending rate `MMRD000A`, plus one rand exchange rate |
| Finding codes | `WebIndicators/CurrentMarketRates` lists current rates with their `TimeseriesCode`. For example it shows the rand per euro rate as `EXCZ002D` |
| Format | JSON or XML |
| Attribution | Credit the South African Reserve Bank and check their terms of use |

Automate the download with `ingestion/download_sarb.py` 

```
python ingestion/download_sarb.py            # repo rate, prime rate, Rand per Euro
python ingestion/download_sarb.py --list-fx  # list rand exchange-rate codes
python ingestion/download_sarb.py --codes MMRD002A MMRD000A <FX_CODE>
python ingestion/download_sarb.py --out "<your secure_file_priv folder>"
```

It saves each response exactly as received to `datasets/source_sarb/<CODE>.json`, checks that it is valid JSON with at least one observation, and retries on network errors.

**Getting JSON into MySQL:** `JSON_TABLE(LOAD_FILE('path'), ...)` reads the file in SQL, but the file must sit in the server's `secure_file_priv` folder and your account needs the `FILE` privilege. Converted each JSON file to CSV and use `LOAD DATA INFILE`.

**Confirmed layout (from real SARB responses):** each JSON file is a list of daily
observations: `{"Period": "2026-09-23T00:00:00", "Timeseries": "Prime lending rate",
"Description": "...", "Value": 10.5, "FormatNumber": "0.00", "FormatDate": "yyyy-MM-dd"}`.
The series code isn't inside the file — it comes from the file name (e.g.
`MMRD000A.json`). SARB publishes business days only, not every calendar day.

`ingestion/sarb_to_csv.py` flattens the saved JSON files into two CSVs the
same way `statssa_to_csv.py` does for Stats SA: `sarb_series.csv` (code, name,
description) and `sarb_observations.csv` (code, date, value). Run it after
`download_sarb.py`:


## Folder layout

```
datasets/
├── source_statssa/
│   ├── ASCII Retail trade sales.txt                          (from the P6242.1 ASCII zip)
│   ├── ASCII - CPI (COICOP) from January 2008 (202607).txt   (from the P0141 ASCII zip)
│   ├── statssa_series.csv                                    (created by statssa_to_csv.py)
│   └── statssa_values.csv                                    (created by statssa_to_csv.py)
└── source_sarb/
    └── MMRD002A.json, MMRD000A.json, ...                     (created by download_sarb.py)
```