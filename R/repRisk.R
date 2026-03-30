#' @title Decompose portfolio risk into individual factor contributions and provide tabular report
#'
#' @description Compute the factor contributions to standard deviation (SD), Value-at-Risk (VaR),
#' Expected Tail Loss or Expected Shortfall (ES) of the return of individual asset within a portfolio
#' return of a portfolio based on Euler's theorem, given the fitted factor model.
#'
#' @importFrom lattice barchart
#' @importFrom methods is
#'
#' @param object fit object of class \code{tsfm}, or \code{ffm}.
#' @param p tail probability for calculation. Default is 0.05.
#' @param weights a vector of weights of the assets in the portfolio, names of
#' the vector should match with asset names. Default is NULL, in which case an
#' equal weights will be used.
#' @param risk one of 'Sd' (standard deviation), 'VaR' (Value-at-Risk) or 'ES' (Expected Tail
#' Loss or Expected Shortfall for calculating risk decompositon. Default is 'Sd'
#' @param decomp one of 'FMCR' (factor marginal contribution to risk),
#' 'FCR' 'factor contribution to risk' or 'FPCR' (factor percent contribution to risk).
#' @param digits digits of number in the resulting table. Default is NULL, in which case digtis = 3 will be
#' used for decomp = ( 'FMCR', 'FCR'), digits = 1 will be used for decomp = 'FPCR'. Used only when
#' isPrint = 'TRUE'
#' @param nrowPrint a numerical value deciding number of assets/portfolio in result vector/table to print
#' or plot
#' @param type one of "np" (non-parametric) or "normal" for calculating VaR & Es.
#' Default is "np".
#' @param sliceby one of 'factor' (slice/condition by factor) or 'asset' (slice/condition by asset) or 'riskType'
#' Used only when isPlot = 'TRUE'
#' @param invert a logical variable to change VaR/ES to positive number, default
#' is False and will return positive values.
#' @param layout layout is a numeric vector of length 2 or 3 giving the number of columns, rows, and pages (optional) in a multipanel display.
#' @param stripText.cex a number indicating the amount by which strip text in the plot(s) should be scaled relative to the default. 1=default, 1.5 is 50\% larger, 0.5 is 50\% smaller, etc.
#' @param axis.cex a number indicating the amount by which axis in the plot(s) should be scaled relative to the default. 1=default, 1.5 is 50\% larger, 0.5 is 50\% smaller, etc.
#' @param portfolio.only logical variable to choose if to calculate portfolio only decomposition, in which case multiple risk measures are
#' allowed.
#' @param isPlot logical variable to generate plot or not.
#' @param isPrint logical variable to print numeric output or not.
#' @param use an optional character string giving a method for computing factor
#' covariances in the presence of missing values. This must be (an
#' abbreviation of) one of the strings "everything", "all.obs",
#' "complete.obs", "na.or.complete", or "pairwise.complete.obs". Default is
#' "pairwise.complete.obs".
#' @param ... other optional arguments passed to \code{\link[stats]{quantile}} and
#' optional arguments passed to \code{\link[stats]{cov}}
#'
#' @return A table containing
#' \item{decomp = 'FMCR'}{(N + 1) * (K + 1) matrix of marginal contributions to risk of portfolio
#' return as well assets return, with first row of values for the portfolio and the remaining rows for
#' the assets in the portfolio, with  (K + 1) columns containing values for the K risk factors and the
#' residual respectively}
#' \item{decomp = 'FCR'}{(N + 1) * (K + 2) matrix of component contributions to risk of portfolio
#' return as well assets return, with first row of values for the portfolio and the remaining rows for
#' the assets in the portfolio, with  first column containing portfolio and asset risk values and remaining
#' (K + 1) columns containing values for the K risk factors and the residual respectively}
#' \item{decomp = 'FPCR'}{(N + 1) * (K + 1) matrix of percentage component contributions to risk
#' of portfolio return as well assets return, with first row of values for the portfolio and the remaining rows for
#' the assets in the portfolio, with  (K + 1) columns containing values for the K risk factors and the
#' residual respectively}
#' Where, K is the number of factors, N is the number of assets.
#'
#' @author Douglas Martin, Lingjie Yi
#'
#'
#' @seealso \code{\link{fitTsfm}}, \code{\link{fitFfm}}
#' for the different factor model fitting functions.
#'
#'
#' @examples
#' # Time Series Factor Model
#'
#' data(managers, package = 'PerformanceAnalytics')
#'
#' fit.macro <- fitTsfm(asset.names = colnames(managers[,(1:6)]),
#'                      factor.names = colnames(managers[,(7:9)]),
#'                      rf.name = colnames(managers[,10]),
#'                      data = managers)
#'
#' report <- repRisk(fit.macro, risk = "ES", decomp = 'FPCR',
#'                   nrowPrint = 10)
#' report
#'
#' # plot
#' repRisk(fit.macro, risk = "ES", decomp = 'FPCR', isPrint = FALSE,
#'         isPlot = TRUE)
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
#' exposure.vars = c("SECTOR","ROE","BP","PM12M1M","SIZE","ANNVOL1M", "EP")
#' fit.cross <- fitFfm(data = dat,
#'                     exposure.vars = exposure.vars,
#'                     date.var = "DATE",
#'                     ret.var = "RETURN",
#'                     asset.var = "TICKER",
#'                     fit.method="WLS",
#'                     z.score = "crossSection")
#'
#' repRisk(fit.cross, risk = "Sd", decomp = 'FCR', nrowPrint = 10,
#'         digits = 4)
#'
#' # get the factor contributions of risk
#' repRisk(fit.cross, wtsStocks145GmvLo, risk = "Sd", decomp = 'FPCR',
#'         nrowPrint = 10)
#'
#' # portfolio only decomposition
#' repRisk(fit.cross, wtsStocks145GmvLo, risk = c("VaR", "ES"), decomp = 'FPCR',
#'         portfolio.only = TRUE)
#'
#' # plot
#' repRisk(fit.cross, wtsStocks145GmvLo, risk = "Sd", decomp = 'FPCR',
#'         isPrint = FALSE, nrowPrint = 15, isPlot = TRUE, layout = c(4,2))
#' @export


