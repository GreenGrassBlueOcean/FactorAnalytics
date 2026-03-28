# =============================================================================
# test-fmTstats.R — Regression tests for t-statistics computation
# =============================================================================

test_that("fmTstats reproduces fixture", {
  fix <- readRDS(test_path("fixtures", "fixture_fmTstats.rds"))
  fit <- fitFfm(
    data = dat145,
    exposure.vars = c("SECTOR", "ROE", "BP", "PM12M1M", "SIZE", "ANNVOL1M", "EP"),
    date.var = "DATE", ret.var = "RETURN", asset.var = "TICKER",
    fit.method = "WLS", z.score = "crossSection"
  )
  out <- fmTstats(fit, isPlot = FALSE)
  expect_equal(out, fix, tolerance = 1e-10)
})

test_that("fmTstats returns correct structure", {
  fit <- fitFfm(
    data = factorDataSetDjia5Yrs,
    asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
    exposure.vars = "SECTOR"
  )
  out <- fmTstats(fit, isPlot = FALSE)
  expect_type(out, "list")
  expect_length(out, 2)
  expect_equal(nrow(out$tstats), length(fit$time.periods))
})
