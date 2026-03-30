# =============================================================================
# test-helpers-extract-stats.R — Unit tests for Phase 8 helpers
#
# Tests build_factor_names() and map_coefficients_to_factor_returns().
# These helpers are used inside extractRegressionStats() to deduplicate
# factor name construction and coefficient mapping logic.
# =============================================================================

# --- build_factor_names ---

# Helper to create specObj with factor-converted dataDT (as fitFfmDT does)
make_spec_with_factors <- function(...) {
  spec <- specFfm(...)
  for (v in spec$exposures.char) {
    spec$dataDT[, (v) := as.factor(get(v))]
  }
  spec
}

test_that("build_factor_names: style-only with intercept → c('Alpha', style)", {
  spec <- make_spec_with_factors(
    data = factorDataSetDjia5Yrs,
    asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
    exposure.vars = c("P2B", "EV2S"), addIntercept = TRUE
  )
  result <- FactorAnalytics:::build_factor_names(spec)
  expect_equal(result, c("Alpha", "P2B", "EV2S"))
})

test_that("build_factor_names: style-only no intercept → style only", {
  spec <- make_spec_with_factors(
    data = factorDataSetDjia5Yrs,
    asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
    exposure.vars = c("P2B", "EV2S"), addIntercept = FALSE
  )
  result <- FactorAnalytics:::build_factor_names(spec)
  expect_equal(result, c("P2B", "EV2S"))
})

test_that("build_factor_names: sector+style+intercept matches fixture", {
  spec <- make_spec_with_factors(
    data = factorDataSetDjia5Yrs,
    asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
    exposure.vars = c("SECTOR", "P2B", "EV2S"), addIntercept = TRUE
  )
  result <- FactorAnalytics:::build_factor_names(spec)
  fix <- readRDS(test_path("fixtures", "fixture_ffm_ls_sector.rds"))
  expect_equal(result, fix$factor.names)
})

test_that("build_factor_names: sector+style no intercept matches fixture", {
  spec <- make_spec_with_factors(
    data = dat145,
    exposure.vars = c("SECTOR", "ROE", "BP", "PM12M1M", "SIZE", "ANNVOL1M", "EP"),
    date.var = "DATE", ret.var = "RETURN", asset.var = "TICKER"
  )
  result <- FactorAnalytics:::build_factor_names(spec)
  fix <- readRDS(test_path("fixtures", "fixture_ffm_wls.rds"))
  expect_equal(result, fix$factor.names)
})

test_that("build_factor_names: sector-only no intercept matches fixture", {
  spec <- make_spec_with_factors(
    data = factorDataSetDjia5Yrs,
    asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
    exposure.vars = "SECTOR"
  )
  result <- FactorAnalytics:::build_factor_names(spec)
  fix <- readRDS(test_path("fixtures", "fixture_ffm_sector_only.rds"))
  expect_equal(result, fix$factor.names)
})

test_that("build_factor_names: MSCI pure model has Market + all levels", {
  # Use MSCI test data (same setup as test-fitFfm-msci.R)
  dat_m <- stocks145scores6[stocks145scores6$DATE >= as.Date("2012-01-01"), ]
  sector_tickers <- split(
    unique(dat_m$TICKER),
    dat_m$SECTOR[match(unique(dat_m$TICKER), dat_m$TICKER)]
  )
  region_map <- do.call(rbind, lapply(names(sector_tickers), function(sec) {
    tk <- sector_tickers[[sec]]
    data.frame(TICKER = tk,
               REGION = rep(c("NorthAm", "Europe"), length.out = length(tk)),
               stringsAsFactors = FALSE)
  }))
  dat_m <- merge(dat_m, region_map, by = "TICKER")
  dat_m <- dat_m[dat_m$SECTOR != "Telecommunications", ]

  spec <- make_spec_with_factors(
    data = dat_m, asset.var = "TICKER", ret.var = "RETURN",
    date.var = "DATE", exposure.vars = c("SECTOR", "REGION"),
    addIntercept = TRUE
  )
  result <- FactorAnalytics:::build_factor_names(spec)

  expect_equal(result[1], "Market")
  expect_true(all(levels(spec$dataDT[["SECTOR"]]) %in% result))
  expect_true(all(levels(spec$dataDT[["REGION"]]) %in% result))
  expect_equal(length(result),
               1 + nlevels(spec$dataDT[["SECTOR"]]) + nlevels(spec$dataDT[["REGION"]]))
})

