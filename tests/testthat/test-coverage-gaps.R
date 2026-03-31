# test-coverage-gaps.R — Targeted coverage for uncovered branches in:
#   repReturn.R, plot.pafm.r, fitTsfm.control.R, fmCov.R,
#   portVolDecomp.R, VIF.R

# ── Local model fits (not shared across test files) ──────────────────────────

local_ffm_sector <- fitFfm(
  data = factorDataSetDjia5Yrs,
  asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
  exposure.vars = c("SECTOR", "P2B"),
  addIntercept = TRUE
)

local_ffm_style <- fitFfm(
  data = factorDataSetDjia5Yrs,
  asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
  exposure.vars = c("P2B", "EV2S")
)

local_tsfm <- fitTsfm(
  asset.names = colnames(managers[, 1:6]),
  factor.names = colnames(managers[, 7:9]),
  rf.name = colnames(managers[, 10]),
  data = managers
)

# ── MSCI data setup (2 character exposures) ──────────────────────────────────

dat_msci_rr <- stocks145scores6[stocks145scores6$DATE >= as.Date("2012-01-01"), ]
sector_tickers_rr <- split(
  unique(dat_msci_rr$TICKER),
  dat_msci_rr$SECTOR[match(unique(dat_msci_rr$TICKER), dat_msci_rr$TICKER)]
)
region_map_rr <- do.call(rbind, lapply(names(sector_tickers_rr), function(sec) {
  tk <- sector_tickers_rr[[sec]]
  data.frame(
    TICKER = tk,
    REGION = rep(c("NorthAm", "Europe"), length.out = length(tk)),
    stringsAsFactors = FALSE
  )
}))
dat_msci_rr <- merge(dat_msci_rr, region_map_rr, by = "TICKER")
dat_msci_rr <- dat_msci_rr[dat_msci_rr$SECTOR != "Telecommunications", ]

local_msci_pure <- fitFfm(
  data = dat_msci_rr, asset.var = "TICKER", ret.var = "RETURN",
  date.var = "DATE", exposure.vars = c("SECTOR", "REGION"),
  addIntercept = TRUE
)

local_msci_style <- fitFfm(
  data = dat_msci_rr, asset.var = "TICKER", ret.var = "RETURN",
  date.var = "DATE", exposure.vars = c("SECTOR", "REGION", "ROE", "BP"),
  addIntercept = TRUE
)

# ============================================================================
# repReturn.R coverage
# ============================================================================

test_that("repReturn rejects non-ffm input", {
  expect_error(repReturn(list()), "ffm")
})

test_that("repReturn rejects unnamed weights", {
  n <- length(local_ffm_sector$asset.names)
  wts <- rep(1 / n, n)
  expect_error(
    repReturn(local_ffm_sector, weights = wts, isPlot = FALSE, isPrint = TRUE),
    "names of weights"
  )
})

# ── repReturn with MSCI model (multi-char-exposure branch, lines 128-136) ──

test_that("repReturn MSCI pure model (2 char exposures) computes correctly", {
  result <- capture.output(
    ret <- repReturn(local_msci_pure, isPlot = FALSE, isPrint = TRUE)
  )
  expect_true(is.matrix(ret))
  expect_equal(ncol(ret), 2)
  expect_equal(colnames(ret), c("Mean", "Volatility"))
  # Should have rows for each factor + aggregates
  expect_true(nrow(ret) > 0)
})

test_that("repReturn MSCI pure model with named weights", {
  n <- length(local_msci_pure$asset.names)
  wts <- rep(1 / n, n)
  names(wts) <- local_msci_pure$asset.names
  result <- capture.output(
    ret <- repReturn(local_msci_pure, weights = wts,
                     isPlot = FALSE, isPrint = TRUE)
  )
  expect_true(is.matrix(ret))
})

test_that("repReturn MSCI pure model plots (which=1:4)", {
  pdf(NULL)
  on.exit(dev.off(), add = TRUE)
  for (w in 1:4) {
    expect_no_error(
      repReturn(local_msci_pure, isPlot = TRUE, isPrint = FALSE, which = w)
    )
  }
})

