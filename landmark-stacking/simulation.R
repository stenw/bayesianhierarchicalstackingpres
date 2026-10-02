# Landmark prediction simulation: exact and PSIS patient-level stacking scores.
# Input: no external data; see config in main().
# Output: CSV summaries and patient-level predictions under output/.

study_dir <- local({
  file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  if (length(file_arg) > 0L) {
    dirname(normalizePath(sub("^--file=", "", file_arg[1L])))
  } else {
    normalizePath(getwd())
  }
})

log_sum_exp <- function(x) {
  m <- max(x)
  m + log(sum(exp(x - m)))
}

simulate_patients <- function(n_subject, seed) {
  stopifnot(n_subject >= 8L)
  set.seed(seed)
  baseline <- sample(rep(0:1, length.out = n_subject))
  b0 <- rnorm(n_subject, 0, 0.5)
  b1 <- rnorm(n_subject, 0, 0.25)
  out <- lapply(seq_len(n_subject), function(i) {
    visit <- 0:6
    time <- (visit - 3) / 3
    x <- baseline[i]
    mean_y <- 1 + 0.35 * x + 0.45 * time + 0.75 * x * time +
      1.35 * x * pmax(time, 0)^2 + b0[i] + b1[i] * time
    data.frame(id = i, x = x, visit = visit, time = time,
               y = rnorm(length(visit), mean_y, 0.35))
  })
  do.call(rbind, out)
}

design_matrix <- function(data, candidate) {
  stopifnot(candidate %in% c("linear", "curved"))
  x <- data$x
  t <- data$time
  ans <- cbind(intercept = 1, x = x, time = t)
  if (candidate == "linear") {
    ans <- cbind(ans, x_time = x * t)
  } else {
    ans <- cbind(ans, x_after_landmark2 = x * pmax(t, 0)^2)
  }
  unname(ans)
}

# The pilot assumes one complete trajectory on visits 0:6 per patient.
# Fail early if an edited generator or imported data violates that design.
validate_study_data <- function(data) {
  required <- c("id", "x", "visit", "time", "y")
  missing <- setdiff(required, names(data))
  if (length(missing) > 0L) {
    stop("Patient data are missing columns: ", paste(missing, collapse = ", "))
  }
  if (nrow(data) == 0L || anyNA(data[required]) ||
      !all(vapply(data[c("x", "visit", "time", "y")], is.numeric,
                  logical(1))) ||
      any(!is.finite(as.matrix(data[c("x", "visit", "time", "y")])))) {
    stop("Patient data must have nonempty, finite numeric measurements.")
  }
  if (!all(data$x %in% 0:1) ||
      any(abs(data$time - (data$visit - 3) / 3) > 1e-10)) {
    stop("The pilot requires binary x and time = (visit - 3) / 3.")
  }
  patients <- split(data, data$id)
  complete <- vapply(patients, function(d) {
    nrow(d) == 7L && all(sort(d$visit) == 0:6) &&
      length(unique(d$x)) == 1L
  }, logical(1))
  if (!all(complete)) {
    stop("Each patient must have exactly one visit 0:6 and one baseline x.")
  }
  invisible(TRUE)
}

stan_data <- function(data, candidate) {
  ids <- unique(data$id)
  x <- design_matrix(data, candidate)
  list(N = nrow(data), J = length(ids), P = ncol(x), X = x,
       time = data$time, subject = match(data$id, ids), y = data$y)
}

fit_base <- function(model, data, candidate, seed, config,
                     final_fit = FALSE, all_draws = FALSE) {
  chains <- if (final_fit) config$chains_final else config$chains_cv
  warmup <- if (final_fit) config$warmup_final else config$warmup_cv
  samples <- if (final_fit) config$samples_final else config$samples_cv
  fit <- model$sample(
    data = stan_data(data, candidate), seed = seed,
    chains = chains, parallel_chains = chains,
    iter_warmup = warmup, iter_sampling = samples,
    refresh = 0
  )
  draws_df <- as.data.frame(fit$draws(
    variables = c("beta", "sd_intercept", "sd_slope", "sd_error"),
    format = "df"
  ))
  chain_id <- draws_df$.chain
  draws <- as.matrix(draws_df[, !names(draws_df) %in%
                                c(".chain", ".iteration", ".draw"),
                              drop = FALSE])
  if (all_draws) {
    # PSIS needs every full-fit draw and its chain ID for relative ESS.
    attr(draws, "chain_id") <- chain_id
    return(draws)
  }
  thin_draws(draws, config$max_draws)
}

