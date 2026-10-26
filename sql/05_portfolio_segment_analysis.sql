/*
Project: SBA 7(a) Loan Risk & Portfolio Analytics
File: 05_portfolio_segment_analysis.sql

Purpose:
Analyze historical five-year charge-off incidence by:
1. Processing method
2. NAICS sector
3. Project state

Population:
478,953 eligible loans, FY2010–FY2019
18,826 recorded five-year charge-offs

Outputs:
- Full-population loan/event counts and rates
- Shares of portfolio loans and recorded events
- FY2010–2014 versus FY2015–2019 comparisons
- Volume ranking and minimum-size eligibility

All comparisons are descriptive, not causal.
*/

CREATE OR REPLACE VIEW analytics.vw_sba_portfolio_segments AS

WITH segment_data AS (

    -- Processing methods
    SELECT
        'Processing Method'::text AS dimension,
        COALESCE(
            NULLIF(TRIM(processing_method), ''),
            'Unknown'
        ) AS category,
        approval_fy,
        chargeoff_within_5yr AS event

    FROM analytics.vw_sba_model_export

    UNION ALL

    -- NAICS sectors
    SELECT
        'NAICS Sector'::text AS dimension,
        COALESCE(
            NULLIF(TRIM(naics_sector), ''),
            'Unknown'
        ) AS category,
        approval_fy,
        chargeoff_within_5yr AS event

    FROM analytics.vw_sba_model_export

    UNION ALL

    -- Project states
    SELECT
        'Project State'::text AS dimension,
        COALESCE(
            NULLIF(TRIM(project_state), ''),
            'Unknown'
        ) AS category,
        approval_fy,
        chargeoff_within_5yr AS event

    FROM analytics.vw_sba_model_export
),

segment_counts AS (

    SELECT
        dimension,
        category,

        COUNT(*) AS loan_count,
        SUM(event) AS event_count,

        COUNT(*) FILTER (
            WHERE approval_fy BETWEEN 2010 AND 2014
        ) AS early_loans,

        COALESCE(
            SUM(event) FILTER (
                WHERE approval_fy BETWEEN 2010 AND 2014
            ), 0
        ) AS early_events,

        COUNT(*) FILTER (
            WHERE approval_fy BETWEEN 2015 AND 2019
        ) AS late_loans,

        COALESCE(
            SUM(event) FILTER (
                WHERE approval_fy BETWEEN 2015 AND 2019
            ), 0
        ) AS late_events

    FROM segment_data

    GROUP BY dimension, category
),

segment_metrics AS (

    SELECT
        *,

        ROUND(
            100.0 * event_count
            / NULLIF(loan_count, 0), 2
        ) AS observed_rate_pct,

        ROUND(
            100.0 * loan_count
            / SUM(loan_count) OVER (
                PARTITION BY dimension
            ), 2
        ) AS loan_share_pct,

        ROUND(
            100.0 * event_count
            / NULLIF(
                SUM(event_count) OVER (
                    PARTITION BY dimension
                ), 0
            ), 2
        ) AS event_share_pct,

        ROUND(
            100.0 * early_events
            / NULLIF(early_loans, 0), 2
        ) AS early_rate_pct,

        ROUND(
            100.0 * late_events
            / NULLIF(late_loans, 0), 2
        ) AS late_rate_pct

    FROM segment_counts
)

SELECT
    dimension,
    category,
    loan_count,
    event_count,
    observed_rate_pct,
    loan_share_pct,
    event_share_pct,

    early_loans,
    early_events,
    early_rate_pct,

    late_loans,
    late_events,
    late_rate_pct,

    ROW_NUMBER() OVER (
        PARTITION BY dimension
        ORDER BY loan_count DESC, category
    ) AS volume_rank,

    (
        loan_count >= 5000
        AND event_count >= 100
    ) AS qualifies_for_rate_comparison

FROM segment_metrics;


-- ===================================================
-- VALIDATION: Every dimension must reconcile
-- ===================================================

SELECT
    dimension,
    COUNT(*) AS categories,
    SUM(loan_count) AS total_loans,
    SUM(event_count) AS total_events,
    SUM(early_loans) AS early_loans,
    SUM(late_loans) AS late_loans,

    CASE
        WHEN SUM(loan_count) = 478953
         AND SUM(event_count) = 18826
         AND SUM(early_loans) = 210806
         AND SUM(late_loans) = 268147
        THEN 'PASS'
        ELSE 'CHECK'
    END AS validation_status

FROM analytics.vw_sba_portfolio_segments

GROUP BY dimension
ORDER BY dimension;


-- ===================================================
-- REPORT 1: Processing methods (all categories)
-- ===================================================

SELECT *
FROM analytics.vw_sba_portfolio_segments
WHERE dimension = 'Processing Method'
ORDER BY volume_rank;


-- ===================================================
-- REPORT 2: NAICS sectors (all categories)
-- ===================================================

SELECT *
FROM analytics.vw_sba_portfolio_segments
WHERE dimension = 'NAICS Sector'
ORDER BY volume_rank;


-- ===================================================
-- REPORT 3: Project states (all categories)
-- ===================================================

SELECT *
FROM analytics.vw_sba_portfolio_segments
WHERE dimension = 'Project State'
ORDER BY volume_rank;