test_that("repReturn MSCI+style model computes correctly", {
  result <- capture.output(
    ret <- repReturn(local_msci_style, isPlot = FALSE, isPrint = TRUE)
  )
  expect_true(is.matrix(ret))
  expect_equal(ncol(ret), 2)
  expect_equal(colnames(ret), c("Mean", "Volatility"))
})

test_that("repReturn MSCI+style model plots (which=1:4)", {
  pdf(NULL)
  on.exit(dev.off(), add = TRUE)
  for (w in 1:4) {
    expect_no_error(
      repReturn(local_msci_style, isPlot = TRUE, isPrint = FALSE, which = w)
    )
  }
})

# ============================================================================
# plot.pafm.r coverage
# ============================================================================

test_that("plot.pafm single-asset bad date triggers tryCatch error branch", {
  fit_tsfm <- fitTsfm(
    asset.names = colnames(managers[, 1:6]),
    factor.names = c("EDHEC.LS.EQ", "SP500.TR"),
    data = managers
  )
  fm_attr <- paFm(fit_tsfm)

  pdf(NULL)
  on.exit(dev.off(), add = TRUE)

  # "2L" with a date that doesn't exist in the data
  expect_no_error(
    plot(fm_attr, plot.single = TRUE, fundName = "HAM1",
         which.plot.single = "2L", date = as.Date("1900-01-01"))
  )
})

test_that("plot.pafm single-asset invalid which.plot.single hits invisible()", {
  fit_tsfm <- fitTsfm(
    asset.names = colnames(managers[, 1:6]),
    factor.names = c("EDHEC.LS.EQ", "SP500.TR"),
    data = managers
  )
  fm_attr <- paFm(fit_tsfm)

  pdf(NULL)
  on.exit(dev.off(), add = TRUE)

  # Bad switch value → invisible()
  expect_no_error(
    plot(fm_attr, plot.single = TRUE, fundName = "HAM1",
         which.plot.single = "99L")
  )
})

test_that("plot.pafm multi-asset bad date triggers tryCatch error branch", {
  fit_tsfm <- fitTsfm(
    asset.names = colnames(managers[, 1:6]),
    factor.names = c("EDHEC.LS.EQ", "SP500.TR"),
    data = managers
  )
  fm_attr <- paFm(fit_tsfm)

  pdf(NULL)
  on.exit(dev.off(), add = TRUE)

  expect_no_error(
    plot(fm_attr, which.plot = "2L", max.show = 4,
         date = as.Date("1900-01-01"))
  )
})

test_that("plot.pafm multi-asset invalid which.plot hits invisible()", {
  fit_tsfm <- fitTsfm(
    asset.names = colnames(managers[, 1:6]),
    factor.names = c("EDHEC.LS.EQ", "SP500.TR"),
    data = managers
  )
  fm_attr <- paFm(fit_tsfm)

  pdf(NULL)
  on.exit(dev.off(), add = TRUE)

  expect_no_error(
    plot(fm_attr, which.plot = "99L")
  )
})

# ============================================================================
# fitTsfm.control.R coverage
# ============================================================================

test_that("fitTsfm.control user-specified args path", {
  # Passing named args that go through match.call branch (line 244)
  ctrl <- fitTsfm.control(method = "exhaustive", type = "lasso")
  expect_equal(ctrl$method, "exhaustive")
  expect_equal(ctrl$type, "lasso")
})

test_that("fitTsfm.control rejects bad decay", {
  expect_error(fitTsfm.control(decay = 0), "Decay")
  expect_error(fitTsfm.control(decay = 1.5), "Decay")
  expect_error(fitTsfm.control(decay = -0.1), "Decay")
})

test_that("fitTsfm.control rejects non-logical model/x/y/qr", {
  expect_error(fitTsfm.control(model = "yes"), "model")
  expect_error(fitTsfm.control(x = "yes"), "'x'")
  expect_error(fitTsfm.control(y = "yes"), "'y'")
  expect_error(fitTsfm.control(qr = "yes"), "'qr'")
})

test_that("fitTsfm.control rejects non-logical really.big/normalize/plot.it", {
  expect_error(fitTsfm.control(really.big = "yes"), "really.big")
  expect_error(fitTsfm.control(normalize = "yes"), "normalize")
  expect_error(fitTsfm.control(plot.it = "yes"), "plot.it")
})

