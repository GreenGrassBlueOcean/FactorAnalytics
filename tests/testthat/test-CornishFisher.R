# test-CornishFisher.R — Phase 4.3.1
# Mathematical property tests for the Cornish-Fisher expansion functions.

test_that("dCornishFisher integrates to approximately 1", {
  x <- seq(-5, 5, by = 0.01)
  d <- dCornishFisher(x, n = 100, skew = 0.5, ekurt = 1.0)
  integral <- sum(d * 0.01)
  expect_equal(integral, 1.0, tolerance = 0.02)
})

test_that("pCornishFisher is monotonically increasing", {
  x <- seq(-3, 3, by = 0.1)
  p <- pCornishFisher(x, n = 100, skew = 0.5, ekurt = 1.0)
  expect_true(all(diff(p) >= 0))
})

test_that("qCornishFisher inverts pCornishFisher", {
  probs <- c(0.01, 0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95, 0.99)
  q <- qCornishFisher(probs, n = 100, skew = 0.5, ekurt = 1.0)
  p_back <- pCornishFisher(q, n = 100, skew = 0.5, ekurt = 1.0)
  expect_equal(p_back, probs, tolerance = 1e-4)
})

test_that("rCornishFisher respects seed parameter", {
  r1 <- rCornishFisher(100, n = 50, skew = 0, ekurt = 0, seed = 4217)
  r2 <- rCornishFisher(100, n = 50, skew = 0, ekurt = 0, seed = 4217)
  expect_identical(r1, r2)
})

test_that("CornishFisher reduces to normal when skew = 0, ekurt = 0", {
  probs <- c(0.05, 0.25, 0.50, 0.75, 0.95)
  q_cf <- qCornishFisher(probs, n = 1000, skew = 0, ekurt = 0)
  q_norm <- qnorm(probs)
  expect_equal(q_cf, q_norm, tolerance = 1e-3)
})

test_that("Cornish-Fisher upper tail widens with positive skew", {
  q_sym <- qCornishFisher(0.95, n = 100, skew = 0, ekurt = 0)
  q_pos <- qCornishFisher(0.95, n = 100, skew = 1.0, ekurt = 0)
  # Positive skew extends the right tail
  expect_true(q_pos > q_sym)
})

test_that("dCornishFisher returns non-negative densities", {
  x <- seq(-4, 4, by = 0.1)
  d <- dCornishFisher(x, n = 100, skew = 0.3, ekurt = 0.5)
  expect_true(all(d >= 0))
})

test_that("pCornishFisher returns values in [0, 1]", {
  x <- seq(-4, 4, by = 0.5)
  p <- pCornishFisher(x, n = 100, skew = 0.3, ekurt = 0.5)
  expect_true(all(p >= 0 & p <= 1))
})
