# Home Credit Default Risk — Proposed Adverse-Action Mapping
#
# These are proposed explanatory mappings for model-card review only. They are
# not legally approved adverse-action notices, and SHAP alone does not establish
# regulatory compliance.

library(tidyverse)

artifact <- readRDS("artifacts/enhanced_model_36.rds")
stopifnot(inherits(artifact$model, "glm"))
stopifnot(identical(
  unname(tools::md5sum("data_preparation.R")),
  artifact$feature_construction$source_script_md5
))
source("data_preparation.R")

# Feature mapping ---------------------------------------------------------

feature_mapping <- tibble::tribble(
  ~technical_feature, ~verified_feature_definition, ~proposed_plain_language, ~feature_category, ~customer_reason_status, ~reason_group, ~limitations_or_documentation,
  "AGE_YEARS", "Applicant age in years: -DAYS_BIRTH / 365.25.", "Age was associated with the model's risk estimate.", "potentially sensitive/proxy", "Do not use without compliance review", "Applicant characteristics", "Age can be legally protected or regulated; validate permissible use and disparate-impact implications.",
  "AMT_INCOME_TOTAL", "Applicant-reported total income in the application data.", "Reported income information affected the risk estimate.", "application financial", "Potential with documentation", "Income and affordability", "Confirm data accuracy, permissible use, and a customer-understandable reason policy.",
  "AMT_CREDIT", "Requested credit amount in the application data.", "The requested amount affected the risk estimate.", "application financial", "Potential with documentation", "Requested financing", "Requires product-policy context; do not imply that amount alone caused the decision.",
  "AMT_ANNUITY", "Required annuity payment amount in the application data.", "The scheduled payment amount affected the risk estimate.", "application financial", "Potential with documentation", "Income and affordability", "Confirm that the payment field is accurate and disclosed in a customer-understandable way.",
  "ANNUITY_INCOME_RATIO", "AMT_ANNUITY divided by AMT_INCOME_TOTAL; larger values indicate larger payment burden relative to income.", "The scheduled payment was high relative to reported income.", "engineered affordability", "Potential with documentation", "Income and affordability", "Validate ratio calculation, income verification, and policy use before customer communication.",
  "CREDIT_GOODS_RATIO", "AMT_CREDIT divided by AMT_GOODS_PRICE; measures financing relative to goods price.", "The requested financing was high relative to the goods price.", "engineered financing", "Potential with documentation", "Requested financing", "Confirm product meaning, treatment of fees, and whether the ratio is a permitted notice reason.",
  "BUREAU_LOAN_COUNT", "Number of Bureau credit-history records for the applicant.", "The amount of recorded external credit history affected the risk estimate.", "external credit history", "Potential with documentation", "Credit history depth", "Requires verified Bureau source, accuracy procedures, and a more specific customer-facing reason if used.",
  "BUREAU_ACTIVE_COUNT", "Count of Bureau records with CREDIT_ACTIVE equal to Active.", "The number of active external credit accounts affected the risk estimate.", "external credit history", "Potential with documentation", "Active credit obligations", "Requires verified Bureau definitions, accuracy controls, and compliance review.",
  "BUREAU_TOTAL_DEBT", "Sum of AMT_CREDIT_SUM_DEBT across Bureau records.", "Recorded outstanding external credit debt affected the risk estimate.", "external credit history", "Potential with documentation", "Outstanding debt", "Requires source verification, currentness checks, and a customer-understandable debt definition.",
  "BUREAU_MAX_OVERDUE_DAYS", "Maximum CREDIT_DAY_OVERDUE across Bureau records, or missing when all values are missing.", "Past-due days in external credit history affected the risk estimate.", "external credit history", "Potential with documentation", "Past-due credit history", "Requires verified timing, dispute handling, and compliance review.",
  "BUREAU_HISTORY_MISSING", "Indicator that BUREAU_LOAN_COUNT is missing after the Bureau join.", "No customer-facing explanation proposed.", "missing-data indicator", "Not suitable as a standalone reason", "Data availability", "Missingness is a data-availability signal, not a substantive applicant behavior; investigate source coverage and proxy risk.",
  "PREV_APP_COUNT", "Number of previous_application records for the applicant.", "The amount of prior application history affected the risk estimate.", "internal application history", "Potential with documentation", "Prior applications", "Requires verified availability, product scope, and a more specific explanation before use.",
  "PREV_APPROVED_COUNT", "Count of previous applications with NAME_CONTRACT_STATUS equal to Approved.", "Prior approved applications affected the risk estimate.", "internal application history", "Potential with documentation", "Prior applications", "Requires clear product/time scope and compliance review.",
  "PREV_REFUSED_COUNT", "Count of previous applications with NAME_CONTRACT_STATUS equal to Refused.", "Prior application outcomes affected the risk estimate.", "internal application history", "Potential with documentation", "Prior applications", "Potentially sensitive/regulated; verify reason-code lineage and do not use circular or unverifiable explanations.",
  "PREV_AVG_CREDIT", "Mean AMT_CREDIT among previous applications with status Approved.", "The average amount of prior approved credit affected the risk estimate.", "internal application history", "Potential with documentation", "Prior applications", "Requires product/time scope and explanation validation.",
  "PREV_HISTORY_MISSING", "Indicator that PREV_APP_COUNT is missing after the previous-application join.", "No customer-facing explanation proposed.", "missing-data indicator", "Not suitable as a standalone reason", "Data availability", "Missingness is not a substantive adverse fact; assess data coverage and proxy effects.",
  "INST_PAYMENT_COUNT", "Number of installment-payment records for the applicant.", "The amount of recorded installment-payment history affected the risk estimate.", "repayment history", "Potential with documentation", "Repayment history", "Requires verified time availability and a more specific behavior-based reason.",
  "INST_LATE_PAYMENT_RATE", "Mean of PAYMENT_DELAY > 0, where PAYMENT_DELAY is DAYS_ENTRY_PAYMENT minus DAYS_INSTALMENT.", "A higher share of recorded installment payments made after the scheduled date affected the risk estimate.", "repayment history", "Potential with documentation", "Late-payment history", "Strong candidate only after validating dates, completeness, product scope, and legal notice language.",
  "INST_AVG_PAYMENT_DELAY", "Mean of positive PAYMENT_DELAY values, with negative delays replaced by zero.", "Longer recorded delays in installment payments affected the risk estimate.", "repayment history", "Potential with documentation", "Late-payment history", "Validate timing and completeness; deduplicate with late-payment rate in notices.",
  "INST_TOTAL_SHORTFALL", "Sum of max(AMT_INSTALMENT - AMT_PAYMENT, 0) across installment records.", "Recorded installment payment shortfalls affected the risk estimate.", "repayment history", "Potential with documentation", "Payment shortfalls", "Validate balances, reversals, timing, and customer-dispute processes.",
  "INST_HISTORY_MISSING", "Indicator that INST_PAYMENT_COUNT is missing after the installment join.", "No customer-facing explanation proposed.", "missing-data indicator", "Not suitable as a standalone reason", "Data availability", "Missingness is not a substantive adverse fact; assess coverage and proxy effects.",
  "POS_RECORD_COUNT", "Number of POS/CASH balance records for the applicant.", "The amount of recorded point-of-sale or cash-balance history affected the risk estimate.", "repayment history", "Potential with documentation", "POS/CASH history", "Requires product scope and a more specific customer-facing interpretation.",
  "POS_AVG_DPD", "Mean SK_DPD across POS/CASH balance records.", "Average days past due in recorded point-of-sale or cash history affected the risk estimate.", "repayment history", "Potential with documentation", "Late-payment history", "Verify SK_DPD definition, timing, and compliance suitability.",
  "POS_MAX_DPD", "Maximum SK_DPD across POS/CASH balance records.", "The most severe recorded days-past-due event affected the risk estimate.", "repayment history", "Potential with documentation", "Late-payment history", "Validate definition and timing; deduplicate with other delinquency reasons.",
  "POS_LATE_PAYMENT_RATE", "Mean of SK_DPD > 0 across POS/CASH balance records.", "A higher share of recorded POS/CASH payments past due affected the risk estimate.", "repayment history", "Potential with documentation", "Late-payment history", "Verify SK_DPD, product scope, and notice language; deduplicate with other delinquency reasons.",
  "POS_AVG_FUTURE_INSTALLMENTS", "Mean CNT_INSTALMENT_FUTURE across POS/CASH balance records.", "Remaining scheduled installments in prior POS/CASH history affected the risk estimate.", "repayment history", "Potential with documentation", "Existing obligations", "Interpretation is indirect; requires product and timing documentation before customer use.",
  "POS_HISTORY_MISSING", "Indicator that POS_RECORD_COUNT is missing after the POS/CASH join.", "No customer-facing explanation proposed.", "missing-data indicator", "Not suitable as a standalone reason", "Data availability", "Missingness is not a substantive adverse fact; assess coverage and proxy effects.",
  "CC_RECORD_COUNT", "Number of credit-card balance records for the applicant.", "The amount of recorded credit-card history affected the risk estimate.", "repayment history", "Potential with documentation", "Credit-card history", "Requires product scope and a more specific behavior-based explanation.",
  "CC_AVG_BALANCE", "Mean AMT_BALANCE across credit-card balance records.", "Average recorded credit-card balance affected the risk estimate.", "repayment history", "Potential with documentation", "Credit-card balance", "Verify balance timing, source accuracy, and notice suitability.",
  "CC_AVG_CREDIT_LIMIT", "Mean AMT_CREDIT_LIMIT_ACTUAL across credit-card balance records.", "Recorded credit-card limit affected the risk estimate.", "repayment history", "Potential with documentation", "Credit-card exposure", "Interpretation may be indirect and proxy-related; compliance review required.",
  "CC_MAX_DPD", "Maximum SK_DPD across credit-card balance records.", "The most severe recorded credit-card days-past-due event affected the risk estimate.", "repayment history", "Potential with documentation", "Late-payment history", "Verify SK_DPD definition, timing, data accuracy, and notice wording.",
  "CC_LATE_PAYMENT_RATE", "Mean of SK_DPD > 0 across credit-card balance records.", "A higher share of recorded credit-card payments past due affected the risk estimate.", "repayment history", "Potential with documentation", "Late-payment history", "Verify timing and completeness; deduplicate with other delinquency reasons.",
  "CC_HISTORY_MISSING", "Indicator that CC_RECORD_COUNT is missing after the credit-card join.", "No customer-facing explanation proposed.", "missing-data indicator", "Not suitable as a standalone reason", "Data availability", "Missingness is not a substantive adverse fact; assess coverage and proxy effects.",
  "EXT_SOURCE_1", "No definition is provided in the project sources beyond an external score variable.", "No customer-facing explanation proposed.", "opaque external score", "Not suitable without verified provenance", "Opaque external score", "Obtain source, scale, permitted use, data lineage, accuracy/dispute process, and compliance approval before any use.",
  "EXT_SOURCE_2", "No definition is provided in the project sources beyond an external score variable.", "No customer-facing explanation proposed.", "opaque external score", "Not suitable without verified provenance", "Opaque external score", "Obtain source, scale, permitted use, data lineage, accuracy/dispute process, and compliance approval before any use.",
  "EXT_SOURCE_3", "No definition is provided in the project sources beyond an external score variable.", "No customer-facing explanation proposed.", "opaque external score", "Not suitable without verified provenance", "Opaque external score", "Obtain source, scale, permitted use, data lineage, accuracy/dispute process, and compliance approval before any use."
)

