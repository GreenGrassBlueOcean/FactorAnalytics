# test-portVolDecomp.R — Phase 4.3.2
# Portfolio volatility decomposition into factor/residual components.

# --- TSFM method ---
test_that("portVolDecomp.tsfm returns correct structure", {
  fit <- fitTsfm(
    asset.names = colnames(managers[, 1:6]),
    factor.names = colnames(managers[, 7:9]),
    rf.name = colnames(managers[, 10]),
    data = managers
  )
  decomp <- portVolDecomp(fit)

  expect_true(is.list(decomp))
  expect_named(decomp, c("Percent Factor Contribution to Risk",
                          "Portfolio Volatility Risk",
                          "Factor Volatility Risk",
                          "Residual Volatility Risk"))

  # Factor + residual vol must equal total vol
  expect_equal(
    decomp[["Factor Volatility Risk"]] + decomp[["Residual Volatility Risk"]],
    decomp[["Portfolio Volatility Risk"]],
    tolerance = 1e-10
  )
  # Percent factor contribution in [0, 1]
  pct <- decomp[["Percent Factor Contribution to Risk"]]
  expect_true(pct >= 0)
  expect_true(pct <= 1)
})

test_that("portVolDecomp.tsfm with custom weights", {
  fit <- fitTsfm(
    asset.names = colnames(managers[, 1:6]),
    factor.names = colnames(managers[, 7:9]),
    rf.name = colnames(managers[, 10]),
    data = managers
  )
  wts <- rep(1/6, 6)
  names(wts) <- fit$asset.names
  decomp <- portVolDecomp(fit, weights = wts)
  expect_true(decomp[["Portfolio Volatility Risk"]] > 0)
})

# --- FFM method ---
test_that("portVolDecomp.ffm returns correct structure", {
  fit <- fitFfm(
    data = factorDataSetDjia5Yrs,
    asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
    exposure.vars = c("P2B", "EV2S")
  )
  decomp <- portVolDecomp(fit)

  expect_true(is.list(decomp))
  expect_equal(
    decomp[["Factor Volatility Risk"]] + decomp[["Residual Volatility Risk"]],
    decomp[["Portfolio Volatility Risk"]],
    tolerance = 1e-10
  )
})

test_that("portVolDecomp.ffm with GMV weights", {
  fit <- fitFfm(
    data = factorDataSetDjia5Yrs,
    asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
    exposure.vars = c("P2B", "EV2S")
  )
  decomp <- portVolDecomp(fit, weights = wtsDjiaGmvLo)
  expect_true(decomp[["Portfolio Volatility Risk"]] > 0)
  expect_true(decomp[["Percent Factor Contribution to Risk"]] >= 0)
})

test_that("portVolDecomp.ffm sector model", {
  fit <- fitFfm(
    data = factorDataSetDjia5Yrs,
    asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
    exposure.vars = c("SECTOR", "P2B"),
    addIntercept = TRUE
  )
  decomp <- portVolDecomp(fit)
  expect_equal(
    decomp[["Factor Volatility Risk"]] + decomp[["Residual Volatility Risk"]],
    decomp[["Portfolio Volatility Risk"]],
    tolerance = 1e-10
  )
})
