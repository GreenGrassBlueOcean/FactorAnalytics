# Bug Report: `fmCov()` and risk decomposition functions fail on FFM fits with character exposures

**Package:** FactorAnalytics (v2.4.2, GreenGrassBlueOcean fork)
**Severity:** High — blocks all covariance and risk decomposition for sector/industry models
**Discovered during:** Phase 0 test infrastructure build

## Summary

`fmCov.ffm()`, `fmSdDecomp.ffm()`, `fmVaRDecomp.ffm()`, and `fmEsDecomp.ffm()` all
crash with `"undefined columns selected"` when the fitted FFM model was built with
character (categorical) exposures — e.g., SECTOR or COUNTRY models. The bug does
**not** affect style-only models (numeric exposures only) or TSFM models.

## Root Cause

All four functions contain a line like:

```r
factor <- as.matrix(object$data[, object$factor.names])
```

This assumes `object$factor.names` are literal column names in `object$data`.

For **style-only** FFM fits, `factor.names` contains the numeric exposure column names
(e.g., `c("P2B", "EV2S")`), which are actual columns in the data frame. This works fine.

For **sector/industry** FFM fits, `factor.names` contains the **factor level names**
derived from the categorical variable — e.g.,
`c("Market", "P2B", "EV2S", "COSTAP", "ENERGY", "FINANCL", ...)`.
These are the names of the estimated coefficients / factor returns, **not** column names
in the original data. The original data has a single column called `"SECTOR"` (the
categorical variable), not one column per sector level.

## Where `factor.names` Gets Set (in `fitFfmDT.R`)

When a character exposure is present, `factor.names` is built from factor levels:

```r
# fitFfmDT.R, line 490 (sector + intercept model)
factor.names <- c("Market",
                   paste(levels(ffMSpecObj$dataDT[[ffMSpecObj$exposures.char]]), sep=" "),
                   ffMSpecObj$exposures.num)

# fitFfmDT.R, line 810 (no intercept, with char exposure)
factor.names <- c(specObj$exposures.num,
                   paste(levels(specObj$dataDT[, specObj$exposures.char, with = F][[1]]), sep=""))

# fitFfmDT.R, line 845 (intercept, mixed model)
factor.names <- c("Market", specObj$exposures.num,
                   paste(levels(specObj$dataDT[, specObj$exposures.char, with = F][[1]]), sep=""))

# fitFfmDT.R, line 927 (MSCI model)
factor.names <- c("Market", specObj$exposures.num, paste(lvl, sep=""))
```

These level names (`"COSTAP"`, `"ENERGY"`, etc.) are never column names in the data
frame. They only exist as column names in `object$beta`, `object$factor.returns`, and
`object$factor.cov`.

## Where `object$data` Gets Set (in `fitFfmDT.R`)

```r
# fitFfmDT.R, line 1264
ffmObj$data <- data.table::copy(SpecObj$dataDT)
# ...
ffmObj$data = data.frame(ffmObj$data)
```

The stored data frame has columns like: `date`, `asset`, `return`, `SECTOR`, `P2B`,
`EV2S`, `mktcap` — the **original input columns**, not one-hot encoded dummies.

## Affected Functions

| Function | File | Failing line | Error |
|---|---|---|---|
| `fmCov.ffm()` | `R/fmCov.R:132` | `as.matrix(object$data[, object$factor.names])` | `undefined columns selected` |
| `fmSdDecomp.ffm()` | `R/fmSdDecomp.R:109` | `as.matrix(object$data[, object$factor.names])` | `undefined columns selected` |
| `fmVaRDecomp.ffm()` | `R/fmVaRDecomp.R:115` | `object$data[, object$factor.names]` | `undefined columns selected` |
| `fmEsDecomp.ffm()` | `R/fmEsDecomp.R:113` | `object$data[, object$factor.names]` | `undefined columns selected` |

Downstream callers that call these internally also break:
- `plot.ffm()` (plots 10, 11, 12, 13 — correlation/decomposition heatmaps)
- `portSdDecomp()`, `portVaRDecomp()`, `portEsDecomp()` — all portfolio-level risk decomposition

## What These Functions Are Trying To Do

The failing line tries to extract factor return time series from `object$data` to either:
1. Recompute the factor covariance matrix (`fmCov`) when `object$factor.cov` is `NULL`
2. Get factor returns for Monte Carlo or historical simulation in risk decomposition

But for FFM models, factor returns are **not stored as columns in the input data**.
They are **estimated** by the cross-sectional regression at each time period and stored
in `object$factor.returns` (an xts matrix with `factor.names` as column names).

## Why Style-Only Models Work

For a style-only FFM (e.g., `exposure.vars = c("P2B", "EV2S")` with no character
exposures):

- `factor.names = c("P2B", "EV2S")` (or `c("Alpha", "P2B", "EV2S")` with intercept)
- `object$data` has columns `P2B` and `EV2S` (the raw numeric exposures)
- The column subsetting succeeds **by coincidence**: the exposure values (which vary by
  asset and date) happen to have the same column names as the factor returns, even though
  they are conceptually different things (exposures ≠ factor returns)