repRisk <- function(object, ...) {
  if (inherits(object, "list")) {
    for (i in seq_along(object)) {
      if (!inherits(object[[i]], c("tsfm", "ffm")))
        stop("Invalid argument: Object should be of class 'tsfm' or 'ffm'.")
    }
    UseMethod("repRisk", object[[1]])
  } else {
    if (!inherits(object, c("tsfm", "ffm")))
      stop("Invalid argument: Object should be of class 'tsfm' or 'ffm'.")
    UseMethod("repRisk")
  }
}


# Slot-name lookup: maps risk type to decomposition slot names
.risk_slots <- list(
  Sd  = list(port_risk = "portSd",  asset_risk = "Sd.fm",
             m = "mSd",  c = "cSd",  pc = "pcSd"),
  VaR = list(port_risk = "portVaR", asset_risk = "VaR.fm",
             m = "mVaR", c = "cVaR", pc = "pcVaR"),
  ES  = list(port_risk = "portES",  asset_risk = "ES.fm",
             m = "mES",  c = "cES",  pc = "pcES")
)


#' @rdname repRisk
#' @method repRisk tsfm
#' @importFrom utils head
#' @export

repRisk.tsfm <- function(object, weights = NULL, risk = c("Sd", "VaR", "ES"),
                         decomp = c("FPCR", "FCR", "FMCR"), digits = NULL,
                         invert = FALSE, nrowPrint = 20, p = 0.05,
                         type = c("np", "normal"),
                         use = "pairwise.complete.obs",
                         sliceby = c("factor", "asset"), isPrint = TRUE,
                         isPlot = FALSE, layout = NULL, stripText.cex = 1,
                         axis.cex = 1, portfolio.only = FALSE, ...) {
  .repRisk_impl(object, weights = weights, risk = risk, decomp = decomp,
                digits = digits, invert = invert, nrowPrint = nrowPrint,
                p = p, type = type, sliceby = sliceby, isPrint = isPrint,
                isPlot = isPlot, layout = layout, stripText.cex = stripText.cex,
                axis.cex = axis.cex, portfolio.only = portfolio.only, ...)
}


#' @rdname repRisk
#' @method repRisk ffm
#' @importFrom utils head
#' @export

