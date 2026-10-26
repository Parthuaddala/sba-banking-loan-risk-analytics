# SQL execution notes — SBA 7(a) Loan Risk & Portfolio Analytics

I wrote the PostgreSQL scripts to make raw ingestion, quality checks, modeling views, and **full-population portfolio segmentation** reproducible.

## Execution order

| Stage | File / action | Purpose |
|---|---|---|
| 1 | `00_create_schemas.sql` | Create `raw` and `analytics` schemas |
| 2 | `01_raw_database_setup.sql` | Create the 42-field source table with generated `loan_row_id` |
| 3 | Source CSV import using `psql \copy` | Import 545,751 FY2010–FY2019 loans; see [complete 42-column command](../docs/SBA_technical_methods_and_reproducibility.md#importing-the-raw-csv) |
| 4 | `02_raw_data_validation.sql` | Audit raw statuses, dates, duplicates, missing values |
| 5 | `03_analytical_views.sql` | Create four dependent analytical/modeling views |
| 6 | `04_exploratory_analysis.sql` *(optional)* | Explore loan, industry, term and guarantee patterns |
| 7 | `05_portfolio_segment_analysis.sql` | Create `analytics.vw_sba_portfolio_segments` and verify all three dimensions |
| 8 | `06_export_portfolio_segments_psql.sql` | Export the aggregated processing method, industry and state results |

`01_raw_database_setup.sql` creates a table, **not** the data. Run the source CSV import separately. `\copy` is a **`psql` client command**, not PostgreSQL SQL understood by pgAdmin's Query Tool. Do not import a value for generated `loan_row_id` or commit a personal absolute CSV path.

## Expected validation results

| Check | Expected |
|---|---:|
| Raw imported records | 545,751 |
| Eligible modeled population | 478,953 |
| Five-year events | 18,826 |
| Model export | 478,953 rows × 25 columns |
| Processing-method report | 24 categories |
| NAICS-sector report | 21 categories |
| Project-state report | 57 categories |

The validation in script 05 must show **`PASS`** for every dimension, with **478,953 loans, 18,826 events, 210,806 early (FY2010–2014) loans, and 268,147 late (FY2015–2019) loans**. The segment view also calculates each category’s loan share, recorded-event share, and both period-specific event rates. Missing period rates are null, not zero.

## Regenerate the three public CSVs

Run script 05 first in **pgAdmin**, against the original project database (`sba_loan_analytics`). Save script 06 in the repository’s `sql/` folder. On a Mac with PostgreSQL installed at `/Library/PostgreSQL/18`, open **Terminal** and run the following from the repository root:

```bash
cd ~/Downloads/sba-banking-loan-risk-analytics
/Library/PostgreSQL/18/bin/psql -U postgres -d sba_loan_analytics -h localhost -v ON_ERROR_STOP=1 -f sql/06_export_portfolio_segments_psql.sql
```

Expected messages: `COPY 24`, `COPY 21`, `COPY 57`. Files are saved relative to the shell’s working directory:

- [`results/portfolio_processing_methods.csv`](../results/portfolio_processing_methods.csv)
- [`results/portfolio_naics_sectors.csv`](../results/portfolio_naics_sectors.csv)
- [`results/portfolio_project_states.csv`](../results/portfolio_project_states.csv)

The output contains only category-level counts, rates and summary metrics, not borrower-level data. If your local PostgreSQL binary path or database name differs, adjust the Terminal invocation; **do not hard-code personal local paths into the committed SQL files**. The source CSV and larger modeling/loan-level exports remain outside GitHub.

## SQL techniques demonstrated

Common table expressions, `CREATE VIEW`, `UNION ALL`, conditional aggregation using `FILTER`, `CASE WHEN`, `NULLIF`, window calculations with `SUM() OVER (PARTITION BY ...)`, `ROW_NUMBER`, volume rankings, and reconciliation checks.

The descriptive event rates are not adjusted causal effects. Selecting extreme categories after applying a minimum-size rule does not eliminate uncertainty or confounding. The earlier exploratory term comparisons do not justify using reported loan term as an approval-time model input.
