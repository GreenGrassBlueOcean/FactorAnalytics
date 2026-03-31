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

# --- print.ffmSpec (18 uncovered lines in fitFfmDT.R) ---
test_that("print.ffmSpec produces expected output", {
  spec <- specFfm(
    data = dat145, asset.var = "TICKER", ret.var = "RETURN",
    date.var = "DATE", exposure.vars = c("SECTOR", "ROE", "BP")
  )
  out <- capture.output(print(spec))
  expect_true(any(grepl("fundamental factor model specification", out)))
  expect_true(any(grepl("TICKER", out)))
  expect_true(any(grepl("145 unique assets", out)))
  expect_true(any(grepl("RETURN", out)))
})

# --- rob.stats=TRUE: robust covariance paths (lines 1047-1114) ---
test_that("fitFfm with rob.stats=TRUE produces robust covariance estimates", {
  skip_if_not_installed("robustbase")
  skip_if_not_installed("RobStatTM")
  # Style-only model to avoid singular robust factor covariance
  fit_rob <- fitFfm(
    data = dat145, asset.var = "TICKER", ret.var = "RETURN",
    date.var = "DATE", exposure.vars = c("ROE", "BP", "SIZE"),
    fit.method = "LS", z.score = "crossSection", rob.stats = TRUE
  )
  fit_std <- fitFfm(
    data = dat145, asset.var = "TICKER", ret.var = "RETURN",
    date.var = "DATE", exposure.vars = c("ROE", "BP", "SIZE"),
    fit.method = "LS", z.score = "crossSection", rob.stats = FALSE
  )
  expect_equal(dim(fit_rob$factor.cov), c(3L, 3L))
  expect_equal(dim(fit_rob$resid.cov), dim(fit_std$resid.cov))
  # Robust and standard estimates should differ
  expect_false(isTRUE(all.equal(fit_rob$factor.cov, fit_std$factor.cov)))
  expect_false(isTRUE(all.equal(fit_rob$resid.cov, fit_std$resid.cov)))
})

# --- weight.var: weighted z-score standardization (lines 456-458) ---
test_that("fitFfm with weight.var uses weighted z-scores", {
  dat_w <- dat145
  dat_w$MKT_CAP <- abs(dat_w$SIZE) + 1
  fit_wt <- fitFfm(
    data = dat_w, asset.var = "TICKER", ret.var = "RETURN",
    date.var = "DATE", exposure.vars = c("SECTOR", "ROE", "BP"),
    addIntercept = TRUE, fit.method = "WLS", z.score = "crossSection",
    weight.var = "MKT_CAP"
  )
  fit_no_wt <- fitFfm(
    data = dat_w, asset.var = "TICKER", ret.var = "RETURN",
    date.var = "DATE", exposure.vars = c("SECTOR", "ROE", "BP"),
    addIntercept = TRUE, fit.method = "WLS", z.score = "crossSection"
  )
  expect_equal(dim(fit_wt$beta), dim(fit_no_wt$beta))
  # Weighted and unweighted z-scores should produce different factor returns
  expect_false(isTRUE(all.equal(fit_wt$factor.returns, fit_no_wt$factor.returns)))
})

# --- rob.stats=TRUE z-score path (lines 469-471 in standardizeExposures) ---
test_that("fitFfm with rob.stats=TRUE uses robust z-scores (median/mad)", {
  skip_if_not_installed("robustbase")
  skip_if_not_installed("RobStatTM")
  fit_rob <- fitFfm(
    data = dat145, asset.var = "TICKER", ret.var = "RETURN",
    date.var = "DATE", exposure.vars = c("ROE", "BP"),
    fit.method = "LS", z.score = "crossSection", rob.stats = TRUE
  )
  fit_std <- fitFfm(
    data = dat145, asset.var = "TICKER", ret.var = "RETURN",
    date.var = "DATE", exposure.vars = c("ROE", "BP"),
    fit.method = "LS", z.score = "crossSection", rob.stats = FALSE
  )
  # Robust z-scores (median/mad) differ from standard z-scores (mean/sd)
  expect_false(isTRUE(all.equal(fit_rob$factor.returns, fit_std$factor.returns)))
})

# --- stdReturn=TRUE: GARCH-standardized returns (fitFfm.R lines 303-305) ---
test_that("fitFfm with stdReturn=TRUE produces different factor returns", {
  fit_plain <- fitFfm(
    data = dat145, asset.var = "TICKER", ret.var = "RETURN",
    date.var = "DATE", exposure.vars = c("SECTOR", "ROE", "BP"),
    stdReturn = FALSE
  )
  fit_std <- fitFfm(
    data = dat145, asset.var = "TICKER", ret.var = "RETURN",
    date.var = "DATE", exposure.vars = c("SECTOR", "ROE", "BP"),
    stdReturn = TRUE
  )
  expect_s3_class(fit_std, "ffm")
  expect_true(all(!is.na(fit_std$r2)))
  # Standardization changes the regressand, so factor returns must differ
  expect_false(
    isTRUE(all.equal(as.matrix(fit_plain$factor.returns),
                     as.matrix(fit_std$factor.returns))),
    "stdReturn=TRUE should change factor returns (regression for no-op bug)"
  )
})

test_that("fitFfm stdReturn=TRUE preserves object structure", {
  fit_std <- fitFfm(
    data = dat145, asset.var = "TICKER", ret.var = "RETURN",
    date.var = "DATE", exposure.vars = c("SECTOR", "ROE", "BP"),
    stdReturn = TRUE
  )
  # Same structure as non-std model
  expect_true("factor.returns" %in% names(fit_std))
  expect_true("residuals" %in% names(fit_std))
  expect_true("beta" %in% names(fit_std))
  expect_true("r2" %in% names(fit_std))
  n_dates <- length(unique(dat145$DATE)) - 1L  # -1 for lagExposures
  expect_equal(length(fit_std$r2), n_dates)
})

# --- lagExposures=FALSE: skip exposure lagging (fitFfm.R line 323) ---
test_that("fitFfm with lagExposures=FALSE uses all dates", {
  fit_lag <- fitFfm(
    data = dat145, asset.var = "TICKER", ret.var = "RETURN",
    date.var = "DATE", exposure.vars = c("SECTOR", "ROE", "BP"),
    lagExposures = TRUE
  )
  fit_nolag <- fitFfm(
    data = dat145, asset.var = "TICKER", ret.var = "RETURN",
    date.var = "DATE", exposure.vars = c("SECTOR", "ROE", "BP"),
    lagExposures = FALSE
  )
  expect_s3_class(fit_nolag, "ffm")
  # Without lagging, all 60 dates are used (vs 59 with lagging)
  expect_equal(nrow(fit_nolag$factor.returns), nrow(fit_lag$factor.returns) + 1L)
  # Factor returns should differ (different exposure alignment)
  expect_false(
    isTRUE(all.equal(
      as.matrix(fit_lag$factor.returns),
      as.matrix(utils::tail(fit_nolag$factor.returns, nrow(fit_lag$factor.returns)))
    ))
  )
})
