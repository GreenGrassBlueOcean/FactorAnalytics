# Phase 2 — Intermediate fixture tests for vectorized EWMA/GARCH loops
# These verify that stats::filter vectorization matches the original for-loop output.

# --- EWMA standardization (Loop #1) ---

test_that("standardizeExposures TimeSeries EWMA matches fixture", {
  spec <- specFfm(
    data = factorDataSetDjia5Yrs,
    asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
    exposure.vars = c("P2B", "EV2S")
  )
  spec <- lagExposures(spec)

  fixture <- readRDS(test_path("fixtures", "fixture_standardize_ewma.rds"))
  lambda <- 0.9
  dataDT <- data.table::copy(spec$dataDT)
  a_ <- spec$asset.var
  d_ <- spec$date.var

  for (e_ in spec$exposures.num) {
    dataDT[, ts := (get(e_) - mean(get(e_), na.rm = TRUE))^2, by = d_]
    data.table::setorderv(dataDT, c(a_, d_))
    dataDT[, s := {
      n <- .N
      if (n == 1L) ts[1L]
      else c(ts[1L], as.numeric(stats::filter(
        x = (1 - lambda) * ts[-1L], filter = lambda,
        method = "recursive", init = ts[1L])))
    }, by = a_]

    expect_equal(dataDT$s, fixture[[e_]]$s, tolerance = 1e-12)
    dataDT[, c("ts", "s") := NULL]
  }
})

# --- GARCH standardization (Loop #2) ---

test_that("standardizeReturns GARCH matches fixture", {
  spec <- specFfm(
    data = factorDataSetDjia5Yrs,
    asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
    exposure.vars = c("P2B", "EV2S")
  )
  spec <- lagExposures(spec)

  fixture <- readRDS(test_path("fixtures", "fixture_standardize_garch.rds"))
  alpha <- 0.1; beta <- 0.81
  dataDT <- data.table::copy(spec$dataDT)
  a_ <- spec$asset.var
  d_ <- spec$date.var

  dataDT[, sdReturns := .(sd(get(spec$yVar), na.rm = TRUE)), by = a_]
  dataDT[, ts := get(spec$yVar)^2]
  data.table::setorderv(dataDT, c(a_, d_))
  dataDT[, sigmaGarch := {
    omega_i <- (1 - alpha - beta) * sdReturns[1L]^2
    x <- omega_i + alpha * ts
    n <- .N
    if (n == 1L) x[1L]
    else c(x[1L], as.numeric(stats::filter(
      x = x[-1L], filter = beta, method = "recursive", init = x[1L])))
  }, by = a_]

  expect_equal(dataDT$sigmaGarch, fixture$sigmaGarch, tolerance = 1e-12)
})

# --- EWMA weights (Loop #3) ---

test_that("EWMA weights match fixture", {
  fixture <- readRDS(test_path("fixtures", "fixture_weights_ewma.rds"))
  lambda <- 0.9

  resid.DT <- data.table::copy(fixture[, list(id, date, residuals, resid.var)])
  resid.DT[, idx := 1:.N, by = id]
  data.table::setorderv(resid.DT, c("id", "date"))

  resid.DT[, w := {
    sq <- residuals^2
    init <- resid.var[1L]
    n <- .N
    if (n == 1L) init
    else c(init, as.numeric(stats::filter(
      x = (1 - lambda) * sq[-1L], filter = lambda,
      method = "recursive", init = init)))
  }, by = id]

  expect_equal(resid.DT$w, fixture$w, tolerance = 1e-12)
})

# --- GARCH weights (Loop #5) ---

test_that("GARCH weights match fixture", {
  fixture <- readRDS(test_path("fixtures", "fixture_weights_garch.rds"))
  alpha <- 0.1; beta <- 0.81

  resid.DT <- data.table::copy(fixture[, list(id, date, residuals, resid.var)])
  resid.DT[, idx := 1:.N, by = id]
  data.table::setorderv(resid.DT, c("id", "date"))

  resid.DT[, w := {
    omega_i <- (1 - alpha - beta) * resid.var[1L]
    sq_lag <- data.table::shift(residuals^2, n = 1L, fill = resid.var[1L])
    x <- omega_i + alpha * sq_lag
    n <- .N
    if (n == 1L) resid.var[1L]
    else c(resid.var[1L], as.numeric(stats::filter(
      x = x[-1L], filter = beta, method = "recursive", init = resid.var[1L])))
  }, by = id]

  expect_equal(resid.DT$w, fixture$w, tolerance = 1e-12)
})