stopifnot(identical(feature_mapping$technical_feature, artifact$predictors))

# Reconstruct the exact scored training matrix ---------------------------

train_data <- readr::read_csv("Data/application_train.csv", show_col_types = FALSE)
train_prepared <- prepare_application_data(
  train_data,
  artifact$application_preparation_parameters
)
bureau_features <- readr::read_csv("Data/bureau.csv", show_col_types = FALSE) |> aggregate_bureau_data()
previous_features <- readr::read_csv("Data/previous_application.csv", show_col_types = FALSE) |> aggregate_previous_data()
installment_features <- readr::read_csv("Data/installments_payments.csv", show_col_types = FALSE) |> aggregate_installments_data()
pos_features <- readr::read_csv("Data/POS_CASH_balance.csv", show_col_types = FALSE) |> aggregate_pos_data()
credit_card_features <- readr::read_csv("Data/credit_card_balance.csv", show_col_types = FALSE) |> aggregate_credit_card_data()

enhanced_train <- train_prepared |>
  dplyr::left_join(bureau_features, by = "SK_ID_CURR") |>
  dplyr::left_join(previous_features, by = "SK_ID_CURR") |>
  dplyr::left_join(installment_features, by = "SK_ID_CURR") |>
  dplyr::left_join(pos_features, by = "SK_ID_CURR") |>
  dplyr::left_join(credit_card_features, by = "SK_ID_CURR") |>
  dplyr::mutate(
    BUREAU_HISTORY_MISSING = as.integer(is.na(BUREAU_LOAN_COUNT)),
    PREV_HISTORY_MISSING = as.integer(is.na(PREV_APP_COUNT)),
    INST_HISTORY_MISSING = as.integer(is.na(INST_PAYMENT_COUNT)),
    POS_HISTORY_MISSING = as.integer(is.na(POS_RECORD_COUNT)),
    CC_HISTORY_MISSING = as.integer(is.na(CC_RECORD_COUNT))
  )
