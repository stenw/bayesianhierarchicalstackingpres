data {
  int<lower=1> N;
  int<lower=1> P;
  matrix[N, P] feature;
  matrix[N, 2] log_pred;
  vector<lower=0>[N] case_weight;
}
parameters {
  real intercept;
  vector[P - 1] raw_effect;
  real<lower=0> effect_scale;
}
transformed parameters {
  vector[P] coef;
  coef[1] = intercept;
  if (P > 1) {
    coef[2:P] = effect_scale * raw_effect;
  }
}
model {
  intercept ~ normal(0, 1.5);
  raw_effect ~ std_normal();
  effect_scale ~ normal(0, 0.75);
  for (n in 1:N) {
    real weight_curved = inv_logit(feature[n] * coef);
    target += case_weight[n] *
      log_mix(weight_curved, log_pred[n, 2], log_pred[n, 1]);
  }
}
