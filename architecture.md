# FactorAnalytics — Architecture Reference

> Reference document for the GreenGrassBlueOcean refactoring effort.
> Generated from `braverock/FactorAnalytics` v2.4.2 (2024-12-12).
> Updated 2026-03-28 with Phase 0 findings.

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
  │     • TimeSeries: EWMA variance per asset (ROW-BY-ROW FOR LOOP ⚠️)
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
├── $factor.fit        list (T)            Full lm() objects per date ⚠️ MEMORY
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
| `fmCov` | ✓ | | | ✓ | ✓ | | ✓ (tsfm only) ⚠️ BUG: fails on sector FFM |
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
| `paFm` | ✓ | ✓ | ✓ | | | | |
| `repReturn` | ✓ | ✓ | ✓ | | | | ✓ |
| `repExposures` | ✓ | | | | | | ✓ |
| `repRisk` | ✓ | ✓ | ✓ | ✓ | ✓ | | ✓ |

**Key insight for refactoring:** Only `fmTstats`, `fmRsq`, `summary.ffm`, `fitted.ffm`,
and `predict.ffm` need the full `lm()` objects (`$factor.fit`). Everything else works
from extracted numeric slots.

### 4.3 `fmCov.ffm()` Bug — Sector Models

**Bug:** `fmCov.ffm()` indexes `object$data[, object$factor.names]` to extract factor
return columns. For FFM fits with character exposures (sector models), `factor.names`
contains the factor *level* names (e.g., `"COSTAP"`, `"ENERGY"`, `"FINS"`) rather than
the original column name (`"SECTOR"`). This causes `"undefined columns selected"`.

**Affected model types:** Any FFM with ≥1 character exposure (sector-only,
sector+style, MSCI). Style-only FFMs (0 character exposures) are unaffected.

**Downstream impact:** All functions that call `fmCov()` internally will fail on sector
models: `fmSdDecomp`, `fmVaRDecomp`, `fmEsDecomp`, `portSdDecomp`, `portVaRDecomp`,
`portEsDecomp`, `riskDecomp`, `repRisk`.

**Workaround:** Compute covariance directly from slots:
```r
cov_mat <- fit$beta %*% fit$factor.cov %*% t(fit$beta) + diag(fit$resid.var)
```

**Fix target:** Phase 3 (API Hardening).

### 4.4 Monte Carlo Subsystem (Isolated)

```
fmmc()                  [R/fmmc.R]
  └─► .fmmc.proc()     Uses fitTsfm internally
  └─► .fmmc.worker()   Parallel via foreach/doSNOW
  └─► fmmc.estimate.se()

fmmcSemiParam()         [R/fmmcSemiParam.R]
  └─► tseries::tsbootstrap()   Stationary bootstrap for factors
  └─► sn::rst()                Skew-t residual simulation
  └─► CornishFisher.R          CF residual simulation
```

These functions are self-contained and have no shared state with the main pipeline.
They are the only consumers of `doSNOW`, `foreach`, `parallel`, `RCurl`, `tseries`,
and `sn`.

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

## 6. Dependency Map

### 6.1 Hard Dependencies (Required for Core Path)

```
data.table        Panel data engine (fitFfmDT, specFfm, all DT functions)
xts / zoo         Time series objects (factor.returns, residuals, all tsfm)
PerformanceAnalytics  checkData(), Return.cumulative(), chart.* in plots
lattice           Trellis plots in repRisk, repReturn, repExposures, fmTstats, fmRsq
methods           is() checks
stats / graphics / grDevices / utils   Base R
```

### 6.2 Optional Dependencies (Gated by User Arguments)

