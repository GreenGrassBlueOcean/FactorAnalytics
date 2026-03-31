# =============================================================================
# test-fmmc.R — Smoke tests for fmmc() and fmmcSemiParam()
#
# Covers: R/fmmc.R, R/fmmcSemiParam.R (both at 0% coverage)
# =============================================================================

# ---------------------------------------------------------------------------
# Shared fixtures
# ---------------------------------------------------------------------------

# Align managers data: remove rows with NAs so factors and R have same length
aligned <- na.omit(merge(managers[, 1:3], managers[, 7:9]))

R_3assets <- aligned[, 1:3]
factors_3 <- aligned[, 4:6]

# Fit a tsfm for extracting beta/alpha/resid.sd (used by fmmcSemiParam tests)
fit_tsfm_mgrs <- fitTsfm(
  asset.names  = colnames(R_3assets),
  factor.names = colnames(factors_3),
  data         = as.matrix(merge(R_3assets, factors_3)),
  variable.selection = "none"
)

# ---------------------------------------------------------------------------
# fmmc()
# ---------------------------------------------------------------------------
test_that("fmmc() returns list of fmmc objects with correct structure", {
  objs <- fmmc(R_3assets, factors_3, variable.selection = "none")

  expect_type(objs, "list")
  # At least one asset should produce a valid fmmc object
  expect_gte(length(objs), 1L)

  obj <- objs[[1]]
  expect_named(obj, c("bootdist", "data", "args"), ignore.order = TRUE)
  expect_named(obj$bootdist, c("returns", "factors"), ignore.order = TRUE)
  expect_named(obj$data, c("R", "factors"), ignore.order = TRUE)

  # bootdist$returns is a numeric matrix

  expect_true(is.numeric(obj$bootdist$returns))
  expect_true(is.numeric(obj$bootdist$factors))

  # data$R should be a single-column xts
  expect_s3_class(obj$data$R, "xts")
  expect_equal(ncol(obj$data$R), 1L)

  # Regression: Cartesian join bug produced T^2 rows instead of T
  T_factors <- nrow(na.omit(factors_3))
  expect_equal(nrow(obj$bootdist$returns), T_factors)
  expect_equal(nrow(obj$bootdist$factors), T_factors)
})

test_that("fmmc.estimate.se() computes estimates without SE", {
  objs <- fmmc(R_3assets, factors_3, variable.selection = "none")
  skip_if(length(objs) == 0, "fmmc returned no valid objects")

  result <- fmmc.estimate.se(objs, fun = mean, se = FALSE)

  expect_true(is.matrix(result))
  expect_equal(ncol(result), 1L)
  expect_equal(colnames(result), "estimate")
  expect_equal(nrow(result), length(objs))
  # Estimates should be finite numbers
  expect_true(all(is.finite(result[, "estimate"])))
})

test_that("fmmc.estimate.se() computes estimates with SE", {
  skip_if_not_installed("boot")

  objs <- fmmc(R_3assets, factors_3, variable.selection = "none")
  skip_if(length(objs) == 0, "fmmc returned no valid objects")

  result <- fmmc.estimate.se(objs, fun = mean, se = TRUE, nboot = 10)

  expect_true(is.matrix(result))
  expect_equal(ncol(result), 2L)
  expect_equal(colnames(result), c("estimate", "se"))
  # SE should be non-negative (NAs possible if some bootstrap iterations fail)
  se_vals <- result[, "se"]
  se_finite <- se_vals[is.finite(se_vals)]
  if (length(se_finite) > 0) {
    expect_true(all(se_finite >= 0))
  }
})

test_that("fmmc.estimate.se() returns NA column when fun is NULL", {
  objs <- fmmc(R_3assets, factors_3, variable.selection = "none")
  skip_if(length(objs) == 0, "fmmc returned no valid objects")

  result <- fmmc.estimate.se(objs, fun = NULL)
  expect_true(all(is.na(result[, "estimate"])))
})

