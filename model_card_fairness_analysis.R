# Home Credit Default Risk — Descriptive Fairness Analysis
#
# This script reports retrospective group disparities for OOF predictions. It
# does not establish unlawful discrimination, causal bias, or deployment
# suitability. A positive classification is predicted TARGET = 1, operationally
# represented here by a decline when predicted risk is at least 0.12.

library(tidyverse)

oof_path <- "artifacts/enhanced_model_36_oof_predictions.csv"
threshold_metrics_path <- "artifacts/model_card_threshold_metrics.csv"
output_directory <- "artifacts"
threshold <- 0.12
small_group_threshold <- 1000L

oof_predictions <- readr::read_csv(oof_path, show_col_types = FALSE)
required_columns <- c(
  "SK_ID_CURR", "TARGET", "CODE_GENDER", "NAME_EDUCATION_TYPE",
  "predicted_probability"
)
stopifnot(all(required_columns %in% names(oof_predictions)))
stopifnot(nrow(oof_predictions) == 307511)
stopifnot(!anyDuplicated(oof_predictions$SK_ID_CURR))
stopifnot(all(oof_predictions$TARGET %in% c(0, 1)))
stopifnot(all(is.finite(oof_predictions$predicted_probability)))

threshold_metrics <- readr::read_csv(
  threshold_metrics_path,
  show_col_types = FALSE
)
threshold_reference <- threshold_metrics |>
  dplyr::filter(round(threshold, 2) == round(!!threshold, 2))
stopifnot(nrow(threshold_reference) == 1)

analysis_data <- oof_predictions |>
  dplyr::mutate(
    decision = dplyr::if_else(
      predicted_probability < threshold,
      "approved",
      "declined"
    ),
    predicted_target_1 = decision == "declined"
  )

stopifnot(sum(analysis_data$decision == "approved") ==
  threshold_reference$approved_count)

format_group <- function(x) {
  dplyr::if_else(is.na(x), "[Missing]", as.character(x))
}

group_status <- function(group, total_applicants) {
  unknown_or_unusual <- group %in% c("[Missing]", "Unknown", "XNA")
  dplyr::case_when(
    total_applicants < small_group_threshold & unknown_or_unusual ~
      "Small and missing/unknown/unusual group",
    total_applicants < small_group_threshold ~ "Small group",
    unknown_or_unusual ~ "Missing/unknown/unusual group",
    TRUE ~ "Standard reporting group"
  )
}

calculate_group_metrics <- function(data, demographic_variable) {
  data |>
    dplyr::transmute(
      group = format_group(.data[[demographic_variable]]),
      TARGET,
      decision,
      predicted_target_1
    ) |>
    dplyr::group_by(group) |>
    dplyr::summarise(
      total_applicants = dplyr::n(),
      approved_applicants = sum(decision == "approved"),
      declined_applicants = sum(decision == "declined"),
      approval_rate = mean(decision == "approved"),
      observed_target_1_rate = mean(TARGET == 1),
      true_positive_declines = sum(predicted_target_1 & TARGET == 1),
      false_positive_declines = sum(predicted_target_1 & TARGET == 0),
      false_negative_approvals = sum(!predicted_target_1 & TARGET == 1),
      true_negative_approvals = sum(!predicted_target_1 & TARGET == 0),
      precision_target_1 = dplyr::if_else(
        sum(predicted_target_1) > 0,
        sum(predicted_target_1 & TARGET == 1) / sum(predicted_target_1),
        NA_real_
      ),
      recall_target_1 = dplyr::if_else(
        sum(TARGET == 1) > 0,
        sum(predicted_target_1 & TARGET == 1) / sum(TARGET == 1),
        NA_real_
      ),
      false_positive_rate_decline = dplyr::if_else(
        sum(TARGET == 0) > 0,
        sum(predicted_target_1 & TARGET == 0) / sum(TARGET == 0),
        NA_real_
      ),
      false_negative_rate_approval = dplyr::if_else(
        sum(TARGET == 1) > 0,
        sum(!predicted_target_1 & TARGET == 1) / sum(TARGET == 1),
        NA_real_
      ),
      .groups = "drop"
    ) |>
    dplyr::mutate(
      demographic_variable = demographic_variable,
      group_status = group_status(group, total_applicants),
      highest_approval_rate = max(approval_rate),
      approval_rate_ratio_to_highest = approval_rate / highest_approval_rate,
      approval_rate_gap_to_highest = highest_approval_rate - approval_rate,
      passes_80_percent_heuristic = approval_rate_ratio_to_highest >= 0.80,
      heuristic_interpretation = dplyr::case_when(
        stringr::str_detect(group_status, "Small|Missing|unknown|unusual") ~
          "Flagged group: ratio is descriptive and unstable/nonstandard",
        passes_80_percent_heuristic ~ "At or above 80% of highest approval rate",
        TRUE ~ "Below 80% of highest approval rate; descriptive review flag"
      )
    ) |>
    dplyr::select(
      demographic_variable,
      group,
      group_status,
      dplyr::everything()
    ) |>
    dplyr::arrange(demographic_variable, dplyr::desc(approval_rate), group)
}

gender_metrics <- calculate_group_metrics(analysis_data, "CODE_GENDER")
education_metrics <- calculate_group_metrics(analysis_data, "NAME_EDUCATION_TYPE")
group_metrics <- dplyr::bind_rows(gender_metrics, education_metrics)

