# test-integration-pa.R — Phase 4.4
# Validates that ffm objects expose the interface that a custom moment
# function for PortfolioAnalytics requires. Does NOT depend on
# PortfolioAnalytics — it simulates the hand-off interface.

# Fit once, reuse across blocks
fit_pa <- fitFfm(
  data = dat145, asset.var = "TICKER", ret.var = "RETURN",
  date.var = "DATE",
  exposure.vars = c("SECTOR", "ROE", "BP", "PM12M1M",
                    "SIZE", "ANNVOL1M", "EP"),
  addIntercept = TRUE, fit.method = "WLS",
  resid.scaleType = "EWMA", lambda = 0.9
)

test_that("ffm object exposes PA-compatible moment components", {
  expect_false(is.null(fit_pa$beta))
  expect_false(is.null(fit_pa$factor.cov))
  expect_false(is.null(fit_pa$resid.var))

  K <- ncol(fit_pa$beta)
  N <- nrow(fit_pa$beta)
  expect_equal(dim(fit_pa$factor.cov), c(K, K))
  expect_equal(length(fit_pa$resid.var), N)
  expect_equal(colnames(fit_pa$beta), colnames(fit_pa$factor.cov))
  expect_equal(colnames(fit_pa$beta), rownames(fit_pa$factor.cov))

  # Reconstructed covariance is PSD
  Sigma <- fit_pa$beta %*% fit_pa$factor.cov %*% t(fit_pa$beta) +
    diag(fit_pa$resid.var)
  eig <- eigen(Sigma, symmetric = TRUE, only.values = TRUE)$values
  expect_true(all(eig > -1e-10))

  # fmCov() produces the same result
  Sigma_fmCov <- fmCov(fit_pa)
  expect_equal(Sigma, Sigma_fmCov, tolerance = 1e-8)
})

test_that("ffm moment components survive asset subsetting", {
  all_assets <- rownames(fit_pa$beta)
  subset_assets <- all_assets[1:50]

  beta_sub <- fit_pa$beta[subset_assets, , drop = FALSE]
  resid_sub <- fit_pa$resid.var[subset_assets]
  Sigma_sub <- beta_sub %*% fit_pa$factor.cov %*% t(beta_sub) +
    diag(resid_sub)

  eig <- eigen(Sigma_sub, symmetric = TRUE, only.values = TRUE)$values
  expect_true(all(eig > -1e-10))
  expect_equal(rownames(Sigma_sub), subset_assets)
  expect_equal(colnames(Sigma_sub), subset_assets)
})

test_that("custom moment function simulation works end-to-end", {
  custom_moments <- function(R, fit) {
    beta <- fit$beta
    Sigma_F <- fit$factor.cov
    D <- diag(fit$resid.var)
    Sigma <- beta %*% Sigma_F %*% t(beta) + D
    assets <- intersect(colnames(R), rownames(Sigma))
    Sigma <- Sigma[assets, assets]
    list(mu = colMeans(R[, assets], na.rm = TRUE), sigma = Sigma)
  }

  R <- as.matrix(fit_pa$residuals)
  result <- custom_moments(R, fit_pa)

  expect_true(is.list(result))
  expect_true(is.numeric(result$mu))
  expect_true(is.matrix(result$sigma))
  expect_equal(nrow(result$sigma), ncol(result$sigma))
  expect_true(isSymmetric(result$sigma))
})

test_that("moment components have consistent asset names across slots", {
  expect_equal(rownames(fit_pa$beta), names(fit_pa$resid.var))
  expect_equal(rownames(fmCov(fit_pa)), rownames(fit_pa$beta))
  expect_equal(colnames(fmCov(fit_pa)), rownames(fit_pa$beta))
})

test_that("fmCov output works with RiskPortfolios", {
  skip_if_not_installed("RiskPortfolios")
  Sigma <- fmCov(fit_pa)
  w <- RiskPortfolios::optimalPortfolio(
    Sigma = Sigma, control = list(type = "erc", constraint = "lo")
  )
  expect_equal(length(w), nrow(Sigma))
  expect_equal(sum(w), 1, tolerance = 1e-6)
  expect_true(all(w >= 0))
})