thin_draws <- function(draws, max_draws) {
  if (!is.matrix(draws) || nrow(draws) == 0L ||
      length(max_draws) != 1L || !is.finite(max_draws) ||
      max_draws < 1L) {
    stop("Draws must be a nonempty matrix and max_draws must be positive.")
  }
  keep <- unique(round(seq(1, nrow(draws),
                           length.out = min(nrow(draws), max_draws))))
  draws[keep, , drop = FALSE]
}

#' Per-draw marginal history/full densities and conditional future densities.
#' Patient random effects are integrated out before computing either PSIS
#' ratio. Each future visit is conditioned on visits through the landmark only.
patient_components <- function(patient, draws, candidate, landmark = 3L,
                               include_full = FALSE) {
  validate_study_data(patient)
  if (length(unique(patient$id)) != 1L) {
    stop("patient_components() requires exactly one patient.")
  }
  history <- patient[patient$visit <= landmark, , drop = FALSE]
  future <- patient[patient$visit > landmark, , drop = FALSE]
  if (nrow(history) == 0L || nrow(future) == 0L) {
    stop("Each patient needs landmark history and future observations.")
  }
  x_h <- design_matrix(history, candidate)
  x_f <- design_matrix(future, candidate)
  if (include_full) {
    x_all <- design_matrix(patient, candidate)
    time_all <- patient$time
  }
  p <- ncol(x_h)
  beta_names <- paste0("beta[", seq_len(p), "]")
  needed <- c(beta_names, "sd_intercept", "sd_slope", "sd_error")
  if (!all(needed %in% colnames(draws))) {
    stop("Base-model posterior draws are missing required columns.")
  }
  if (!is.matrix(draws) || nrow(draws) == 0L ||
      !is.numeric(draws) || any(!is.finite(draws[, needed, drop = FALSE])) ||
      any(draws[, c("sd_intercept", "sd_slope", "sd_error"),
                drop = FALSE] < 0) ||
      any(draws[, "sd_error"] <= 0)) {
    stop("Posterior draws must be finite with valid nonnegative scales.")
  }
  s <- nrow(draws)
  m <- nrow(future)
  log_history <- numeric(s)
  log_full <- if (include_full) numeric(s) else NULL
  conditional_mean <- matrix(NA_real_, s, m)
  conditional_log_density <- matrix(NA_real_, s, m)
  time_h <- history$time
  time_f <- future$time
  for (d in seq_len(s)) {
    beta <- as.numeric(draws[d, beta_names])
    v0 <- as.numeric(draws[d, "sd_intercept"])^2
    v1 <- as.numeric(draws[d, "sd_slope"])^2
    ve <- as.numeric(draws[d, "sd_error"])^2
    mean_h <- drop(x_h %*% beta)
    mean_f <- drop(x_f %*% beta)
    covariance_h <- v0 + v1 * outer(time_h, time_h)
    diag(covariance_h) <- diag(covariance_h) + ve
    ch <- chol(covariance_h)
    residual <- history$y - mean_h
    solve_cov <- function(z) {
      backsolve(ch, forwardsolve(t(ch), z))
    }
    inv_residual <- solve_cov(residual)
    log_history[d] <- -0.5 * (
      length(residual) * log(2 * pi) +
        2 * sum(log(diag(ch))) + sum(residual * inv_residual)
    )
    if (include_full) {
      mean_all <- drop(x_all %*% beta)
      covariance_all <- v0 + v1 * outer(time_all, time_all)
      diag(covariance_all) <- diag(covariance_all) + ve
      ca <- chol(covariance_all)
      residual_all <- patient$y - mean_all
      inv_all <- backsolve(ca, forwardsolve(t(ca), residual_all))
      log_full[d] <- -0.5 * (
        length(residual_all) * log(2 * pi) +
          2 * sum(log(diag(ca))) + sum(residual_all * inv_all)
      )
    }
    cross_cov <- v0 + v1 * outer(time_f, time_h)
    conditional_mean[d, ] <- mean_f + drop(cross_cov %*% inv_residual)
    reduction <- rowSums(cross_cov * t(solve_cov(t(cross_cov))))
    conditional_sd <- sqrt(pmax(v0 + v1 * time_f^2 + ve - reduction,
                                 1e-12))
    conditional_log_density[d, ] <- dnorm(
      future$y, conditional_mean[d, ], conditional_sd, log = TRUE
    )
  }
  list(future = future, log_history = log_history,
       log_full = log_full, conditional_mean = conditional_mean,
       conditional_log_density = conditional_log_density)
}

