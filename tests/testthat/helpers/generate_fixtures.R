#!/usr/bin/env Rscript
# =============================================================================
# generate_fixtures.R — One-time fixture generation for Phase 0.2
#
# Run this ONCE against the UNMODIFIED upstream code to produce gold-standard
# reference outputs. Every subsequent refactoring phase must reproduce these
# fixtures within the specified tolerances.
#
# Usage:
#   source("tests/testthat/helpers/generate_fixtures.R")
#
# Output:
#   tests/testthat/fixtures/*.rds
#
# IMPORTANT: Do NOT save full fitted objects (lm, ffm, tsfm). R's serialization
# silently captures environments attached to formula/terms objects, producing
# multi-GB .rds files. Save only numeric components needed for assertions.
# =============================================================================

library(FactorAnalytics)
library(zoo)

fixture_dir <- "tests/testthat/fixtures"
if (!dir.exists(fixture_dir)) dir.create(fixture_dir, recursive = TRUE)

save_fixture <- function(obj, name) {
  path <- file.path(fixture_dir, paste0(name, ".rds"))
  saveRDS(obj, path, compress = "xz")
  message("Saved: ", path)
}

# Extract numeric-only slots from an ffm object
extract_ffm_slots <- function(fit) {
  list(
    beta           = fit$beta,
    factor.returns = as.matrix(fit$factor.returns),
    residuals      = as.matrix(fit$residuals),
    factor.cov     = fit$factor.cov,
    resid.var      = fit$resid.var,
    r2             = fit$r2,
    asset.names    = fit$asset.names,
    factor.names   = fit$factor.names,
    time.periods   = fit$time.periods,
    exposures.num  = fit$exposures.num,
    exposures.char = fit$exposures.char
  )
}

# Extract numeric-only slots from a tsfm object
extract_tsfm_slots <- function(fit) {
  list(
    alpha       = as.data.frame(fit$alpha),
    beta        = as.data.frame(fit$beta),
    r2          = fit$r2,
    resid.sd    = fit$resid.sd,
    residuals   = as.matrix(residuals(fit)),
    fitted      = as.matrix(fitted(fit)),
    asset.names = fit$asset.names,
    factor.names = fit$factor.names
  )
}

# =============================================================================
# 1. FUNDAMENTAL FACTOR MODEL FIXTURES
# =============================================================================

data("factorDataSetDjia5Yrs")
data("stocks145scores6")
data("wtsDjiaGmvLo")
data("wtsStocks145GmvLo")

# --- 1a. FFM LS, style-only (0 char exposures → model.styleOnly path) ---
message("\n--- FFM LS style-only ---")
fit_ffm_ls_style <- fitFfm(
  data = factorDataSetDjia5Yrs,
  asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
  exposure.vars = c("P2B", "EV2S")
)
save_fixture(extract_ffm_slots(fit_ffm_ls_style), "fixture_ffm_ls_style")

# --- 1b. FFM LS, sector + style + intercept (1 char exposure) ---
message("\n--- FFM LS sector+style ---")
fit_ffm_ls_sector <- fitFfm(
  data = factorDataSetDjia5Yrs,
  asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
  exposure.vars = c("SECTOR", "P2B", "EV2S"),
  addIntercept = TRUE
)
save_fixture(extract_ffm_slots(fit_ffm_ls_sector), "fixture_ffm_ls_sector")

# --- 1c. FFM WLS, sector + style (the most common production path) ---
message("\n--- FFM WLS sector+style ---")
dat145 <- stocks145scores6
dat145$DATE <- as.yearmon(dat145$DATE)
dat145 <- dat145[dat145$DATE >= as.yearmon("2008-01-01") &
                   dat145$DATE <= as.yearmon("2012-12-31"), ]

fit_ffm_wls <- fitFfm(
  data = dat145,
  exposure.vars = c("SECTOR", "ROE", "BP", "PM12M1M", "SIZE", "ANNVOL1M", "EP"),
  date.var = "DATE", ret.var = "RETURN", asset.var = "TICKER",
  fit.method = "WLS", z.score = "crossSection"
)
save_fixture(extract_ffm_slots(fit_ffm_wls), "fixture_ffm_wls")

# --- 1d. FFM W-Rob, sector + style (robust path) ---
message("\n--- FFM W-Rob robust ---")
fit_ffm_wrob <- fitFfm(
  data = factorDataSetDjia5Yrs,
  asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
  exposure.vars = c("SECTOR", "P2B"),
  fit.method = "W-Rob"
)
save_fixture(extract_ffm_slots(fit_ffm_wrob), "fixture_ffm_wrob")

