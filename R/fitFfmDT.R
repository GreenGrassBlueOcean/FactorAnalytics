# Strip heavy payload from lm/lmrob objects to reduce memory footprint.
# Preserves: coefficients, residuals, fitted.values, qr, rank, df.residual,
#   assign, terms, xlevels (needed by summary, vcov, predict, fitted).
# Strips: model frame, design matrix, response vector, captured call/scope.
strip_lm <- function(fit) {
  # Keep $model — predict.lm needs it when newdata = NULL to reconstruct
  # the model frame via model.frame.lm(). Stripping it breaks predict(fit).
  fit$x <- NULL
  fit$y <- NULL
  # Neuter call: preserve function name but strip captured data arguments.
  # For namespaced calls (e.g., RobStatTM::lmrobdetMM), deparse gives
  # "RobStatTM::lmrobdetMM" as a single string suitable for call().
  fn_name <- tryCatch(deparse(fit$call[[1L]]), error = function(e) "lm")
  fit$call <- call(fn_name)
  attr(fit$terms, ".Environment") <- baseenv()
  if (!is.null(fit$formula)) {
    environment(fit$formula) <- baseenv()
  }
  fit
}

# Build unrestricted design matrix with Market intercept.
# Given a data.frame with categorical columns (already factors), construct
# the model.matrix dummies and prepend a Market intercept column (all 1s).
# Handles both single-categorical (sector) and multi-categorical (MSCI) cases.
#
# @param data_df data.frame (or data.table subset) containing factor columns
# @param exposures_char character vector of categorical exposure column names
# @return matrix with columns: Market, then one-hot dummies for each exposure
build_beta_star <- function(data_df, exposures_char) {
  mm_list <- lapply(exposures_char, function(v) {
    model.matrix(~ . - 1, data = data_df[, v, drop = FALSE])
  })
  mm <- do.call(cbind, mm_list)
  cbind(Market = rep(1, nrow(data_df)), mm)
}

# Build sum-to-zero restriction matrix for categorical exposures.
# For a single categorical with K levels, produces a (K+1) x K matrix.
# For two categoricals with K1 and K2 levels, produces a (K1+K2+1) x (K1+K2-1)
# matrix with block-diagonal structure.
#
# @param K_levels integer vector of factor level counts (length 1 or 2)
# @return restriction matrix R such that B.mod = beta_star %*% R
build_restriction_matrix <- function(K_levels) {
  if (length(K_levels) == 1L) {
    K1 <- K_levels[1L]
    rbind(diag(K1), c(0, rep(-1, K1 - 1)))
  } else if (length(K_levels) == 2L) {
    K1 <- K_levels[1L]
    K2 <- K_levels[2L]
    rbind(
      cbind(diag(K1), matrix(0, nrow = K1, ncol = K2 - 1)),
      c(c(0, rep(-1, K1 - 1)), rep(0, K2 - 1)),
      cbind(matrix(0, ncol = K1, nrow = K2 - 1), diag(K2 - 1)),
      c(rep(0, K1), rep(-1, K2 - 1))
    )
  } else {
    stop("build_restriction_matrix supports at most 2 categorical exposures.",
         call. = FALSE)
  }
}

# Apply restriction matrix to unrestricted design matrix.
# Computes B.mod = beta_star %*% R_matrix and names columns V1..Vk.
#
# @param beta_star matrix from build_beta_star() (N x (1+sum(K)))
# @param R_matrix matrix from build_restriction_matrix()
# @return matrix B.mod with columns named V1, V2, ..., Vk
apply_restriction <- function(beta_star, R_matrix) {
  B_mod <- beta_star %*% R_matrix
  colnames(B_mod) <- paste0("V", seq_len(ncol(B_mod)))
  B_mod
}

# Build factor names vector for the fitted model.
# Handles all reachable cases across the three extractRegressionStats branches:
#   - no intercept + char exposure(s) → c(style, categorical_levels)
#   - style-only + intercept          → c("Alpha", style)
#   - style-only, no intercept        → style
#   - sector+style + intercept        → c("Market", style, categorical_levels)
#   - MSCI + intercept                → c("Market", style, all_categorical_levels)
#
# @param specObj ffmSpec object from specFfm()
# @return character vector of factor names
build_factor_names <- function(specObj) {
  has_char <- length(specObj$exposures.char) > 0L

  if (!specObj$addIntercept || specObj$model.styleOnly) {
    if (has_char) {
      lvl <- paste(levels(
        specObj$dataDT[, specObj$exposures.char, with = FALSE][[1L]]
      ), sep = "")
      c(specObj$exposures.num, lvl)
    } else if (specObj$addIntercept) {
      c("Alpha", specObj$exposures.num)
    } else {
      specObj$exposures.num
    }
  } else if (!specObj$model.MSCI) {
    lvl <- paste(levels(
      specObj$dataDT[, specObj$exposures.char, with = FALSE][[1L]]
    ), sep = "")
    c("Market", specObj$exposures.num, lvl)
  } else {
    lvl <- unlist(sapply(
      specObj$dataDT[, .SD, .SDcols = specObj$exposures.char], levels
    ))
    c("Market", specObj$exposures.num, paste(lvl, sep = ""))
  }
}

# Map restricted V-coefficients back to the original factor return space.
# Shared by sector (branch 2) and MSCI (branch 3) paths in
# extractRegressionStats where R_matrix links restricted coefficients
# to the full set of Market + categorical + style factor returns.
#
# @param g_row numeric vector of regression coefficients
#   (V1..VK_cat, then style coefficients if any)
# @param R_matrix restriction matrix from build_restriction_matrix()
# @param K_cat integer: number of restricted (V) coefficients = ncol(R_matrix)
# @param col_names character vector of output names in desired column order.
#   Length must equal nrow(R_matrix) + length(style coefficients).
# @return named numeric vector in col_names order
map_coefficients_to_factor_returns <- function(g_row, R_matrix, K_cat, col_names) {
  mapped_cat <- as.numeric(R_matrix %*% g_row[seq_len(K_cat)])

  if (length(g_row) > K_cat) {
    g_style <- g_row[(K_cat + 1L):length(g_row)]
    style_nm <- names(g_style)
    cat_nm <- setdiff(col_names, c("Market", style_nm))
    result <- numeric(length(col_names))
    names(result) <- col_names
    result["Market"] <- mapped_cat[1L]
    result[cat_nm] <- mapped_cat[-1L]
    result[style_nm] <- unname(g_style)
  } else {
    result <- mapped_cat
    names(result) <- col_names
  }
  result
}

