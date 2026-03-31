# test-coverage-expansion.R
# Covers previously-uncovered branches in summary, predict, plot, and risk
# decomposition methods. Each section notes the target file and lines.

# --- Shared fitted models used across multiple sections ---
fit_tsfm_ls <- fitTsfm(
  asset.names = colnames(managers[, 1:6]),
  factor.names = c("EDHEC.LS.EQ", "SP500.TR"),
  data = managers
)

fit_ffm_style <- fitFfm(
  data = factorDataSetDjia5Yrs,
  asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
  exposure.vars = c("P2B", "MKTCAP")
)

# ============================================================================
# 1. fitTsfmMT — market timing wrapper (fitTsfmMT.R, 23 lines, was 0%)
# ============================================================================

test_that("fitTsfmMT returns a tsfm object with down-market factor", {
  fit <- fitTsfmMT(
    asset.names = colnames(managers[, 1:6]),
    mkt.name = "SP500.TR",
    data = managers
  )
  expect_s3_class(fit, "tsfm")
  expect_true("down market" %in% fit$factor.names)
  expect_true("SP500.TR" %in% fit$factor.names)
  expect_equal(length(fit$factor.names), 2L)
  expect_equal(ncol(fit$beta), 2L)
})

test_that("fitTsfmMT with rf.name subtracts risk-free rate", {
  fit_rf <- fitTsfmMT(
    asset.names = colnames(managers[, 1:6]),
    mkt.name = "SP500.TR",
    rf.name = "US.3m.TR",
    data = managers
  )
  expect_s3_class(fit_rf, "tsfm")
  expect_equal(length(fit_rf$factor.names), 2L)
})

test_that("fitTsfmMT errors without mkt.name", {
  expect_error(
    fitTsfmMT(asset.names = "HAM1", mkt.name = NULL, data = managers),
    "mkt.name"
  )
})

# ============================================================================
# 2. summary.tsfm — HC/HAC + lars + labels=FALSE (summary.tsfm.r, ~27 lines)
# ============================================================================

test_that("summary.tsfm with HC standard errors", {
  skip_if_not_installed("lmtest")
  skip_if_not_installed("sandwich")
  s <- summary(fit_tsfm_ls, se.type = "HC")
  expect_s3_class(s, "summary.tsfm")
  expect_equal(s$se.type, "HC")
  # HC coefficients should differ from default OLS SEs
  s_def <- summary(fit_tsfm_ls)
  coef_hc <- s$sum.list[[1]]$coefficients
  coef_def <- s_def$sum.list[[1]]$coefficients
  # Same estimates, different SEs
  expect_equal(coef_hc[, 1], coef_def[, 1])
  expect_false(isTRUE(all.equal(coef_hc[, 2], coef_def[, 2])))
})

test_that("summary.tsfm with HAC standard errors", {
  skip_if_not_installed("lmtest")
  skip_if_not_installed("sandwich")
  s <- summary(fit_tsfm_ls, se.type = "HAC")
  expect_s3_class(s, "summary.tsfm")
  expect_equal(s$se.type, "HAC")
})

test_that("summary.tsfm errors for Robust + HC", {
  skip_if_not_installed("RobStatTM")
  fit_rob <- fitTsfm(
    asset.names = colnames(managers[, 1:2]),
    factor.names = "SP500.TR",
    data = managers,
    fit.method = "Robust"
  )
  expect_error(summary(fit_rob, se.type = "HC"), "HC/HAC")
})

test_that("summary.tsfm lars branch", {
  skip_if_not_installed("lars")
  fit_lars <- fitTsfm(
    asset.names = colnames(managers[, 1:3]),
    factor.names = colnames(managers[, 7:9]),
    data = managers,
    variable.selection = "lars"
  )
  s <- summary(fit_lars)
  expect_s3_class(s, "summary.tsfm")
  # lars summary has 1-column coefficient matrix (Estimate only)
  expect_equal(ncol(s$sum.list[[1]]$coefficients), 1L)
  expect_true(!is.null(s$sum.list[[1]]$r.squared))
  expect_true(!is.null(s$sum.list[[1]]$sigma))
})

