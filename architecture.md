# FactorAnalytics — Architecture Reference

> Reference document for the GreenGrassBlueOcean refactoring effort.
> Generated from `braverock/FactorAnalytics` v2.4.2 (2024-12-12).
> Updated 2026-03-29 with Phase 0, 0.5, 1 (Dependency Pruning), 2 (Performance), and 4 (Testing & Bug Fixes) findings.

---

## 1. Package Overview

FactorAnalytics provides three types of linear factor models for asset returns:

| Model type | Entry point | Class | Internal engine |
|---|---|---|---|
| **Fundamental** (cross-sectional) | `fitFfm()` | `ffm` | `fitFfmDT.R` (data.table) |
| **Time series** (macroeconomic) | `fitTsfm()` | `tsfm` | `fitTsfm.R` (xts/lm per asset) |
| **Statistical** (latent) | *(no fitting function in current codebase)* | `sfm` | *(stub only — class referenced in generics but no `fitSfm`)* |

All three model types feed into a shared downstream layer of risk decomposition,
performance attribution, covariance estimation, and reporting functions.

---

## 2. The Fundamental Factor Model Pipeline (`ffm`)

This is the primary pipeline and the focus of the refactoring. It is already partially
`data.table`-native.

### 2.1 Call Graph

```
fitFfm()                                    [R/fitFfm.R, line 218]
  │
  ├─► specFfm()                             [R/fitFfmDT.R, line 32]
  │     Creates ffmSpec object; converts data to data.table;
  │     sets keys (asset, date); classifies exposures (numeric vs char);
  │     detects model type (style-only / sector / MSCI).
  │
  ├─► lagExposures()                        [R/fitFfmDT.R, line 134]
  │     Lags all exposure columns by one period per asset using
  │     data.table::shift(). Drops first observation per asset.
  │
  ├─► standardizeExposures()                [R/fitFfmDT.R, line 182]
  │     Z-scores numeric exposures. Two paths:
  │     • CrossSection: grouped by date, standard z-score
  │     • TimeSeries: EWMA variance per asset (vectorized via stats::filter)
  │
  ├─► fitFfmDT()                            [R/fitFfmDT.R, line 447]
  │     Core cross-sectional regression engine:
  │     1. Builds model.matrix per date (grouped by date)
  │     2. Constructs restriction matrices for sector + intercept models
  │     3. Runs lm() or lmrobdetMM() per date via data.table grouping
  │     4. Optional second-pass WLS/W-Rob via calcAssetWeightsForRegression()
  │     Returns: reg.listDT (lm objects per date), betasDT (design matrices)
  │
  ├─► extractRegressionStats()              [R/fitFfmDT.R, line 724]
  │     Extracts from lm objects: R², coefficients, residuals.
  │     Computes factor covariance, residual covariance, return covariance.
  │     Heavy xts conversion (6-10 as.xts.data.table calls).
  │     Three code paths: no-intercept, with-intercept, MSCI (two categoricals).
  │
  └─► convert.ffmSpec()                     [R/fitFfmDT.R, line 1239]
        Assembles final ffm object from spec, fit, and regstats.
        Converts data back to data.frame (line 1267).
        Stores lm objects in $factor.fit (line 1271).
```

### 2.2 The `ffm` Object Structure

The return value of `fitFfm()` is a list of class `"ffm"`:

```
ffm
├── $beta              N × K matrix       Last-period factor exposures
├── $factor.returns    xts (T × K)        Estimated factor return time series
├── $residuals         xts (T × N)        Asset residual time series
├── $r2                numeric (T)         R² per cross-section
├── $factor.cov        K × K matrix       Factor return covariance
├── $resid.cov         N × N matrix       Residual covariance (diagonal or full)
├── $resid.var         numeric (N)         Residual variances per asset
├── $return.cov        N × N matrix       Full return covariance (B·Σf·B' + D)
├── $g.cov             matrix or NULL      g-coefficient covariance (intercept models)
├── $restriction.mat   matrix or NULL      Restriction matrix R (intercept models)
├── $factor.fit        list (T)            Stripped lm() objects per date (Phase 2: env severed, $x/$y removed)
├── $factor.names      character (K)       Factor names
├── $asset.names       character (N)       Asset names
├── $time.periods      Date (T)            Unique dates
├── $data              data.frame          Original panel data (converted back from DT)
├── $asset.var         character            Column name for asset identifier
├── $date.var          character            Column name for date
├── $ret.var           character            Column name for returns
├── $exposure.vars     character            Column names for exposures
├── $exposures.num     character            Numeric exposure names
└── $exposures.char    character            Categorical exposure names
```

### 2.3 The `ffmSpec` Object Structure

Intermediate object created by `specFfm()`, consumed by the pipeline:

```
ffmSpec
├── $dataDT            data.table          Panel data (keyed by asset, date)
├── $asset.var         character
├── $ret.var           character
├── $date.var          character
├── $yVar              character            Active return column name (changes if
│                                           returns are standardized/residualized)
├── $exposure.vars     character
├── $exposures.num     character
├── $exposures.char    character
├── $which.numeric     logical
├── $weight.var        character or NULL
├── $rob.stats         logical
├── $addIntercept      logical
├── $model.MSCI        logical              TRUE when 2 categorical exposures
├── $model.styleOnly   logical              TRUE when 0 categorical exposures
├── $lagged            logical
├── $standardizedReturns  logical
└── $residualizedReturns  logical
```

### 2.4 Model Types (Branching Logic)

`fitFfmDT()` and `extractRegressionStats()` have **three major code paths** controlled
by the spec object flags. This is the most complex branching in the package:

| Model type | Condition | Intercept | Restriction matrix |
|---|---|---|---|
| **Style-only** | `model.styleOnly == TRUE` | Optional (`addIntercept`) | None |
| **Sector + Style** | `model.MSCI == FALSE`, has 1 char exposure | Optional | R matrix applied when `addIntercept == TRUE` |
| **MSCI** (Sector + Country + Style) | `model.MSCI == TRUE`, has 2 char exposures | Always (implicit) | Block R matrix |

