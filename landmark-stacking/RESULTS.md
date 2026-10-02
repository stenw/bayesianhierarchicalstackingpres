# Pilot results

Run on 2026-10-02 with the default settings in `simulation.R`: two
replicates, 18 training patients and 60 untouched test patients per
replicate. Each patient has history through visit 3 and a separate
prediction at visits 4–6. The 72 exact leave-patient-out candidate
refits used one chain with 250 warmup and 250 sampling iterations.
The full-data candidate fits and stacking fits used four chains with
500 warmup and 500 sampling iterations each. PSIS used all 2,000
full-data draws per candidate; test prediction integration used 200.

| Method | Mean test log predictive density | Test RMSE |
| --- | ---: | ---: |
| Linear candidate | -0.870 | 0.570 |
| Curved candidate | -0.924 | 0.596 |
| Equal density mixture | **-0.834** | **0.564** |
| Constant stacking, exact refits | -0.841 | 0.567 |
| Dynamic stacking, exact refits | -0.837 | 0.565 |
| Constant stacking, PSIS (4) | -0.841 | 0.567 |
| Dynamic stacking, PSIS (4) | -0.837 | 0.565 |
| Constant stacking, PSIS (5) | -0.840 | 0.566 |
| Dynamic stacking, PSIS (5) | -0.837 | 0.564 |

Each row summarizes 360 predictions from 120 distinct test patients.
Higher log predictive density and lower RMSE are better. The stacking
methods learned from PSIS scores perform similarly to the ones learned
from exact refits in this small study. Equal weights have the best mean
log score here. The differences are too small and the study too short
to claim general superiority.

The candidate **training** log scores from PSIS versus exact refits had
these mean absolute differences across patients and horizons:

| Candidate | PSIS (4) | PSIS (5) |
| --- | ---: | ---: |
| Linear | 0.0189 | 0.0193 |
| Curved | 0.0231 | 0.0225 |

The maximum absolute differences were 0.176–0.179 for the linear
candidate and 0.143–0.145 for the curved candidate. Pareto diagnostics
were calculated for each patient and candidate:

| Candidate | Formula | Maximum Pareto k | Patients with k ≥ 0.7 | Minimum PSIS ESS |
| --- | --- | ---: | ---: | ---: |
| Linear | (4) | 1.131 | 1 / 36 | 11 |
| Linear | (5) | 0.642 | 0 / 36 | 150 |
| Curved | (4) | 0.985 | 1 / 36 | 5 |
| Curved | (5) | 0.756 | 1 / 36 | 46 |

These flags make the affected patient-level PSIS scores unreliable as
standalone replacements for exact refits. Formula (5), which retains
the observed landmark history while removing all later outcomes, had
better Pareto diagnostics in this run. The two formulations target the
same conditional density in the unsmoothed importance-sampling limit;
they differ after finite-sample Pareto smoothing.

The synthetic design has complete, equally spaced continuous outcomes
and one fixed landmark. Short, single-chain exact refits limit the
precision of the reference scores. Some Stan proposals were rejected
for invalid scale or location values, and one 2,000-transition stacking
fit reported a divergence. A larger study should vary sample size,
signal strength, visit pattern, and missingness, and inspect all sampler
diagnostics. The Quarto report provides the equations and live tables;
the patient-level CSV files in `output/` retain the complete values.