#' @title Specifies the elements of a fundamental factor model
#'
#' @description Factor models have a few parameters that describe how the
#' fitting is done.  This function summarizes them and returns a spec object for
#' cross-sectional regressions.  It also preps the data. An object of class
#' \code{"ffmSpec"} is returned.
#'
#' @importFrom data.table as.data.table last setkey setkeyv copy shift key
#' setnames setcolorder
#' @importFrom stats ts cor
#'
#' @param data data.frame of the balanced panel data containing the variables
#' \code{asset.var}, \code{ret.var}, \code{exposure.vars}, \code{date.var} and
#' optionally, \code{weight.var}.
#' @param asset.var character; name of the variable  for asset names.
#' @param ret.var character; name of the variable for asset returns.
#' @param date.var character; name of the variable containing the dates
#' coercible to class \code{Date}.
#' @param exposure.vars vector; names of the variables containing the
#' fundamental factor exposures.
#' @param weight.var character; name of the variable containing the weights
#' used when standarizing style factor exposures. Default is \code{NULL}. See
#' Details.
#' @param addIntercept logical; If \code{TRUE}, intercept is added in
#'  the exposure matrix. Default is \code{FALSE},
#' @param rob.stats logical; If \code{TRUE}, robust estimates of covariance,
#' correlation, location and univariate scale are computed as appropriate (see
#' Details). Default is \code{FALSE}.
#'
#' @export
#'
specFfm <- function(data, asset.var, ret.var, date.var, exposure.vars,
                    weight.var = NULL, addIntercept = FALSE, rob.stats = FALSE){

  # Due to NSE notes related to data.table in R CMD check
  idx = RawReturn = NULL
  # See data.table "Importing data.table" vignette

  # set defaults and check input validity
  if (missing(data) || !is.data.frame(data)) {
    stop("Invalid args: data must be a data.frame")
  }
  if (missing(asset.var) || !is.character(asset.var)) {
    stop("Invalid args: asset.var must be a character string")
  }
  if (missing(date.var) || !is.character(date.var)) {
    stop("Invalid args: date.var must be a character string")
  }
  if (missing(ret.var) || !is.character(ret.var)) {
    stop("Invalid args: ret.var must be a character string")
  }
  if (missing(exposure.vars) || !is.character(exposure.vars)) {
    stop("Invalid args: exposure.vars must be a character vector")
  }
  if (ret.var %in% exposure.vars) {
    stop("Invalid args: ret.var cannot also be an exposure")
  }

  # Verify all referenced columns exist in data
  all_vars <- c(asset.var, date.var, ret.var, exposure.vars)
  if (!is.null(weight.var)) all_vars <- c(all_vars, weight.var)
  missing_cols <- setdiff(all_vars, colnames(data))
  if (length(missing_cols) > 0L) {
    stop("Invalid args: column(s) not found in data: ",
         paste(missing_cols, collapse = ", "), call. = FALSE)
  }

  if (!is.null(weight.var) && !is.character(weight.var)) {
    stop("Invalid args: weight.var must be a character string")
  }
  if (!is.logical(rob.stats) || length(rob.stats) != 1) {
    stop("Invalid args: control parameter 'rob.stats' must be logical")
  }
  obj <- list()
  class(obj) <- "ffmSpec"
  # prep the data
  obj$dataDT <- ( data.table::as.data.table(data))[, c(date.var,asset.var,ret.var,exposure.vars), with = FALSE]
  obj$dataDT[ , eval(date.var) := as.Date(get(date.var))]
  # mido important change of order
  data.table::setkeyv(obj$dataDT,c(asset.var, date.var))

  # this is needed for path dependent calculations
  obj$dataDT[, idx := 1:.N, by = eval(asset.var)]

  # specify the variables
  obj$asset.var <- asset.var
  obj$ret.var <- ret.var
  obj$dataDT[, RawReturn := get(ret.var)] # this is the raw return
  obj$yVar <- "RawReturn" # this will serve as the name of the regressand column
  obj$standardizedReturns <- FALSE
  obj$residualizedReturns <- FALSE

  obj$date.var <- date.var
  obj$exposure.vars <- exposure.vars
  obj$weight.var <- weight.var
  # treat the exposures
  obj$which.numeric <- sapply(obj$dataDT[,exposure.vars, with = F], is.numeric)
  obj$exposures.num <- exposure.vars[  obj$which.numeric]
  obj$exposures.char <- exposure.vars[!  obj$which.numeric]
  # specify the type of model
  if (length(  obj$exposures.char) > 1)
  { #Model has both Sector and Country along wit Intercept
    # however it is better to  check a different condition
    obj$model.MSCI = TRUE
  } else {
    obj$model.MSCI = FALSE
  }
  if (length(  obj$exposures.char) == 0)
  {
    obj$model.styleOnly = TRUE
  } else {
    obj$model.styleOnly = FALSE
    # this would prevent the issue of having one company in a sector..
    # this would produce 0 variance whcih causes the weight to blow up iin
    # WLS...  I check for the number of companies per date becuase we fit a model
    # for each day...
    if (min(  obj$dataDT[ , .N, by = c(date.var, obj$exposures.char)]$N) == 1 )
        stop("
             There is at least one ", obj$exposures.char, " that has one observation which will cause a
             problem with computing residual variance.")
  }


  obj$rob.stats <- rob.stats
  obj$addIntercept <- addIntercept
  obj$lagged <- FALSE

  return(obj)
}


#' @title lagExposures allows the user to lag exposures by one time period
#'
#' @description Function lag the style exposures in the exposure matrix
#'  by one time period.
#' @param specObj an ffm specification object of of class \code{"ffmSpec"}
#' @return specObj an ffm spec Object that has been lagged
#' @details this function operates on the data inside the specObj and applies a lag to
#' it
#' @seealso \code{\link{specFfm}} for information on the definition of the specFfm object.
#' @export
#'
lagExposures <- function(specObj){

  idx <- NULL # due to NSE notes related to data.table in R CMD check

  a_ <- eval(specObj$asset.var) # name of the asset column or id

  specObj$dataDT <- data.table::copy(specObj$dataDT) # hard_copy

  # need to protect against only categorical variables -Mido

  # for (e_ in specObj$exposures.num){
  for (e_ in specObj$exposure.vars){
    specObj$dataDT[, eval(e_) := shift(get(e_), fill = NA, type = "lag") , by = a_]
  }

  specObj$lagged <- TRUE

  specObj$dataDT <- specObj$dataDT[!is.na(get(e_))]

  data.table::setkeyv(specObj$dataDT,c(a_, specObj$date.var))

  # this is needed for path dependent calculations
  specObj$dataDT[, idx := 1:.N, by = eval(specObj$asset.var)]

  return(specObj)
}



#' @title standardizeExposures
#'
#' @description
#' function to calculate z-scores for numeric exposure using weights weight.var
#'
#' @param specObj is a ffmSpec object,
#' @param Std.Type method for exposure standardization; one of "none",
#' "CrossSection", or "TimeSeries".
#' Default is \code{"none"}.
#' @param lambda lambda value to be used for the EWMA estimation of residual
#' variances. Default is 0.9
#'
#' @return the ffM spec object with exposures z-scored
#' @details this function operates on the data inside the specObj and applies a
#' standardization to it.  The user can choose CrossSectional or timeSeries standardization
#'
#' @seealso \code{\link{specFfm}} for information on the definition of the specFfm object.
#' @export
#'
standardizeExposures <- function(specObj,
                                 Std.Type = c("None",
                                              "CrossSection",
                                              "TimeSeries"),
                                 lambda = 0.9){

  # Due to NSE notes related to data.table in R CMD check
  w <- s <- ts <- NULL


  weight.var <- specObj$weight.var
  dataDT <- data.table::copy(specObj$dataDT) # hard_copy
  # we did have a copy but do we really need a full  copy, reference should be oka here
  if (is(specObj) != "ffmSpec") {
    stop("specObj must be class ffmSpec")
  }
  Std.Type = toupper(Std.Type[1])
  Std.Type <- match.arg(arg = Std.Type, choices = toupper(c("NONE", "CROSSSECTION", "TIMESERIES")),
                        several.ok = F )

  a_ <- specObj$asset.var
  d_ <- specObj$date.var
  # Convert numeric exposures to z-scores
  if (!grepl(Std.Type, "NONE")) {
    if (!is.null(weight.var)) {
      dataDT[, w := get(weight.var)] # adding the weight variable to dataDT
      # Weight exposures within each period using weight.var
      dataDT[ , w := w/sum(w, na.rm = TRUE), by = d_]

    } else {
      dataDT[, w := 1] # adding the weight variable to the data table

    }

    # Calculate z-scores looping through all numeric exposures
    if (grepl(Std.Type, "CROSSSECTION")) {
      for (e_ in specObj$exposures.num) {
        if (specObj$rob.stats) {
          dataDT[, eval(e_) := (w * get(e_) - median(w * get(e_), na.rm = TRUE))/mad(w * get(e_),
                   center = median(w * get(e_), na.rm = TRUE)),
                   by = d_]

        } else {
          dataDT[, eval(e_) := (w * get(e_) - mean(w * get(e_), na.rm = TRUE))/
                   sqrt(sum((w * get(e_) - mean(w * get(e_), na.rm = T))^2, na.rm = T)/(.N - 1) ),
                 by = d_]
          # sd(get(e_) , na.rm = T)

        }
      }
    } else {
      # for each exposure...quartion : do we need to weight it here?
      #startIdx <- ifelse(specObj$lagged,2,1)
      for (e_ in specObj$exposures.num) {
# for each asset compute the difference between its exposure at time t - 1 and
# the Xsection mean of exposures and square it
        dataDT[, ts := (get(e_) - mean(get(e_), na.rm = TRUE))^2, by = d_]
        data.table::setorderv(dataDT, c(a_, d_))
        dataDT[, s := {
          n <- .N
          if (n == 1L) {
            ts[1L]
          } else {
            c(ts[1L],
              as.numeric(stats::filter(
                x = (1 - lambda) * ts[-1L],
                filter = lambda,
                method = "recursive",
                init = ts[1L]
              )))
          }
        }, by = a_]
        dataDT[, eval(e_) := (get(e_) - mean(get(e_), na.rm = TRUE))/sqrt(s), by = d_]
      }
      dataDT[, ts := NULL]
      dataDT[, s := NULL]

    }
  }

  specObj$dataDT <- dataDT

  return(specObj)
}

#'
#'
#' @title  residualizeReturns
#'
#' @description  #' function to Residualize the returns via regressions
#'
#' @param specObj  specObj is a ffmSpec object,
#' @param benchmark we might need market returns
#' @param rfRate risk free rate
#' @param isBenchExcess toggle to select whether to calculate excess returns
#' @details this function operates on the data inside the specObj and residualizes
#' the returns to create residual return using regressions of returns on a
#' benchmark.
#'
#' @seealso \code{\link{specFfm}} for information on the definition of the specFfm object.
#' @importFrom xts is.xts
#'
#' @export
residualizeReturns <- function(specObj, benchmark, rfRate, isBenchExcess = F ){

  # Due to NSE notes related to data.table in R CMD check
  ExcessReturn = . = ResidualizedReturn = NULL
  # See data.table "Importing data.table" vignette


  dataDT <- data.table::copy(specObj$dataDT) # hard_copy
  currKey <- data.table::key(dataDT)
  d_ <- eval(specObj$date.var)

  data.table::setkeyv(dataDT, d_) # for merging with bench and ref

  a_ <- eval(specObj$asset.var) # name of the asset column or id
  r_ <- specObj$yVar # name of the variable column for returns.. sometimes get sometimes eval
  # we need this variable to be created.. in case returns are not standardized
  #dataDT[, rawReturn := get(r_)]

  # the benchmark is required to be in  an xts so that we know where the date is
  if (is.xts(benchmark)){
    specObj$benchmark.var <- colnames(benchmark) # do this before converting to data.table
    if (is.null(specObj$benchmark.var)) stop("benchmark data must have column names.")
    benchmark <-  data.table::as.data.table(benchmark)
    data.table::setnames(benchmark, old = "index", d_) # this way we are able to merge
    benchmark[[d_]] <- as.Date(benchmark[[d_]])
    data.table::setkeyv(benchmark, d_)
    dataDT <- merge(dataDT, benchmark, all.x = TRUE) # left join

  } else {
    stop("Invalid args: benchmark must be an xts.")
  }

  if (is.xts(rfRate)){
    specObj$rfRate.var <- colnames(rfRate)
    if (is.null(specObj$rfRate.var)) stop("risk free vector must have a column name.")
    rfRate <-  data.table::as.data.table(rfRate)
    data.table::setnames(rfRate, old = "index", d_) # this way we are able to merge
    rfRate[[d_]] <- as.Date(rfRate[[d_]])
    data.table::setkeyv(rfRate, d_)
    dataDT <- merge(dataDT, rfRate, all.x = TRUE) # left join

  } else {
    stop("Invalid args: rfRate must be an xts.")
  }

  data.table::setkeyv(dataDT, currKey)
  dataDT[, ExcessReturn := get(r_) - get(specObj$rfRate.var)]

  if (!isBenchExcess) {
    for (b_ in specObj$benchmark.var){
      dataDT[, eval(b_) := get(b_) - get(specObj$rfRate.var)]
    }

  }

  residuals.DT <- dataDT[, .(resid = .(residuals(lm(ExcessReturn ~0+ get(specObj$benchmark.var))))) , by = a_]
  dataDT[, ResidualizedReturn := unlist(residuals.DT$resid)]

  specObj$yVar <- "ResidualizedReturn"
  specObj$residualizedReturns <- TRUE
  specObj$dataDT <- data.table::copy(dataDT)

  return(specObj)
}


#' @title standardizeReturns
#'
#' @description Standardize the returns using GARCH(1,1) volatilities.
#' @param specObj  is a ffmSpec object
#' @param GARCH.params fixed Garch(1,1) parameters
#'
#' @return an ffmSpec Object with the standardized returns added
#' @details this function operates on the data inside the specObj and standardizes
#' the returns to create scaled return.
#' @seealso \code{\link{specFfm}} for information on the definition of the specFfm object.
#' @export
standardizeReturns <- function(specObj,
                               GARCH.params = list(omega = 0.09,
                                                   alpha = 0.1,
                                                   beta = 0.81)) {

  # Due to NSE notes related to data.table in R CMD check
  sdReturns <- sigmaGarch <- StandardizedReturns <- ts <- NULL
  # See data.table "Importing data.table" vignette

  dataDT <- data.table::copy(specObj$dataDT) # hard_copy
  a_ <- specObj$asset.var
  d_ <- specObj$date.var
  r_ <- specObj$yVar
  # we need this variable to be created.. in case returns are not standardized

  alpha <- GARCH.params$alpha
  beta <- GARCH.params$beta
  dataDT[, sdReturns := list(sd(get(r_), na.rm = TRUE)), by = a_]

  # for each asset calculate squared returns
  dataDT[, ts := get(r_)^2]

  data.table::setorderv(dataDT, c(a_, d_))
  dataDT[, sigmaGarch := {
    omega_i <- (1 - alpha - beta) * sdReturns[1L]^2
    x <- omega_i + alpha * ts
    n <- .N
    if (n == 1L) {
      x[1L]
    } else {
      c(x[1L],
        as.numeric(stats::filter(
          x = x[-1L],
          filter = beta,
          method = "recursive",
          init = x[1L]
        )))
    }
  }, by = a_]


  dataDT[, sigmaGarch := sqrt(sigmaGarch)]

  #dataDT[, stdReturns:=get(r_)]

  specObj$standardizedReturns <- TRUE

  # dataDT[, preStdReturns := get(r_)]
  # if we standardize then we do regressions with the std returns?
  # dataDT[, eval(r_) := get(r_)/sigmaGarch]
  dataDT[, StandardizedReturns := get(r_)/sigmaGarch]
  specObj$yVar <- "StandardizedReturns"
  # dataDT[, stdReturns := get(r_)]
  dataDT[, sdReturns := NULL]
  dataDT[, ts := NULL]
  # dataDT[, sigmaGarch := NULL]
  specObj$dataDT <- data.table::copy(dataDT)

  return(specObj)
}



#'
#' @title fitFfmDT
#'
#' @description This function fits a fundamental factor model
#'
#' @param ffMSpecObj a \link{specFfm} object
#' @param fit.method method for estimating factor returns; one of "LS", "WLS"
#' "ROB" or "W-ROB". See details. Default is "LS".
#' @param resid.scaleType one of 4 choices "StdDev","EWMA","RobustEWMA", "GARCH"
#' @param lambda the ewma parameter
#' @param GARCH.params list containing GARCH parameters omega, alpha, and beta.
#' Default values are (0.09, 0.1, 0.81) respectively. Valid only when
#' \code{GARCH.MLE} is set to \code{FALSE}. Estimation outsourced to the
#'  rugarch package, please load it first.
#' @param GARCH.MLE boolean input (TRUE|FALSE), default value = \code{FALSE}. This
#' argument allows one to choose to compute GARCH parameters by maximum
#' likelihood estimation. Estimation outsourced to the rugarch
#' package, please load it.
#' @param lmrobdet.control.para.list list of parameters to pass to lmrobdet.control().
#' Sets tuning parameters for the MM estimator implemented in lmrobdetMM of the
#' RobStatTM package. See \code{\link[RobStatTM]{lmrobdetMM}}.
#' @param ... additional pass through arguments
#'
#' @return \code{fitFfm} returns a list with two object of class \code{"data.table"}
#' The first reg.listDT is object of class \code{"data.table"} is a list containing the following
#' components:
#' \item{DATE}{length-T vector of dates.}
#' \item{id}{length-N vector of asset id's for each date.}
#' \item{reg.list}{list of fitted objects that estimate factor returns in each
#' time period. Each fitted object is of class \code{lm} if
#' \code{fit.method="LS" or "WLS"}, or, class \code{lmrobdetMM} if
#' \code{fit.method="Rob" or "W-Rob"}.}
#' The second betasDT is object of class \code{"data.table"} is a list containing the following
#' components:
#' \item{DATE}{length-T vector of dates.}
#' \item{R_matrix}{The K+1 by K restriction matrix where K is the number of categorical variables for each date.}
#' @details this function operates on the data inside the specObj fits a fundamental factor
#' model to the data
#' @seealso \code{\link{specFfm}} for information on the definition of the specFfm object.
#' @importFrom stats complete.cases
#'
#' @export
#'
fitFfmDT <- function(ffMSpecObj,
                     fit.method=c("LS","WLS","Rob","W-Rob"),
                     resid.scaleType = c("StdDev","EWMA","RobustEWMA", "GARCH"),
                     lambda = 0.9,
                     GARCH.params = list(omega = 0.09, alpha = 0.1, beta = 0.81),
                     GARCH.MLE = FALSE,
                     lmrobdet.control.para.list = NULL,
                     ...){

  # Due to NSE notes related to data.table in R CMD check
  . = beta.star = R_matrix = toRegress = beta.mod.style = B.style = NULL
  beta.mic = K = K1 = K2 = W = B.mod = NULL
  # See data.table "Importing data.table" vignette

  fit.method = toupper(fit.method[1])
  fit.method <- match.arg(arg = fit.method, choices = toupper(c("LS","WLS","ROB","W-ROB")), several.ok = F )

  # Guard robust regression dependencies
  if (fit.method %in% c("ROB", "W-ROB")) {
    if (!requireNamespace("RobStatTM", quietly = TRUE)) {
      stop("Package 'RobStatTM' is required for fit.method = '", fit.method,
           "'. Install it with: install.packages('RobStatTM')", call. = FALSE)
    }
    if (is.null(lmrobdet.control.para.list)) {
      lmrobdet.control.para.list <- RobStatTM::lmrobdet.control()
    }
  }

  resid.scaleType <- toupper(resid.scaleType[1])
  resid.scaleType <- match.arg(arg = resid.scaleType, choices = c("STDDEV","EWMA","ROBUSTEWMA", "GARCH"))

  # if ((resid.scaleType != "STDDEV") && !(fit.method %in% c("WLS","W-Rob"))) {
  #   stop("Invalid args: resid.scaleType ", resid.scaleType, " must be used with WLS or W-Rob")
  # }

  a_ <- eval(ffMSpecObj$asset.var) # data table requires variable names to be evaluated
  d_ <- eval(ffMSpecObj$date.var)

  # SET UP of FORMULAS ----
  # determine factor model formula to be passed to lm or lmrobdetMM
  fm.formula <- paste(ffMSpecObj$yVar, "~", paste(ffMSpecObj$exposure.vars, collapse="+"))

  if (!ffMSpecObj$model.MSCI){


    if (length(ffMSpecObj$exposures.char)){
      #Remove Intercept as it introduces rank deficiency in the exposure matrix.
      #Implemetation with Intercept is handled later, using a Restriction matrix
      # to remove the rank deficiency.
      fm.formula <- paste(fm.formula, "- 1")
      ffMSpecObj$dataDT[, eval(ffMSpecObj$exposures.char) :=  as.factor(get(ffMSpecObj$exposures.char))]

      factor.names <- c("Market", paste(levels(ffMSpecObj$dataDT[[ffMSpecObj$exposures.char]]),sep=" "),
                        ffMSpecObj$exposures.num)

    } else if (ffMSpecObj$addIntercept == FALSE){
      fm.formula <- paste(fm.formula, "- 1")
    }
    # convert the pasted expression into a formula object
    fm.formula <- as.formula(fm.formula)

    sdcols <- c(data.table::key(ffMSpecObj$dataDT), ffMSpecObj$yVar, ffMSpecObj$exposure.vars )
    #Beta  is for the whole model (generally without intercept)
    #clean up NA's
    ffMSpecObj$dataDT <- ffMSpecObj$dataDT[complete.cases(ffMSpecObj$dataDT[, .SD, .SDcols = sdcols])]
    betasDT <- ffMSpecObj$dataDT[, .(toRegress = .(.SD),
                                     beta = .(model.matrix(fm.formula, .SD))),
                                 .SDcols = sdcols, by = d_]
    idxNA <- sapply(betasDT$toRegress, FUN = anyNA) # this could exist due to LAGGING of exposures

    if (length(ffMSpecObj$exposures.char)){
      beta_star_dt <- ffMSpecObj$dataDT[, list(
        beta.star = list(build_beta_star(as.data.frame(.SD), ffMSpecObj$exposures.char))
      ), .SDcols = sdcols, by = d_]
      beta_star_dt[, K := .(dim(beta.star[[1]])[2]), by = d_]
      data.table::setkeyv(betasDT, d_)
      data.table::setkeyv(beta_star_dt, d_)

      betasDT <- betasDT[beta_star_dt]
    }



    if (ffMSpecObj$addIntercept == TRUE && ffMSpecObj$model.styleOnly ==FALSE) {
      K_levels <- vapply(ffMSpecObj$exposures.char,
                         function(v) nlevels(ffMSpecObj$dataDT[[v]]),
                         integer(1))
      betasDT[, R_matrix := list(list(build_restriction_matrix(K_levels))), by = d_]
      betasDT[, B.mod := list(list(apply_restriction(beta.star[[1]], R_matrix[[1]]))), by = d_]

      betasDT[, toRegress := .(.(cbind(B.mod[[1]],toRegress[[1]] ))), by = d_]

      data.table::setkeyv(betasDT, d_)
      if(length(ffMSpecObj$exposures.num) > 0){
        sdcols <- ffMSpecObj$exposures.num
        #Define Beta for Style factors
        tempDT <- ffMSpecObj$dataDT[, .(B.style = .(as.matrix(x = .SD))),
                                    .SDcols = sdcols, by = d_]
        data.table::setkeyv(tempDT, ffMSpecObj$date.var)

        betasDT <- betasDT[tempDT]
        betasDT[, beta.mod.style := .(.(cbind(B.mod[[1]],B.style[[1]]))), by = d_]

      }

      # Formula for Market+Sector/Country Model
      n_V <- sum(K_levels)
      fmSI.formula <- as.formula(paste(ffMSpecObj$yVar, "~",
                                       paste(c(paste0("V", seq_len(n_V)),
                                               ffMSpecObj$exposures.num), collapse = "+"),
                                       "-1"))
      fm.formula <- fmSI.formula
    }
  } else {

    # MSCI..
    if (length(ffMSpecObj$exposures.char)) {
      fm.formula <- paste(fm.formula, "- 1")
      ffMSpecObj$dataDT[ ,  (ffMSpecObj$exposures.char) := lapply(.SD, as.factor), .SDcols = ffMSpecObj$exposures.char]
    }

    # convert the pasted expression into a formula object
    fm.formula <- as.formula(fm.formula)
    sdcols <- c(data.table::key(ffMSpecObj$dataDT), ffMSpecObj$yVar, ffMSpecObj$exposure.vars )
    ffMSpecObj$dataDT <- ffMSpecObj$dataDT[complete.cases(ffMSpecObj$dataDT[, .SD, .SDcols = sdcols])]
    betasDT <- ffMSpecObj$dataDT[, list(
      toRegress = list(.SD),
      beta = list(model.matrix(fm.formula, .SD)),
      beta.mic = list(build_beta_star(as.data.frame(.SD), ffMSpecObj$exposures.char))
    ), .SDcols = sdcols, by = d_]

    K_levels_msci <- vapply(ffMSpecObj$exposures.char,
                            function(v) nlevels(ffMSpecObj$dataDT[[v]]),
                            integer(1))
    betasDT[, K1 := K_levels_msci[1L]]
    betasDT[, K2 := K_levels_msci[2L]]

    betasDT[, R_matrix := list(list(build_restriction_matrix(K_levels_msci))), by = d_]
    betasDT[, B.mod := list(list(apply_restriction(beta.mic[[1]], R_matrix[[1]]))), by = d_]

    betasDT[, toRegress := .(.(cbind(B.mod[[1]],toRegress[[1]] ))), by = d_]

    data.table::setkeyv(betasDT, d_)
    idxNA <- sapply(betasDT$toRegress, FUN = anyNA)

    # Formula for MSCI Model
    n_V_msci <- sum(K_levels_msci) - 1L
    fmMSCI.formula <- as.formula(paste(ffMSpecObj$yVar, "~",
                                       paste(c(paste0("V", seq_len(n_V_msci)),
                                               ffMSpecObj$exposures.num), collapse = "+"),
                                       "-1"))
    fm.formula <- fmMSCI.formula






  }

  # Perform Regressions ----

  # estimate factor returns using LS or Robust regression ----
  # returns a list of the fitted lm or lmrobdetMM objects for each time period
  if (grepl("LS",fit.method)) {

    reg.listDT <- betasDT[which(!idxNA), list(id = list(toRegress[[1]][[a_]]),
                                           reg.list = list({
                                             fit <- lm(formula = fm.formula, data = toRegress[[1]],
                                                        na.action = na.omit)
                                             strip_lm(fit)
                                           })), by = d_]

  }else if (grepl("ROB",fit.method)) {


    reg.listDT <- betasDT[which(!idxNA), list(id = list(toRegress[[1]][[a_]]),
                                           reg.list = list({
                                             fit <- RobStatTM::lmrobdetMM(formula = fm.formula,
                                                                   data = toRegress[[1]],
                                                                   na.action = na.omit,
                                                                   control = lmrobdet.control.para.list)
                                             strip_lm(fit)
                                           })), by = d_]
  }
  # second pass weighted regressions ----
  if (grepl("W",fit.method)) {

    SecondStepRegression <- data.table::rbindlist(betasDT$toRegress)
    # compute residual variance for all assets for weighted regression
    # the weights will be 1/w
    SecondStepRegression <- calcAssetWeightsForRegression(specObj = ffMSpecObj, fitResults = reg.listDT,
                                                          SecondStepRegression = SecondStepRegression, resid.scaleType = resid.scaleType,
                                                          lambda = lambda, GARCH.params = GARCH.params, GARCH.MLE = GARCH.MLE)
    # estimate factor returns using WLS or weighted-Robust regression
    # returns a list of the fitted lm or lmrobdetMM objects for each time period
    # w <- SecondStepRegression[, c(d_, a_, "W"), with = F] # needed for the residual variances
    # w$W <- 1/w$W
    if (fit.method=="WLS") {
      reg.listDT <- SecondStepRegression[ complete.cases(SecondStepRegression[,ffMSpecObj$exposure.vars, with = F]) ,
                                          list(reg.list = list({
                                            fit <- lm(formula = fm.formula, data = .SD, weights = W, na.action = na.omit)
                                            strip_lm(fit)
                                          }))
                                          , by = d_]

    } else if (fit.method=="W-Rob") {


      reg.listDT <-
        SecondStepRegression[ complete.cases(SecondStepRegression[,ffMSpecObj$exposure.vars, with = F]) ,
                              list(reg.list = list({
                                fit <- RobStatTM::lmrobdetMM(
                                  formula = fm.formula,
                                  data = .SD,
                                  weights = W,
                                  na.action = na.omit,
                                  control = lmrobdet.control.para.list)
                                strip_lm(fit)
                              }))
                              , by = d_]

    }
    assetInfo <- SecondStepRegression[complete.cases(SecondStepRegression[,ffMSpecObj$exposure.vars, with = F]),
                                      .(id = .(get(a_)), w = .(1/W)), by = d_]
    data.table::setkeyv(assetInfo, d_)
    data.table::setkeyv(reg.listDT, d_)
    reg.listDT <- reg.listDT[assetInfo]
  }


  return(list(reg.listDT = reg.listDT, betasDT = betasDT,
              resid.scaleType = resid.scaleType, fit.method = fit.method)
  )


}




#' @title extractRegressionStats
#'
#' @description function to compute or Extract objects to be returned
#'
#' @param specObj fitFM object that has been already fit
#' @param fitResults output from fitFfmDT
#' @param full.resid.cov an option to calculate the full residual covariance or not
#'
#' @return a structure of class ffm holding all the information
#' @details this function operates on the specObje data and the output of fitFfm
#' to get information on the fundamental factor.
#'
#' @importFrom methods is
#'
#' @seealso \code{\link{specFfm}} and \code{\link{fitFfmDT}} for information on the definition of the specFfm
#' object and the usage of fitFfmDT.
#'
#' @importFrom data.table rbindlist dcast as.xts.data.table last
#' @importFrom stats coefficients
#'
#' @export
#'
extractRegressionStats <- function(specObj, fitResults, full.resid.cov=FALSE){

  # Due to NSE notes related to data.table in R CMD check
  reg.list <- id <- R_matrix <- B.mod <- beta.mic <- w <- NULL
  # See data.table "Importing data.table" vignette

  restriction.mat = NULL
  g.cov = NULL

  a_ <- eval(specObj$asset.var) # data table requires variable names to be evaluated
  d_ <- eval(specObj$date.var) # name of the date var
  reg.listDT <- data.table::copy(fitResults$reg.listDT)
  betasDT <- data.table::copy(fitResults$betasDT)
  resid.scaleType <- fitResults$resid.scaleType # we send this because what we do in the
  # fit is linked to how we extract results
  fit.method <- fitResults$fit.method

  # r-squared values for each time period ----
  r2 <- reg.listDT[, list(r2 = list(summary(reg.list[[1]])$r.squared)), by = d_]
  r2 <- unlist(r2$r2)
  names(r2) <- reg.listDT[[d_]]

  # residuals ----
  reg.listDT[, residuals := list(list(data.frame(date = get(d_), id = id,
                                           residuals = residuals(reg.list[[1]])))), by = d_]
  # now we have to extract the asset level residuals series and get their time series variance or
  # robust stats
  # residuals1 <-  data.table::as.data.table(reg.listDT[get(d_) == max(get(d_)),]$residuals[[1]])
  # we have a problem here in case of a jagged matrix
  residuals1 <- data.table::rbindlist(l = reg.listDT$residuals, use.names = F)
  data.table::setnames(residuals1, c("date", "id", "residuals") )
  # Assets in the final cross-section determine beta dimensions and

  # residual column filtering. For unbalanced panels, this excludes
  # delisted assets that exited before the last period.
  a_last <- reg.listDT[get(d_) == max(get(d_)),]$id[[1]]
  asset.names <- a_last
  # this is needed so that the matrices conform
  residuals1 <- residuals1[ id %in% a_last]
  residuals1 <- data.table::dcast(data = residuals1, formula = date ~ id,
                                  value.var = "residuals")
  residuals1 <- data.table::as.xts.data.table(residuals1)

  # Resdiuals ----
  #if resid.scaleType is not stdDev, use the most recent residual var as the diagonal cov-var of residuals
  if (grepl("W",fit.method)){
    reg.listDT[, w := list(list(data.frame(date = get(d_)[[1]], id = reg.listDT$id[[1]],
                                     w = w[[1]]))), by = d_]
    w <- data.table::rbindlist(l = reg.listDT$w)
    w <- data.table::dcast(data = w , formula = date ~ id, value.var = "w")
    w <- data.table::as.xts.data.table(w)

    resid.cov  <- diag(as.numeric(w[data.table::last(index(w)),])) # use the last estimate
    # update resid.var with the timeseries of estimated resid variances
    resid.var = w


  }
  #Residual Variance ----
  residuals1 <- residuals1[, which(!is.na(data.table::last(residuals1)))]
  resid.var <- apply(coredata(residuals1), 2, var, na.rm=T)
  # resid.var <- resid.var[which(!is.na(xts::last(residuals1)))]
  # if we have an unbalanced panel...then there would be some NA's so we have to clean them up
  # we just need the last period


  # residual covariances----
  if (specObj$rob.stats) {
    if (!requireNamespace("robustbase", quietly = TRUE)) {
      stop("Package 'robustbase' is required for rob.stats = TRUE. ",
           "Install it with: install.packages('robustbase')", call. = FALSE)
    }
    resid.var <- apply(coredata(residuals1), 2, robustbase::scaleTau2)^2
    if (full.resid.cov) {
      resid.cov <- robustbase::covOGK(coredata(residuals1), sigmamu=robustbase::scaleTau2, n.iter=1)$cov
    } else {
      resid.cov <- diag(resid.var)
    }

  } else {

    if (full.resid.cov) {
      resid.cov <- cov(coredata(residuals1), use = "pairwise.complete.obs")
    } else {
      resid.cov <- diag(resid.var)
    }
  }


  factor.names <- build_factor_names(specObj)

  if (specObj$addIntercept == FALSE || specObj$model.styleOnly ==TRUE) {

    # coefficients ----

    reg.listDT[, factor.returns := list(list(data.frame(date = get(d_)[[1]], factor.names = list(factor.names),
                                                  factor.returns = coefficients(reg.list[[1]])))), by = d_]

    # now we have to extract the asset level residuals series and get their time series variance or
    # robust stats
    factor.returns <- data.table::rbindlist(l = reg.listDT$factor.returns)
    colnames(factor.returns)[2] <- "factor"
    factor.returns <- data.table::dcast(data = factor.returns , formula = date ~ factor, value.var = "factor.returns")
    data.table::setcolorder(factor.returns,  c("date", factor.names))
    factor.returns <- data.table::as.xts.data.table(factor.returns)

    #Exposure matrix for the last time period
    beta <- betasDT[ get(d_) == max(get(d_)), ]$beta[[1]]
    rownames(beta) <- reg.listDT[ get(d_) == max(get(d_)), ]$id[[1]]
    if (specObj$addIntercept == TRUE) colnames(beta)[1] <- "Alpha"


  } else if ( specObj$addIntercept && specObj$model.styleOnly == FALSE && !specObj$model.MSCI) {

    # coefficients ----

    g <- reg.listDT[, list(g = list(coefficients(reg.list[[1]]))), by = d_]
    data.table::setkeyv(g, d_)
    factor.returns <- betasDT[, c(d_, "R_matrix"), with = FALSE][g]

    g <- g[, list(list(data.frame(date = get(d_)[[1]], t(g[[1]])))), by = d_]
    g <- data.table::rbindlist(g$V1)
    g <- data.table::as.xts.data.table(g)
    g.cov <- cov(g)

    K <- ncol(betasDT[1, ]$R_matrix[[1]])
    # Sector branch column order: Market, categorical levels, then style
    cat_levels <- levels(specObj$dataDT[[specObj$exposures.char]])
    fr_col_names <- if (length(specObj$exposures.num)) {
      c("Market", cat_levels, specObj$exposures.num)
    } else {
      c("Market", cat_levels)
    }

    factor.returns[, factor.returns := list(list(matrix(
      map_coefficients_to_factor_returns(g[[1]], R_matrix[[1]], K, fr_col_names),
      nrow = 1,
      dimnames = list(date = eval(d_)[[1]], factors = fr_col_names)
    ))), by = d_]

    factor.returns[, factor.returns := list(list(
      data.frame(date = get(d_)[[1]], factor.returns[[1]])
    )), by = d_]
    factor.returns <- data.table::rbindlist(factor.returns$factor.returns)
    factor.returns <- data.table::as.xts.data.table(factor.returns)



    #Restriction matrix
    restriction.mat <- betasDT[ get(d_) == max(get(d_)), R_matrix[[1]]]

    #Returns covariance
    if(length(specObj$exposures.num) > 0){
      #Exposure matrix for the last time period
      beta.star <- as.matrix(betasDT[ get(d_) == max(get(d_)), beta.star[[1]]])
      B.style <- as.matrix(betasDT[ get(d_) == max(get(d_)), B.style[[1]]])

      beta <- cbind(beta.star[,1], B.style, beta.star[,-1])
      colnames(beta) <- factor.names
      rownames(beta) <- asset.names
      beta.stms = as.matrix(betasDT[ get(d_) == max(get(d_)),cbind(B.mod, B.style)])
    } else    {
      #Exposure matrix for the last time period
      beta <- as.matrix(betasDT[ get(d_) == max(get(d_)), beta.star[[1]]])
      rownames(beta) <- asset.names
      beta.stms = as.matrix(betasDT[ get(d_) == max(get(d_)), B.mod[[1]] ])
    }
    # return covariance estimated by the factor model

  } else {
    # msci — model with 2+ character exposures (e.g. Sector + Country)

    g <- reg.listDT[, list(g = list(coefficients(reg.list[[1]]))), by = d_]
    data.table::setkeyv(g, d_)
    factor.returns <- betasDT[, c(d_, "R_matrix"), with = FALSE][g]

    g <- g[, list(list(data.frame(date = get(d_)[[1]], t(g[[1]])))), by = d_]
    g <- data.table::rbindlist(g$V1)
    g <- data.table::as.xts.data.table(g)
    g.cov <- cov(g)

    K_cat <- ncol(betasDT[1, ]$R_matrix[[1]])

    factor.returns[, factor.returns := list(list(matrix(
      map_coefficients_to_factor_returns(g[[1]], R_matrix[[1]], K_cat, factor.names),
      nrow = 1,
      dimnames = list(date = eval(d_)[[1]], factors = factor.names)
    ))), by = d_]

    factor.returns[, factor.returns := list(list(
      data.frame(date = get(d_)[[1]], factor.returns[[1]])
    )), by = d_]
    factor.returns <- data.table::rbindlist(factor.returns$factor.returns)
    factor.returns <- data.table::as.xts.data.table(factor.returns)

    restriction.mat <- betasDT[get(d_) == max(get(d_)), R_matrix[[1]]]

    #Exposure matrix for the last time period
    beta <- as.matrix(betasDT[get(d_) == max(get(d_)), beta.mic[[1]]])
    rownames(beta) <- asset.names

    if (length(specObj$exposures.num) > 0) {
      # Include style exposures in beta, ordered: Market, style, categorical
      B.style <- as.matrix(
        specObj$dataDT[get(d_) == max(get(d_)), .SD, .SDcols = specObj$exposures.num]
      )
      rownames(B.style) <- asset.names
      beta <- cbind(beta[, 1, drop = FALSE], B.style, beta[, -1, drop = FALSE])
    }

    beta.stms <- as.matrix(betasDT[get(d_) == max(get(d_)), B.mod[[1]]])
    if (length(specObj$exposures.num) > 0) {
      beta.stms <- cbind(beta.stms, B.style)
    }
  }

  # factor covariances ----
  if (specObj$rob.stats) {
    if (!requireNamespace("RobStatTM", quietly = TRUE)) {
      stop("Package 'RobStatTM' is required for rob.stats = TRUE. ",
           "Install it with: install.packages('RobStatTM')", call. = FALSE)
    }
    if (kappa(na.exclude(coredata(factor.returns))) < 1e+10) {
      factor.cov <- RobStatTM::covRob(coredata(factor.returns))$cov
    } else {
      cat("Covariance matrix of factor returns is singular.\n")
      factor.cov <- RobStatTM::covRob(coredata(factor.returns))$cov
    }
  } else {
    factor.cov <- cov(coredata(factor.returns), use = "pairwise.complete.obs")

  }

  # return Covariance ----
  if (specObj$addIntercept == FALSE || specObj$model.styleOnly ==TRUE || specObj$model.MSCI) {
    # return covariance estimated by the factor model
    #(here beta corresponds to the exposure of last time period,TP)
    return.cov <-  beta %*% factor.cov %*% t(beta) + resid.cov
    dimnames(return.cov) <- list(names(resid.var) ,names( resid.var))
  } else if ( specObj$addIntercept && specObj$model.styleOnly == FALSE) {
    # return covariance estimated by the factor model
    return.cov <-  beta.stms %*% g.cov %*% t(beta.stms) + resid.cov

  }

  if (!identical(colnames(beta) , colnames(factor.returns))){
    # we need to clean up.. easier to do it on the beta rather than the
    # factor returns ... (factor.cov) follows factor.returns
    colnames(beta) <- sub(pattern = paste0(specObj$exposures.char,collapse = "|"), colnames(beta),replacement = "")

    # the names of the beta matrix have a prefix when we have the flag
    # add intercept F and have an exposure variable that is a character.
    # now that we have cleaned it up we can rearrange the columns
    beta = beta[, match(colnames(factor.returns), colnames(beta))]
  }

  # create list of return values.
  result <- list(beta=beta, factor.returns=factor.returns,
                 residuals=residuals1, r2=r2, factor.cov=factor.cov, g.cov = g.cov,
                 resid.cov=resid.cov, return.cov=return.cov, restriction.mat=restriction.mat,
                 resid.var=resid.var,
                 factor.names=factor.names)

  class(result) <- "ffm"
  return(result)

}

#' @title calcFLAM
#'
#' @description function to calculate fundamental law of active management
#' @importFrom data.table data.table .N
#'
#' @param specObj an object as the output from specFfm function
#' @param modelStats  output of the extractRegressionStats functions.
#' Contains fit statistics of the factor model.
#' @param fitResults output from fitFfmDT
#' @param analysis type character, choice of c("none", "ISM","NEW"). Default = "none".
#' Corresponds to methods used in the analysis of fundamental law of active management.
#' @param targetedVol numeric; the targeted portfolio volatility in the analysis.
#' Default is 0.06.
#' @param ... additional arguments
#'

calcFLAM <- function(specObj, modelStats, fitResults, analysis = c("ISM", "NEW"),
                     targetedVol = 0.06, ...){

  # Due to NSE notes related to data.table in R CMD check
  . = NULL
  # See data.table "Importing data.table" vignette

  # only works for SFM
  analysis <- match.arg(toupper(analysis[1]), choices = c("ISM", "NEW"),
                        several.ok = F)

  # check if returns are lagged.. or I guess exposures are lagged then proceed.
  d_ <- eval(specObj$date.var)
  a_ <- eval(specObj$asset.var)
  r_ <- specObj$yVar # get(r_)
  # r_ is standardized in NEW and not in ISM
  # IC ----
  IC <- NULL
  # this is equation (25) and (26) for single factor models and for multi factor models equations (34) & (35)
  for (e_ in specObj$exposures.num) {

    # we should use pearson?
    ICtemp <- specObj$dataDT[, (IC_ = .(cor(get(e_), get(r_), use = "pair"))) , by = d_]

    data.table::setnames(ICtemp, c(d_, paste0("IC_", e_)))
    data.table::setkeyv(ICtemp, d_)
    if (is.null(IC)) {
      IC <- ICtemp # the first exposure
    } else {
      IC <- IC[ICtemp] # else merge the data
    }
  }
  IC <- data.table::as.xts.data.table(IC)
  # number of assets.... since they can change from month to month we will calculate mean # of assets
  N <- mean(specObj$dataDT[, .N, by = d_]$N, na.rm = TRUE)

  meanIC <- colMeans(IC)
  sigmaIC <- apply(IC, MARGIN = 2, sd)

  IR_GK <- meanIC * sqrt(N)
  IR_inf <- meanIC / sigmaIC
  IR_N <- meanIC / sqrt((1 - meanIC^2 - sigmaIC^2) / N + sigmaIC ^ 2)

  temp <- (specObj$dataDT[get(d_) == max(get(d_)),c(a_,e_), with = F])
  stdExposures <- as.numeric(temp[[e_]])
  names(stdExposures) <- temp[[a_]]

  resid.var <- modelStats$resid.var
  f_rets <- modelStats$factor.returns
  if (analysis == "ISM") {
    mu <- mean(f_rets)
    sig <- sd(f_rets)
  } else {
    mu <- meanIC
    sig <- sigmaIC
  }
  if (analysis == "ISM"){

    condAlpha <- mu * stdExposures
    condOmega <-  sig^2 * (stdExposures %*% t(stdExposures)) + diag(resid.var)
  } else {
    sigmaGarch <- specObj$dataDT[ get(d_) == max(get(d_)), sigmaGarch]

    condAlpha <- mu * diag(sigmaGarch) %*% stdExposures
    names(condAlpha) <- names(stdExposures)
    condOmega <- diag(sigmaGarch) %*%
      (sig^2 * stdExposures %*% t(stdExposures) +
         (1 - mu^2 - sig^2)*diag(rep(1, N))) %*% diag(sigmaGarch)
    #
  }

  kappa <- (t(condAlpha) %*% solve(condOmega) %*% rep(1, N)) / (rep(1, N) %*% solve(condOmega) %*% rep(1, N))
  K <- as.numeric(kappa) * as.matrix(rep(1, N))
  # activeWeights <- te.target * (solve(condOmega) %*% as.matrix(condAlpha)) /
  #   c(sqrt(t(as.matrix(condAlpha)) %*% solve(condOmega) %*% as.matrix(condAlpha)))
  #

  activeWeights <- targetedVol * (solve(condOmega) %*% (as.matrix(condAlpha) - K)) /
    c(sqrt(t(as.matrix(condAlpha)) %*% solve(condOmega) %*% (as.matrix(condAlpha) - K)))
  rownames(activeWeights) <- names(stdExposures)

  return(list(meanIC = meanIC, sigmaIC = sigmaIC, IR_GK = IR_GK, IR_inf = IR_inf,
              IR_N = IR_N, IC = IC, N= N, activeWeights = activeWeights))


}

# private functions ----
#' @importFrom data.table := set .SD
#'
#Calculate Weights For Second Weighted Regression (private function)
calcAssetWeightsForRegression <- function(specObj,
                                          fitResults ,
                                          SecondStepRegression,
                                          resid.scaleType = "STDDEV",
                                          lambda = 0.9,
                                          GARCH.params = list(omega = 0.09,
                                                              alpha = 0.1,
                                                              beta = 0.81),
                                          GARCH.MLE = FALSE) {

  # Due to NSE notes related to data.table in R CMD check
  reg.list <- id <- idx <- resid.var <- residuals <- w <- NULL
  # See data.table "Importing data.table" vignette

  resid.scaleType = toupper(resid.scaleType[1])
  resid.scaleType <- match.arg(arg = resid.scaleType,
                               choices = toupper(c("STDDEV",
                                                   "EWMA", "ROBUSTEWMA",
                                                   "GARCH")),
                               several.ok = F)

  a_ <- eval(specObj$asset.var) # data table requires variable names to be evaluated
  d_ <- eval(specObj$date.var) # name of the date var

  fitResults[, residuals := list(list(data.frame(date = get(d_)[[1]],
                                           id = fitResults$id[[1]],
                                           residuals = residuals(reg.list[[1]])))), by = d_]
  # extract the asset level residuals series and get time series variance or
  # robust stats
  resid.DT <- data.table::rbindlist(l = fitResults$residuals)
  data.table::setkey(resid.DT, id, date)

  resid.DT[, idx := 1:.N, by = id] # this is needed for path dependent calculations

  if (specObj$rob.stats) {
    if (!requireNamespace("robustbase", quietly = TRUE)) {
      stop("Package 'robustbase' is required for rob.stats = TRUE. ",
           "Install it with: install.packages('robustbase')", call. = FALSE)
    }
    resid.DT[, resid.var := robustbase::scaleTau2(residuals)^2, by = id]
  } else {
    resid.DT[, resid.var := var(residuals), by = id]
  }
  #Compute cross-sectional weights using EWMA or GARCH
  if((resid.scaleType != "STDDEV")){

    if(resid.scaleType == "EWMA"){

      #Use sample variance as the initial variance
      data.table::setorderv(resid.DT, c("id", "date"))
      resid.DT[, w := {
        sq <- residuals^2
        init <- resid.var[1L]
        n <- .N
        if (n == 1L) {
          init
        } else {
          c(init,
            as.numeric(stats::filter(
              x = (1 - lambda) * sq[-1L],
              filter = lambda,
              method = "recursive",
              init = init
            )))
        }
      }, by = id]
    } else if (resid.scaleType == "ROBUSTEWMA"){
      # Robust EWMA: rejection threshold a=2.5 per Martin (2005) eq 6.6.
      # Bug fix: original code referenced resid.DT$var (non-existent column);
      # correct column is resid.var.
      data.table::setorderv(resid.DT, c("id", "date"))
      resid.DT[, w := {
        init <- resid.var[1L]
        eps2 <- residuals^2
        n <- .N
        if (n == 1L) {
          init
        } else {
          Reduce(function(w_prev, t) {
            if (abs(residuals[t]) <= 2.5 * sqrt(w_prev)) {
              lambda * w_prev + (1 - lambda) * eps2[t]
            } else {
              w_prev
            }
          }, x = 2L:n, init = init, accumulate = TRUE)
        }
      }, by = id]

    } else if(resid.scaleType == "GARCH") {

      #Compute parameters using MLE
      if(GARCH.MLE){
        if (!requireNamespace("rugarch", quietly = TRUE)) {
          stop("Package 'rugarch' is required for GARCH.MLE = TRUE. ",
               "Install it with: install.packages('rugarch')", call. = FALSE)
        }
        garch.spec = rugarch::ugarchspec(variance.model=list(model="sGARCH", garchOrder=c(1,1)),
                                mean.model=list(armaOrder=c(0,0), include.mean = FALSE),
                                distribution.model="norm")
        resid.DT[, w := rugarch::ugarchfit(garch.spec, data = .SD)@fit$var, .SDcols = c("residuals"), by = id]


      } else {
        # use fixed parameters
        # default values of omega, Alpha and beta are based on Martin and Ding (2017)
        alpha = GARCH.params$alpha
        beta =  GARCH.params$beta
        #Use sample variance as the initial variance
        data.table::setorderv(resid.DT, c("id", "date"))
        resid.DT[, w := {
          omega_i <- (1 - alpha - beta) * resid.var[1L]
          sq_lag <- data.table::shift(residuals^2, n = 1L, fill = resid.var[1L])
          x <- omega_i + alpha * sq_lag
          n <- .N
          if (n == 1L) {
            resid.var[1L]
          } else {
            c(resid.var[1L],
              as.numeric(stats::filter(
                x = x[-1L],
                filter = beta,
                method = "recursive",
                init = resid.var[1L]
              )))
          }
        }, by = id]



      }

    }

    W = resid.DT[, list(W = 1/w), by = c("id", "date")] # id is the asset id
    data.table::setnames(W,old =  c("id","date"), c(a_, d_)) # we need the original name of the asset id

    # when the weighing scheme is not std deviation we need to merge bak by date and id
    # since the weights are time varying rather than jst 1/sample variance
    data.table::setkeyv(W, c(a_, d_)) # so that we can merger it back with the regression data set and
    data.table::setkeyv(SecondStepRegression, c(a_, d_))

  } else {
    W = resid.DT[, list(W = 1/unique(resid.var)), by = id] # id is the asset id
    data.table::setnames(W,old =  "id", a_) # we need the original name of the asset id
    data.table::setkeyv(W, a_) # so that we can merger it back with the regression data set and
    # run weighted regressions
    data.table::setkeyv(SecondStepRegression, a_)

  }


  SecondStepRegression <- SecondStepRegression[W]
  data.table::setkeyv(SecondStepRegression, c(d_, a_))
  return(SecondStepRegression)
}




# S3 methods ----
# function to convert to current class # mido to change to retroFit


#' Function to convert to current class # mido to change to retroFit
#'
#' @param SpecObj an object as the output from specFfm function
#' @param FitObj an object as the output from fitFfmDT function
#' @param RegStatsObj an object as the output from extractRegressionStats function
#' @param ... additional arguments
#' @method convert ffmSpec
#' @export
convert.ffmSpec <- function(SpecObj, FitObj, RegStatsObj, ...) {

  # Due to NSE notes related to data.table in R CMD check
  reg.list = NULL
  # See data.table "Importing data.table" vignette

  asset.names <- names(RegStatsObj$residuals)
  time.periods <- unique(SpecObj$dataDT[[SpecObj$date.var]])
  # R² already extracted in extractRegressionStats — reuse instead of
  # re-calling summary() on every lm object (Phase 2 dedup).
  r2 <- RegStatsObj$r2
  factor.names <- RegStatsObj$factor.names

  ffmObj <- list()
  ffmObj$asset.names <- asset.names
  ffmObj$r2 <- r2
  ffmObj$factor.names <- factor.names
  # SpecObj
  ffmObj$asset.var <- SpecObj$asset.var
  ffmObj$date.var <- SpecObj$date.var
  ffmObj$ret.var <- SpecObj$ret.var
  ffmObj$exposure.vars <- SpecObj$exposure.vars
  ffmObj$exposures.num <- SpecObj$exposures.num
  ffmObj$exposures.char <- SpecObj$exposures.char
  # Store ordered factor levels for each char exposure. Used by predict.ffm
  # to reconstruct model.matrix dummy columns from user-supplied newdata.
  if (length(SpecObj$exposures.char)) {
    ffmObj$char_levels <- lapply(
      SpecObj$exposures.char,
      function(v) levels(SpecObj$dataDT[[v]])
    )
    names(ffmObj$char_levels) <- SpecObj$exposures.char
  } else {
    ffmObj$char_levels <- list()
  }
  ffmObj$data <- data.table::copy(SpecObj$dataDT)
  data.table::setkeyv(ffmObj$data, c(SpecObj$date.var, SpecObj$asset.var))  # to match the order
  # expected in reporting functions
  ffmObj$data = data.frame(ffmObj$data)

  # fit
  ffmObj$time.periods <- time.periods
  ffmObj$factor.fit <- FitObj$reg.listDT$reg.list
  names(ffmObj$factor.fit) <- time.periods

  # regStats
  ffmObj$beta <- RegStatsObj$beta
  ffmObj$factor.returns <- RegStatsObj$factor.returns
  ffmObj$restriction.mat <- RegStatsObj$restriction.mat
  ffmObj$factor.cov <- RegStatsObj$factor.cov
  ffmObj$resid.var <- RegStatsObj$resid.var
  ffmObj$residuals <- RegStatsObj$residuals
  ffmObj$g.cov <- RegStatsObj$g.cov
  ffmObj$return.cov <- RegStatsObj$return.cov
  ffmObj$resid.cov <- RegStatsObj$resid.cov
  ffmObj$model.MSCI <- isTRUE(SpecObj$model.MSCI)

  # clean up

class(ffmObj) <- "ffm"

  return(ffmObj)

}

#' @title convert
#' @description function to convert the new ffm spec object to ffm object to make it
#' easier in plotting and reporting
#' @param SpecObj an object as the output from specFfm function
#' @param FitObj an object as the output from fitFfmDT function
#' @param RegStatsObj an object as the output from extractRegressionStats function
#' @param ... additional arguments
#' @export
#'
convert <- function(SpecObj, FitObj, RegStatsObj, ...) {
  UseMethod("convert")
}



#' @method print ffmSpec
#' @export
print.ffmSpec <- function(x, ...){



  a_ <- x$asset.var
  r_ <- x$ret.var
  d_ <- x$date.var
  cat(sprintf("A fundamental factor model specification object.\n "))
  cat(sprintf("The data table is %i rows by %i columns.\n", dim(x$dataDT)[1],dim(x$dataDT)[2]))
  cat(sprintf("The asset identifier is: %s . There are %i unique assets.\n", a_, length(unique(x$dataDT[[a_]]))))
  cat(sprintf("The return variable is in this column: %s \n", r_))

  if (x$standardizedReturns & !x$residualizedReturns)
    cat(sprintf("Returns have been standardized but not residualized\n"))
  if (!x$standardizedReturns &x$residualizedReturns)
    cat(sprintf("Returns have been residualized but not standardized\n "))
  if (x$standardizedReturns &x$residualizedReturns)
    cat(sprintf("Returns have been residualized and standardized\n "))
  cat(sprintf("The return variable that is fit in the model is: %s.\n",x$yVar))

  cat(sprintf("The date variable is in this columns: %s.  The data spans from %s to %s.\n", d_,
             x$dataDT[[d_]][1], x$dataDT[[d_]][nrow(x$dataDT)]))

}