repRisk.ffm <- function(object, weights = NULL, risk = c("Sd", "VaR", "ES"),
                        decomp = c("FMCR", "FCR", "FPCR"), digits = NULL,
                        invert = FALSE, nrowPrint = 20, p = 0.05,
                        type = c("np", "normal"),
                        sliceby = c("factor", "asset", "riskType"),
                        isPrint = TRUE, isPlot = FALSE, layout = NULL,
                        stripText.cex = 1, axis.cex = 1,
                        portfolio.only = FALSE, ...) {
  # Handle list-of-objects (multi-portfolio) input
  if (inherits(object, "list")) {
    if (length(weights) != length(object))
      stop("Error: Number of portfolios and weights do not match")

    output.list <- lapply(seq_along(object), function(X) {
      .repRisk_impl(object[[X]], weights = weights[[X]], risk = risk,
                    decomp = decomp, digits = digits, invert = invert,
                    nrowPrint = nrowPrint, p = p, type = type,
                    sliceby = sliceby, isPrint = isPrint, isPlot = FALSE,
                    layout = layout, stripText.cex = stripText.cex,
                    axis.cex = axis.cex, portfolio.only = portfolio.only, ...)
    })

    if (isPlot && portfolio.only)
      .plot_multi_portfolio(output.list, object, risk, decomp, layout,
                           axis.cex, stripText.cex)

    return(output.list)
  }

  # Single-object path
  .repRisk_impl(object, weights = weights, risk = risk, decomp = decomp,
                digits = digits, invert = invert, nrowPrint = nrowPrint,
                p = p, type = type, sliceby = sliceby, isPrint = isPrint,
                isPlot = isPlot, layout = layout, stripText.cex = stripText.cex,
                axis.cex = axis.cex, portfolio.only = portfolio.only, ...)
}


# ---------------------------------------------------------------------------
# Shared implementation for single-object repRisk
# ---------------------------------------------------------------------------
.repRisk_impl <- function(object, weights, risk, decomp, digits, invert,
                          nrowPrint, p, type, sliceby, isPrint, isPlot,
                          layout, stripText.cex, axis.cex, portfolio.only,
                          ...) {
  type <- type[1]
  sliceby <- sliceby[1]
  decomp <- decomp[1]

  if (!(type %in% c("np", "normal")))
    stop("Invalid args: type must be 'np' or 'normal' ")
  if (!all(risk %in% c("Sd", "VaR", "ES")))
    stop("Invalid args: risk must be 'Sd', 'VaR' or 'ES' ")
  if (!(decomp %in% c("FMCR", "FCR", "FPCR")))
    stop("Invalid args: decomp must be 'FMCR', 'FCR' or 'FPCR' ")

  if (!portfolio.only) risk <- risk[1]

  # --- Single-risk path (portfolio + asset decomposition) ---
  if (!portfolio.only) {
    slots <- .risk_slots[[risk]]
    port <- riskDecomp(object, risk = risk, weights = weights,
                       p = p, type = type, invert = invert, ...)
    asset <- riskDecomp(object, risk = risk, portDecomp = FALSE,
                        p = p, type = type, invert = invert, ...)

    result <- .assemble_result(port, asset, slots, decomp)

    if (isPlot)
      .plot_single_risk(result, decomp, risk, nrowPrint, sliceby,
                        layout, axis.cex, stripText.cex)

    if (isPrint) {
      if (is.null(digits)) digits <- if (decomp == "FPCR") 1 else 3
      result <- round(head(result, nrowPrint), digits)
      output <- list(decomp = result)
      names(output) <- paste0(risk, decomp)
      return(output)
    }
    return(invisible(NULL))
  }

  # --- Portfolio-only path (multi-risk allowed) ---
  decomps <- lapply(c("Sd", "VaR", "ES"), function(r) {
    riskDecomp(object, risk = r, weights = weights,
               p = p, type = type, invert = invert, ...)
  })
  names(decomps) <- c("Sd", "VaR", "ES")

  result <- .assemble_portfolio_only(decomps, risk, decomp)

  if (isPrint) {
    if (is.null(digits)) digits <- if (decomp == "FPCR") 1 else 3
    result <- round(result, digits)
    Type <- if (type == "normal") "Parametric Normal" else "Non-Parametric"
    output <- list(decomp = result)
    names(output) <- paste("Portfolio", decomp, Type)
  } else {
    output <- list(decomp = result)
  }

  if (isPlot)
    .plot_portfolio_only(result, risk, decomp, sliceby,
                         layout, axis.cex, stripText.cex)

  return(output)
}


