# test-riskDecomp-dispatch.R — Verify riskDecomp dispatches to specialized methods
#
# riskDecomp is a thin dispatcher that routes to fmSdDecomp, fmVaRDecomp,
# fmEsDecomp, portSdDecomp, portVaRDecomp, and portEsDecomp. These tests
# verify output equivalence between the unified and specialized APIs.

# --- Setup: fit models used across this file ---
fit_tsfm <- fitTsfm(
  asset.names = colnames(managers[, 1:6]),
  factor.names = colnames(managers[, 7:9]),
  rf.name = colnames(managers[, 10]),
  data = managers
)

fit_ffm <- fitFfm(
  data = dat145,
  asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
  exposure.vars = c("SECTOR", "ROE", "BP", "PM12M1M", "SIZE",
                     "ANNVOL1M", "EP"),
  fit.method = "WLS", z.score = "crossSection"
)

tsfm_wts <- rep(1 / 6, 6)
names(tsfm_wts) <- fit_tsfm$asset.names

# ---------- tsfm: dispatch equivalence ----------

test_that("riskDecomp.tsfm Sd/asset matches fmSdDecomp", {
  rd <- riskDecomp(fit_tsfm, risk = "Sd", portDecomp = FALSE)
  ref <- fmSdDecomp(fit_tsfm)
  expect_equal(rd$Sd.fm, ref$Sd.fm)
  expect_equal(rd$mSd, ref$mSd)
  expect_equal(rd$cSd, ref$cSd)
  expect_equal(rd$pcSd, ref$pcSd)
})

test_that("riskDecomp.tsfm Sd/port matches portSdDecomp", {
  rd <- riskDecomp(fit_tsfm, risk = "Sd", weights = tsfm_wts,
                   portDecomp = TRUE)
  ref <- portSdDecomp(fit_tsfm, weights = tsfm_wts)
  expect_equal(rd$portSd, ref$portSd)
  expect_equal(rd$mSd, ref$mSd)
  expect_equal(rd$cSd, ref$cSd)
  expect_equal(rd$pcSd, ref$pcSd)
})

test_that("riskDecomp.tsfm VaR/asset with invert=TRUE matches fmVaRDecomp", {
  # invert=TRUE: riskDecomp returns raw (negative) values, same as fmVaRDecomp
  rd <- suppressWarnings(
    riskDecomp(fit_tsfm, risk = "VaR", portDecomp = FALSE, invert = TRUE)
  )
  ref <- suppressWarnings(fmVaRDecomp(fit_tsfm))
  expect_equal(rd$VaR.fm, ref$VaR.fm)
  expect_equal(rd$mVaR, ref$mVaR)
  expect_equal(rd$cVaR, ref$cVaR)
  expect_equal(rd$pcVaR, ref$pcVaR)
  expect_equal(rd$n.exceed, ref$n.exceed)
})

test_that("riskDecomp.tsfm VaR/asset invert=FALSE negates risk, marginal, component", {
  rd_raw <- suppressWarnings(
    riskDecomp(fit_tsfm, risk = "VaR", portDecomp = FALSE, invert = TRUE)
  )
  rd_inv <- suppressWarnings(
    riskDecomp(fit_tsfm, risk = "VaR", portDecomp = FALSE, invert = FALSE)
  )
  expect_equal(rd_inv$VaR.fm, -rd_raw$VaR.fm)
  expect_equal(rd_inv$mVaR, -rd_raw$mVaR)
  expect_equal(rd_inv$cVaR, -rd_raw$cVaR)
  # pcVaR unchanged: (-c)/(-V) = c/V
  expect_equal(rd_inv$pcVaR, rd_raw$pcVaR)
})

test_that("riskDecomp.tsfm VaR/port with invert=TRUE matches portVaRDecomp", {
  rd <- riskDecomp(fit_tsfm, risk = "VaR", weights = tsfm_wts,
                   portDecomp = TRUE, invert = TRUE)
  ref <- portVaRDecomp(fit_tsfm, weights = tsfm_wts, invert = FALSE)
  expect_equal(rd$portVaR, ref$portVaR)
  expect_equal(rd$mVaR, ref$mVaR)
  expect_equal(rd$cVaR, ref$cVaR)
  expect_equal(rd$pcVaR, ref$pcVaR)
})

test_that("riskDecomp.tsfm ES/asset with invert=TRUE matches fmEsDecomp", {
  rd <- riskDecomp(fit_tsfm, risk = "ES", portDecomp = FALSE, invert = TRUE)
  ref <- fmEsDecomp(fit_tsfm)
  expect_equal(rd$ES.fm, ref$ES.fm)
  expect_equal(rd$mES, ref$mES)
  expect_equal(rd$cES, ref$cES)
  expect_equal(rd$pcES, ref$pcES)
})

test_that("riskDecomp.tsfm ES/port with invert=TRUE matches portEsDecomp", {
  rd <- riskDecomp(fit_tsfm, risk = "ES", weights = tsfm_wts,
                   portDecomp = TRUE, invert = TRUE)
  ref <- portEsDecomp(fit_tsfm, weights = tsfm_wts, invert = FALSE)
  expect_equal(rd$portES, ref$portES)
  expect_equal(rd$mES, ref$mES)
  expect_equal(rd$cES, ref$cES)
  expect_equal(rd$pcES, ref$pcES)
})

# ---------- ffm: dispatch equivalence ----------