# --- 1e. FFM sector-only (no numeric exposures, just SECTOR) ---
message("\n--- FFM sector-only ---")
fit_ffm_sector_only <- fitFfm(
  data = factorDataSetDjia5Yrs,
  asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
  exposure.vars = "SECTOR"
)
save_fixture(extract_ffm_slots(fit_ffm_sector_only), "fixture_ffm_sector_only")


# =============================================================================
# 2. TIME SERIES FACTOR MODEL FIXTURES
# =============================================================================

data(managers, package = "PerformanceAnalytics")
colnames(managers) <- make.names(colnames(managers))

# --- 2a. TSFM LS, no variable selection ---
message("\n--- TSFM LS ---")
fit_tsfm_ls <- fitTsfm(
  asset.names = colnames(managers[, 1:6]),
  factor.names = colnames(managers[, 7:9]),
  rf.name = colnames(managers[, 10]),
  data = managers
)
save_fixture(extract_tsfm_slots(fit_tsfm_ls), "fixture_tsfm_ls")

# --- 2b. TSFM Robust ---
message("\n--- TSFM Robust ---")
fit_tsfm_robust <- fitTsfm(
  asset.names = colnames(managers[, 1:6]),
  factor.names = colnames(managers[, 7:9]),
  rf.name = colnames(managers[, 10]),
  data = managers,
  fit.method = "Robust"
)
save_fixture(extract_tsfm_slots(fit_tsfm_robust), "fixture_tsfm_robust")

# --- 2c. TSFM lars variable selection ---
message("\n--- TSFM lars ---")
fit_tsfm_lars <- fitTsfm(
  asset.names = colnames(managers[, 1:6]),
  factor.names = colnames(managers[, 7:9]),
  rf.name = colnames(managers[, 10]),
  data = managers,
  variable.selection = "lars"
)
save_fixture(extract_tsfm_slots(fit_tsfm_lars), "fixture_tsfm_lars")


# =============================================================================
# 3. COVARIANCE MATRIX FIXTURES
# =============================================================================

# --- 3a. fmCov on FFM ---
message("\n--- fmCov FFM ---")
cov_ffm <- fmCov(fit_ffm_wls)
save_fixture(list(
  cov = cov_ffm,
  rownames = rownames(cov_ffm),
  colnames = colnames(cov_ffm)
), "fixture_fmCov_ffm")

# --- 3b. fmCov on TSFM ---
message("\n--- fmCov TSFM ---")
cov_tsfm <- fmCov(fit_tsfm_ls)
save_fixture(list(
  cov = cov_tsfm,
  rownames = rownames(cov_tsfm),
  colnames = colnames(cov_tsfm)
), "fixture_fmCov_tsfm")

# --- 3c. Covariance identity: beta %*% factor.cov %*% t(beta) + diag(resid.var) ---
message("\n--- Covariance identity (WLS) ---")
# Verify the identity on the WLS fit, save the components
cov_identity_ffm <- list(
  direct = cov_ffm,
  reconstructed = fit_ffm_wls$beta %*% fit_ffm_wls$factor.cov %*% t(fit_ffm_wls$beta) +
    diag(fit_ffm_wls$resid.var)
)
save_fixture(cov_identity_ffm, "fixture_cov_identity_ffm")


# =============================================================================
# 4. RISK DECOMPOSITION FIXTURES
# =============================================================================

wts145 <- round(wtsStocks145GmvLo, 5)

# --- 4a. fmSdDecomp on FFM ---
message("\n--- fmSdDecomp FFM ---")
sd_decomp_ffm <- fmSdDecomp(fit_ffm_wls)
save_fixture(list(
  Sd.fm    = sd_decomp_ffm$Sd.fm,
  mSd      = sd_decomp_ffm$mSd,
  cSd      = sd_decomp_ffm$cSd,
  pcSd     = sd_decomp_ffm$pcSd
), "fixture_fmSdDecomp_ffm")

# --- 4b. fmVaRDecomp on FFM ---
message("\n--- fmVaRDecomp FFM ---")
var_decomp_ffm <- fmVaRDecomp(fit_ffm_wls)
save_fixture(list(
  VaR.fm   = var_decomp_ffm$VaR.fm,
  mVaR     = var_decomp_ffm$mVaR,
  cVaR     = var_decomp_ffm$cVaR,
  pcVaR    = var_decomp_ffm$pcVaR
), "fixture_fmVaRDecomp_ffm")