#' Predict post-landmark visits using only this patient's landmark history.
predict_patient <- function(patient, draws, candidate, landmark = 3L) {
  component <- patient_components(patient, draws, candidate, landmark)
  future <- component$future
  log_history <- component$log_history
  conditional_mean <- component$conditional_mean
  conditional_log_density <- component$conditional_log_density
  m <- nrow(future)
  normalizer <- log_sum_exp(log_history)
  history_weight <- exp(log_history - normalizer)
  log_pred <- vapply(seq_len(m), function(j) {
    log_sum_exp(log_history + conditional_log_density[, j]) -
      normalizer
  }, numeric(1))
  pred_mean <- drop(crossprod(history_weight, conditional_mean))
  data.frame(id = future$id, x = future$x, visit = future$visit,
             y = future$y, log_pred = log_pred, pred_mean = pred_mean)
}

#' Compare the two patient-level PSIS constructions using one full-data fit.
#' Equation (4) weights draws by 1 / m_i(all), then updates by m_i(history).
#' Equation (5) directly weights by m_i(history) / m_i(all). Both remove all
#' future visits, even when scoring only one horizon; PSIS smooths the two
#' ratios separately, so their finite-draw scores can differ.
psis_patient <- function(patient, draws, candidate, replicate,
                         landmark = 3L) {
  component <- patient_components(patient, draws, candidate, landmark,
                                  include_full = TRUE)
  log_h <- component$log_history
  log_all <- component$log_full
  log_cond <- component$conditional_log_density
  if (any(!is.finite(c(log_h, log_all, log_cond)))) {
    stop("Non-finite marginal likelihood or conditional predictive density.")
  }
  chain_id <- attr(draws, "chain_id")
  if (is.null(chain_id) || length(chain_id) != length(log_h)) {
    stop("Full posterior draws need matching MCMC chain identifiers.")
  }
  r_eff_4 <- loo::relative_eff(exp(log_all - max(log_all)),
                                chain_id = chain_id)
  r_eff_5 <- loo::relative_eff(
    exp(log_all - log_h - max(log_all - log_h)),
    chain_id = chain_id
  )
  if (any(!is.finite(c(r_eff_4, r_eff_5))) ||
      any(c(r_eff_4, r_eff_5) <= 0)) {
    stop("PSIS relative effective sample sizes must be finite and positive.")
  }
  ps4 <- loo::psis(-log_all, r_eff = r_eff_4)
  ps5 <- loo::psis(log_h - log_all, r_eff = r_eff_5)
  lw4 <- weights(ps4)
  lw5 <- weights(ps5)
  score4 <- vapply(seq_len(ncol(log_cond)), function(j) {
    log_sum_exp(lw4 + log_h + log_cond[, j]) -
      log_sum_exp(lw4 + log_h)
  }, numeric(1))
  score5 <- vapply(seq_len(ncol(log_cond)), function(j) {
    log_sum_exp(lw5 + log_cond[, j])
  }, numeric(1))
  if (any(!is.finite(c(lw4, lw5, score4, score5)))) {
    stop("Non-finite PSIS weight or predictive score.")
  }
  scores <- data.frame(
    replicate = replicate, id = component$future$id,
    x = component$future$x, visit = component$future$visit,
    candidate = candidate, log_score_4 = score4,
    log_score_5 = score5
  )
  diagnostics <- data.frame(
    replicate = replicate, id = unique(patient$id), candidate = candidate,
    draws = length(log_h), pareto_k_4 = loo::pareto_k_values(ps4),
    pareto_k_5 = loo::pareto_k_values(ps5),
    ess_4 = loo::psis_n_eff_values(ps4),
    ess_5 = loo::psis_n_eff_values(ps5),
    r_eff_4 = r_eff_4, r_eff_5 = r_eff_5
  )
  list(scores = scores, diagnostics = diagnostics)
}

