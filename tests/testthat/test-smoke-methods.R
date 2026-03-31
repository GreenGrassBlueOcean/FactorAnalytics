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

# ---------------------------------------------------------------------------
# predict.ffm with newdata — walk-forward regression tests (Phase 3 prep)
# Verifies stripped lm objects support predict(fit, newdata = ...) correctly.
# ---------------------------------------------------------------------------

test_that("predict.ffm with newdata works on style-only model", {
  set.seed(8193)
  n_pred <- 15
  newdata <- data.frame(P2B = rnorm(n_pred), EV2S = rnorm(n_pred))

  p <- predict(fit_ffm_style, newdata = newdata)
  expect_true(is.matrix(p))
  expect_equal(nrow(p), n_pred)
  expect_equal(ncol(p), length(names(fit_ffm_style$factor.fit)))
})

test_that("predict.ffm with newdata + pred.date matches manual X %*% beta (style)", {
  dates <- names(fit_ffm_style$factor.fit)
  test_date <- dates[30]

  set.seed(8193)
  n_pred <- 15
  newdata <- data.frame(P2B = rnorm(n_pred), EV2S = rnorm(n_pred))

  pred <- predict(fit_ffm_style, newdata = newdata, pred.date = test_date)
  expect_true(is.matrix(pred))
  expect_equal(nrow(pred), n_pred)

  beta <- coef(fit_ffm_style$factor.fit[[test_date]])
  X <- as.matrix(newdata[, names(beta), drop = FALSE])
  manual <- as.numeric(X %*% beta)

  expect_equal(as.numeric(pred), manual, tolerance = 1e-12)
})

test_that("predict.ffm with newdata works on sector model (model.matrix columns)", {
  # Sector models expand categoricals via model.matrix into V1, V2, ... columns.
  # newdata must use those column names, not the original factor variable.
  lm1 <- fit_ffm_sector$factor.fit[[1]]
  coef_names <- names(coef(lm1))

  set.seed(4271)
  n_pred <- 10
  newdata <- as.data.frame(
    matrix(rnorm(n_pred * length(coef_names)), nrow = n_pred,
           dimnames = list(NULL, coef_names))
  )

  p <- predict(fit_ffm_sector, newdata = newdata)
  expect_true(is.matrix(p))
  expect_equal(nrow(p), n_pred)
})

test_that("predict.ffm with newdata + pred.date matches manual X %*% beta (sector)", {
  dates <- names(fit_ffm_sector$factor.fit)
  test_date <- dates[30]

  lm_date <- fit_ffm_sector$factor.fit[[test_date]]
  beta <- coef(lm_date)
  coef_names <- names(beta)

  set.seed(4271)
  n_pred <- 10
  newdata <- as.data.frame(
    matrix(rnorm(n_pred * length(coef_names)), nrow = n_pred,
           dimnames = list(NULL, coef_names))
  )

  pred <- predict(fit_ffm_sector, newdata = newdata, pred.date = test_date)
  expect_true(is.matrix(pred))
  expect_equal(nrow(pred), n_pred)

  # No intercept in sector model — direct multiplication
  X <- as.matrix(newdata[, coef_names, drop = FALSE])
  manual <- as.numeric(X %*% beta)

  expect_equal(as.numeric(pred), manual, tolerance = 1e-12)
})

# ---------------------------------------------------------------------------
# Phase 3.0 — char_levels slot + auto-expansion for sector models
# ---------------------------------------------------------------------------

test_that("ffm object stores char_levels for sector model", {
  expect_true(!is.null(fit_ffm_sector$char_levels))
  expect_named(fit_ffm_sector$char_levels, "SECTOR")
  expect_identical(
    fit_ffm_sector$char_levels[["SECTOR"]],
    levels(factor(fit_ffm_sector$data$SECTOR))
  )
})

test_that("ffm object has empty char_levels for style-only model", {
  expect_identical(fit_ffm_style$char_levels, list())
})