pairwise_approval_gaps <- group_metrics |>
  dplyr::select(
    demographic_variable,
    group,
    total_applicants,
    approval_rate,
    group_status
  ) |>
  dplyr::group_by(demographic_variable) |>
  dplyr::group_modify(function(data, key) {
    pairs <- utils::combn(seq_len(nrow(data)), 2)
    if (ncol(pairs) == 0) return(tibble::tibble())

    tibble::tibble(
      group_a = data$group[pairs[1, ]],
      group_b = data$group[pairs[2, ]],
      group_a_total = data$total_applicants[pairs[1, ]],
      group_b_total = data$total_applicants[pairs[2, ]],
      group_a_approval_rate = data$approval_rate[pairs[1, ]],
      group_b_approval_rate = data$approval_rate[pairs[2, ]],
      absolute_approval_rate_gap = abs(
        data$approval_rate[pairs[1, ]] - data$approval_rate[pairs[2, ]]
      ),
      group_a_status = data$group_status[pairs[1, ]],
      group_b_status = data$group_status[pairs[2, ]]
    )
  }) |>
  dplyr::ungroup()

stopifnot(sum(gender_metrics$total_applicants) == nrow(analysis_data))
stopifnot(sum(education_metrics$total_applicants) == nrow(analysis_data))
stopifnot(sum(gender_metrics$approved_applicants) == threshold_reference$approved_count)
stopifnot(sum(education_metrics$approved_applicants) == threshold_reference$approved_count)
stopifnot(sum(gender_metrics$declined_applicants) == nrow(analysis_data) - threshold_reference$approved_count)
stopifnot(sum(education_metrics$declined_applicants) == nrow(analysis_data) - threshold_reference$approved_count)

approval_plot <- group_metrics |>
  dplyr::mutate(
    group = forcats::fct_reorder(group, approval_rate)
  ) |>
  ggplot2::ggplot(ggplot2::aes(x = group, y = approval_rate, fill = group_status)) +
  ggplot2::geom_col() +
  ggplot2::geom_hline(yintercept = 0.805, linetype = "dashed", color = "grey40") +
  ggplot2::coord_flip() +
  ggplot2::facet_wrap(~ demographic_variable, scales = "free_y") +
  ggplot2::scale_fill_manual(
    values = c(
      "Standard reporting group" = "#619CFF",
      "Small group" = "#00BA38",
      "Small and missing/unknown/unusual group" = "#F8766D"
    ),
    name = "Group status"
  ) +
  ggplot2::scale_y_continuous(labels = scales::label_percent()) +
  ggplot2::labs(
    title = "Approval Rates by Reported Demographic Group",
    subtitle = "OOF predictions; approval means predicted risk < 0.12",
    x = NULL,
    y = "Approval rate"
  ) +
  ggplot2::theme_minimal(base_size = 11)

error_plot_data <- group_metrics |>
  dplyr::select(
    demographic_variable,
    group,
    false_positive_rate_decline,
    false_negative_rate_approval
  ) |>
  tidyr::pivot_longer(
    cols = c(false_positive_rate_decline, false_negative_rate_approval),
    names_to = "error_metric",
    values_to = "rate"
  ) |>
  dplyr::filter(!is.na(rate)) |>
  dplyr::mutate(
    group = forcats::fct_reorder(group, rate),
    error_metric = dplyr::recode(
      error_metric,
      false_positive_rate_decline = "Incorrectly declined (TARGET = 0)",
      false_negative_rate_approval = "Approved with payment difficulty (TARGET = 1)"
    )
  )

error_plot <- ggplot2::ggplot(
  error_plot_data,
  ggplot2::aes(x = group, y = rate, fill = error_metric)
) +
  ggplot2::geom_col(position = "dodge") +
  ggplot2::coord_flip() +
  ggplot2::facet_wrap(~ demographic_variable, scales = "free_y") +
  ggplot2::scale_y_continuous(labels = scales::label_percent()) +
  ggplot2::labs(
    title = "Error Rates by Reported Demographic Group",
    subtitle = "Decline-positive classification: predicted risk >= 0.12 means decline",
    x = NULL,
    y = "Rate",
    fill = NULL,
    caption = "Group-specific rates; undefined rates are omitted (see CSV tables)."
  ) +
  ggplot2::theme_minimal(base_size = 11)

dir.create(output_directory, recursive = TRUE, showWarnings = FALSE)
readr::write_csv(group_metrics, file.path(
  output_directory,
  "model_card_fairness_group_metrics.csv"
))
readr::write_csv(pairwise_approval_gaps, file.path(
  output_directory,
  "model_card_fairness_pairwise_approval_gaps.csv"
))
readr::write_csv(tibble::tibble(
  threshold = threshold,
  total_applicants = nrow(analysis_data),
  overall_approved = sum(analysis_data$decision == "approved"),
  overall_declined = sum(analysis_data$decision == "declined"),
  threshold_analysis_approved = threshold_reference$approved_count,
  positive_classification = "Predicted TARGET = 1 / declined (risk >= 0.12)"
), file.path(output_directory, "model_card_fairness_verification.csv"))
ggplot2::ggsave(
  file.path(output_directory, "model_card_fairness_approval_rates.png"),
  approval_plot,
  width = 10,
  height = 6,
  dpi = 180
)
ggplot2::ggsave(
  file.path(output_directory, "model_card_fairness_error_rates.png"),
  error_plot,
  width = 10,
  height = 6,
  dpi = 180
)

message("Fairness analysis completed.")
message("Positive classification: predicted TARGET = 1 / decline at risk >= 0.12")
print(gender_metrics, n = nrow(gender_metrics), width = Inf)
print(education_metrics, n = nrow(education_metrics), width = Inf)
