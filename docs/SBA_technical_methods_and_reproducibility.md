# SBA 7(a) Loan Risk Analytics — Technical Methods and Reproducibility

This supporting reference preserves the detailed SQL, target-definition, feature-audit, calibration, sensitivity, and reproducibility information behind the [main project README](../README.md). It is not intended as the first page of the portfolio case study.

**Data source:** [U.S. SBA 7(a) & 504 FOIA dataset and data dictionary](https://data.sba.gov/dataset/7a-504-foia) (FY2010–FY2019 extract, snapshot June 30, 2026). The SBA labels this dataset as U.S. Government Works.

**Important:** The term-field audit identified a credible leakage concern, not a confirmed post-approval data mechanism. The five-row outcome reconciliation concerns an inclusive calendar-anniversary definition versus an approximated day-count definition; the stable row IDs refer to this import, not universal IDs across independent imports.

---

## 🗃️ Dataset and population

| Item | Count |
|---|---:|
| Original SBA FOIA data | **545,751 loans**, 42 source columns |
| Eligible modeling population | **478,953** |
| Recorded charge-offs within five calendar years | **18,826** |
| Target = 0 | **460,127** |
| Five-year event incidence | **3.9307%** |
| Unique modeling record IDs | **478,953** |
| Duplicate `loan_row_id` in modeling export | **0** |

**Eligibility:** Normalize source `LoanStatus = 'P I F'` to `PIF`; retain `PIF`, `EXEMPT`, and `CHGOFF`; exclude `CANCLD` and `COMMIT`. Exclude **10 CHGOFF records missing `ChargeOffDate`** because their event timing cannot be determined. `EXEMPT` indicates active/exempt status in the source, not proven five-year survival. The population is not the universe of loan applicants or even an unbiased sample of all approved loans.

### Exact target definition

`chargeoff_within_5yr = 1` when **all** of the following hold:

1. Normalized `loan_status = 'CHGOFF'`;
2. `chargeoff_date >= approval_date`;
3. `chargeoff_date <= approval_date + INTERVAL '5 years'` (**inclusive fifth calendar anniversary**);
4. `chargeoff_date <= snapshot_date` (June 30, 2026).

All other *eligible* rows are assigned `0`. The SQL uses **calendar intervals**, not 1,825 fixed days. Nine records with post-snapshot charge-off dates were flagged for audit; none qualify as an event on their post-snapshot date.

**Outcome reconciliation performed:**

| Window definition | Five-year events |
|---|---:|
| Selected: inclusive fifth calendar anniversary | **18,826** |
| Exclusive anniversary boundary | 18,813 |
| Fixed 1,825 days | 18,810 |

Exactly **13 events** fell on the fifth calendar anniversary. In a separate reconciliation against a fixed 60-month approximation, I traced a five-event difference to loans whose charge-off dates were exactly **1,827 days** after approval and fell on the inclusive fifth calendar anniversary. The corresponding `loan_row_id` values in that audit were `98159`, `99462`, `112401`, `290107`, and `518877`. I retained the calendar-anniversary definition and excluded the ten charged-off loans with unknown event dates. These checks explain the compared row-count and five-event differences for that reconciliation; any independently constructed extract still requires confirmation of its exact filtering rules.

## 🐘 PostgreSQL pipeline and SQL work

I built the SQL pipeline using `raw` and `analytics` schemas, taking the source CSV through validation, outcome construction, feature preparation, and a reproducible modeling export.

### 1. Raw import and quality validation

- I created a PostgreSQL database and `raw.sba_loans`, with **42 source fields** plus the persistent `loan_row_id` used to trace original rows.
- I loaded **545,751** SBA 7(a) rows with `psql`'s `\copy` workflow.
- I validated row counts, fiscal-year coverage, status distributions, relevant dates, duplicate occurrences, missing values, and abnormal terms.
- I found **1,136 exact source-row repeat occurrences** in the raw data. The modeling export retained a unique `loan_row_id` per row; that does **not** imply the underlying source contained no repeated loan information.
- I investigated missing/invalid charge-off and disbursement dates, date inconsistencies and post-snapshot charge-off records rather than silently dropping anomalies.

### Importing the raw CSV

I import the source CSV with PostgreSQL's `psql` client, after running `sql/00_create_schemas.sql` and `sql/01_raw_database_setup.sql`. In `psql`, use this **single-line** command, replacing the sample file path with the location of your local dataset:

```sql
\copy raw.sba_loans ("AsOfDate", "Program", "LocationID", "BorrName", "BorrStreet", "BorrCity", "BorrState", "BorrZip", "BankName", "BankFDICNumber", "BankNCUANumber", "BankStreet", "BankCity", "BankState", "BankZip", "GrossApproval", "SBAGuaranteedApproval", "ApprovalDate", "ApprovalFY", "FirstDisbursementDate", "ProcessingMethod", "InitialInterestRate", "FixedorVariableInterestInd", "TermInMonths", "NaicsCode", "NaicsDescription", "FranchiseCode", "FranchiseName", "ProjectCounty", "ProjectState", "SBADistrictOffice", "CongressionalDistrict", "BusinessType", "BusinessAge", "LoanStatus", "PaidInFullDate", "ChargeOffDate", "GrossChargeOffAmount", "RevolverStatus", "JobsSupported", "CollateralInd", "SoldSecMrktInd") FROM '/path/to/FOIA_7a_FY2010_FY2019_asof_260630.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
```

`\copy` is a `psql` client command; it does not run in pgAdmin's normal Query Tool. The 42 quoted source fields match the table definition. Do **not** include `loan_row_id`: PostgreSQL generates it. Verify the import with:

```sql
SELECT COUNT(*) FROM raw.sba_loans;
-- Expected: 545751
```

Keep the original borrower-level CSV and any local import script containing an absolute file path out of Git. The raw source file is not included in this repository.

### 2. Clean analytical view — `analytics.vw_sba_loans_clean`

I created the cleaned analytical view to perform these transformations:

- Normalize `P I F` to `PIF`, trim other status text, cast date and numeric source fields.
- Compute `guarantee_pct = ROUND(100 * SBAGuaranteedApproval / NULLIF(GrossApproval, 0), 2)` and `unguaranteed_approval = GrossApproval - SBAGuaranteedApproval`.
- Map detailed `BusinessAge` source labels into common business-age groups; assign `Unknown` or `Unmapped` explicitly where appropriate.
- Group terms into duration categories (including invalid/zero terms) for **exploration only**.
- Derive NAICS sector using the first two digits of `NaicsCode` and sector mapping; standardize project state.
- Construct a lender identifier using FDIC number when available, otherwise NCUA number, otherwise normalized lender name, otherwise a row-specific unknown fallback. Flag records containing both FDIC and NCUA identifiers.

### 3. Five-year outcome view — `analytics.vw_sba_5yr_risk_population`

I built the outcome view to join cleaned records to source records using `loan_row_id`, retain eligible statuses, exclude charged-off records without known charge-off dates, and derive:

- `chargeoff_date` and `snapshot_date`;
- `five_year_anniversary = (approval_date + INTERVAL '5 years')::date`;
- `chargeoff_within_5yr` under the four rules above;
- `post_snapshot_event_flag` for events after the dataset snapshot.

For example, the core **event-condition pattern** is:

```sql
CASE
    WHEN loan_status = 'CHGOFF'
     AND chargeoff_date >= approval_date
     AND chargeoff_date <= (approval_date + INTERVAL '5 years')::date
     AND chargeoff_date <= snapshot_date
    THEN 1 ELSE 0
END AS chargeoff_within_5yr
```

*This is the core target condition; `sql/03_analytical_views.sql` contains the complete executable view definition.*

### 4. Modeling views and data export

- `analytics.vw_sba_model_candidates`: prepares model candidate fields and flags for assessment.
- `analytics.vw_sba_model_export`: supplies the final **25-column** dataset, including target, feature inputs, cohort labels, identifiers, and audit-only fields.
- Exported `data/exports/sba_model_export.csv` containing **478,953 × 25** rows/columns.
- Preserved the model-eligible population independently of post-holdout feature audits.

**SQL scripts (in execution order):**

1. `sql/00_create_schemas.sql` — create `raw` and `analytics` schemas.
2. `sql/01_raw_database_setup.sql` — create the raw SBA table (42 source fields and generated `loan_row_id`).
3. Import the original SBA CSV with the `psql` `\copy` command above.
4. `sql/02_raw_data_validation.sql` — inspect raw counts, statuses, duplicate occurrences, missing values, amounts, and date anomalies.
5. `sql/03_analytical_views.sql` — create the four dependent views in order: clean, five-year population, model candidates, and model export.
6. `sql/04_exploratory_analysis.sql` — optional read-only portfolio, guarantee, and NAICS analyses.
7. `sql/05_portfolio_segment_analysis.sql` — create aggregated segment view and validate the three complete portfolio dimensions.
8. `sql/06_export_portfolio_segments_psql.sql` — `psql`-only export of the three complete CSV reports to `results/`.

I reran the SQL workflow in a separate PostgreSQL database during the reproducibility test and recovered **545,751** raw rows and **478,953** modeling records with **18,826** five-year events.

### 5. Representative SQL concepts demonstrated

`CREATE VIEW`, `CASE WHEN`, `NULLIF`, `TRIM`, numeric/date casts, `INTERVAL`, `LEFT()`/sector bucketing, derived columns, `JOIN`, conditional aggregation via `COUNT(*) FILTER (WHERE ...)`, `GROUP BY`, fiscal-year summaries, duplicate-row investigation, and auditing view definitions through PostgreSQL catalog metadata.

**SQL validation checkpoints:**

```sql
-- Final risk-population counts (read-only)
SELECT
    COUNT(*) AS loans,
    COUNT(*) FILTER (WHERE chargeoff_within_5yr = 1) AS events,
    COUNT(*) FILTER (WHERE chargeoff_within_5yr = 0) AS non_events,
    COUNT(*) FILTER (WHERE post_snapshot_event_flag = 1) AS post_snapshot_flags
FROM analytics.vw_sba_5yr_risk_population;
-- Observed: 478953, 18826, 460127, 9
```

```sql
-- Confirm fiscal-year event counts
SELECT approval_fy,
       COUNT(*) AS loans,
       SUM(chargeoff_within_5yr) AS events
FROM analytics.vw_sba_5yr_risk_population
GROUP BY approval_fy
ORDER BY approval_fy;
```

**Import note:** `\copy` runs in `psql`, not in the standard pgAdmin Query Tool. Change the source CSV path locally and do not commit personal filesystem paths.

## 🧠 Chronological model design

| Cohort | Role | Loans | Events | Incidence |
|---|---|---:|---:|---:|
| FY2010–2015 | Train | 266,226 | 9,894 | 3.7164% |
| FY2016 | Tune | 56,785 | 2,198 | 3.8707% |
| FY2017 | Fit probability calibrators | 56,078 | 2,419 | 4.3136% |
| FY2018 | Validate and freeze selection | 54,194 | 2,529 | 4.6666% |
| FY2019 | Final holdout | 45,670 | 1,786 | 3.9107% |

No later cohort was used to refit the selected Logistic Regression for the primary final evaluation. **Important historical realism limitation:** Training on FY2010–2015 labels to backtest FY2019 does not mimic what labels were fully matured by the start of FY2019.

### Final 13 predictors

**Numeric (4):** `gross_approval`, `guarantee_pct`, `initial_interest_rate_model`, `jobs_supported`.

**Categorical (8):** `business_age_group`, `naics_sector`, `project_state`, `processing_method`, `collateral_indicator`, `revolver_status`, `interest_rate_type`, `business_type`.

**Flag (1):** `invalid_interest_rate_flag`.

The model excludes `term_months_model` and `invalid_term_flag` following leakage diagnostics. The remaining fields are **provisional** pending verification that each field's value reflects the time of approval. Previously unseen business-age labels appeared in later cohorts, creating an additional generalization concern.

### Baseline and challenger

- **Logistic Regression:** median numeric imputation, scaling, one-hot encoding for categorical inputs, L2 regularization, `C=1.0`, `class_weight=None`, intercept enabled. Saved as `models/logistic_regression_13_features.joblib`.
- **Histogram Gradient Boosting:** nonlinear challenger with the same 13 candidate predictors; saved as `models/gradient_boosting_13_features.joblib`. Its categorical training-vocabulary conversion was implemented outside the saved estimator, so reproducing that challenger requires the associated notebook processing as well.
- **Sigmoid calibration:** fitted on FY2017; FY2018 diagnostics did not justify using calibrated Logistic Regression probabilities as the final artifact.

I set the challenger selection rule before testing: it required **at least 10% relative improvement in Average Precision** **and** **at least +5 percentage points Recall@10%**, without materially worse calibration or stability. It did **not** satisfy these conditions on FY2018. I selected the **uncalibrated Logistic Regression**; its calibration choice was informed by FY2018 and should not be treated as a separate untouched comparison.

### Leakage investigation: reported loan term

My initial Gradient Boosting model with reported loan term achieved implausibly strong results. Permutation analysis identified term as overwhelmingly influential. Unusual, nonstandard loan terms had exceptionally elevated event incidence, raising concern that reported terms might incorporate post-approval servicing or modification information. The mechanism was **not proven**. Both term-related predictors were excluded from the primary comparison before final selection.

This was a central modeling lesson: when validation scores appear unusually strong, I investigate feature meaning and timing before trusting the result.

## ⚖️ Model selection and uncertainty

**Independent FY2018 results (uncalibrated predictions):**

| Model | Average Precision | ROC-AUC | Recall@10% | Charge-offs captured | Brier |
|---|---:|---:|---:|---:|---:|
| Logistic Regression | **0.0941** | **0.7076** | 22.62% | 572 | 0.043512 |
| Gradient Boosting | 0.0924 | 0.7030 | **23.13%** | 585 | 0.043528 |

On 500 paired, loan-level bootstrap resamples, the **GB minus LR** difference had intervals:

- Average Precision: mean **−0.00205**, percentile 95% interval **[−0.00761, +0.00348]**.
- Recall@10%: mean **+0.45 pp**, percentile 95% interval **[−1.30, +2.25] pp**.

Both intervals include zero. This bootstrap does not account for loans clustered by lender and is not a lender-clustered confidence interval.

A frozen model-selection record is saved in `models/model_selection_record.json`.

## 📈 Final FY2019 holdout (frozen model)

| Metric | Result |
|---|---:|
| Loans / recorded events | 45,670 / 1,786 |
| Observed event incidence | 3.9107% |
| Average Precision (PR summary) | **0.0774** |
| Average Precision lift vs. prevalence | **1.98×** |
| ROC-AUC | **0.7020** |
| Review capacity | **Top 10% = 4,567 loans** |
| Recorded events in reviewed group | **398** |
| Recall@10% | **22.28%** |
| Precision@10% | **8.71%** |
| Precision lift vs. prevalence | **2.23×** |
| Mean predicted event probability | **6.1107%** |
| Brier score | **0.037618** |
| Brier reference: constant training prevalence | **0.037581** |
| Brier Skill Score | **−0.0984%** |

At a fixed 10% review capacity, the model concentrates ~22% of observed events in its top-ranked loans—approximately **2.23 times** the expected capture under random selection. These are *historical event counts*, **not** estimates of preventable losses or economic returns.

### Calibration limitation

FY2019 observed incidence was **3.9107%**, below the average predicted probability of **6.1107%** (a **+2.200 percentage-point** overprediction gap). All ten FY2019 score deciles overpredicted observed incidence. In the highest-risk decile, the average prediction was **15.381%**, versus observed incidence of **8.715%** (gap **−6.667 pp**, using observed minus predicted). The Brier Skill Score is slightly negative relative to a fixed training-incidence benchmark. **Do not interpret raw model probabilities as trusted individual default probabilities.**

## 📗 Excel risk-review simulator

- **Dashboard:** Select FY2018 or FY2019 and a review capacity of **5%, 10%, 15%, 20%, or 25%**; compare historically observed charge-off capture against a random-review baseline, including the selected capacity marker on the chart.
- **Capacity Analysis:** Precomputed cohort/capacity summaries supply counts reviewed, recorded charge-offs captured, recall, precision, lift, and historically recorded charge-off dollars in the selected group.
- **Risk Deciles:** Compare observed event incidence and mean model score across ten score-ranked groups for each fiscal-year cohort.
- **Loan Data:** Contains **99,864 historical FY2018/FY2019 loan records** with 11 exported fields, sourced from `data/exports/sba_simulator_expanded.csv`.
- **Methodology:** Explains inputs, assumptions, metrics, and limitations.

At **FY2019 / 10%** capacity the workbook reports **4,567 reviewed loans**, **398 captured historical charge-offs**, **22.28% recall**, **8.71% precision**, and **2.23× precision lift**. These tie to the final evaluation.

**How the workbook updates:** Dashboard metrics use `INDEX/MATCH` to read the **precomputed Capacity Analysis table**, rather than recalculating model rankings and metrics from the full Loan Data sheet. Changing the fiscal-year/capacity selectors updates displayed summaries; manually changing Loan Data **does not automatically rebuild** those precomputed values. To refresh source data or scores, regenerate the exports and summary tables with the documented Python workflow. The financial what-if uses user-entered **cost per review** and an **assumed prevention rate**; outputs are scenarios, not observed prevention or established ROI. Historical gross charge-off amounts are descriptive and should not be interpreted as recoverable savings.

## 🔎 Exploratory post-holdout feature and drift audit

After freezing the final model, I investigated feature distributions and changing portfolio composition without retraining or reselecting the model. These are explanatory audits, **not** fresh independent validation.

| Retained feature | Audit finding |
|---|---|
| `gross_approval` | Loans under $25K: 6.313% incidence; loans $2M+: 0.609%. Loan size and portfolio mix likely confound this comparison. |
| `guarantee_pct` | 85% guarantee: 57,213 loans / 7.733% incidence; 75% guarantee: 161,081 / 2.222%. The 85% group is much smaller by median approved amount ($100K vs. $510K), and its elevated observed rate persists across approval fiscal years. |
| `initial_interest_rate_model` | At least 11%: 5,622 loans / 9.374% incidence. High rates are overwhelmingly concentrated in FY2018–2019; interest-rate distribution shifted over time. |
| `jobs_supported` | More supported jobs generally coincide with larger loans and lower incidence; 501+ group contains just six loans, unsuitable for strong inference. |
| `invalid_interest_rate_flag` | Seven missing modeled rates; all seven flagged correctly, no mismatches. |

**Training interest-rate range:** 0.660%–11.520%; FY2019 had 2,228 loans (**4.878%**) above that maximum. FY2019 median interest rate was 7.75%, compared with the FY2010–2015 training median of 6.00%. These are evidence of shifting inputs, **not** proof of leakage or causation.

### Mean predicted risk versus observed incidence by cohort

| Fiscal year | Observed | Predicted | Predicted − observed |
|---|---:|---:|---:|
| FY2016 | 3.871% | 3.648% | −0.222 pp |
| FY2017 | 4.314% | 3.741% | −0.573 pp |
| FY2018 | 4.667% | 5.153% | +0.486 pp |
| FY2019 | 3.911% | 6.111% | **+2.200 pp** |

I trained the final model **without class weighting** (`class_weight=None`). I reproduced the FY2019 Average Precision, ROC-AUC, mean prediction, and Brier score in a fresh Python 3.12.8 / **scikit-learn 1.5.1** environment.

### Interest-rate substitution sensitivity (not a proposed recalibration)

Holding each later cohort's interest-rate input to the **6.00% training median** while leaving the other inputs unchanged gives:

| FY | Original predicted mean | Rate-fixed predicted mean | Original − rate-fixed |
|---|---:|---:|---:|
| 2016 | 3.648% | 3.087% | 0.561 pp |
| 2017 | 3.741% | 2.912% | 0.829 pp |
| 2018 | 5.153% | 3.467% | 1.686 pp |
| 2019 | 6.111% | 3.612% | **2.499 pp** |

This demonstrates the **fitted model's sensitivity** to the rate feature. It does **not** causally decompose the calibration gap, and the manipulated inputs can represent unrealistic combinations of features. The FY2019 evaluation remains unchanged.

## Full-population portfolio segmentation (FY2010–FY2019)

I created `sql/05_portfolio_segment_analysis.sql` to calculate aggregated results for processing method (24 categories), normalized NAICS sector (21), and project state (57). The source is `analytics.vw_sba_model_export`, comprising **478,953 eligible loans** and **18,826 five-year charge-off events**. Unlike the Excel simulator’s FY2018–2019 extract, these three reports span **all ten approval fiscal years**.

For each category the reusable `analytics.vw_sba_portfolio_segments` view calculates loan count, recorded events, event rate (`100 × events / loans`), portfolio loan share, portfolio event share, and event rates for **FY2010–2014** versus **FY2015–2019**. It also ranks categories by loan volume within each dimension and flags categories with **at least 5,000 loans AND 100 recorded events** for *highest/lowest observed-rate* comparisons.

The README selects the five largest categories plus the highest and lowest qualifying observed rates within each dimension. It is not a ranking of the truly riskiest groups: rates are unadjusted, category extremes are sensitive to multiple comparisons, and even 5,000-loan groups have sampling uncertainty. Method, size, guarantee percentage, industry, geography and fiscal year vary together. The model’s coefficients offer related multivariable associations but are not causal effects.

**Independent summary validation:** all three category-level exports sum to **478,953 loans, 18,826 events**, with **210,806 FY2010–2014 loans and 268,147 FY2015–2019 loans**. Event totals in each time period also reconcile, and absent time bands display `N/A` rather than a fabricated zero rate. Industry categories inherit the documented SQL mapping: Retail Trade (NAICS 44–45), Transportation/Warehousing (48–49), and Manufacturing (31–33) are combined sectors.

| Published complete result | Categories | SQL source |
|---|---:|---|
| [Processing methods](../results/portfolio_processing_methods.csv) | 24 | `analytics.vw_sba_portfolio_segments` |
| [NAICS sectors](../results/portfolio_naics_sectors.csv) | 21 | `analytics.vw_sba_portfolio_segments` |
| [Project states](../results/portfolio_project_states.csv) | 57 | `analytics.vw_sba_portfolio_segments` |

To reproduce, run [`sql/05_portfolio_segment_analysis.sql`](../sql/05_portfolio_segment_analysis.sql) against the populated database, confirm its validation query says `PASS`, then run [`sql/06_export_portfolio_segments_psql.sql`](../sql/06_export_portfolio_segments_psql.sql) from the repository root in `psql`. The latter uses client-side `\copy` and writes three CSVs under `results/`. See [SQL notes](../sql/README_SQL.md). These are descriptive historical comparisons, not counterfactual tests or underwriting recommendations.

## Illustrative review-economics assumptions

For FY2019's top-10% queue, there are 4,567 loans and $15,416,819 in historical **gross charge-off amounts**. The simplistic ratio `(cost_per_review × 4,567) / 15,416,819` gives **2.96%** at $100, **14.81%** at $500, and **29.62%** at $1,000 per review. The ratio does not model lender/SBA guarantee loss allocation, recoveries, loan-by-loan intervention effectiveness, or discounting. It cannot be interpreted as an estimated prevention probability or proven savings.

## 📂 Repository structure and reproducibility

The repository separates SQL, notebooks, saved models, results, documentation, and the Excel simulator. Large raw and modeling exports stay local and are **not** included in the GitHub checkout.

```text
.
├── README.md
├── requirements.txt
├── .gitignore
├── LICENSE
├── assets/                             # Actual Excel simulator screenshots
│   ├── sba_dashboard.png
│   ├── capture_curve.png
│   ├── sba_risk_deciles.png
│   └── vintage_chargeoff_rates.png
├── sql/
│   ├── 00_create_schemas.sql
│   ├── 01_raw_database_setup.sql
│   ├── 02_raw_data_validation.sql
│   ├── 03_analytical_views.sql
│   ├── 04_exploratory_analysis.sql
│   ├── 05_portfolio_segment_analysis.sql
│   ├── 06_export_portfolio_segments_psql.sql
│   └── README_SQL.md
├── notebooks/
│   ├── 00_sba_feasibility.ipynb
│   ├── 01_model_data_validation.ipynb
│   ├── 02_logistic_regression_baseline.ipynb
│   ├── 03_gradient_boosting_challenger.ipynb
│   ├── 04_probability_calibration.ipynb
│   ├── 05_independent_validation.ipynb
│   ├── 06_final_holdout_evaluation.ipynb
│   └── 07_feature_integrity_audit.ipynb
├── models/
│   ├── logistic_regression_13_features.joblib
│   ├── gradient_boosting_13_features.joblib
│   └── model_selection_record.json
├── results/
│   ├── fy2019_final_model_metrics.csv
│   ├── fy2019_calibration_deciles.csv
│   ├── annual_calibration_drift.csv
│   ├── interest_rate_sensitivity.csv
│   ├── portfolio_processing_methods.csv
│   ├── portfolio_naics_sectors.csv
│   └── portfolio_project_states.csv
├── excel/
│   └── SBA_Risk_Review_Simulator.xlsx
└── docs/
    ├── model_evaluation_summary.md
    └── SBA_technical_methods_and_reproducibility.md
```

`data/raw/` and `data/exports/` contain local data files omitted from GitHub. The repository includes the primary selected-model artifact, challenger artifact, evaluation outputs, and supporting documentation.

**How to reproduce the analysis:**

1. Use **Python 3.12.8** and install the pinned packages in `requirements.txt`, notably **scikit-learn 1.5.1**, NumPy 1.26.4, pandas 2.2.2, SciPy 1.13.1, joblib 1.4.2, matplotlib 3.9.2, openpyxl 3.1.5, and ipykernel 6.28.0.
2. Obtain the original SBA FY2010–FY2019 7(a) FOIA source **as of June 30, 2026** and its 42-field dictionary. A newer snapshot may give different figures. Place the source CSV locally in `data/raw/` and read the SQL import guidance.
3. Create PostgreSQL schemas and the raw table, import the 42-field CSV using **`psql` `\copy`**, then run the validation and analytical-view SQL scripts in `sql/` in the documented order.
4. Export `analytics.vw_sba_model_export` as **`data/exports/sba_model_export.csv`** (expected 478,953 records and 25 columns). This large file is omitted from GitHub. The notebooks use relative paths and expect the data to be present locally. Example in `psql`:

   ```sql
   \copy (SELECT * FROM analytics.vw_sba_model_export) TO 'data/exports/sba_model_export.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
   ```

   The destination is interpreted relative to the `psql` client's working directory; use a local absolute path if needed, without committing it.
5. Run the notebooks in numerical order **00–07** as appropriate. Notebook 00 is an exploratory feasibility check; notebooks 01–07 cover the modeling and evaluation pipeline. Rerunning notebooks that write artifacts can overwrite saved models/exports or refresh selection-record timestamps; back up published artifacts before full re-execution.
6. For segment analytics, run SQL scripts 05 and 06 and check the three aggregate CSV exports (478,953 loans and 18,826 events within each dimension).
7. Compare final FY2019 metrics against `results/` and the frozen decision record. Notebook 07 also produces FY2018/FY2019 simulator data and supporting summaries; the released Excel workbook is a **precomputed historical review tool**, not an automatically regenerating modeling interface.

**Reproducibility results:** I cloned the published repository into a separate working directory, created an isolated Python 3.12.8 environment with scikit-learn 1.5.1, imported the source CSV into a separate PostgreSQL database, recreated the views, and executed notebooks 01–07. The final Logistic Regression FY2019 holdout metrics reproduced at the reported precision, and the FY2018 selection again favored Logistic Regression. Gradient Boosting also executed successfully, but some challenger metrics differed slightly between runs; I do **not** claim exact numerical reproducibility for that model. The saved model loaded successfully in the fresh environment; this test does not by itself prove that the selected final model artifact was independently refitted byte-for-byte. The workflow requires the omitted raw CSV, manual `psql` ingestion, and local data export—it is not a one-command setup. The sanitized Excel simulator was also checked in Excel for Mac.


## ⚠️ Limitations and responsible use

- **Selection bias:** Eligibility is conditioned on retrospectively observed statuses. Some `0` records are not verified five-year survivors.
- **Timing and leakage:** Loan term was excluded due to leakage risk; approval-time provenance remains incomplete for some retained fields.
- **Maturity / temporal realism:** Outcomes observed by a 2026 snapshot do not necessarily reflect labels available when a model for FY2019 would have been deployed.
- **Outcome meaning:** Recorded charge-off within five calendar years is not the same as default, delinquency, loss severity, or preventable loss.
- **Calibration:** FY2019 probabilities materially overpredict incidence; a risk-ranking demo should not price credit or predict dollar savings from these probabilities.
- **Unseen categories / drift:** Historical cohorts differ in business-age categories and interest-rate distribution.
- **Data anomalies:** Source duplicates, invalid term/rate values and post-snapshot event flags require transparent handling.
- **Uncertainty:** Paired bootstrap samples individual loans, not lender clusters.
- **No causal claim:** Associations and counterfactual feature substitutions are descriptive, not evidence of interventions that reduce losses.

---

*I built this project as a research and analytics portfolio demonstration, not an operational credit-decision tool. The source snapshot, modeling population, validation approach, and limitations are documented so readers can interpret the results appropriately.*

**Created by Parthasarathi Addala**

[GitHub: Parthuaddala](https://github.com/Parthuaddala)