stopifnot(nrow(enhanced_train) == nrow(train_data))
stopifnot(!anyDuplicated(enhanced_train$SK_ID_CURR))

model_frame <- enhanced_train |>
  dplyr::select(TARGET, dplyr::all_of(artifact$predictors)) |>
  dplyr::mutate(TARGET = as.integer(TARGET))
for (predictor in artifact$predictors) {
  invalid <- !is.finite(model_frame[[predictor]])
  model_frame[[predictor]][invalid] <- artifact$training_medians[[predictor]]
}
feature_matrix <- as.matrix(model_frame[artifact$predictors])
storage.mode(feature_matrix) <- "double"
stopifnot(identical(colnames(feature_matrix), artifact$predictors))
stopifnot(all(is.finite(feature_matrix)))

# Exact marginal/interventional linear SHAP for a reproducible declined case.
coefficients <- stats::coef(artifact$model)[artifact$predictors]
background_means <- colMeans(feature_matrix)
baseline_log_odds <- unname(
  stats::coef(artifact$model)[["(Intercept)"]] +
    sum(coefficients * background_means)
)
predicted_risk <- as.numeric(stats::predict(
  artifact$model,
  newdata = as.data.frame(feature_matrix),
  type = "response"
))
eligible_rows <- which(predicted_risk >= 0.12)
stopifnot(length(eligible_rows) > 0)
set.seed(6812)
example_row <- as.integer(sample(eligible_rows, size = 1, replace = FALSE))
stopifnot(
  length(predicted_risk) == nrow(feature_matrix),
  length(example_row) == 1,
  example_row >= 1,
  example_row <= length(predicted_risk)
)
example_applicant_id <- enhanced_train$SK_ID_CURR[example_row]
example_target <- enhanced_train$TARGET[example_row]
example_predicted_risk <- predicted_risk[example_row]
stopifnot(
  length(example_applicant_id) == 1,
  length(example_target) == 1,
  length(example_predicted_risk) == 1,
  is.finite(example_predicted_risk)
)
example_matrix <- feature_matrix[example_row, , drop = FALSE]
example_shap <- as.numeric((example_matrix[1, ] - background_means) * coefficients)
names(example_shap) <- artifact$predictors
example_log_odds <- as.numeric(stats::predict(
  artifact$model,
  newdata = as.data.frame(example_matrix),
  type = "link"
))
reconstructed_log_odds <- baseline_log_odds + sum(example_shap)
reconstructed_risk <- stats::plogis(reconstructed_log_odds)
tolerance <- 1e-10
stopifnot(abs(example_log_odds - reconstructed_log_odds) <= tolerance)
stopifnot(abs(example_predicted_risk - reconstructed_risk) <= tolerance)
stopifnot(example_predicted_risk >= 0.12)