This means even the style-only path is semantically wrong — it extracts **exposure values**
rather than **factor returns** — but produces a correct result only when
`object$factor.cov` is already non-NULL (which it always is for `fitFfm`/`fitFfmDT`
output), because the extracted values are never actually used in that case: the
pre-computed `factor.cov` short-circuits the `cov()` call.

## The `object$factor.cov` Short-Circuit

Looking at `fmCov.ffm()` more carefully:

```r
fmCov.ffm <- function(object, use="pairwise.complete.obs", ...) {
  beta <- as.matrix(object$beta)
  beta[is.na(beta)] <- 0
  sig2.e = object$resid.var
  factor <- as.matrix(object$data[, object$factor.names])  # <-- FAILS HERE
  factor.cov = object$factor.cov
  if (is.null(factor.cov)) {
    factor.cov = cov(factor, use=use, ...)    # only uses `factor` if factor.cov is NULL
  } else {
    identical(dim(factor.cov), ...)            # no-op comparison, result discarded
  }
  D.e = diag(sig2.e)
  cov.fm = beta %*% factor.cov %*% t(beta) + D.e
  return(cov.fm)
}
```

Key observations:
1. The `factor` variable is **only used** when `object$factor.cov` is `NULL`
2. For `fitFfm`/`fitFfmDT` output, `factor.cov` is **always** pre-computed and non-NULL
3. The crash happens **before** the NULL check because R eagerly evaluates the column
   subsetting on line 132
4. The `else` branch (line 138) calls `identical()` but discards its return value — this
   is dead code (likely a leftover assertion that was never completed)

## Reproduction

```r
library(FactorAnalytics)
data(stocks145scores6)

dat <- stocks145scores6[stocks145scores6$DATE >= "2008-01-31" &
                         stocks145scores6$DATE <= "2012-12-31", ]

# This fit succeeds
fit_sector <- fitFfm(data = dat,
                     asset.var = "TICKER",
                     ret.var = "RETURN",
                     date.var = "DATE",
                     exposure.vars = c("SECTOR", "P2B", "EV2S"),
                     addIntercept = TRUE)

# This fails
fmCov(fit_sector)
# Error in `[.data.frame`(object$data, , object$factor.names) :
#   undefined columns selected

# These also fail
fmSdDecomp(fit_sector)
fmVaRDecomp(fit_sector)
fmEsDecomp(fit_sector)
```

## Known Workaround

The covariance can be computed directly from slots that are always available:

```r
beta <- as.matrix(fit_sector$beta)
beta[is.na(beta)] <- 0
cov_fm <- beta %*% fit_sector$factor.cov %*% t(beta) + diag(fit_sector$resid.var)
```

This produces a correct, positive-definite covariance matrix.

## Proposed Fix Direction

The fix should:

1. **Not extract factor data from `object$data` when `object$factor.cov` is already
   available.** Move the `object$data[, object$factor.names]` extraction inside the
   `if (is.null(factor.cov))` block so it's only evaluated when actually needed.

2. **Handle the `factor.cov == NULL` fallback correctly for sector models.** If the
   factor covariance ever does need to be recomputed, use `object$factor.returns`
   (the estimated factor return time series) rather than columns from `object$data`
   (which are raw exposures, not factor returns).

3. **Apply the same fix pattern to all four affected functions** (`fmCov.ffm`,
   `fmSdDecomp.ffm`, `fmVaRDecomp.ffm`, `fmEsDecomp.ffm`). Note that the risk
   decomposition functions use the extracted factor data for simulation, not just
   covariance, so they will need `object$factor.returns` regardless.

4. **Remove the dead `identical()` call** in the `else` branch of `fmCov.ffm()`.

5. **Add tests** for sector-model covariance and risk decomposition (currently untestable
   due to the bug; our Phase 0 test suite works around it).

## Object Structure Reference

For context, here are the relevant slots of an `ffm` object:

| Slot | Type | Contents |
|---|---|---|
| `$data` | data.frame | Original input data (date, asset, return, raw exposures) |
| `$factor.names` | character vector | Names of estimated factors (includes level names for categorical exposures) |
| `$exposure.vars` | character vector | Original column names passed to `fitFfm()` (e.g., `c("SECTOR", "P2B", "EV2S")`) |
| `$exposures.char` | character vector | Which exposure vars are categorical (e.g., `"SECTOR"`) |
| `$exposures.num` | character vector | Which exposure vars are numeric (e.g., `c("P2B", "EV2S")`) |
| `$beta` | matrix | N×K exposure/loading matrix (assets × factors) |
| `$factor.returns` | xts | T×K matrix of estimated factor returns |
| `$factor.cov` | matrix | K×K factor covariance matrix (pre-computed) |
| `$resid.var` | named numeric | Per-asset residual variance |
| `$residuals` | xts | T×N residual matrix |
| `$restriction.mat` | matrix or NULL | Restriction matrix R such that f = R·g (for intercept models) |

The key insight: `$factor.names` aligns with columns of `$beta`, `$factor.returns`,
and `$factor.cov` — but **not** with columns of `$data`.