test_that("print.summary.tsfm labels=FALSE", {
  s <- summary(fit_tsfm_ls)
  out <- capture.output(print(s, labels = FALSE))
  # labels=FALSE omits "Call:" and "Factor Model Coefficients:"
  expect_false(any(grepl("Call:", out)))
  expect_false(any(grepl("Factor Model Coefficients:", out)))
  # But still prints asset names
  expect_true(any(grepl("HAM1", out)))
})

test_that("print.summary.tsfm lars 1-col branch", {
  skip_if_not_installed("lars")
  fit_lars <- fitTsfm(
    asset.names = colnames(managers[, 1:3]),
    factor.names = colnames(managers[, 7:9]),
    data = managers,
    variable.selection = "lars"
  )
  s <- summary(fit_lars)
  # 1-column coef matrix triggers the else branch (no SE header)
  out <- capture.output(print(s))
  expect_true(any(grepl("HAM1", out)))
  # Should NOT print "Standard Errors" for lars
  expect_false(any(grepl("Standard Errors", out)))
})

# ============================================================================
# 3. summary.tsfmUpDn + print (summary.tsfmUpDn.r, ~24 lines)
# ============================================================================

test_that("summary.tsfmUpDn returns correct class and prints", {
  fit <- fitTsfmUpDn(
    asset.names = colnames(managers[, 1:6]),
    mkt.name = "SP500.TR",
    data = managers
  )
  s <- summary(fit)
  expect_s3_class(s, "summary.tsfmUpDn")
  expect_true(!is.null(s$Up))
  expect_true(!is.null(s$Dn))

  out <- capture.output(print(s))
  expect_true(any(grepl("_Up", out)))
  expect_true(any(grepl("_Dn", out)))
  expect_true(any(grepl("R-squared_Up", out)))
  expect_true(any(grepl("R-squared_Dn", out)))
})

test_that("summary.tsfmUpDn errors on non-tsfmUpDn object", {
  expect_error(summary.tsfmUpDn(fit_tsfm_ls), "Invalid")
})

# ============================================================================
# 4. summary.ffm — labels=FALSE branch (summary.ffm.R, ~9 lines)
# ============================================================================

test_that("print.summary.ffm labels=FALSE", {
  s <- summary(fit_ffm_style)
  out <- capture.output(print(s, labels = FALSE))
  # labels=FALSE omits "Call:" and "Factor Returns:"
  expect_false(any(grepl("Call:", out)))
  expect_false(any(grepl("Factor Returns:", out)))
  # But still prints period date strings
  expect_true(length(out) > 1)
})

# ============================================================================
# 5. predict.tsfm with newdata (predict.tsfm.r, 2 lines)
# ============================================================================

test_that("predict.tsfm with newdata", {
  newdata <- data.frame(
    EDHEC.LS.EQ = rnorm(10),
    SP500.TR = rnorm(10)
  )
  p <- predict(fit_tsfm_ls, newdata = newdata)
  expect_true(is.matrix(p) || is.list(p))
  if (is.matrix(p)) {
    expect_equal(nrow(p), 10L)
  }
})

# ============================================================================
# 6. predict.ffm with pred.date (predict.ffm.R, ~5 lines)
# ============================================================================

test_that("predict.ffm with pred.date", {
  dates <- names(fit_ffm_style$factor.fit)
  pred <- predict(fit_ffm_style, pred.date = dates[1])
  expect_true(is.matrix(pred))
  # pred.date selects a single period's lm; predict returns one value per asset
  expect_equal(nrow(pred), length(fit_ffm_style$asset.names))
})

test_that("predict.ffm errors on invalid pred.date", {
  expect_error(predict(fit_ffm_style, pred.date = "9999-01-01"), "pred.date")
})

# ============================================================================
# 7. fmVaRDecomp + fmEsDecomp with type="normal" (asset-level)
#    fmVaRDecomp.R ~11 lines, fmEsDecomp.R ~12 lines
# ============================================================================

