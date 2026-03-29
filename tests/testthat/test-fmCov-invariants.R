# test-fmCov-invariants.R — Phase 4.2
# Structural/dimensional invariants for fmCov across all model types.
# Separate from test-fmCov.R which tests numerical reproducibility via fixtures.

source(test_path("helpers", "make_unbalanced_panel.R"))
ub <- make_unbalanced_panel()

# Helper: run all 6 invariant checks on an ffm fit
check_ffm_invariants <- function(fit, label) {
  cov_mat <- fmCov(fit)

  # 1. Symmetry
  expect_equal(cov_mat, t(cov_mat), info = paste(label, "symmetry"))

  # 2. PSD (eigenvalues >= 0)
  eig <- eigen(cov_mat, symmetric = TRUE, only.values = TRUE)$values
  expect_true(all(eig >= -1e-10), info = paste(label, "PSD"))

  # 3. Dimension match: nrow(fmCov) == nrow(beta)
  expect_equal(nrow(cov_mat), nrow(fit$beta), info = paste(label, "dim"))

  # 4. Name match: rownames(fmCov) == rownames(beta) == names(resid.var)
  expect_equal(rownames(cov_mat), rownames(fit$beta),
               info = paste(label, "rownames beta"))
  expect_equal(rownames(cov_mat), names(fit$resid.var),
               info = paste(label, "names resid.var"))

  # 5. Factor dimension match: colnames(factor.cov) == colnames(beta)
  expect_equal(colnames(fit$factor.cov), colnames(fit$beta),
               info = paste(label, "factor dim"))

  # 6. Identity: fmCov(fit) == beta %*% factor.cov %*% t(beta) + diag(resid.var)
  manual <- fit$beta %*% fit$factor.cov %*% t(fit$beta) + diag(fit$resid.var)
  expect_equal(cov_mat, manual, tolerance = 1e-8,
               info = paste(label, "identity"))
}

# --- Balanced panel models ---

test_that("fmCov invariants: style-only LS (DJIA)", {
  fit <- fitFfm(
    data = factorDataSetDjia5Yrs,
    asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
    exposure.vars = c("P2B", "EV2S")
  )
  check_ffm_invariants(fit, "style-only-LS")
})

test_that("fmCov invariants: sector+style LS (DJIA)", {
  fit <- fitFfm(
    data = factorDataSetDjia5Yrs,
    asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
    exposure.vars = c("SECTOR", "P2B"),
    addIntercept = TRUE
  )
  check_ffm_invariants(fit, "sector-style-LS")
})

test_that("fmCov invariants: WLS (stocks145)", {
  fit <- fitFfm(
    data = dat145, asset.var = "TICKER", ret.var = "RETURN",
    date.var = "DATE",
    exposure.vars = c("SECTOR", "ROE", "BP", "PM12M1M", "SIZE",
                      "ANNVOL1M", "EP"),
    addIntercept = TRUE, fit.method = "WLS",
    resid.scaleType = "EWMA", lambda = 0.9
  )
  check_ffm_invariants(fit, "WLS")
})

test_that("fmCov invariants: W-Rob (DJIA)", {
  skip_if_not_installed("RobStatTM")
  skip_if_not_installed("robustbase")
  fit <- fitFfm(
    data = factorDataSetDjia5Yrs,
    asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
    exposure.vars = c("SECTOR", "P2B"),
    addIntercept = TRUE, fit.method = "W-Rob"
  )
  check_ffm_invariants(fit, "W-Rob")
})

test_that("fmCov invariants: sector-only LS (DJIA)", {
  fit <- fitFfm(
    data = factorDataSetDjia5Yrs,
    asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
    exposure.vars = "SECTOR",
    addIntercept = TRUE
  )
  check_ffm_invariants(fit, "sector-only-LS")
})

# --- Unbalanced panel models ---

test_that("fmCov invariants: unbalanced style-only", {
  fit <- fitFfm(
    data = ub$data, asset.var = "TICKER", ret.var = "RETURN",
    date.var = "DATE", exposure.vars = c("P2B", "SIZE")
  )
  check_ffm_invariants(fit, "unbalanced-style")
})

test_that("fmCov invariants: unbalanced sector+style", {
  fit <- fitFfm(
    data = ub$data, asset.var = "TICKER", ret.var = "RETURN",
    date.var = "DATE", exposure.vars = c("SECTOR", "P2B"),
    addIntercept = TRUE
  )
  check_ffm_invariants(fit, "unbalanced-sector-style")
})

# --- TSFM invariants ---

test_that("fmCov invariants: TSFM LS (managers)", {
  fit <- fitTsfm(
    asset.names = colnames(managers[, 1:6]),
    factor.names = colnames(managers[, 7:9]),
    rf.name = colnames(managers[, 10]),
    data = managers
  )
  cov_mat <- fmCov(fit)

  expect_equal(cov_mat, t(cov_mat))
  eig <- eigen(cov_mat, symmetric = TRUE, only.values = TRUE)$values
  expect_true(all(eig >= -1e-10))
  expect_equal(nrow(cov_mat), length(fit$asset.names))
  expect_equal(rownames(cov_mat), fit$asset.names)
  expect_equal(colnames(cov_mat), fit$asset.names)
})

# --- User-supplied factor covariance (TSFM only — fmCov.ffm does not accept it) ---

test_that("fmCov.tsfm accepts user-supplied factor.cov", {
  fit <- fitTsfm(
    asset.names = colnames(managers[, 1:6]),
    factor.names = colnames(managers[, 7:9]),
    rf.name = colnames(managers[, 10]),
    data = managers
  )
  factor <- as.matrix(fit$data[, fit$factor.names])
  default_cov <- cov(factor, use = "pairwise.complete.obs")
  # Shrink toward diagonal
  custom_cov <- 0.5 * default_cov + 0.5 * diag(diag(default_cov))

  cov_mat <- fmCov(fit, factor.cov = custom_cov)
  beta <- as.matrix(fit$beta)
  beta[is.na(beta)] <- 0
  manual <- beta %*% custom_cov %*% t(beta) + diag(fit$resid.sd^2)

  expect_equal(cov_mat, manual, tolerance = 1e-8)
  expect_equal(nrow(cov_mat), length(fit$asset.names))
})
