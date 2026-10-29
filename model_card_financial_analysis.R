# Home Credit Default Risk — Illustrative Financial Threshold Analysis
#
# This script evaluates retrospective decision scenarios only. TARGET = 1
# denotes payment difficulties, not a confirmed permanent loss; AMT_CREDIT is
# a loan-amount proxy rather than exposure at default; and no result is a
# deployment-ready profit forecast.

library(tidyverse)

oof_path <- "artifacts/enhanced_model_36_oof_predictions.csv"
application_path <- "Data/application_train.csv"
threshold_output_path <- "artifacts/model_card_financial_threshold_metrics.csv"
sensitivity_output_path <- "artifacts/model_card_financial_sensitivity_metrics.csv"
optima_output_path <- "artifacts/model_card_financial_sensitivity_optima.csv"

oof_predictions <- readr::read_csv(oof_path, show_col_types = FALSE)
application_amounts <- readr::read_csv(
  application_path,
  col_select = c(SK_ID_CURR, AMT_CREDIT),
  show_col_types = FALSE
)

required_oof_columns <- c("SK_ID_CURR", "TARGET", "predicted_probability")
stopifnot(all(required_oof_columns %in% names(oof_predictions)))
stopifnot(!anyDuplicated(oof_predictions$SK_ID_CURR))
stopifnot(!anyDuplicated(application_amounts$SK_ID_CURR))
stopifnot(all(oof_predictions$TARGET %in% c(0, 1)))
stopifnot(all(is.finite(oof_predictions$predicted_probability)))
stopifnot(all(
  oof_predictions$predicted_probability >= 0 &
    oof_predictions$predicted_probability <= 1
))

analysis_data <- oof_predictions |>
  dplyr::left_join(application_amounts, by = "SK_ID_CURR")

stopifnot(nrow(analysis_data) == nrow(oof_predictions))
stopifnot(!anyNA(analysis_data$AMT_CREDIT))
stopifnot(all(is.finite(analysis_data$AMT_CREDIT)))
stopifnot(all(analysis_data$AMT_CREDIT > 0))
stopifnot(!anyDuplicated(analysis_data$SK_ID_CURR))

thresholds <- seq(0.01, 0.50, by = 0.01)
total_applicants <- nrow(analysis_data)

# Professor Webb's illustrative base case. These are scenario inputs, not
# verified Home Credit profitability or recovery estimates.
base_repayment_contribution <- 0.119
base_recovery_rate <- 0.135
base_loss_severity <- 1 - base_recovery_rate

threshold_counts <- purrr::map_dfr(thresholds, function(threshold) {
  approved <- analysis_data$predicted_probability < threshold
  declined <- !approved

  approved_target_0 <- approved & analysis_data$TARGET == 0
  approved_target_1 <- approved & analysis_data$TARGET == 1
  declined_target_0 <- declined & analysis_data$TARGET == 0
  declined_target_1 <- declined & analysis_data$TARGET == 1

  tibble::tibble(
    threshold = threshold,
    approved_count = sum(approved),
    approval_rate = mean(approved),
    approved_target_0_count = sum(approved_target_0),
    approved_target_1_count = sum(approved_target_1),
    declined_target_0_count = sum(declined_target_0),
    declined_target_1_count = sum(declined_target_1),
    approved_target_0_credit = sum(analysis_data$AMT_CREDIT[approved_target_0]),
    approved_target_1_credit = sum(analysis_data$AMT_CREDIT[approved_target_1]),
    confusion_matrix_total = sum(
      approved_target_0,
      approved_target_1,
      declined_target_0,
      declined_target_1
    )
  )
})

stopifnot(all(threshold_counts$confusion_matrix_total == total_applicants))

calculate_contributions <- function(counts, repayment_contribution, loss_severity) {
  counts |>
    dplyr::mutate(
      standardized_exposure_contribution =
        approved_target_0_count * repayment_contribution -
        approved_target_1_count * loss_severity,
      credit_exposure_proxy_contribution =
        approved_target_0_credit * repayment_contribution -
        approved_target_1_credit * loss_severity
    )
}