# ---------------------------------------------------------------------------
# Result assembly helpers
# ---------------------------------------------------------------------------
.assemble_result <- function(port, asset, slots, decomp) {
  if (decomp == "FMCR") {
    result <- rbind(port[[slots$m]], asset[[slots$m]])
    rownames(result)[1] <- "Portfolio"
  } else if (decomp == "FCR") {
    rm_col <- c(port[[slots$port_risk]], asset[[slots$asset_risk]])
    result <- cbind(RM = rm_col, rbind(port[[slots$c]], asset[[slots$c]]))
    rownames(result)[1] <- "Portfolio"
  } else {
    result <- rbind(port[[slots$pc]], asset[[slots$pc]])
    rownames(result)[1] <- "Portfolio"
    result <- cbind(Total = rowSums(result), result)
  }
  result
}

.assemble_portfolio_only <- function(decomps, risk, decomp) {
  if (decomp == "FMCR") {
    rows <- lapply(c("Sd", "VaR", "ES"), function(r)
      decomps[[r]][[.risk_slots[[r]]$m]])
    result <- do.call(rbind, rows)
    rownames(result) <- c("Sd", "VaR", "ES")
    result <- result[risk, , drop = FALSE]
  } else if (decomp == "FCR") {
    rm_vals <- vapply(c("Sd", "VaR", "ES"), function(r)
      decomps[[r]][[.risk_slots[[r]]$port_risk]], numeric(1))
    names(rm_vals) <- c("Sd", "VaR", "ES")
    rows <- lapply(c("Sd", "VaR", "ES"), function(r)
      decomps[[r]][[.risk_slots[[r]]$c]])
    result <- do.call(rbind, rows)
    rownames(result) <- c("Sd", "VaR", "ES")
    result <- cbind(RM = rm_vals, result)
    result <- result[risk, , drop = FALSE]
  } else {
    rows <- lapply(c("Sd", "VaR", "ES"), function(r)
      decomps[[r]][[.risk_slots[[r]]$pc]])
    result <- do.call(rbind, rows)
    rownames(result) <- c("Sd", "VaR", "ES")
    result <- cbind(Total = rowSums(result), result)
    result <- result[risk, , drop = FALSE]
  }
  result
}


# ---------------------------------------------------------------------------
# Plotting helpers
# ---------------------------------------------------------------------------
.auto_layout <- function(n) {
  l <- 3
  while (n %% l == 1) l <- l + 1
  c(l, 1)
}

.plot_single_risk <- function(result, decomp, risk, nrowPrint, sliceby,
                              layout, axis.cex, stripText.cex) {
  # Strip RM/Total column for plotting
  if (decomp %in% c("FCR", "FPCR")) result <- result[, -1, drop = FALSE]
  result <- head(result, nrowPrint)

  if (sliceby == "asset") result <- t(result)
  if (is.null(layout)) layout <- .auto_layout(ncol(result))

  print(barchart(result[rev(rownames(result)), , drop = FALSE], groups = FALSE,
                 main = paste(decomp, "of", risk), layout = layout,
                 scales = list(y = list(cex = axis.cex),
                               x = list(cex = axis.cex)),
                 par.strip.text = list(col = "black", cex = stripText.cex),
                 ylab = "", xlab = "", as.table = TRUE))
}