psis_scores <- function(training, linear_draws, curved_draws, replicate) {
  patients <- split(training, training$id)
  result <- lapply(patients, function(patient) {
    list(psis_patient(patient, linear_draws, "linear", replicate),
         psis_patient(patient, curved_draws, "curved", replicate))
  })
  entries <- unlist(result, recursive = FALSE)
  list(
    scores = do.call(rbind, lapply(entries, `[[`, "scores")),
    diagnostics = do.call(rbind, lapply(entries, `[[`, "diagnostics"))
  )
}

predict_cohort <- function(data, draws, candidate) {
  patients <- split(data, data$id)
  do.call(rbind, lapply(patients, predict_patient,
                        draws = draws, candidate = candidate))
}

join_candidates <- function(linear, curved) {
  stopifnot(identical(linear[, c("id", "visit")],
                      curved[, c("id", "visit")]))
  data.frame(
    id = linear$id, x = linear$x, visit = linear$visit, y = linear$y,
    log_linear = linear$log_pred, log_curved = curved$log_pred,
    mean_linear = linear$pred_mean, mean_curved = curved$pred_mean
  )
}

loo_scores <- function(training, model, config, seed) {
  # Exact reference: refit without the entire held-out patient, then reveal
  # that patient's history for each conditional future prediction.
  ids <- unique(training$id)
  rows <- vector("list", length(ids))
  for (i in seq_along(ids)) {
    id <- ids[i]
    message("  held-out patient ", i, "/", length(ids))
    other <- training[training$id != id, , drop = FALSE]
    held_out <- training[training$id == id, , drop = FALSE]
    linear_draws <- fit_base(model, other, "linear",
                             seed + 10L * i, config)
    curved_draws <- fit_base(model, other, "curved",
                             seed + 10L * i + 1L, config)
    rows[[i]] <- join_candidates(
      predict_patient(held_out, linear_draws, "linear"),
      predict_patient(held_out, curved_draws, "curved")
    )
  }
  do.call(rbind, rows)
}

weight_features <- function(data, dynamic) {
  horizon <- (data$visit - 3) / 3
  if (dynamic) {
    cbind(1, horizon, data$x, horizon * data$x)
  } else {
    matrix(1, nrow(data), 1L)
  }
}

fit_stacking <- function(model, loo, dynamic, seed, config) {
  if (nrow(loo) == 0L ||
      any(!is.finite(as.matrix(loo[, c("log_linear", "log_curved")])))) {
    stop("Stacking requires finite candidate log predictive densities.")
  }
  features <- weight_features(loo, dynamic)
  # Three future horizons per patient, each carrying one-third of that
  # patient's total contribution to the composite stacking objective.
  future_per_patient <- as.numeric(table(loo$id)[as.character(loo$id)])
  fit <- model$sample(
    data = list(
      N = nrow(loo), P = ncol(features), feature = features,
      log_pred = unname(as.matrix(loo[, c("log_linear", "log_curved")])),
      case_weight = 1 / future_per_patient
    ),
    seed = seed, chains = config$chains_final,
    parallel_chains = config$chains_final,
    iter_warmup = config$warmup_final,
    iter_sampling = config$samples_final, refresh = 0
  )
  coef <- as.matrix(fit$draws(variables = "coef", format = "matrix"))
  list(coef = coef, summary = fit$summary(variables = "coef"))
}

mean_curved_weight <- function(data, fit, dynamic) {
  features <- weight_features(data, dynamic)
  coef_names <- paste0("coef[", seq_len(ncol(features)), "]")
  eta <- features %*% t(fit$coef[, coef_names, drop = FALSE])
  rowMeans(plogis(eta))
}

log_mix_two <- function(log_a, log_b, weight_b) {
  m <- pmax(log_a, log_b)
  m + log((1 - weight_b) * exp(log_a - m) +
            weight_b * exp(log_b - m))
}