| Package | Gating condition | Files |
|---|---|---|
| `RobStatTM` | `fit.method = "Rob"` or `"W-Rob"`, or `rob.stats = TRUE` | fitFfm, fitFfmDT, fitTsfm, fitTsfm.control, extractRegressionStats, plot.tsfm |
| `robustbase` | `rob.stats = TRUE` | fitFfm, fitFfmDT (extractRegressionStats, calcAssetWeights) |
| `lars` | `variable.selection = "lars"` | fitTsfm, fitTsfm.control |
| `sn` | Skew-t density overlay in plots; skew-t residuals in fmmcSemiParam | plot.ffm, plot.tsfm, fmmcSemiParam |
| `doSNOW` / `foreach` / `parallel` | Parallel execution in fmmc | fmmc.R only |
| `RCurl` | Single `merge.list()` call | fmmc.R only |
| `tseries` | Stationary bootstrap | fmmcSemiParam.R only |
| `sandwich` | HC/HAC standard errors in tsfm summary | summary.tsfm.r only |
| `leaps` | `variable.selection = "subsets"` | fitTsfm.R only |
| `boot` | Bootstrap in fmmcSemiParam | fmmcSemiParam.R only |
| `rugarch` | `GARCH.MLE = TRUE` or `stdReturn = TRUE` | fitFfmDT.R (calcAssetWeights), fitFfm |

---

## 7. Performance Bottlenecks

### 7.1 Row-by-Row `for` Loops (5 instances, all in `fitFfmDT.R`)

All follow the same recursive variance pattern: `σ²[t] = α·x[t] + β·σ²[t-1]`

| Location | Function | Line | Purpose |
|---|---|---|---|
| 1 | `standardizeExposures` | 239 | TimeSeries z-score EWMA |
| 2 | `standardizeReturns` | 373 | GARCH(1,1) return standardization |
| 3 | `calcAssetWeightsForRegression` | 1159 | EWMA residual variance for WLS |
| 4 | `calcAssetWeightsForRegression` | 1165 | Robust EWMA residual variance |
| 5 | `calcAssetWeightsForRegression` | 1189 | GARCH residual variance for WLS |

### 7.2 `lm()` Object Accumulation

`fitFfmDT()` stores full `lm()` objects per date in `reg.listDT$reg.list`. Each `lm`
silently captures `$model` (data frame copy), `$qr` (QR decomposition), and the formula
environment (pointer to parent data.table). At STOXX 1800 scale (~120 dates × ~1800
assets), this creates ~120 hidden copies of the panel.

**Consumers that require `lm` objects:** `fmTstats` (vcov), `fmRsq` (summary),
`summary.ffm`, `fitted.ffm`, `predict.ffm`.

**Consumers that only need extracted numerics:** everything else.

### 7.3 `xts` Conversion Churn

`extractRegressionStats()` converts intermediate data.table results to xts 6–10 times
(residuals, factor returns, weights, g-coefficients, IC). `convert.ffmSpec()` then
converts the data *back* to data.frame (line 1267).

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

All currently tracked via Git LFS (to be migrated in a future commit — see plan Phase 0.4).

### 9.2 Test Fixtures

22 gold-standard `.rds` fixtures in `tests/testthat/fixtures/`, generated from
unmodified v2.4.2 code. Each stores only numeric slots (no `lm` objects).

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

**Note on risk decomposition percentages:** `pcSd`, `pcVaR`, `pcES` are on the 0–100
scale (percentages), not 0–1 (proportions).

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

1. **Covariance identity:** `fit$beta %*% fit$factor.cov %*% t(fit$beta) + diag(fit$resid.var)` must produce the correct asset covariance matrix for all model types. For style-only FFMs, this must also equal `fmCov(fit)`. (Note: `fmCov.ffm()` currently has a bug on sector models — see Section 4.3.)

2. **Dimensional consistency:** `rownames(fit$beta)` == `names(fit$resid.var)` == `colnames(fit$residuals)`.

3. **Factor return dimensions:** `colnames(fit$factor.returns)` == `colnames(fit$beta)` == `colnames(fit$factor.cov)`.

4. **R² reproducibility:** `fit$r2[t]` must match `summary(lm(...))$r.squared` for the cross-section at date `t`.

5. **Restriction matrix math:** For intercept models, `f = R·g` where `f` are factor returns, `R` is the restriction matrix, and `g` are unrestricted coefficients. `fit$factor.cov` is computed from `f`, while `fit$g.cov` is computed from `g`.

6. **Risk decomposition summation:** `rowSums(pcSd)`, `rowSums(pcVaR)`, and `rowSums(pcES)` must equal 100 (percentage scale) for all assets. Verified in `test-riskDecomp.R`.

7. **TSFM excess return symmetry:** When `rf.name` is provided, `fitTsfm()` subtracts rf from both asset returns and factor returns. Manual cross-validation of betas must replicate this convention (see Section 3.3).
