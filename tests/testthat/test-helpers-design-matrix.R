# test-helpers-design-matrix.R — Phase 7
# Unit tests for build_beta_star, build_restriction_matrix, apply_restriction

# --- build_beta_star ---

test_that("build_beta_star with 1 char exposure produces Market + K dummies", {
  df <- data.frame(SECTOR = factor(c("A", "B", "A", "C"),
                                   levels = c("A", "B", "C")))
  bs <- FactorAnalytics:::build_beta_star(df, "SECTOR")

  expect_equal(nrow(bs), 4L)
  expect_equal(ncol(bs), 4L)
  expect_equal(colnames(bs)[1], "Market")
  expect_true(all(bs[, "Market"] == 1))
  # Row 1: SECTOR = A -> dummy = (1, 0, 0)
  expect_equal(as.numeric(bs[1, -1]), c(1, 0, 0))
  # Row 2: SECTOR = B -> dummy = (0, 1, 0)
  expect_equal(as.numeric(bs[2, -1]), c(0, 1, 0))
})

test_that("build_beta_star with 2 char exposures produces Market + K1 + K2 dummies", {
  df <- data.frame(
    SECTOR = factor(c("A", "B", "A"), levels = c("A", "B")),
    COUNTRY = factor(c("US", "US", "EU"), levels = c("US", "EU"))
  )
  bs <- FactorAnalytics:::build_beta_star(df, c("SECTOR", "COUNTRY"))

  expect_equal(nrow(bs), 3L)
  expect_equal(ncol(bs), 5L)
  expect_equal(colnames(bs)[1], "Market")
  # Row 1: SECTOR=A, COUNTRY=US -> (1, 1,0, 1,0)
  expect_equal(as.numeric(bs[1, ]), c(1, 1, 0, 1, 0))
})

test_that("build_beta_star ignores non-char columns in data", {
  df <- data.frame(
    SECTOR = factor(c("A", "B"), levels = c("A", "B")),
    P2B = c(1.5, -0.3),
    RETURN = c(0.01, 0.02)
  )
  bs <- FactorAnalytics:::build_beta_star(df, "SECTOR")
  expect_equal(ncol(bs), 3L)
})

# --- build_restriction_matrix ---

test_that("build_restriction_matrix sector: correct dimensions", {
  R <- FactorAnalytics:::build_restriction_matrix(3L)
  expect_equal(dim(R), c(4, 3))
})

test_that("build_restriction_matrix MSCI: correct dimensions", {
  R <- FactorAnalytics:::build_restriction_matrix(c(4L, 3L))
  expect_equal(dim(R), c(8, 6))
})

test_that("build_restriction_matrix matches inline construction (sector)", {
  # Replicate the inline code from fitFfmDT.R line 588
  K <- 9L
  inline <- rbind(diag(K - 1), c(0, rep(-1, K - 2)))
  helper <- FactorAnalytics:::build_restriction_matrix(8L)
  expect_identical(inline, helper)
})

test_that("build_restriction_matrix matches inline construction (MSCI)", {
  # Replicate the inline code from fitFfmDT.R lines 654-657
  K1 <- 4L; K2 <- 3L
  inline <- rbind(
    cbind(diag(K1), matrix(0, nrow = K1, ncol = K2 - 1)),
    c(c(0, rep(-1, K1 - 1)), rep(0, K2 - 1)),
    cbind(matrix(0, ncol = K1, nrow = K2 - 1), diag(K2 - 1)),
    c(rep(0, K1), rep(-1, K2 - 1))
  )
  helper <- FactorAnalytics:::build_restriction_matrix(c(K1, K2))
  expect_identical(inline, helper)
})

test_that("build_restriction_matrix errors for 3+ groups", {
  expect_error(
    FactorAnalytics:::build_restriction_matrix(c(3L, 4L, 2L)),
    "at most 2 categorical"
  )
})

# --- apply_restriction ---

test_that("apply_restriction names columns V1..Vk", {
  beta_star <- matrix(1, nrow = 5, ncol = 4)
  R <- diag(4)[, 1:3]
  result <- FactorAnalytics:::apply_restriction(beta_star, R)
  expect_equal(colnames(result), c("V1", "V2", "V3"))
})

# --- Round-trip: build_beta_star + apply_restriction vs expand_newdata_ffm ---

test_that("full helper pipeline matches expand_newdata_ffm output", {
  fit_sector <- fitFfm(
    data = factorDataSetDjia5Yrs,
    asset.var = "TICKER", ret.var = "RETURN", date.var = "DATE",
    exposure.vars = c("SECTOR", "P2B"), addIntercept = TRUE
  )

  newdata <- data.frame(
    SECTOR = factor(c("COSTAP", "ENERGY"),
                    levels = fit_sector$char_levels[["SECTOR"]]),
    P2B = c(1.0, 2.0)
  )

  # Via expand_newdata_ffm (existing)
  expanded <- FactorAnalytics:::expand_newdata_ffm(fit_sector, newdata)

  # Via shared helpers
  bs <- FactorAnalytics:::build_beta_star(newdata, "SECTOR")
  bmod <- FactorAnalytics:::apply_restriction(bs, fit_sector$restriction.mat)
  manual <- as.data.frame(bmod)
  manual$P2B <- newdata$P2B

  expect_equal(expanded, manual)
})
