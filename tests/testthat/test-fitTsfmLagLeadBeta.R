# test-fitTsfmLagLeadBeta.R
# Tests for fitTsfmLagLeadBeta() — lagged/lead beta wrapper around fitTsfm
#
# Covers 36 lines in fitTsfmLagLeadBeta.r (previously 0% coverage)

library(testthat)

# Use managers dataset (already loaded in setup.R with make.names applied)
mgr_assets <- colnames(managers[, 1:6])

# ── Lag-only model ──
test_that("fitTsfmLagLeadBeta works with LagOnly=TRUE, LagLeadBeta=1", {
  fit <- fitTsfmLagLeadBeta(
    asset.names = mgr_assets,
    mkt.name = "SP500.TR",
    rf.name = "US.3m.TR",
    data = managers,
    LagLeadBeta = 1,
    LagOnly = TRUE
  )
  expect_s3_class(fit, "tsfm")
  # Should have market + 1 lag = 2 factors
  expect_equal(ncol(fit$beta), 2)
  expect_true("MktLag1" %in% colnames(fit$beta))
  expect_false(any(grepl("MktLead", colnames(fit$beta))))
  expect_equal(length(fit$r2), length(mgr_assets))
})

test_that("fitTsfmLagLeadBeta LagOnly=TRUE with LagLeadBeta=2", {
  fit <- fitTsfmLagLeadBeta(
    asset.names = mgr_assets,
    mkt.name = "SP500.TR",
    rf.name = "US.3m.TR",
    data = managers,
    LagLeadBeta = 2,
    LagOnly = TRUE
  )
  expect_s3_class(fit, "tsfm")
  expect_equal(ncol(fit$beta), 3)  # market + 2 lags
  expect_true(all(c("MktLag1", "MktLag2") %in% colnames(fit$beta)))
})

# ── Lag + lead model ──
test_that("fitTsfmLagLeadBeta includes leads when LagOnly=FALSE", {
  fit <- fitTsfmLagLeadBeta(
    asset.names = mgr_assets,
    mkt.name = "SP500.TR",
    rf.name = "US.3m.TR",
    data = managers,
    LagLeadBeta = 1,
    LagOnly = FALSE
  )
  expect_s3_class(fit, "tsfm")
  # market + 1 lag + 1 lead = 3 factors
  expect_equal(ncol(fit$beta), 3)
  expect_true("MktLag1" %in% colnames(fit$beta))
  expect_true("MktLead1" %in% colnames(fit$beta))
})

test_that("fitTsfmLagLeadBeta LagOnly=FALSE with LagLeadBeta=2", {
  fit <- fitTsfmLagLeadBeta(
    asset.names = mgr_assets,
    mkt.name = "SP500.TR",
    rf.name = "US.3m.TR",
    data = managers,
    LagLeadBeta = 2,
    LagOnly = FALSE
  )
  expect_equal(ncol(fit$beta), 5)  # market + 2 lags + 2 leads
  expect_true(all(c("MktLag1", "MktLag2", "MktLead1", "MktLead2") %in%
                    colnames(fit$beta)))
})

# ── rf.name=NULL (no excess return adjustment) ──
test_that("fitTsfmLagLeadBeta works with rf.name=NULL", {
  fit <- fitTsfmLagLeadBeta(
    asset.names = mgr_assets,
    mkt.name = "SP500.TR",
    rf.name = NULL,
    data = managers,
    LagLeadBeta = 1,
    LagOnly = TRUE
  )
  expect_s3_class(fit, "tsfm")
  expect_equal(ncol(fit$beta), 2)
})

# ── rf.name bug regression: rf.name should not become mkt.name ──
test_that("rf.name is preserved, not overwritten by mkt.name", {
  # With the bug, rf.name was set to make.names(mkt.name) instead of
  # make.names(rf.name). If fixed, the model should subtract the actual
  # risk-free rate, producing different alphas than a NULL rf model.
  fit_rf <- fitTsfmLagLeadBeta(
    asset.names = mgr_assets[1:2],
    mkt.name = "SP500.TR",
    rf.name = "US.3m.TR",
    data = managers,
    LagLeadBeta = 1,
    LagOnly = TRUE
  )
  fit_no_rf <- fitTsfmLagLeadBeta(
    asset.names = mgr_assets[1:2],
    mkt.name = "SP500.TR",
    rf.name = NULL,
    data = managers,
    LagLeadBeta = 1,
    LagOnly = TRUE
  )
  # Alphas should differ when rf is properly subtracted
  expect_false(isTRUE(all.equal(fit_rf$alpha, fit_no_rf$alpha, tolerance = 1e-8)),
               "rf.name should affect alpha estimates (regression for rf.name bug)")
})

# ── Error paths ──
test_that("fitTsfmLagLeadBeta errors on missing mkt.name", {
  expect_error(
    fitTsfmLagLeadBeta(
      asset.names = mgr_assets,
      mkt.name = NULL,
      data = managers,
      LagLeadBeta = 1
    ),
    "mkt.name"
  )
})

test_that("fitTsfmLagLeadBeta errors on invalid LagLeadBeta", {
  # LagLeadBeta = -1 and 1.5 both fail the integer/>=1 check inside the block
  expect_error(
    fitTsfmLagLeadBeta(
      asset.names = mgr_assets,
      mkt.name = "SP500.TR",
      data = managers,
      LagLeadBeta = -1
    ),
    "LagLeadBeta"
  )
  expect_error(
    fitTsfmLagLeadBeta(
      asset.names = mgr_assets,
      mkt.name = "SP500.TR",
      data = managers,
      LagLeadBeta = 1.5
    ),
    "LagLeadBeta"
  )
})

# ── S3 methods work on returned object ──
test_that("summary, coef, fitted, residuals work on LagLeadBeta fit", {
  fit <- fitTsfmLagLeadBeta(
    asset.names = mgr_assets[1:3],
    mkt.name = "SP500.TR",
    rf.name = "US.3m.TR",
    data = managers,
    LagLeadBeta = 1,
    LagOnly = TRUE
  )
  expect_no_error(summary(fit))
  co <- coef(fit)
  expect_true(is.data.frame(co) || is.matrix(co))
  expect_s3_class(fitted(fit), "xts")
  expect_s3_class(residuals(fit), "xts")
})
