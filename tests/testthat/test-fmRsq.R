# =============================================================================
# test-fmRsq.R — Regression tests for R-squared computation
# =============================================================================

test_that("fmRsq reproduces fixture", {
  fix <- readRDS(test_path("fixtures", "fixture_fmRsq.rds"))
  fit <- fitFfm(
    data = dat145,
    exposure.vars = c("SECTOR", "ROE", "BP", "PM12M1M", "SIZE", "ANNVOL1M", "EP"),
    date.var = "DATE", ret.var = "RETURN", asset.var = "TICKER",
    fit.method = "WLS", z.score = "crossSection"
  )
  out <- fmRsq(fit, rsq = TRUE, rsqAdj = TRUE, isPrint = FALSE)
  expect_equal(out, fix, tolerance = 1e-10)
})

test_that("fmRsq output lengths are correct", {
  fit <- fitFfm(
    data = factorDataSetDjia5Yrs,
    asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
    exposure.vars = "SECTOR"
  )
  out1 <- fmRsq(fit, rsq = TRUE, rsqAdj = FALSE, isPrint = FALSE)
  expect_length(out1, 2)

  out2 <- fmRsq(fit, rsq = FALSE, rsqAdj = TRUE, isPrint = FALSE)
  expect_length(out2, 2)

  out3 <- fmRsq(fit, rsq = TRUE, rsqAdj = TRUE, isPrint = FALSE)
  expect_length(out3, 4)
})

test_that("fmRsq errors when both rsq and rsqAdj are FALSE", {
  fit <- fitFfm(
    data = factorDataSetDjia5Yrs,
    asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
    exposure.vars = "SECTOR"
  )
  expect_error(fmRsq(fit, rsq = FALSE, rsqAdj = FALSE),
               "Invalid arguments: Inputs rsq and rsqAdj cannot be False")
})