test_that("build_factor_names: MSCI+style model has Market + style + levels", {
  dat_m <- stocks145scores6[stocks145scores6$DATE >= as.Date("2012-01-01"), ]
  sector_tickers <- split(
    unique(dat_m$TICKER),
    dat_m$SECTOR[match(unique(dat_m$TICKER), dat_m$TICKER)]
  )
  region_map <- do.call(rbind, lapply(names(sector_tickers), function(sec) {
    tk <- sector_tickers[[sec]]
    data.frame(TICKER = tk,
               REGION = rep(c("NorthAm", "Europe"), length.out = length(tk)),
               stringsAsFactors = FALSE)
  }))
  dat_m <- merge(dat_m, region_map, by = "TICKER")
  dat_m <- dat_m[dat_m$SECTOR != "Telecommunications", ]

  spec <- make_spec_with_factors(
    data = dat_m, asset.var = "TICKER", ret.var = "RETURN",
    date.var = "DATE", exposure.vars = c("SECTOR", "REGION", "ROE", "BP"),
    addIntercept = TRUE
  )
  result <- FactorAnalytics:::build_factor_names(spec)

  expect_equal(result[1], "Market")
  expect_true("ROE" %in% result)
  expect_true("BP" %in% result)
  total_expected <- 1 + 2 + nlevels(spec$dataDT[["SECTOR"]]) + nlevels(spec$dataDT[["REGION"]])
  expect_equal(length(result), total_expected)
})

# --- map_coefficients_to_factor_returns ---

test_that("map_coefficients_to_factor_returns: sector+style+intercept exact match", {
  fit <- fitFfm(
    data = factorDataSetDjia5Yrs,
    asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
    exposure.vars = c("SECTOR", "P2B", "EV2S"), addIntercept = TRUE
  )
  R_mat <- fit$restriction.mat
  K_cat <- ncol(R_mat)
  fr_cols <- colnames(fit$factor.returns)

  for (i in c(1, 10, 30)) {
    g <- coefficients(fit$factor.fit[[i]])
    result <- FactorAnalytics:::map_coefficients_to_factor_returns(g, R_mat, K_cat, fr_cols)
    actual <- as.numeric(fit$factor.returns[i, ])
    names(actual) <- fr_cols
    expect_equal(result, actual, tolerance = 1e-10,
                 info = paste("period", i))
  }
})

test_that("map_coefficients_to_factor_returns: sector-only+intercept exact match", {
  fit <- fitFfm(
    data = factorDataSetDjia5Yrs,
    asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
    exposure.vars = "SECTOR", addIntercept = TRUE
  )
  R_mat <- fit$restriction.mat
  K_cat <- ncol(R_mat)
  fr_cols <- colnames(fit$factor.returns)

  g <- coefficients(fit$factor.fit[[1]])
  result <- FactorAnalytics:::map_coefficients_to_factor_returns(g, R_mat, K_cat, fr_cols)
  actual <- as.numeric(fit$factor.returns[1, ])
  names(actual) <- fr_cols
  expect_equal(result, actual, tolerance = 1e-10)
})