The restriction matrix `R` handles the sum-to-zero constraint on sector/country
dummies when an intercept (Market) factor is included: `f = R·g`, where `g` are the
unrestricted coefficients.

---

## 3. The Time Series Factor Model Pipeline (`tsfm`)

### 3.1 Call Graph

```
fitTsfm()                                   [R/fitTsfm.R, line 166]
  │
  ├─► PerformanceAnalytics::checkData()     Converts to xts
  ├─► Return.excess() (if rf.name)          Computes excess returns
  │
  ├── variable.selection dispatch:
  │   ├─► NoVariableSelection()             [R/fitTsfm.R, line 288]
  │   │     Loop over assets → lm() or lmrobdetMM() per asset
  │   ├─► SelectStepwise()                  [R/fitTsfm.R, line 320]
  │   │     Loop over assets → lm/lmrobdetMM + step()
  │   ├─► SelectAllSubsets()                [R/fitTsfm.R, line 365]
  │   │     Loop over assets → regsubsets() + lm/lmrobdetMM
  │   └─► SelectLars()                      [R/fitTsfm.R, line 424]
  │         Loop over assets → lars::lars() + cv.lars()
  │
  └── Assembles tsfm object:
        Extracts alpha, beta, r2, resid.sd from per-asset lm objects
```

### 3.2 The `tsfm` Object Structure

```
tsfm
├── $asset.fit         list (N)            lm/lmrobdetMM/lars objects per asset
├── $alpha             data.frame (N × 1)  Intercepts
├── $beta              data.frame (N × K)  Factor loadings
├── $r2                numeric (N)         R² per asset
├── $resid.sd          numeric (N)         Residual standard deviations
├── $data              xts                 Input data (asset + factor returns)
├── $asset.names       character (N)
├── $factor.names      character (K)
├── $mkt.name          character or NULL
├── $fit.method        character           "LS", "DLS", or "Robust"
├── $variable.selection character           "none", "stepwise", "subsets", "lars"
└── $call              call
```

**Key difference from `ffm`:** TSFM fits one regression per *asset* (time series),
while FFM fits one regression per *date* (cross-section).

### 3.3 Excess Return Convention

When `rf.name` is provided, `fitTsfm()` subtracts the risk-free rate from **both**
asset returns **and** factor returns before fitting. The internal `reg.xts` data.table
passed to `lm()` contains `asset_i - rf` as the response and `factor_j - rf` as each
regressor. This is critical for replication: a manual `lm()` cross-check must also
subtract rf from both sides.

---

## 4. Downstream Consumers

All downstream functions are generic (`UseMethod`) with methods for `tsfm` and `ffm`
(and sometimes `sfm`). They read from the fitted model objects documented above.

### 4.1 Consumer Dependency Map

```
                    ┌──────────┐     ┌──────────┐
                    │  fitFfm  │     │ fitTsfm  │
                    │  → ffm   │     │  → tsfm  │
                    └────┬─────┘     └────┬─────┘
                         │                │
           ┌─────────────┼────────────────┼─────────────────┐
           │             │                │                  │
           ▼             ▼                ▼                  ▼
     ┌──────────┐  ┌──────────┐    ┌──────────┐     ┌──────────────┐
     │  fmCov   │  │riskDecomp│    │  paFm    │     │ fmTstats     │
     │  (cov)   │  │(Sd/VaR/ES│    │(perf     │     │ fmRsq        │
     │          │  │ Euler)   │    │ attrib)  │     │ VIF          │
     └──────────┘  └─────┬────┘    └──────────┘     └──────────────┘
                         │                               (ffm only)
           ┌─────────────┼─────────────────┐
           │             │                 │
           ▼             ▼                 ▼
     ┌──────────┐  ┌──────────┐    ┌──────────────┐
     │fmSdDecomp│  │fmVaRDecomp│   │fmEsDecomp   │
     │          │  │           │   │              │
     └──────────┘  └───────────┘   └──────────────┘
           │             │                 │
           ▼             ▼                 ▼
     ┌──────────┐  ┌──────────┐    ┌──────────────┐
     │portSdDec │  │portVaRDec│    │portEsDecomp  │
     │          │  │          │    │              │
     └──────────┘  └──────────┘    └──────────────┘

     ┌───────────────────────────────────────────────┐
     │  Reporting / Plotting Layer                   │
     │  repRisk, repReturn, repExposures             │
     │  plot.ffm, plot.tsfm, plot.pafm               │
     │  summary.ffm, summary.tsfm                    │
     │  print.ffm, print.tsfm                        │
     │  predict.ffm, predict.tsfm                    │
     └───────────────────────────────────────────────┘
```

### 4.2 Consumer → Object Slot Access Map

Which slots each consumer reads from the fitted object:

| Consumer | `$beta` | `$factor.returns` | `$residuals` | `$factor.cov` | `$resid.var` / `$resid.sd` | `$factor.fit` / `$asset.fit` | `$data` |
|---|---|---|---|---|---|---|---|
| `fmCov` | ✓ | | | ✓ | ✓ | | ✓ (tsfm only) |
| `riskDecomp` | ✓ | ✓ (via data) | ✓ | ✓ (via cov) | ✓ | | ✓ |
| `fmSdDecomp` | ✓ | | | ✓ (via cov) | ✓ | | ✓ |
| `fmVaRDecomp` | ✓ | | ✓ | ✓ (via cov) | ✓ | | ✓ |
| `fmEsDecomp` | ✓ | | ✓ | ✓ (via cov) | ✓ | | ✓ |
| `portSdDecomp` | ✓ | | | ✓ (via cov) | ✓ | | ✓ |
| `fmTstats` | | | | | | ✓ `vcov()` | |
| `fmRsq` | | | | | | ✓ `summary()` | |
| `summary.ffm` | | | | | | ✓ `summary()` | |
| `fitted.ffm` | | | | | | ✓ `fitted()` | |
| `predict.ffm` | | | | | | ✓ `predict()` | |
| `paFm` | ✓ | ✓ | | | | | ✓ (ffm: `$asset.var`, `$ret.var`, `$exposure.vars`) |
| `repReturn` | ✓ | ✓ | ✓ | | | | ✓ |
| `repExposures` | ✓ | | | | | | ✓ |
| `repRisk` | ✓ | ✓ | ✓ | ✓ | ✓ | | ✓ |

