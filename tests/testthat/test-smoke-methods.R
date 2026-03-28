# =============================================================================
# test-smoke-methods.R — Smoke tests for S3 accessor, summary, print, predict,
#                        plot, and reporting methods.
#
# These are NOT fixture-backed regression tests. They verify "does not crash"
# and "returns the expected type/class." Written as a Phase 1.0 safety net
# before dependency pruning adds requireNamespace() guards to these files.
# =============================================================================

# ---------------------------------------------------------------------------
# Model fitting (once per file, reused across all test blocks)
# ---------------------------------------------------------------------------

fit_ffm_style <- fitFfm(
  data = factorDataSetDjia5Yrs,
  asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
  exposure.vars = c("P2B", "EV2S")
)

fit_ffm_sector <- fitFfm(
  data = factorDataSetDjia5Yrs,
  asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
  exposure.vars = c("SECTOR", "P2B"),
  addIntercept = TRUE
)

fit_tsfm_ls <- fitTsfm(
  asset.names = colnames(managers[, 1:6]),
  factor.names = colnames(managers[, 7:9]),
  rf.name = colnames(managers[, 10]),
  data = managers
)

# ===== STEP 1: Accessor, print, and summary methods =========================

test_that("coef.ffm returns matrix with correct dimensions", {
  co <- coef(fit_ffm_style)
  expect_true(is.matrix(co))
  expect_equal(nrow(co), length(fit_ffm_style$asset.names))
  expect_equal(ncol(co), length(fit_ffm_style$exposure.vars))

  co_sec <- coef(fit_ffm_sector)
  expect_true(is.matrix(co_sec))
  expect_equal(nrow(co_sec), length(fit_ffm_sector$asset.names))
})

test_that("coef.tsfm returns data.frame with intercept + factors", {
  co <- coef(fit_tsfm_ls)
  expect_true(is.data.frame(co))
  expect_equal(colnames(co)[1], "(Intercept)")
  expect_equal(nrow(co), length(fit_tsfm_ls$asset.names))
  expect_equal(ncol(co), 1L + length(fit_tsfm_ls$factor.names))
})

test_that("residuals.ffm returns xts with correct dimensions", {
  r <- residuals(fit_ffm_style)
  expect_s3_class(r, "xts")
  expect_equal(ncol(r), length(fit_ffm_style$asset.names))
})

test_that("residuals.tsfm returns xts with correct dimensions", {
  r <- residuals(fit_tsfm_ls)
  expect_s3_class(r, "xts")
  expect_equal(ncol(r), length(fit_tsfm_ls$asset.names))
})

test_that("fitted.ffm returns xts/zoo with correct dimensions", {
  f <- fitted(fit_ffm_style)
  expect_true(is.xts(f) || is.zoo(f))
  expect_equal(ncol(f), length(fit_ffm_style$asset.names))
})

test_that("fitted.tsfm returns xts with correct dimensions", {
  f <- fitted(fit_tsfm_ls)
  expect_s3_class(f, "xts")
  expect_equal(ncol(f), length(fit_tsfm_ls$asset.names))
})

test_that("predict.ffm works with default (NULL) newdata", {
  p <- predict(fit_ffm_style)
  expect_true(is.matrix(p))
  expect_equal(nrow(p), length(fit_ffm_style$asset.names))
})

test_that("predict.tsfm works with default (NULL) newdata", {
  p <- predict(fit_tsfm_ls)
  # sapply returns a list when assets have unequal history (NA trimming)
  expect_true(is.matrix(p) || is.list(p))
  if (is.list(p)) {
    expect_equal(length(p), length(fit_tsfm_ls$asset.names))
  } else {
    expect_equal(ncol(p), length(fit_tsfm_ls$asset.names))
  }
})

test_that("print.ffm runs without error", {
  expect_no_error(capture.output(print(fit_ffm_style)))
  expect_no_error(capture.output(print(fit_ffm_sector)))
})

test_that("print.tsfm runs without error", {
  expect_no_error(capture.output(print(fit_tsfm_ls)))
})

test_that("summary.ffm returns correct class", {
  s <- summary(fit_ffm_style)
  expect_s3_class(s, "summary.ffm")
  expect_no_error(capture.output(print(s)))
})

test_that("summary.tsfm returns correct class (default SE)", {
  s <- summary(fit_tsfm_ls)
  expect_s3_class(s, "summary.tsfm")
  expect_no_error(capture.output(print(s)))
})

# ===== STEP 2: Plot method smoke tests ======================================

# All plot calls use pdf(NULL) to suppress graphical output and explicit `which`
# values to avoid the interactive menu() prompt.
# Skip corrplot-dependent group plots (7, 8) — corrplot is in Suggests.

