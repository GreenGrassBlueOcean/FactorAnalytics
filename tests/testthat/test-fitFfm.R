# =============================================================================
# test-fitFfm.R — Regression tests for fundamental factor model fitting
#
# Covers all three FFM model branches:
#   - Style-only (0 character exposures)
#   - Sector + style + intercept (1 character exposure)
#   - Sector-only (character exposure only)
#   - WLS sector + style (production path)
#   - W-Rob robust (robust regression path)
# =============================================================================

# --- Style-only (P2B, EV2S on DJIA) ---
test_that("fitFfm LS style-only reproduces fixture", {
  fix <- readRDS(test_path("fixtures", "fixture_ffm_ls_style.rds"))
  fit <- fitFfm(
    data = factorDataSetDjia5Yrs,
    asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
    exposure.vars = c("P2B", "EV2S")
  )
  expect_equal(fit$beta, fix$beta, tolerance = 1e-10)
  expect_equal(as.matrix(fit$factor.returns), fix$factor.returns, tolerance = 1e-10)
  expect_equal(as.matrix(fit$residuals), fix$residuals, tolerance = 1e-10)
  expect_equal(fit$factor.cov, fix$factor.cov, tolerance = 1e-10)
  expect_equal(fit$resid.var, fix$resid.var, tolerance = 1e-10)
  expect_equal(fit$r2, fix$r2, tolerance = 1e-10)
  expect_equal(fit$asset.names, fix$asset.names)
  expect_equal(fit$factor.names, fix$factor.names)
  expect_equal(fit$time.periods, fix$time.periods)
})

# --- Sector + style + intercept ---
test_that("fitFfm LS sector+style+intercept reproduces fixture", {
  fix <- readRDS(test_path("fixtures", "fixture_ffm_ls_sector.rds"))
  fit <- fitFfm(
    data = factorDataSetDjia5Yrs,
    asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
    exposure.vars = c("SECTOR", "P2B", "EV2S"),
    addIntercept = TRUE
  )
  expect_equal(fit$beta, fix$beta, tolerance = 1e-10)
  expect_equal(as.matrix(fit$factor.returns), fix$factor.returns, tolerance = 1e-10)
  expect_equal(as.matrix(fit$residuals), fix$residuals, tolerance = 1e-10)
  expect_equal(fit$factor.cov, fix$factor.cov, tolerance = 1e-10)
  expect_equal(fit$resid.var, fix$resid.var, tolerance = 1e-10)
  expect_equal(fit$r2, fix$r2, tolerance = 1e-10)
})

# --- Sector-only ---
test_that("fitFfm sector-only reproduces fixture", {
  fix <- readRDS(test_path("fixtures", "fixture_ffm_sector_only.rds"))
  fit <- fitFfm(
    data = factorDataSetDjia5Yrs,
    asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
    exposure.vars = "SECTOR"
  )
  expect_equal(fit$beta, fix$beta, tolerance = 1e-10)
  expect_equal(as.matrix(fit$factor.returns), fix$factor.returns, tolerance = 1e-10)
  expect_equal(as.matrix(fit$residuals), fix$residuals, tolerance = 1e-10)
  expect_equal(fit$factor.cov, fix$factor.cov, tolerance = 1e-10)
  expect_equal(fit$resid.var, fix$resid.var, tolerance = 1e-10)
  expect_equal(fit$r2, fix$r2, tolerance = 1e-10)
})

# --- WLS sector + style (production path on 145-stock universe) ---
test_that("fitFfm WLS sector+style reproduces fixture", {
  fix <- readRDS(test_path("fixtures", "fixture_ffm_wls.rds"))
  fit <- fitFfm(
    data = dat145,
    exposure.vars = c("SECTOR", "ROE", "BP", "PM12M1M", "SIZE", "ANNVOL1M", "EP"),
    date.var = "DATE", ret.var = "RETURN", asset.var = "TICKER",
    fit.method = "WLS", z.score = "crossSection"
  )
  expect_equal(fit$beta, fix$beta, tolerance = 1e-10)
  expect_equal(as.matrix(fit$factor.returns), fix$factor.returns, tolerance = 1e-10)
  expect_equal(as.matrix(fit$residuals), fix$residuals, tolerance = 1e-10)
  expect_equal(fit$factor.cov, fix$factor.cov, tolerance = 1e-10)
  expect_equal(fit$resid.var, fix$resid.var, tolerance = 1e-10)
  expect_equal(fit$r2, fix$r2, tolerance = 1e-10)
})

# --- W-Rob robust (DJIA, sector + P2B) ---
test_that("fitFfm W-Rob reproduces fixture", {
  skip_if_not_installed("RobStatTM")
  skip_if_not_installed("robustbase")
  fix <- readRDS(test_path("fixtures", "fixture_ffm_wrob.rds"))
  fit <- fitFfm(
    data = factorDataSetDjia5Yrs,
    asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
    exposure.vars = c("SECTOR", "P2B"),
    fit.method = "W-Rob"
  )
  # W-Rob uses IRLS; convergence varies across BLAS implementations
  expect_equal(fit$beta, fix$beta, tolerance = 1e-4)
  expect_equal(as.matrix(fit$factor.returns), fix$factor.returns, tolerance = 1e-4)
  expect_equal(as.matrix(fit$residuals), fix$residuals, tolerance = 1e-4)
  expect_equal(fit$factor.cov, fix$factor.cov, tolerance = 1e-4)
  expect_equal(fit$resid.var, fix$resid.var, tolerance = 1e-4)
  expect_equal(fit$r2, fix$r2, tolerance = 1e-4)
})

