# =============================================================================
# test-input-validation.R — Edge cases, bad inputs, and error messages
# =============================================================================

# --- fitFfm input validation ---
test_that("fitFfm errors on missing required arguments", {
  expect_error(fitFfm(data = factorDataSetDjia5Yrs))
})

# --- portDecomp weight validation ---
test_that("portSdDecomp rejects wrong weight count for FFM", {
  fit <- fitFfm(
    data = dat145,
    exposure.vars = c("SECTOR", "ROE", "BP", "PM12M1M", "SIZE", "ANNVOL1M", "EP"),
    date.var = "DATE", ret.var = "RETURN", asset.var = "TICKER",
    fit.method = "WLS", z.score = "crossSection"
  )
  expect_error(portSdDecomp(fit, weights = c(0.5, 0.5)),
               "incorrect number of weights")
})

test_that("portVaRDecomp rejects wrong weight count for FFM", {
  fit <- fitFfm(
    data = dat145,
    exposure.vars = c("SECTOR", "ROE", "BP", "PM12M1M", "SIZE", "ANNVOL1M", "EP"),
    date.var = "DATE", ret.var = "RETURN", asset.var = "TICKER",
    fit.method = "WLS", z.score = "crossSection"
  )
  expect_error(portVaRDecomp(fit, weights = c(0.5, 0.5)),
               "incorrect number of weights")
})

test_that("portEsDecomp rejects wrong weight count for FFM", {
  fit <- fitFfm(
    data = dat145,
    exposure.vars = c("SECTOR", "ROE", "BP", "PM12M1M", "SIZE", "ANNVOL1M", "EP"),
    date.var = "DATE", ret.var = "RETURN", asset.var = "TICKER",
    fit.method = "WLS", z.score = "crossSection"
  )
  expect_error(portEsDecomp(fit, weights = c(0.5, 0.5)),
               "incorrect number of weights")
})

# --- repExposures / repReturn weight validation ---
test_that("repExposures rejects wrong weight count", {
  fit <- fitFfm(
    data = dat145,
    exposure.vars = c("SECTOR", "ROE", "BP", "PM12M1M", "SIZE", "ANNVOL1M", "EP"),
    date.var = "DATE", ret.var = "RETURN", asset.var = "TICKER",
    fit.method = "WLS", z.score = "crossSection"
  )
  expect_error(
    repExposures(fit, weights = c(0.5, 0.5), isPlot = TRUE, which = 1),
    "incorrect number of weights"
  )
})

test_that("repReturn rejects wrong weight count", {
  fit <- fitFfm(
    data = dat145,
    exposure.vars = c("SECTOR", "ROE", "BP", "PM12M1M", "SIZE", "ANNVOL1M", "EP"),
    date.var = "DATE", ret.var = "RETURN", asset.var = "TICKER",
    fit.method = "WLS", z.score = "crossSection"
  )
  expect_error(
    repReturn(fit, weights = c(0.5, 0.5), isPlot = TRUE, which = 1),
    "incorrect number of weights"
  )
})
