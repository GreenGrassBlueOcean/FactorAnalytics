#' @title Decompose Risk into individual factor contributions
#' 
#' @description Compute the factor contributions to Sd, VaR and ES of returns based on Euler's theorem, given 
#' the fitted factor model. This is a convenience wrapper that dispatches to the
#' specialized decomposition functions: \code{\link{fmSdDecomp}},
#' \code{\link{fmVaRDecomp}}, \code{\link{fmEsDecomp}},
#' \code{\link{portSdDecomp}}, \code{\link{portVaRDecomp}}, and
#' \code{\link{portEsDecomp}}.
#' 
#' @param object fit object of class \code{tsfm}, or \code{ffm}.
#' @param risk one of "Sd" (Standard Deviation) or "VaR" (Value at Risk) or "ES" (Expected Shortfall)
#' @param weights a vector of weights of the assets in the portfolio, names of 
#' the vector should match with asset names. Default is NULL, in which case an 
#' equal weights will be used.
#' @param portDecomp logical. If \code{True} the decomposition of risk is done for the portfolio based on the weights.
#' Else, the decomposition of risk is done for each asset. \code{Default} is \code{TRUE}
#' @param factor.cov optional user specified factor covariance matrix with 
#' named columns; defaults to the sample covariance matrix.
#' @param p tail probability for calculation. Default is 0.05.
#' @param type one of "np" (non-parametric) or "normal" for calculating Es. 
#' Default is "np".
#' @param invert a logical variable to choose if change ES to positive number, default
#' is False 
#' @param use an optional character string giving a method for computing factor
#' covariances in the presence of missing values. This must be (an 
#' abbreviation of) one of the strings "everything", "all.obs", 
#' "complete.obs", "na.or.complete", or "pairwise.complete.obs". Default is 
#' "pairwise.complete.obs".
#' @param ... other optional arguments passed to \code{\link[stats]{quantile}} and 
#' optional arguments passed to \code{\link[stats]{cov}}
#' 
#' @return A list containing 
#' \item{portES}{factor model ES of portfolio returns.}
#' \item{mES}{length-(K + 1) vector of marginal contributions to Es.}
#' \item{cES}{length-(K + 1) vector of component contributions to Es.}
#' \item{pcES}{length-(K + 1) vector of percentage component contributions to Es.}
#' Where, K is the number of factors. 
#' 
#' @author Eric Zivot, Yi-An Chen, Sangeetha Srinivasan, Lingjie Yi and Avinash Acharya
#' 
#' @seealso \code{\link{fmSdDecomp}}, \code{\link{fmVaRDecomp}},
#' \code{\link{fmEsDecomp}} for asset-level decomposition.
#' 
#' \code{\link{portSdDecomp}}, \code{\link{portVaRDecomp}},
#' \code{\link{portEsDecomp}} for portfolio-level decomposition.
#' 
#' \code{\link{fitTsfm}}, \code{\link{fitFfm}}
#' for the different factor model fitting functions.
#' 
#' @examples
#' # Time Series Factor Model
#' data(managers, package = 'PerformanceAnalytics')
#' fit.macro <- FactorAnalytics::fitTsfm(asset.names=colnames(managers[,(1:6)]),
#'                      factor.names=colnames(managers[,(7:9)]),
#'                      rf.name=colnames(managers[,10]), data=managers)
#' decompSd <- riskDecomp(fit.macro,risk = "Sd")
#' decompVaR <- riskDecomp(fit.macro,invert = TRUE, risk = "VaR")
#' decompES <- riskDecomp(fit.macro,invert = TRUE, risk = "ES")
#' # get the component contribution
#' 
#' # random weights 
#' wts = runif(6)
#' wts = wts/sum(wts)
#' names(wts) <- colnames(managers)[1:6]
#' portSd.decomp <- riskDecomp(fit.macro, wts, portDecomp = TRUE, risk = "Sd")
#' portVaR.decomp <- riskDecomp(fit.macro, wts, portDecomp = TRUE, risk = "VaR")
#' portES.decomp <- riskDecomp(fit.macro, wts, portDecomp = TRUE, risk = "ES")
#' 
#' # Fundamental Factor Model
#' data("stocks145scores6")
#' dat = stocks145scores6
#' dat$DATE = zoo::as.yearmon(dat$DATE)
#' dat = dat[dat$DATE >=zoo::as.yearmon("2008-01-01") & dat$DATE <= zoo::as.yearmon("2012-12-31"),]
#'
#'
#' # Load long-only GMV weights for the return data
#' data("wtsStocks145GmvLo")
#' wtsStocks145GmvLo = round(wtsStocks145GmvLo,5)  
#'                                                      
#' # fit a fundamental factor model
#' exposure.vars = c("SECTOR","ROE","BP","PM12M1M","SIZE", "ANNVOL1M", "EP")
#' fit.cross <- fitFfm(data = dat, 
#'               exposure.vars = exposure.vars,
#'               date.var = "DATE", 
#'               ret.var = "RETURN", 
#'               asset.var = "TICKER", 
#'               fit.method="WLS", 
#'               z.score = "crossSection")
#'               
#' decompES = riskDecomp(fit.cross, risk = "ES") 
#' 
#' #get the factor contributions of risk 
#' portES.decomp = riskDecomp(fit.cross, weights = wtsStocks145GmvLo, risk = "ES", portDecomp = TRUE)  
#' @export

