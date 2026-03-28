# =============================================================================
# test-riskDecomp.R — Regression tests for asset-level risk decomposition
#
# Covers: fmSdDecomp, fmVaRDecomp, fmEsDecomp on FFM style-only fit.
# =============================================================================

# --- fmSdDecomp ---
test_that("fmSdDecomp FFM reproduces fixture", {
  fix <- readRDS(test_path("fixtures", "fixture_fmSdDecomp_ffm.rds"))
  fit <- fitFfm(
    data = factorDataSetDjia5Yrs,
    asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
    exposure.vars = c("P2B", "EV2S")
  )
  decomp <- fmSdDecomp(fit)
  expect_equal(decomp$Sd.fm, fix$Sd.fm, tolerance = 1e-6)
  expect_equal(decomp$mSd, fix$mSd, tolerance = 1e-6)
  expect_equal(decomp$cSd, fix$cSd, tolerance = 1e-6)
  expect_equal(decomp$pcSd, fix$pcSd, tolerance = 1e-6)
})

test_that("fmSdDecomp percentage contributions sum to 100", {
  fit <- fitFfm(
    data = factorDataSetDjia5Yrs,
    asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
    exposure.vars = c("P2B", "EV2S")
  )
  decomp <- fmSdDecomp(fit)
  row_sums <- rowSums(decomp$pcSd)
  expect_equal(row_sums, rep(100, length(row_sums)),
               tolerance = 1e-10, ignore_attr = TRUE)
})

# --- fmVaRDecomp ---
test_that("fmVaRDecomp FFM reproduces fixture", {
  fix <- readRDS(test_path("fixtures", "fixture_fmVaRDecomp_ffm.rds"))
  fit <- fitFfm(
    data = factorDataSetDjia5Yrs,
    asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
    exposure.vars = c("P2B", "EV2S")
  )
  decomp <- fmVaRDecomp(fit)
  expect_equal(decomp$VaR.fm, fix$VaR.fm, tolerance = 1e-6)
  expect_equal(decomp$mVaR, fix$mVaR, tolerance = 1e-6)
  expect_equal(decomp$cVaR, fix$cVaR, tolerance = 1e-6)
  expect_equal(decomp$pcVaR, fix$pcVaR, tolerance = 1e-6)
})

test_that("fmVaRDecomp percentage contributions sum to 100", {
  fit <- fitFfm(
    data = factorDataSetDjia5Yrs,
    asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
    exposure.vars = c("P2B", "EV2S")
  )
  decomp <- fmVaRDecomp(fit)
  row_sums <- rowSums(decomp$pcVaR)
  expect_equal(row_sums, rep(100, length(row_sums)),
               tolerance = 1e-10, ignore_attr = TRUE)
})

# --- fmEsDecomp ---
test_that("fmEsDecomp FFM reproduces fixture", {
  fix <- readRDS(test_path("fixtures", "fixture_fmEsDecomp_ffm.rds"))
  fit <- fitFfm(
    data = factorDataSetDjia5Yrs,
    asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
    exposure.vars = c("P2B", "EV2S")
  )
  decomp <- fmEsDecomp(fit)
  expect_equal(decomp$ES.fm, fix$ES.fm, tolerance = 1e-6)
  expect_equal(decomp$mES, fix$mES, tolerance = 1e-6)
  expect_equal(decomp$cES, fix$cES, tolerance = 1e-6)
  expect_equal(decomp$pcES, fix$pcES, tolerance = 1e-6)
})

test_that("fmEsDecomp percentage contributions sum to 100", {
  fit <- fitFfm(
    data = factorDataSetDjia5Yrs,
    asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
    exposure.vars = c("P2B", "EV2S")
  )
  decomp <- fmEsDecomp(fit)
  row_sums <- rowSums(decomp$pcES)
  expect_equal(row_sums, rep(100, length(row_sums)),
               tolerance = 1e-10, ignore_attr = TRUE)
})
