-- SBA 7(a) retrospective portfolio exploratory analysis.
-- Original file: Untitled.sql (confirmed project-related).
-- Read-only queries; run after 03_analytical_views.sql.
-- Loan-term analyses are exploratory and NOT approved model predictors.
-- These descriptive comparisons are not causal evidence.

-- Validate five-year charge-off population

SELECT
    COUNT(*) AS eligible_loans,

    SUM(chargeoff_within_5yr)
        AS five_year_chargeoffs,

    ROUND(
        100.0 * AVG(chargeoff_within_5yr),
        4
    ) AS five_year_chargeoff_rate_pct,

    SUM(post_snapshot_event_flag)
        AS post_snapshot_records

FROM analytics.vw_sba_5yr_risk_population;



-- Compare five-year charge-off incidence by approval vintage

SELECT
    approval_fy,

    COUNT(*) AS eligible_loans,

    SUM(chargeoff_within_5yr)
        AS five_year_chargeoffs,

    ROUND(
        100.0 * AVG(chargeoff_within_5yr),
        2
    ) AS five_year_chargeoff_rate_pct

FROM analytics.vw_sba_5yr_risk_population

GROUP BY approval_fy

ORDER BY approval_fy;



-- Compare five-year charge-off incidence by business age

SELECT
    business_age_group,

    COUNT(*) AS eligible_loans,

    SUM(chargeoff_within_5yr)
        AS five_year_chargeoffs,

    ROUND(
        100.0 * AVG(chargeoff_within_5yr),
        2
    ) AS five_year_chargeoff_rate_pct

FROM analytics.vw_sba_5yr_risk_population

GROUP BY business_age_group

ORDER BY five_year_chargeoff_rate_pct DESC;



-- Compare five-year charge-off incidence by loan term

SELECT
    term_group,

    COUNT(*) AS eligible_loans,

    SUM(chargeoff_within_5yr)
        AS five_year_chargeoffs,

    ROUND(
        100.0 * AVG(chargeoff_within_5yr),
        2
    ) AS five_year_chargeoff_rate_pct

FROM analytics.vw_sba_5yr_risk_population

GROUP BY term_group

ORDER BY five_year_chargeoff_rate_pct DESC;


-- Examine five-year charge-off incidence
-- by SBA guarantee percentage

WITH guarantee_segments AS (
    SELECT
        loan_row_id,
        chargeoff_within_5yr,

        CASE
            WHEN guarantee_pct < 50
                THEN 'Below 50%'

            WHEN guarantee_pct < 75
                THEN '50%–74.99%'

            WHEN guarantee_pct < 85
                THEN '75%–84.99%'

            WHEN guarantee_pct < 90
                THEN '85%–89.99%'

            WHEN guarantee_pct <= 100
                THEN '90%–100%'

            ELSE 'Unknown / Invalid'
        END AS guarantee_group

    FROM analytics.vw_sba_5yr_risk_population
)

SELECT
    guarantee_group,

    COUNT(*) AS eligible_loans,

    SUM(chargeoff_within_5yr)
        AS five_year_chargeoffs,

    ROUND(
        100.0 * AVG(chargeoff_within_5yr),
        2
    ) AS five_year_chargeoff_rate_pct

FROM guarantee_segments

GROUP BY guarantee_group

ORDER BY five_year_chargeoff_rate_pct DESC;


-- Examine SBA processing-method distribution

SELECT
    processing_method,

    COUNT(*) AS eligible_loans,

    SUM(chargeoff_within_5yr)
        AS five_year_chargeoffs,

    ROUND(
        100.0 * AVG(chargeoff_within_5yr),
        2
    ) AS five_year_chargeoff_rate_pct

FROM analytics.vw_sba_5yr_risk_population

GROUP BY processing_method

ORDER BY eligible_loans DESC;




-- Examine processing methods within the 85%-89.99% guarantee group