# --- Object structure invariants ---
test_that("fitFfm returns expected object class and slot names", {
  fit <- fitFfm(
    data = factorDataSetDjia5Yrs,
    asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
    exposure.vars = c("P2B", "EV2S")
  )
  expect_s3_class(fit, "ffm")
  expected_names <- c("asset.names", "r2", "factor.names", "asset.var",
                      "date.var", "ret.var", "exposure.vars", "exposures.num",
                      "exposures.char", "data", "time.periods", "factor.fit",
                      "beta", "factor.returns", "factor.cov", "resid.var",
                      "residuals")
  expect_true(all(expected_names %in% names(fit)))
})

# --- Dimensional consistency ---
test_that("fitFfm dimensions are internally consistent", {
  fit <- fitFfm(
    data = factorDataSetDjia5Yrs,
    asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
    exposure.vars = c("P2B", "EV2S")
  )
  n_assets <- length(fit$asset.names)
  n_factors <- length(fit$factor.names)
  n_periods <- length(fit$time.periods)

  expect_equal(nrow(fit$beta), n_assets)
  expect_equal(ncol(fit$beta), n_factors)
  expect_equal(nrow(fit$factor.returns), n_periods)
  expect_equal(ncol(fit$factor.returns), n_factors)
  expect_equal(nrow(fit$residuals), n_periods)
  expect_equal(ncol(fit$residuals), n_assets)
  expect_equal(length(fit$resid.var), n_assets)
  expect_equal(length(fit$r2), n_periods)
  expect_equal(nrow(fit$factor.cov), n_factors)
  expect_equal(ncol(fit$factor.cov), n_factors)

  # Rownames / colnames consistency
  expect_equal(rownames(fit$beta), fit$asset.names)
  expect_equal(colnames(fit$beta), fit$factor.names)
  expect_equal(names(fit$resid.var), fit$asset.names)
})

# ── Standalone Rob (no WLS second pass) ──────────────────────────────────────

test_that("fitFfm Rob (standalone) produces valid fit", {
  skip_if_not_installed("RobStatTM")
  skip_if_not_installed("robustbase")
  fit <- fitFfm(
    data = factorDataSetDjia5Yrs,
    asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
    exposure.vars = c("P2B", "EV2S"),
    fit.method = "Rob"
  )
  expect_s3_class(fit, "ffm")
  expect_equal(nrow(fit$beta), length(fit$asset.names))
  expect_equal(ncol(fit$factor.returns), length(fit$factor.names))
  expect_equal(length(fit$resid.var), length(fit$asset.names))
  expect_true(all(fit$resid.var > 0))
})

# ── GARCH residual scaling ───────────────────────────────────────────────────

test_that("fitFfm WLS + GARCH residual scaling produces valid fit", {
  fit <- fitFfm(
    data = dat145,
    asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
    exposure.vars = c("SECTOR", "ROE", "BP"),
    fit.method = "WLS",
    resid.scaleType = "GARCH"
  )
  expect_s3_class(fit, "ffm")
  expect_equal(nrow(fit$beta), length(fit$asset.names))
  expect_true(all(fit$resid.var > 0))
})

# ── RobustEWMA residual scaling ──────────────────────────────────────────────

test_that("fitFfm WLS + RobustEWMA residual scaling produces valid fit", {
  fit <- fitFfm(
    data = dat145,
    asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
    exposure.vars = c("SECTOR", "ROE", "BP"),
    fit.method = "WLS",
    resid.scaleType = "RobustEWMA"
  )
  expect_s3_class(fit, "ffm")
  expect_equal(nrow(fit$beta), length(fit$asset.names))
  expect_true(all(fit$resid.var > 0))
})

test_that("fitFfm accepts legacy 'robEWMA' alias", {
  # Pre-existing naming mismatch: fitFfm validated "robEWMA" but fitFfmDT
  # expected "RobustEWMA". Now normalized via tolower() alias.
  fit <- fitFfm(
    data = dat145,
    asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
    exposure.vars = c("SECTOR", "ROE", "BP"),
    fit.method = "WLS",
    resid.scaleType = "robEWMA"
  )
  expect_s3_class(fit, "ffm")
})

# ── rob.stats = TRUE ─────────────────────────────────────────────────────────

test_that("fitFfm WLS + rob.stats uses robust residual variance", {
  skip_if_not_installed("robustbase")
  fit <- fitFfm(
    data = dat145,
    asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
    exposure.vars = c("SECTOR", "ROE", "BP"),
    fit.method = "WLS",
    rob.stats = TRUE
  )
  expect_s3_class(fit, "ffm")
  expect_true(all(fit$resid.var > 0))
  # Robust residual variance should differ from standard variance
  fit_std <- fitFfm(
    data = dat145,
    asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
    exposure.vars = c("SECTOR", "ROE", "BP"),
    fit.method = "WLS",
    rob.stats = FALSE
  )
  expect_false(isTRUE(all.equal(fit$resid.var, fit_std$resid.var)),
               info = "Robust and standard resid.var should differ")
})
