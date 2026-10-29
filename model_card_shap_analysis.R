# Home Credit Default Risk — Exact Logistic-Regression SHAP Analysis
#
# SHAP definition: interventional/marginal Shapley values on the model's
# log-odds scale. With background means mu_j, phi_j = beta_j * (x_j - mu_j)
# and phi_0 = beta_0 + sum(beta_j * mu_j). This decomposition is exact for
# the fitted linear predictor, while assuming marginal rather than conditional
# feature integration.

library(tidyverse)

artifact_path <- "artifacts/enhanced_model_36.rds"
output_directory <- "artifacts"

artifact <- readRDS(artifact_path)
required_artifact_fields <- c(
  "model",
  "predictors",
  "predictor_types",
  "training_medians",
  "application_preparation_parameters",
  "feature_construction"
)
stopifnot(all(required_artifact_fields %in% names(artifact)))
stopifnot(inherits(artifact$model, "glm"))
stopifnot(length(artifact$predictors) == 36)
stopifnot(identical(
  unname(tools::md5sum("data_preparation.R")),
  artifact$feature_construction$source_script_md5
))

source("data_preparation.R")

# Input reconstruction ----------------------------------------------------

train_data <- readr::read_csv(
  "Data/application_train.csv",
  show_col_types = FALSE
)

train_prepared <- prepare_application_data(
  train_data,
  artifact$application_preparation_parameters
)

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
stopifnot(all(artifact$predictors %in% names(enhanced_train)))

apply_training_medians <- function(data, predictors, medians) {
  result <- data

  for (predictor in predictors) {
    invalid <- !is.finite(result[[predictor]])
    result[[predictor]][invalid] <- medians[[predictor]]
  }

  result
}

model_frame <- enhanced_train |>
  dplyr::select(TARGET, dplyr::all_of(artifact$predictors)) |>
  dplyr::mutate(TARGET = as.integer(TARGET)) |>
  apply_training_medians(artifact$predictors, artifact$training_medians)

feature_matrix <- as.matrix(model_frame[artifact$predictors])
storage.mode(feature_matrix) <- "double"

stopifnot(identical(colnames(feature_matrix), artifact$predictors))
stopifnot(all(is.finite(feature_matrix)))
reconstructed_types <- vapply(
  model_frame[artifact$predictors],
  function(x) paste(class(x), collapse = "/"),
  character(1)
)
stopifnot(identical(reconstructed_types, artifact$predictor_types))

model_coefficients <- stats::coef(artifact$model)
stopifnot(identical(names(model_coefficients)[-1], artifact$predictors))
stopifnot(!anyNA(model_coefficients))

# Reproducible SHAP sample and background --------------------------------

set.seed(6812)
sample_rows <- sample.int(nrow(feature_matrix), size = 1000, replace = FALSE)
sample_matrix <- feature_matrix[sample_rows, , drop = FALSE]
background_means <- colMeans(feature_matrix)
coefficients <- model_coefficients[artifact$predictors]
baseline_log_odds <- unname(
  model_coefficients[["(Intercept)"]] + sum(coefficients * background_means)
)

# Exact interventional/marginal SHAP values for the linear predictor.
shap_matrix <- sweep(sample_matrix, 2, background_means, FUN = "-")
shap_matrix <- sweep(shap_matrix, 2, coefficients, FUN = "*")

model_log_odds <- as.numeric(
  stats::predict(
    artifact$model,
    newdata = as.data.frame(sample_matrix),
    type = "link"
  )
)
reconstructed_log_odds <- baseline_log_odds + rowSums(shap_matrix)
model_probability <- as.numeric(
  stats::predict(
    artifact$model,
    newdata = as.data.frame(sample_matrix),
    type = "response"
  )
)
reconstructed_probability <- stats::plogis(reconstructed_log_odds)

log_odds_error <- max(abs(model_log_odds - reconstructed_log_odds))
probability_error <- max(abs(model_probability - reconstructed_probability))
tolerance <- 1e-10
stopifnot(log_odds_error <= tolerance)
stopifnot(probability_error <= tolerance)

# Tidy outputs ------------------------------------------------------------

sampled_applicants <- tibble::tibble(
  SK_ID_CURR = enhanced_train$SK_ID_CURR[sample_rows],
  TARGET = enhanced_train$TARGET[sample_rows],
  predicted_log_odds = model_log_odds,
  predicted_probability = model_probability
)