**Key insight for refactoring:** Only `fmTstats`, `fmRsq`, `summary.ffm`, `fitted.ffm`,
and `predict.ffm` need the full `lm()` objects (`$factor.fit`). Everything else works
from extracted numeric slots.

### 4.3 `fmCov.ffm()` Bug — Sector Models (FIXED)

**Bug (historical):** `fmCov.ffm()` indexed `object$data[, object$factor.names]` to
extract factor return columns. For FFM fits with character exposures (sector models),
`factor.names` contains the factor *level* names (e.g., `"COSTAP"`, `"ENERGY"`) rather
than the original column name (`"SECTOR"`). This caused `"undefined columns selected"`.

A second, related bug: `fitFfmDT.R` did not set `rownames(beta) <- asset.names` in the
`addIntercept = TRUE` + sector+style code path, causing `beta` to have numeric rownames
("1", "2", ...) instead of ticker names. This broke downstream indexing in
`fmVaRDecomp.ffm` and `fmEsDecomp.ffm` with `"subscript out of bounds"`.

**Fix applied:**
- `R/fmCov.R`: Deferred factor extraction into the `if (is.null(factor.cov))` block;
  switched source from `object$data` to `object$factor.returns`; removed dead
  `identical()` call.
- `R/fitFfmDT.R`: Added `rownames(beta) <- asset.names` after the `cbind()` in the
  intercept + sector+style branch.
- The `.ffm` methods for `fmSdDecomp`, `fmVaRDecomp`, `fmEsDecomp` already used
  `object$factor.returns` correctly — no changes needed.
- `fixture_ffm_ls_sector.rds` regenerated with corrected rownames.
- Regression tests added: `test-fmCov.R` (sector + sector-only), `test-riskDecomp.R`
  (sector Sd/VaR/ES decomposition with summation invariant).

### 4.4 Pre-Existing Upstream Issues (Discovered Phase 0.5)

These are **not regressions** — they exist in upstream v2.4.2 and were uncovered while
writing smoke tests.

1. **`plot.ffm` group plot 3 requires explicit `asset.variable`:** The function has no
   default for this parameter and cannot infer it from the `ffm` object. Callers must
   pass e.g. `which.plot.group = 3, asset.variable = "TICKER"` explicitly.

2. **`plot.tsfm` group plots 9–11 emit vector recycling warnings:** When assets have
   unequal history (as in the `managers` dataset), `fmVaRDecomp` produces matrices with
   rows that don't align, triggering "longer object length is not a multiple of shorter
   object length" warnings from internal arithmetic.

3. **`repReturn` and `repExposures` crash on small datasets:** Both functions fail with
   "subscript out of bounds" when called on the 28-stock DJIA dataset. They work
   correctly on the 145-stock WLS model, which is the intended production use case.
   Root cause is hard-coded assumptions about minimum number of assets/dates.

### 4.5 Bugs Fixed During Phase 1 (Dependency Pruning)

These are pre-existing bugs in upstream v2.4.2 code that were discovered and fixed
during the Phase 1 `requireNamespace()` guard work.

1. **`fitTsfm()` unconditionally calls `lmrobdet.control()`** (lines 198–200): Even
   when `fit.method = "LS"`, the function executed `lmrobdet.control()` to parse robust
   control parameters. This meant every `fitTsfm()` call required `RobStatTM` as a hard
   dependency even when robust regression was not requested. **Fix:** Wrapped in
   `if (fit.method == "Robust")` guard.

2. **`fitFfmDT()` default parameter evaluates `lmrobdet.control()`** (line 453):
   `lmrobdet.control.para.list = lmrobdet.control()` as a function default. While R
   evaluates defaults lazily, this still requires `RobStatTM` at parse time for
   `R CMD check`. **Fix:** Changed default to `NULL`; create the control list inside
   the function body only when `fit.method %in% c("ROB", "W-ROB")`.

3. **`fitFfmDT()` calls `ugarchspec()`/`ugarchfit()` without namespace prefix**
   (lines 1178–1181): These `rugarch` function names were declared as NSE `NULL`
   variables to silence R CMD check, but the calls lacked `rugarch::` prefix and had
   no `requireNamespace()` guard. Would crash at runtime if `rugarch` wasn't loaded.
   **Fix:** Added `requireNamespace("rugarch")` guard and `rugarch::` prefix.

4. **`plot.ffm.R` and `plot.tsfm.R` unconditionally fit skew-t distribution**:
   `sn::st.mple()` was called during plot setup, not inside the specific plot branch
   that uses the result (plot 11 in `plot.ffm`, plot 12 in `plot.tsfm`). This meant
   any call to these plot functions required `sn`, even for unrelated plot types.
   **Fix:** Deferred the `sn::st.mple()` + `sn::dst()` calls into the specific plot
   branches where they're used, with `requireNamespace("sn")` guards.

5. **`summary.tsfm()` HC/HAC path had informal guard**: Line 91 used
   `message("requires package lmtest")` instead of a proper `requireNamespace()` +
   `stop()`. **Fix:** Replaced with `requireNamespace()` guards for both `lmtest` and
   `sandwich`, with informative `stop()` messages.

### 4.6 Bugs Fixed During Phase 4 (Testing & Bug Fixes)