evaluate_methods <- function(scores, fits, replicate) {
  weights <- list(linear = rep(0, nrow(scores)),
                  curved = rep(1, nrow(scores)),
                  equal = rep(0.5, nrow(scores)),
                  constant = mean_curved_weight(scores, fits$constant, FALSE),
                  dynamic = mean_curved_weight(scores, fits$dynamic, TRUE),
                  constant_psis4 = mean_curved_weight(
                    scores, fits$constant_psis4, FALSE),
                  dynamic_psis4 = mean_curved_weight(
                    scores, fits$dynamic_psis4, TRUE),
                  constant_psis5 = mean_curved_weight(
                    scores, fits$constant_psis5, FALSE),
                  dynamic_psis5 = mean_curved_weight(
                    scores, fits$dynamic_psis5, TRUE))
  do.call(rbind, lapply(names(weights), function(method) {
    w <- weights[[method]]
    predicted <- (1 - w) * scores$mean_linear +
      w * scores$mean_curved
    data.frame(
      replicate = replicate, id = scores$id, x = scores$x,
      visit = scores$visit, method = method, observed = scores$y,
      predicted = predicted, weight_curved = w,
      log_score = log_mix_two(scores$log_linear, scores$log_curved, w),
      squared_error = (scores$y - predicted)^2
    )
  }))
}

summarize_predictions <- function(predictions, group_columns) {
  groups <- interaction(predictions[group_columns], drop = TRUE)
  parts <- split(predictions, groups)
  do.call(rbind, lapply(parts, function(d) {
    cbind(d[1L, group_columns, drop = FALSE],
          n_patients = length(unique(paste(d$replicate, d$id))),
          n_predictions = nrow(d),
          mean_log_score = mean(d$log_score),
          rmse = sqrt(mean(d$squared_error)), row.names = NULL)
  }))
}

run_replicate <- function(replicate, model_base, model_stack, config) {
  message("Simulation replicate ", replicate, "/", config$replications)
  data <- simulate_patients(config$n_train + config$n_test,
                            config$seed + 10000L * replicate)
  validate_study_data(data)
  train_ids <- seq_len(config$n_train)
  train <- data[data$id %in% train_ids, , drop = FALSE]
  test <- data[!data$id %in% train_ids, , drop = FALSE]
  seed <- config$seed + 1000L * replicate
  loo <- loo_scores(train, model_base, config, seed)
  linear <- fit_base(model_base, train, "linear", seed + 200L,
                     config, final_fit = TRUE, all_draws = TRUE)
  curved <- fit_base(model_base, train, "curved", seed + 201L,
                     config, final_fit = TRUE, all_draws = TRUE)
  psis <- psis_scores(train, linear, curved, replicate)
  score_key <- paste(loo$id, loo$visit)
  psis_wide <- data.frame(replicate = replicate, id = loo$id,
                          x = loo$x, visit = loo$visit)
  for (candidate in c("linear", "curved")) {
    candidate_scores <- psis$scores[
      psis$scores$candidate == candidate, , drop = FALSE]
    index <- match(score_key, paste(candidate_scores$id,
                                    candidate_scores$visit))
    stopifnot(!anyNA(index))
    for (version in c("4", "5")) {
      psis_wide[[paste0("log_", candidate, "_", version)]] <-
        candidate_scores[[paste0("log_score_", version)]][index]
    }
  }
  psis_wide$exact_linear <- loo$log_linear
  psis_wide$exact_curved <- loo$log_curved
  psis_scores_for <- function(version) {
    score_data <- loo
    score_data$log_linear <- psis_wide[[paste0("log_linear_", version)]]
    score_data$log_curved <- psis_wide[[paste0("log_curved_", version)]]
    score_data
  }
  fits <- list(
    constant = fit_stacking(model_stack, loo, FALSE, seed + 100L,
                            config),
    dynamic = fit_stacking(model_stack, loo, TRUE, seed + 101L,
                           config),
    constant_psis4 = fit_stacking(model_stack, psis_scores_for("4"),
                                  FALSE, seed + 102L, config),
    dynamic_psis4 = fit_stacking(model_stack, psis_scores_for("4"),
                                 TRUE, seed + 103L, config),
    constant_psis5 = fit_stacking(model_stack, psis_scores_for("5"),
                                  FALSE, seed + 104L, config),
    dynamic_psis5 = fit_stacking(model_stack, psis_scores_for("5"),
                                 TRUE, seed + 105L, config)
  )
  test_scores <- join_candidates(
    predict_cohort(test, thin_draws(linear, config$max_draws), "linear"),
    predict_cohort(test, thin_draws(curved, config$max_draws), "curved")
  )
  weight_grid <- data.frame(x = rep(0:1, each = 3), visit = rep(4:6, 2))
  weight_rows <- do.call(rbind, lapply(c("dynamic", "dynamic_psis4",
                                         "dynamic_psis5"), function(method) {
    data.frame(replicate = replicate, method = method,
               x = weight_grid$x, visit = weight_grid$visit,
               weight_curved = mean_curved_weight(weight_grid,
                                                   fits[[method]], TRUE))
  }))
  list(
    predictions = evaluate_methods(test_scores, fits, replicate),
    weights = weight_rows,
    psis_scores = psis_wide,
    psis_diagnostics = psis$diagnostics,
    stacking_summaries = lapply(fits, `[[`, "summary")
  )
}