SELECT
    processing_method,

    COUNT(*) AS eligible_loans,

    SUM(chargeoff_within_5yr)
        AS five_year_chargeoffs,

    ROUND(
        100.0 * AVG(chargeoff_within_5yr),
        2
    ) AS five_year_chargeoff_rate_pct

FROM analytics.vw_sba_5yr_risk_population

WHERE guarantee_pct >= 85
  AND guarantee_pct < 90

GROUP BY processing_method

ORDER BY eligible_loans DESC;


-- Compare SBA guarantee groups within Preferred Lenders Program

WITH guarantee_segments AS (
    SELECT
        guarantee_pct,
        chargeoff_within_5yr,

        CASE
            WHEN guarantee_pct < 50 THEN 'Below 50%'
            WHEN guarantee_pct < 75 THEN '50%–74.99%'
            WHEN guarantee_pct < 85 THEN '75%–84.99%'
            WHEN guarantee_pct < 90 THEN '85%–89.99%'
            WHEN guarantee_pct <= 100 THEN '90%–100%'
            ELSE 'Unknown / Invalid'
        END AS guarantee_group

    FROM analytics.vw_sba_5yr_risk_population

    WHERE processing_method = 'Preferred Lenders Program'
)

SELECT
    guarantee_group,
    COUNT(*) AS eligible_loans,
    SUM(chargeoff_within_5yr) AS five_year_chargeoffs,

    ROUND(
        100.0 * AVG(chargeoff_within_5yr),
        2
    ) AS five_year_chargeoff_rate_pct

FROM guarantee_segments

GROUP BY guarantee_group

ORDER BY eligible_loans DESC;



-- Compare guarantee groups across approval vintages
-- within the Preferred Lenders Program

WITH preferred_lender_loans AS (
    SELECT
        approval_fy,
        chargeoff_within_5yr,

        CASE
            WHEN guarantee_pct >= 75
             AND guarantee_pct < 85
                THEN '75%–84.99%'

            WHEN guarantee_pct >= 85
             AND guarantee_pct < 90
                THEN '85%–89.99%'
        END AS guarantee_group

    FROM analytics.vw_sba_5yr_risk_population

    WHERE processing_method = 'Preferred Lenders Program'
      AND guarantee_pct >= 75
      AND guarantee_pct < 90
)

SELECT
    approval_fy,
    guarantee_group,

    COUNT(*) AS eligible_loans,

    SUM(chargeoff_within_5yr)
        AS five_year_chargeoffs,

    ROUND(
        100.0 * AVG(chargeoff_within_5yr),
        2
    ) AS five_year_chargeoff_rate_pct

FROM preferred_lender_loans

GROUP BY
    approval_fy,
    guarantee_group

ORDER BY
    approval_fy,
    guarantee_group;


	
-- Compare loan sizes across guarantee groups
-- within the Preferred Lenders Program

SELECT
    CASE
        WHEN guarantee_pct >= 75
         AND guarantee_pct < 85
            THEN '75%–84.99%'

        WHEN guarantee_pct >= 85
         AND guarantee_pct < 90
            THEN '85%–89.99%'
    END AS guarantee_group,

    COUNT(*) AS eligible_loans,

    ROUND(AVG(gross_approval), 2)
        AS average_loan_amount,

    ROUND(
        PERCENTILE_CONT(0.5)
        WITHIN GROUP (ORDER BY gross_approval)::NUMERIC,
        2
    ) AS median_loan_amount,

    ROUND(
        100.0 * AVG(chargeoff_within_5yr),
        2
    ) AS five_year_chargeoff_rate_pct

FROM analytics.vw_sba_5yr_risk_population

WHERE processing_method = 'Preferred Lenders Program'
  AND guarantee_pct >= 75
  AND guarantee_pct < 90

GROUP BY guarantee_group

ORDER BY guarantee_group;



-- Compare loan-term composition within
-- Preferred Lenders Program guarantee groups