shap_values <- as.data.frame(shap_matrix) |>
  dplyr::mutate(
    sample_row = seq_len(nrow(sample_matrix)),
    SK_ID_CURR = sampled_applicants$SK_ID_CURR,
    TARGET = sampled_applicants$TARGET,
    predicted_probability = sampled_applicants$predicted_probability
  ) |>
  tidyr::pivot_longer(
    cols = dplyr::all_of(artifact$predictors),
    names_to = "predictor",
    values_to = "shap_log_odds_contribution"
  ) |>
  dplyr::mutate(
    feature_value = as.vector(sample_matrix[cbind(
      sample_row,
      match(predictor, artifact$predictors)
    )])
  )

global_importance <- shap_values |>
  dplyr::group_by(predictor) |>
  dplyr::summarise(
    mean_absolute_shap_log_odds = mean(abs(shap_log_odds_contribution)),
    mean_shap_log_odds = mean(shap_log_odds_contribution),
    .groups = "drop"
  ) |>
  dplyr::arrange(dplyr::desc(mean_absolute_shap_log_odds))

# Reproducible local explanation: the first selected applicant under seed 6812.
local_applicant <- sampled_applicants |>
  dplyr::slice(1)
local_values <- shap_values |>
  dplyr::filter(SK_ID_CURR == local_applicant$SK_ID_CURR) |>
  dplyr::arrange(dplyr::desc(shap_log_odds_contribution))

top_positive <- local_values |>
  dplyr::filter(shap_log_odds_contribution > 0) |>
  dplyr::slice_head(n = 5) |>
  dplyr::mutate(direction = "positive")
top_negative <- local_values |>
  dplyr::filter(shap_log_odds_contribution < 0) |>
  dplyr::arrange(shap_log_odds_contribution) |>
  dplyr::slice_head(n = 5) |>
  dplyr::mutate(direction = "negative")
local_top_contributions <- dplyr::bind_rows(top_positive, top_negative) |>
  dplyr::select(
    SK_ID_CURR,
    TARGET,
    predicted_probability,
    direction,
    predictor,
    feature_value,
    shap_log_odds_contribution
  )

selected_predictors <- unique(local_top_contributions$predictor)
waterfall_contributions <- local_values |>
  dplyr::filter(predictor %in% selected_predictors) |>
  dplyr::select(predictor, shap_log_odds_contribution)
other_contribution <- sum(local_values$shap_log_odds_contribution) -
  sum(waterfall_contributions$shap_log_odds_contribution)

waterfall_steps <- dplyr::bind_rows(
  tibble::tibble(
    component = "Baseline",
    contribution = baseline_log_odds,
    component_type = "baseline"
  ),
  waterfall_contributions |>
    dplyr::rename(component = predictor, contribution = shap_log_odds_contribution) |>
    dplyr::mutate(component_type = if_else(contribution >= 0, "positive", "negative")),
  tibble::tibble(
    component = "Other feature contributions",
    contribution = other_contribution,
    component_type = if_else(other_contribution >= 0, "positive", "negative")
  )
) |>
  dplyr::mutate(
    step = dplyr::row_number(),
    start = dplyr::lag(cumsum(contribution), default = 0),
    end = cumsum(contribution),
    ymin = pmin(start, end),
    ymax = pmax(start, end)
  )

waterfall_final <- tibble::tibble(
  component = "Final log-odds",
  contribution = local_applicant$predicted_log_odds,
  component_type = "final",
  step = max(waterfall_steps$step) + 1,
  start = 0,
  end = local_applicant$predicted_log_odds,
  ymin = min(0, local_applicant$predicted_log_odds),
  ymax = max(0, local_applicant$predicted_log_odds)
)
waterfall_plot_data <- dplyr::bind_rows(waterfall_steps, waterfall_final)

# Visualizations ----------------------------------------------------------

global_plot <- global_importance |>
  dplyr::mutate(predictor = forcats::fct_reorder(
    predictor,
    mean_absolute_shap_log_odds
  )) |>
  ggplot2::ggplot(
    ggplot2::aes(x = predictor, y = mean_absolute_shap_log_odds)
  ) +
  ggplot2::geom_col(fill = "#2C7FB8") +
  ggplot2::coord_flip() +
  ggplot2::labs(
    title = "Global SHAP Feature Importance",
    subtitle = "Mean absolute SHAP contribution across 1,000 applicants",
    x = NULL,
    y = "Mean absolute log-odds contribution"
  ) +
  ggplot2::theme_minimal(base_size = 11)

summary_plot_data <- shap_values |>
  dplyr::group_by(predictor) |>
  dplyr::mutate(
    feature_value_scaled = {
      feature_minimum <- min(feature_value)
      feature_maximum <- max(feature_value)

      if (feature_maximum > feature_minimum) {
        (feature_value - feature_minimum) /
          (feature_maximum - feature_minimum)
      } else {
        rep(0.5, dplyr::n())
      }
    }
  ) |>
  dplyr::ungroup() |>
  dplyr::mutate(
    predictor = factor(predictor, levels = rev(global_importance$predictor))
  )

