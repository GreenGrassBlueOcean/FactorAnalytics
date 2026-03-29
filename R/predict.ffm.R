#' @title Predicts asset returns based on a fitted fundamental factor model
#' 
#' @description S3 \code{predict} method for object of class \code{ffm}.
#' 
#' @details The estimated factor returns and potentially new factor exposures 
#' are used to predict the asset returns during all dates from the fitted 
#' \code{ffm} object. For predictions based on estimated factor returns from a 
#' specific period use the \code{pred.date} argument.
#' 
#' @importFrom PerformanceAnalytics checkData
#' 
#' @param object an object of class \code{ffm} produced by \code{fitFfm}.
#' @param newdata data.frame containing the same \code{exposure.vars} used in
#' the fitted \code{ffm} object. For models with categorical exposures (sector
#' or MSCI), \code{newdata} may contain either the original factor/character
#' columns (e.g., \code{SECTOR}) or the pre-expanded model.matrix columns
#' (\code{V1}, \code{V2}, ...). If original columns are supplied, they are
#' automatically expanded using the restriction matrix and factor levels stored
#' at fit time. If omitted, the predictions are based on the data used for the
#' fit.
#' @param pred.date character; unique date used to base the predictions. Should 
#' be coercible to class \code{Date} and match one of the dates in the data used
#' in the fiited \code{object}.
#' @param ... optional arguments passed to \code{predict.lm} or 
#' \code{\link[robustbase]{predict.lmrob}}.
#' 
#' @return 
#' \code{predict.ffm} produces a N x T matrix of predicted asset returns, where 
#' T is the number of time periods and N is the number of assets. T=1 if 
#' \code{pred.date} is specified.
#' 
#' @author Sangeetha Srinivasan
#' 
#' @seealso \code{\link{fitFfm}}, \code{\link{summary.ffm}}, 
#' \code{\link[stats]{predict.lm}}, \code{\link[robustbase]{predict.lmrob}}
#' 
#' @examples
#' 
#' # Load fundamental and return data
#'  data("factorDataSetDjia5Yrs")
#' 
#' # fit a fundamental factor model
#' fit <- fitFfm(data = factorDataSetDjia5Yrs, 
#'               asset.var = "TICKER", 
#'               ret.var = "RETURN", 
#'               date.var = "DATE", 
#'               exposure.vars = c("P2B", "MKTCAP"))
#'               
#' # generate random data
#' newdata <- as.data.frame(unique(factorDataSetDjia5Yrs$TICKER))
#' newdata$P2B <- rnorm(nrow(newdata))
#' newdata$MKTCAP <- rnorm(nrow(newdata))
#' pred.fund <- predict(fit, newdata)
#' 
#' @method predict ffm
#' @export
#' 

predict.ffm <- function(object, newdata=NULL, pred.date=NULL, ...){
  
  if (!is.null(pred.date) && !(pred.date %in% names(object$factor.fit))) {
    stop("Invalid args: pred.date must be a character string that matches one 
         of the dates used in the fit")
  }
  
  if (is.null(newdata)) {
    sapply(object$factor.fit, predict, ...)
  } else {
    newdata <- PerformanceAnalytics::checkData(newdata, method="data.frame")
    # For sector/MSCI models, the internal lm objects use model.matrix-expanded
    # column names (V1, V2, ...) rather than the original exposure names (SECTOR).
    # Auto-expand newdata if it has original columns but not V columns.
    if (length(object$exposures.char) > 0L && !is.null(object$restriction.mat)) {
      coef_names <- names(coef(object$factor.fit[[1L]]))
      has_model_cols <- all(coef_names %in% names(newdata))
      has_original_cols <- all(object$exposures.char %in% names(newdata))
      if (!has_model_cols && has_original_cols) {
        newdata <- expand_newdata_ffm(object, newdata)
      }
    }
    if (is.null(pred.date)) {
      sapply(object$factor.fit, predict, newdata = newdata, ...)
    } else {
      as.matrix(predict(object$factor.fit[[pred.date]], newdata = newdata, ...))
    }
  }
}

# Expand newdata with original exposure columns into the model.matrix
# column format (V1..Vk + numeric) used internally by fitFfmDT.
# Only needed for sector/MSCI models (char exposures present).
expand_newdata_ffm <- function(object, newdata) {
  exposures_char <- object$exposures.char
  exposures_num <- object$exposures.num
  char_levels <- object$char_levels
  R_mat <- object$restriction.mat

  if (length(exposures_char) == 0L || is.null(R_mat)) {
    return(newdata)
  }

  # Backward compatibility: ffm objects saved before char_levels was added
  if (is.null(char_levels)) {
    message("This ffm object was fitted before char_levels was stored. ",
            "Recovering factor levels from fit$data. ",
            "Consider re-fitting for guaranteed level ordering.")
    char_levels <- lapply(
      exposures_char,
      function(v) levels(factor(object$data[[v]]))
    )
    names(char_levels) <- exposures_char
  }

  # Validate: all char exposures must be present in newdata
  missing_vars <- setdiff(exposures_char, names(newdata))
  if (length(missing_vars)) {
    stop("newdata is missing categorical exposure variable(s): ",
         paste(missing_vars, collapse = ", "), call. = FALSE)
  }

  # Convert char columns to factors with the same levels used during fitting
  for (v in exposures_char) {
    orig_vals <- newdata[[v]]
    newdata[[v]] <- factor(newdata[[v]], levels = char_levels[[v]])
    unknown <- which(is.na(newdata[[v]]) & !is.na(orig_vals))
    if (length(unknown)) {
      stop("newdata contains unknown levels for '", v, "': ",
           paste(unique(orig_vals[unknown]), collapse = ", "),
           ". Levels must be one of: ",
           paste(char_levels[[v]], collapse = ", "), call. = FALSE)
    }
  }

  # Build model.matrix for each char exposure (no intercept = one dummy per level).
  # Subset to only char columns before model.matrix so NAs in numeric columns
  # cannot trigger row-dropping via na.action.
  if (length(exposures_char) == 1L) {
    mm <- model.matrix(~ . - 1,
                       data = newdata[, exposures_char, drop = FALSE])
    beta_star <- cbind(Market = rep(1, nrow(newdata)), mm)
  } else {
    mm1 <- model.matrix(~ . - 1,
                        data = newdata[, exposures_char[1], drop = FALSE])
    mm2 <- model.matrix(~ . - 1,
                        data = newdata[, exposures_char[2], drop = FALSE])
    beta_star <- cbind(Market = rep(1, nrow(newdata)), mm1, mm2)
  }

  # Apply restriction matrix: B.mod = beta_star %*% R_mat
  B_mod <- beta_star %*% R_mat
  colnames(B_mod) <- paste0("V", seq_len(ncol(B_mod)))

  # Combine with numeric exposures
  result <- as.data.frame(B_mod)
  for (v in exposures_num) {
    if (!(v %in% names(newdata))) {
      stop("newdata is missing numeric exposure variable: ", v, call. = FALSE)
    }
    result[[v]] <- newdata[[v]]
  }

  result
}
