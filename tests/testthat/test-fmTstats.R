# =============================================================================
# test-fmTstats.R — Tests for t-statistics computation and plotting
# =============================================================================

# ── 1. Fixture regression (existing) ─────────────────────────────────────────

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

# ── 2. Structure tests ───────────────────────────────────────────────────────

test_that("fmTstats returns correct structure (sector model)", {
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

test_that("fmTstats works with style-only model (Branch 2 / else path)", {
  # Style-only model has n.expo.char == 0, taking the else branch (lines 155-162)
  fit <- fitFfm(
    data = factorDataSetDjia5Yrs,
    asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
    exposure.vars = c("P2B", "EV2S")
  )
  out <- fmTstats(fit, isPlot = FALSE)
  expect_type(out, "list")
  expect_length(out, 2)
  expect_equal(nrow(out$tstats), length(fit$time.periods))
  expect_equal(ncol(out$tstats), length(fit$factor.names))
  expect_equal(out$z.alpha, 1.96)
})

test_that("fmTstats isPrint=TRUE prints output", {
  fit <- fitFfm(
    data = factorDataSetDjia5Yrs,
    asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
    exposure.vars = c("P2B", "EV2S")
  )
  expect_output(fmTstats(fit, isPlot = FALSE, isPrint = TRUE))
})

# ── 3. Input validation ──────────────────────────────────────────────────────

test_that("fmTstats rejects non-ffm objects", {
  expect_error(fmTstats(list(a = 1)), "Invalid argument")
})

# ── 4. Plotting smoke tests ──────────────────────────────────────────────────

test_that("fmTstats tStats plot works", {
  fit <- fitFfm(
    data = factorDataSetDjia5Yrs,
    asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
    exposure.vars = c("SECTOR", "P2B")
  )
  pdf(NULL)
  on.exit(dev.off(), add = TRUE)
  expect_no_error(fmTstats(fit, isPlot = TRUE, whichPlot = "tStats"))
})

test_that("fmTstats tStats plot with title=FALSE", {
  fit <- fitFfm(
    data = factorDataSetDjia5Yrs,
    asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
    exposure.vars = c("SECTOR", "P2B")
  )
  pdf(NULL)
  on.exit(dev.off(), add = TRUE)
  expect_no_error(fmTstats(fit, isPlot = TRUE, whichPlot = "tStats", title = FALSE))
})

test_that("fmTstats significantTstatsV plot works", {
  fit <- fitFfm(
    data = factorDataSetDjia5Yrs,
    asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
    exposure.vars = c("SECTOR", "P2B")
  )
  pdf(NULL)
  on.exit(dev.off(), add = TRUE)
  expect_no_error(fmTstats(fit, isPlot = TRUE, whichPlot = "significantTstatsV"))
})

test_that("fmTstats significantTstatsH plot works", {
  fit <- fitFfm(
    data = factorDataSetDjia5Yrs,
    asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
    exposure.vars = c("SECTOR", "P2B")
  )
  pdf(NULL)
  on.exit(dev.off(), add = TRUE)
  expect_no_error(fmTstats(fit, isPlot = TRUE, whichPlot = "significantTstatsH"))
})

test_that("fmTstats 'all' whichPlot works", {
  fit <- fitFfm(
    data = factorDataSetDjia5Yrs,
    asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
    exposure.vars = c("SECTOR", "P2B")
  )
  pdf(NULL)
  on.exit(dev.off(), add = TRUE)
  expect_no_error(fmTstats(fit, isPlot = TRUE, whichPlot = "all"))
})

test_that("fmTstats significantTstatsLikert plot works", {
  skip_if_not_installed("HH")
  fit <- fitFfm(
    data = factorDataSetDjia5Yrs,
    asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
    exposure.vars = c("SECTOR", "P2B")
  )
  pdf(NULL)
  on.exit(dev.off(), add = TRUE)
  expect_no_error(
    fmTstats(fit, isPlot = TRUE, whichPlot = "significantTstatsLikert")
  )
})
