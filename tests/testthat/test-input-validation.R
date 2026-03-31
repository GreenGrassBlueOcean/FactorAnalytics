# =============================================================================
# test-input-validation.R — Edge cases, bad inputs, and error messages
# =============================================================================

# --- fitFfm / specFfm input validation ---
# Validation of shared parameters (data, asset.var, etc.) lives in specFfm().
# fitFfm() validates only its own parameters (fit.method, resid.scaleType, etc.).

test_that("fitFfm errors on missing required arguments", {
  expect_error(fitFfm(data = factorDataSetDjia5Yrs))
})

test_that("specFfm catches basic parameter errors", {
  expect_error(specFfm(data = "not_a_df", asset.var = "TICKER",
                       ret.var = "RETURN", date.var = "DATE",
                       exposure.vars = "P2B"),
               "data must be a data.frame")
  expect_error(specFfm(data = factorDataSetDjia5Yrs, asset.var = 123,
                       ret.var = "RETURN", date.var = "DATE",
                       exposure.vars = "P2B"),
               "asset.var must be a character")
  expect_error(specFfm(data = factorDataSetDjia5Yrs, asset.var = "TICKER",
                       ret.var = "RETURN", date.var = "DATE",
                       exposure.vars = "RETURN"),
               "cannot also be an exposure")
})

test_that("specFfm catches remaining type errors (date.var, ret.var, exposure.vars, weight.var, rob.stats)", {
  djia <- factorDataSetDjia5Yrs
  expect_error(specFfm(data = djia, asset.var = "TICKER",
                       ret.var = "RETURN", date.var = 42,
                       exposure.vars = "P2B"),
               "date.var must be a character")
  expect_error(specFfm(data = djia, asset.var = "TICKER",
                       ret.var = 42, date.var = "DATE",
                       exposure.vars = "P2B"),
               "ret.var must be a character")
  expect_error(specFfm(data = djia, asset.var = "TICKER",
                       ret.var = "RETURN", date.var = "DATE",
                       exposure.vars = 42),
               "exposure.vars must be a character")
  # weight.var = 42: coerced to "42", hits column-not-found before type check
  expect_error(specFfm(data = djia, asset.var = "TICKER",
                       ret.var = "RETURN", date.var = "DATE",
                       exposure.vars = "P2B", weight.var = 42),
               "not found in data")
  expect_error(specFfm(data = djia, asset.var = "TICKER",
                       ret.var = "RETURN", date.var = "DATE",
                       exposure.vars = "P2B", rob.stats = "yes"),
               "rob.stats.*must be logical")
})

test_that("specFfm catches missing columns in data", {
  expect_error(specFfm(data = factorDataSetDjia5Yrs, asset.var = "TICKER",
                       ret.var = "RETURN", date.var = "DATE",
                       exposure.vars = "NONEXISTENT"),
               "not found in data.*NONEXISTENT")
  expect_error(specFfm(data = factorDataSetDjia5Yrs, asset.var = "BOGUS",
                       ret.var = "RETURN", date.var = "DATE",
                       exposure.vars = "P2B"),
               "not found in data.*BOGUS")
})

test_that("fitFfm validates its own parameters (not delegated to specFfm)", {
  expect_error(fitFfm(data = factorDataSetDjia5Yrs, asset.var = "TICKER",
                       ret.var = "RETURN", date.var = "DATE",
                       exposure.vars = "P2B", fit.method = "INVALID"),
               "fit.method")
  expect_error(fitFfm(data = factorDataSetDjia5Yrs, asset.var = "TICKER",
                       ret.var = "RETURN", date.var = "DATE",
                       exposure.vars = "P2B", resid.scaleType = "INVALID"),
               "resid.scaleType")
  expect_error(fitFfm(data = factorDataSetDjia5Yrs, asset.var = "TICKER",
                       ret.var = "RETURN", date.var = "DATE",
                       exposure.vars = "P2B", analysis = "INVALID"),
               "analysis")
})

# --- fitTsfm input validation ---
test_that("fitTsfm catches missing asset columns", {
  expect_error(fitTsfm(asset.names = c("HAM1", "NONEXISTENT"),
                       factor.names = "SP500.TR",
                       data = managers),
               "not found in data.*NONEXISTENT")
})

test_that("fitTsfm catches missing factor columns", {
  expect_error(fitTsfm(asset.names = "HAM1",
                       factor.names = c("SP500.TR", "BOGUS"),
                       data = managers),
               "not found in data.*BOGUS")
})

test_that("fitTsfm catches missing mkt.name column", {
  expect_error(fitTsfm(asset.names = "HAM1",
                       factor.names = "SP500.TR",
                       mkt.name = "NONEXISTENT",
                       data = managers),
               "mkt.name.*not found")
})

test_that("fitTsfm catches missing rf.name column", {
  expect_error(fitTsfm(asset.names = "HAM1",
                       factor.names = "SP500.TR",
                       rf.name = "NONEXISTENT",
                       data = managers),
               "rf.name.*not found")
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