WITH preferred_lender_loans AS (
    SELECT
        term_group,
        chargeoff_within_5yr,

        CASE
            WHEN guarantee_pct >= 75
             AND guarantee_pct < 85
                THEN '75%–84.99%'

            WHEN guarantee_pct >= 85
             AND guarantee_pct < 90
                THEN '85%–89.99%'
        END AS guarantee_group

    FROM analytics.vw_sba_5yr_risk_population

    WHERE processing_method = 'Preferred Lenders Program'
      AND guarantee_pct >= 75
      AND guarantee_pct < 90
)

SELECT
    guarantee_group,
    term_group,

    COUNT(*) AS eligible_loans,

    SUM(chargeoff_within_5yr)
        AS five_year_chargeoffs,

    ROUND(
        100.0 * AVG(chargeoff_within_5yr),
        2
    ) AS five_year_chargeoff_rate_pct

FROM preferred_lender_loans

GROUP BY
    guarantee_group,
    term_group

ORDER BY
    guarantee_group,
    eligible_loans DESC;



-- Compare five-year charge-off incidence by loan size
-- within Preferred Lenders Program, 5–10-year terms

WITH loan_size_segments AS (
    SELECT
        chargeoff_within_5yr,

        CASE
            WHEN guarantee_pct >= 75
             AND guarantee_pct < 85
                THEN '75%–84.99%'

            WHEN guarantee_pct >= 85
             AND guarantee_pct < 90
                THEN '85%–89.99%'
        END AS guarantee_group,

        CASE
            WHEN gross_approval <= 50000
                THEN 'Up to $50K'

            WHEN gross_approval <= 150000
                THEN '$50K–$150K'

            WHEN gross_approval <= 350000
                THEN '$150K–$350K'

            WHEN gross_approval <= 500000
                THEN '$350K–$500K'

            ELSE 'Over $500K'
        END AS loan_size_group

    FROM analytics.vw_sba_5yr_risk_population

    WHERE processing_method = 'Preferred Lenders Program'
      AND term_group = '5–10 Years'
      AND guarantee_pct >= 75
      AND guarantee_pct < 90
)

SELECT
    loan_size_group,
    guarantee_group,

    COUNT(*) AS eligible_loans,

    SUM(chargeoff_within_5yr)
        AS five_year_chargeoffs,

    ROUND(
        100.0 * AVG(chargeoff_within_5yr),
        2
    ) AS five_year_chargeoff_rate_pct

FROM loan_size_segments

GROUP BY
    loan_size_group,
    guarantee_group

ORDER BY
    loan_size_group,
    guarantee_group;


-- Examine historical SBA loan approvals by status

SELECT
    loan_status,

    COUNT(*) AS total_loans,

    ROUND(
        SUM(gross_approval) / 1000000000,
        2
    ) AS gross_approval_billions,

    ROUND(
        SUM(sba_guaranteed_approval) / 1000000000,
        2
    ) AS sba_guaranteed_billions,

    ROUND(
        SUM(unguaranteed_approval) / 1000000000,
        2
    ) AS unguaranteed_billions

FROM analytics.vw_sba_loans_clean

GROUP BY loan_status

ORDER BY gross_approval_billions DESC;



-- Summarize historical approvals for funded-status loans

SELECT
    COUNT(*) AS funded_status_loans,

    ROUND(SUM(gross_approval), 2)
        AS total_gross_approval,

    ROUND(SUM(sba_guaranteed_approval), 2)
        AS total_sba_guaranteed,

    ROUND(SUM(unguaranteed_approval), 2)
        AS total_unguaranteed_approval,

    ROUND(
        100.0 * SUM(sba_guaranteed_approval)
        / NULLIF(SUM(gross_approval), 0),
        2
    ) AS dollar_weighted_guarantee_pct

FROM analytics.vw_sba_loans_clean

WHERE loan_status IN ('PIF', 'EXEMPT', 'CHGOFF');



-- Examine broad industry concentration by NAICS prefix

SELECT
    LEFT(TRIM("NaicsCode"), 2) AS naics_2_digit,

    COUNT(*) AS total_loans,

    ROUND(
        SUM("GrossApproval"::NUMERIC) / 1000000000,
        2
    ) AS gross_approval_billions