test_that("predict.ffm with original SECTOR column works (sector model)", {
  dates <- names(fit_ffm_sector$factor.fit)
  test_date <- dates[30]

  set.seed(5017)
  n_pred <- 10
  sectors <- fit_ffm_sector$char_levels[["SECTOR"]]
  newdata <- data.frame(
    SECTOR = sample(sectors, n_pred, replace = TRUE),
    P2B = rnorm(n_pred)
  )

  pred <- predict(fit_ffm_sector, newdata = newdata, pred.date = test_date)
  expect_true(is.matrix(pred))
  expect_equal(nrow(pred), n_pred)

  # Cross-validate: manually expand and predict
  expanded <- FactorAnalytics:::expand_newdata_ffm(fit_ffm_sector, newdata)
  manual <- predict(fit_ffm_sector$factor.fit[[test_date]], newdata = expanded)
  expect_equal(as.numeric(pred), as.numeric(manual), tolerance = 1e-12)
})

test_that("predict.ffm still works with pre-expanded V1..Vk newdata (sector)", {
  lm1 <- fit_ffm_sector$factor.fit[[1]]
  coef_names <- names(coef(lm1))
  set.seed(4271)
  n_pred <- 10
  newdata <- as.data.frame(
    matrix(rnorm(n_pred * length(coef_names)), nrow = n_pred,
           dimnames = list(NULL, coef_names))
  )
  expect_no_error(predict(fit_ffm_sector, newdata = newdata))
})

test_that("predict.ffm errors on unknown sector level", {
  newdata <- data.frame(SECTOR = "NONEXISTENT", P2B = 0.5)
  expect_error(
    predict(fit_ffm_sector, newdata = newdata),
    "unknown levels"
  )
})

test_that("predict.ffm errors when newdata is missing numeric exposure", {
  newdata <- data.frame(SECTOR = "COSTAP")
  expect_error(
    predict(fit_ffm_sector, newdata = newdata),
    "missing numeric exposure"
  )
})

test_that("predict.ffm handles NA in numeric exposure without row-dropping", {
  sectors <- fit_ffm_sector$char_levels[["SECTOR"]]
  newdata <- data.frame(
    SECTOR = sectors[1:3],
    P2B = c(1.5, NA, -0.3)
  )
  pred <- predict(fit_ffm_sector, newdata = newdata,
                  pred.date = names(fit_ffm_sector$factor.fit)[1])
  expect_equal(nrow(pred), 3L)
  expect_true(is.na(pred[2, 1]))
})

