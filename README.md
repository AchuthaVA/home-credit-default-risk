# Home Credit Default Risk

## MSBA Capstone Project

This repository contains my work for the Home Credit Default Risk project in the University of Utah MSBA Capstone course.

The project focuses on using predictive analytics to identify loan applicants who may be at risk of default. Throughout the semester, this repository will document the project from business problem definition and exploratory data analysis through modeling, business recommendations, and presentation of findings.

## Data Preparation and Feature Engineering

The `data_preparation.R` script prepares the Home Credit application training and test datasets for later predictive modeling. The transformations are based on findings and decisions from the exploratory data analysis (EDA).

### What the Script Does

The script applies the following cleaning and feature-engineering steps:

- Replaces the special `DAYS_EMPLOYED` value of 365243 with missing (`NA`) because the EDA showed that it does not represent a valid employment duration.
- Converts `DAYS_BIRTH` into `AGE_YEARS` to make applicant age easier to interpret.
- Converts valid `DAYS_EMPLOYED` values into `EMPLOYMENT_YEARS`.
- Converts the `XNA` value in `CODE_GENDER` and the `Unknown` value in `NAME_FAMILY_STATUS` to missing values because the EDA identified them as unavailable category information.
- Creates `ANNUITY_INCOME_RATIO`, which compares the required annuity payment with applicant income.
- Creates `CREDIT_GOODS_RATIO`, which compares the requested credit amount with the price of the goods.
- Creates `COMMONAREA_AVG_MISSING` to preserve the missingness information identified in the EDA. The EDA found a payment-difficulty rate of 8.57% when `COMMONAREA_AVG` was missing compared with 6.91% when it was not missing.
- Imputes missing `COMMONAREA_AVG` values using the median calculated from the training data.

During the initial EDA and application-level data preparation, supplementary datasets were not incorporated. However, the predictive modeling phase expanded the analysis by aggregating and joining five additional datasets: Bureau, Previous Applications, Installment Payments, POS/CASH Balance, and Credit Card Balance. These datasets provided historical credit and repayment features that improved the model's predictive performance.

Interaction terms and binned variables were not included in the initial application-level preparation because the EDA did not identify a specific need for them.

### Train/Test Consistency

Parameters used for preprocessing are learned from the training data only. In particular, the median used to impute `COMMONAREA_AVG` is calculated from the training dataset and stored for reuse when preparing both training and test data. The training-derived median was approximately `0.0211`. This prevents information from the test dataset from influencing preprocessing decisions.

Validation checks were performed after preparation:

- Training-only predictor columns, excluding `TARGET`: `character(0)`
- Test-only predictor columns: `character(0)`
- One row per `SK_ID_CURR` in the prepared training data: `TRUE`
- One row per `SK_ID_CURR` in the prepared test data: `TRUE`

These checks confirm that the prepared training and test datasets contain identical predictor columns, except for `TARGET`, and preserve one application-level row per `SK_ID_CURR`.

### How to Run the Script

The script expects the following input files:

- `Data/application_train.csv`
- `Data/application_test.csv`

From the project directory, run the following commands in R:

```r
library(tidyverse)

source("data_preparation.R")

train_data <- read_csv("Data/application_train.csv", show_col_types = FALSE)
test_data <- read_csv("Data/application_test.csv", show_col_types = FALSE)

prep_parameters <- learn_preparation_parameters(train_data)

train_prepared <- prepare_application_data(train_data, prep_parameters)
test_prepared <- prepare_application_data(test_data, prep_parameters)

validation_results <- validate_prepared_data(
  train_prepared,
  test_prepared
)

validation_results
```

### Outputs

The preparation workflow creates two prepared data frames in R:

- `train_prepared`: 307,511 rows and 127 columns. It contains the prepared training applications and retains `TARGET` for later predictive modeling.
- `test_prepared`: 48,744 rows and 126 columns. It contains the prepared test applications and the same predictor columns as `train_prepared`, excluding `TARGET`.

The prepared datasets include the original application variables along with the engineered variables `AGE_YEARS`, `EMPLOYMENT_YEARS`, `ANNUITY_INCOME_RATIO`, `CREDIT_GOODS_RATIO`, and `COMMONAREA_AVG_MISSING`.

The script does not write prepared data files to the repository. The prepared data frames are created in R for use in later modeling steps.

## Predictive Modeling

The modeling phase evaluated multiple classification algorithms to predict whether loan applicants would experience payment difficulties.

### Models Evaluated

Three classification algorithms were compared using five-fold stratified cross-validation:

| Model | Mean ROC AUC |
|---|---:|
| Logistic Regression | 0.602 |
| Random Forest | 0.567 |
| Decision Tree | 0.505 |

Logistic Regression achieved the strongest initial performance and was selected for further development. Additional experiments with class weighting and Random Forest hyperparameter tuning did not improve upon its performance.

### Feature Engineering and Model Enhancement

The initial Logistic Regression model used six application-level predictors. The enhanced model incorporated historical financial information from five supplementary datasets:

- **Bureau:** Previous credit accounts, outstanding debt, and overdue payments.
- **Previous Applications:** Historical loan applications, approvals, and refusals.
- **Installment Payments:** Payment delays, late payment frequency, and payment shortfalls.
- **POS/CASH Balance:** Previous loan balances, overdue payments, and installment information.
- **Credit Card Balance:** Credit card balances, credit limits, and repayment behavior.

The enhanced model used 33 predictors and was trained on the full dataset of 307,511 applicants.

### Kaggle Evaluation Results

Both the initial and enhanced Logistic Regression models were evaluated using the Home Credit Default Risk Kaggle competition.

| Model | Public ROC AUC | Private ROC AUC |
|---|---:|---:|
| Initial Logistic Regression | 0.62268 | 0.60727 |
| Enhanced Logistic Regression | 0.69607 | 0.68375 |
| Improvement | +0.07339 | +0.07648 |

The results demonstrate that incorporating historical credit and repayment information improved the model's ability to distinguish between higher-risk and lower-risk applicants.

### Business Implications

Improved credit risk prediction could help lenders identify applicants who are more likely to experience payment difficulties and support more informed lending decisions.

However, the enhanced model is not ready for real-world deployment. Further evaluation of fairness, interpretability, probability calibration, and classification errors would be necessary.

### Future Improvements

Future work could explore gradient boosting models, additional feature engineering, precision-recall analysis, and more extensive cross-validation.

### Modeling Files

- `modeling.qmd` — Quarto source notebook containing the modeling workflow, experiments, and results.
- `modeling.html` — Rendered modeling report.
- `data_preparation.R` — Reusable application preparation and supplementary feature aggregation functions.

The raw datasets and Kaggle submission files are excluded from the repository using `.gitignore`.