.plot_portfolio_only <- function(result, risk, decomp, sliceby,
                                layout, axis.cex, stripText.cex) {
  if (is.matrix(result) && nrow(result) > 1) {
    # Multi-risk matrix: strip RM/Total, reshape
    plot_mat <- if (decomp %in% c("FCR", "FPCR")) result[, -1, drop = FALSE]
                else result
    newdata <- as.data.frame(as.table(plot_mat))
    colnames(newdata) <- c("Var1", "Var2", "value")
    if (sliceby == "riskType") {
      print(barchart(value ~ Var2 | Var1, data = newdata, stack = TRUE,
                     origin = 0,
                     main = list(paste("Portfolio", decomp, "Comparison"),
                                 cex = axis.cex),
                     layout = layout,
                     scales = list(y = list(cex = axis.cex),
                                   x = list(cex = axis.cex, rot = 90)),
                     par.strip.text = list(col = "black", font = 2,
                                           cex = stripText.cex),
                     ylab = "", xlab = "", as.table = TRUE))
    } else {
      print(barchart(value ~ Var1 | Var2, data = newdata, stack = TRUE,
                     origin = 0,
                     main = list(paste("Portfolio", decomp, "Comparison"),
                                 cex = axis.cex),
                     layout = layout,
                     scales = list(y = list(cex = axis.cex),
                                   x = list(cex = axis.cex)),
                     par.strip.text = list(col = "black", font = 2,
                                           cex = stripText.cex),
                     ylab = "", xlab = "", as.table = TRUE))
    }
  } else {
    # Single-risk vector: simple barchart
    if (is.matrix(result)) result <- result[1, ]
    plot_result <- result[names(result) != "RM" & names(result) != "Total"]
    result.mat <- matrix(plot_result, ncol = 1)
    rownames(result.mat) <- names(plot_result)
    colnames(result.mat) <- risk[1]
    print(barchart(result.mat, stack = TRUE, groups = FALSE,
                   main = list(paste("Portfolio", risk[1], "Decomposition-", decomp),
                               cex = axis.cex),
                   layout = layout, horizontal = FALSE,
                   scales = list(y = list(cex = axis.cex),
                                 x = list(cex = axis.cex)),
                   par.strip.text = list(col = "black", font = 2,
                                         cex = stripText.cex),
                   ylab = "", xlab = "", as.table = TRUE))
  }
}

.plot_multi_portfolio <- function(output.list, object, risk, decomp, layout,
                                 axis.cex, stripText.cex) {
  decomp <- decomp[1]
  if (length(risk) > 1) {
    # Multi-risk: stack results from all portfolios
    result <- unlist(output.list, recursive = FALSE, use.names = FALSE)
    result.mat <- matrix(unlist(result), ncol = length(result))
    factor_nms <- colnames(result[[1]])
    if (is.null(factor_nms))
      factor_nms <- paste0("F", seq_len(nrow(result.mat) / length(risk)))
    rownames(result.mat) <- rep(factor_nms, times = length(risk))
    colnames(result.mat) <- paste0("P", seq_along(object))
    # Remove portfolio-level total rows
    result.mat <- result.mat[-seq_len(length(risk)), , drop = FALSE]

    newdata <- as.data.frame(as.table(result.mat))
    colnames(newdata) <- c("factor", "portfolio", "value")
    n_per_risk <- as.integer(nrow(result.mat) / length(risk))
    newdata$risk <- factor(rep(rep(risk, each = n_per_risk),
                               times = ncol(result.mat)))

    print(barchart(value ~ factor | portfolio * risk, data = newdata,
                   stack = TRUE, origin = 0,
                   main = list(paste("Portfolio Risk Comparison-", decomp),
                               cex = axis.cex),
                   layout = layout,
                   scales = list(y = list(cex = axis.cex),
                                 x = list(cex = axis.cex)),
                   par.strip.text = list(col = "black", font = 2,
                                         cex = stripText.cex),
                   ylab = "", xlab = "", as.table = TRUE))
  } else {
    # Single-risk: simple comparison across portfolios
    result.mat <- matrix(unlist(output.list), ncol = length(output.list))
    colnames(result.mat) <- paste("Portfolio", seq_along(object))
    rownames(result.mat) <- names(output.list[[1]][[1]])
    # Remove Total row
    result.mat <- result.mat[-1, , drop = FALSE]

    newdata <- as.data.frame(as.table(result.mat))
    colnames(newdata) <- c("factor", "portfolio", "value")

    print(barchart(value ~ factor | portfolio, data = newdata,
                   stack = TRUE, origin = 0,
                   main = list(paste("Portfolio Risk Comparison-", risk, decomp),
                               cex = axis.cex),
                   layout = layout,
                   scales = list(y = list(cex = axis.cex),
                                 x = list(cex = axis.cex)),
                   par.strip.text = list(col = "black", font = 2,
                                         cex = stripText.cex),
                   ylab = "", xlab = "", as.table = TRUE))
  }
}