# ---------------------------------------------------------------------------
# .fmmc.default.args (internal helper)
# ---------------------------------------------------------------------------
test_that(".fmmc.default.args sets correct defaults", {
  args <- FactorAnalytics:::.fmmc.default.args()
  expect_equal(args$fit.method, "LS")
  expect_equal(args$variable.selection, "subsets")
  expect_true(!is.null(args$nvmax))

  args2 <- FactorAnalytics:::.fmmc.default.args(
    fit.method = "Robust",
    variable.selection = "none"
  )
  expect_equal(args2$fit.method, "Robust")
  expect_equal(args2$variable.selection, "none")

  # Invalid variable.selection falls back to "subsets"
  args3 <- FactorAnalytics:::.fmmc.default.args(variable.selection = "bogus")
  expect_equal(args3$variable.selection, "subsets")
})

# ---------------------------------------------------------------------------
# fmmcSemiParam() — Normal residuals
# ---------------------------------------------------------------------------
test_that("fmmcSemiParam() works with Normal residuals", {
  resid.par <- as.matrix(fit_tsfm_mgrs$resid.sd, ncol = 1)

  result <- fmmcSemiParam(
    B          = 200,
    factor.ret = factors_3,
    beta       = fit_tsfm_mgrs$beta,
    alpha      = fit_tsfm_mgrs$alpha,
    resid.par  = resid.par,
    resid.dist = "normal",
    seed       = 4217
  )

  expect_named(result, c("sim.fund.ret", "boot.factor.ret", "sim.resid"))
  expect_equal(nrow(result$sim.fund.ret), 200L)
  expect_equal(ncol(result$sim.fund.ret), 3L)
  expect_equal(nrow(result$boot.factor.ret), 200L)
  expect_equal(ncol(result$boot.factor.ret), ncol(factors_3))
  expect_equal(dim(result$sim.resid), c(200L, 3L))

  # Simulated returns should be finite
  expect_true(all(is.finite(result$sim.fund.ret)))
  expect_true(all(is.finite(result$sim.resid)))
})

test_that("fmmcSemiParam() works with Normal (mean + sd) residuals", {
  resid.par <- cbind(rep(0, 3), fit_tsfm_mgrs$resid.sd)
  rownames(resid.par) <- rownames(fit_tsfm_mgrs$beta)
  colnames(resid.par) <- c("mean", "sd")

  result <- fmmcSemiParam(
    B          = 100,
    factor.ret = factors_3,
    beta       = fit_tsfm_mgrs$beta,
    alpha      = fit_tsfm_mgrs$alpha,
    resid.par  = resid.par,
    resid.dist = "normal",
    seed       = 7832
  )

  expect_equal(nrow(result$sim.fund.ret), 100L)
  expect_equal(ncol(result$sim.fund.ret), 3L)
})

# ---------------------------------------------------------------------------
# fmmcSemiParam() — Cornish-Fisher residuals
# ---------------------------------------------------------------------------
test_that("fmmcSemiParam() works with Cornish-Fisher residuals", {
  set.seed(5093)
  resid.par <- cbind(
    sigma = fit_tsfm_mgrs$resid.sd,
    skew  = rnorm(3, 0, 0.5),
    ekurt = abs(rnorm(3, 0, 1))
  )
  rownames(resid.par) <- rownames(fit_tsfm_mgrs$beta)

  result <- fmmcSemiParam(
    B          = 150,
    factor.ret = factors_3,
    beta       = fit_tsfm_mgrs$beta,
    alpha      = fit_tsfm_mgrs$alpha,
    resid.par  = resid.par,
    resid.dist = "Cornish-Fisher",
    seed       = 2841
  )

  expect_equal(dim(result$sim.fund.ret), c(150L, 3L))
  expect_true(all(is.finite(result$sim.fund.ret)))
})

# ---------------------------------------------------------------------------
# fmmcSemiParam() — skew-t residuals (requires 'sn')
# ---------------------------------------------------------------------------
test_that("fmmcSemiParam() works with skew-t residuals", {
  skip_if_not_installed("sn")

  resid.par <- cbind(
    xi    = rep(0, 3),
    omega = fit_tsfm_mgrs$resid.sd,
    alpha = rep(0.5, 3),
    nu    = rep(5, 3)
  )
  rownames(resid.par) <- rownames(fit_tsfm_mgrs$beta)

  result <- fmmcSemiParam(
    B          = 100,
    factor.ret = factors_3,
    beta       = fit_tsfm_mgrs$beta,
    alpha      = fit_tsfm_mgrs$alpha,
    resid.par  = resid.par,
    resid.dist = "skew-t",
    seed       = 9134
  )

  expect_equal(dim(result$sim.fund.ret), c(100L, 3L))
  expect_true(all(is.finite(result$sim.fund.ret)))
})