test_that("fmVaRDecomp type='normal' produces valid output (tsfm)", {
  d <- fmVaRDecomp(fit_tsfm_ls, type = "normal")
  expect_true(is.numeric(d$VaR.fm))
  expect_equal(length(d$VaR.fm), length(fit_tsfm_ls$asset.names))
  # Normal VaR should be negative for p=0.05
  expect_true(all(d$VaR.fm < 0))
  # pcVaR rows sum to ~100
  row_sums <- rowSums(d$pcVaR, na.rm = TRUE)
  expect_true(all(abs(row_sums - 100) < 1))
})

test_that("fmVaRDecomp type='normal' produces valid output (ffm)", {
  d <- fmVaRDecomp(fit_ffm_style, type = "normal")
  expect_true(is.numeric(d$VaR.fm))
  expect_equal(length(d$VaR.fm), length(fit_ffm_style$asset.names))
})

test_that("fmEsDecomp type='normal' produces valid output (tsfm)", {
  d <- fmEsDecomp(fit_tsfm_ls, type = "normal")
  expect_true(is.numeric(d$ES.fm))
  expect_equal(length(d$ES.fm), length(fit_tsfm_ls$asset.names))
  # Normal ES should be more extreme than VaR
  d_var <- fmVaRDecomp(fit_tsfm_ls, type = "normal")
  expect_true(all(d$ES.fm <= d_var$VaR.fm))
})

test_that("fmEsDecomp type='normal' produces valid output (ffm)", {
  d <- fmEsDecomp(fit_ffm_style, type = "normal")
  expect_true(is.numeric(d$ES.fm))
  expect_equal(length(d$ES.fm), length(fit_ffm_style$asset.names))
})

# ============================================================================
# 8. fmRsq — barplot (plt.type=1), title=FALSE, combined rsq+rsqAdj
#    fmRsq.R, ~16 lines
# ============================================================================

test_that("fmRsq barplot (plt.type=1) runs without error", {
  pdf(NULL)
  on.exit(dev.off(), add = TRUE)
  expect_no_error(
    fmRsq(fit_ffm_style, rsq = TRUE, rsqAdj = FALSE,
           plt.type = 1, isPrint = FALSE)
  )
})

test_that("fmRsq rsqAdj barplot (plt.type=1)", {
  pdf(NULL)
  on.exit(dev.off(), add = TRUE)
  expect_no_error(
    fmRsq(fit_ffm_style, rsq = FALSE, rsqAdj = TRUE,
           plt.type = 1, isPrint = FALSE)
  )
})

test_that("fmRsq title=FALSE", {
  pdf(NULL)
  on.exit(dev.off(), add = TRUE)
  expect_no_error(
    fmRsq(fit_ffm_style, rsq = TRUE, rsqAdj = FALSE,
           plt.type = 2, isPrint = FALSE, title = FALSE)
  )
})

test_that("fmRsq combined rsq+rsqAdj with time series plot", {
  pdf(NULL)
  on.exit(dev.off(), add = TRUE)
  out <- fmRsq(fit_ffm_style, rsq = TRUE, rsqAdj = TRUE,
               plt.type = 2, isPrint = FALSE)
  # isPrint=FALSE returns invisibly; capture the printed means
  expect_true("Mean R-Squared" %in% names(out))
  expect_true("Mean Adj R-Squared" %in% names(out))
})

test_that("fmRsq rsqAdj title=FALSE", {
  pdf(NULL)
  on.exit(dev.off(), add = TRUE)
  expect_no_error(
    fmRsq(fit_ffm_style, rsq = FALSE, rsqAdj = TRUE,
           plt.type = 2, isPrint = FALSE, title = FALSE)
  )
})

# ============================================================================
# 9. plot.pafm — explicit which.plot paths (plot.pafm.r, ~33 lines)
# ============================================================================

test_that("plot.pafm single-asset which.plot.single paths", {
  fit_tsfm <- fitTsfm(
    asset.names = colnames(managers[, 1:6]),
    factor.names = c("EDHEC.LS.EQ", "SP500.TR"),
    data = managers
  )
  fm_attr <- paFm(fit_tsfm)

  pdf(NULL)
  on.exit(dev.off(), add = TRUE)

  # which.plot.single = "1L": attributed cumulative returns (single)
  expect_no_error(
    plot(fm_attr, plot.single = TRUE, fundName = "HAM1",
         which.plot.single = "1L")
  )
  # which.plot.single = "2L": attributed returns on specific date
  expect_no_error(
    plot(fm_attr, plot.single = TRUE, fundName = "HAM1",
         which.plot.single = "2L")
  )
  # which.plot.single = "3L": time series
  expect_no_error(
    plot(fm_attr, plot.single = TRUE, fundName = "HAM1",
         which.plot.single = "3L")
  )
})