summary_plot <- ggplot2::ggplot(
  summary_plot_data,
  ggplot2::aes(
    x = shap_log_odds_contribution,
    y = predictor,
    color = feature_value_scaled
  )
) +
  ggplot2::geom_vline(xintercept = 0, color = "grey70", linewidth = 0.3) +
  ggplot2::geom_point(
    alpha = 0.30,
    size = 0.65,
    position = ggplot2::position_jitter(height = 0.22, seed = 6812)
  ) +
  ggplot2::scale_color_gradient(
    low = "#2166AC",
    high = "#B2182B",
    name = "Within-feature\nscaled value"
  ) +
  ggplot2::labs(
    title = "SHAP Summary Plot",
    subtitle = "Exact interventional/marginal SHAP values on the log-odds scale",
    x = "SHAP log-odds contribution",
    y = NULL
  ) +
  ggplot2::theme_minimal(base_size = 10)

waterfall_plot <- ggplot2::ggplot(
  waterfall_plot_data,
  ggplot2::aes(
    xmin = step - 0.4,
    xmax = step + 0.4,
    ymin = ymin,
    ymax = ymax,
    fill = component_type
  )
) +
  ggplot2::geom_rect(color = "white") +
  ggplot2::geom_hline(yintercept = 0, color = "grey70", linewidth = 0.3) +
  ggplot2::scale_fill_manual(
    values = c(
      baseline = "#636363",
      positive = "#D73027",
      negative = "#4575B4",
      final = "#252525"
    ),
    guide = "none"
  ) +
  ggplot2::scale_x_continuous(
    breaks = waterfall_plot_data$step,
    labels = waterfall_plot_data$component
  ) +
  ggplot2::labs(
    title = paste0("Local SHAP Waterfall: Applicant ", local_applicant$SK_ID_CURR),
    subtitle = paste0(
      "Actual TARGET = ", local_applicant$TARGET,
      "; predicted risk = ", sprintf("%.3f", local_applicant$predicted_probability)
    ),
    x = NULL,
    y = "Log-odds"
  ) +
  ggplot2::theme_minimal(base_size = 10) +
  ggplot2::theme(
    axis.text.x = ggplot2::element_text(angle = 45, hjust = 1)
  )

# Save outputs ------------------------------------------------------------

dir.create(output_directory, recursive = TRUE, showWarnings = FALSE)
readr::write_csv(sampled_applicants, file.path(
  output_directory,
  "model_card_shap_sampled_applicants.csv"
))
readr::write_csv(shap_values, file.path(
  output_directory,
  "model_card_shap_values_log_odds.csv"
))
readr::write_csv(global_importance, file.path(
  output_directory,
  "model_card_shap_global_importance.csv"
))
readr::write_csv(local_top_contributions, file.path(
  output_directory,
  "model_card_shap_local_top_contributions.csv"
))
readr::write_csv(tibble::tibble(
  baseline_log_odds = baseline_log_odds,
  baseline_probability = stats::plogis(baseline_log_odds),
  max_log_odds_reconstruction_error = log_odds_error,
  max_probability_reconstruction_error = probability_error,
  tolerance = tolerance,
  shap_definition = "interventional/marginal linear SHAP on log-odds scale"
), file.path(output_directory, "model_card_shap_verification.csv"))
readr::write_csv(tibble::tibble(
  limitation = c(
    "Correlated predictors make marginal/interventional SHAP values differ from conditional attributions.",
    "EXT_SOURCE_1, EXT_SOURCE_2, and EXT_SOURCE_3 are opaque and may encode proxy effects.",
    "SHAP contributions describe model behavior and are not automatically customer-facing adverse-action reasons.",
    "Historical aggregates do not enforce an application-time availability cutoff."
  )
), file.path(output_directory, "model_card_shap_limitations.csv"))
ggplot2::ggsave(
  file.path(output_directory, "model_card_shap_global_importance.png"),
  global_plot,
  width = 9,
  height = 10,
  dpi = 180
)
ggplot2::ggsave(
  file.path(output_directory, "model_card_shap_summary.png"),
  summary_plot,
  width = 10,
  height = 10,
  dpi = 180
)
ggplot2::ggsave(
  file.path(output_directory, "model_card_shap_waterfall.png"),
  waterfall_plot,
  width = 11,
  height = 6,
  dpi = 180
)

message("SHAP verification passed.")
message("Documented local applicant: ", local_applicant$SK_ID_CURR)
message("Predicted risk: ", sprintf("%.6f", local_applicant$predicted_probability))
message("Actual TARGET: ", local_applicant$TARGET)
print(global_importance, n = 10)
print(local_top_contributions, n = nrow(local_top_contributions), width = Inf)
