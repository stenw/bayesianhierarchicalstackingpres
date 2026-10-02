data {
  int<lower=1> N;
  int<lower=1> J;
  int<lower=1> P;
  matrix[N, P] X;
  vector[N] time;
  array[N] int<lower=1, upper=J> subject;
  vector[N] y;
}
parameters {
  vector[P] beta;
  vector[J] z_intercept;
  vector[J] z_slope;
  real<lower=0> sd_intercept;
  real<lower=0> sd_slope;
  real<lower=0> sd_error;
}
transformed parameters {
  vector[J] b_intercept = sd_intercept * z_intercept;
  vector[J] b_slope = sd_slope * z_slope;
}
model {
  beta ~ normal(0, 2);
  z_intercept ~ std_normal();
  z_slope ~ std_normal();
  sd_intercept ~ normal(0, 1);
  sd_slope ~ normal(0, 1);
  sd_error ~ normal(0, 1);
  y ~ normal(X * beta + b_intercept[subject] +
             b_slope[subject] .* time, sd_error);
}