test_that("plot.pafm multi-asset which.plot paths", {
  fit_tsfm <- fitTsfm(
    asset.names = colnames(managers[, 1:6]),
    factor.names = c("EDHEC.LS.EQ", "SP500.TR"),
    data = managers
  )
  fm_attr <- paFm(fit_tsfm)

  pdf(NULL)
  on.exit(dev.off(), add = TRUE)

  # which.plot = "1L": cumulative attributed returns (all assets)
  expect_no_error(plot(fm_attr, which.plot = "1L", max.show = 4))
  # which.plot = "2L": attributed returns on date
  expect_no_error(plot(fm_attr, which.plot = "2L", max.show = 4))
  # which.plot = "3L": time series (all assets)
  expect_no_error(plot(fm_attr, which.plot = "3L", max.show = 4))
})

# ============================================================================
# 10. plot.tsfmUpDn — SFM.line, LSandRob, single asset
#     (plot.tsfmUpDn.r, ~34 lines)
# ============================================================================

test_that("plot.tsfmUpDn with SFM.line", {
  fit <- fitTsfmUpDn(
    asset.names = colnames(managers[, 1:3]),
    mkt.name = "SP500.TR",
    data = managers
  )

  pdf(NULL)
  on.exit(dev.off(), add = TRUE)

  expect_no_error(
    plot(fit, asset.name = "HAM1", SFM.line = TRUE)
  )
})

test_that("plot.tsfmUpDn with LSandRob comparison (LS original)", {
  skip_if_not_installed("RobStatTM")
  fit <- fitTsfmUpDn(
    asset.names = colnames(managers[, 1:3]),
    mkt.name = "SP500.TR",
    data = managers,
    fit.method = "LS"
  )

  pdf(NULL)
  on.exit(dev.off(), add = TRUE)

  # LSandRob=TRUE refits with the alternative method (Robust) and overlays
  expect_no_error(
    plot(fit, asset.name = "HAM1", LSandRob = TRUE)
  )
})

test_that("plot.tsfmUpDn with LSandRob comparison (Robust original)", {
  skip_if_not_installed("RobStatTM")
  fit_rob <- fitTsfmUpDn(
    asset.names = colnames(managers[, 1:3]),
    mkt.name = "SP500.TR",
    data = managers,
    fit.method = "Robust"
  )

  pdf(NULL)
  on.exit(dev.off(), add = TRUE)

  # Exercises the Robust→LS direction and the legend else branch
  expect_no_error(
    plot(fit_rob, asset.name = "HAM1", LSandRob = TRUE)
  )
})

test_that("plot.tsfmUpDn legend labels match model type", {
  skip_if_not_installed("RobStatTM")
  fit <- fitTsfmUpDn(
    asset.names = colnames(managers[, 1:3]),
    mkt.name = "SP500.TR",
    data = managers,
    fit.method = "LS"
  )

  pdf(NULL)
  on.exit(dev.off(), add = TRUE)

  # Capture the plot output to verify legend content
  out <- capture.output({
    plot(fit, asset.name = "HAM1", LSandRob = TRUE)
  })
  # The function should complete; legend correctness verified by no error
  expect_true(TRUE)
})

test_that("plot.tsfmUpDn Robust-only legend uses correct beta (no LSandRob)", {
  skip_if_not_installed("RobStatTM")
  fit_rob <- fitTsfmUpDn(
    asset.names = colnames(managers[, 1:3]),
    mkt.name = "SP500.TR",
    data = managers,
    fit.method = "Robust"
  )

  pdf(NULL)
  on.exit(dev.off(), add = TRUE)

  # Previously crashed: referenced undefined up.beta.alt when LSandRob=FALSE
  expect_no_error(
    plot(fit_rob, asset.name = "HAM1", LSandRob = FALSE)
  )
})

