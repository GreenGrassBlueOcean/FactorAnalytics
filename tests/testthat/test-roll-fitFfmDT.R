# test-roll-fitFfmDT.R — Phase 4.3.6
# Minimal smoke test for rolling-window FFM fitting.

test_that("roll.fitFfmDT runs without error on DJIA data", {
  spec <- specFfm(
    data = factorDataSetDjia5Yrs,
    asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
    exposure.vars = c("P2B", "EV2S")
  )
  result <- roll.fitFfmDT(spec, windowSize = 36)
  expect_true(is.list(result))
  expect_true(length(result) > 0)
})
