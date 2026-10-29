# Home Credit Default Risk — Model Card Preparation
#
# Purpose:
# Recreate the final 36-predictor enhanced logistic-regression model and
# generate out-of-fold (OOF) validation probabilities for model-card work.
# This script deliberately skips all benchmark, tree, random-forest, tuning,
# and staged feature-comparison experiments in modeling.qmd.

library(tidyverse)
library(rsample)

source("data_preparation.R")

# Output locations --------------------------------------------------------

artifact_directory <- "artifacts"
model_artifact_path <- file.path(
  artifact_directory,
  "enhanced_model_36.rds"
)
validation_predictions_path <- file.path(
  artifact_directory,
  "enhanced_model_36_oof_predictions.csv"
)

# Input data --------------------------------------------------------------

train_data <- readr::read_csv(
  "Data/application_train.csv",
  show_col_types = FALSE
)

# Keep audit fields from the unmodified application file. In particular, this
# retains the source CODE_GENDER values rather than the later modeling-cleaned
# version in which "XNA" is converted to missing.
audit_fields <- train_data |>
  dplyr::select(
    SK_ID_CURR,
    TARGET,
    CODE_GENDER,
    NAME_EDUCATION_TYPE
  )

# The application preparation parameters are learned once from the complete
# training dataset, exactly as in the final-model workflow. They are stored in
# the artifact for consistent scoring of future applicant data.
application_preparation_parameters <- learn_preparation_parameters(train_data)

train_prepared <- prepare_application_data(
  train_data,
  application_preparation_parameters
)

# Historical feature aggregation -----------------------------------------

bureau_features <- readr::read_csv(
  "Data/bureau.csv",
  show_col_types = FALSE
) |>
  aggregate_bureau_data()

previous_features <- readr::read_csv(
  "Data/previous_application.csv",
  show_col_types = FALSE
) |>
  aggregate_previous_data()

installment_features <- readr::read_csv(
  "Data/installments_payments.csv",
  show_col_types = FALSE
) |>
  aggregate_installments_data()

pos_features <- readr::read_csv(
  "Data/POS_CASH_balance.csv",
  show_col_types = FALSE
) |>
  aggregate_pos_data()

credit_card_features <- readr::read_csv(
  "Data/credit_card_balance.csv",
  show_col_types = FALSE
) |>
  aggregate_credit_card_data()

# Join one row of history features to every applicant and retain applicants
# without history via explicit missing-history indicators.
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

stopifnot(nrow(enhanced_train) == nrow(train_prepared))
stopifnot(!anyDuplicated(enhanced_train$SK_ID_CURR))

# Use these functions in both full-model and fold-specific assembly. The
# historical aggregates are applicant-level summaries defined in
# data_preparation.R; they do not estimate any population-level parameters.
add_historical_features <- function(application_data) {
  application_data |>
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
}

get_raw_applicants <- function(applicant_ids) {
  matched_rows <- match(applicant_ids, train_data$SK_ID_CURR)
  stopifnot(!anyNA(matched_rows))

  train_data[matched_rows, , drop = FALSE]
}

# Final 36 predictors -----------------------------------------------------

enhanced_predictors <- c(
  "AGE_YEARS",
  "AMT_INCOME_TOTAL",
  "AMT_CREDIT",
  "AMT_ANNUITY",
  "ANNUITY_INCOME_RATIO",
  "CREDIT_GOODS_RATIO",
  "BUREAU_LOAN_COUNT",
  "BUREAU_ACTIVE_COUNT",
  "BUREAU_TOTAL_DEBT",
  "BUREAU_MAX_OVERDUE_DAYS",
  "BUREAU_HISTORY_MISSING",
  "PREV_APP_COUNT",
  "PREV_APPROVED_COUNT",
  "PREV_REFUSED_COUNT",
  "PREV_AVG_CREDIT",
  "PREV_HISTORY_MISSING",
  "INST_PAYMENT_COUNT",
  "INST_LATE_PAYMENT_RATE",
  "INST_AVG_PAYMENT_DELAY",
  "INST_TOTAL_SHORTFALL",
  "INST_HISTORY_MISSING",
  "POS_RECORD_COUNT",
  "POS_AVG_DPD",
  "POS_MAX_DPD",
  "POS_LATE_PAYMENT_RATE",
  "POS_AVG_FUTURE_INSTALLMENTS",
  "POS_HISTORY_MISSING",
  "CC_RECORD_COUNT",
  "CC_AVG_BALANCE",
  "CC_AVG_CREDIT_LIMIT",
  "CC_MAX_DPD",
  "CC_LATE_PAYMENT_RATE",
  "CC_HISTORY_MISSING",
  "EXT_SOURCE_1",
  "EXT_SOURCE_2",
  "EXT_SOURCE_3"
)

