
-- =====================================================
-- Project 2: SBA Banking Loan Risk & Portfolio Analytics
-- File: 03_analytical_views.sql
-- Purpose: Create four dependent analytical views in execution order
-- Source: raw.sba_loans
-- Run after raw import and initial validation.
-- CAUTION: changing output columns of an existing view may require migration.
-- The loan-term candidate columns are retained for auditing but excluded from the frozen 13-feature model.
-- =====================================================

-- =====================================================
-- Create the first standardized SBA loan view
-- =====================================================

-- Standardize SBA loan fields
-- Creates the clean view before the dependent outcome/modeling views

CREATE OR REPLACE VIEW analytics.vw_sba_loans_clean AS

SELECT
    loan_row_id,

    CASE
        WHEN TRIM("LoanStatus") = 'P I F' THEN 'PIF'
        ELSE TRIM("LoanStatus")
    END AS loan_status,

    "ApprovalDate"::DATE AS approval_date,
    "ApprovalFY"::INTEGER AS approval_fy,

    "GrossApproval"::NUMERIC AS gross_approval,
    "SBAGuaranteedApproval"::NUMERIC AS sba_guaranteed_approval,
    "GrossChargeOffAmount"::NUMERIC AS gross_chargeoff_amount,

    -- Additional loan characteristics
    "ProcessingMethod" AS processing_method,
    "TermInMonths"::NUMERIC AS term_months,
    "InitialInterestRate"::NUMERIC AS initial_interest_rate,
    
"BusinessAge" AS business_age,
"CollateralInd" AS collateral_indicator,
"RevolverStatus" AS revolver_status,

-- Standardize business-age categories
CASE
    WHEN TRIM("BusinessAge") = 'Startup, Loan Funds will Open Business'
        THEN 'Startup'

    WHEN TRIM("BusinessAge") = 'New, Less than 1 Year old'
        THEN 'Under 1 Year'

    WHEN TRIM("BusinessAge") = 'New Business or 2 years or less'
        THEN 'Up to 2 Years'

    WHEN TRIM("BusinessAge") = 'Less than 3 years old but at least 2'
        THEN '2–3 Years'

    WHEN TRIM("BusinessAge") = 'Less than 4 years old but at least 3'
        THEN '3–4 Years'

    WHEN TRIM("BusinessAge") = 'Less than 5 years old but at least 4'
        THEN '4–5 Years'

    WHEN TRIM("BusinessAge") = 'Existing, 5 or more years'
        THEN '5+ Years'

    WHEN TRIM("BusinessAge") = 'Existing or more than 2 years old'
        THEN 'Over 2 Years (Unspecified)'

    WHEN TRIM("BusinessAge") = 'Change of Ownership'
        THEN 'Ownership Change'

    WHEN NULLIF(TRIM("BusinessAge"), '') IS NULL
      OR TRIM("BusinessAge") = 'Unanswered'
        THEN 'Unknown'


    ELSE 'Unmapped'
END AS business_age_group,

-- Categorize contractual loan terms
CASE
    WHEN "TermInMonths"::NUMERIC <= 0
        THEN 'Invalid / Zero Term'

    WHEN "TermInMonths"::NUMERIC <= 60
        THEN 'Up to 5 Years'

    WHEN "TermInMonths"::NUMERIC <= 120
        THEN '5–10 Years'

    WHEN "TermInMonths"::NUMERIC <= 180
        THEN '10–15 Years'

    WHEN "TermInMonths"::NUMERIC <= 240
        THEN '15–20 Years'

    WHEN "TermInMonths"::NUMERIC <= 300
        THEN '20–25 Years'

    WHEN "TermInMonths"::NUMERIC <= 360
        THEN '25–30 Years'

    WHEN "TermInMonths"::NUMERIC > 360
        THEN 'Over 30 Years'

    
    ELSE 'Missing'
END AS term_group,

