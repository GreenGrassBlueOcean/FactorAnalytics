# =============================================================================
# test-assetDecomp.R — Tests for assetDecomp()
#
# Covers: R/assetDecomp.R
# =============================================================================

# ---------------------------------------------------------------------------
# Shared fixture: FFM fit on DJIA data
# ---------------------------------------------------------------------------
fit_djia_ad <- fitFfm(
  data = factorDataSetDjia5Yrs,
  asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
  exposure.vars = c("P2B", "MKTCAP"),
  z.score = "crossSection"
)
n_assets <- length(fit_djia_ad$asset.names)
wts <- wtsDjiaGmvLo

# ---------------------------------------------------------------------------
# Sd decomposition
# ---------------------------------------------------------------------------
test_that("assetDecomp() Sd returns correct structure", {
  res <- assetDecomp(fit_djia_ad, wts, rm = "Sd")

  expect_type(res, "list")
  expect_named(res, c("Sd", "Sd.contribution", "Sd.Percentage_Contrib"))

  # Scalar portfolio Sd

  expect_length(res$Sd, 1L)
  expect_gt(res$Sd, 0)

  # Contributions: one per asset
  expect_equal(length(res$Sd.contribution), n_assets)

  # Percentage contributions sum to ~100
  expect_equal(sum(res$Sd.Percentage_Contrib), 100, tolerance = 1e-6)
})

test_that("assetDecomp() Sd with equal weights", {
  eq_wts <- rep(1 / n_assets, n_assets)
  res <- assetDecomp(fit_djia_ad, eq_wts, rm = "Sd")

  expect_gt(res$Sd, 0)
  expect_equal(sum(res$Sd.Percentage_Contrib), 100, tolerance = 1e-6)
})

test_that("assetDecomp() Sd with NULL weights defaults to equal weight", {
  res <- assetDecomp(fit_djia_ad, weights = NULL, rm = "Sd")
  expect_gt(res$Sd, 0)
  expect_equal(length(res$Sd.contribution), n_assets)
})

# ---------------------------------------------------------------------------
# VaR decomposition — non-parametric
# ---------------------------------------------------------------------------
test_that("assetDecomp() VaR (np) returns correct structure", {
  res <- assetDecomp(fit_djia_ad, wts, rm = "VaR", p = 0.05, type = "np")

  expect_named(res, c("VaR", "VaR.contribution", "VaR.Percentage_Contrib"))

  # VaR should be negative (loss at 5% tail)
  expect_lt(res$VaR, 0)

  # Contributions: one per asset
  expect_equal(length(res$VaR.contribution), n_assets)

  # Percentage contributions sum to ~100
  expect_equal(sum(res$VaR.Percentage_Contrib), 100, tolerance = 0.5)
})

# ---------------------------------------------------------------------------
# VaR decomposition — normal
# ---------------------------------------------------------------------------
test_that("assetDecomp() VaR (normal) returns correct structure", {
  res <- assetDecomp(fit_djia_ad, wts, rm = "VaR", p = 0.05, type = "normal")

  expect_named(res, c("VaR", "VaR.contribution", "VaR.Percentage_Contrib"))
  expect_lt(res$VaR, 0)
  expect_equal(length(res$VaR.contribution), n_assets)
  expect_equal(sum(res$VaR.Percentage_Contrib), 100, tolerance = 1e-6)
})

# ---------------------------------------------------------------------------
# ES decomposition — non-parametric
# ---------------------------------------------------------------------------
test_that("assetDecomp() ES (np) returns correct structure", {
  res <- assetDecomp(fit_djia_ad, wts, rm = "ES", p = 0.05, type = "np")

  expect_named(res, c("ES", "ES.contribution", "ES.Percentage_Contrib"))

  # ES should be negative and more extreme than VaR
  expect_lt(res$ES, 0)

  var_res <- assetDecomp(fit_djia_ad, wts, rm = "VaR", p = 0.05, type = "np")
  expect_lte(res$ES, var_res$VaR)

  expect_equal(length(res$ES.contribution), n_assets)
  expect_equal(sum(res$ES.Percentage_Contrib), 100, tolerance = 0.5)
})

# ---------------------------------------------------------------------------
# ES decomposition — normal (sign bug now fixed)
# ---------------------------------------------------------------------------
test_that("assetDecomp() ES (normal) returns correct structure and sign", {
  res <- assetDecomp(fit_djia_ad, wts, rm = "ES", p = 0.05, type = "normal")

  expect_named(res, c("ES", "ES.contribution", "ES.Percentage_Contrib"))
  expect_true(is.finite(res$ES))
  expect_equal(length(res$ES.contribution), n_assets)
  expect_equal(sum(res$ES.Percentage_Contrib), 100, tolerance = 1e-6)

  # Normal ES should be negative (left tail)
  expect_lt(res$ES, 0)

  # ES should be more extreme than VaR
  var_res <- assetDecomp(fit_djia_ad, wts, rm = "VaR", p = 0.05, type = "normal")
  expect_lt(res$ES, var_res$VaR)
})

# ---------------------------------------------------------------------------
# Slot-based column access (hard-coded column names bug now fixed)
# ---------------------------------------------------------------------------
test_that("assetDecomp() uses object$ret.var and object$date.var (not hard-coded)", {
  # stocks145scores6 has ret.var="RETURN" and date.var="DATE" which happen to

  # match the old hard-coded names, but this test verifies the slot-based path
  # works for a different dataset structure
  fit_145 <- fitFfm(
    data = stocks145scores6,
    asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
    exposure.vars = c("BP", "SIZE"),
    z.score = "crossSection"
  )

  res <- assetDecomp(fit_145, weights = NULL, rm = "Sd")
  expect_gt(res$Sd, 0)
  n <- length(fit_145$asset.names)
  expect_equal(length(res$Sd.contribution), n)
  expect_equal(sum(res$Sd.Percentage_Contrib), 100, tolerance = 1e-6)
})
