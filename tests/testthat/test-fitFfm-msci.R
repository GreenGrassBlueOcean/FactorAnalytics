# test-fitFfm-msci.R — MSCI model branch (2+ character exposures)
#
# The MSCI branch is triggered when specFfm() detects > 1 character exposure.
# It uses a dual restriction matrix to handle rank deficiency from two
# categorical variables (e.g. Sector + Region). This file tests:
#   1. Pure 2-char model (no numeric exposures) — LS
#   2. 2-char + style model (numeric exposures) — LS
#   3. Downstream methods: fmCov, fmSdDecomp, fmVaRDecomp, fmEsDecomp
#   4. WLS and W-Rob fit methods (pure + style)

# ── Synthetic data: add a REGION column to stocks145scores6 ──
# Use 2 regions with balanced assignment per sector (min 2 per cell)
dat_msci_test <- stocks145scores6[stocks145scores6$DATE >= as.Date("2012-01-01"), ]

sector_tickers <- split(
  unique(dat_msci_test$TICKER),
  dat_msci_test$SECTOR[match(unique(dat_msci_test$TICKER), dat_msci_test$TICKER)]
)
region_map <- do.call(rbind, lapply(names(sector_tickers), function(sec) {
  tk <- sector_tickers[[sec]]
  data.frame(
    TICKER = tk,
    REGION = rep(c("NorthAm", "Europe"), length.out = length(tk)),
    stringsAsFactors = FALSE
  )
}))
dat_msci_test <- merge(dat_msci_test, region_map, by = "TICKER")
# Telecom has only 3 stocks → singleton cells; remove it
dat_msci_test <- dat_msci_test[dat_msci_test$SECTOR != "Telecommunications", ]

n_assets <- length(unique(dat_msci_test$TICKER))
n_dates  <- length(unique(dat_msci_test$DATE))
n_sectors <- length(unique(dat_msci_test$SECTOR))
n_regions <- length(unique(dat_msci_test$REGION))

# ── 1. Pure MSCI model (2 character exposures, no numeric) ──

test_that("MSCI pure 2-char model fits and has correct structure", {
  fit <- fitFfm(data = dat_msci_test, asset.var = "TICKER", ret.var = "RETURN",
                date.var = "DATE", exposure.vars = c("SECTOR", "REGION"),
                addIntercept = TRUE)

  expect_s3_class(fit, "ffm")
  # model.MSCI lives on the spec, not the final object; verify via exposures.char

  expect_equal(length(fit$exposures.char), 2)

  # factor.names: Market + all sector levels + all region levels
  expect_equal(length(fit$factor.names), 1 + n_sectors + n_regions)
  expect_true("Market" %in% fit$factor.names)
  expect_true(all(unique(dat_msci_test$SECTOR) %in% fit$factor.names))
  expect_true(all(unique(dat_msci_test$REGION) %in% fit$factor.names))

  # beta dimensions: n_assets x length(factor.names)
  expect_equal(dim(fit$beta), c(n_assets, length(fit$factor.names)))
  expect_equal(rownames(fit$beta), sort(unique(dat_msci_test$TICKER)))

  # factor.returns: columns match factor.names
  expect_equal(ncol(fit$factor.returns), length(fit$factor.names))
  expect_equal(colnames(fit$factor.returns), fit$factor.names)

  # factor.cov: square, symmetric, conformable with beta
  expect_equal(dim(fit$factor.cov), rep(length(fit$factor.names), 2))
  expect_true(isSymmetric(fit$factor.cov))

  # restriction.mat should be set (not NULL)
  expect_false(is.null(fit$restriction.mat))
  expect_equal(nrow(fit$restriction.mat), n_sectors + n_regions + 1)
  expect_equal(ncol(fit$restriction.mat), n_sectors + n_regions - 1)

  # Market column in beta should be all 1s
  expect_true(all(fit$beta[, "Market"] == 1))

  # fmCov-derived return covariance: PSD
  cov_mat <- fmCov(fit)
  eig <- eigen(cov_mat, symmetric = TRUE, only.values = TRUE)$values
  expect_true(all(eig >= -1e-10))
})

# ── 2. MSCI + style model (2 char + numeric exposures) ──