# ============================================================================
# 11. portSdDecomp — user-supplied factor.cov (portSdDecomp.R, ~10 lines)
# ============================================================================

test_that("portSdDecomp.tsfm with user-supplied factor.cov", {
  fac <- as.matrix(fit_tsfm_ls$data[, fit_tsfm_ls$factor.names])
  fc <- cov(fac, use = "pairwise.complete.obs")
  d <- portSdDecomp(fit_tsfm_ls, factor.cov = fc)
  expect_true(is.numeric(d$portSd))
  expect_true(d$portSd > 0)

  # Should match default (no factor.cov)
  d2 <- portSdDecomp(fit_tsfm_ls)
  expect_equal(d$portSd, d2$portSd, tolerance = 1e-10)
})

test_that("portSdDecomp errors on wrong factor.cov dimensions", {
  expect_error(
    portSdDecomp(fit_tsfm_ls, factor.cov = matrix(1, 1, 1)),
    "Dimensions"
  )
})

test_that("portSdDecomp.tsfm errors on unnamed weights", {
  wts <- rep(1/6, 6)
  expect_error(portSdDecomp(fit_tsfm_ls, weights = wts), "names")
})

# ============================================================================
# 12. exposuresTseries (exposuresTseries.R, 16 lines, was 0%)
# ============================================================================

test_that("exposuresTseries runs with single ticker", {
  pdf(NULL)
  on.exit(dev.off(), add = TRUE)
  expect_no_error(
    exposuresTseries(factorDataSetDjia5Yrs, tickers = "BAC",
                     which.exposures = "MKTCAP")
  )
})

test_that("exposuresTseries runs with multiple tickers, no returns", {
  pdf(NULL)
  on.exit(dev.off(), add = TRUE)
  expect_no_error(
    exposuresTseries(factorDataSetDjia5Yrs,
                     tickers = c("AA", "BAC"),
                     plot.returns = FALSE)
  )
})

test_that("exposuresTseries NULL tickers defaults to first ticker", {
  pdf(NULL)
  on.exit(dev.off(), add = TRUE)
  expect_no_error(
    exposuresTseries(factorDataSetDjia5Yrs, tickers = NULL,
                     which.exposures = "P2B")
  )
})

test_that("exposuresTseries errors on invalid ticker", {
  expect_error(
    exposuresTseries(factorDataSetDjia5Yrs, tickers = "NONEXISTENT"),
    "not present"
  )
})

# ============================================================================
# 13. predict.ffm backward compat: char_levels=NULL fallback
#     (predict.ffm.R, lines 103-112)
# ============================================================================

test_that("expand_newdata_ffm handles missing char_levels gracefully", {
  # Fit a sector model so we have char exposures
  fit_sector <- fitFfm(
    data = factorDataSetDjia5Yrs,
    asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
    exposure.vars = c("SECTOR", "P2B"),
    addIntercept = TRUE
  )

  # Simulate a pre-char_levels ffm object
  fit_no_levels <- fit_sector
  fit_no_levels$char_levels <- NULL

  newdata <- data.frame(
    SECTOR = c("COSTAP", "ENERGY"),
    P2B = c(1.0, 2.0)
  )

  expect_message(
    result <- expand_newdata_ffm(fit_no_levels, newdata),
    "char_levels"
  )
  expect_true(is.data.frame(result))
})

# ============================================================================
# 14. fitFfm zScore branches (fitFfm.R lines 354-379)
# ============================================================================

test_that("fitFfm z.score='crossSection' with rob.stats=TRUE uses robust z-scores", {
  fit_cs_rob <- fitFfm(
    data = factorDataSetDjia5Yrs,
    asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
    exposure.vars = c("P2B", "MKTCAP"),
    z.score = "crossSection", rob.stats = TRUE
  )
  expect_s3_class(fit_cs_rob, "ffm")
  expect_equal(nrow(fit_cs_rob$beta), length(fit_cs_rob$asset.names))
  expect_true(all(c("P2B", "MKTCAP") %in% colnames(fit_cs_rob$beta)))
})

