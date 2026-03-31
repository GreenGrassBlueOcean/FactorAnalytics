# test-plot-coverage.R — Targeted coverage for non-interactive branches in
#   plot.tsfm.R and plot.ffm.R
#
# The remaining uncovered lines fall into 3 categories:
#   1. Interactive menu() + par(ask=TRUE) loops — not testable (~65 lines)
#   2. Package-not-available guards (sn, RobStatTM) — would require mocking (~4 lines)
#   3. Testable branches: Lars errors, DLS decay, invisible() defaults,
#      missing asset.name, <2 assets group error (~17 lines)
# This file covers category 3.

# ── Shared fixtures ──────────────────────────────────────────────────────────

# Lars fit (variable.selection = "lars", sets fit.method = NULL → "Lars")
local_lars <- fitTsfm(
  asset.names = colnames(managers[, 1:3]),
  factor.names = colnames(managers[, 7]),
  rf.name = colnames(managers[, 10]),
  data = managers,
  variable.selection = "lars"
)

# DLS fit with explicit decay (non-default)
local_dls_decay <- fitTsfm(
  asset.names = colnames(managers[, 1:3]),
  factor.names = colnames(managers[, 7]),
  rf.name = colnames(managers[, 10]),
  data = managers,
  fit.method = "DLS",
  decay = 0.9
)

# Multi-asset LS fit (for group plot errors)
local_tsfm_multi <- fitTsfm(
  asset.names = colnames(managers[, 1:6]),
  factor.names = colnames(managers[, 7:9]),
  rf.name = colnames(managers[, 10]),
  data = managers
)

# FFM fits (for ffm plot tests)
local_ffm <- fitFfm(
  data = factorDataSetDjia5Yrs,
  asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
  exposure.vars = c("P2B", "EV2S")
)

# ============================================================================
# plot.tsfm.R — Lars method detection (L174)
# ============================================================================

test_that("plot.tsfm detects Lars fit method", {
  # Lars fits have fit.method = NULL; plot.tsfm sets meth <- "Lars"
  expect_null(local_lars$fit.method)
  pdf(NULL)
  on.exit(dev.off(), add = TRUE)
  # which=1 is a basic plot that works with any method
  expect_no_error(
    plot(local_lars, plot.single = TRUE,
         asset.name = local_lars$asset.names[1], which = 1)
  )
})

# ============================================================================
# plot.tsfm.R — missing asset.name error (L179-180)
# ============================================================================

test_that("plot.tsfm errors when plot.single=TRUE without asset.name", {
  expect_error(
    plot(local_tsfm_multi, plot.single = TRUE, which = 1),
    "asset.name"
  )
})

# ============================================================================
# plot.tsfm.R — Lars-specific errors for which=4, 18, 19 (L247, L372, L404)
# ============================================================================

test_that("plot.tsfm Lars fit errors on which=4 (sqrt modified residuals)", {
  pdf(NULL)
  on.exit(dev.off(), add = TRUE)
  expect_error(
    plot(local_lars, plot.single = TRUE,
         asset.name = local_lars$asset.names[1], which = 4),
    "not available for.*lars"
  )
})

test_that("plot.tsfm Lars fit errors on which=18 (rolling regression)", {
  pdf(NULL)
  on.exit(dev.off(), add = TRUE)
  expect_error(
    plot(local_lars, plot.single = TRUE,
         asset.name = local_lars$asset.names[1], which = 18),
    "not available for.*lars"
  )
})

test_that("plot.tsfm Lars fit errors on which=19 (single factor scatter)", {
  pdf(NULL)
  on.exit(dev.off(), add = TRUE)
  expect_error(
    plot(local_lars, plot.single = TRUE,
         asset.name = local_lars$asset.names[1], which = 19),
    "not available for.*lars"
  )
})

test_that("plot.tsfm Lars fit errors on group which=12", {
  pdf(NULL)
  on.exit(dev.off(), add = TRUE)
  expect_error(
    plot(local_lars, which = 12, a.sub = 1:2, f.sub = 1),
    "not available for.*lars"
  )
})

# ============================================================================
# plot.tsfm.R — DLS with explicit decay in which=18 (L382)
# ============================================================================

test_that("plot.tsfm DLS with explicit decay works for which=18", {
  pdf(NULL)
  on.exit(dev.off(), add = TRUE)
  expect_no_error(
    plot(local_dls_decay, plot.single = TRUE,
         asset.name = local_dls_decay$asset.names[1], which = 18)
  )
})

# ============================================================================
# plot.tsfm.R — invisible() defaults (L420, L596) and <2 assets (L434)
# ============================================================================

test_that("plot.tsfm single-asset invalid which hits invisible()", {
  pdf(NULL)
  on.exit(dev.off(), add = TRUE)
  expect_no_error(
    plot(local_tsfm_multi, plot.single = TRUE,
         asset.name = local_tsfm_multi$asset.names[1], which = 99)
  )
})

test_that("plot.tsfm group invalid which hits invisible()", {
  pdf(NULL)
  on.exit(dev.off(), add = TRUE)
  expect_no_error(
    plot(local_tsfm_multi, which = 99)
  )
})

test_that("plot.tsfm group errors with <2 assets", {
  expect_error(
    plot(local_tsfm_multi, which = 1, a.sub = 1),
    "Two or more assets"
  )
})

# ============================================================================
# plot.ffm.R — invisible() defaults (L319, L486) and <2 assets (L333)
# ============================================================================

test_that("plot.ffm single-asset invalid which hits invisible()", {
  pdf(NULL)
  on.exit(dev.off(), add = TRUE)
  expect_no_error(
    plot(local_ffm, plot.single = TRUE,
         asset.name = local_ffm$asset.names[1], which = 99)
  )
})

test_that("plot.ffm group invalid which hits invisible()", {
  pdf(NULL)
  on.exit(dev.off(), add = TRUE)
  expect_no_error(
    plot(local_ffm, which = 99)
  )
})

test_that("plot.ffm group errors with <2 assets", {
  expect_error(
    plot(local_ffm, which = 1, a.sub = 1),
    "Two or more assets"
  )
})
