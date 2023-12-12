
library(tidyverse)
library(dplyr)
library(tidymodels)
library(janitor) ## clean_names()
library(ranger) ## random forest model engine


library(readr)
library(ISLR)
library(discrim)
library(poissonreg)
library(glmnet)
library(corrr)
library(corrplot)
library(tune)
library(xgboost)
library(vip)
library(ggplot2)
library(forcats)
tidymodels_prefer()
############################### HELPER FUNCTIONS ###############################
## Helper function to rename factor levels
clean <- function(mushrooms) {
  levels(mushrooms$class) <- c("edible", "poisonous")
  levels(mushrooms$cap_shape) <- c("bell", "conical", "flat", "knobbed", "sunken", "convex")
  levels(mushrooms$cap_color) <- c("buff", "cinnamon", "red", "gray", "brown", "pink", 
                                   "green", "purple", "white", "yellow")
  levels(mushrooms$cap_surface) <- c("fibrous", "grooves", "scaly", "smooth")
  levels(mushrooms$bruises) <- c("no", "yes")
  levels(mushrooms$odor) <- c("almond", "creosote", "foul", "anise", "musty", "none", "pungent", "spicy", "fishy")
  levels(mushrooms$gill_attachment) <- c("attached", "free")
  levels(mushrooms$gill_spacing) <- c("close", "crowded")
  levels(mushrooms$gill_size) <- c("broad", "narrow")
  levels(mushrooms$gill_color) <- c("buff", "red", "gray", "chocolate", "black", "brown", "orange", 
                                    "pink", "green", "purple", "white", "yellow")
  levels(mushrooms$stalk_shape) <- c("enlarging", "tapering")
  levels(mushrooms$stalk_root) <- c("missing", "bulbous", "club", "equal", "rooted")
  levels(mushrooms$stalk_surface_above_ring) <- c("fibrous", "silky", "smooth", "scaly")
  levels(mushrooms$stalk_surface_below_ring) <- c("fibrous", "silky", "smooth", "scaly")
  levels(mushrooms$stalk_color_above_ring) <- c("buff", "cinnamon", "red", "gray", "brown", "pink", 
                                                "green", "purple", "white", "yellow")
  levels(mushrooms$stalk_color_below_ring) <- c("buff", "cinnamon", "red", "gray", "brown", "pink", 
                                                "green", "purple", "white", "yellow")
  levels(mushrooms$veil_type) <- c("partial","universal")
  levels(mushrooms$veil_color) <- c("brown", "orange", "white", "yellow")
  levels(mushrooms$ring_number) <- c("none", "one", "two")
  levels(mushrooms$ring_type) <- c("evanescent", "flaring", "large", "none", "pendant")
  levels(mushrooms$spore_print_color) <- c("buff", "chocolate", "black", "brown", "orange", 
                                           "green", "purple", "white", "yellow")
  levels(mushrooms$population) <- c("abundant", "clustered", "numerous", "scattered", "several", "solitary")
  levels(mushrooms$habitat) <- c("wood", "grasses", "leaves", "meadows", "paths", "urban", "waste")
  return (mushrooms)
}
mushrooms <- clean(mushrooms)


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