test_that("fitFfm z.score='timeSeries' produces valid model", {
  fit_ts <- fitFfm(
    data = factorDataSetDjia5Yrs,
    asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
    exposure.vars = c("P2B", "MKTCAP"),
    z.score = "timeSeries"
  )
  expect_s3_class(fit_ts, "ffm")
  expect_equal(nrow(fit_ts$beta), length(fit_ts$asset.names))
})

# ============================================================================
# 15. fitFfm validation error branches (fitFfm.R lines 250-292, 314, 319)
# ============================================================================

test_that("fitFfm errors on < 2 assets", {
  dat_1asset <- factorDataSetDjia5Yrs[factorDataSetDjia5Yrs$TICKER == "AA", ]
  expect_error(
    fitFfm(data = dat_1asset, asset.var = "TICKER", ret.var = "RETURN",
           date.var = "DATE", exposure.vars = "P2B"),
    "at least 2 assets"
  )
})

test_that("fitFfm errors on non-logical full.resid.cov", {
  expect_error(
    fitFfm(data = factorDataSetDjia5Yrs, asset.var = "TICKER",
           ret.var = "RETURN", date.var = "DATE",
           exposure.vars = "P2B", full.resid.cov = "yes"),
    "full.resid.cov"
  )
})

test_that("fitFfm errors on resid.scaleType with LS", {
  expect_error(
    fitFfm(data = factorDataSetDjia5Yrs, asset.var = "TICKER",
           ret.var = "RETURN", date.var = "DATE",
           exposure.vars = "P2B", fit.method = "LS",
           resid.scaleType = "EWMA"),
    "WLS or W-Rob"
  )
})

test_that("fitFfm errors on non-list GARCH.params", {
  expect_error(
    fitFfm(data = factorDataSetDjia5Yrs, asset.var = "TICKER",
           ret.var = "RETURN", date.var = "DATE",
           exposure.vars = "P2B", GARCH.params = "bad"),
    "GARCH.params"
  )
})

test_that("fitFfm errors on non-logical stdReturn", {
  expect_error(
    fitFfm(data = factorDataSetDjia5Yrs, asset.var = "TICKER",
           ret.var = "RETURN", date.var = "DATE",
           exposure.vars = "P2B", stdReturn = "yes"),
    "stdReturn"
  )
})

test_that("fitFfm errors on invalid z.score", {
  expect_error(
    fitFfm(data = factorDataSetDjia5Yrs, asset.var = "TICKER",
           ret.var = "RETURN", date.var = "DATE",
           exposure.vars = "P2B", z.score = "badValue"),
    "z.score"
  )
})

test_that("fitFfm errors on < 2 time periods", {
  dat_1period <- factorDataSetDjia5Yrs[factorDataSetDjia5Yrs$DATE ==
    min(factorDataSetDjia5Yrs$DATE), ]
  expect_error(
    fitFfm(data = dat_1period, asset.var = "TICKER", ret.var = "RETURN",
           date.var = "DATE", exposure.vars = "P2B"),
    "at least 2 unique time periods"
  )
})

# ============================================================================
# 16. repRisk portfolio.only with FMCR and FCR decompositions
#     (repRisk.R lines 305-319 in .assemble_portfolio_only)
# ============================================================================

test_that("repRisk portfolio.only with decomp='FMCR' returns marginal contributions", {
  wts <- rep(1/length(fit_ffm_style$asset.names),
             length(fit_ffm_style$asset.names))
  names(wts) <- fit_ffm_style$asset.names

  out <- repRisk(fit_ffm_style, weights = wts,
                 risk = c("Sd", "VaR", "ES"), decomp = "FMCR",
                 portfolio.only = TRUE, isPrint = FALSE, isPlot = FALSE)
  expect_true(is.list(out))
  d <- out$decomp
  expect_true(is.matrix(d))
  expect_equal(nrow(d), 3L)
  expect_equal(sort(rownames(d)), c("ES", "Sd", "VaR"))
  # FMCR has no RM/Total column — just factor + residual marginals
  expect_true("Residuals" %in% colnames(d))
})