riskDecomp <- function(object, ...){
  # check input object validity
  if (!inherits(object, c("tsfm", "ffm"))) {
    stop("Invalid argument: Object should be of class 'tsfm', or 'ffm'.")
  }
  UseMethod("riskDecomp")
}


# Apply riskDecomp's invert convention to VaR/ES decomposition results.
#
# riskDecomp convention: invert=FALSE (default) negates risk/marginal/component
# to produce positive numbers. invert=TRUE leaves raw (negative) values.
#
# The specialized portVaRDecomp/portEsDecomp methods have the OPPOSITE convention
# (invert=TRUE negates, and only the main risk measure). So riskDecomp always
# calls them with invert=FALSE (raw output) and applies its own logic here.
#
# @param out list returned by a specialized VaR or ES decomposition method
# @param risk character, "VaR" or "ES"
# @param invert logical, the riskDecomp invert parameter
# @param portDecomp logical, whether this is portfolio or asset level
# @return modified out list
apply_riskDecomp_invert <- function(out, risk, invert, portDecomp) {
  if (invert) return(out)

  # invert=FALSE (default): negate risk, marginal, and component values
  if (risk == "VaR") {
    risk_slot <- if (portDecomp) "portVaR" else "VaR.fm"
    out[[risk_slot]] <- -out[[risk_slot]]
    out$mVaR <- -out$mVaR
    out$cVaR <- -out$cVaR
  } else {
    risk_slot <- if (portDecomp) "portES" else "ES.fm"
    out[[risk_slot]] <- -out[[risk_slot]]
    out$mES <- -out$mES
    out$cES <- -out$cES
  }
  out
}


#' @rdname riskDecomp
#' @method riskDecomp tsfm
#' @export

riskDecomp.tsfm <- function(object, risk, weights = NULL, portDecomp = TRUE,
                            p = 0.05, type = c("np", "normal"),
                            factor.cov, invert = FALSE,
                            use = "pairwise.complete.obs", ...) {

  if (missing(risk) || !(risk %in% c("Sd", "VaR", "ES"))) {
    stop("Invalid or Missing arg: risk must be 'Sd' or 'VaR' or 'ES' ")
  }

  type <- type[1]
  if (!(type %in% c("np", "normal"))) {
    stop("Invalid args: type must be 'np' or 'normal' ")
  }

  # Conditionally include factor.cov in forwarded args
  fc_args <- if (!missing(factor.cov)) list(factor.cov = factor.cov) else list()

  if (portDecomp) {
    out <- switch(risk,
      Sd  = do.call(portSdDecomp,
              c(list(object = object, weights = weights, use = use),
                fc_args, list(...))),
      VaR = do.call(portVaRDecomp,
              c(list(object = object, weights = weights, p = p, type = type,
                     invert = FALSE, use = use),
                fc_args, list(...))),
      ES  = do.call(portEsDecomp,
              c(list(object = object, weights = weights, p = p, type = type,
                     invert = FALSE, use = use),
                fc_args, list(...)))
    )
  } else {
    out <- switch(risk,
      Sd  = do.call(fmSdDecomp,
              c(list(object = object, use = use), fc_args, list(...))),
      VaR = do.call(fmVaRDecomp,
              c(list(object = object, p = p, type = type, use = use),
                fc_args, list(...))),
      ES  = do.call(fmEsDecomp,
              c(list(object = object, p = p, type = type, use = use),
                fc_args, list(...)))
    )
  }

  if (risk != "Sd") {
    out <- apply_riskDecomp_invert(out, risk, invert, portDecomp)
  }

  out
}


#' @rdname riskDecomp
#' @method riskDecomp ffm
#' @export

riskDecomp.ffm <- function(object, risk, weights = NULL, portDecomp = TRUE,
                           factor.cov, p = 0.05, type = c("np", "normal"),
                           invert = FALSE, ...) {

  if (missing(risk) || !(risk %in% c("Sd", "VaR", "ES"))) {
    stop("Invalid or Missing arg: risk must be 'Sd' or 'VaR' or 'ES' ")
  }

  type <- type[1]
  if (!(type %in% c("np", "normal"))) {
    stop("Invalid args: type must be 'np' or 'normal' ")
  }

  fc_args <- if (!missing(factor.cov)) list(factor.cov = factor.cov) else list()

  if (portDecomp) {
    out <- switch(risk,
      Sd  = do.call(portSdDecomp,
              c(list(object = object, weights = weights), fc_args, list(...))),
      VaR = do.call(portVaRDecomp,
              c(list(object = object, weights = weights, p = p, type = type,
                     invert = FALSE),
                fc_args, list(...))),
      ES  = do.call(portEsDecomp,
              c(list(object = object, weights = weights, p = p, type = type,
                     invert = FALSE),
                fc_args, list(...)))
    )
  } else {
    out <- switch(risk,
      Sd  = do.call(fmSdDecomp,
              c(list(object = object), fc_args, list(...))),
      VaR = do.call(fmVaRDecomp,
              c(list(object = object, p = p, type = type), fc_args, list(...))),
      ES  = do.call(fmEsDecomp,
              c(list(object = object, p = p, type = type), fc_args, list(...)))
    )
  }

  if (risk != "Sd") {
    out <- apply_riskDecomp_invert(out, risk, invert, portDecomp)
  }

  out
}
