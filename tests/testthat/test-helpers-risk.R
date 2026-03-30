# =============================================================================
# test-helpers-risk.R — Unit tests for shared risk decomposition helpers
#
# Tests make_beta_star, make_factor_star_cov, normalize_fm_residuals,
# make_resid_diag against manually constructed equivalents and against
# the output of existing fitted models.
# =============================================================================

# --- make_beta_star ---

test_that("make_beta_star — asset-level tsfm matches inline construction", {
  fit <- fitTsfm(
    asset.names  = colnames(managers[, 1:6]),
    factor.names = colnames(managers[, 7:9]),
    rf.name      = colnames(managers[, 10]),
    data         = managers
  )
  # Inline construction (as in fmSdDecomp.tsfm)
  beta <- fit$beta
  beta[is.na(beta)] <- 0
  expected <- as.matrix(cbind(beta, Residuals = fit$resid.sd))

  result <- make_beta_star(fit$beta, fit$resid.sd)

  expect_equal(result, expected, tolerance = 0)
  expect_equal(ncol(result), ncol(fit$beta) + 1L)
  expect_equal(colnames(result)[ncol(result)], "Residuals")
})

test_that("make_beta_star — asset-level ffm zeros NAs", {
  fit <- fitFfm(
    data = factorDataSetDjia5Yrs,
    asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
    exposure.vars = c("P2B", "EV2S")
  )
  result <- make_beta_star(fit$beta, sqrt(fit$resid.var))

  # No NAs in output

  expect_false(anyNA(result))
  expect_equal(colnames(result)[ncol(result)], "Residuals")
  expect_equal(nrow(result), nrow(fit$beta))
})

test_that("make_beta_star — portfolio-level", {
  fit <- fitTsfm(
    asset.names  = colnames(managers[, 1:6]),
    factor.names = colnames(managers[, 7:9]),
    rf.name      = colnames(managers[, 10]),
    data         = managers
  )
  n <- nrow(fit$beta)
  w <- rep(1/n, n)

  result <- make_beta_star(fit$beta, fit$resid.sd, weights = w)

  expect_equal(nrow(result), 1L)
  expect_equal(ncol(result), ncol(fit$beta) + 1L)

  # Portfolio beta = weights %*% beta
  beta <- fit$beta
  beta[is.na(beta)] <- 0
  expect_equal(result[1, 1:ncol(beta)], drop(w %*% as.matrix(beta)), tolerance = 0)

  # Portfolio residual = sqrt(sum(w^2 * sd^2))
  expect_equal(unname(result[1, "Residuals"]),
               sqrt(sum(w^2 * fit$resid.sd^2)), tolerance = 0)
})

# --- make_factor_star_cov ---

test_that("make_factor_star_cov — structure", {
  fc <- matrix(c(0.04, 0.01, 0.01, 0.09), 2, 2,
               dimnames = list(c("A", "B"), c("A", "B")))
  result <- make_factor_star_cov(fc)

  expect_equal(dim(result), c(3L, 3L))
  expect_equal(result[1:2, 1:2], fc, tolerance = 0)
  expect_equal(result[3, 3], 1)
  expect_equal(result[3, 1:2], c(A = 0, B = 0))
  expect_equal(result[1:2, 3], c(A = 0, B = 0))
  expect_equal(colnames(result), c("A", "B", "Residuals"))
  expect_equal(rownames(result), c("A", "B", "Residuals"))
})

test_that("make_factor_star_cov — round-trip vs fmSdDecomp inline", {
  fit <- fitTsfm(
    asset.names  = colnames(managers[, 1:6]),
    factor.names = colnames(managers[, 7:9]),
    rf.name      = colnames(managers[, 10]),
    data         = managers
  )
  factor <- as.matrix(fit$data[, fit$factor.names])
  factor.cov <- cov(factor, use = "pairwise.complete.obs")

  # Inline construction
  K <- ncol(fit$beta)
  expected <- diag(K + 1)
  expected[1:K, 1:K] <- factor.cov
  colnames(expected) <- c(colnames(factor.cov), "Residuals")
  rownames(expected) <- c(colnames(factor.cov), "Residuals")

  result <- make_factor_star_cov(factor.cov)
  expect_equal(result, expected, tolerance = 0)
})

test_that("make_factor_star_cov — NULL colnames fallback", {
  fc <- matrix(c(1, 0.5, 0.5, 2), 2, 2)
  result <- make_factor_star_cov(fc)
  expect_equal(colnames(result), c("F1", "F2", "Residuals"))
})

# --- normalize_fm_residuals ---

test_that("normalize_fm_residuals — asset-level matches inline", {
  fit <- fitTsfm(
    asset.names  = colnames(managers[, 1:6]),
    factor.names = colnames(managers[, 7:9]),
    rf.name      = colnames(managers[, 10]),
    data         = managers
  )
  # Inline construction (as in fmVaRDecomp.tsfm)
  expected <- xts::as.xts(
    t(t(zoo::coredata(residuals(fit))) / fit$resid.sd),
    order.by = zoo::index(residuals(fit))
  )
  zoo::index(expected) <- as.Date(zoo::index(expected))

  result <- normalize_fm_residuals(residuals(fit), fit$resid.sd)

  expect_s3_class(result, "xts")
  expect_equal(dim(result), dim(residuals(fit)))
  expect_equal(zoo::coredata(result), zoo::coredata(expected), tolerance = 1e-12)
})

test_that("normalize_fm_residuals — portfolio-level uses correct formula", {
  fit <- fitTsfm(
    asset.names  = colnames(managers[, 1:6]),
    factor.names = colnames(managers[, 7:9]),
    rf.name      = colnames(managers[, 10]),
    data         = managers
  )
  n <- nrow(fit$beta)
  w <- rep(1/n, n)

  result <- normalize_fm_residuals(residuals(fit), fit$resid.sd, weights = w)

  expect_s3_class(result, "xts")
  expect_equal(ncol(result), 1L)

  # Verify correct formula: z_p = sum(w * e) / sigma_p
  sig_p <- sqrt(sum(w^2 * fit$resid.sd^2))
  expected <- zoo::coredata(residuals(fit)) %*% w / sig_p
  expect_equal(zoo::coredata(result), expected, tolerance = 1e-12)

  # Variance should be closer to 1 than the buggy formula
  z_var <- var(as.numeric(result), na.rm = TRUE)
  expect_gt(z_var, 0.5)
  expect_lt(z_var, 1.5)
})

# --- make_resid_diag ---

test_that("make_resid_diag — multiple assets", {
  rv <- c(0.01, 0.04, 0.09)
  result <- make_resid_diag(rv)
  expect_equal(dim(result), c(3L, 3L))
  expect_equal(diag(result), rv)
  # Off-diagonals are zero
  expect_equal(sum(result) - sum(diag(result)), 0)
})

test_that("make_resid_diag — single asset returns 1x1 matrix", {
  result <- make_resid_diag(0.04)
  expect_true(is.matrix(result))
  expect_equal(dim(result), c(1L, 1L))
  expect_equal(result[1, 1], 0.04)
})