example_contributions <- tibble::tibble(
  SK_ID_CURR = example_applicant_id,
  TARGET = example_target,
  predicted_risk = example_predicted_risk,
  threshold = 0.12,
  decision = "declined",
  technical_feature = artifact$predictors,
  feature_value = as.numeric(example_matrix[1, ]),
  shap_log_odds_contribution = example_shap
) |>
  dplyr::left_join(feature_mapping, by = "technical_feature") |>
  dplyr::arrange(dplyr::desc(shap_log_odds_contribution))

positive_risk_contributions <- example_contributions |>
  dplyr::filter(shap_log_odds_contribution > 0) |>
  dplyr::mutate(
    proposed_reason_eligible = customer_reason_status == "Potential with documentation"
  )

deduplicated_proposed_reasons <- positive_risk_contributions |>
  dplyr::filter(proposed_reason_eligible) |>
  dplyr::group_by(reason_group) |>
  dplyr::arrange(dplyr::desc(shap_log_odds_contribution), .by_group = TRUE) |>
  dplyr::slice(1) |>
  dplyr::ungroup() |>
  dplyr::mutate(
    proposed_reason_status = "Proposed only; requires documentation and compliance review"
  )

flagged_positive_contributions <- positive_risk_contributions |>
  dplyr::filter(!proposed_reason_eligible) |>
  dplyr::mutate(
    proposed_reason_status = "Not proposed as a customer-facing reason"
  )

