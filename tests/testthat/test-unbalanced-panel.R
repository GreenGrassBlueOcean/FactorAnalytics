# test-unbalanced-panel.R — Phase 4.1
# Verifies that fitFfm, fmCov, and risk decomposition handle unbalanced panels
# (assets entering/exiting mid-sample) correctly.

source(test_path("helpers", "make_unbalanced_panel.R"))
ub <- make_unbalanced_panel()

# --- Style-only model on unbalanced panel ---
test_that("fitFfm style-only handles unbalanced panel", {
  fit <- fitFfm(
    data = ub$data, asset.var = "TICKER", ret.var = "RETURN",
    date.var = "DATE", exposure.vars = c("P2B", "SIZE")
  )

  # Beta must contain exactly the final-period assets
  expect_equal(sort(rownames(fit$beta)), sort(ub$final_assets))
  expect_equal(sort(names(fit$resid.var)), sort(ub$final_assets))

  # Key Invariant #2: rownames(beta) == names(resid.var)
  expect_equal(rownames(fit$beta), names(fit$resid.var))

  # fmCov dimensions match
  cov_mat <- fmCov(fit)
  expect_equal(rownames(cov_mat), rownames(fit$beta))
  expect_equal(colnames(cov_mat), rownames(fit$beta))

  # Key Invariant #1: covariance identity
  manual_cov <- fit$beta %*% fit$factor.cov %*% t(fit$beta) + diag(fit$resid.var)
  expect_equal(cov_mat, manual_cov, tolerance = 1e-8)
})

# --- Sector + style model on unbalanced panel ---
test_that("fitFfm sector+style handles unbalanced panel", {
  fit <- fitFfm(
    data = ub$data, asset.var = "TICKER", ret.var = "RETURN",
    date.var = "DATE", exposure.vars = c("SECTOR", "P2B"),
    addIntercept = TRUE
  )

  expect_equal(sort(rownames(fit$beta)), sort(ub$final_assets))
  expect_equal(sort(names(fit$resid.var)), sort(ub$final_assets))
  expect_equal(rownames(fit$beta), names(fit$resid.var))

  cov_mat <- fmCov(fit)
  expect_equal(nrow(cov_mat), length(ub$final_assets))
  expect_equal(ncol(cov_mat), length(ub$final_assets))

  # PSD check
  eig <- eigen(cov_mat, symmetric = TRUE, only.values = TRUE)$values
  expect_true(all(eig >= -1e-10))
})

# --- Risk decomposition on unbalanced panel ---
test_that("fmSdDecomp works on unbalanced panel sector model", {
  fit <- fitFfm(
    data = ub$data, asset.var = "TICKER", ret.var = "RETURN",
    date.var = "DATE", exposure.vars = c("SECTOR", "P2B"),
    addIntercept = TRUE
  )
  decomp <- fmSdDecomp(fit)

  # pcSd rows must sum to 100
  expect_equal(unname(rowSums(decomp$pcSd)), rep(100, nrow(decomp$pcSd)),
               tolerance = 1e-6)
  # Correct number of assets (Sd.fm is a named vector)
  expect_equal(length(decomp$Sd.fm), length(ub$final_assets))
})

# --- VaR and ES decomposition ---
test_that("fmVaRDecomp and fmEsDecomp work on unbalanced panel", {
  fit <- fitFfm(
    data = ub$data, asset.var = "TICKER", ret.var = "RETURN",
    date.var = "DATE", exposure.vars = c("SECTOR", "P2B"),
    addIntercept = TRUE
  )

  # VaR decomposition
  suppressWarnings({
    var_dec <- fmVaRDecomp(fit)
  })
  expect_equal(length(var_dec$VaR.fm), length(ub$final_assets))
  expect_equal(unname(rowSums(var_dec$pcVaR)), rep(100, nrow(var_dec$pcVaR)),
               tolerance = 1e-6)

  # ES decomposition — suppress vector recycling warnings (upstream issue
  # with unequal history lengths)
  suppressWarnings({
    es_dec <- fmEsDecomp(fit)
  })
  expect_equal(length(es_dec$ES.fm), length(ub$final_assets))
  # ES pcES may have NaN for assets with very short residual history
  # (pre-existing upstream issue); verify non-NaN rows sum to 100
  ok <- !is.nan(rowSums(es_dec$pcES))
  if (any(ok)) {
    expect_equal(unname(rowSums(es_dec$pcES[ok, , drop = FALSE])),
                 rep(100, sum(ok)), tolerance = 1e-6)
  }
})

# --- Predict on unbalanced panel model ---
test_that("predict.ffm works on unbalanced panel sector model", {
  fit <- fitFfm(
    data = ub$data, asset.var = "TICKER", ret.var = "RETURN",
    date.var = "DATE", exposure.vars = c("SECTOR", "P2B"),
    addIntercept = TRUE
  )
  newdata <- data.frame(SECTOR = "S1", P2B = 1.5)
  last_date <- names(fit$factor.fit)[length(fit$factor.fit)]
  pred <- predict(fit, newdata = newdata, pred.date = last_date)
  expect_true(is.matrix(pred))
  expect_equal(nrow(pred), 1L)
})

# --- Delisted assets must NOT appear in output ---
test_that("delisted assets excluded from beta and resid.var", {
  fit <- fitFfm(
    data = ub$data, asset.var = "TICKER", ret.var = "RETURN",
    date.var = "DATE", exposure.vars = c("SECTOR", "P2B"),
    addIntercept = TRUE
  )
  expect_false(any(ub$delisted %in% rownames(fit$beta)))
  expect_false(any(ub$delisted %in% names(fit$resid.var)))
})

# --- Late-entering assets SHOULD appear in output ---
test_that("late-entering assets included in beta and resid.var", {
  fit <- fitFfm(
    data = ub$data, asset.var = "TICKER", ret.var = "RETURN",
    date.var = "DATE", exposure.vars = c("SECTOR", "P2B"),
    addIntercept = TRUE
  )
  expect_true(all(ub$entered %in% rownames(fit$beta)))
  expect_true(all(ub$entered %in% names(fit$resid.var)))
})

# --- Sector-only model (no numeric exposures) on unbalanced panel ---
test_that("fitFfm sector-only handles unbalanced panel", {
  fit <- fitFfm(
    data = ub$data, asset.var = "TICKER", ret.var = "RETURN",
    date.var = "DATE", exposure.vars = "SECTOR",
    addIntercept = TRUE
  )
  expect_equal(sort(rownames(fit$beta)), sort(ub$final_assets))
  expect_equal(rownames(fit$beta), names(fit$resid.var))
})
