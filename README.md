
# FactorAnalytics <img src="man/figures/logo.png" align="right" height="139" />

<!-- badges -->
[![R-CMD-check](https://github.com/GreenGrassBlueOcean/FactorAnalytics/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/GreenGrassBlueOcean/FactorAnalytics/actions/workflows/R-CMD-check.yaml)
[![codecov](https://codecov.io/gh/GreenGrassBlueOcean/FactorAnalytics/graph/badge.svg)](https://codecov.io/gh/GreenGrassBlueOcean/FactorAnalytics)

Linear factor models for asset return data: fitting, risk decomposition,
and performance attribution. Covers the three major model types used in
portfolio construction and risk management:

| Model | Entry point | Class | Use case |
|-------|-------------|-------|----------|
| **Fundamental** (cross-sectional) | `fitFfm()` | `ffm` | Sector/style risk models, MSCI-type multi-country models |
| **Time series** | `fitTsfm()` | `tsfm` | Macro factor models, market timing |
| **Statistical** (PCA) | `fitSfm()` | `sfm` | Latent factor discovery |

## About this fork

This is the [GreenGrassBlueOcean](https://github.com/GreenGrassBlueOcean/FactorAnalytics)
fork of [braverock/FactorAnalytics](https://github.com/braverock/FactorAnalytics) (v2.4.2).
The upstream package has been used in production at investment firms for over a decade.
This fork applies a systematic refactoring focused on reliability, performance, and
test coverage while preserving full API compatibility.

### What changed

**Bug fixes (13 pre-existing bugs found and fixed)**

- `fmCov()` crashed on sector models (wrong column lookup in `object$data`)
- `paFm()` used legacy slot names and blindly dropped intercept columns
- `extractRegressionStats()` broke on unbalanced panels (delisted assets)
- `fitFfm()` validated the wrong parameter (`z.score` instead of `analysis`)
- MSCI models (2+ character exposures) with style variables produced
  non-conformable matrix errors — style coefficients were not separated
  before restriction-matrix multiplication
- Robust EWMA weighting referenced a non-existent column, producing `NA` weights
- Several more — see [AGENTS.md](AGENTS.md) for the full list

**Performance**

- 5 row-by-row `for`/`set()` loops replaced with vectorized `stats::filter()`
  and `Reduce()` (EWMA/GARCH recursions)
- `lm` objects stripped of hidden environment references and redundant slots,
  preventing ~120 silent copies of the panel at STOXX 1800 scale
- R² extraction deduped (was re-calling `summary()` on every stored `lm`)

**Dependency pruning**

Hard imports reduced from 18 to 6 (`data.table`, `lattice`, `methods`,
`PerformanceAnalytics`, `xts`, `zoo`). 12 packages moved to Suggests;
3 removed entirely (`RCurl`, `doSNOW`, `foreach`).

**Input validation**

- Column-existence checks with clear error messages in `fitFfm()` and `fitTsfm()`
- Duplicate validation between `fitFfm()` and `specFfm()` consolidated

**Test suite**

605 assertions across 20 test files, 0 failures. Coverage increased from
~0% to 46%. Tests cover model fitting, risk decomposition, performance
attribution, input validation, unbalanced panels, and MSCI multi-country models.

**CI**

Fast two-tier GitHub Actions: ~3 min single-OS check on every push/PR,
full 4-OS matrix on main.

## Quick start

### Installation

The bundled datasets use Git LFS. Install LFS first
([instructions](https://docs.github.com/en/repositories/working-with-files/managing-large-files/installing-git-large-file-storage)),
then:

```r
# install.packages("remotes")
remotes::install_github("GreenGrassBlueOcean/FactorAnalytics")
```

Or clone and build locally:

```bash
git lfs install
git clone https://github.com/GreenGrassBlueOcean/FactorAnalytics.git
R CMD INSTALL FactorAnalytics
```

### Fundamental factor model

```r
library(FactorAnalytics)
data(stocks145scores6)

# Sector + style model
fit <- fitFfm(
  data         = stocks145scores6,
  asset.var    = "TICKER",
  ret.var      = "RETURN",
  date.var     = "DATE",
  exposure.vars = c("SECTOR", "ROE", "BP", "PM12M1M"),
  addIntercept = TRUE
)

fit                             # print summary
coef(fit)[1:5, 1:4]            # exposures (betas) for first 5 assets
head(fit$factor.returns)        # factor return time series
```

### Risk decomposition

```r
# Factor model covariance matrix
cov_mat <- fmCov(fit)

# Decompose volatility, VaR, and ES by factor
sd_dec  <- fmSdDecomp(fit)
var_dec <- fmVaRDecomp(fit)
es_dec  <- fmEsDecomp(fit)

# Percentage of each asset's VaR attributed to each factor
head(var_dec$pcVaR)
```

### Performance attribution

```r
pa <- paFm(fit)

# Cumulative return attributed to each factor, per asset
head(pa$cum.ret.attr.f)

# Time series of attributed returns for a single asset
pa$attr.list[["AAPL"]]
```

### Time series factor model

```r
data(managers, package = "PerformanceAnalytics")
colnames(managers) <- make.names(colnames(managers))

fit_ts <- fitTsfm(
  asset.names  = colnames(managers[, 1:6]),
  factor.names = colnames(managers[, 7:9]),
  mkt.name     = "SP500.TR",
  rf.name      = "US.3m.TR",
  data         = managers
)

summary(fit_ts)
fmCov(fit_ts)
```

### MSCI-type multi-country model

Models with two or more categorical exposures (e.g. sector + country) trigger
the MSCI branch, which uses restriction matrices to handle rank deficiency:

```r
# Assuming your data has SECTOR and COUNTRY character columns
fit_msci <- fitFfm(
  data          = my_data,
  asset.var     = "TICKER",
  ret.var       = "RETURN",
  date.var      = "DATE",
  exposure.vars = c("SECTOR", "COUNTRY", "ROE", "BP"),
  addIntercept  = TRUE
)

fit_msci$model.MSCI   # TRUE
fit_msci$factor.names  # Market, ROE, BP, sector levels..., country levels...
```

## Bundled datasets

| Dataset | Description |
|---------|-------------|
| `stocks145scores6` | 145 US stocks, 6 factor scores, monthly 1990–2015 |
| `factorDataSetDjia5Yrs` | 22 DJIA stocks, sector + style, monthly 2008–2013 |
| `managers` | 6 funds + 3 factors + risk-free rate (from PerformanceAnalytics) |

## Key functions

| Category | Functions |
|----------|-----------|
| **Model fitting** | `fitFfm()`, `fitTsfm()`, `fitTsfmUpDn()` |
| **Covariance** | `fmCov()` |
| **Risk decomposition** | `fmSdDecomp()`, `fmVaRDecomp()`, `fmEsDecomp()` |
| **Portfolio risk** | `portSdDecomp()`, `portVaRDecomp()`, `portEsDecomp()` |
| **Attribution** | `paFm()`, `repReturn()`, `repRisk()` |
| **Diagnostics** | `fmRsq()`, `fmTstats()`, `vif()` |
| **S3 methods** | `plot()`, `summary()`, `predict()`, `coef()` |

## Documentation

- **Vignette:** `vignette("Fundamental-Factor-Models-FactorAnalytics")` — theory
  and worked examples for fundamental factor models
- **Architecture reference:** [architecture.md](architecture.md) — call graphs,
  data flow, and implementation details
- **Refactoring log:** [AGENTS.md](AGENTS.md) — complete record of all bug fixes,
  optimizations, and phase deliverables

## Upstream

Forked from [braverock/FactorAnalytics](https://github.com/braverock/FactorAnalytics).
Original authors: Eric Zivot, Doug Martin, Sangeetha Srinivasan, Avinash Acharya,
Yi-An Chen, Mido Shammaa, Lingjie Yi, Kirk Li, and Justin M. Shea.

## License

GPL-2