FROM raw.sba_loans

WHERE TRIM("LoanStatus") IN ('P I F', 'EXEMPT', 'CHGOFF')

GROUP BY LEFT(TRIM("NaicsCode"), 2)

ORDER BY gross_approval_billions DESC;


-- Examine standardized NAICS sector concentration

WITH industry_classification AS (
    SELECT
        "GrossApproval"::NUMERIC AS gross_approval,

        CASE
            WHEN LEFT(TRIM("NaicsCode"), 2) = '11'
                THEN 'Agriculture, Forestry, Fishing and Hunting'
            WHEN LEFT(TRIM("NaicsCode"), 2) = '21'
                THEN 'Mining, Quarrying, Oil and Gas'
            WHEN LEFT(TRIM("NaicsCode"), 2) = '22'
                THEN 'Utilities'
            WHEN LEFT(TRIM("NaicsCode"), 2) = '23'
                THEN 'Construction'
            WHEN LEFT(TRIM("NaicsCode"), 2) IN ('31', '32', '33')
                THEN 'Manufacturing'
            WHEN LEFT(TRIM("NaicsCode"), 2) = '42'
                THEN 'Wholesale Trade'
            WHEN LEFT(TRIM("NaicsCode"), 2) IN ('44', '45')
                THEN 'Retail Trade'
            WHEN LEFT(TRIM("NaicsCode"), 2) IN ('48', '49')
                THEN 'Transportation and Warehousing'
            WHEN LEFT(TRIM("NaicsCode"), 2) = '51'
                THEN 'Information'
            WHEN LEFT(TRIM("NaicsCode"), 2) = '52'
                THEN 'Finance and Insurance'
            WHEN LEFT(TRIM("NaicsCode"), 2) = '53'
                THEN 'Real Estate and Rental and Leasing'
            WHEN LEFT(TRIM("NaicsCode"), 2) = '54'
                THEN 'Professional, Scientific and Technical Services'
            WHEN LEFT(TRIM("NaicsCode"), 2) = '55'
                THEN 'Management of Companies and Enterprises'
            WHEN LEFT(TRIM("NaicsCode"), 2) = '56'
                THEN 'Administrative and Support Services'
            WHEN LEFT(TRIM("NaicsCode"), 2) = '61'
                THEN 'Educational Services'
            WHEN LEFT(TRIM("NaicsCode"), 2) = '62'
                THEN 'Health Care and Social Assistance'
            WHEN LEFT(TRIM("NaicsCode"), 2) = '71'
                THEN 'Arts, Entertainment and Recreation'
            WHEN LEFT(TRIM("NaicsCode"), 2) = '72'
                THEN 'Accommodation and Food Services'
            WHEN LEFT(TRIM("NaicsCode"), 2) = '81'
                THEN 'Other Services'
            WHEN LEFT(TRIM("NaicsCode"), 2) = '92'
                THEN 'Public Administration'
            ELSE 'Unknown / Unmapped'
        END AS naics_sector

    FROM raw.sba_loans

    WHERE TRIM("LoanStatus") IN ('P I F', 'EXEMPT', 'CHGOFF')
)

SELECT
    naics_sector,

    COUNT(*) AS total_loans,

    ROUND(
        SUM(gross_approval) / 1000000000,
        2
    ) AS gross_approval_billions

FROM industry_classification

GROUP BY naics_sector

ORDER BY gross_approval_billions DESC;



-- Validate standardized industry-sector classifications

SELECT
    naics_sector,
    COUNT(*) AS total_loans,
    ROUND(
        SUM(gross_approval) / 1000000000,
        2
    ) AS gross_approval_billions

FROM analytics.vw_sba_loans_clean

WHERE loan_status IN ('PIF', 'EXEMPT', 'CHGOFF')

GROUP BY naics_sector

ORDER BY gross_approval_billions DESC;


