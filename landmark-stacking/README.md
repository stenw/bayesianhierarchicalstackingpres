# Landmark prediction with subject-level stacking

This is a small, synthetic R and Stan simulation inspired by Yao et al. (2022),
*Bayesian Hierarchical Stacking: Some Models Are (Somewhere) Useful*. The design
combines the paper's input-dependent weights, its forward-looking treatment of
longitudinal data (§2.5), and the leave-one-cell-out idea for predicting new
clusters (§6.1). Here a **cell is a patient**. It is an extension of those ideas,
not a result or a direct reproduction of the paper.

## Question and estimand

We fit candidate models to complete trajectories from training patients. For a
different patient, we observe visits 0–3 (the landmark is visit 3) and predict
the biomarker separately at visits 4, 5, and 6. The target at each horizon is
the **conditional predictive density**

`p(y_new,t | y_new,0:3, baseline_new, training patients)`.

The history is available at prediction time. Outcomes after visit 3 are never
used to predict any of the three horizons. A held-out patient's entire record is
excluded from base-model fitting when constructing stacking scores.

## Simulation

- A continuous marker is observed at seven equally spaced visits.
- Each patient has a binary baseline covariate and random intercept and slope.
- Baseline group 1 bends upward after the landmark; group 0 stays linear.
- Candidate `linear` is a Gaussian random-intercept/slope model with a linear
  baseline-by-time interaction but no bend. Candidate `curved` has a
  baseline-specific quadratic term after the landmark but omits the linear
  baseline-by-time interaction. Thus neither candidate exactly matches the
  simulated trajectory. Both are fit in Stan.
- The stacking model in Stan gives `curved` a logistic weight. The constant
  version has one intercept. The dynamic version uses horizon, baseline group,
  and their interaction with shrinkage on the extra coefficients. The two-model
  logistic weight is the paper's softmax construction in this special case.

The candidate models' subject effects are **integrated out** when scoring a new
patient. For each population posterior draw, Gaussian conditioning uses the
history to update that patient's random intercept and slope. The population
draws are then weighted by their likelihood for the history, so the result is
the ratio of the joint and history posterior predictive densities. This also
allows the new history to inform uncertainty in population parameters.

## Validation protocol

1. For each training patient, refit both candidates to all *other* training
   patients. Score that patient's future values using only their visits 0–3.
   This is exact leave-one-subject-out refitting, rather than row-wise LOO.
2. Fit each candidate to all training patients once more. For every patient,
   integrate out their random effects and calculate patient-level PSIS ratios
   using both equations (4) and (5) in the Quarto report. Compare their
   conditional future log scores and Pareto diagnostics with the exact refits.
3. Fit constant and dynamic stacking weights separately to the exact, PSIS (4),
   and PSIS (5) out-of-subject scores. Each of the three horizons receives
   weight 1/3, so each patient contributes one unit to the stacking objective.
   This is a weighted composite log score because horizons within a patient
   are dependent.
4. Apply the weights to an
   untouched test cohort. Compare each candidate, equal weights, constant
   stacking, and dynamic stacking by mean log predictive density and RMSE.
   Results are also broken down by replicate, baseline group, and horizon.

All mixtures combine **predictive densities**, not just point predictions. The
weighted predictive means are used only for RMSE. Mean log predictive density
is the primary proper-score comparison. The synthetic test cohort is never used
to fit candidate models or stacking weights.

## Run

Install R, [CmdStan](https://mc-stan.org/users/interfaces/cmdstan),
[CmdStanR](https://mc-stan.org/cmdstanr/), and
[`loo`](https://mc-stan.org/loo/). In R, for example:

```r
install.packages("cmdstanr", repos = c(
  "https://stan-dev.r-universe.dev", getOption("repos")
))
cmdstanr::install_cmdstan()
install.packages("loo")
```

From this directory:

```powershell
Rscript check_logic.R
Rscript simulation.R --quick
Rscript simulation.R
```

`--quick` is a pipeline check, with one replicate and short MCMC runs. The
default pilot has two replicates, 18 training patients and 60 test patients in
each, and **72 leave-subject-out base-model fits**, plus full-data fits and
stacking fits. It may take substantial time on a laptop. Edit the `config`
list in `main()` to expand the study. For publication-quality inference,
increase replications and MCMC iterations, use multiple chains for the LOO
refits, and review convergence and divergence diagnostics. This small pilot
does not establish a general performance advantage for dynamic stacking.

`--quick` writes to the same `output/` files as the default run. Run the
default simulation again before rendering the report if you want its tables
to describe the two-replicate pilot.

## Checks and diagnostics

`check_logic.R` needs R but not CmdStan. It checks the fixed visit grid,
rejects malformed times and duplicate visits, verifies that changing a
future outcome does not change another horizon's prediction, checks the
Gaussian likelihood in the zero-random-effect case, and checks that the
unsmoothed forms of (4) and (5) agree. `simulation.R` also stops on
missing or non-finite patient data, invalid posterior scales, and
non-finite stacking or PSIS scores. These checks enforce the current
pilot's complete visits 0–6, binary baseline group, and fixed time scale;
adapt the validation before using irregular clinical records.

The simulation saves Pareto $k$, PSIS effective sample size, and relative
MCMC efficiency for each patient and candidate in `psis_diagnostics.csv`.
Inspect these diagnostics before treating a PSIS score as a substitute
for its exact refit; a high Pareto $k$ indicates an unreliable
importance-sampling approximation. The pilot still fits PSIS stacking
weights for comparison, while retaining exact refit scores as its
reference. The short, one-chain exact refits and any sampler warnings
also need review before drawing scientific conclusions.

Output appears in `output/`: patient-level `predictions.csv`, `overall.csv`,
`by_replicate.csv`, `by_group_horizon.csv`, `weights.csv`,
`psis_scores.csv`, `psis_diagnostics.csv`, and `run_info.rds`
with the run settings and weight-model parameter summaries.
`psis_scores.csv` has one row per training patient and future visit,
with exact and PSIS candidate log scores; `predictions.csv` has one row
per test patient, horizon, and ensemble method. The generated `output/`
directory and compiled Stan binaries are ignored by Git.
The findings from the two-replicate pilot are in [RESULTS.md](RESULTS.md).
The methodological explanation, including the conditional PSIS derivation,
is in [landmark-stacking-analysis.qmd](landmark-stacking-analysis.qmd).
Render it with `quarto render landmark-stacking-analysis.qmd --to html` after
running the simulation. The HTML embeds its math resources, so inline
subscripts render without an external MathJax connection.

## Sources

- [Yao et al., Bayesian Analysis 2022](https://doi.org/10.1214/21-BA1287),
  especially §2.4–2.5 and §6.1.
- [Authors' R and Stan replication code](https://github.com/yao-yl/hierarchical-stacking-code).
- [CmdStanR documentation](https://mc-stan.org/cmdstanr/).
