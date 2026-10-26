-- Run from the repository root using psql.
-- These are psql commands, not pgAdmin Query Tool SQL.

\copy (SELECT * FROM analytics.vw_sba_portfolio_segments WHERE dimension = 'Processing Method' ORDER BY volume_rank) TO 'results/portfolio_processing_methods.csv' WITH (FORMAT CSV, HEADER TRUE);

\copy (SELECT * FROM analytics.vw_sba_portfolio_segments WHERE dimension = 'NAICS Sector' ORDER BY volume_rank) TO 'results/portfolio_naics_sectors.csv' WITH (FORMAT CSV, HEADER TRUE);

\copy (SELECT * FROM analytics.vw_sba_portfolio_segments WHERE dimension = 'Project State' ORDER BY volume_rank) TO 'results/portfolio_project_states.csv' WITH (FORMAT CSV, HEADER TRUE);