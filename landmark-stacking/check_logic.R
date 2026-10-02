# Checks the R-side scoring and time boundary without requiring CmdStan.
source(file.path(dirname(normalizePath(sub(
  "^--file=", "", grep("^--file=", commandArgs(FALSE),
                      value = TRUE)[1L]))), "simulation.R"))

expect_error <- function(expr, text) {
  message <- tryCatch({ force(expr); NULL },
                      error = function(e) conditionMessage(e))
  if (is.null(message) || !grepl(text, message, fixed = TRUE)) {
    stop("Expected an error containing: ", text)
  }
}

data <- simulate_patients(12L, 37L)
validate_study_data(data)
stopifnot(length(unique(data$id)) == 12L)
stopifnot(all(table(data$id) == 7L))
stopifnot(sum(data[data$id == 1L, "visit"] <= 3L) == 4L)
duplicated_visit <- rbind(data, data[1L, ])
expect_error(validate_study_data(duplicated_visit), "exactly one visit")
wrong_time <- data
wrong_time$time[1L] <- 0
expect_error(validate_study_data(wrong_time), "time = (visit - 3) / 3")

patient <- data[data$id == 1L, , drop = FALSE]
draws <- matrix(c(1, 0.3, 0.4, 0.2, 0, 0, 0.35), nrow = 1L)
colnames(draws) <- c(paste0("beta[", 1:4, "]"),
                     "sd_intercept", "sd_slope", "sd_error")
pred <- predict_patient(patient, draws, "linear")
expected <- drop(design_matrix(patient[patient$visit > 3L, ],
                               "linear") %*% draws[1L, 1:4])
stopifnot(isTRUE(all.equal(pred$pred_mean, expected)))
stopifnot(isTRUE(all.equal(pred$log_pred,
                           dnorm(pred$y, expected, 0.35, log = TRUE))))
component_independent <- patient_components(patient, draws, "linear",
                                            include_full = TRUE)
all_mean <- drop(design_matrix(patient, "linear") %*% draws[1L, 1:4])
stopifnot(isTRUE(all.equal(component_independent$log_full,
                           sum(dnorm(patient$y, all_mean, 0.35,
                                     log = TRUE)))))
invalid_draws <- draws
invalid_draws[1L, "sd_error"] <- NA_real_
expect_error(predict_patient(patient, invalid_draws, "linear"),
             "Posterior draws must be finite")
expect_error(thin_draws(draws, 0L), "max_draws must be positive")

draws[1L, "sd_intercept"] <- 0.5
draws[1L, "sd_slope"] <- 0.25
original <- predict_patient(patient, draws, "linear")
changed_future <- patient
changed_future$y[changed_future$visit == 4L] <- 100
future_result <- predict_patient(changed_future, draws, "linear")
stopifnot(isTRUE(all.equal(original$pred_mean,
                           future_result$pred_mean)))
stopifnot(isTRUE(all.equal(original$log_pred[2:3],
                           future_result$log_pred[2:3])))
changed_history <- patient
changed_history$y[changed_history$visit == 3L] <-
  changed_history$y[changed_history$visit == 3L] + 2
history_result <- predict_patient(changed_history, draws, "linear")
stopifnot(any(abs(original$pred_mean - history_result$pred_mean) > 0.01))

# Without Pareto smoothing, (4) and (5) are the same conditional ratio.
draws_two <- rbind(draws, draws)
draws_two[2L, "beta[1]"] <- draws_two[2L, "beta[1]"] + 0.4
component <- patient_components(patient, draws_two, "linear",
                                include_full = TRUE)
log_h <- component$log_history
log_all <- component$log_full
log_cond <- component$conditional_log_density[, 1L]
raw4 <- -log_all - log_sum_exp(-log_all)
raw5 <- log_h - log_all - log_sum_exp(log_h - log_all)
score4 <- log_sum_exp(raw4 + log_h + log_cond) -
  log_sum_exp(raw4 + log_h)
score5 <- log_sum_exp(raw5 + log_cond)
stopifnot(isTRUE(all.equal(score4, score5, tolerance = 1e-12)))

stopifnot(isTRUE(all.equal(log_mix_two(-2, -1, 0), -2)))
stopifnot(isTRUE(all.equal(log_mix_two(-2, -1, 1), -1)))
cat("R scoring and landmark checks passed.\n")