# ---------------------------------------------------------------------------
# fmmcSemiParam() — empirical residuals (from FFM)
# ---------------------------------------------------------------------------
test_that("fmmcSemiParam() works with empirical residuals", {
  fit_ffm_djia_local <- fitFfm(
    data = factorDataSetDjia5Yrs,
    asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
    exposure.vars = c("P2B", "MKTCAP"),
    z.score = "crossSection"
  )

  resid.par <- as.matrix(residuals(fit_ffm_djia_local))

  result <- fmmcSemiParam(
    B           = 100,
    factor.ret  = fit_ffm_djia_local$factor.returns,
    beta        = fit_ffm_djia_local$beta,
    resid.par   = resid.par,
    resid.dist  = "empirical",
    boot.method = "random",
    seed        = 6381
  )

  expect_equal(nrow(result$sim.fund.ret), 100L)
  n_assets <- nrow(fit_ffm_djia_local$beta)
  expect_equal(ncol(result$sim.fund.ret), n_assets)
  expect_true(all(is.finite(result$sim.fund.ret)))
})

test_that("fmmcSemiParam() block bootstrap works with empirical residuals", {
  skip_if_not_installed("tseries")

  fit_ffm_djia_local <- fitFfm(
    data = factorDataSetDjia5Yrs,
    asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
    exposure.vars = c("P2B", "MKTCAP"),
    z.score = "crossSection"
  )

  resid.par <- as.matrix(residuals(fit_ffm_djia_local))

  result <- fmmcSemiParam(
    B           = 100,
    factor.ret  = fit_ffm_djia_local$factor.returns,
    beta        = fit_ffm_djia_local$beta,
    resid.par   = resid.par,
    resid.dist  = "empirical",
    boot.method = "block",
    seed        = 1476
  )

  expect_equal(nrow(result$sim.fund.ret), 100L)
})

# ---------------------------------------------------------------------------
# fmmcSemiParam() — input validation
# ---------------------------------------------------------------------------
test_that("fmmcSemiParam() validates inputs", {
  resid.par <- as.matrix(fit_tsfm_mgrs$resid.sd, ncol = 1)

  expect_error(fmmcSemiParam(factor.ret = factors_3, beta = fit_tsfm_mgrs$beta,
                             resid.par = resid.par),
               NA)

  # Missing factor.ret
  expect_error(fmmcSemiParam(beta = fit_tsfm_mgrs$beta, resid.par = resid.par),
               "factor.ret")

  # Missing beta
  expect_error(fmmcSemiParam(factor.ret = factors_3, resid.par = resid.par),
               "beta")

  # Wrong resid.par dimensions for Cornish-Fisher (needs 3 cols)
  expect_error(
    fmmcSemiParam(factor.ret = factors_3, beta = fit_tsfm_mgrs$beta,
                  resid.par = resid.par, resid.dist = "Cornish-Fisher"),
    "resid.par"
  )

  # Invalid boot.method
  expect_error(
    fmmcSemiParam(factor.ret = factors_3, beta = fit_tsfm_mgrs$beta,
                  resid.par = resid.par, boot.method = "bogus"),
    "boot.method"
  )
})

# ---------------------------------------------------------------------------
# fmmcSemiParam() — missing alpha defaults to zero
# ---------------------------------------------------------------------------
test_that("fmmcSemiParam() defaults alpha to zero when missing", {
  resid.par <- as.matrix(fit_tsfm_mgrs$resid.sd, ncol = 1)

  # Call without alpha
  result <- fmmcSemiParam(
    B          = 50,
    factor.ret = factors_3,
    beta       = fit_tsfm_mgrs$beta,
    resid.par  = resid.par,
    resid.dist = "normal",
    seed       = 3561
  )

  expect_equal(dim(result$sim.fund.ret), c(50L, 3L))
})