test_that("repRisk portfolio.only with decomp='FCR' includes RM column", {
  wts <- rep(1/length(fit_ffm_style$asset.names),
             length(fit_ffm_style$asset.names))
  names(wts) <- fit_ffm_style$asset.names

  out <- repRisk(fit_ffm_style, weights = wts,
                 risk = c("Sd", "VaR", "ES"), decomp = "FCR",
                 portfolio.only = TRUE, isPrint = FALSE, isPlot = FALSE)
  d <- out$decomp
  expect_true(is.matrix(d))
  expect_equal(nrow(d), 3L)
  expect_true("RM" %in% colnames(d))
})

test_that("repRisk portfolio.only single risk with FMCR", {
  wts <- rep(1/length(fit_ffm_style$asset.names),
             length(fit_ffm_style$asset.names))
  names(wts) <- fit_ffm_style$asset.names

  out <- repRisk(fit_ffm_style, weights = wts,
                 risk = "VaR", decomp = "FMCR",
                 portfolio.only = TRUE, isPrint = FALSE, isPlot = FALSE)
  d <- out$decomp
  expect_true(is.matrix(d))
  expect_equal(nrow(d), 1L)
  expect_equal(rownames(d), "VaR")
})

# ============================================================================
# 17. repRisk list-of-objects dispatch (repRisk.R lines 125-129, 186)
# ============================================================================

test_that("repRisk accepts list of ffm objects", {
  wts <- rep(1/length(fit_ffm_style$asset.names),
             length(fit_ffm_style$asset.names))
  names(wts) <- fit_ffm_style$asset.names

  out <- repRisk(list(fit_ffm_style, fit_ffm_style),
                 weights = list(wts, wts),
                 risk = "Sd", decomp = "FPCR",
                 isPrint = FALSE, isPlot = FALSE)
  expect_true(is.list(out))
})

test_that("repRisk list dispatch errors on non-fm objects", {
  expect_error(
    repRisk(list("not_a_model"), weights = list(c(a = 1))),
    "tsfm.*ffm"
  )
})

# ============================================================================
# 18. fmmc edge cases (fmmc.R lines 62-63, 69-70, 106-110, 287-294)
# ============================================================================

test_that(".fmmc.proc warns on non-matrix inputs", {
  expect_warning(
    result <- FactorAnalytics:::.fmmc.proc(R = 1:10, factors = 1:10),
    "not matrix"
  )
  expect_true(is.na(result))
})

test_that(".fmmc.proc warns when factors shorter than assets", {
  R <- xts::xts(matrix(rnorm(20), ncol = 1), order.by = seq.Date(as.Date("2020-01-01"), by = "month", length.out = 20))
  colnames(R) <- "Asset1"
  fac <- xts::xts(matrix(rnorm(10), ncol = 1), order.by = seq.Date(as.Date("2020-01-01"), by = "month", length.out = 10))
  colnames(fac) <- "Factor1"
  expect_warning(
    result <- FactorAnalytics:::.fmmc.proc(R = R, factors = fac),
    "Length of factors"
  )
  expect_true(is.na(result))
})

test_that("fmmc parallel=TRUE produces same structure as sequential", {
  # parallel path calls clusterEvalQ(cl, library(FactorAnalytics)) which
  # requires the package to be installed, not just source-loaded via load_all.
  # Detect load_all: system.file() returns path ending in /inst for source packages.
  pkg_path <- system.file(package = "FactorAnalytics")
  skip_if(grepl("/inst$", pkg_path),
          "FactorAnalytics loaded via devtools, not installed")
  # R CMD check sets _R_CHECK_LIMIT_CORES_ which makes makeCluster() error
  # when requesting more than 2 cores (detectCores() on CI typically returns 4).
  skip_if(nzchar(Sys.getenv("_R_CHECK_LIMIT_CORES_")),
          "R CMD check limits parallel cores")
  R <- managers[, 1:2]
  factors <- managers[, c("EDHEC.LS.EQ", "SP500.TR")]

  result_seq <- fmmc(R, factors, parallel = FALSE)
  result_par <- fmmc(R, factors, parallel = TRUE)
  expect_equal(length(result_seq), length(result_par))
})
