# Diagrams

Mermaid diagrams, replacing the original repo's PNG/PDF exports
(`data_architecture.png`, `data_flow.png`, `data_model.png`, `data_layers.pdf`,
`ETL.png`). These render directly on GitHub and in most Markdown viewers — no
separate image files to keep in sync with the SQL.

---

## 1. Data architecture

How the two source publishers reach the three MySQL databases (bronze,
silver, gold) that stand in for the medallion layers.

```mermaid
flowchart LR
    subgraph Sources
        SA["Stats SA<br/>ASCII files<br/>(P6242.1 retail, P0141 CPI)"]
        SARB["SARB Web API<br/>JSON per series"]
    end

    subgraph Ingest["ingestion/ (Python)"]
        C1["statssa_to_csv.py"]
        C2["download_sarb.py<br/>+ sarb_to_csv.py"]
    end

    subgraph MySQL["MySQL 8.0"]
        B[("bronze<br/>(raw text)")]
        S[("silver<br/>(typed, cleansed)")]
        G[("gold<br/>(star schema views)")]
    end

    SA --> C1 --> B
    SARB --> C2 --> B
    B -- "load_bronze.sql (LOAD DATA)" --> B
    B -- "silver_layer.load_silver()" --> S
    S -- "CREATE VIEW" --> G
```

**Notes:**
- Bronze keeps everything as text and is truncate-and-load — a re-run never
  duplicates data.
- Silver is a stored procedure (`silver_layer.load_silver()`) with an exit handler
  that `RESIGNAL`s on error, so a failed load is never mistaken for a
  finished one.
- Gold is views, not tables — it always reflects the current silver data
  with no separate load step.

---

## 2. Data flow (ETL detail)

What happens to a value on its way from a downloaded file to a gold fact row.
Two parallel paths — Stats SA and SARB — that only meet in gold, through the
shared `dim_date`.

```mermaid
flowchart TD
    subgraph StatsSA["Stats SA path"]
        A1["ASCII file<br/>(header blocks, no dates on value lines)"]
        A2["statssa_to_csv.py<br/>flattens to 2 CSVs"]
        A3["bronze_layer.statssa_series<br/>bronze_layer.statssa_values"]
        A4["silver_layer.load_silver():<br/>date = series start + obs_seq months<br/>labels standardised"]
        A5["silver_layer.statssa_retail_*<br/>silver_layer.statssa_cpi_*"]
        A1 --> A2 --> A3 --> A4 --> A5
    end

    subgraph SARB["SARB path"]
        B1["JSON file per series<br/>(code = file name)"]
        B2["sarb_to_csv.py<br/>flattens to 2 CSVs"]
        B3["bronze_layer.sarb_series<br/>bronze_layer.sarb_observations"]
        B4["silver_layer.load_silver():<br/>unit inferred from code prefix"]
        B5["silver_layer.sarb_series<br/>silver_layer.sarb_observations"]
        B1 --> B2 --> B3 --> B4 --> B5
    end

    A5 --> G1["gold_layer.fact_retail_sales<br/>gold_layer.fact_cpi_headline"]
    B5 --> G2["gold_layer.fact_monthly_rates<br/>(daily rolled up to month,<br/>via window functions)"]
    DD["gold_layer.dim_date<br/>(built from BOTH paths' date ranges)"]
    A5 -.-> DD
    B5 -.-> DD
    DD --> G1
    DD --> G2
```

---

## 3. Data model (star schema)

The gold layer as an entity-relationship diagram. Two fact tables share
`dim_date`; `fact_retail_sales` and `fact_cpi_headline` are Stats SA-only,
`fact_monthly_rates` is SARB-only.

```mermaid
erDiagram
    dim_date ||--o{ fact_retail_sales : "date_key"
    dim_retailer_type ||--o{ fact_retail_sales : "retailer_type_key"
    dim_sales_basis ||--o{ fact_retail_sales : "sales_basis_key"

    dim_date ||--o{ fact_cpi_headline : "date_key"
    dim_geography ||--o{ fact_cpi_headline : "geography_key"

    dim_date ||--o{ fact_monthly_rates : "date_key"
    dim_rate_indicator ||--o{ fact_monthly_rates : "indicator_key"

    dim_date {
        int date_key PK
        date month_start_date
        int year_number
        int quarter_number
        int month_number
        varchar month_name
    }
    dim_retailer_type {
        int retailer_type_key PK
        varchar retailer_type_name
    }
    dim_sales_basis {
        int sales_basis_key PK
        varchar price_basis
        varchar adjustment
        varchar unit
    }
    dim_geography {
        int geography_key PK
        varchar geography_name
    }
    dim_rate_indicator {
        int indicator_key PK
        varchar series_code
        varchar indicator_name
        varchar unit
    }
    fact_retail_sales {
        int date_key FK
        int retailer_type_key FK
        int sales_basis_key FK
        decimal sales_rm
    }
    fact_cpi_headline {
        int date_key FK
        int geography_key FK
        decimal cpi_index
    }
    fact_monthly_rates {
        int date_key FK
        int indicator_key FK
        decimal avg_value
        decimal month_end_value
    }
```

See `docs/data_catalog.md` for column-level detail on every object above.