test_that("riskDecomp.ffm Sd/asset matches fmSdDecomp", {
  rd <- riskDecomp(fit_ffm, risk = "Sd", portDecomp = FALSE)
  ref <- fmSdDecomp(fit_ffm)
  expect_equal(rd$Sd.fm, ref$Sd.fm)
  expect_equal(rd$mSd, ref$mSd)
  expect_equal(rd$cSd, ref$cSd)
  expect_equal(rd$pcSd, ref$pcSd)
})

test_that("riskDecomp.ffm Sd/port matches portSdDecomp", {
  rd <- riskDecomp(fit_ffm, risk = "Sd", weights = wts145,
                   portDecomp = TRUE)
  ref <- portSdDecomp(fit_ffm, weights = wts145)
  expect_equal(rd$portSd, ref$portSd)
  expect_equal(rd$mSd, ref$mSd)
  expect_equal(rd$cSd, ref$cSd)
  expect_equal(rd$pcSd, ref$pcSd)
})

test_that("riskDecomp.ffm VaR/asset with invert=TRUE matches fmVaRDecomp", {
  rd <- riskDecomp(fit_ffm, risk = "VaR", portDecomp = FALSE, invert = TRUE)
  ref <- fmVaRDecomp(fit_ffm)
  expect_equal(rd$VaR.fm, ref$VaR.fm)
  expect_equal(rd$mVaR, ref$mVaR)
  expect_equal(rd$cVaR, ref$cVaR)
  expect_equal(rd$pcVaR, ref$pcVaR)
})

test_that("riskDecomp.ffm VaR/port matches portVaRDecomp", {
  rd <- riskDecomp(fit_ffm, risk = "VaR", weights = wts145,
                   portDecomp = TRUE, invert = TRUE)
  ref <- portVaRDecomp(fit_ffm, weights = wts145, invert = FALSE)
  expect_equal(rd$portVaR, ref$portVaR)
  expect_equal(rd$mVaR, ref$mVaR)
  expect_equal(rd$cVaR, ref$cVaR)
  expect_equal(rd$pcVaR, ref$pcVaR)
})

test_that("riskDecomp.ffm ES/asset with invert=TRUE matches fmEsDecomp", {
  rd <- riskDecomp(fit_ffm, risk = "ES", portDecomp = FALSE, invert = TRUE)
  ref <- fmEsDecomp(fit_ffm)
  expect_equal(rd$ES.fm, ref$ES.fm)
  expect_equal(rd$mES, ref$mES)
  expect_equal(rd$cES, ref$cES)
  expect_equal(rd$pcES, ref$pcES)
})

test_that("riskDecomp.ffm ES/port matches portEsDecomp", {
  rd <- riskDecomp(fit_ffm, risk = "ES", weights = wts145,
                   portDecomp = TRUE, invert = TRUE)
  ref <- portEsDecomp(fit_ffm, weights = wts145, invert = FALSE)
  expect_equal(rd$portES, ref$portES)
  expect_equal(rd$mES, ref$mES)
  expect_equal(rd$cES, ref$cES)
  expect_equal(rd$pcES, ref$pcES)
})

# ---------- invert convention: ffm ----------

test_that("riskDecomp.ffm VaR invert=FALSE negates correctly", {
  rd_raw <- riskDecomp(fit_ffm, risk = "VaR", portDecomp = FALSE,
                       invert = TRUE)
  rd_inv <- riskDecomp(fit_ffm, risk = "VaR", portDecomp = FALSE,
                       invert = FALSE)
  expect_equal(rd_inv$VaR.fm, -rd_raw$VaR.fm)
  expect_equal(rd_inv$mVaR, -rd_raw$mVaR)
  expect_equal(rd_inv$cVaR, -rd_raw$cVaR)
  expect_equal(rd_inv$pcVaR, rd_raw$pcVaR)
})

test_that("riskDecomp.ffm ES invert=FALSE negates correctly", {
  rd_raw <- riskDecomp(fit_ffm, risk = "ES", portDecomp = FALSE,
                       invert = TRUE)
  rd_inv <- riskDecomp(fit_ffm, risk = "ES", portDecomp = FALSE,
                       invert = FALSE)
  expect_equal(rd_inv$ES.fm, -rd_raw$ES.fm)
  expect_equal(rd_inv$mES, -rd_raw$mES)
  expect_equal(rd_inv$cES, -rd_raw$cES)
  expect_equal(rd_inv$pcES, rd_raw$pcES)
})

# ---------- input validation ----------

test_that("riskDecomp rejects invalid risk argument", {
  expect_error(riskDecomp(fit_tsfm, risk = "foo"),
               "risk must be")
  expect_error(riskDecomp(fit_tsfm),
               "risk must be")
})

test_that("riskDecomp rejects invalid type argument", {
  expect_error(riskDecomp(fit_tsfm, risk = "VaR", type = "foo"),
               "type must be")
})

test_that("riskDecomp rejects invalid object class", {
  expect_error(riskDecomp(list(a = 1), risk = "Sd"),
               "class 'tsfm', or 'ffm'")
})

# ---------- repRisk integration (smoke) ----------

test_that("repRisk.tsfm still works via riskDecomp dispatcher", {
  skip_if_not_installed("lattice")
  expect_no_error(
    capture.output(repRisk(fit_tsfm, isPrint = TRUE, isPlot = FALSE))
  )
})

test_that("repRisk.ffm still works via riskDecomp dispatcher", {
  skip_if_not_installed("lattice")
  expect_no_error(
    capture.output(repRisk(fit_ffm, isPrint = TRUE, isPlot = FALSE))
  )
})
