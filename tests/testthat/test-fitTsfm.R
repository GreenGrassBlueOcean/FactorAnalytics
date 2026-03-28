# =============================================================================
# test-fitTsfm.R — Regression tests for time series factor model fitting
#
# Covers: LS, Robust, and lars variable selection paths.
# Uses the PerformanceAnalytics::managers dataset.
# =============================================================================

# --- TSFM LS ---
test_that("fitTsfm LS reproduces fixture", {
  fix <- readRDS(test_path("fixtures", "fixture_tsfm_ls.rds"))
  fit <- fitTsfm(
    asset.names = colnames(managers[, 1:6]),
    factor.names = colnames(managers[, 7:9]),
    rf.name = colnames(managers[, 10]),
    data = managers
  )
  expect_equal(as.data.frame(fit$alpha), fix$alpha, tolerance = 1e-10)
  expect_equal(as.data.frame(fit$beta), fix$beta, tolerance = 1e-10)
  expect_equal(fit$r2, fix$r2, tolerance = 1e-10)
  expect_equal(fit$resid.sd, fix$resid.sd, tolerance = 1e-10)
  # as.Date.yearmon end-of-month convention differs across platforms (±1 day);
  # compare values only, ignoring date rownames
  expect_equal(unname(as.matrix(residuals(fit))), unname(fix$residuals), tolerance = 1e-10)
  expect_equal(unname(as.matrix(fitted(fit))), unname(fix$fitted), tolerance = 1e-10)
  expect_equal(fit$asset.names, fix$asset.names)
  expect_equal(fit$factor.names, fix$factor.names)
})

# --- TSFM Robust ---
test_that("fitTsfm Robust reproduces fixture", {
  skip_if_not_installed("RobStatTM")
  fix <- readRDS(test_path("fixtures", "fixture_tsfm_robust.rds"))
  fit <- fitTsfm(
    asset.names = colnames(managers[, 1:6]),
    factor.names = colnames(managers[, 7:9]),
    rf.name = colnames(managers[, 10]),
    data = managers,
    fit.method = "Robust"
  )
  expect_equal(as.data.frame(fit$alpha), fix$alpha, tolerance = 1e-10)
  expect_equal(as.data.frame(fit$beta), fix$beta, tolerance = 1e-10)
  expect_equal(fit$r2, fix$r2, tolerance = 1e-10)
  expect_equal(fit$resid.sd, fix$resid.sd, tolerance = 1e-10)
})

# --- TSFM lars ---
test_that("fitTsfm lars reproduces fixture", {
  skip_if_not_installed("lars")
  fix <- readRDS(test_path("fixtures", "fixture_tsfm_lars.rds"))
  fit <- fitTsfm(
    asset.names = colnames(managers[, 1:6]),
    factor.names = colnames(managers[, 7:9]),
    rf.name = colnames(managers[, 10]),
    data = managers,
    variable.selection = "lars"
  )
  expect_equal(as.data.frame(fit$alpha), fix$alpha, tolerance = 1e-10)
  expect_equal(as.data.frame(fit$beta), fix$beta, tolerance = 1e-10)
  expect_equal(fit$r2, fix$r2, tolerance = 1e-10)
  expect_equal(fit$resid.sd, fix$resid.sd, tolerance = 1e-10)
})

# --- Cross-validation with manual lm ---
test_that("fitTsfm LS betas match per-asset lm()", {
  assets <- colnames(managers)[1:6]
  factors <- colnames(managers)[7:9]
  rf <- colnames(managers)[10]

  fit <- fitTsfm(
    asset.names = assets,
    factor.names = factors,
    rf.name = rf,
    data = managers
  )

  # fitTsfm subtracts rf from BOTH assets and factors before fitting.
  for (a in assets) {
    dat_a <- managers[, c(a, factors, rf)]
    ex_ret <- dat_a[, a] - dat_a[, rf]
    ex_factors <- dat_a[, factors] - as.numeric(dat_a[, rf])
    manual_fit <- lm(coredata(ex_ret) ~ coredata(ex_factors))
    manual_beta <- coef(manual_fit)[-1]
    manual_r2 <- summary(manual_fit)$r.squared

    expect_equal(as.numeric(fit$beta[a, ]), as.numeric(manual_beta),
                 tolerance = 1e-10, info = paste("beta mismatch for", a))
    expect_equal(as.numeric(fit$r2[a]), manual_r2,
                 tolerance = 1e-10, info = paste("r2 mismatch for", a))
  }
})

# --- Object structure ---
test_that("fitTsfm returns expected object class and slots", {
  fit <- fitTsfm(
    asset.names = colnames(managers[, 1:6]),
    factor.names = colnames(managers[, 7:9]),
    rf.name = colnames(managers[, 10]),
    data = managers
  )
  expect_s3_class(fit, "tsfm")
  expect_true(all(c("asset.fit", "alpha", "beta", "r2", "resid.sd",
                     "asset.names", "factor.names") %in% names(fit)))
  expect_equal(nrow(fit$beta), length(fit$asset.names))
  expect_equal(length(fit$r2), length(fit$asset.names))
  expect_equal(length(fit$resid.sd), length(fit$asset.names))
})
