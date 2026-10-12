# Home Credit Default Risk - Data Preparation
# Author: Achuthasai Valluru
#
# Purpose:
# Prepare the Home Credit application training and test data for modeling.
# The cleaning and feature-engineering decisions in this script come from
# findings documented in the exploratory data analysis (EDA).
#
# The functions are designed to apply the same transformations to both
# training and test data to maintain consistency and reduce data leakage.


# Load packages -----------------------------------------------------------

library(tidyverse)

# Clean application data --------------------------------------------------

clean_application_data <- function(data) {

  # EDA decision:
  # DAYS_EMPLOYED uses 365243 as a special value rather than a valid
  # employment duration. Replace it with NA so it is not interpreted
  # as an actual number of days employed.
  data <- data |>
    mutate(
      DAYS_EMPLOYED = if_else(
        DAYS_EMPLOYED == 365243,
        NA_real_,
        as.numeric(DAYS_EMPLOYED)
      )
    )
  # EDA decision:
  # DAYS_BIRTH is stored as negative days. The EDA showed that the resulting
  # ages were plausible, so convert it to a more interpretable age in years.
  #
  # DAYS_EMPLOYED is also expressed in days. After removing the 365243
  # special value above, convert valid employment durations to years.
      data <- data |>
       mutate(
       AGE_YEARS = -DAYS_BIRTH / 365.25,
       EMPLOYMENT_YEARS = -DAYS_EMPLOYED / 365.25
    )

  # EDA decision:
  # CODE_GENDER contains a small number of "XNA" values and
  # NAME_FAMILY_STATUS contains "Unknown" values. These represent
  # unavailable category information rather than meaningful categories,
  # so convert them to NA for later modeling.
  data <- data |>
    mutate(
      CODE_GENDER = na_if(CODE_GENDER, "XNA"),
      NAME_FAMILY_STATUS = na_if(NAME_FAMILY_STATUS, "Unknown")
    )
  return(data)
}

# Create engineered features ---------------------------------------------

create_features <- function(data) {

  # Feature engineering decision:
  # Compare the required annuity payment with applicant income.
  # A larger value represents a larger payment burden relative to income.
  data <- data |>
    mutate(
      ANNUITY_INCOME_RATIO = AMT_ANNUITY / AMT_INCOME_TOTAL
    )
  # Feature engineering decision:
  # Compare the requested credit amount with the price of the goods.
  # This provides a measure of the amount financed relative to the
  # underlying purchase value.
  data <- data |>
    mutate(
      CREDIT_GOODS_RATIO = AMT_CREDIT / AMT_GOODS_PRICE
    )
  # EDA decision:
  # Missingness in COMMONAREA_AVG was associated with payment difficulty
  # in the EDA (8.57% when missing vs. 6.91% when not missing).
  # Preserve this information with an explicit missing-data indicator.
  data <- data |>
    mutate(
      COMMONAREA_AVG_MISSING = if_else(
        is.na(COMMONAREA_AVG),
        1L,
        0L
      )
    )

  return(data)
}

# Learn preparation parameters from training data ------------------------

learn_preparation_parameters <- function(train_data) {

  # EDA decision:
  # COMMONAREA_AVG contains substantial missingness. Its missingness is
  # preserved separately with COMMONAREA_AVG_MISSING. For the numeric
  # value itself, learn the median from training data only so information
  # from the test set cannot influence data preparation.
  commonarea_avg_median <- median(
    train_data$COMMONAREA_AVG,
    na.rm = TRUE
  )

  list(
    commonarea_avg_median = commonarea_avg_median
  )
}

# Apply training-derived parameters --------------------------------------

apply_preparation_parameters <- function(data, parameters) {

  # Training/test consistency decision:
  # Replace missing COMMONAREA_AVG values using the median learned from
  # training data only. The same stored value is applied to both train
  # and test to prevent information from the test data leaking into
  # preprocessing decisions.
  data <- data |>
    mutate(
      COMMONAREA_AVG = replace_na(
        COMMONAREA_AVG,
        parameters$commonarea_avg_median
      )
    )

  return(data)
}

# Prepare application data -----------------------------------------------

prepare_application_data <- function(data, parameters) {

  # Apply the same cleaning and feature-engineering steps to any
  # application dataset passed to this function. Training-derived
  # parameters are reused so test data does not influence preparation.
  data <- data |>
    clean_application_data() |>
    create_features() |>
    apply_preparation_parameters(parameters)

  return(data)
}

# Validate prepared data -------------------------------------------------