-- Calculate SBA guarantee percentage
ROUND(
    100.0 * "SBAGuaranteedApproval"::NUMERIC
    / NULLIF("GrossApproval"::NUMERIC, 0),
    2
) AS guarantee_pct,

-- Calculate unguaranteed approved amount
(
    "GrossApproval"::NUMERIC
    - "SBAGuaranteedApproval"::NUMERIC

) AS unguaranteed_approval,

-- Preserve the original NAICS classification
NULLIF(TRIM("NaicsCode"), '') AS naics_code,

-- Standardize broad NAICS industry sectors
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

END AS naics_sector,

-- Project location for geographic portfolio analysis

NULLIF(TRIM("ProjectState"), '') AS project_state,

-- Preserve the reported lender name
NULLIF(TRIM("BankName"), '') AS lender_name,

-- Create a consistent analytical lender grouping key
CASE
    WHEN NULLIF(TRIM("BankFDICNumber"), '') IS NOT NULL
        THEN 'FDIC:' || TRIM("BankFDICNumber")

    WHEN NULLIF(TRIM("BankNCUANumber"), '') IS NOT NULL
        THEN 'NCUA:' || TRIM("BankNCUANumber")

    WHEN NULLIF(TRIM("BankName"), '') IS NOT NULL
        THEN 'NAME:' || UPPER(TRIM("BankName"))

    ELSE 'UNKNOWN:' || loan_row_id::TEXT
END AS lender_key,

-- Flag records containing both institutional identifiers
CASE
    WHEN NULLIF(TRIM("BankFDICNumber"), '') IS NOT NULL
     AND NULLIF(TRIM("BankNCUANumber"), '') IS NOT NULL
        THEN 1
    ELSE 0

END AS lender_identifier_overlap_flag,

-- Preserve the source-provided SBA lender identifier
NULLIF(TRIM("LocationID"), '') AS sba_lender_id


FROM raw.sba_loans;








-- =====================================================
-- Five-year SBA charge-off analytical population
-- Purpose: Identify loans with an observed charge-off
-- within five calendar years of approval
-- =====================================================

CREATE OR REPLACE VIEW analytics.vw_sba_5yr_risk_population AS


SELECT
    a.loan_row_id,
    a.loan_status,
    a.approval_date,
    a.approval_fy,
    a.gross_approval,
    a.sba_guaranteed_approval,
    a.gross_chargeoff_amount,
    a.processing_method,
    a.term_months,
    a.initial_interest_rate,
    a.business_age,
    a.collateral_indicator,
    a.revolver_status,
    a.business_age_group,
    a.term_group,
    a.guarantee_pct,
    a.unguaranteed_approval,


    r."ChargeOffDate"::DATE AS chargeoff_date,

    r."AsOfDate"::DATE AS snapshot_date,

    (
        a.approval_date + INTERVAL '5 years'
    )::DATE AS five_year_anniversary,

    CASE
        WHEN a.loan_status = 'CHGOFF'
             AND r."ChargeOffDate"::DATE
                 BETWEEN a.approval_date
                 AND a.approval_date + INTERVAL '5 years'
             AND r."ChargeOffDate"::DATE
                 <= r."AsOfDate"::DATE
            THEN 1

        ELSE 0
    END AS chargeoff_within_5yr,

    CASE
        WHEN a.loan_status = 'CHGOFF'
             AND r."ChargeOffDate"::DATE
                 > r."AsOfDate"::DATE
            THEN 1

        ELSE 0
   
    END AS post_snapshot_event_flag,

    -- Industry classification
  		a.naics_code,
  		a.naics_sector,

-- Geographic classification

a.project_state,

-- Lender identification
a.lender_name,
a.lender_key,
a.lender_identifier_overlap_flag,

-- Source-provided lender identifier
a.sba_lender_id




FROM analytics.vw_sba_loans_clean AS a

JOIN raw.sba_loans AS r
    ON a.loan_row_id = r.loan_row_id