test_that("MSCI 2-char + style model fits and has correct structure", {
  fit <- fitFfm(data = dat_msci_test, asset.var = "TICKER", ret.var = "RETURN",
                date.var = "DATE",
                exposure.vars = c("SECTOR", "REGION", "ROE", "BP"),
                addIntercept = TRUE)

  expect_s3_class(fit, "ffm")
  expect_equal(length(fit$exposures.char), 2)

  # factor.names: Market + style vars + sector levels + region levels
  expected_n <- 1 + 2 + n_sectors + n_regions
  expect_equal(length(fit$factor.names), expected_n)
  expect_equal(fit$factor.names[1], "Market")
  expect_true("ROE" %in% fit$factor.names)
  expect_true("BP" %in% fit$factor.names)

  # Style factors come right after Market, before categorical levels
  style_pos <- which(fit$factor.names %in% c("ROE", "BP"))
  cat_pos   <- which(fit$factor.names %in% unique(dat_msci_test$SECTOR))
  expect_true(all(style_pos < min(cat_pos)))

  # Dimensions
  expect_equal(dim(fit$beta), c(n_assets, expected_n))
  expect_equal(ncol(fit$factor.returns), expected_n)
  expect_equal(colnames(fit$beta), fit$factor.names)
  expect_equal(colnames(fit$factor.returns), fit$factor.names)

  # factor.cov: square, symmetric
  expect_equal(dim(fit$factor.cov), rep(expected_n, 2))
  expect_true(isSymmetric(fit$factor.cov))

  # Style betas should vary across assets (not constant like Market)
  expect_gt(sd(fit$beta[, "ROE"]), 0)
  expect_gt(sd(fit$beta[, "BP"]), 0)
})

# ── 3. Downstream methods on MSCI models ──

test_that("fmCov works on MSCI pure model", {
  fit <- fitFfm(data = dat_msci_test, asset.var = "TICKER", ret.var = "RETURN",
                date.var = "DATE", exposure.vars = c("SECTOR", "REGION"),
                addIntercept = TRUE)

  cov_mat <- fmCov(fit)
  expect_equal(dim(cov_mat), c(n_assets, n_assets))
  expect_true(isSymmetric(cov_mat))
  expect_true(all(diag(cov_mat) > 0))
})

test_that("fmCov works on MSCI + style model", {
  fit <- fitFfm(data = dat_msci_test, asset.var = "TICKER", ret.var = "RETURN",
                date.var = "DATE",
                exposure.vars = c("SECTOR", "REGION", "ROE", "BP"),
                addIntercept = TRUE)

  cov_mat <- fmCov(fit)
  expect_equal(dim(cov_mat), c(n_assets, n_assets))
  expect_true(isSymmetric(cov_mat))
  expect_true(all(diag(cov_mat) > 0))
})

test_that("Risk decomposition works on MSCI + style model", {
  fit <- fitFfm(data = dat_msci_test, asset.var = "TICKER", ret.var = "RETURN",
                date.var = "DATE",
                exposure.vars = c("SECTOR", "REGION", "ROE", "BP"),
                addIntercept = TRUE)

  sd_dec  <- fmSdDecomp(fit)
  var_dec <- fmVaRDecomp(fit)
  es_dec  <- fmEsDecomp(fit)

  n_factors <- length(fit$factor.names)

  # fmSdDecomp
  expect_equal(length(sd_dec$Sd.fm), n_assets)
  expect_true(all(sd_dec$Sd.fm > 0))
  expect_equal(dim(sd_dec$pcSd), c(n_assets, n_factors + 1))

  # fmVaRDecomp
  expect_equal(length(var_dec$VaR.fm), n_assets)
  expect_equal(dim(var_dec$pcVaR), c(n_assets, n_factors + 1))
  # Percentage contributions should sum to ~100%
  row_sums <- rowSums(var_dec$pcVaR)
  expect_true(all(abs(row_sums - 100) < 1e-6))

  # fmEsDecomp
  expect_equal(length(es_dec$ES.fm), n_assets)
  expect_equal(dim(es_dec$pcES), c(n_assets, n_factors + 1))
})

