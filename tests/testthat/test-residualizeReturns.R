# test-residualizeReturns.R
# Tests for residualizeReturns() + print.ffmSpec conditional messages
#
# Covers ~53 lines in fitFfmDT.R:
#   - residualizeReturns() lines 536-599 (benchmark/rfRate merge, excess return
#     regression, yVar update, residualizedReturns flag)
#   - print.ffmSpec lines 1530-1535 (conditional messages for
#     standardized/residualized returns)

library(testthat)
library(xts)

# ── Synthetic benchmark + rfRate matching dat145 dates ──
dates_145 <- sort(unique(as.Date(dat145$DATE)))  # 60 monthly dates

set.seed(4817)
bench_vals <- rnorm(length(dates_145), mean = 0.005, sd = 0.04)
benchmark_xts <- xts(bench_vals, order.by = dates_145)
colnames(benchmark_xts) <- "MKT"

rf_vals <- rep(0.002, length(dates_145))
rfRate_xts <- xts(rf_vals, order.by = dates_145)
colnames(rfRate_xts) <- "RF"

spec_for_resid <- specFfm(
  data = dat145, asset.var = "TICKER", ret.var = "RETURN",
  date.var = "DATE", exposure.vars = c("SECTOR", "ROE", "BP")
)

# ── Core functionality ──
test_that("residualizeReturns modifies specObj correctly", {
  res <- residualizeReturns(spec_for_resid, benchmark_xts, rfRate_xts)

  expect_s3_class(res, "ffmSpec")
  expect_equal(res$yVar, "ResidualizedReturn")
  expect_true(res$residualizedReturns)
  expect_false(res$standardizedReturns)

  # ResidualizedReturn column should exist in dataDT

  expect_true("ResidualizedReturn" %in% colnames(res$dataDT))
  expect_true("ExcessReturn" %in% colnames(res$dataDT))

  # Benchmark and rfRate columns merged in
  expect_true("MKT" %in% colnames(res$dataDT))
  expect_true("RF" %in% colnames(res$dataDT))
  expect_equal(res$benchmark.var, "MKT")
  expect_equal(res$rfRate.var, "RF")

  # Residualized returns should differ from raw returns
  raw <- res$dataDT[["RawReturn"]]
  resids <- res$dataDT[["ResidualizedReturn"]]
  expect_false(isTRUE(all.equal(raw, resids)),
               "Residualized returns should differ from raw returns")

  # Residualized returns should have smaller variance than excess returns
  # (regression removes systematic benchmark component)
  excess <- res$dataDT[["ExcessReturn"]]
  expect_lt(var(resids, na.rm = TRUE), var(excess, na.rm = TRUE))
})

test_that("residualizeReturns with isBenchExcess=TRUE skips benchmark adjustment", {
  res_excess <- residualizeReturns(spec_for_resid, benchmark_xts, rfRate_xts,
                                   isBenchExcess = TRUE)
  res_raw <- residualizeReturns(spec_for_resid, benchmark_xts, rfRate_xts,
                                isBenchExcess = FALSE)

  # When isBenchExcess=TRUE, benchmark is NOT adjusted for rf
  # The MKT column should differ between the two
  mkt_excess <- res_excess$dataDT[["MKT"]]
  mkt_raw <- res_raw$dataDT[["MKT"]]
  expect_false(isTRUE(all.equal(mkt_excess, mkt_raw)),
               "Benchmark should differ when isBenchExcess toggles")
})

test_that("residualizeReturns does not mutate original specObj", {
  orig_yVar <- spec_for_resid$yVar
  orig_flag <- spec_for_resid$residualizedReturns
  residualizeReturns(spec_for_resid, benchmark_xts, rfRate_xts)
  expect_equal(spec_for_resid$yVar, orig_yVar)
  expect_equal(spec_for_resid$residualizedReturns, orig_flag)
})

# ── Error paths ──
test_that("residualizeReturns rejects non-xts benchmark", {
  expect_error(
    residualizeReturns(spec_for_resid, as.data.frame(benchmark_xts), rfRate_xts),
    "benchmark must be an xts"
  )
})

test_that("residualizeReturns rejects non-xts rfRate", {
  expect_error(
    residualizeReturns(spec_for_resid, benchmark_xts, as.data.frame(rfRate_xts)),
    "rfRate must be an xts"
  )
})

test_that("residualizeReturns rejects benchmark without colnames", {
  bench_noname <- benchmark_xts
  colnames(bench_noname) <- NULL
  expect_error(
    residualizeReturns(spec_for_resid, bench_noname, rfRate_xts),
    "column names"
  )
})

test_that("residualizeReturns rejects rfRate without colnames", {
  rf_noname <- rfRate_xts
  colnames(rf_noname) <- NULL
  expect_error(
    residualizeReturns(spec_for_resid, benchmark_xts, rf_noname),
    "column name"
  )
})

# ── print.ffmSpec conditional messages ──
test_that("print.ffmSpec shows 'residualized but not standardized'", {
  res <- residualizeReturns(spec_for_resid, benchmark_xts, rfRate_xts)
  out <- capture.output(print(res))
  expect_true(any(grepl("residualized but not standardized", out)))
  expect_true(any(grepl("ResidualizedReturn", out)))
})

test_that("print.ffmSpec shows 'standardized but not residualized'", {
  skip_if_not_installed("rugarch")
  std <- standardizeReturns(spec_for_resid)
  out <- capture.output(print(std))
  expect_true(any(grepl("standardized but not residualized", out)))
  expect_true(any(grepl("StandardizedReturns", out)))
})

test_that("print.ffmSpec shows 'residualized and standardized'", {
  skip_if_not_installed("rugarch")
  res <- residualizeReturns(spec_for_resid, benchmark_xts, rfRate_xts)
  both <- standardizeReturns(res)
  out <- capture.output(print(both))
  expect_true(any(grepl("residualized and standardized", out)))
})

# ── Residualized specObj can be fit through internal pipeline ──
test_that("fitFfmDT + extractRegressionStats works on residualized specObj", {
  res <- residualizeReturns(spec_for_resid, benchmark_xts, rfRate_xts)
  res <- standardizeExposures(res)

  mdlFit <- fitFfmDT(res, fit.method = "LS")
  regStats <- extractRegressionStats(res, mdlFit)
  result <- convert(res, mdlFit, regStats)

  expect_s3_class(result, "ffm")
  expect_true(nrow(result$factor.returns) > 0)
  expect_true(all(!is.na(result$r2)))
  # yVar should reflect residualized returns
  expect_equal(res$yVar, "ResidualizedReturn")
})