test_that("map_coefficients_to_factor_returns: MSCI pure exact match", {
  dat_m <- stocks145scores6[stocks145scores6$DATE >= as.Date("2012-01-01"), ]
  sector_tickers <- split(
    unique(dat_m$TICKER),
    dat_m$SECTOR[match(unique(dat_m$TICKER), dat_m$TICKER)]
  )
  region_map <- do.call(rbind, lapply(names(sector_tickers), function(sec) {
    tk <- sector_tickers[[sec]]
    data.frame(TICKER = tk,
               REGION = rep(c("NorthAm", "Europe"), length.out = length(tk)),
               stringsAsFactors = FALSE)
  }))
  dat_m <- merge(dat_m, region_map, by = "TICKER")
  dat_m <- dat_m[dat_m$SECTOR != "Telecommunications", ]

  fit <- fitFfm(data = dat_m, asset.var = "TICKER", ret.var = "RETURN",
                date.var = "DATE", exposure.vars = c("SECTOR", "REGION"),
                addIntercept = TRUE)

  R_mat <- fit$restriction.mat
  K_cat <- ncol(R_mat)
  fr_cols <- colnames(fit$factor.returns)

  g <- coefficients(fit$factor.fit[[1]])
  result <- FactorAnalytics:::map_coefficients_to_factor_returns(g, R_mat, K_cat, fr_cols)
  actual <- as.numeric(fit$factor.returns[1, ])
  names(actual) <- fr_cols
  expect_equal(result, actual, tolerance = 1e-10)
})

test_that("map_coefficients_to_factor_returns: MSCI+style exact match", {
  dat_m <- stocks145scores6[stocks145scores6$DATE >= as.Date("2012-01-01"), ]
  sector_tickers <- split(
    unique(dat_m$TICKER),
    dat_m$SECTOR[match(unique(dat_m$TICKER), dat_m$TICKER)]
  )
  region_map <- do.call(rbind, lapply(names(sector_tickers), function(sec) {
    tk <- sector_tickers[[sec]]
    data.frame(TICKER = tk,
               REGION = rep(c("NorthAm", "Europe"), length.out = length(tk)),
               stringsAsFactors = FALSE)
  }))
  dat_m <- merge(dat_m, region_map, by = "TICKER")
  dat_m <- dat_m[dat_m$SECTOR != "Telecommunications", ]

  fit <- fitFfm(data = dat_m, asset.var = "TICKER", ret.var = "RETURN",
                date.var = "DATE", exposure.vars = c("SECTOR", "REGION", "ROE", "BP"),
                addIntercept = TRUE)

  R_mat <- fit$restriction.mat
  K_cat <- ncol(R_mat)
  fr_cols <- colnames(fit$factor.returns)

  for (i in c(1, 6)) {
    g <- coefficients(fit$factor.fit[[i]])
    result <- FactorAnalytics:::map_coefficients_to_factor_returns(g, R_mat, K_cat, fr_cols)
    actual <- as.numeric(fit$factor.returns[i, ])
    names(actual) <- fr_cols
    expect_equal(result, actual, tolerance = 1e-10,
                 info = paste("period", i))
  }
})

# --- Round-trip: full pipeline produces identical output ---

test_that("build_factor_names matches fitFfm factor.names for all model types", {
  # Style-only
  fit1 <- fitFfm(data = factorDataSetDjia5Yrs,
                 asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
                 exposure.vars = c("P2B", "EV2S"))
  spec1 <- make_spec_with_factors(
    data = factorDataSetDjia5Yrs,
    asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
    exposure.vars = c("P2B", "EV2S"))
  expect_equal(FactorAnalytics:::build_factor_names(spec1), fit1$factor.names)

  # Sector+style+intercept
  fit2 <- fitFfm(data = factorDataSetDjia5Yrs,
                 asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
                 exposure.vars = c("SECTOR", "P2B", "EV2S"), addIntercept = TRUE)
  spec2 <- make_spec_with_factors(
    data = factorDataSetDjia5Yrs,
    asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
    exposure.vars = c("SECTOR", "P2B", "EV2S"), addIntercept = TRUE)
  expect_equal(FactorAnalytics:::build_factor_names(spec2), fit2$factor.names)
})
