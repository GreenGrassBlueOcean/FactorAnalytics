# =============================================================================
# test-fmCov.R — Regression tests for factor model covariance computation
#
# Covers: fmCov on style-only FFM (where it works), fmCov on TSFM,
# and the covariance identity: Cov = beta %*% Sigma_F %*% t(beta) + diag(sigma2)
# =============================================================================

# --- fmCov on FFM style-only ---
test_that("fmCov FFM style-only reproduces fixture", {
  fix <- readRDS(test_path("fixtures", "fixture_fmCov_ffm_style.rds"))
  fit <- fitFfm(
    data = factorDataSetDjia5Yrs,
    asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
    exposure.vars = c("P2B", "EV2S")
  )
  cov_mat <- fmCov(fit)
  expect_equal(cov_mat, fix$cov, tolerance = 1e-8)
  expect_equal(rownames(cov_mat), fix$rownames)
  expect_equal(colnames(cov_mat), fix$colnames)
})

# --- fmCov on TSFM ---
test_that("fmCov TSFM reproduces fixture", {
  fix <- readRDS(test_path("fixtures", "fixture_fmCov_tsfm.rds"))
  fit <- fitTsfm(
    asset.names = colnames(managers[, 1:6]),
    factor.names = colnames(managers[, 7:9]),
    rf.name = colnames(managers[, 10]),
    data = managers
  )
  cov_mat <- fmCov(fit)
  expect_equal(cov_mat, fix$cov, tolerance = 1e-8)
  expect_equal(rownames(cov_mat), fix$rownames)
  expect_equal(colnames(cov_mat), fix$colnames)
})

# --- Covariance identity: Cov == beta %*% Sigma_F %*% t(beta) + diag(resid.var) ---
test_that("covariance identity holds for FFM style-only", {
  fit <- fitFfm(
    data = factorDataSetDjia5Yrs,
    asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
    exposure.vars = c("P2B", "EV2S")
  )
  cov_direct <- fmCov(fit)
  cov_manual <- fit$beta %*% fit$factor.cov %*% t(fit$beta) + diag(fit$resid.var)
  expect_equal(cov_direct, cov_manual, tolerance = 1e-12)
})

# --- Covariance identity: manual reconstruction on WLS fit ---
test_that("covariance identity holds for FFM WLS (manual reconstruction)", {
  fix <- readRDS(test_path("fixtures", "fixture_cov_identity_ffm.rds"))
  fit <- fitFfm(
    data = dat145,
    exposure.vars = c("SECTOR", "ROE", "BP", "PM12M1M", "SIZE", "ANNVOL1M", "EP"),
    date.var = "DATE", ret.var = "RETURN", asset.var = "TICKER",
    fit.method = "WLS", z.score = "crossSection"
  )
  cov_manual <- fit$beta %*% fit$factor.cov %*% t(fit$beta) + diag(fit$resid.var)
  expect_equal(cov_manual, fix$cov, tolerance = 1e-8)
  expect_equal(rownames(cov_manual), fix$rownames)
  expect_equal(colnames(cov_manual), fix$colnames)
})

# --- Symmetry and positive semi-definiteness ---
test_that("fmCov returns symmetric PSD matrix", {
  fit <- fitFfm(
    data = factorDataSetDjia5Yrs,
    asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
    exposure.vars = c("P2B", "EV2S")
  )
  cov_mat <- fmCov(fit)
  expect_equal(cov_mat, t(cov_mat), tolerance = 1e-14)
  eigenvalues <- eigen(cov_mat, symmetric = TRUE, only.values = TRUE)$values
  expect_true(all(eigenvalues >= -1e-10))
})
