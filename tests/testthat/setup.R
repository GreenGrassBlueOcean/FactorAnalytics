# =============================================================================
# setup.R — Shared test setup for FactorAnalytics testthat suite
#
# This file is sourced automatically by testthat before any test file runs.
# It loads common datasets and pre-fits models used across multiple test files.
# =============================================================================

library(FactorAnalytics)
library(zoo)
library(data.table)

# --- Bundled datasets ---
data("factorDataSetDjia5Yrs")
data("stocks145scores6")
data("wtsDjiaGmvLo")
data("wtsStocks145GmvLo")
data(managers, package = "PerformanceAnalytics")
colnames(managers) <- make.names(colnames(managers))

# --- Prepare stocks145 subset (2008–2012, as.yearmon dates) ---
dat145 <- stocks145scores6
dat145$DATE <- as.yearmon(dat145$DATE)
dat145 <- dat145[dat145$DATE >= as.yearmon("2008-01-01") &
                   dat145$DATE <= as.yearmon("2012-12-31"), ]

wts145 <- round(wtsStocks145GmvLo, 5)