test_that("MSCI pure model risk decomposition percentage contributions sum to 100%", {
  fit <- fitFfm(data = dat_msci_test, asset.var = "TICKER", ret.var = "RETURN",
                date.var = "DATE", exposure.vars = c("SECTOR", "REGION"),
                addIntercept = TRUE)

  var_dec <- fmVaRDecomp(fit)
  row_sums <- rowSums(var_dec$pcVaR)
  expect_true(all(abs(row_sums - 100) < 1e-6))

  es_dec <- fmEsDecomp(fit)
  row_sums_es <- rowSums(es_dec$pcES)
  expect_true(all(abs(row_sums_es - 100) < 1e-6))
})

# ── 4. WLS and W-Rob fit methods ──

# Helper: fit MSCI model, check structure and downstream methods
check_msci_fit <- function(fit, expected_n_factors, label) {
  expect_s3_class(fit, "ffm")
  expect_equal(length(fit$exposures.char), 2)

  # Core dimensions

  expect_equal(length(fit$factor.names), expected_n_factors)
  expect_equal(dim(fit$beta), c(n_assets, expected_n_factors))
  expect_equal(ncol(fit$factor.returns), expected_n_factors)
  expect_equal(colnames(fit$beta), fit$factor.names)
  expect_equal(colnames(fit$factor.returns), fit$factor.names)

  # factor.cov symmetric and conformable
  expect_equal(dim(fit$factor.cov), rep(expected_n_factors, 2))
  expect_true(isSymmetric(fit$factor.cov))

  # Downstream: fmCov
  cov_mat <- fmCov(fit)
  expect_equal(dim(cov_mat), c(n_assets, n_assets))
  expect_true(isSymmetric(cov_mat))
  expect_true(all(diag(cov_mat) > 0))

  # Downstream: risk decomposition VaR sums to 100%
  var_dec <- fmVaRDecomp(fit)
  expect_equal(dim(var_dec$pcVaR), c(n_assets, expected_n_factors + 1))
  row_sums <- rowSums(var_dec$pcVaR)
  expect_true(all(abs(row_sums - 100) < 1e-6))
}

test_that("MSCI pure 2-char model works with WLS", {
  fit <- fitFfm(data = dat_msci_test, asset.var = "TICKER", ret.var = "RETURN",
                date.var = "DATE", exposure.vars = c("SECTOR", "REGION"),
                addIntercept = TRUE, fit.method = "WLS")
  check_msci_fit(fit, 1 + n_sectors + n_regions, "WLS pure")
})

test_that("MSCI 2-char + style model works with WLS", {
  fit <- fitFfm(data = dat_msci_test, asset.var = "TICKER", ret.var = "RETURN",
                date.var = "DATE",
                exposure.vars = c("SECTOR", "REGION", "ROE", "BP"),
                addIntercept = TRUE, fit.method = "WLS")
  check_msci_fit(fit, 1 + 2 + n_sectors + n_regions, "WLS+style")

  # Style betas should vary
  expect_gt(sd(fit$beta[, "ROE"]), 0)
  expect_gt(sd(fit$beta[, "BP"]), 0)
})

test_that("MSCI pure 2-char model works with W-Rob", {
  skip_if_not_installed("RobStatTM")
  fit <- fitFfm(data = dat_msci_test, asset.var = "TICKER", ret.var = "RETURN",
                date.var = "DATE", exposure.vars = c("SECTOR", "REGION"),
                addIntercept = TRUE, fit.method = "W-Rob")
  check_msci_fit(fit, 1 + n_sectors + n_regions, "W-Rob pure")
})

test_that("MSCI 2-char + style model works with W-Rob", {
  skip_if_not_installed("RobStatTM")
  # lmrobdetMM may not converge on some cross-sections with many dummies
  fit <- suppressWarnings(fitFfm(
    data = dat_msci_test, asset.var = "TICKER", ret.var = "RETURN",
    date.var = "DATE",
    exposure.vars = c("SECTOR", "REGION", "ROE", "BP"),
    addIntercept = TRUE, fit.method = "W-Rob"))
  check_msci_fit(fit, 1 + 2 + n_sectors + n_regions, "W-Rob+style")

  # Style betas should vary
  expect_gt(sd(fit$beta[, "ROE"]), 0)
  expect_gt(sd(fit$beta[, "BP"]), 0)
})