test_that("fitTsfm.control rejects bad nvmin/nvmax", {
  expect_error(fitTsfm.control(nvmin = 0), "nvmin")
  expect_error(fitTsfm.control(nvmin = 1.5), "nvmin")
  expect_error(fitTsfm.control(nvmax = 0, nvmin = 1), "nvmax")
})

test_that("fitTsfm.control rejects bad lars.criterion", {
  expect_error(fitTsfm.control(lars.criterion = "AIC"), "lars.criterion")
})

# ============================================================================
# fmCov.R coverage
# ============================================================================

test_that("fmCov rejects non-tsfm/ffm input", {
  expect_error(fmCov(list()), "tsfm.*ffm")
})

test_that("fmCov.ffm computes factor.cov from factor.returns when NULL", {
  # Null out the stored factor.cov to force sample computation (lines 123-124)
  fit_no_cov <- local_ffm_style
  fit_no_cov$factor.cov <- NULL
  cov_mat <- fmCov(fit_no_cov)
  expect_true(is.matrix(cov_mat))
  expect_equal(nrow(cov_mat), ncol(cov_mat))
  expect_equal(nrow(cov_mat), length(local_ffm_style$asset.names))
  eig <- eigen(cov_mat, symmetric = TRUE, only.values = TRUE)$values
  expect_true(all(eig >= -1e-10))
})

# ============================================================================
# portVolDecomp.R coverage
# ============================================================================

test_that("portVolDecomp rejects non-tsfm/ffm input", {
  expect_error(portVolDecomp(list()), "tsfm.*ffm")
})

test_that("portVolDecomp.tsfm rejects wrong weight count", {
  expect_error(
    portVolDecomp(local_tsfm, weights = c(0.5, 0.5)),
    "incorrect number"
  )
})

test_that("portVolDecomp.tsfm rejects unnamed weights", {
  n <- length(local_tsfm$asset.names)
  wts <- rep(1 / n, n)
  expect_error(
    portVolDecomp(local_tsfm, weights = wts),
    "names of weights"
  )
})

test_that("portVolDecomp.tsfm rejects wrong factor.cov dimensions", {
  expect_error(
    portVolDecomp(local_tsfm, factor.cov = matrix(1, 1, 1)),
    "Dimensions"
  )
})

test_that("portVolDecomp.ffm rejects non-ffm input", {
  expect_error(portVolDecomp.ffm(list()), "ffm")
})

test_that("portVolDecomp.ffm rejects wrong weight count", {
  expect_error(
    portVolDecomp(local_ffm_style, weights = c(0.5, 0.5)),
    "incorrect number"
  )
})

test_that("portVolDecomp.ffm rejects unnamed weights", {
  n <- length(local_ffm_style$asset.names)
  wts <- rep(1 / n, n)
  expect_error(
    portVolDecomp(local_ffm_style, weights = wts),
    "names of weights"
  )
})

test_that("portVolDecomp.ffm rejects wrong factor.cov dimensions", {
  expect_error(
    portVolDecomp(local_ffm_style, factor.cov = matrix(1, 1, 1)),
    "Dimensions"
  )
})

# ============================================================================
# VIF.R coverage
# ============================================================================

test_that("vif rejects non-tsfm/ffm input", {
  expect_error(vif(list()), "tsfm.*ffm")
})

test_that("vif rejects model with < 2 numeric exposures", {
  fit_sec <- fitFfm(
    data = factorDataSetDjia5Yrs,
    asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
    exposure.vars = c("SECTOR"),
    addIntercept = TRUE
  )
  expect_error(vif(fit_sec), "2 continous")
})

test_that("vif title=FALSE works", {
  pdf(NULL)
  on.exit(dev.off(), add = TRUE)
  expect_no_error(
    capture.output(vif(local_ffm_style, title = FALSE, isPrint = TRUE))
  )
})

test_that("vif isPrint=FALSE returns invisibly", {
  pdf(NULL)
  on.exit(dev.off(), add = TRUE)
  result <- capture.output(vif(local_ffm_style, isPrint = FALSE, isPlot = FALSE))
  expect_true(length(result) > 0)
})