stopifnot(length(enhanced_predictors) == 36)
stopifnot(all(enhanced_predictors %in% names(enhanced_train)))

# Final-model preprocessing ----------------------------------------------

learn_predictor_medians <- function(data, predictors) {
  medians <- vapply(
    data[predictors],
    function(x) {
      x[!is.finite(x)] <- NA_real_
      median_value <- stats::median(x, na.rm = TRUE)
      if (!is.finite(median_value)) 0 else median_value
    },
    numeric(1)
  )

  medians[predictors]
}

apply_predictor_medians <- function(data, predictors, medians) {
  result <- data

  for (predictor in predictors) {
    missing_values <- !is.finite(result[[predictor]])
    result[[predictor]][missing_values] <- medians[[predictor]]
  }

  result
}

prepare_model_frame <- function(data, predictors, medians) {
  data |>
    dplyr::select(TARGET, dplyr::all_of(predictors)) |>
    dplyr::mutate(TARGET = as.integer(TARGET)) |>
    apply_predictor_medians(predictors, medians)
}

# Full-data model artifact ------------------------------------------------

training_medians <- learn_predictor_medians(
  enhanced_train,
  enhanced_predictors
)

enhanced_model_data <- prepare_model_frame(
  enhanced_train,
  enhanced_predictors,
  training_medians
)

enhanced_model <- stats::glm(
  TARGET ~ .,
  data = enhanced_model_data,
  family = stats::binomial()
)

stopifnot(enhanced_model$converged)

model_artifact <- list(
  model = enhanced_model,
  predictors = enhanced_predictors,
  predictor_types = vapply(
    enhanced_model_data[enhanced_predictors],
    function(x) paste(class(x), collapse = "/"),
    character(1)
  ),
  training_medians = training_medians,
  application_preparation_parameters = application_preparation_parameters,
  preprocessing = list(
    application_preparation_function = "prepare_application_data",
    predictor_missing_value_rule = paste0(
      "Replace missing or non-finite predictor values with the ",
      "training median; use 0 if no finite median exists."
    ),
    historical_missing_indicators = c(
      "BUREAU_HISTORY_MISSING",
      "PREV_HISTORY_MISSING",
      "INST_HISTORY_MISSING",
      "POS_HISTORY_MISSING",
      "CC_HISTORY_MISSING"
    )
  ),
  feature_construction = list(
    source_script = "data_preparation.R",
    source_script_md5 = unname(tools::md5sum("data_preparation.R")),
    application_functions = c(
      "clean_application_data",
      "create_features",
      "learn_preparation_parameters",
      "apply_preparation_parameters",
      "prepare_application_data"
    ),
    historical_aggregation_functions = c(
      bureau = "aggregate_bureau_data",
      previous_applications = "aggregate_previous_data",
      installments = "aggregate_installments_data",
      pos_cash = "aggregate_pos_data",
      credit_card = "aggregate_credit_card_data"
    ),
    historical_feature_sources = c(
      "Data/bureau.csv",
      "Data/previous_application.csv",
      "Data/installments_payments.csv",
      "Data/POS_CASH_balance.csv",
      "Data/credit_card_balance.csv"
    ),
    timing_limitation = paste(
      "Historical records are aggregated as supplied and this workflow does",
      "not impose an application-time cutoff. Their availability at the",
      "lending decision time must be validated before operational use."
    )
  ),
  runtime = list(
    r_version = R.version.string,
    platform = R.version$platform,
    package_versions = vapply(
      c("tidyverse", "rsample", "dplyr", "readr"),
      function(package_name) {
        as.character(utils::packageVersion(package_name))
      },
      character(1)
    )
  ),
  training_rows = nrow(enhanced_model_data),
  model_family = "binomial",
  created_at_utc = format(Sys.time(), tz = "UTC", usetz = TRUE)
)