dir.create("artifacts", recursive = TRUE, showWarnings = FALSE)
readr::write_csv(feature_mapping, "artifacts/model_card_adverse_action_feature_mapping.csv")
readr::write_csv(example_contributions, "artifacts/model_card_adverse_action_example_contributions.csv")
readr::write_csv(deduplicated_proposed_reasons, "artifacts/model_card_adverse_action_proposed_reasons.csv")
readr::write_csv(flagged_positive_contributions, "artifacts/model_card_adverse_action_flagged_contributions.csv")
readr::write_csv(tibble::tibble(
  SK_ID_CURR = example_applicant_id,
  TARGET = example_target,
  threshold = 0.12,
  predicted_risk = example_predicted_risk,
  decision = "declined",
  baseline_log_odds = baseline_log_odds,
  model_log_odds = example_log_odds,
  reconstructed_log_odds = reconstructed_log_odds,
  reconstruction_error = abs(example_log_odds - reconstructed_log_odds),
  probability_reconstruction_error = abs(example_predicted_risk - reconstructed_risk),
  shap_definition = "interventional/marginal linear SHAP on log-odds scale"
), "artifacts/model_card_adverse_action_verification.csv")

message("Adverse-action mapping completed.")
message("Example applicant: ", example_applicant_id)
message("Predicted risk: ", sprintf("%.6f", example_predicted_risk))
message("Actual TARGET: ", example_target)
print(positive_risk_contributions |> dplyr::slice_head(n = 10), width = Inf)
print(deduplicated_proposed_reasons, width = Inf)