# --- Robust EWMA (Loop #4) — validated against hand-computed expected values ---

test_that("Robust EWMA matches standard EWMA when no outliers", {
  # When all residuals are within 2.5*sigma, Robust EWMA == standard EWMA.
  # Use deterministic small residuals that cannot trigger the 2.5*sqrt(w) threshold.
  lambda <- 0.9
  n_periods <- 10L

  resid.DT <- data.table::data.table(
    id = rep(c("A1", "A2"), each = n_periods),
    date = rep(seq.Date(as.Date("2020-01-01"), by = "month", length.out = n_periods), 2),
    residuals = rep(c(0.01, -0.01, 0.005, -0.005, 0.008,
                      -0.008, 0.003, -0.003, 0.006, -0.006), 2),
    resid.var = rep(0.01, 2 * n_periods)
  )
  data.table::setorderv(resid.DT, c("id", "date"))

  # Standard EWMA
  ewma_DT <- data.table::copy(resid.DT)
  ewma_DT[, w := {
    sq <- residuals^2
    init <- resid.var[1L]
    n <- .N
    c(init, as.numeric(stats::filter(
      x = (1 - lambda) * sq[-1L], filter = lambda,
      method = "recursive", init = init)))
  }, by = id]

  # Robust EWMA (should match — all |residuals| << 2.5*sqrt(0.01) = 0.25)
  robust_DT <- data.table::copy(resid.DT)
  robust_DT[, w := {
    init <- resid.var[1L]
    eps2 <- residuals^2
    n <- .N
    Reduce(function(w_prev, t) {
      if (abs(residuals[t]) <= 2.5 * sqrt(w_prev)) {
        lambda * w_prev + (1 - lambda) * eps2[t]
      } else {
        w_prev
      }
    }, x = 2L:n, init = init, accumulate = TRUE)
  }, by = id]

  expect_equal(robust_DT$w, ewma_DT$w, tolerance = 1e-12)
})

test_that("Robust EWMA freezes weight on outlier", {
  lambda <- 0.9

  resid.DT <- data.table::data.table(
    id = "A1",
    date = seq.Date(as.Date("2020-01-01"), by = "month", length.out = 5),
    residuals = c(0.01, 0.02, 0.50, 0.01, 0.02),
    resid.var = rep(0.0004, 5)
  )
  data.table::setorderv(resid.DT, c("id", "date"))

  resid.DT[, w := {
    init <- resid.var[1L]
    eps2 <- residuals^2
    n <- .N
    Reduce(function(w_prev, t) {
      if (abs(residuals[t]) <= 2.5 * sqrt(w_prev)) {
        lambda * w_prev + (1 - lambda) * eps2[t]
      } else {
        w_prev
      }
    }, x = 2L:n, init = init, accumulate = TRUE)
  }, by = id]

  # w[1] = 0.0004 (init)
  # w[2] = 0.9*0.0004 + 0.1*0.02^2 = 0.00036 + 0.00004 = 0.0004
  # w[3]: |0.50| > 2.5*sqrt(0.0004) = 2.5*0.02 = 0.05, so FREEZE: w[3] = w[2]
  # w[4] = 0.9*0.0004 + 0.1*0.01^2 = 0.00036 + 0.00001 = 0.00037
  # w[5] = 0.9*0.00037 + 0.1*0.02^2 = 0.000333 + 0.00004 = 0.000373
  expect_equal(resid.DT$w[1], 0.0004)
  expect_equal(resid.DT$w[3], resid.DT$w[2],
               info = "Weight should freeze when residual exceeds 2.5*sqrt(w)")
  expect_true(resid.DT$w[4] < resid.DT$w[3],
              info = "Weight should resume updating after non-outlier")
})

# --- Stripped lm objects (Phase 2.3) ---

test_that("stripped lm objects support all S3 methods", {
  fit <- fitFfm(
    data = factorDataSetDjia5Yrs,
    asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
    exposure.vars = c("P2B", "EV2S")
  )
  lm1 <- fit$factor.fit[[1]]
  expect_no_error(coef(lm1))
  expect_no_error(residuals(lm1))
  expect_no_error(fitted(lm1))
  expect_no_error(summary(lm1))
  expect_no_error(vcov(lm1))
  expect_no_error(predict(lm1))
})
