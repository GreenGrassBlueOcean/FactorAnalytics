# test-fitTsfmUpDn.R — Phase 4.3.5
# Up/down market timing model tests.

test_that("fitTsfmUpDn returns correct structure", {
  fit <- fitTsfmUpDn(
    asset.names = colnames(managers[, 1:6]),
    mkt.name = "SP500.TR",
    data = managers
  )

  expect_s3_class(fit, "tsfmUpDn")
  expect_s3_class(fit$Up, "tsfm")
  expect_s3_class(fit$Dn, "tsfm")
  expect_true(nrow(fit$Up$data) > 0)
  expect_true(nrow(fit$Dn$data) > 0)
})

test_that("fitTsfmUpDn with rf.name", {
  fit <- fitTsfmUpDn(
    asset.names = colnames(managers[, 1:6]),
    mkt.name = "SP500.TR",
    rf.name = "US.3m.TR",
    data = managers
  )
  expect_s3_class(fit, "tsfmUpDn")
  expect_true(length(fit$Up$asset.names) > 0)
  expect_true(length(fit$Dn$asset.names) > 0)
})

test_that("fitTsfmUpDn S3 methods run without error", {
  fit <- fitTsfmUpDn(
    asset.names = colnames(managers[, 1:6]),
    mkt.name = "SP500.TR",
    data = managers
  )

  expect_no_error(capture.output(print(fit)))
  expect_no_error(summary(fit))

  pdf(NULL)
  on.exit(dev.off(), add = TRUE)
  # Pass explicit asset.name to avoid par(ask=TRUE) loop over all assets
  expect_no_error(plot(fit, asset.name = fit$Up$asset.names[1]))
})

test_that("predict.tsfmUpDn runs without error", {
  fit <- fitTsfmUpDn(
    asset.names = colnames(managers[, 1:6]),
    mkt.name = "SP500.TR",
    data = managers
  )
  expect_no_error(predict(fit))
})
