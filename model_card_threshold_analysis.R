# Home Credit Default Risk — Model Card Threshold Analysis
#
# Uses out-of-fold probabilities from the final model to describe lending
# decisions at candidate risk thresholds. This script does not estimate profit
# or choose a financially optimal threshold.

library(tidyverse)

input_path <- "artifacts/enhanced_model_36_oof_predictions.csv"
output_path <- "artifacts/model_card_threshold_metrics.csv"

oof_predictions <- readr::read_csv(input_path, show_col_types = FALSE)

# Identify and validate the model-card outcome and risk-score columns.
target_candidates <- c("TARGET", "target", "outcome")
probability_candidates <- c(
  "predicted_probability",
  "prediction",
  "probability",
  "risk_score"
)

target_matches <- intersect(target_candidates, names(oof_predictions))
probability_matches <- intersect(probability_candidates, names(oof_predictions))

if (length(target_matches) != 1 || length(probability_matches) != 1) {
  stop(
    "Could not identify exactly one TARGET and one predicted-probability ",
    "column. Available columns: ",
    paste(names(oof_predictions), collapse = ", ")
  )
}

target_column <- target_matches[[1]]
probability_column <- probability_matches[[1]]
target <- oof_predictions[[target_column]]
predicted_risk <- oof_predictions[[probability_column]]

stopifnot(all(target %in% c(0, 1)))
stopifnot(all(is.finite(predicted_risk)))
stopifnot(all(predicted_risk >= 0 & predicted_risk <= 1))

thresholds <- seq(0.01, 0.50, by = 0.01)
total_applicants <- nrow(oof_predictions)

threshold_metrics <- purrr::map_dfr(thresholds, function(threshold) {
  # An applicant is approved only when predicted risk is strictly below the
  # candidate threshold. A decline is the positive decision for TARGET = 1.
  approved <- predicted_risk < threshold
  declined <- !approved

  approved_target_0 <- sum(approved & target == 0)
  approved_target_1 <- sum(approved & target == 1)
  declined_target_0 <- sum(declined & target == 0)
  declined_target_1 <- sum(declined & target == 1)

  predicted_positive <- declined_target_0 + declined_target_1
  actual_positive <- approved_target_1 + declined_target_1
  approved_count <- approved_target_0 + approved_target_1

  tibble::tibble(
    threshold = threshold,
    approved_count = approved_count,
    approved_percentage = 100 * approved_count / total_applicants,
    approved_target_0 = approved_target_0,
    approved_target_1 = approved_target_1,
    declined_target_0 = declined_target_0,
    declined_target_1 = declined_target_1,
    precision_target_1 = dplyr::if_else(
      predicted_positive > 0,
      declined_target_1 / predicted_positive,
      NA_real_
    ),
    recall_target_1 = dplyr::if_else(
      actual_positive > 0,
      declined_target_1 / actual_positive,
      NA_real_
    ),
    approved_target_1_percentage = dplyr::if_else(
      approved_count > 0,
      100 * approved_target_1 / approved_count,
      NA_real_
    ),
    confusion_matrix_total = approved_target_0 + approved_target_1 +
      declined_target_0 + declined_target_1
  )
})

stopifnot(all(threshold_metrics$confusion_matrix_total == total_applicants))

dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)
readr::write_csv(threshold_metrics, output_path)

summary_thresholds <- c(0.05, 0.10, 0.15, 0.20, 0.30, 0.40, 0.50)
threshold_summary <- threshold_metrics |>
  dplyr::filter(round(threshold, 2) %in% summary_thresholds) |>
  dplyr::select(
    threshold,
    approved_count,
    approved_percentage,
    approved_target_0,
    approved_target_1,
    declined_target_0,
    declined_target_1,
    precision_target_1,
    recall_target_1,
    approved_target_1_percentage
  )

message("TARGET column: ", target_column)
message("Predicted-probability column: ", probability_column)
message("Saved threshold metrics: ", output_path)
print(threshold_summary, n = nrow(threshold_summary), width = Inf)
