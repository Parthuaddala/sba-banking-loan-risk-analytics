
-- =====================================================
-- Project 2: SBA Banking Loan Risk & Portfolio Analytics
-- Run after 00_create_schemas.sql. Creates the 42-field raw table.
-- Import the original CSV using psql \copy separately (see README); never commit a personal path.
-- =====================================================

CREATE TABLE IF NOT EXISTS raw.sba_loans (

    -- PostgreSQL-generated row identifier
    loan_row_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    -- Original SBA source columns
    "AsOfDate" TEXT,
    "Program" TEXT,
    "LocationID" TEXT,
    "BorrName" TEXT,
    "BorrStreet" TEXT,
    "BorrCity" TEXT,
    "BorrState" TEXT,
    "BorrZip" TEXT,
    "BankName" TEXT,
    "BankFDICNumber" TEXT,
    "BankNCUANumber" TEXT,
    "BankStreet" TEXT,
    "BankCity" TEXT,
    "BankState" TEXT,
    "BankZip" TEXT,
    "GrossApproval" TEXT,
    "SBAGuaranteedApproval" TEXT,
    "ApprovalDate" TEXT,
    "ApprovalFY" TEXT,
    "FirstDisbursementDate" TEXT,
    "ProcessingMethod" TEXT,
    "InitialInterestRate" TEXT,
    "FixedorVariableInterestInd" TEXT,
    "TermInMonths" TEXT,
    "NaicsCode" TEXT,
    "NaicsDescription" TEXT,
    "FranchiseCode" TEXT,
    "FranchiseName" TEXT,
    "ProjectCounty" TEXT,
    "ProjectState" TEXT,
    "SBADistrictOffice" TEXT,
    "CongressionalDistrict" TEXT,
    "BusinessType" TEXT,
    "BusinessAge" TEXT,
    "LoanStatus" TEXT,
    "PaidInFullDate" TEXT,
    "ChargeOffDate" TEXT,
    "GrossChargeOffAmount" TEXT,
    "RevolverStatus" TEXT,
    "JobsSupported" TEXT,
    "CollateralInd" TEXT,
    "SoldSecMrktInd" TEXT
);



-- Verify the raw SBA table
SELECT COUNT(*) AS total_records
FROM raw.sba_loans;

