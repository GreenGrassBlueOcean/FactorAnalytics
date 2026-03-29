# test-paFm.R — Phase 4.3.4
# Performance attribution factor model tests.

# --- TSFM attribution ---
test_that("paFm.tsfm produces correct structure", {
  fit <- fitTsfm(
    asset.names = colnames(managers[, 1:6]),
    factor.names = colnames(managers[, 7:9]),
    rf.name = colnames(managers[, 10]),
    data = managers
  )
  pa <- paFm(fit)

  expect_s3_class(pa, "pafm")
  expect_true(!is.null(pa$cum.ret.attr.f))
  expect_true(!is.null(pa$cum.spec.ret))
  expect_true(!is.null(pa$attr.list))

  # N assets x K factors
  expect_equal(nrow(pa$cum.ret.attr.f), length(fit$asset.names))
  expect_equal(ncol(pa$cum.ret.attr.f), length(fit$factor.names))

  # attr.list has one entry per asset
  expect_equal(length(pa$attr.list), length(fit$asset.names))
})

# --- FFM attribution: style-only ---
test_that("paFm.ffm produces correct structure (style-only)", {
  fit <- fitFfm(
    data = factorDataSetDjia5Yrs,
    asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
    exposure.vars = c("P2B", "EV2S")
  )
  pa <- paFm(fit)

  expect_s3_class(pa, "pafm")
  expect_equal(nrow(pa$cum.ret.attr.f), length(fit$asset.names))
  expect_equal(ncol(pa$cum.ret.attr.f), length(fit$factor.names))
  expect_equal(length(pa$cum.spec.ret), length(fit$asset.names))
  expect_equal(length(pa$attr.list), length(fit$asset.names))
})

# --- FFM attribution: sector+style ---
test_that("paFm.ffm produces correct structure (sector+style)", {
  fit <- fitFfm(
    data = factorDataSetDjia5Yrs,
    asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
    exposure.vars = c("SECTOR", "P2B", "EV2S"),
    addIntercept = TRUE
  )
  pa <- paFm(fit)

  expect_s3_class(pa, "pafm")
  # All factor names (Market + sectors + numeric) should be in attribution
  expect_equal(colnames(pa$cum.ret.attr.f), colnames(fit$factor.returns))
  expect_equal(nrow(pa$cum.ret.attr.f), length(fit$asset.names))
  expect_equal(length(pa$cum.spec.ret), length(fit$asset.names))
})

# --- FFM attribution: sector-only ---
test_that("paFm.ffm produces correct structure (sector-only)", {
  fit <- fitFfm(
    data = factorDataSetDjia5Yrs,
    asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
    exposure.vars = "SECTOR"
  )
  pa <- paFm(fit)

  expect_s3_class(pa, "pafm")
  expect_equal(nrow(pa$cum.ret.attr.f), length(fit$asset.names))
  expect_equal(length(pa$cum.spec.ret), length(fit$asset.names))
})

# --- S3 methods ---
test_that("print and summary.pafm run without error", {
  fit <- fitTsfm(
    asset.names = colnames(managers[, 1:6]),
    factor.names = colnames(managers[, 7:9]),
    rf.name = colnames(managers[, 10]),
    data = managers
  )
  pa <- paFm(fit)

  expect_no_error(capture.output(print(pa)))
  expect_no_error(summary(pa))
})

test_that("plot.pafm runs without error (TSFM)", {
  fit <- fitTsfm(
    asset.names = colnames(managers[, 1:6]),
    factor.names = colnames(managers[, 7:9]),
    rf.name = colnames(managers[, 10]),
    data = managers
  )
  pa <- paFm(fit)

  pdf(NULL)
  on.exit(dev.off(), add = TRUE)
  expect_no_error(plot(pa, which.plot = "1L"))
})

test_that("plot.pafm runs without error (FFM)", {
  fit <- fitFfm(
    data = factorDataSetDjia5Yrs,
    asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
    exposure.vars = c("P2B", "EV2S")
  )
  pa <- paFm(fit)

  pdf(NULL)
  on.exit(dev.off(), add = TRUE)
  expect_no_error(plot(pa, which.plot = "1L"))
})
