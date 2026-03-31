# test-residualizeReturns.R
# Tests for specFfm helper functions: residualizeReturns(), standardizeReturns(),
# lagExposures(), and print.ffmSpec conditional messages.
#
# Covers lines in fitFfmDT.R:
#   - residualizeReturns() lines 536-599
#   - standardizeReturns() lines 613-672
#   - lagExposures() lines 385-410
#   - print.ffmSpec lines 1530-1535

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
  std <- standardizeReturns(spec_for_resid)
  out <- capture.output(print(std))
  expect_true(any(grepl("standardized but not residualized", out)))
  expect_true(any(grepl("StandardizedReturns", out)))
})

test_that("print.ffmSpec shows 'residualized and standardized'", {
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


# ═══════════════════════════════════════════════════════════════════════════════
# standardizeReturns() tests
# Covers ~50 lines in fitFfmDT.R (lines 613-672)
# ═══════════════════════════════════════════════════════════════════════════════

# ── Core functionality ──
test_that("standardizeReturns modifies specObj correctly", {
  std <- standardizeReturns(spec_for_resid)

  expect_s3_class(std, "ffmSpec")
  expect_equal(std$yVar, "StandardizedReturns")
  expect_true(std$standardizedReturns)
  expect_false(std$residualizedReturns)

  expect_true("StandardizedReturns" %in% colnames(std$dataDT))
  expect_true("sigmaGarch" %in% colnames(std$dataDT))
  # Temp columns cleaned up
  expect_false("sdReturns" %in% colnames(std$dataDT))
  expect_false("ts" %in% colnames(std$dataDT))
})

test_that("StandardizedReturns equals RawReturn / sigmaGarch", {
  std <- standardizeReturns(spec_for_resid)
  raw <- std$dataDT[["RawReturn"]]
  sigma <- std$dataDT[["sigmaGarch"]]
  std_ret <- std$dataDT[["StandardizedReturns"]]
  expect_equal(raw / sigma, std_ret)
})

test_that("sigmaGarch matches manual GARCH(1,1) recursion", {
  alpha <- 0.1; beta_g <- 0.81
  std <- standardizeReturns(spec_for_resid,
                            GARCH.params = list(omega = 0.09, alpha = alpha,
                                                beta = beta_g))

  # Pick one asset and verify the recursion
  dt <- data.table::copy(std$dataDT)
  one <- dt[dt[[spec_for_resid$asset.var]] == "AA"]
  data.table::setorderv(one, spec_for_resid$date.var)

  sd_ret <- sd(one$RawReturn, na.rm = TRUE)
  omega <- (1 - alpha - beta_g) * sd_ret^2
  n <- nrow(one)
  sigma2 <- numeric(n)
  sigma2[1] <- omega + alpha * one$RawReturn[1]^2
  for (i in 2:n) {
    sigma2[i] <- omega + alpha * one$RawReturn[i]^2 + beta_g * sigma2[i - 1]
  }
  expect_equal(sqrt(sigma2), one$sigmaGarch, tolerance = 1e-12)
})

test_that("sigmaGarch values are strictly positive", {
  std <- standardizeReturns(spec_for_resid)
  expect_true(all(std$dataDT$sigmaGarch > 0))
})

test_that("custom GARCH params produce different results", {
  std_default <- standardizeReturns(spec_for_resid)
  std_custom <- standardizeReturns(
    spec_for_resid,
    GARCH.params = list(omega = 0.05, alpha = 0.15, beta = 0.75)
  )
  expect_false(
    isTRUE(all.equal(std_default$dataDT$sigmaGarch,
                     std_custom$dataDT$sigmaGarch)),
    "Different GARCH params should produce different volatilities"
  )
})

test_that("standardizeReturns does not mutate original specObj", {
  orig_yVar <- spec_for_resid$yVar
  orig_flag <- spec_for_resid$standardizedReturns
  orig_ncol <- ncol(spec_for_resid$dataDT)
  standardizeReturns(spec_for_resid)
  expect_equal(spec_for_resid$yVar, orig_yVar)
  expect_equal(spec_for_resid$standardizedReturns, orig_flag)
  expect_equal(ncol(spec_for_resid$dataDT), orig_ncol)
})

test_that("standardized specObj can be fit through internal pipeline", {
  std <- standardizeReturns(spec_for_resid)
  std <- standardizeExposures(std)

  mdlFit <- fitFfmDT(std, fit.method = "LS")
  regStats <- extractRegressionStats(std, mdlFit)
  result <- convert(std, mdlFit, regStats)

  expect_s3_class(result, "ffm")
  expect_true(nrow(result$factor.returns) > 0)
  expect_true(all(!is.na(result$r2)))
})


# ═══════════════════════════════════════════════════════════════════════════════
# lagExposures() tests
# Covers ~25 lines in fitFfmDT.R (lines 385-410)
# ═══════════════════════════════════════════════════════════════════════════════

spec_for_lag <- specFfm(
  data = dat145, asset.var = "TICKER", ret.var = "RETURN",
  date.var = "DATE", exposure.vars = c("SECTOR", "ROE", "BP")
)

test_that("lagExposures sets lagged flag and drops first period", {
  n_assets <- length(unique(spec_for_lag$dataDT$TICKER))
  n_dates_before <- length(unique(spec_for_lag$dataDT$DATE))
  n_rows_before <- nrow(spec_for_lag$dataDT)

  lagged <- lagExposures(spec_for_lag)

  expect_true(lagged$lagged)
  n_dates_after <- length(unique(lagged$dataDT$DATE))
  expect_equal(n_dates_after, n_dates_before - 1L)
  expect_equal(nrow(lagged$dataDT), n_rows_before - n_assets)
})

test_that("lagExposures shifts numeric exposures by one period", {
  lagged <- lagExposures(spec_for_lag)

  orig <- data.table::copy(spec_for_lag$dataDT)
  lag_dt <- data.table::copy(lagged$dataDT)
  data.table::setorderv(orig, c("TICKER", "DATE"))
  data.table::setorderv(lag_dt, c("TICKER", "DATE"))

  aa_orig <- orig[TICKER == "AA"]
  aa_lag <- lag_dt[TICKER == "AA"]

  # Lagged period 1 (date index 2) should have original period 1 values
  expect_equal(aa_lag$ROE[1], aa_orig$ROE[1])
  expect_equal(aa_lag$BP[1], aa_orig$BP[1])
  # Lagged period 2 should have original period 2 values
  expect_equal(aa_lag$ROE[2], aa_orig$ROE[2])
})

test_that("lagExposures also shifts character exposures", {
  lagged <- lagExposures(spec_for_lag)

  orig <- data.table::copy(spec_for_lag$dataDT)
  lag_dt <- data.table::copy(lagged$dataDT)
  data.table::setorderv(orig, c("TICKER", "DATE"))
  data.table::setorderv(lag_dt, c("TICKER", "DATE"))

  aa_orig <- orig[TICKER == "AA"]
  aa_lag <- lag_dt[TICKER == "AA"]

  # SECTOR at lagged date 2 should be original SECTOR at date 1
  expect_equal(aa_lag$SECTOR[1], aa_orig$SECTOR[1])
})

test_that("lagExposures does not mutate original specObj", {
  orig_nrow <- nrow(spec_for_lag$dataDT)
  orig_flag <- spec_for_lag$lagged
  lagExposures(spec_for_lag)
  expect_equal(nrow(spec_for_lag$dataDT), orig_nrow)
  expect_equal(spec_for_lag$lagged, orig_flag)
})

test_that("lagExposures preserves key and idx column", {
  lagged <- lagExposures(spec_for_lag)
  expect_equal(data.table::key(lagged$dataDT), c("TICKER", "DATE"))
  expect_true("idx" %in% colnames(lagged$dataDT))
  # idx should restart from 1 for each asset
  idx_mins <- lagged$dataDT[, min(idx), by = TICKER]$V1
  expect_true(all(idx_mins == 1L))
})