main <- function() {
  local_library <- file.path(study_dir, ".Rlib")
  if (dir.exists(local_library)) {
    .libPaths(c(local_library, .libPaths()))
  }
  if (!requireNamespace("cmdstanr", quietly = TRUE) ||
      !requireNamespace("loo", quietly = TRUE)) {
    stop("Install cmdstanr, CmdStan, and loo; see README.md.")
  }
  cmdstanr::cmdstan_version()
  config <- list(
    replications = 2L, n_train = 18L, n_test = 60L,
    seed = 20260930L, chains_cv = 1L, warmup_cv = 250L,
    samples_cv = 250L, chains_final = 4L,
    warmup_final = 500L, samples_final = 500L,
    max_draws = 200L
  )
  if ("--quick" %in% commandArgs(TRUE)) {
    config$replications <- 1L
    config$n_train <- 10L
    config$n_test <- 24L
    config$warmup_cv <- 100L
    config$samples_cv <- 100L
    config$warmup_final <- 200L
    config$samples_final <- 200L
    config$max_draws <- 100L
  }
  output_dir <- file.path(study_dir, "output")
  dir.create(output_dir, showWarnings = FALSE)
  model_base <- cmdstanr::cmdstan_model(
    file.path(study_dir, "base_model.stan"))
  model_stack <- cmdstanr::cmdstan_model(
    file.path(study_dir, "stacking_weights.stan"))
  runs <- lapply(seq_len(config$replications), run_replicate,
                 model_base = model_base, model_stack = model_stack,
                 config = config)
  predictions <- do.call(rbind, lapply(runs, `[[`, "predictions"))
  weights <- do.call(rbind, lapply(runs, `[[`, "weights"))
  psis_scores_out <- do.call(rbind, lapply(runs, `[[`, "psis_scores"))
  psis_diagnostics <- do.call(rbind, lapply(runs, `[[`, "psis_diagnostics"))
  write.csv(predictions, file.path(output_dir, "predictions.csv"),
            row.names = FALSE)
  write.csv(summarize_predictions(predictions, "method"),
            file.path(output_dir, "overall.csv"), row.names = FALSE)
  write.csv(summarize_predictions(predictions,
                                  c("replicate", "method")),
            file.path(output_dir, "by_replicate.csv"),
            row.names = FALSE)
  write.csv(summarize_predictions(predictions,
                                  c("x", "visit", "method")),
            file.path(output_dir, "by_group_horizon.csv"),
            row.names = FALSE)
  write.csv(weights, file.path(output_dir, "weights.csv"),
            row.names = FALSE)
  write.csv(psis_scores_out, file.path(output_dir, "psis_scores.csv"),
            row.names = FALSE)
  write.csv(psis_diagnostics,
            file.path(output_dir, "psis_diagnostics.csv"), row.names = FALSE)
  saveRDS(list(config = config, stacking_summaries =
                 lapply(runs, `[[`, "stacking_summaries")),
          file.path(output_dir, "run_info.rds"))
  print(read.csv(file.path(output_dir, "overall.csv")))
  message("Saved simulation results in ", output_dir)
}

if (sys.nframe() == 0L) {
  main()
}