1. **`extractRegressionStats()` unbalanced panel dimension mismatch** (line ~800):
   `asset.names` was set to `unique(specObj$data[[specObj$asset.var]])` — all assets
   ever in the dataset — but `residuals` was filtered to `a_last` (last-period assets
   only). On unbalanced panels (e.g., STOXX 1800 with delistings), `beta` had more rows
   than `residuals` columns, breaking downstream covariance calculations.
   **Fix:** Set `asset.names <- a_last` after line 821 so `rownames(beta)` matches
   the last-period asset set. Balanced panels are unaffected (all assets present in
   every period).

2. **`paFm.ffm()` broken slot names and blind intercept drop** (R/paFm.r):
   Used legacy slot names (`fit$assetvar`, `fit$returnsvar`, `fit$exposure.names`) that
   don't exist on the current `fitFfm` object. Also did `fit$factor.returns[, -1]`
   assuming the first column is always an intercept; for style-only models this dropped
   the first real factor.
   **Root causes and fix:**
   - `fit$assetvar` → `fit$asset.var`; `fit$returnsvar` → `fit$ret.var`;
     `fit$exposure.names` → `fit$exposure.vars`
   - Conditional intercept drop: only remove `"(Intercept)"` column by name
   - Replaced positional industry factor indexing (`[-(1:n)]`) with name-based:
     `setdiff(factor.names, num.f.names)`
   - Added `exposure[, factor.names, drop = FALSE]` reordering to ensure column
     alignment before element-wise multiplication
   - Hoisted loop-invariant computations out of per-asset loop

3. **`plot.pafm()` column-select on `cum.spec.ret` data.frame** (R/plot.pafm.r):
   `x$cum.spec.ret[i]` where `i` is an asset name performed column-select (data.frame)
   instead of row-select. Also, `c(scalar, data.frame_row)` produced a list instead of
   a numeric vector.
   **Fix:** Type normalization at function entry converts `cum.spec.ret` to a named
   numeric vector; `unlist()` on `cum.ret.attr.f[i,]` before concatenation.

### 4.7 Monte Carlo Subsystem (Isolated)

```
fmmc()                  [R/fmmc.R]
  └─► .fmmc.proc()     Uses fitTsfm internally
  └─► .fmmc.worker()   Parallel via parallel::parLapply (Phase 1: replaced foreach/doSNOW)
  └─► fmmc.estimate.se()

fmmcSemiParam()         [R/fmmcSemiParam.R]
  └─► tseries::tsbootstrap()   Stationary bootstrap for factors (Suggests)
  └─► sn::rst()                Skew-t residual simulation (Suggests)
  └─► CornishFisher.R          CF residual simulation
```

These functions are self-contained and have no shared state with the main pipeline.
They are the primary consumers of `parallel` (Suggests), `tseries` (Suggests), `sn`
(Suggests), and `boot` (Suggests). Phase 1 removed `doSNOW`, `foreach`, and `RCurl`
entirely — parallel execution now uses `parallel::parLapply()` with explicit
`clusterExport()` (PSOCK workers need variable export), and sequential fallback uses
`lapply()`. The single `RCurl::merge.list()` call was replaced with native R list
merging.

---

## 5. S3 Class Hierarchy and Method Dispatch

### 5.1 Classes

| Class | Created by | Parent |
|---|---|---|
| `ffm` | `fitFfm()` → `convert.ffmSpec()` | list |
| `ffmSpec` | `specFfm()` | list |
| `tsfm` | `fitTsfm()` | list |
| `pafm` | `paFm()` | list |
| `tsfmUpDn` | `fitTsfmUpDn()` | list |
| `summary.ffm` | `summary.ffm()` | list |
| `summary.tsfm` | `summary.tsfm()` | list |
| `summary.tsfmUpDn` | `summary.tsfmUpDn()` | list |

### 5.2 S3 Method Registration (45 methods)

**`ffm` methods:** coef, convert, fitted, fmCov, fmEsDecomp, fmRsq, fmSdDecomp,
fmTstats, fmVaRDecomp, plot, portEsDecomp, portSdDecomp, portVaRDecomp, portVolDecomp,
predict, print, repRisk, residuals, riskDecomp, summary

**`tsfm` methods:** coef, fitted, fmCov, fmEsDecomp, fmSdDecomp, fmVaRDecomp, plot,
portEsDecomp, portSdDecomp, portVaRDecomp, portVolDecomp, predict, print, repRisk,
residuals, riskDecomp, summary

**`sfm` methods (stubs):** fmCov, fmEsDecomp, fmSdDecomp, fmVaRDecomp

**`pafm` methods:** plot, print, summary

**`ffmSpec` methods:** convert, print

**`tsfmUpDn` methods:** plot, predict, print, summary

---

## 6. Dependency Map (Post–Phase 1)

Phase 1 reduced hard Imports from 18 packages to 6 (plus base R). Three packages
(`RCurl`, `doSNOW`, `foreach`) were removed entirely; 12 were moved to Suggests with
`requireNamespace()` guards at every call site.

### 6.1 Hard Dependencies (Imports — Required for Core Path)

```
data.table             Panel data engine (fitFfmDT, specFfm, all DT functions)
xts / zoo              Time series objects (factor.returns, residuals, all tsfm)
PerformanceAnalytics   checkData(), Return.cumulative(), chart.* in plots
lattice                Trellis plots in repRisk, repReturn, repExposures, fmTstats, fmRsq
methods                is() checks
stats / graphics / grDevices / utils   Base R (not listed in Imports)
```

### 6.2 Optional Dependencies (Suggests — Guarded with `requireNamespace()`)

All call sites use `requireNamespace("pkg", quietly = TRUE)` with an informative
`stop()` message directing the user to `install.packages()`.

