# SBA 7(a) Loan Risk — Model Evaluation Summary

## 1. Project Objective

Develop a retrospective loan-risk ranking framework using SBA 7(a) loan-level data from fiscal years 2010–2019.

The primary objective is to identify loans associated with a higher likelihood of recorded charge-off within five years of approval, with emphasis on supporting a fixed-capacity credit-risk review process.

## 2. Dataset and Outcome

- Original dataset: 545,751 records
- Modeling population: 478,953 records
- Five-year charge-off events: 18,826
- Overall observed incidence: 3.93%
- Source: SBA 7(a) FOIA loan-level data, snapshot dated June 30, 2026

The target is a recorded charge-off occurring within five years of loan approval.

The population is retrospective and selected based on loan status. It does not represent the complete population of historical loan applications.

### Outcome Definition and Population Reconciliation

The modeling population contains 478,953 SBA 7(a) loan records from FY2010–FY2019.

Eligible loan statuses are Paid in Full (`PIF`), Active/Exempt (`EXEMPT`), and Charged Off (`CHGOFF`). Cancelled (`CANCLD`) and Committed (`COMMIT`) records are excluded.

Ten charged-off loans with missing charge-off dates are excluded because their five-year outcome timing cannot be established.

The binary target `chargeoff_within_5yr` equals 1 when:

- The normalized loan status is `CHGOFF`.
- The recorded charge-off date is on or after the approval date.
- The charge-off date is on or before the fifth calendar anniversary of approval, inclusive.
- The charge-off date is no later than the dataset snapshot date, June 30, 2026.

All remaining eligible records receive a target value of 0.

The five-year boundary uses PostgreSQL calendar-date arithmetic (`INTERVAL '5 years'`), not a fixed 1,825-day approximation.

**Outcome validation results:**

| Definition | Five-year charge-offs |
|---|---:|
| Final inclusive calendar-year definition | 18,826 |
| Exclusive fifth-anniversary definition | 18,813 |
| Fixed 1,825-day definition | 18,810 |

Thirteen charge-offs occurred exactly on the fifth anniversary and are included in the final target.

An external review calculated 478,963 loans and 18,821 events. The ten-loan population difference was reconciled to missing charge-off dates. The five-event difference remains unexplained because the external calculation's exact rules and loan-level event identifiers are unavailable.

The frozen modeling population, target definition, and final holdout results were not modified during this reconciliation.

**Interpretation limitation:** This outcome measures recorded charge-offs within five years, not all defaults, delinquencies, or realized financial losses. The retrospective population is status-selected, and records assigned 0 should not automatically be interpreted as confirmed non-defaults throughout their entire five-year observation period.

## 3. Model Development

Two modeling approaches were evaluated:

- **Logistic Regression:** Interpretable baseline using 13 provisional predictors.
- **Histogram Gradient Boosting:** Nonlinear challenger using the same predictor set.

The chronological development process was:

| Fiscal years | Purpose |
|---|---|
| 2010–2015 | Model training |
| 2016 | Hyperparameter tuning |
| 2017 | Probability calibration |
| 2018 | Independent validation and model selection |
| 2019 | Final holdout evaluation |

Loan-term variables were excluded from the primary models following an investigation of unusually strong associations with charge-off status and possible post-approval information leakage.

The remaining predictors were treated as provisional because approval-time provenance could not be fully verified for every field.

## 4. Model Selection

Logistic Regression was selected after Gradient Boosting failed the predefined FY2018 requirements for meaningful improvement in both Average Precision and Recall@10%.

The selected model uses:

- L2-regularized Logistic Regression
- Regularization parameter C = 1.0
- 13 predictors
- Uncalibrated probability output
- Review capacity fixed at the highest-risk 10% of loans

The calibration choice was informed by FY2018 diagnostic performance. It is documented as a validation-stage decision rather than an independently confirmed calibration improvement.

## 5. Final Holdout Results

The frozen selected model was evaluated on FY2019 without retraining or changing the predictor set.

| Metric | FY2019 result |
|---|---:|
| Loans evaluated | 45,670 |
| Recorded five-year charge-offs | 1,786 |
| Charge-off incidence | 3.91% |
| Average Precision | 0.0774 |
| ROC-AUC | 0.7020 |
| Recall@10% | 22.28% |
| Precision@10% | 8.71% |
| Loans reviewed at 10% capacity | 4,567 |
| Charge-offs captured in top 10% | 398 |
| AP lift over event prevalence | 1.98× |
| Model Brier score | 0.037618 |
| Brier Skill Score | −0.0984% |

The model concentrated approximately 22% of recorded five-year charge-offs within the highest-scored 10% of loans.

## 6. Calibration Findings

The model systematically overpredicted FY2019 charge-off incidence.

- Average predicted risk: 6.11%
- Observed charge-off incidence: 3.91%
- Highest-risk decile average prediction: 15.38%
- Highest-risk decile observed incidence: 8.72%

Every FY2019 decile exhibited overprediction.

The slightly negative Brier Skill Score indicates that the model did not improve overall squared probability error relative to a constant forecast based on training-period event prevalence.

Accordingly, the current model is better supported as a retrospective **risk-ranking tool** than as a calibrated estimator of individual loan charge-off probability.

## 7. Limitations

1. **Retrospective selection:** The modeling population is not the complete loan application population. Results should not be interpreted as prospective underwriting performance.

2. **Feature provenance:** Some retained fields lack fully verified approval-time availability, leaving residual information-leakage risk.

3. **Outcome definition:** The target concerns recorded charge-off within five years, not all defaults, delinquencies, or financial losses.

4. **Historical coverage and outcome maturity:** Loan cohorts and recorded outcomes are subject to the dataset's reporting and timing conventions. Training on labels obtained from the 2026 snapshot does not simulate which five-year outcomes would actually have been known at a historical FY2019 deployment date.

5. **Probability calibration:** Predicted probabilities overestimate observed charge-off incidence on the final holdout.

6. **Temporal generalization:** Performance across historical fiscal-year cohorts does not guarantee stability for future lending conditions.

7. **Uncertainty and dependence:** The primary bootstrap analysis resampled individual loans and did not account for lender-level dependence.

## 8. Business Interpretation

The selected model demonstrates modest but useful historical risk concentration at a fixed 10% review capacity.

However, the results do not establish that additional reviews would prevent charge-offs, reduce losses, or improve underwriting profitability.

The completed **Excel Risk-Review Simulator** supports FY2018/FY2019 cohort selection and 5%, 10%, 15%, 20%, or 25% review capacities. It displays historically observed charge-off capture, precision, recall, comparison with random selection, and risk-decile summaries. It also reports captured historical gross charge-off amounts and provides a financial what-if scenario based on user-entered review cost and assumed prevention rate. These scenario outputs are **illustrative**, not observed savings or evidence that reviews prevent losses.

The dashboard reads from **precomputed capacity and decile summaries**; editing its loan-level input data does not automatically recompute those summaries. Model probabilities remain insufficiently calibrated for direct financial forecasting.

## 9. Final Conclusion

The project demonstrates a structured loan-risk modeling workflow involving SQL preparation, chronological model evaluation, leakage investigation, probabilistic calibration assessment, and independent holdout testing.

Logistic Regression was retained as the primary model because the nonlinear challenger did not achieve the predefined improvement requirements.

The resulting model has useful retrospective ranking performance but material probability-calibration and deployment-readiness limitations. Further validation would be required before using it for live credit decisions.