base_threshold_metrics <- calculate_contributions(
  threshold_counts,
  base_repayment_contribution,
  base_loss_severity
) |>
  dplyr::mutate(
    repayment_contribution = base_repayment_contribution,
    recovery_rate = base_recovery_rate,
    loss_severity = base_loss_severity
  ) |>
  dplyr::select(
    threshold,
    repayment_contribution,
    recovery_rate,
    loss_severity,
    dplyr::everything()
  )

find_grid_optimum <- function(data, contribution_column) {
  data |>
    dplyr::arrange(dplyr::desc({{ contribution_column }}), threshold) |>
    dplyr::slice(1)
}

base_standardized_optimum <- find_grid_optimum(
  base_threshold_metrics,
  standardized_exposure_contribution
)
base_credit_weighted_optimum <- find_grid_optimum(
  base_threshold_metrics,
  credit_exposure_proxy_contribution
)

# Sensitivity grid: all nine repayment-contribution and recovery-rate pairs.
sensitivity_scenarios <- tidyr::crossing(
  repayment_contribution = c(0.08, 0.1188, 0.16),
  recovery_rate = c(0.00, 0.135, 0.25)
) |>
  dplyr::mutate(loss_severity = 1 - recovery_rate)

sensitivity_threshold_metrics <- purrr::pmap_dfr(
  sensitivity_scenarios,
  function(repayment_contribution, recovery_rate, loss_severity) {
    calculate_contributions(
      threshold_counts,
      repayment_contribution,
      loss_severity
    ) |>
      dplyr::mutate(
        repayment_contribution = repayment_contribution,
        recovery_rate = recovery_rate,
        loss_severity = loss_severity
      ) |>
      dplyr::select(
        repayment_contribution,
        recovery_rate,
        loss_severity,
        dplyr::everything()
      )
  }
)

exposure_basis_metrics <- sensitivity_threshold_metrics |>
  dplyr::select(
    repayment_contribution,
    recovery_rate,
    loss_severity,
    threshold,
    approved_count,
    approval_rate,
    approved_target_0_count,
    approved_target_1_count,
    declined_target_0_count,
    declined_target_1_count,
    confusion_matrix_total,
    standardized_exposure_contribution,
    credit_exposure_proxy_contribution
  ) |>
  tidyr::pivot_longer(
    cols = c(
      standardized_exposure_contribution,
      credit_exposure_proxy_contribution
    ),
    names_to = "exposure_basis",
    values_to = "estimated_contribution"
  ) |>
  dplyr::mutate(
    contribution_unit = dplyr::recode(
      exposure_basis,
      standardized_exposure_contribution = "standardized_exposure_units",
      credit_exposure_proxy_contribution = "AMT_CREDIT_exposure_proxy_units"
    )
  )

sensitivity_optima <- exposure_basis_metrics |>
  dplyr::group_by(
    repayment_contribution,
    recovery_rate,
    loss_severity,
    exposure_basis,
    contribution_unit
  ) |>
  dplyr::arrange(dplyr::desc(estimated_contribution), threshold, .by_group = TRUE) |>
  dplyr::slice(1) |>
  dplyr::ungroup()

stopifnot(all(sensitivity_threshold_metrics$confusion_matrix_total == total_applicants))
stopifnot(nrow(sensitivity_scenarios) == 9)
stopifnot(nrow(sensitivity_optima) == 18)

dir.create("artifacts", recursive = TRUE, showWarnings = FALSE)
readr::write_csv(base_threshold_metrics, threshold_output_path)
readr::write_csv(sensitivity_threshold_metrics, sensitivity_output_path)
readr::write_csv(sensitivity_optima, optima_output_path)

message("Saved base threshold metrics: ", threshold_output_path)
message("Saved sensitivity threshold metrics: ", sensitivity_output_path)
message("Saved sensitivity optima: ", optima_output_path)
message("\nBase-case optimum: standardized exposure units")
print(base_standardized_optimum, width = Inf)
message("\nBase-case optimum: AMT_CREDIT exposure-proxy units")
print(base_credit_weighted_optimum, width = Inf)
message("\nSensitivity optima")
print(sensitivity_optima, n = nrow(sensitivity_optima), width = Inf)