# Five-fold OOF predictions ----------------------------------------------

# Every fitted preprocessing value used in an OOF fold is learned solely from
# that fold's analysis applicants. CODE_GENDER and NAME_EDUCATION_TYPE are
# carried through only as audit fields; they are never model predictors.
set.seed(123)

enhanced_folds <- rsample::vfold_cv(
  enhanced_train,
  v = 5,
  strata = TARGET
)

oof_validation_predictions <- purrr::map_dfr(
  seq_along(enhanced_folds$splits),
  function(fold_number) {
    split <- enhanced_folds$splits[[fold_number]]
    analysis_ids <- rsample::analysis(split)$SK_ID_CURR
    assessment_ids <- rsample::assessment(split)$SK_ID_CURR

    analysis_raw <- get_raw_applicants(analysis_ids)
    assessment_raw <- get_raw_applicants(assessment_ids)

    fold_application_parameters <- learn_preparation_parameters(analysis_raw)

    analysis_data <- prepare_application_data(
      analysis_raw,
      fold_application_parameters
    ) |>
      add_historical_features()
    assessment_data <- prepare_application_data(
      assessment_raw,
      fold_application_parameters
    ) |>
      add_historical_features()

    stopifnot(nrow(analysis_data) == length(analysis_ids))
    stopifnot(nrow(assessment_data) == length(assessment_ids))
    stopifnot(identical(analysis_data$SK_ID_CURR, analysis_ids))
    stopifnot(identical(assessment_data$SK_ID_CURR, assessment_ids))

    fold_medians <- learn_predictor_medians(
      analysis_data,
      enhanced_predictors
    )

    analysis_model_data <- prepare_model_frame(
      analysis_data,
      enhanced_predictors,
      fold_medians
    )
    assessment_model_data <- prepare_model_frame(
      assessment_data,
      enhanced_predictors,
      fold_medians
    )

    assessment_audit <- audit_fields |>
      dplyr::slice(match(assessment_ids, SK_ID_CURR))

    stopifnot(identical(assessment_audit$SK_ID_CURR, assessment_ids))

    fold_model <- stats::glm(
      TARGET ~ .,
      data = analysis_model_data,
      family = stats::binomial()
    )

    tibble::tibble(
      SK_ID_CURR = assessment_audit$SK_ID_CURR,
      TARGET = assessment_audit$TARGET,
      CODE_GENDER = assessment_audit$CODE_GENDER,
      NAME_EDUCATION_TYPE = assessment_audit$NAME_EDUCATION_TYPE,
      fold = fold_number,
      predicted_probability = as.numeric(
        stats::predict(
          fold_model,
          newdata = dplyr::select(assessment_model_data, -TARGET),
          type = "response"
        )
      )
    )
  }
)

stopifnot(nrow(oof_validation_predictions) == nrow(enhanced_train))
stopifnot(!anyDuplicated(oof_validation_predictions$SK_ID_CURR))
stopifnot(all(is.finite(oof_validation_predictions$predicted_probability)))
stopifnot(all(
  oof_validation_predictions$predicted_probability >= 0 &
    oof_validation_predictions$predicted_probability <= 1
))

# Persist artifacts -------------------------------------------------------

dir.create(artifact_directory, recursive = TRUE, showWarnings = FALSE)

saveRDS(model_artifact, model_artifact_path)
readr::write_csv(oof_validation_predictions, validation_predictions_path)

message("Saved model artifact: ", model_artifact_path)
message("Saved OOF validation predictions: ", validation_predictions_path)
