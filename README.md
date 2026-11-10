# Home Credit Default Risk — Predictive Analytics and Lending Decision Support

**Individual analytics portfolio by Achuthasai Valluru**

Home Credit serves applicants who may have limited traditional credit history. The business challenge is to identify elevated payment-difficulty risk without unnecessarily declining applicants likely to repay. This project develops an interpretable lending-risk decision-support model and documents the business, financial, explainability, and governance questions that must be addressed before operational use.

The final 36-predictor logistic-regression model achieved a mean five-fold ROC AUC of **0.7481**. The analysis shows how application data, historical repayment and credit information, and carefully governed model outputs can support more informed loan-review decisions. It is an academic analysis—not a production lending system.

## My Role and Individual Contributions

This repository documents my individual analytics work in R. I performed:

- exploratory analysis of applicant characteristics, missingness, data quality, and payment-difficulty patterns;
- reusable preprocessing and applicant-level aggregation of historical credit and repayment data;
- feature engineering, logistic-regression development, model comparison, and stratified cross-validation;
- out-of-fold threshold analysis and illustrative financial sensitivity scenarios;
- exact log-odds SHAP explainability for the final logistic model;
- proposed feature-to-reason mappings for adverse-action review; and
- descriptive gender and education fairness analyses.

This repository is my individual portfolio, not a reproduction of a separate group presentation or group-submitted deliverable. It documents the work and results maintained in this repository; it does not claim ownership of work outside that scope.

## Key Results

| Result | Evidence |
|---|---|
| Training population | 307,511 historical Home Credit applications |
| Final model | 36-predictor binomial logistic regression |
| Mean five-fold CV ROC AUC | **0.7481** |
| Pooled out-of-fold ROC AUC | **0.748113** |
| Documented Kaggle public / private ROC AUC | **0.74751 / 0.73212** |
| Illustrative lending-risk threshold | Approve when predicted risk is strictly below **12%** |
| Illustrative approval rate at 12% | Approximately **80.5%** |

The public and private Kaggle AUC values are documented results from the original competition evaluation. Available local submission CSV files do not independently verify that the recorded scores came from the final 36-predictor submission.

The 12% threshold is an illustrative retrospective decision policy selected from a tested grid under stated financial assumptions. It is **not** an operationally validated underwriting cutoff or a recommendation for automated lending.

## Business Value and Recommendations

The model produces a risk ranking that could help credit-risk and underwriting teams prioritize review, compare decision policies, and make the trade-off between lending volume and observed payment difficulties explicit. At lower risk thresholds, more applicants are declined; at higher thresholds, more applicants are approved, including more applicants later recorded with payment difficulties.

The financial analysis evaluates sensitivity scenarios using standardized exposure units and `AMT_CREDIT` as a requested-credit exposure proxy. It does **not** claim realized lender profit, savings, loss severity, or recovery outcomes. The scenarios are intended to make financial assumptions visible and test how threshold conclusions change when those assumptions change.

Before any deployment, the analysis recommends:

1. probability-calibration and external-performance validation;
2. portfolio-specific cost, recovery, and loss-severity validation;
3. continued fairness, proxy-risk, and data-timing assessment; and
4. a supervised pilot with model-risk, legal, compliance, and underwriting governance.

## Challenges Encountered

- **Incomplete information across source tables:** Application and historical-credit files contain substantial missingness. I retained missing-history indicators where appropriate and used training-derived imputation so missingness was visible rather than silently discarded.
- **Applicant-level feature construction:** Historical records are stored at a different grain from applications. I aggregated them to one row per applicant and checked joins for duplicated or lost applicant records.
- **Leakage-safe evaluation:** Preprocessing statistics can unintentionally incorporate validation information. I learned fitted preparation and imputation parameters within each training fold, then used out-of-fold predictions for threshold, financial, and fairness analyses.
- **Opaque and potentially proxy-related inputs:** The definitions of `EXT_SOURCE_*` variables are not available in the project data. I treated their contributions as model inputs requiring provenance review, not as automatically suitable customer-facing denial reasons.
- **Incomplete financial outcomes:** The data do not provide verified lender profit, recovery, or loss-severity outcomes. I used clearly labeled illustrative sensitivity scenarios and retained the limitation that they are not realized-profit estimates.

## Lessons Learned

- I learned that combining well-governed application, repayment, and credit-history features can improve risk ranking, but the added information must be joined and timed carefully.
- I learned that reliable performance and decision analysis require stratified cross-validation and out-of-fold predictions rather than relying on fitted training predictions.
- I learned that ROC AUC measures ranking discrimination; it does not by itself establish calibrated probabilities, financial benefit, or deployment readiness.
- I learned that SHAP explanations, proposed adverse-action mappings, and fairness evaluation reveal governance questions that model performance alone cannot answer.
- I learned that analytics creates stronger business value when technical findings are connected to decision trade-offs, explicit assumptions, validation needs, and actionable recommendations.

