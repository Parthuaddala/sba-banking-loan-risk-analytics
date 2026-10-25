# SQL execution notes

Execute in order: `00_create_schemas.sql`, `01_raw_database_setup.sql`, import the original 42-column CSV using the prevalidated `psql \copy` column list (exclude generated `loan_row_id`), `02_raw_data_validation.sql`, `03_analytical_views.sql`, then optionally `04_exploratory_analysis.sql`.

Important: `01_raw_database_setup.sql` only defines the raw table; it does not import data. `CREATE OR REPLACE VIEW` may need explicit migration if used to replace a view with a different column layout. On a fresh DB, create them in the specified order.

Expected validation: raw 545751; five-year eligible 478953, positive 18826; model export 478953 records and 25 columns. Numeric and date casts presume source fields have parseable values, matching the verified source snapshot.

The exploratory script is the original `Untitled.sql`, renamed. Its descriptive loan-term analyses do not justify using term fields as approval-time predictors.

All provided scripts were inspected and organized, but were not re-executed against PostgreSQL in this review.