| Package | Gating condition | Files | Guard location |
|---|---|---|---|
| `RobStatTM` | `fit.method = "Rob"/"W-Rob"/"Robust"`, `rob.stats = TRUE` | fitFfmDT, fitTsfm, plot.tsfm | Function entry (fitFfmDT, fitTsfm); robust branch (plot.tsfm) |
| `robustbase` | `rob.stats = TRUE` | fitFfmDT (extractRegressionStats, calcAssetWeights) | Before `scaleTau2()` / `covOGK()` calls |
| `lars` | `variable.selection = "lars"` | fitTsfm | Top of `SelectLars()` |
| `leaps` | `variable.selection = "subsets"` | fitTsfm | Top of `SelectAllSubsets()` |
| `sn` | Skew-t density overlay; skew-t residuals | plot.ffm (plot 11), plot.tsfm (plot 12), fmmcSemiParam | Inside plot branch; before `rst()` call |
| `sandwich` | `se.type = "HC"/"HAC"` | summary.tsfm | Inside HC/HAC `if` block |
| `lmtest` | `se.type = "HC"/"HAC"` | summary.tsfm | Inside HC/HAC `if` block (co-guarded with sandwich) |
| `boot` | Bootstrap SE estimation | fmmc, fmmcSemiParam | At `.fmmc.se()` entry; at `boot()` call site |
| `tseries` | `boot.method = "block"` | fmmcSemiParam | Inside block bootstrap `if` block |
| `parallel` | `fmmc(parallel = TRUE)` | fmmc | Inside `if (parallel)` block |
| `rugarch` | `GARCH.MLE = TRUE` or `stdReturn = TRUE` | fitFfmDT (calcAssetWeights) | Before `ugarchspec()` / `ugarchfit()` calls |
| `corrplot` | Correlation plot types (group plots 7–8) | plot.ffm, plot.tsfm | *(pre-existing guards)* |
| `strucchange` | Structural break tests (individual plots 15–17) | plot.tsfm | *(pre-existing guards)* |
| `HH` | *(legacy, no active call sites found)* | — | — |
| `R.rsp` | Vignette builder only | — | `VignetteBuilder` field |
| `testthat` | Testing only | tests/ | — |

### 6.3 Removed Dependencies (Phase 1)

| Package | Was | Replacement |
|---|---|---|
| `RCurl` | Imports | Single `merge.list()` call → native `c(args, add.args[setdiff(...)])` |
| `doSNOW` | Imports | `registerDoSNOW()` → `parallel::parLapply()` with `clusterExport()` |
| `foreach` | Imports | `foreach %dopar%` → `parallel::parLapply()`; `foreach %do%` → `lapply()` |

---

## 7. Performance Bottlenecks (Post–Phase 2)

### 7.1 Row-by-Row `for` Loops — ✅ RESOLVED (Phase 2)

All 5 row-by-row `set()` for-loops in `fitFfmDT.R` followed the recursive variance
pattern `σ²[t] = α·x[t] + β·σ²[t-1]` and have been replaced:

| Loop | Function | Replacement | Notes |
|---|---|---|---|
| 1 | `standardizeExposures` (EWMA) | `stats::filter(method = "recursive")` | C-level |
| 2 | `standardizeReturns` (GARCH) | `stats::filter(method = "recursive")` | C-level |
| 3 | `calcAssetWeightsForRegression` (EWMA) | `stats::filter(method = "recursive")` | C-level |
| 4 | `calcAssetWeightsForRegression` (Robust EWMA) | `Reduce(accumulate = TRUE)` | Conditional recursion; can't use `stats::filter` |
| 5 | `calcAssetWeightsForRegression` (GARCH) | `stats::filter(method = "recursive")` | C-level |

4 intermediate fixtures verify vectorized output matches the original for-loop results
within `1e-12` tolerance.

**Bug fixed during vectorization:** Loop #4 (Robust EWMA) referenced
`resid.DT$var` (non-existent column) instead of `resid.DT$resid.var`. Since
`data.table` `$` does not partial-match, all Robust EWMA weights were `NA`.

### 7.2 `lm()` Object Accumulation — ✅ RESOLVED (Phase 2)

`fitFfmDT()` stores `lm()` objects per date in `reg.listDT$reg.list`. Previously each
`lm` silently captured `$model`, `$qr`, and the formula environment (pointer to parent
data.table). At STOXX 1800 scale this created ~120 hidden copies of the panel.

**Fix:** `strip_lm()` helper applied at all 4 regression call sites (LS, ROB, WLS,
W-Rob):
- Neuters `$call` → `call("lm")`
- Severs `.Environment` → `baseenv()`
- Removes `$x`, `$y`
- Retains `$model` (required by `predict.lm()` without `newdata`)

Regression test in `test-vectorize.R` verifies `coef()`, `residuals()`, `fitted()`,
`summary()`, `vcov()`, and `predict()` all work on stripped objects.

### 7.3 R² Extraction Dedup — ✅ RESOLVED (Phase 2)

`convert.ffmSpec()` previously re-called `summary()` on every stored `lm` object to
extract R². Now reads `RegStatsObj$r2` directly (already computed in
`extractRegressionStats()`).

### 7.4 `xts` Conversion Churn (Remaining)

`extractRegressionStats()` converts intermediate data.table results to xts 6–10 times
(residuals, factor returns, weights, g-coefficients, IC). `convert.ffmSpec()` then
converts the data *back* to data.frame (line 1267). This is a Phase 3 candidate.

---

## 8. Exported Public API

### 8.1 Model Fitting (6 functions)

| Function | File | Description |
|---|---|---|
| `fitFfm` | fitFfm.R | Fundamental factor model (main entry) |
| `fitFfmDT` | fitFfmDT.R | DT regression engine (called by fitFfm) |
| `specFfm` | fitFfmDT.R | Create ffmSpec object |
| `fitTsfm` | fitTsfm.R | Time series factor model |
| `fitTsfm.control` | fitTsfm.control.R | Control parameters for fitTsfm |
| `fitTsfmUpDn` | fitTsfmUpDn.R | Up/down market timing model |

