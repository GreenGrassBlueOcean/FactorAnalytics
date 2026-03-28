# =============================================================================
# test-portDecomp.R — Regression tests for portfolio-level risk decomposition
#
# Covers: portSdDecomp, portVaRDecomp, portEsDecomp on both TSFM and FFM.
# =============================================================================

# --- portSdDecomp TSFM ---
test_that("portSdDecomp TSFM reproduces fixture", {
  fix <- readRDS(test_path("fixtures", "fixture_portSdDecomp_tsfm.rds"))
  fit <- fitTsfm(
    asset.names = colnames(managers[, 1:6]),
    factor.names = colnames(managers[, 7:9]),
    rf.name = colnames(managers[, 10]),
    data = managers
  )
  decomp <- portSdDecomp(fit)
  expect_equal(decomp$Sd.fm, fix$Sd.fm, tolerance = 1e-6)
  expect_equal(decomp$mSd, fix$mSd, tolerance = 1e-6)
  expect_equal(decomp$cSd, fix$cSd, tolerance = 1e-6)
  expect_equal(decomp$pcSd, fix$pcSd, tolerance = 1e-6)
})

# --- portVaRDecomp TSFM ---
test_that("portVaRDecomp TSFM reproduces fixture", {
  fix <- readRDS(test_path("fixtures", "fixture_portVaRDecomp_tsfm.rds"))
  fit <- fitTsfm(
    asset.names = colnames(managers[, 1:6]),
    factor.names = colnames(managers[, 7:9]),
    rf.name = colnames(managers[, 10]),
    data = managers
  )
  decomp <- portVaRDecomp(fit, p = 0.9, type = "normal")
  expect_equal(decomp$VaR.fm, fix$VaR.fm, tolerance = 1e-6)
  expect_equal(decomp$mVaR, fix$mVaR, tolerance = 1e-6)
  expect_equal(decomp$cVaR, fix$cVaR, tolerance = 1e-6)
  expect_equal(decomp$pcVaR, fix$pcVaR, tolerance = 1e-6)
})

# --- portEsDecomp TSFM ---
test_that("portEsDecomp TSFM reproduces fixture", {
  fix <- readRDS(test_path("fixtures", "fixture_portEsDecomp_tsfm.rds"))
  fit <- fitTsfm(
    asset.names = colnames(managers[, 1:6]),
    factor.names = colnames(managers[, 7:9]),
    rf.name = colnames(managers[, 10]),
    data = managers
  )
  decomp <- portEsDecomp(fit, p = 0.9, type = "normal")
  expect_equal(decomp$ES.fm, fix$ES.fm, tolerance = 1e-6)
  expect_equal(decomp$mES, fix$mES, tolerance = 1e-6)
  expect_equal(decomp$cES, fix$cES, tolerance = 1e-6)
  expect_equal(decomp$pcES, fix$pcES, tolerance = 1e-6)
})

# --- portSdDecomp FFM ---
test_that("portSdDecomp FFM reproduces fixture", {
  fix <- readRDS(test_path("fixtures", "fixture_portSdDecomp_ffm.rds"))
  fit <- fitFfm(
    data = factorDataSetDjia5Yrs,
    asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
    exposure.vars = c("P2B", "EV2S")
  )
  decomp <- portSdDecomp(fit)
  expect_equal(decomp$Sd.fm, fix$Sd.fm, tolerance = 1e-6)
  expect_equal(decomp$mSd, fix$mSd, tolerance = 1e-6)
  expect_equal(decomp$cSd, fix$cSd, tolerance = 1e-6)
  expect_equal(decomp$pcSd, fix$pcSd, tolerance = 1e-6)
})

# --- portVaRDecomp FFM ---
test_that("portVaRDecomp FFM reproduces fixture", {
  fix <- readRDS(test_path("fixtures", "fixture_portVaRDecomp_ffm.rds"))
  fit <- fitFfm(
    data = factorDataSetDjia5Yrs,
    asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
    exposure.vars = c("P2B", "EV2S")
  )
  decomp <- portVaRDecomp(fit, p = 0.9, type = "normal")
  expect_equal(decomp$VaR.fm, fix$VaR.fm, tolerance = 1e-6)
  expect_equal(decomp$mVaR, fix$mVaR, tolerance = 1e-6)
  expect_equal(decomp$cVaR, fix$cVaR, tolerance = 1e-6)
  expect_equal(decomp$pcVaR, fix$pcVaR, tolerance = 1e-6)
})

# --- portEsDecomp FFM ---
test_that("portEsDecomp FFM reproduces fixture", {
  fix <- readRDS(test_path("fixtures", "fixture_portEsDecomp_ffm.rds"))
  fit <- fitFfm(
    data = factorDataSetDjia5Yrs,
    asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
    exposure.vars = c("P2B", "EV2S")
  )
  decomp <- portEsDecomp(fit, p = 0.9, type = "normal")
  expect_equal(decomp$ES.fm, fix$ES.fm, tolerance = 1e-6)
  expect_equal(decomp$mES, fix$mES, tolerance = 1e-6)
  expect_equal(decomp$cES, fix$cES, tolerance = 1e-6)
  expect_equal(decomp$pcES, fix$pcES, tolerance = 1e-6)
})

# --- Error handling ---
test_that("portSdDecomp errors on wrong number of weights", {
  fit <- fitTsfm(
    asset.names = colnames(managers[, 1:6]),
    factor.names = colnames(managers[, 7:9]),
    rf.name = colnames(managers[, 10]),
    data = managers
  )
  expect_error(portSdDecomp(fit, weights = c(0.5, 0.5)),
               "incorrect number of weights")
})

test_that("portVaRDecomp errors on unnamed weights", {
  fit <- fitTsfm(
    asset.names = colnames(managers[, 1:6]),
    factor.names = colnames(managers[, 7:9]),
    rf.name = colnames(managers[, 10]),
    data = managers
  )
  wts <- runif(6)
  wts <- wts / sum(wts)
  expect_error(portVaRDecomp(fit, wts),
               "names of weights vector should match")
})

test_that("portEsDecomp errors on wrong number of weights", {
  fit <- fitTsfm(
    asset.names = colnames(managers[, 1:6]),
    factor.names = colnames(managers[, 7:9]),
    rf.name = colnames(managers[, 10]),
    data = managers
  )
  expect_error(portEsDecomp(fit, weights = c(0.5, 0.5)),
               "incorrect number of weights")
})
