
library(tidyverse)
library(dplyr)
library(tidymodels)
library(janitor) ## clean_names()
library(ranger) ## random forest model engine


############################## DATA PREPROCESSING ##############################

# loading the data
hotel <- read.csv("data/HotelReservations.csv")

# cleaning predictor names
hotel <- clean_names(hotel)

# summarize data
summary(hotel) # Categorical variables are stored in "character" variables

# Convert characters to factors and rename factor levels
hotel<- data.frame(lapply(hotel, factor))
summary(hotel)

# Train/val/test split
set.seed(1234)
hotel_split <- initial_split(hotel, prop = 0.7, strata = booking_status)
hotel_train <- training(hotel_split)
hotel_test <- testing(hotel_split)

# Create a recipe for the dataset
hotel_recipe <- 
  recipe(booking_status ~., data = hotel_train) %>% 
  step_other(all_predictors(), threshold = 0.05) %>% ## factor levels with an occurring frequency less than 0.05 would be pooled to "other"
  step_dummy(all_nominal_predictors()) ## factors will be encoded to multiple binary variables corresponding to each level

# 10-fold Cross validation
hotel_folds <- vfold_cv(hotel_train, v = 10, strata = booking_status)




################################ DECISION TREE #################################

# Define the model (Decision Tree)
dt_model<-decision_tree() %>% 
  set_mode("classification") %>% ## type of tasks
  set_engine("rpart") %>% ## type of engine used to fit the model
  set_args(tree_depth(c(1L, 15L))) ## Other parameters

# combine the model and the dataset to a workflow
dt_wf <- workflow() %>%
  add_recipe(hotel_recipe) %>%
  add_model(dt_model)

# fit the model
hotel_results_dt <- fit_resamples(
  dt_wf,
  resamples = hotel_folds, ## cross-validation
  metrics = metric_set(roc_auc, accuracy, sensitivity, specificity) ## metrics to keep track on
)

# summarize the result
results_summary_dt <- hotel_results_dt %>%
  collect_metrics() %>%
  select(c(".metric", "mean"))
results_summary_dt



################################# RANDOM FOREST ################################
# Define the model (Random Forest)
rf_model <- rand_forest(mtry = 15, ## number of random sampled predictors used for each split
                        trees = 20, ## number of trees
                        min_n = 10) %>% ## minimum number of data points needed in a node to split
  set_mode("classification") %>% ## type of tasks
  set_engine("ranger") ## type of engine used to fit the model

# combine the model and the dataset to a workflow
rf_wf <- workflow() %>% 
  add_model(rf_model) %>% 
  add_recipe(hotel_recipe)

# fit the model
hotel_results_rf <- fit_resamples(
  rf_wf,
  resamples = hotel_folds, ## cross-validation
  metrics = metric_set(roc_auc, accuracy, sensitivity, specificity) ## metrics to keep track on
)

# summarize the result
results_summary_rf <- hotel_results_rf %>%
  collect_metrics() %>%
  select(c(".metric", "mean"))
results_summary_rf



############################### HYPER-PARAMETERS ###############################
# Define the model (Random Forest)
rf_model_tune <- rand_forest(mtry = tune(), ## number of random sampled predictors used for each split
                             trees = tune(), ## number of trees
                             min_n = tune()) %>% ## minimum number of data points needed in a node to split
  set_mode("classification") %>% ## type of tasks
  set_engine("ranger") ## type of engine used to fit the model

rf_grid <- grid_regular(
  mtry(c(2, 18)),
  trees(c(10, 200)),
  min_n(c(10, 50)),
  levels = 3
)

# combine the model and the dataset to a workflow
rf_wf_tune <- workflow() %>% 
  add_model(rf_model_tune) %>% 
  add_recipe(hotel_recipe)

hotel_results_rf_tune <- tune_grid(
  rf_wf_tune,
  resamples = hotel_folds,
  grid = rf_grid)

show_best(hotel_results_rf_tune, metric = "roc_auc")