### 8.2 Pipeline Components (5 functions, exported but primarily internal)

| Function | File | Description |
|---|---|---|
| `lagExposures` | fitFfmDT.R | Lag style exposures by one period |
| `standardizeExposures` | fitFfmDT.R | Z-score exposures |
| `standardizeReturns` | fitFfmDT.R | GARCH standardize returns |
| `residualizeReturns` | fitFfmDT.R | Residualize returns vs benchmark |
| `extractRegressionStats` | fitFfmDT.R | Extract stats from lm objects |

### 8.3 Risk Decomposition (8 functions)

| Function | Classes | Description |
|---|---|---|
| `riskDecomp` | tsfm, ffm | Unified Sd/VaR/ES decomposition |
| `fmSdDecomp` | tsfm, sfm, ffm | Standard deviation decomposition |
| `fmVaRDecomp` | tsfm, sfm, ffm | Value-at-Risk decomposition |
| `fmEsDecomp` | tsfm, sfm, ffm | Expected Shortfall decomposition |
| `portSdDecomp` | tsfm, ffm | Portfolio SD decomposition |
| `portVaRDecomp` | tsfm, ffm | Portfolio VaR decomposition |
| `portEsDecomp` | tsfm, ffm | Portfolio ES decomposition |
| `portVolDecomp` | tsfm, ffm | Portfolio volatility decomposition |

### 8.4 Analytics & Covariance (5 functions)

| Function | Classes | Description |
|---|---|---|
| `fmCov` | tsfm, sfm, ffm | Factor model covariance matrix |
| `fmTstats` | ffm | T-statistics time series |
| `fmRsq` | ffm | R² time series |
| `vif` | ffm | Variance inflation factors |
| `paFm` | tsfm, sfm, ffm | Performance attribution |

### 8.5 Reporting (3 functions, ffm only)

| Function | Description |
|---|---|
| `repRisk` | Risk decomposition report with plots |
| `repReturn` | Return decomposition report with plots |
| `repExposures` | Exposure report with plots |

### 8.6 Monte Carlo (3 functions)

| Function | Description |
|---|---|
| `fmmc` | Factor model Monte Carlo (parallel) |
| `fmmc.estimate.se` | SE estimation from fmmc output |
| `fmmcSemiParam` | Semi-parametric FMMC |

### 8.7 Utilities (7 functions)

| Function | Description |
|---|---|
| `convert` | Generic; converts ffmSpec → ffm |
| `roll.fitFfmDT` | Rolling-window FFM fitting |
| `fitTsfmMT` | Market-timing wrapper for fitTsfm |
| `fitTsfmLagLeadBeta` | Lag/lead beta estimation |
| `selectCRSPandSPGMI` | Data selection for CRSP/SPGMI |
| `exposuresTseries` | Exposure time series plotting |
| `tsPlotMP` | Multi-panel time series plot |

### 8.8 Cornish-Fisher Distribution (4 functions)

`dCornishFisher`, `pCornishFisher`, `qCornishFisher`, `rCornishFisher`

---

## 9. Data Files

| File | Size | Description |
|---|---|---|
| `stocks145scores6.rda` | 1.3 MB | 145 stocks, 6 scores, monthly panel (DATE, TICKER, RETURN, SECTOR, + factors) |
| `factorDataSetDjia5Yrs.rda` | 30.5 KB | DJIA components, 5 years (DATE, TICKER, RETURN, + fundamental factors) |
| `wtsDjiaGmvLo.rda` | 392 B | GMV long-only weights for DJIA |
| `wtsStocks145GmvLo.rda` | 1.8 KB | GMV long-only weights for 145 stocks |

All tracked via Git LFS.

### 9.2 Test Fixtures

26 `.rds` fixtures in `tests/testthat/fixtures/`. 22 gold-standard fixtures generated
from unmodified v2.4.2 code; 4 added in Phase 2 for vectorized EWMA/GARCH intermediate
results. Each stores only numeric slots (no `lm` objects).