WHERE
    a.loan_status IN ('PIF', 'EXEMPT', 'CHGOFF')

    AND NOT (
        a.loan_status = 'CHGOFF'
        AND NULLIF(TRIM(r."ChargeOffDate"), '') IS NULL
    );




-- =====================================================
-- Model candidate dataset for five-year charge-off risk
-- Separates candidate predictors from evaluation fields
-- =====================================================

CREATE OR REPLACE VIEW analytics.vw_sba_model_candidates AS

SELECT
    -- Record identification and chronological splitting
    m.loan_row_id,
    m.approval_date,
    approval_fy,

    -- Candidate numerical predictors
    m.gross_approval,
    guarantee_pct,

    -- Treat invalid loan terms as missing
    CASE
        WHEN term_months > 0
         AND term_months <= 360
            THEN term_months
        ELSE NULL
    END AS term_months_model,

    -- Preserve a loan-term data-quality flag
    CASE
        WHEN term_months IS NULL
          OR term_months <= 0
          OR term_months > 360
            THEN 1
        ELSE 0
    END AS invalid_term_flag,

    -- Treat nonpositive interest rates as missing
    CASE
        WHEN initial_interest_rate > 0
            THEN initial_interest_rate
        ELSE NULL
    END AS initial_interest_rate_model,

    -- Preserve an interest-rate data-quality flag
    CASE
        WHEN initial_interest_rate IS NULL
          OR initial_interest_rate <= 0
            THEN 1
        ELSE 0
    END AS invalid_interest_rate_flag,

    -- Candidate categorical predictors
    business_age_group,
    naics_sector,
    project_state,
    processing_method,
    collateral_indicator,
    revolver_status,

    -- Five-year prediction target
    m.chargeoff_within_5yr,

    -- Evaluation and audit fields, not predictors
    lender_key,
    lender_name,
    gross_chargeoff_amount,
    post_snapshot_event_flag,

-- Lender identifier for clustering and evaluation only

sba_lender_id,

-- Additional application-related candidate predictors
NULLIF(TRIM(r."FixedorVariableInterestInd"), '')
    AS interest_rate_type,

COALESCE(
    NULLIF(TRIM(r."BusinessType"), ''),
    'Unknown'
) AS business_type,

r."JobsSupported"::NUMERIC AS jobs_supported



FROM analytics.vw_sba_5yr_risk_population AS m

LEFT JOIN raw.sba_loans AS r
    ON m.loan_row_id = r.loan_row_id;



-- Model export with fixed chronological evaluation periods
-- Evaluation and audit fields must not enter the feature matrix

CREATE OR REPLACE VIEW analytics.vw_sba_model_export AS

SELECT
    -- Record identification and chronological controls
    loan_row_id,
    approval_date,
    approval_fy,

    CASE
        WHEN approval_fy BETWEEN 2010 AND 2015
            THEN 'Train'

        WHEN approval_fy = 2016
            THEN 'Tune'

        WHEN approval_fy = 2017
            THEN 'Calibrate'

        WHEN approval_fy = 2018
            THEN 'Validate'

        WHEN approval_fy = 2019
            THEN 'Test'

        ELSE 'Outside Study Period'
    END AS modeling_period,

    -- Candidate numerical features
    gross_approval,
    guarantee_pct,
    term_months_model,
    invalid_term_flag,
    initial_interest_rate_model,
    invalid_interest_rate_flag,
    jobs_supported,

    -- Candidate categorical features
    business_age_group,
    naics_sector,
    project_state,
    processing_method,
    collateral_indicator,
    revolver_status,
    interest_rate_type,
    business_type,

    -- Five-year charge-off target
    chargeoff_within_5yr,

    -- Evaluation and audit fields only
    sba_lender_id,
    lender_key,
    lender_name,
    gross_chargeoff_amount,
    post_snapshot_event_flag

FROM analytics.vw_sba_model_candidates;



