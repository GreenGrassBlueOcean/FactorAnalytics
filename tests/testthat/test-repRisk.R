# test-repRisk.R — Phase 10.1
# Tests for repRisk() S3 methods: baseline smoke + bug fix regressions

# ---------- Setup --------------------------------------------------------

# tsfm fit (from setup.R: managers dataset already loaded)
fit_tsfm_rr <- fitTsfm(
  asset.names = colnames(managers[, 1:6]),
  factor.names = colnames(managers[, 7:9]),
  rf.name = colnames(managers[, 10]),
  data = managers
)

# ffm fit (from setup.R: dat145 already available)
fit_ffm_rr <- fitFfm(
  data = dat145,
  asset.var = "TICKER", date.var = "DATE", ret.var = "RETURN",
  exposure.vars = c("SECTOR", "ROE", "BP", "SIZE"),
  addIntercept = TRUE
)

wts6 <- rep(1/6, 6)
names(wts6) <- colnames(managers[, 1:6])

wts_ffm <- rep(1 / length(fit_ffm_rr$asset.names),
               length(fit_ffm_rr$asset.names))
names(wts_ffm) <- fit_ffm_rr$asset.names

# ---------- Baseline smoke: common single-portfolio paths ----------------

test_that("repRisk.tsfm single-risk isPrint returns valid list", {
  res <- repRisk(fit_tsfm_rr, weights = wts6, risk = "Sd",
                 decomp = "FPCR", isPrint = TRUE, isPlot = FALSE)
  expect_type(res, "list")
  expect_length(res, 1)
  mat <- res[[1]]
  expect_true(is.matrix(mat))
  # First row should be Portfolio
  expect_equal(rownames(mat)[1], "Portfolio")
})

test_that("repRisk.ffm single-risk isPrint returns valid list", {
  res <- repRisk(fit_ffm_rr, weights = wts_ffm, risk = "ES",
                 decomp = "FMCR", isPrint = TRUE, isPlot = FALSE)
  expect_type(res, "list")
  expect_length(res, 1)
  mat <- res[[1]]
  expect_true(is.matrix(mat))
  expect_equal(rownames(mat)[1], "Portfolio")
})

test_that("S3 dispatch: repRisk() dispatches correctly for both classes", {
  res_ts <- repRisk(fit_tsfm_rr, weights = wts6, risk = "Sd",
                    decomp = "FPCR")
  res_ffm <- repRisk(fit_ffm_rr, weights = wts_ffm, risk = "Sd",
                     decomp = "FPCR")
  expect_type(res_ts, "list")
  expect_type(res_ffm, "list")
  # Both should produce named matrices with matching structure
  expect_true(is.matrix(res_ts[[1]]))
  expect_true(is.matrix(res_ffm[[1]]))
})

test_that("repRisk.ffm portfolio.only single-risk isPrint works", {
  res <- repRisk(fit_ffm_rr, weights = wts_ffm,
                 risk = "Sd", decomp = "FPCR",
                 portfolio.only = TRUE, isPrint = TRUE)
  expect_type(res, "list")
  mat <- res[[1]]
  expect_true(is.numeric(mat))
})

test_that("repRisk.ffm portfolio.only multi-risk isPrint works", {
  res <- repRisk(fit_ffm_rr, weights = wts_ffm,
                 risk = c("VaR", "ES"), decomp = "FPCR",
                 portfolio.only = TRUE, isPrint = TRUE)
  expect_type(res, "list")
  mat <- res[[1]]
  expect_true(is.matrix(mat) || is.numeric(mat))
})

# ---------- Bug 3 regression: is(result) == "matrix" --------------------

test_that("Bug 3 fix: single-portfolio + multi-risk + isPlot no error", {
  # Bug: is(result) == "matrix" produces length > 1 condition
  pdf(NULL)
  on.exit(dev.off(), add = TRUE)
  expect_no_error(
    repRisk(fit_ffm_rr, weights = wts_ffm,
            risk = c("VaR", "ES"), decomp = "FPCR",
            portfolio.only = TRUE,
            isPrint = FALSE, isPlot = TRUE)
  )
})

# ---------- Bug 1 & 2 regressions: multi-portfolio paths -----------------
# These require a list of ffm objects passed directly to repRisk.ffm

test_that("Bug 1 fix: multi-portfolio + multi-risk + isPlot no error", {
  pdf(NULL)
  on.exit(dev.off(), add = TRUE)
  wts_list <- list(wts_ffm, wts_ffm)
  expect_no_error(
    repRisk.ffm(list(fit_ffm_rr, fit_ffm_rr),
                weights = wts_list,
                risk = c("VaR", "ES"), decomp = "FPCR",
                portfolio.only = TRUE,
                isPrint = FALSE, isPlot = TRUE)
  )
})

test_that("Bug 2 fix: multi-portfolio + single-risk + isPlot no error", {
  pdf(NULL)
  on.exit(dev.off(), add = TRUE)
  wts_list <- list(wts_ffm, wts_ffm)
  expect_no_error(
    repRisk.ffm(list(fit_ffm_rr, fit_ffm_rr),
                weights = wts_list,
                risk = "Sd", decomp = "FPCR",
                portfolio.only = TRUE,
                isPrint = FALSE, isPlot = TRUE)
  )
})

# ---------- Extended structure checks: decomp × risk combinations ----------

test_that("FMCR/FCR/FPCR × Sd produce correct result structure", {
  fmcr <- repRisk(fit_ffm_rr, weights = wts_ffm, risk = "Sd",
                  decomp = "FMCR")[[1]]
  fcr  <- repRisk(fit_ffm_rr, weights = wts_ffm, risk = "Sd",
                  decomp = "FCR")[[1]]
  fpcr <- repRisk(fit_ffm_rr, weights = wts_ffm, risk = "Sd",
                  decomp = "FPCR")[[1]]
  expect_equal(rownames(fmcr)[1], "Portfolio")
  # FCR has an extra RM column
  expect_equal(colnames(fcr)[1], "RM")
  expect_equal(ncol(fcr), ncol(fmcr) + 1)
  # FPCR has a Total column
  expect_equal(colnames(fpcr)[1], "Total")
})

test_that("VaR and ES decomp return matrices with correct row names", {
  var_res <- repRisk(fit_tsfm_rr, weights = wts6, risk = "VaR",
                     decomp = "FMCR")[[1]]
  es_res  <- repRisk(fit_tsfm_rr, weights = wts6, risk = "ES",
                     decomp = "FMCR")[[1]]
  expect_equal(rownames(var_res)[1], "Portfolio")
  expect_equal(rownames(es_res)[1], "Portfolio")
  expect_true(nrow(var_res) > 1)
  expect_true(nrow(es_res) > 1)
})

test_that("portfolio.only=TRUE, single risk, sliceby='factor' isPlot works", {
  pdf(NULL)
  on.exit(dev.off(), add = TRUE)
  expect_no_error(
    repRisk(fit_ffm_rr, weights = wts_ffm,
            risk = "Sd", decomp = "FPCR",
            portfolio.only = TRUE,
            isPrint = FALSE, isPlot = TRUE)
  )
})

test_that("single risk isPlot sliceby='asset' works", {
  pdf(NULL)
  on.exit(dev.off(), add = TRUE)
  expect_no_error(
    repRisk(fit_ffm_rr, weights = wts_ffm,
            risk = "Sd", decomp = "FPCR",
            isPrint = FALSE, isPlot = TRUE, sliceby = "asset",
            nrowPrint = 5)
  )
})
