# test-vif.R — Phase 4.3.3
# Variance Inflation Factor tests.

test_that("vif returns correct structure for style model", {
  fit <- fitFfm(
    data = factorDataSetDjia5Yrs,
    asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
    exposure.vars = c("P2B", "EV2S", "MKTCAP")
  )
  v <- vif(fit, isPlot = FALSE)

  expect_true(is.list(v))
  expect_true("Mean.VIF" %in% names(v))
  # VIF mathematical lower bound is 1.0
  expect_true(all(v$Mean.VIF >= 1.0))
})

test_that("vif works on sector+style model", {
  fit <- fitFfm(
    data = factorDataSetDjia5Yrs,
    asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
    exposure.vars = c("SECTOR", "P2B", "EV2S"),
    addIntercept = TRUE
  )
  v <- vif(fit, isPlot = FALSE)
  # VIF computed only for numeric exposures
  expect_equal(length(v$Mean.VIF), 2L)
  expect_true(all(v$Mean.VIF >= 1.0))
})

test_that("vif with isPlot = TRUE runs without error", {
  fit <- fitFfm(
    data = factorDataSetDjia5Yrs,
    asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
    exposure.vars = c("P2B", "EV2S", "MKTCAP")
  )
  pdf(NULL)
  on.exit(dev.off(), add = TRUE)
  expect_no_error(vif(fit, isPlot = TRUE))
})