test_that("plot.ffm group plots do not error", {
  pdf(NULL)
  on.exit(dev.off(), add = TRUE)
  # Skip 7-8 (corrplot is in Suggests, may not be installed)
  # Plot 3 needs asset.variable — test separately
  for (w in c(1:2, 4:6, 9:12)) {
    expect_no_error(plot(fit_ffm_style, which = w))
  }
  expect_no_error(
    plot(fit_ffm_style, which = 3, asset.variable = "TICKER")
  )
})

test_that("plot.ffm individual plots do not error", {
  pdf(NULL)
  on.exit(dev.off(), add = TRUE)
  asset <- fit_ffm_style$asset.names[1]
  for (w in 1:13) {
    expect_no_error(
      plot(fit_ffm_style, plot.single = TRUE, asset.name = asset, which = w)
    )
  }
})

test_that("plot.ffm works with sector model", {
  pdf(NULL)
  on.exit(dev.off(), add = TRUE)
  expect_no_error(plot(fit_ffm_sector, which = 1))
  expect_no_error(plot(fit_ffm_sector, which = 2))
  expect_no_error(plot(fit_ffm_sector, which = 12))
})

test_that("plot.tsfm group plots do not error", {
  pdf(NULL)
  on.exit(dev.off(), add = TRUE)
  # Skip 7-8 (corrplot in Suggests), skip 12 (requires single-factor model)
  # Suppress warnings from fmVaRDecomp vector recycling with unequal history
  for (w in c(1:6, 9:11)) {
    expect_no_error(suppressWarnings(plot(fit_tsfm_ls, which = w)))
  }
})

test_that("plot.tsfm individual plots do not error", {
  pdf(NULL)
  on.exit(dev.off(), add = TRUE)
  asset <- fit_tsfm_ls$asset.names[1]
  # Skip 15-17 (strucchange in Suggests), skip 19 (single-factor only)
  for (w in c(1:14, 18)) {
    expect_no_error(
      plot(fit_tsfm_ls, plot.single = TRUE, asset.name = asset, which = w)
    )
  }
})

# ===== STEP 3: Reporting function smoke tests ================================

# repExposures and repReturn use menu() when which = NULL and isPlot = TRUE.
# Always pass explicit `which` for the plot path.
#
# repReturn/repExposures have a pre-existing subscript bug on the small DJIA
# dataset; use the 145-stock WLS model which matches their intended use case.

fit_ffm_wls <- fitFfm(
  data = dat145,
  asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
  exposure.vars = c("SECTOR", "ROE", "BP", "PM12M1M", "SIZE", "ANNVOL1M", "EP"),
  addIntercept = TRUE, fit.method = "WLS", z.score = "crossSection"
)

test_that("repExposures runs without error (computation only)", {
  expect_no_error(
    capture.output(repExposures(fit_ffm_wls, isPlot = FALSE, isPrint = TRUE))
  )
})

test_that("repExposures plots without error", {
  pdf(NULL)
  on.exit(dev.off(), add = TRUE)
  # which = 1 (time series), 2 (boxplot), 3 (barchart)
  for (w in 1:3) {
    expect_no_error(
      repExposures(fit_ffm_wls, isPlot = TRUE, isPrint = FALSE, which = w)
    )
  }
})

test_that("repReturn runs without error (computation only)", {
  expect_no_error(
    capture.output(repReturn(fit_ffm_wls, isPlot = FALSE, isPrint = TRUE))
  )
})

test_that("repReturn plots without error", {
  pdf(NULL)
  on.exit(dev.off(), add = TRUE)
  # which = 1 (decomposition), 2 (style), 3 (sector), 4 (boxplot)
  for (w in 1:4) {
    expect_no_error(
      repReturn(fit_ffm_wls, isPlot = TRUE, isPrint = FALSE, which = w)
    )
  }
})

test_that("repRisk.ffm runs without error", {
  expect_no_error(
    capture.output(repRisk(fit_ffm_style, isPrint = TRUE, isPlot = FALSE))
  )
})

test_that("repRisk.ffm plots without error", {
  pdf(NULL)
  on.exit(dev.off(), add = TRUE)
  expect_no_error(repRisk(fit_ffm_style, isPrint = FALSE, isPlot = TRUE))
})

test_that("repRisk.tsfm runs without error", {
  expect_no_error(
    suppressWarnings(
      capture.output(repRisk(fit_tsfm_ls, isPrint = TRUE, isPlot = FALSE))
    )
  )
})

test_that("repRisk.tsfm plots without error", {
  pdf(NULL)
  on.exit(dev.off(), add = TRUE)
  expect_no_error(
    suppressWarnings(repRisk(fit_tsfm_ls, isPrint = FALSE, isPlot = TRUE))
  )
})
