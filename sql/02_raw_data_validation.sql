-- =====================================================
-- Project 2: SBA Banking Loan Risk & Portfolio Analytics
-- File: 02_raw_data_validation.sql
-- Purpose: Validate original SBA data imported into PostgreSQL
-- =====================================================


-- Verify total imported records
SELECT COUNT(*) AS total_records
FROM raw.sba_loans;


-- Validate loan-status distribution
SELECT
    "LoanStatus",
    COUNT(*) AS total_loans
FROM raw.sba_loans
GROUP BY "LoanStatus"
ORDER BY total_loans DESC;


-- Reconcile financial amounts
-- Verify approved loan amounts, SBA guarantees,
-- and reported gross charge-off amounts

SELECT
    COUNT(*) AS total_loans,

    ROUND(
        SUM("GrossApproval"::NUMERIC), 2
    ) AS total_gross_approval,

    ROUND(
        SUM("SBAGuaranteedApproval"::NUMERIC), 2
    ) AS total_sba_guaranteed,

    ROUND(
        SUM("GrossChargeOffAmount"::NUMERIC), 2
    ) AS total_gross_chargeoff

FROM raw.sba_loans;



-- Validate surrogate row identifiers
-- Check uniqueness, missing IDs, and ID range

SELECT
    COUNT(*) AS total_records,

    COUNT(DISTINCT loan_row_id) AS unique_row_ids,

    COUNT(*) - COUNT(loan_row_id) AS missing_row_ids,

    MIN(loan_row_id) AS minimum_row_id,

    MAX(loan_row_id) AS maximum_row_id

FROM raw.sba_loans;




-- =====================================================
-- Validate missing values
-- Compare PostgreSQL missing values with Python EDA
-- =====================================================

SELECT
    COUNT(*) FILTER (
        WHERE NULLIF(TRIM("FirstDisbursementDate"), '') IS NULL
    ) AS missing_disbursement_date,

    COUNT(*) FILTER (
        WHERE NULLIF(TRIM("PaidInFullDate"), '') IS NULL
    ) AS missing_paid_in_full_date,

    COUNT(*) FILTER (
        WHERE NULLIF(TRIM("ChargeOffDate"), '') IS NULL
    ) AS missing_chargeoff_date,

    COUNT(*) FILTER (
        WHERE NULLIF(TRIM("BusinessAge"), '') IS NULL
    ) AS missing_business_age,

    COUNT(*) FILTER (
        WHERE NULLIF(TRIM("NaicsCode"), '') IS NULL
    ) AS missing_naics_code

FROM raw.sba_loans;



-- =====================================================
-- Validate exact duplicate occurrences
-- Compare all 42 source fields, excluding loan_row_id
-- =====================================================

WITH numbered_records AS (
    SELECT
        "LoanStatus",

        ROW_NUMBER() OVER (
            PARTITION BY (
                to_jsonb(t) - 'loan_row_id'
            )
            ORDER BY loan_row_id
        ) AS duplicate_sequence

    FROM raw.sba_loans AS t
)

SELECT
    "LoanStatus",
    COUNT(*) AS duplicate_occurrences

FROM numbered_records

WHERE duplicate_sequence > 1

GROUP BY "LoanStatus"

ORDER BY duplicate_occurrences DESC;


-- =====================================================
-- Validate loan terms, interest rates,
-- and charge-off data quality
-- =====================================================

SELECT
    COUNT(*) FILTER (
        WHERE "TermInMonths"::NUMERIC <= 0
    ) AS nonpositive_loan_terms,

    COUNT(*) FILTER (
        WHERE "TermInMonths"::NUMERIC > 360
    ) AS unusual_long_terms,

    COUNT(*) FILTER (
        WHERE "InitialInterestRate"::NUMERIC <= 0
    ) AS nonpositive_interest_rates,

    COUNT(*) FILTER (
        WHERE TRIM("LoanStatus") = 'CHGOFF'
          AND NULLIF(TRIM("ChargeOffDate"), '') IS NULL
    ) AS charged_off_missing_date,

    COUNT(*) FILTER (
        WHERE TRIM("LoanStatus") = 'CHGOFF'
          AND NULLIF(TRIM("ChargeOffDate"), '') IS NOT NULL
          AND "ChargeOffDate"::DATE > "AsOfDate"::DATE
    ) AS chargeoffs_after_snapshot,

    COUNT(*) FILTER (
        WHERE TRIM("LoanStatus") = 'CHGOFF'
          AND "GrossChargeOffAmount"::NUMERIC = 0
    ) AS charged_off_zero_amount

FROM raw.sba_loans;