validate_prepared_data <- function(train_data, test_data) {

  # Validation decision:
  # Training and test data should contain identical predictor columns.
  # TARGET is expected only in the training data.
  train_only <- setdiff(
    names(train_data),
    c(names(test_data), "TARGET")
  )

  test_only <- setdiff(
    names(test_data),
    names(train_data)
  )

  # The EDA identified SK_ID_CURR as the application-level primary key.
  # Preparation should therefore preserve exactly one row per applicant.
  train_unique_id <- nrow(train_data) == n_distinct(train_data$SK_ID_CURR)
  test_unique_id <- nrow(test_data) == n_distinct(test_data$SK_ID_CURR)

  list(
    train_only_columns = train_only,
    test_only_columns = test_only,
    train_one_row_per_id = train_unique_id,
    test_one_row_per_id = test_unique_id
  )
}

# Aggregate Bureau credit history -----------------------------------------

aggregate_bureau_data <- function(bureau) {

  bureau |>
    group_by(SK_ID_CURR) |>
    summarise(
      BUREAU_LOAN_COUNT = n(),

      BUREAU_ACTIVE_COUNT = sum(
        CREDIT_ACTIVE == "Active",
        na.rm = TRUE
      ),

      BUREAU_TOTAL_DEBT = sum(
        AMT_CREDIT_SUM_DEBT,
        na.rm = TRUE
      ),

      BUREAU_MAX_OVERDUE_DAYS = if (
        all(is.na(CREDIT_DAY_OVERDUE))
      ) NA_real_ else max(
        CREDIT_DAY_OVERDUE,
        na.rm = TRUE
      ),

      .groups = "drop"
    )
}

# Aggregate previous loan applications ----------------------------

aggregate_previous_data <- function(previous) {

  previous |>
    dplyr::group_by(SK_ID_CURR) |>
    dplyr::summarise(
      PREV_APP_COUNT = dplyr::n(),

      PREV_APPROVED_COUNT = sum(
        NAME_CONTRACT_STATUS == "Approved",
        na.rm = TRUE
      ),

      PREV_REFUSED_COUNT = sum(
        NAME_CONTRACT_STATUS == "Refused",
        na.rm = TRUE
      ),

      PREV_AVG_CREDIT = {
        approved_credit <- AMT_CREDIT[
          !is.na(NAME_CONTRACT_STATUS) &
          NAME_CONTRACT_STATUS == "Approved"
        ]

        if (all(is.na(approved_credit)) ||
            length(approved_credit) == 0) {
          NA_real_
        } else {
          mean(approved_credit, na.rm = TRUE)
        }
      },

      .groups = "drop"
    )
}

# Aggregate installment payment history ------------------------

aggregate_installments_data <- function(installments) {

  installments |>
    dplyr::mutate(
      PAYMENT_DELAY = DAYS_ENTRY_PAYMENT - DAYS_INSTALMENT,

      PAYMENT_SHORTFALL = pmax(
        AMT_INSTALMENT - AMT_PAYMENT,
        0
      )
    ) |>
    dplyr::group_by(SK_ID_CURR) |>
    dplyr::summarise(
      INST_PAYMENT_COUNT = dplyr::n(),

      INST_LATE_PAYMENT_RATE = mean(
        PAYMENT_DELAY > 0,
        na.rm = TRUE
      ),

      INST_AVG_PAYMENT_DELAY = mean(
        pmax(PAYMENT_DELAY, 0),
        na.rm = TRUE
      ),

      INST_TOTAL_SHORTFALL = sum(
        PAYMENT_SHORTFALL,
        na.rm = TRUE
      ),

      .groups = "drop"
    )
}

# Aggregate POS/CASH balance history -------------------------

aggregate_pos_data <- function(pos) {

  pos |>
    dplyr::group_by(SK_ID_CURR) |>
    dplyr::summarise(
      POS_RECORD_COUNT = dplyr::n(),

      POS_AVG_DPD = mean(
        SK_DPD,
        na.rm = TRUE
      ),

      POS_MAX_DPD = max(
        SK_DPD,
        na.rm = TRUE
      ),

      POS_LATE_PAYMENT_RATE = mean(
        SK_DPD > 0,
        na.rm = TRUE
      ),

      POS_AVG_FUTURE_INSTALLMENTS = mean(
        CNT_INSTALMENT_FUTURE,
        na.rm = TRUE
      ),

      .groups = "drop"
    )
}

# Aggregate credit card balance history --------------------------

aggregate_credit_card_data <- function(credit_card) {

  credit_card |>
    dplyr::group_by(SK_ID_CURR) |>
    dplyr::summarise(

      CC_RECORD_COUNT = dplyr::n(),

      CC_AVG_BALANCE = mean(
        AMT_BALANCE,
        na.rm = TRUE
      ),

      CC_AVG_CREDIT_LIMIT = mean(
        AMT_CREDIT_LIMIT_ACTUAL,
        na.rm = TRUE
      ),

      CC_MAX_DPD = max(
        SK_DPD,
        na.rm = TRUE
      ),

      CC_LATE_PAYMENT_RATE = mean(
        SK_DPD > 0,
        na.rm = TRUE
      ),

      .groups = "drop"
    )
}