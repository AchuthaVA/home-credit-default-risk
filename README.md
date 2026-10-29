# Home Credit Default Risk

## IS 6812 Model Card project

This project develops and documents a model that estimates an applicant's risk of recorded payment difficulties for the Home Credit Default Risk dataset. It is an academic decision-support analysis, not a production lending system. In this dataset, `TARGET = 1` records payment difficulties; it is not a confirmed permanent loan loss.

The final model is a binomial logistic regression with 36 predictors. It was fit on 307,511 training applicants and combines application and affordability information, aggregated historical credit and repayment information, and three opaque `EXT_SOURCE` variables. The final workflow is documented in [modeling.qmd](modeling.qmd).

## Model performance

The original modeling workflow reports a mean five-fold stratified cross-validation ROC AUC of **0.7481**. Separately, pooling all 307,511 out-of-fold (OOF) predictions produced ROC AUC **0.748113**. These are different calculations and should not be treated as identical statistics.

The final-model results documented in `modeling.qmd` report Kaggle ROC AUC of **0.74751** on the public leaderboard and **0.73212** on the private leaderboard. The local submission files available in the project do not independently verify that the 36-predictor submission produced those scores; they are therefore documented competition results with a provenance caveat.

## Model Card

[model_card.qmd](model_card.qmd) is the reproducible Quarto source for the final nine-section Model Card:

1. Model Details
2. Intended Use
3. Performance
4. Decision Threshold
5. Explainability
6. Adverse Action Mapping
7. Fairness
8. Limitations and Risks
9. Executive Summary

The Model Card uses an illustrative approval rule: approve an applicant when predicted risk is strictly below **0.12**. This threshold is a retrospective scenario based on unverified financial assumptions; it is not a deployment recommendation.

The Model Card includes:

- OOF threshold-performance analysis;
- illustrative financial sensitivity analysis using standardized exposure units and `AMT_CREDIT` exposure-proxy units, not realized profit;
- exact linear-model SHAP explanations on the log-odds scale;
- proposed adverse-action mappings, explicitly not legally approved notices; and
- descriptive fairness analyses for reported gender and education groups using OOF predictions.

[model_card.html](model_card.html) is the rendered, self-contained version of the Model Card. Open that file directly in a modern web browser to view the report, tables, and embedded figures; rendering R or downloading the ignored artifacts is not required for viewing it.

## Repository files

- `data_preparation.R` — reusable application preparation and historical-data aggregation functions.
- `eda.qmd` — exploratory data analysis notebook.
- `modeling.qmd` / `modeling.html` — modeling workflow and rendered report.
- `model_card_preparation.R` — recreates the final model artifact and five-fold OOF predictions without rerunning earlier benchmark experiments.
- `model_card_threshold_analysis.R` — produces threshold metrics from OOF predictions.
- `model_card_financial_analysis.R` — produces illustrative financial threshold and sensitivity outputs.
- `model_card_shap_analysis.R` — produces exact log-odds SHAP outputs and figures from the saved model.
- `model_card_adverse_action_analysis.R` — produces proposed feature-to-reason mappings and an illustrative declined-applicant explanation.
- `model_card_fairness_analysis.R` — produces descriptive OOF fairness metrics and figures.
- `model_card.qmd` / `model_card.html` — Model Card source and self-contained rendered deliverable.

## Reproducing Model Card artifacts

The raw `Data/` directory and generated `artifacts/` directory are intentionally Git-ignored. Consequently, a fresh clone can open `model_card.html`, but cannot render `model_card.qmd` until the original data and locally generated artifacts are available.

The scripts directly verify the following inputs and dependencies:

- `data_preparation.R` and all Model Card scripts use the R `tidyverse` package.
- `model_card_preparation.R` additionally uses `rsample` for five-fold stratified OOF validation.
- The preparation, SHAP, and adverse-action scripts require the original application-training and historical Home Credit CSV files under `Data/`; the preparation script writes `artifacts/enhanced_model_36.rds` and `artifacts/enhanced_model_36_oof_predictions.csv`.
- The threshold, financial, and fairness scripts use the OOF predictions. The financial script also reads `Data/application_train.csv` for `AMT_CREDIT`.
- The SHAP and adverse-action scripts use the saved model artifact, `data_preparation.R`, and the original historical files. Both verify that the current `data_preparation.R` matches the source checksum stored in the model artifact.
- `model_card.qmd` checks for all required saved artifacts before rendering. It is rendered with Quarto after the analyses have produced those inputs.

With the original data and the required R packages already available, run the scripts from the project root in this order:

```text
model_card_preparation.R
model_card_threshold_analysis.R
model_card_financial_analysis.R
model_card_shap_analysis.R
model_card_adverse_action_analysis.R
model_card_fairness_analysis.R
```

Then render `model_card.qmd` with Quarto. These instructions describe the existing scripts only; the repository does not provide package-installation commands or include the raw data/artifacts needed to reproduce the analyses in a new clone.

## Limitations

The model is not deployment-ready. The Model Card documents limitations involving target meaning, calibration, historical-data timing, external-score opacity, financial assumptions, group disparities, external validity, and governance. Any real lending use would require independent validation, approved financial assumptions, monitoring, legal/compliance review, and model-risk governance.