| Fixture | Model / Function | Key slots |
|---|---|---|
| `fixture_ffm_ls_style` | `fitFfm()` LS, style-only (P2B, EV2S on DJIA) | beta, factor.returns, residuals, factor.cov, resid.var, r2 |
| `fixture_ffm_ls_sector` | `fitFfm()` LS, SECTOR + P2B + EV2S + intercept | " |
| `fixture_ffm_sector_only` | `fitFfm()` LS, SECTOR only | " |
| `fixture_ffm_wls` | `fitFfm()` WLS, 7 exposures on stocks145 | " |
| `fixture_ffm_wrob` | `fitFfm()` W-Rob, SECTOR + P2B on DJIA | " |
| `fixture_tsfm_ls` | `fitTsfm()` LS on managers | alpha, beta, r2, resid.sd, residuals, fitted |
| `fixture_tsfm_robust` | `fitTsfm()` Robust on managers | " |
| `fixture_tsfm_lars` | `fitTsfm()` lars on managers | " |
| `fixture_fmCov_ffm_style` | `fmCov()` on style-only FFM | cov matrix + dimnames |
| `fixture_fmCov_tsfm` | `fmCov()` on TSFM LS | " |
| `fixture_cov_identity_ffm` | Manual β·Σ_F·β' + D on WLS FFM | cov, beta, factor.cov, resid.var |
| `fixture_fmSdDecomp_ffm` | `fmSdDecomp()` on style-only FFM | Sd.fm, mSd, cSd, pcSd |
| `fixture_fmVaRDecomp_ffm` | `fmVaRDecomp()` on style-only FFM | VaR.fm, mVaR, cVaR, pcVaR |
| `fixture_fmEsDecomp_ffm` | `fmEsDecomp()` on style-only FFM | ES.fm, mES, cES, pcES |
| `fixture_portSdDecomp_tsfm` | `portSdDecomp()` on TSFM LS | Sd.fm, mSd, cSd, pcSd |
| `fixture_portVaRDecomp_tsfm` | `portVaRDecomp()` on TSFM LS (p=0.9, normal) | VaR.fm, mVaR, cVaR, pcVaR |
| `fixture_portEsDecomp_tsfm` | `portEsDecomp()` on TSFM LS (p=0.9, normal) | ES.fm, mES, cES, pcES |
| `fixture_portSdDecomp_ffm` | `portSdDecomp()` on style-only FFM | Sd.fm, mSd, cSd, pcSd |
| `fixture_portVaRDecomp_ffm` | `portVaRDecomp()` on style-only FFM (p=0.9, normal) | VaR.fm, mVaR, cVaR, pcVaR |
| `fixture_portEsDecomp_ffm` | `portEsDecomp()` on style-only FFM (p=0.9, normal) | ES.fm, mES, cES, pcES |
| `fixture_fmRsq` | `fmRsq()` on WLS FFM | rsq + rsqAdj |
| `fixture_fmTstats` | `fmTstats()` on WLS FFM | tstats + pvalues |
| `fixture_standardize_ewma` | EWMA z-score (Loop #1) on DJIA | Per-exposure variance series |
| `fixture_standardize_garch` | GARCH(1,1) standardization (Loop #2) on DJIA | sigmaGarch column |
| `fixture_weights_ewma` | EWMA WLS weights (Loop #3) | id, date, residuals, resid.var, w |
| `fixture_weights_garch` | GARCH WLS weights (Loop #5) | id, date, residuals, resid.var, w |

**Note on risk decomposition percentages:** `pcSd`, `pcVaR`, `pcES` are on the 0–100
scale (percentages), not 0–1 (proportions).

### 9.3 Smoke Tests (Phase 0.5)

`tests/testthat/test-smoke-methods.R` contains 91 run-and-check assertions across 23
`test_that()` blocks. These are **not** fixture-backed; they verify "does not crash" and
"returns expected type/class" for S3 methods that had zero test coverage.

| Category | Blocks | Assertions | Coverage targets |
|---|---|---|---|
| Accessor & summary methods | 10 | 28 | `coef`, `residuals`, `fitted`, `predict`, `print`, `summary` for both `ffm` and `tsfm` |
| Plot methods | 5 | 50 | `plot.ffm` (11 group + 13 individual), `plot.tsfm` (9 group + 15 individual) |
| Reporting functions | 8 | 13 | `repExposures`, `repReturn`, `repRisk` (both `ffm` and `tsfm`) |

**Skips and suppressions (pre-existing upstream issues, not regressions):**
- `plot.ffm` / `plot.tsfm` group plots 7–8 skipped (`corrplot` is in Suggests)
- `plot.ffm` individual plot 11 skipped (skew-t density requires separate fit)
- `plot.tsfm` individual plots 15–17 skipped (`strucchange` is in Suggests)
- `plot.tsfm` group plots 9–11 suppress vector recycling warnings (unequal asset history in `managers` dataset)

**Test models (defined in `setup.R` and file-local `local()` blocks):**
- `fit_ffm_style`: 2-factor style-only (P2B, EV2S) on DJIA
- `fit_ffm_sector`: Sector + style with intercept on DJIA
- `fit_ffm_wls`: 145-stock WLS production model (used for `repReturn` / `repExposures`)
- `fit_tsfm_ls`: TSFM LS on managers (6 assets, 3 factors)

### 9.4 Total Test Inventory

| File | Blocks | Focus | Type |
|---|---|---|---|
| `test-fitFfm.R` | 5 | FFM model branches + structure invariants | Fixture-backed |
| `test-fitTsfm.R` | 3 | TSFM paths + manual `lm()` cross-validation | Fixture-backed |
| `test-fmCov.R` | 5 | Covariance matrices + identity/PSD verification | Fixture-backed |
| `test-riskDecomp.R` | 6 | Asset-level Sd/VaR/ES decomposition | Fixture-backed |
| `test-portDecomp.R` | 9 | Portfolio-level decomposition + weight validation | Fixture-backed |
| `test-fmRsq.R` | 2 | R-squared computation | Fixture-backed |
| `test-fmTstats.R` | 2 | T-statistics computation | Fixture-backed |
| `test-input-validation.R` | 5 | Error handling, weight validation | Behavioural |
| `test-smoke-methods.R` | 23 | S3 methods, plots, reporting | Smoke (run-and-check) |
| `test-vectorize.R` | 7 | EWMA/GARCH vectorization, Robust EWMA, stripped `lm` | Fixture-backed + behavioural (Phase 2) |
| `test-unbalanced-panel.R` | 8 | Synthetic unbalanced panel: delist/entry assets | Behavioural (Phase 4) |
| `test-fmCov-invariants.R` | 13 | 6 invariants × 8 model configs (symmetry, PSD, dims) | Structural (Phase 4) |
| `test-CornishFisher.R` | 8 | CF expansion mathematical properties | Behavioural (Phase 4) |
| `test-portVolDecomp.R` | 5 | Portfolio volatility decomposition (TSFM + FFM) | Behavioural (Phase 4) |
| `test-vif.R` | 3 | Variance inflation factors | Behavioural (Phase 4) |
| `test-paFm.R` | 8 | Performance attribution: TSFM + 3 FFM types + plots | Behavioural (Phase 4) |
| `test-fitTsfmUpDn.R` | 4 | Up/down market timing model | Behavioural (Phase 4) |
| `test-roll-fitFfmDT.R` | 1 | Rolling-window FFM smoke test | Smoke (Phase 4) |
| **Total** | **117** | | **438 assertions** |

**Conditional skips (added Phase 1):** Three test blocks skip when optional packages
are absent:
- `test-fitFfm.R` W-Rob fixture test → `skip_if_not_installed("RobStatTM")` +
  `skip_if_not_installed("robustbase")`
- `test-fitTsfm.R` Robust fixture test → `skip_if_not_installed("RobStatTM")`
- `test-fitTsfm.R` lars fixture test → `skip_if_not_installed("lars")`

---

## 10. File Index

### R Source Files by Functional Area

**FFM core** (6 files, 103 KB):
`fitFfm.R`, `fitFfmDT.R`, `fitFfM2_rolling.R`, `selectCRSPandSPGMI.R`,
`residualizeReturns.R` *(logic lives inside fitFfmDT.R)*

**TSFM core** (4 files, 52 KB):
`fitTsfm.R`, `fitTsfm.control.R`, `fitTsfmMT.R`, `fitTsfmUpDn.R`,
`fitTsfmLagLeadBeta.r`

**Risk decomposition** (8 files, 109 KB):
`riskDecomp.R`, `fmSdDecomp.R`, `fmVaRDecomp.R`, `fmEsDecomp.R`,
`portSdDecomp.R`, `portVaRDecomp.R`, `portEsDecomp.R`, `portVolDecomp.R`,
`assetDecomp.R`

**Covariance & stats** (4 files, 31 KB):
`fmCov.R`, `fmRsq.R`, `fmTstats.R`, `VIF.R`

**Reporting** (3 files, 52 KB):
`repRisk.R`, `repReturn.R`, `repExposures.R`

**Plotting** (5 files, 72 KB):
`plot.ffm.R`, `plot.tsfm.R`, `plot.pafm.r`, `plot.tsfmUpDn.r`, `tsPlotMP.R`

**S3 methods** (10 files, 22 KB):
`summary.ffm.R`, `summary.tsfm.r`, `summary.pafm.r`, `summary.tsfmUpDn.r`,
`print.ffm.R`, `print.tsfm.r`, `print.pafm.r`, `print.tsfmUpDn.r`,
`predict.ffm.R`, `predict.tsfm.r`, `predict.tsfmUpDn.r`

**Monte Carlo** (3 files, 26 KB):
`fmmc.R`, `fmmcSemiParam.R`, `CornishFisher.R`

**Performance attribution** (1 file, 9 KB):
`paFm.r`

**Utilities** (2 files, 6 KB):
`exposuresTseries.R`, `tsPlotMP.R`

**Data documentation** (4 files, 4 KB):
`factorDataSetDjia5Yrs.R`, `stocks145scores6.R`, `wtsDjiaGmvLo.R`,
`wtsStocks145GmvLo.R`

---

## 11. Key Invariants for Refactoring

These are properties that **must** hold after every phase:

1. **Covariance identity:** `fit$beta %*% fit$factor.cov %*% t(fit$beta) + diag(fit$resid.var)` must produce the correct asset covariance matrix for all model types. `fmCov(fit)` must produce the same result. Verified for style-only and sector models in `test-fmCov.R`.

2. **Dimensional consistency:** `rownames(fit$beta)` == `names(fit$resid.var)` == `colnames(fit$residuals)`.

3. **Factor return dimensions:** `colnames(fit$factor.returns)` == `colnames(fit$beta)` == `colnames(fit$factor.cov)`.

4. **R² reproducibility:** `fit$r2[t]` must match `summary(lm(...))$r.squared` for the cross-section at date `t`.

5. **Restriction matrix math:** For intercept models, `f = R·g` where `f` are factor returns, `R` is the restriction matrix, and `g` are unrestricted coefficients. `fit$factor.cov` is computed from `f`, while `fit$g.cov` is computed from `g`.

6. **Risk decomposition summation:** `rowSums(pcSd)`, `rowSums(pcVaR)`, and `rowSums(pcES)` must equal 100 (percentage scale) for all assets. Verified in `test-riskDecomp.R`.

7. **TSFM excess return symmetry:** When `rf.name` is provided, `fitTsfm()` subtracts rf from both asset returns and factor returns. Manual cross-validation of betas must replicate this convention (see Section 3.3).

## 12. Phase Status

| Phase | Status | Key Deliverable | Key Numbers |
|---|---|---|---|
| **0 — Foundation** | ✅ Complete | testthat migration, 22 fixtures, CI/CD | 163 assertions; 0 errors, 0 warnings |
| **0.5 — Smoke Tests** | ✅ Complete | 91 smoke tests for S3 methods | 254 total assertions; coverage 23.4% → 46.4% |
| **1 — Dependency Pruning** | ✅ Complete | Imports 18 → 6; 3 packages removed; 12 to Suggests | 254 tests pass; 5 pre-existing bugs fixed |
| **2 — Performance** | ✅ Complete | Vectorize 5 for loops; strip lm() objects; dedup R² | 269 assertions; 4 new fixtures; Robust EWMA bug fixed. Commit `3988d65`. |
| **3 — API Hardening** | 🔲 Not started | Unbalanced panels; fmCov dimensionality; PA integration | — |
| **4 — Testing & Bug Fixes** | 🔄 In progress | Unbalanced panel fix; fmCov invariants; coverage expansion; paFm/plot.pafm fixes | 438 assertions; 8 new test files; 3 pre-existing bugs fixed. Commit `7039a0a`. |

---

## 13. CI / Notifications

The CI workflow (`.github/workflows/slack-notify-build.yml`) runs R CMD check on 5 OS/R-version combinations. It inherited Slack notification steps from the upstream `braverock/FactorAnalytics` repo. These steps are guarded with `if: env.SLACK_BOT_TOKEN != ''` so they are silently skipped when the `SLACK_NOTIFICATIONS_BOT_TOKEN` secret is not configured.

**Future:** Consider replacing the Slack integration with Mattermost using [GreenGrassBlueOcean/MattermostR](https://github.com/GreenGrassBlueOcean/MattermostR). This would align CI notifications with the organisation's own tooling rather than depending on the upstream's Slack workspace.