## Responsible AI and Model Governance

The project treats performance as only one component of responsible lending analytics.

- **Explainability:** Exact marginal/interventional SHAP values decompose the logistic model on the log-odds scale.
- **Feature transparency:** The model card distinguishes interpretable financial-history variables from missing-data indicators, potentially sensitive variables, and opaque `EXT_SOURCE_*` scores.
- **Adverse-action review:** Feature-to-reason mappings are proposed explanatory aids, not legally approved notices. SHAP values alone do not establish legal adequacy.
- **Fairness evaluation:** Out-of-fold approval and error-rate comparisons are reported for `CODE_GENDER` and `NAME_EDUCATION_TYPE`, with small and unusual groups flagged.

Important limitations remain: `TARGET = 1` indicates recorded payment difficulties rather than confirmed permanent default or loss; `EXT_SOURCE_*` definitions and provenance are opaque; other inputs may act as demographic proxies; and the historical data do not prove every feature was available at the time of a lending decision.

## Explore My Work

| File | What it demonstrates |
|---|---|
| [eda.qmd](eda.qmd) | Exploratory data analysis, data-quality review, missingness, visualizations, and business insights. |
| [modeling.qmd](modeling.qmd) | Feature engineering, logistic regression, model comparisons, cross-validation, and final-model validation. |
| [model_card.qmd](model_card.qmd) | Decision thresholds, financial sensitivity, SHAP, proposed adverse-action mapping, fairness, limitations, and executive summary. |
| [data_preparation.R](data_preparation.R) | Reusable application preparation and historical-data aggregation functions. |
| [model_card_preparation.R](model_card_preparation.R) | Recreates the final model artifact and five-fold out-of-fold predictions without rerunning benchmark experiments. |
| [model_card_threshold_analysis.R](model_card_threshold_analysis.R) | Evaluates threshold operating points using out-of-fold predictions. |
| [model_card_financial_analysis.R](model_card_financial_analysis.R) | Produces illustrative threshold and nine-scenario financial sensitivity outputs. |
| [model_card_shap_analysis.R](model_card_shap_analysis.R) | Calculates exact logistic-model SHAP values and explainability figures. |
| [model_card_adverse_action_analysis.R](model_card_adverse_action_analysis.R) | Creates proposed feature-to-reason mappings and an illustrative declined-applicant explanation. |
| [model_card_fairness_analysis.R](model_card_fairness_analysis.R) | Produces descriptive out-of-fold fairness metrics and visualizations. |

The repository intentionally retains source notebooks rather than compiled reports. GitHub displays the QMD source, but does not execute Quarto notebooks or display locally generated report output. Compiled HTML reports are kept local and Git-ignored under the course submission policy.

## Tools and Skills Demonstrated

- **Programming and workflow:** R, Quarto, Git, GitHub
- **Data work:** `tidyverse`, data cleaning, missing-data handling, joins, aggregation, and feature engineering
- **Modeling:** binomial logistic regression, decision trees (`rpart`), random forests (`ranger`), ROC AUC (`pROC`), and stratified cross-validation (`rsample`)
- **Analytics communication:** `ggplot2` visualizations, business interpretation, model documentation, and reproducibility checks
- **Responsible analytics:** threshold trade-offs, financial sensitivity, SHAP explainability, adverse-action review, and descriptive fairness evaluation

## Reproducibility

The source data are from Kaggle's [Home Credit Default Risk competition](https://www.kaggle.com/competitions/home-credit-default-risk/data). Download the original competition files and place them in a local `Data/` directory at the project root.

The Model Card workflow uses `tidyverse`; `model_card_preparation.R` also uses `rsample`. The modeling notebook additionally loads `pROC`, `rpart`, and `ranger`. Package versions are not fully pinned, and this project is not presented as a one-command reproducible environment.

With the original data and required R packages available, run the Model Card scripts from the project root in this order:

```text
Rscript model_card_preparation.R
Rscript model_card_threshold_analysis.R
Rscript model_card_financial_analysis.R
Rscript model_card_shap_analysis.R
Rscript model_card_adverse_action_analysis.R
Rscript model_card_fairness_analysis.R
```

Then render `model_card.qmd` with Quarto. The generated `artifacts/` directory, compiled HTML reports, Kaggle submission CSVs, and raw `Data/` files are intentionally Git-ignored. A fresh clone therefore cannot render the Model Card until the original data are available and the required artifacts have been regenerated.

## Limitations

This model is not deployment-ready. It requires independent validation, probability calibration, portfolio-specific financial assumptions, monitoring, and legal/compliance approval before any production lending use.
