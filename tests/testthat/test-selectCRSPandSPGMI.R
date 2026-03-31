# test-selectCRSPandSPGMI.R
# Covers: selectCRSPandSPGMI() — all 13 executable lines.
# Requires PCRA package for stocksCRSP and factorsSPGMI datasets.

skip_if_not_installed("PCRA")

data(stocksCRSP, package = "PCRA")
data(factorsSPGMI, package = "PCRA")

# --- Default-like call (matches roxygen example) ---
test_that("selectCRSPandSPGMI returns correct structure", {
  result <- selectCRSPandSPGMI(
    stocks = stocksCRSP,
    factors = factorsSPGMI,
    dateSet = c("2006-01-31", "2010-12-31"),
    stockItems = c("Date", "TickerLast", "CapGroup", "Sector",
                   "Return", "Ret13WkBill", "MktIndexCRSP"),
    factorItems = c("BP", "LogMktCap", "SEV"),
    capChoice = "SmallCap",
    Nstocks = 20
  )

  expect_s3_class(result, "data.table")
  expect_equal(ncol(result), 10L)
  expect_equal(
    names(result),
    c("Date", "TickerLast", "CapGroup", "Sector", "Return",
      "Ret13WkBill", "MktIndexCRSP", "BP", "LogMktCap", "SEV")
  )
  expect_equal(length(unique(result$TickerLast)), 20L)

  # Date filtering
  expect_true(all(result$Date >= as.Date("2006-01-31")))
  expect_true(all(result$Date <= as.Date("2010-12-31")))

  # CapGroup filtering
  expect_true(all(result$CapGroup == "SmallCap"))

  # No NA sectors (line 67 filter)
  expect_false(anyNA(result$Sector))
})

# --- Different capChoice and Nstocks ---
test_that("selectCRSPandSPGMI works with LargeCap and fewer stocks", {
  result <- selectCRSPandSPGMI(
    stocks = stocksCRSP,
    factors = factorsSPGMI,
    dateSet = c("2008-01-31", "2009-12-31"),
    stockItems = c("Date", "TickerLast", "CapGroup", "Sector", "Return"),
    factorItems = c("EP"),
    capChoice = "LargeCap",
    Nstocks = 5
  )

  expect_s3_class(result, "data.table")
  expect_equal(length(unique(result$TickerLast)), 5L)
  expect_true(all(result$CapGroup == "LargeCap"))
  expect_equal(names(result), c("Date", "TickerLast", "CapGroup", "Sector", "Return", "EP"))
})

# --- End-to-end: feeds into fitFfm ---
test_that("selectCRSPandSPGMI output works with fitFfm", {
  sf <- selectCRSPandSPGMI(
    stocks = stocksCRSP,
    factors = factorsSPGMI,
    dateSet = c("2006-01-31", "2010-12-31"),
    stockItems = c("Date", "TickerLast", "CapGroup", "Sector",
                   "Return", "Ret13WkBill", "MktIndexCRSP"),
    factorItems = c("BP", "LogMktCap", "SEV"),
    capChoice = "SmallCap",
    Nstocks = 20
  )

  fit <- fitFfm(
    data = sf,
    asset.var = "TickerLast",
    ret.var = "Return",
    date.var = "Date",
    exposure.vars = c("BP", "LogMktCap")
  )

  expect_s3_class(fit, "ffm")
  # Panel may be unbalanced: some tickers absent in last period
  expect_true(length(fit$asset.names) >= 10L)
  expect_true(nrow(fit$factor.returns) > 1L)
})