# --- 4c. fmEsDecomp on FFM ---
message("\n--- fmEsDecomp FFM ---")
es_decomp_ffm <- fmEsDecomp(fit_ffm_wls)
save_fixture(list(
  ES.fm    = es_decomp_ffm$ES.fm,
  mES      = es_decomp_ffm$mES,
  cES      = es_decomp_ffm$cES,
  pcES     = es_decomp_ffm$pcES
), "fixture_fmEsDecomp_ffm")


# =============================================================================
# 5. PORTFOLIO-LEVEL RISK DECOMPOSITION FIXTURES
# =============================================================================

# --- 5a. portSdDecomp on TSFM ---
message("\n--- portSdDecomp TSFM ---")
port_sd_tsfm <- portSdDecomp(fit_tsfm_ls)
save_fixture(list(
  Sd.fm   = port_sd_tsfm$Sd.fm,
  mSd     = port_sd_tsfm$mSd,
  cSd     = port_sd_tsfm$cSd,
  pcSd    = port_sd_tsfm$pcSd
), "fixture_portSdDecomp_tsfm")

# --- 5b. portVaRDecomp on TSFM ---
message("\n--- portVaRDecomp TSFM ---")
port_var_tsfm <- portVaRDecomp(fit_tsfm_ls, p = 0.9, type = "normal")
save_fixture(list(
  VaR.fm  = port_var_tsfm$VaR.fm,
  mVaR    = port_var_tsfm$mVaR,
  cVaR    = port_var_tsfm$cVaR,
  pcVaR   = port_var_tsfm$pcVaR
), "fixture_portVaRDecomp_tsfm")

# --- 5c. portEsDecomp on TSFM ---
message("\n--- portEsDecomp TSFM ---")
port_es_tsfm <- portEsDecomp(fit_tsfm_ls, p = 0.9, type = "normal")
save_fixture(list(
  ES.fm   = port_es_tsfm$ES.fm,
  mES     = port_es_tsfm$mES,
  cES     = port_es_tsfm$cES,
  pcES    = port_es_tsfm$pcES
), "fixture_portEsDecomp_tsfm")

# --- 5d. portSdDecomp on FFM (with weights) ---
message("\n--- portSdDecomp FFM ---")
port_sd_ffm <- portSdDecomp(fit_ffm_wls, wts145)
save_fixture(list(
  Sd.fm   = port_sd_ffm$Sd.fm,
  mSd     = port_sd_ffm$mSd,
  cSd     = port_sd_ffm$cSd,
  pcSd    = port_sd_ffm$pcSd
), "fixture_portSdDecomp_ffm")

# --- 5e. portVaRDecomp on FFM (with weights) ---
message("\n--- portVaRDecomp FFM ---")
port_var_ffm <- portVaRDecomp(fit_ffm_wls, wts145, p = 0.9, type = "normal")
save_fixture(list(
  VaR.fm  = port_var_ffm$VaR.fm,
  mVaR    = port_var_ffm$mVaR,
  cVaR    = port_var_ffm$cVaR,
  pcVaR   = port_var_ffm$pcVaR
), "fixture_portVaRDecomp_ffm")

# --- 5f. portEsDecomp on FFM (with weights) ---
message("\n--- portEsDecomp FFM ---")
port_es_ffm <- portEsDecomp(fit_ffm_wls, wts145, p = 0.9, type = "normal")
save_fixture(list(
  ES.fm   = port_es_ffm$ES.fm,
  mES     = port_es_ffm$mES,
  cES     = port_es_ffm$cES,
  pcES    = port_es_ffm$pcES
), "fixture_portEsDecomp_ffm")


# =============================================================================
# 6. AUXILIARY FUNCTION FIXTURES
# =============================================================================

# --- 6a. fmRsq ---
message("\n--- fmRsq ---")
rsq_out <- fmRsq(fit_ffm_wls, rsq = TRUE, rsqAdj = TRUE, isPrint = FALSE)
save_fixture(rsq_out, "fixture_fmRsq")

# --- 6b. fmTstats ---
message("\n--- fmTstats ---")
tstats_out <- fmTstats(fit_ffm_wls, isPlot = FALSE)
save_fixture(tstats_out, "fixture_fmTstats")


# =============================================================================
# SUMMARY
# =============================================================================
message("\n=== Fixture generation complete ===")
fixture_files <- list.files(fixture_dir, pattern = "\\.rds$", full.names = TRUE)
for (f in fixture_files) {
  message(sprintf("  %s (%s)", basename(f), format(file.size(f), big.mark = ",")))
}
message(sprintf("\nTotal: %d fixtures", length(fixture_files)))
