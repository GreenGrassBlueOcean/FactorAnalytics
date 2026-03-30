# =============================================================================
# helpers-risk.R — Shared internal helpers for risk decomposition
#
# These helpers extract the 4 duplicated "augmented factor model" setup
# patterns from the 8 risk decomposition files into a single source of truth.
#
# The augmented factor model for asset i's return:
#   R_i(t) = beta_i' f(t) + e_i(t) = beta.star_i' f.star(t)
# where beta.star_i = (beta_i, sigma_e_i)' and f.star(t) = [f(t)', z_i(t)]'
# with z_i(t) = e_i(t) / sigma_e_i being the standardized residual.
# =============================================================================


#' Extract common model components for risk decomposition
#'
#' Unified extraction of beta, residual SD, factor returns, factor covariance,
#' factor names, asset names, and an asset-return retrieval closure from either
#' tsfm or ffm objects.
#'
#' @param object fit object of class tsfm or ffm
#' @param factor.cov optional user-supplied K x K factor covariance matrix.
#'   If NULL (default), computed from sample for tsfm or read from object for ffm.
#' @param use method for computing covariances for tsfm; ignored for ffm
#' @return list with: beta, resid.sd, factors.xts, factor.names, asset.names,
#'   K, factor.cov, get_R (closure returning xts of asset returns)
#' @keywords internal
extract_fm_components <- function(object, factor.cov = NULL,
                                  use = "pairwise.complete.obs") {
  if (inherits(object, "tsfm")) {
    beta <- object$beta
    resid.sd <- object$resid.sd
    factors.xts <- object$data[, object$factor.names]
    factor.names <- object$factor.names
    asset.names <- object$asset.names
    K <- length(factor.names)
    if (is.null(factor.cov)) {
      factor.cov <- cov(as.matrix(factors.xts), use = use)
    }
    get_R <- function(i) object$data[, i]
  } else if (inherits(object, "ffm")) {
    beta <- object$beta
    resid.sd <- sqrt(object$resid.var)
    factors.xts <- object$factor.returns
    factor.names <- object$factor.names
    asset.names <- object$asset.names
    K <- length(factor.names)
    if (is.null(factor.cov)) {
      factor.cov <- object$factor.cov
    }
    get_R <- function(i) {
      subrows <- which(object$data[[object$asset.var]] == i)
      dts <- object$data[subrows, object$date.var]
      # Robust POSIXct -> Date conversion (Phase 9.7 pattern)
      if (inherits(dts, "POSIXt")) {
        tz <- attr(dts, "tzone")
        if (is.null(tz) || tz == "") tz <- Sys.timezone()
        dts <- as.Date(dts, tz = tz)
      } else {
        dts <- as.Date(dts)
      }
      xts::as.xts(object$data[subrows, object$ret.var, drop = FALSE],
                   order.by = dts)
    }
  } else {
    stop("extract_fm_components: object must be of class 'tsfm' or 'ffm'")
  }

  list(beta = beta, resid.sd = resid.sd, factors.xts = factors.xts,
       factor.names = factor.names, asset.names = asset.names,
       K = K, factor.cov = factor.cov, get_R = get_R)
}


#' Build augmented beta matrix with residual pseudo-factor
#'
#' Constructs beta.star by appending residual standard deviations as the
#' (K+1)-th column ("Residuals"). Handles both asset-level (N x K+1) and
#' portfolio-level (1 x K+1) cases. NAs in beta are set to 0.
#'
#' @param beta N x K matrix of factor exposures
#' @param resid_sd N-vector of residual standard deviations
#' @param weights optional N-vector of portfolio weights. If provided,
#'   returns a 1 x (K+1) portfolio-level beta.star.
#' @return matrix with "Residuals" column appended
#' @keywords internal
make_beta_star <- function(beta, resid_sd, weights = NULL) {
  beta <- as.matrix(beta)
  beta[is.na(beta)] <- 0
  if (is.null(weights)) {
    out <- cbind(beta, Residuals = resid_sd)
  } else {
    port_beta <- weights %*% beta
    port_resid <- sqrt(sum(weights^2 * resid_sd^2))
    out <- cbind(port_beta, Residuals = port_resid)
  }
  as.matrix(out)
}


#' Build augmented factor covariance matrix
#'
#' Extends a K x K factor covariance matrix to (K+1) x (K+1) by adding a
#' unit-variance residual pseudo-factor with zero covariance to all real
#' factors.
#'
#' @param factor_cov K x K factor covariance matrix (with or without colnames)
#' @return (K+1) x (K+1) matrix with "Residuals" row/column appended
#' @keywords internal
make_factor_star_cov <- function(factor_cov) {
  K <- ncol(factor_cov)
  fsc <- diag(K + 1L)
  fsc[seq_len(K), seq_len(K)] <- factor_cov
  # Guard against NULL colnames on user-supplied factor_cov
  f_names <- colnames(factor_cov)
  if (is.null(f_names)) f_names <- paste0("F", seq_len(K))
  nms <- c(f_names, "Residuals")
  dimnames(fsc) <- list(nms, nms)
  fsc
}


#' Normalize factor model residuals to unit-variance pseudo-factors
#'
#' Divides each asset's residuals by its residual standard deviation to
#' produce standardized residuals z(t) = e(t) / sigma_e with approximately
#' unit variance. Optionally aggregates to portfolio level:
#'   z_p(t) = sum(w_i * e_it) / sqrt(sum(w_i^2 * sigma_i^2))
#'
#' @param resid_mat T x N matrix of residuals (typically from residuals(object))
#' @param resid_sd N-vector of residual standard deviations
#' @param weights optional N-vector of portfolio weights for aggregation
#' @return xts object: T x N (asset-level) or T x 1 (portfolio-level)
#' @keywords internal
normalize_fm_residuals <- function(resid_mat, resid_sd, weights = NULL) {
  if (is.null(weights)) {
    # Asset-level: z_i(t) = e_i(t) / sigma_i
    z <- t(t(zoo::coredata(resid_mat)) / resid_sd)
  } else {
    # Portfolio-level: z_p(t) = sum(w_i * e_it) / sigma_p
    sig_p <- sqrt(sum(weights^2 * resid_sd^2))
    z <- zoo::coredata(resid_mat) %*% weights / sig_p
  }
  z_xts <- xts::as.xts(z, order.by = zoo::index(resid_mat))
  idx <- zoo::index(resid_mat)
  if (inherits(idx, "POSIXct")) {
    tz_use <- attr(idx, "tzone")
    if (is.null(tz_use) || !nzchar(tz_use)) tz_use <- Sys.timezone()
    zoo::index(z_xts) <- as.Date(zoo::index(z_xts), tz = tz_use)
  } else {
    zoo::index(z_xts) <- as.Date(zoo::index(z_xts))
  }
  z_xts
}


#' Build diagonal residual covariance matrix
#'
#' Constructs D.e = diag(sigma_e^2) for the factor model covariance
#' decomposition: Cov(R) = B Cov(F) B' + D.e.
#'
#' @param resid_var N-vector of residual variances (sigma_e^2)
#' @return N x N diagonal matrix
#' @keywords internal
make_resid_diag <- function(resid_var) {
  diag(resid_var, nrow = length(resid_var))
}