test_that("predict.ffm works when newdata has only a subset of sectors", {
  sectors <- fit_ffm_sector$char_levels[["SECTOR"]]
  newdata <- data.frame(
    SECTOR = sectors[1:2],
    P2B = c(1.0, 2.0)
  )
  pred <- predict(fit_ffm_sector, newdata = newdata,
                  pred.date = names(fit_ffm_sector$factor.fit)[1])
  expect_true(is.matrix(pred))
  expect_equal(nrow(pred), 2L)
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

# ── plot.ffm: additional coverage ─────────────────────────────────────────────

test_that("plot.ffm group plots with character a.sub work (a.sub bug regression)", {
  pdf(NULL)
  on.exit(dev.off(), add = TRUE)
  # This exercises the fixed a.sub assignment (was f.sub <- ... instead of a.sub <-)
  assets <- fit_ffm_style$asset.names[1:3]
  expect_no_error(
    plot(fit_ffm_style, which = 1, a.sub = assets)
  )
})

test_that("plot.ffm group plots with character f.sub work", {
  pdf(NULL)
  on.exit(dev.off(), add = TRUE)
  expect_no_error(
    plot(fit_ffm_style, which = 2, f.sub = fit_ffm_style$factor.names[1])
  )
})

test_that("plot.ffm group plots 7-8 (corrplot) work", {
  skip_if_not_installed("corrplot")
  pdf(NULL)
  on.exit(dev.off(), add = TRUE)
  for (w in 7:8) {
    expect_no_error(suppressWarnings(plot(fit_ffm_style, which = w)))
  }
})

test_that("plot.ffm single-asset error when asset.name missing", {
  expect_error(
    plot(fit_ffm_style, plot.single = TRUE, which = 1),
    "asset.name"
  )
})

test_that("plot.tsfm group plots with character a.sub work (a.sub bug regression)", {
  pdf(NULL)
  on.exit(dev.off(), add = TRUE)
  assets <- fit_tsfm_ls$asset.names[1:3]
  expect_no_error(
    plot(fit_tsfm_ls, which = 1, a.sub = assets)
  )
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

# ── plot.tsfm: additional coverage ─────────────────────────────────────────────

test_that("plot.tsfm individual plots 15-17 (strucchange) work", {
  skip_if_not_installed("strucchange")
  pdf(NULL)
  on.exit(dev.off(), add = TRUE)
  asset <- fit_tsfm_ls$asset.names[1]
  for (w in 15:17) {
    expect_no_error(
      plot(fit_tsfm_ls, plot.single = TRUE, asset.name = asset, which = w)
    )
  }
})

test_that("plot.tsfm individual plot 12 (skew-t density) works", {
  skip_if_not_installed("sn")
  pdf(NULL)
  on.exit(dev.off(), add = TRUE)
  asset <- fit_tsfm_ls$asset.names[1]
  expect_no_error(
    plot(fit_tsfm_ls, plot.single = TRUE, asset.name = asset, which = 12)
  )
})

test_that("plot.tsfm individual plot 19 works with single-factor model", {
  fit_1f <- fitTsfm(
    asset.names = colnames(managers)[1:3],
    factor.names = colnames(managers)[7],
    rf.name = colnames(managers)[10],
    data = managers
  )
  pdf(NULL)
  on.exit(dev.off(), add = TRUE)
  expect_no_error(
    plot(fit_1f, plot.single = TRUE, asset.name = fit_1f$asset.names[1], which = 19)
  )
})

test_that("plot.tsfm group plot 12 works with single-factor model", {
  fit_1f <- fitTsfm(
    asset.names = colnames(managers)[1:3],
    factor.names = colnames(managers)[7],
    rf.name = colnames(managers)[10],
    data = managers
  )
  pdf(NULL)
  on.exit(dev.off(), add = TRUE)
  expect_no_error(
    plot(fit_1f, which = 12, a.sub = 1:3, f.sub = 1)
  )
})

test_that("plot.tsfm individual plot 18 works with DLS model", {
  # Use single factor to avoid multi-panel plot.zoo prompting for input
  fit_dls <- fitTsfm(
    asset.names = colnames(managers)[1:3],
    factor.names = colnames(managers)[7],
    rf.name = colnames(managers)[10],
    data = managers,
    fit.method = "DLS"
  )
  pdf(NULL)
  on.exit(dev.off(), add = TRUE)
  expect_no_error(
    plot(fit_dls, plot.single = TRUE, asset.name = fit_dls$asset.names[1], which = 18)
  )
})

test_that("plot.tsfm individual plot 18 works with Robust model", {
  skip_if_not_installed("RobStatTM")
  # Use single factor to avoid multi-panel plot.zoo prompting for input
  fit_rob <- fitTsfm(
    asset.names = colnames(managers)[1:3],
    factor.names = colnames(managers)[7],
    rf.name = colnames(managers)[10],
    data = managers,
    fit.method = "Robust"
  )
  pdf(NULL)
  on.exit(dev.off(), add = TRUE)
  expect_no_error(
    plot(fit_rob, plot.single = TRUE, asset.name = fit_rob$asset.names[1], which = 18)
  )
})

test_that("plot.tsfm group plots with character f.sub work", {
  pdf(NULL)
  on.exit(dev.off(), add = TRUE)
  expect_no_error(
    plot(fit_tsfm_ls, which = 2, f.sub = c("EDHEC.LS.EQ", "SP500.TR"))
  )
})

test_that("plot.tsfm group plots 7-8 (corrplot) work", {
  skip_if_not_installed("corrplot")
  pdf(NULL)
  on.exit(dev.off(), add = TRUE)
  for (w in 7:8) {
    expect_no_error(suppressWarnings(plot(fit_tsfm_ls, which = w)))
  }
})

# Skipping multi-plot which vector test: the plot function internally sets
# par(ask=TRUE) which triggers interactive prompts even on pdf(NULL).

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

# ── repReturn: additional coverage ─────────────────────────────────────────────

test_that("repReturn with named weights works", {
  wts <- rep(1 / length(fit_ffm_wls$asset.names), length(fit_ffm_wls$asset.names))
  names(wts) <- fit_ffm_wls$asset.names
  expect_no_error(
    capture.output(
      repReturn(fit_ffm_wls, weights = wts, isPlot = FALSE, isPrint = TRUE)
    )
  )
})

test_that("repReturn plots with titleText=FALSE work", {
  pdf(NULL)
  on.exit(dev.off(), add = TRUE)
  for (w in 1:4) {
    expect_no_error(
      repReturn(fit_ffm_wls, isPlot = TRUE, isPrint = FALSE,
                which = w, titleText = FALSE)
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
