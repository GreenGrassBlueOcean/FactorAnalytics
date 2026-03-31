# FactorAnalytics — Agent Rules

## Project Context

This is the `GreenGrassBlueOcean/FactorAnalytics` fork, a production-grade R package
for fundamental and time-series factor models. The refactoring plan and full
architecture reference are in:

- `.positai/plans/2026-03-27-2145-phased-refactoring-plan-for-greengrassblueoceanfactoranalytics-fork.md`
- `architecture.md`

## Phase Status

| Phase | Status | Exit Criterion |
|---|---|---|
| **Phase 0 — Foundation** | ✅ Complete | 0 errors, 0 warnings, 0 notes in R CMD check. 22 fixtures, 8 test files, all passing. |
| **Phase 0.5 — Smoke Tests** | ✅ Complete | 91 smoke assertions in `test-smoke-methods.R`. 254 total tests, 0 failures. Coverage: 23.4% → 46.4% (2,095 / 4,512 lines). |
| **Phase 1 — Dependency Pruning** | ✅ Complete | Imports 18 → 6; 3 packages removed (`RCurl`, `doSNOW`, `foreach`); 12 moved to Suggests. 5 pre-existing bugs fixed. R CMD check clean. |
| **Phase 2 — Performance** | ✅ Complete | 5 for-loops vectorized; `lm` objects stripped; R² extraction deduped; Robust EWMA bug fixed. 269 tests, 0 failures. Commit `3988d65`. |
| **Phase 3 — API Hardening** | ✅ Complete | `predict.ffm` newdata expansion, `char_levels` slot. 294 assertions. Commits `2f81a1e`, `fde2aee`. ||
| **Phase 4 — Testing & Bug Fixes** | ✅ Complete | Unbalanced panel bug fixed. fmCov invariants. Coverage expansion. PA integration test. xts churn profiled → closed (not a bottleneck). 8 pre-existing bugs fixed. 458 assertions across 19 test files, 0 failures, 0 skips. Commit `7039a0a`. |
| **Phase 5 — Input Validation** | ✅ Complete | fitFfm/specFfm dedup (8 checks consolidated). Column-existence checks in specFfm + fitTsfm. `analysis` length bug fixed. fitTsfm.control duplicate + typo fixed. 470 assertions across 19 test files, 0 failures. |
| **Phase 6 — MSCI Branch Testing** | ✅ Complete | MSCI+style extraction bug fixed. 135 MSCI-specific assertions (LS/WLS/W-Rob × pure/style, paFm, downstream methods). `print.tsfm` example fix. `return.cov`/`resid.cov`/`model.MSCI` added to ffm object. Fast CI. 605 assertions across 20 test files, 0 failures. R CMD check clean. |
| **Phase 7 — Shared model.matrix Helper** | ✅ Complete | Extracted `build_beta_star`, `build_restriction_matrix`, `apply_restriction` helpers. 3 code sites → 1 source of truth for categorical design matrix pipeline. Dead code removed (`formula.expochar`, `formulaL`, `beta.expochar`, `beta1`/`beta2` columns). 623 assertions across 21 test files, 0 failures. R CMD check clean. |
| **Phase 8 — extractRegressionStats Cleanup** | ✅ Complete | Extracted `build_factor_names` (6-way factor.names logic → 1 helper) + `map_coefficients_to_factor_returns` (sector/MSCI coefficient mapping dedup). `.()` → `list()` cleanup in `extractRegressionStats`. Dead NSE vars removed (`factor.returns1`, `factor.returns2`). 645 assertions across 22 test files, 0 failures. R CMD check clean. |
| **Phase 9 — S3 Method Consolidation** | ✅ Complete | 4 shared risk helpers (`make_beta_star`, `make_factor_star_cov`, `normalize_fm_residuals`, `make_resid_diag`) in `R/helpers-risk.R`. Integrated into 8 files / 15+ methods. `fmSdDecomp.ffm` NA-zeroing inconsistency fixed. 690 assertions across 23 test files, 0 failures. R CMD check clean. |
| **Phase 9.6 — riskDecomp Dispatcher** | ✅ Complete | `riskDecomp.R` 762→~200 lines: thin dispatcher to 6 specialized methods. Portfolio residual normalization bug eliminated from `repRisk` path. Orphaned `@importFrom` directives relocated to correct files. 67 dispatch assertions. 757 total assertions across 24 test files, 0 failures. R CMD check clean (0 errors, 0 warnings, 1 note). |
| **Phase 9.7 — Branch 2/3 Unification** | ✅ Complete | `extractRegressionStats` branches 2 (sector) and 3 (MSCI) unified via 2 helpers (`extract_restricted_returns`, `build_last_period_beta`). ~90 lines → ~10 lines in caller. Branch 2 column ordering fixed (`factor.returns` now matches `factor.names` for all model types). `normalize_fm_residuals` POSIXct→Date timezone bug fixed. 782 assertions across 24 test files, 0 failures, 0 warnings. |
| **Phase 10 — Risk Reporting Cleanup** | ✅ Complete | 5 repRisk.ffm bugs fixed. 340 lines orphaned `.sfm` dead code removed (4 S3 methods + `paFm` branch). `.tsfm`/`.ffm` decomposition methods deduplicated via `extract_fm_components()` + 3 shared `_impl` functions. `repRisk.R` refactored 760→461 lines via slot-lookup table + `.repRisk_impl()`. Latent `as.Date()` timezone bug fixed in `fmVaRDecomp.ffm`/`fmEsDecomp.ffm`. `missing(factor.cov)` → `NULL` default across 6 S3 methods. 831 assertions across 25 test files, 0 failures. R CMD check clean. Profiled: `portfolio.only` ~2.5× faster / ~3× less memory than full path (50ms vs 127ms, 6MB vs 19MB). |

## Test Infrastructure

- **Framework:** `testthat` 3.0+ (Edition 3). Configured in `DESCRIPTION` and
  `tests/testthat.R`.
- **Fixtures:** 26 `.rds` files in `tests/testthat/fixtures/`. 16 generated from
  **unmodified** v2.4.2 upstream code by `tests/testthat/helpers/generate_fixtures.R`;
  4 added in Phase 2 for vectorized EWMA/GARCH intermediate results;
  6 portDecomp fixtures regenerated after the portfolio residual normalization
  bug fix (commit `7fc0fe3`) with corrected slot names;
  `fixture_ffm_ls_sector.rds` regenerated in Phase 9.7 after column ordering fix
  (values identical, column order changed from `(Market, cat, style)` to
  `(Market, style, cat)` to match `factor.names`).
  Each fixture stores only numeric components (no full `lm`/`ffm` objects).
- **Test files:** 29 files in `tests/testthat/`:
  - `test-fitFfm.R` — 5 FFM model branches + structure/dimension invariants + Rob standalone + GARCH/RobustEWMA/rob.stats residual scaling + robEWMA alias + print.ffmSpec + rob.stats=TRUE covariance + weight.var z-scores (Coverage Expansion)
  - `test-fitTsfm.R` — 3 TSFM paths + DLS + stepwise + subsets + LARS cv + single-asset + manual `lm()` cross-validation (Coverage Expansion)
  - `test-fmCov.R` — Covariance matrices + identity verification
  - `test-riskDecomp.R` — fmSdDecomp, fmVaRDecomp, fmEsDecomp
  - `test-portDecomp.R` — Portfolio-level Sd/VaR/ES decomposition
  - `test-fmRsq.R` — R-squared computation
  - `test-fmTstats.R` — T-statistics computation + all 4 plot types + isPrint + style-only Branch 2 + title=FALSE (Coverage Expansion)
  - `test-input-validation.R` — Error handling, weight validation, column-existence checks (Phase 5)
  - `test-smoke-methods.R` — 161 smoke tests for S3 methods, plots, reporting. Expanded: plot.tsfm plots 12/15-17/19, DLS/Robust rolling, character f.sub/a.sub, corrplot, single-asset auto-inference, group which=3 small a.sub, group which=12 ≥5 assets, CUSUM non-LS errors, multi-factor which=19/12 errors, bad a.sub/f.sub errors; plot.ffm character a.sub/f.sub, corrplot, single-asset error, group which=3 small a.sub, single-factor f.sub auto-set, bad a.sub/f.sub errors; repReturn named weights, titleText=FALSE; repExposures named/unnamed weights, non-ffm error, titleText=FALSE, style-only model, single-numeric which=3, multi-which (Coverage Expansion)
  - `test-vectorize.R` — 15 assertions: EWMA/GARCH vectorization, Robust EWMA, stripped `lm` (Phase 2)
  - `test-unbalanced-panel.R` — 26 assertions: synthetic unbalanced panel (Phase 4.1)
  - `test-fmCov-invariants.R` — ~60 assertions: 6 invariants × 8 model configs (Phase 4.2)
  - `test-CornishFisher.R` — 8 assertions: CF expansion mathematical properties (Phase 4.3)
  - `test-portVolDecomp.R` — 11 assertions: portfolio volatility decomposition (Phase 4.3)
  - `test-vif.R` — 3 assertions: variance inflation factors (Phase 4.3)
  - `test-paFm.R` — 20 assertions: performance attribution TSFM + FFM + plots (Phase 4.3)
  - `test-fitTsfmUpDn.R` — 12 assertions: up/down market timing model (Phase 4.3)
  - `test-roll-fitFfmDT.R` — 2 assertions: rolling-window FFM smoke test (Phase 4.3)
  - `test-integration-pa.R` — 20 assertions: PortfolioAnalytics integration simulation (Phase 4.4)
  - `test-fitFfm-msci.R` — 135 assertions: MSCI model: LS/WLS/W-Rob × pure/style, downstream fmCov/VaR/ES, paFm decomposition identity, plot/print/summary (Phase 6)
  - `test-helpers-design-matrix.R` — 18 assertions: build_beta_star, build_restriction_matrix, apply_restriction unit tests + round-trip vs expand_newdata_ffm (Phase 7)
  - `test-helpers-extract-stats.R` — 47 assertions: build_factor_names (6 model configs + round-trip), map_coefficients_to_factor_returns (sector/MSCI/pure, exact match against fitted models) (Phase 8), extract_restricted_returns + build_last_period_beta structure tests, colnames(factor.returns)==factor.names invariant for all model types (Phase 9.7)
  - `test-helpers-risk.R` — 33 assertions: make_beta_star (asset/portfolio/ffm), make_factor_star_cov (structure/round-trip/NULL colnames), normalize_fm_residuals (asset/portfolio correctness), make_resid_diag (multi/single asset) (Phase 9)
  - `test-riskDecomp-dispatch.R` — 67 assertions: riskDecomp dispatch equivalence (Sd/VaR/ES × asset/port × tsfm/ffm), invert convention, input validation, repRisk smoke (Phase 9.6)
  - `test-repRisk.R` — 29 assertions: repRisk baseline smoke (tsfm+ffm), S3 dispatch, bug regressions (5 bugs), decomp×risk structure checks, plot paths (Phase 10)
  - `test-fmmc.R` — 51 assertions: fmmc() structure + Cartesian join regression + fmmc.estimate.se() with/without SE + .fmmc.default.args + fmmcSemiParam() Normal/Cornish-Fisher/skew-t/empirical residuals + block bootstrap + input validation (Post-Phase 10)
  - `test-assetDecomp.R` — 32 assertions: assetDecomp() Sd/VaR/ES × np/normal decomposition, structure checks, percentage-sums-to-100, ES≤VaR ordering (incl. normal ES sign regression), NULL/equal weights, slot-based column access (Post-Phase 10)
  - `test-residualizeReturns.R` — 46 assertions: residualizeReturns() core functionality (yVar update, flags, column merge, variance reduction), isBenchExcess toggle, immutability, error paths (non-xts, missing colnames), print.ffmSpec conditional messages (residualized/standardized/both), end-to-end fitFfmDT pipeline on residualized specObj; standardizeReturns() GARCH(1,1) output structure, ret/sigma identity, manual recursion verification, positivity, custom params, immutability, end-to-end pipeline; lagExposures() shift verification (numeric + character), first-period drop, flag/key/idx preservation, immutability (Post-Phase 10)
  - `test-fitTsfmLagLeadBeta.R` — 24 assertions: fitTsfmLagLeadBeta() lag-only/lag+lead models (LagLeadBeta=1,2), rf.name=NULL, rf.name bug regression, error paths (missing mkt.name, invalid LagLeadBeta), S3 method compatibility (Post-Phase 10)
  - `test-selectCRSPandSPGMI.R` — 15 assertions: selectCRSPandSPGMI() structure/filtering (date range, CapGroup, Sector NA removal), LargeCap+Nstocks params, end-to-end fitFfm pipeline (Post-Phase 10, requires PCRA)
  - `test-coverage-expansion.R` — 77 assertions: fitTsfmMT, summary.tsfm HC/HAC/lars/labels, summary.tsfmUpDn+print, summary.ffm labels=FALSE, predict.tsfm newdata, predict.ffm pred.date+backward compat, fmVaRDecomp/fmEsDecomp type="normal", fmRsq barplot/title/combined, plot.pafm which.plot paths, plot.tsfmUpDn SFM.line+LSandRob (LS+Robust originals)+Robust-only legend, portSdDecomp user factor.cov, exposuresTseries (Post-Phase 10)
- **Total:** 1219 assertions across 31 test files, 0 failures, 2 skips (interactive `par(ask)` test, single-asset ffm not constructible).
- **Coverage:** 80.0% (Codecov, commit `84ac63f`). Previously 68.4% at Phase 10 end, 57.8% at Phase 9 commit `526d2c3`. Baseline was 46.4% at commit `4b58a6e`.
- **Tolerances:** Coefficients/factor returns `1e-10`, covariance `1e-8`, risk decomp `1e-6`.
- **Setup:** `tests/testthat/setup.R` loads all bundled datasets and prepares the
  `dat145` subset used across multiple test files.

## Known Bugs (Discovered & Fixed)

### `portVaRDecomp()` / `portEsDecomp()` wrong portfolio residual normalization — FIXED

**Severity:** High — systematically distorts factor vs. residual risk attribution.

The augmented factor model decomposes portfolio return as:
`R_p(t) = beta_p' f(t) + sigma_p * z(t)`
where `z(t) = e_p(t) / sigma_p`, `e_p(t) = sum(w_i * e_it)`, and
`sigma_p = sqrt(sum(w_i^2 * sigma_i^2))`.

The upstream code computed the residual pseudo-factor as:
`z(t) = sum(w_i * (e_it / sigma_i))`  ← WRONG (normalizes per-asset, then sums)

The correct formula is:
`z(t) = sum(w_i * e_it) / sqrt(sum(w_i^2 * sigma_i^2))`  ← CORRECT (sums raw, then normalizes)

**Numerical impact (managers dataset, equal-weight portfolio):**
- `Var(z_upstream)` ≈ 0.13 (should be ~1.0 for a unit-variance pseudo-factor)
- `Var(z_correct)` ≈ 0.78 (close to 1.0; <1 due to NAs and finite sample)
- Residual pcVaR: 23% (upstream) → 47% (correct) — a 24 percentage point shift

**Affected code:** 4 methods in 2 files:
- `portVaRDecomp.tsfm()` and `portVaRDecomp.ffm()` in `R/portVaRDecomp.R`
- `portEsDecomp.tsfm()` and `portEsDecomp.ffm()` in `R/portEsDecomp.R`

**NOT affected:**
- Asset-level decomposition (`fmSdDecomp`, `fmVaRDecomp`, `fmEsDecomp`)
- `portSdDecomp` (uses portfolio beta directly, not weighted residuals)
- Model fitting (`fitTsfm`, `fitFfm`) — fitting is correct

**Fix (applied):** In all 4 methods, replaced:
```r
resid.xts <- xts::as.xts(t(t(residuals(object))/object$resid.sd) %*% weights)
```
with:
```r
resid.xts <- xts::as.xts(
  zoo::coredata(residuals(object)) %*% weights / beta.star[1, "Residuals"],
  order.by = zoo::index(residuals(object))
)
```
where `beta.star[1, "Residuals"]` is `sigma_p = sqrt(sum(w^2 * sigma^2))`,
already computed earlier in the function.

**Additional fix:** The `test-portDecomp.R` fixture names were mismatched
(`$VaR.fm` vs actual `$portVaR`, etc.), causing 6 out of 24 fixture assertions
to silently compare `NULL` to `NULL`. Corrected fixture names and regenerated
all 6 portDecomp fixtures.

### `fmCov()` fails on FFM fits with character exposures (sector models) — FIXED

`fmCov.ffm()` did `object$data[, object$factor.names]`. For sector models,
`factor.names` contains factor level names (e.g., `"COSTAP"`, `"ENERGY"`) rather than
column names. This caused `"undefined columns selected"`.

**Fix (applied):**
- `R/fmCov.R`: Deferred factor extraction into the `if (is.null(factor.cov))` block
  and switched from `object$data` to `object$factor.returns`.
- `R/fitFfmDT.R`: Added missing `rownames(beta) <- asset.names` in the
  `addIntercept = TRUE` + sector+style code path (line ~913). This was the root cause
  of both wrong dimension names on `fmCov` output and `"subscript out of bounds"` in
  `fmVaRDecomp.ffm` / `fmEsDecomp.ffm`.
- The `.ffm` methods for `fmSdDecomp`, `fmVaRDecomp`, and `fmEsDecomp` already used
  `object$factor.returns` correctly; no changes needed.
- Updated `fixture_ffm_ls_sector.rds` to reflect corrected `rownames(beta)`.
- Added regression tests in `test-fmCov.R` (2 tests) and `test-riskDecomp.R` (1 test).

### `fitTsfm()` excess return convention

`fitTsfm()` subtracts `rf` from **both** asset returns **and** factor returns before
fitting. This is important for cross-validation: manual `lm()` replication must also
subtract rf from both the response and the regressors.

### `extractRegressionStats()` unbalanced panel dimension mismatch — FIXED (Phase 4)

`extractRegressionStats()` set `asset.names <- unique(specObj$data[[specObj$asset.var]])`
(ALL unique assets ever in the dataset), but later filtered residuals to `a_last`
(last-period assets only). On unbalanced panels with delistings, `beta` had more rows
than `residuals` columns, breaking downstream `fmCov` and risk decomposition.

**Fix:** Deleted the early `asset.names` assignment. After `a_last` is computed (line
~821), set `asset.names <- a_last`. All three `rownames(beta) <- asset.names` calls
now use the last-period asset set. Balanced panels are unaffected.

### `calcAssetWeightsForRegression` Robust EWMA used wrong column — FIXED (Phase 2)

The Robust EWMA branch referenced `resid.DT$var` (non-existent column) instead of
`resid.DT$resid.var`. Since `data.table` `$` does not partial-match, the expression
returned `NULL`, making all Robust EWMA weights `NA`.

**Fix:** Changed `resid.DT$var` → `resid.DT$resid.var` in the Robust EWMA path of
`calcAssetWeightsForRegression()`.

### `paFm.ffm()` broken slot names and blind intercept drop — FIXED (Phase 4)

`paFm.ffm()` used legacy slot names (`fit$assetvar`, `fit$returnsvar`,
`fit$exposure.names`) that don't exist on the current `fitFfm` object. It also did
`fit$factor.returns[, -1]` assuming the first column is always an intercept; for
style-only models (no intercept column) this silently dropped the first real factor.

**Root causes:**
- `fit$assetvar` → should be `fit$asset.var`
- `fit$returnsvar` → should be `fit$ret.var`
- `fit$exposure.names` → should be `fit$exposure.vars`
- `factor.returns[, -1]` → conditional: only drop if `"(Intercept)"` column exists
- Industry factor detection used positional indexing (`[-(1:n)]`), which assumed numeric
  factors come first in `colnames(beta)`. They actually come last.

**Fix (applied to `R/paFm.r`):**
- Conditional intercept drop: only removes `"(Intercept)"` column by name.
- Corrected all slot references to current API.
- Replaced positional industry factor indexing with name-based: `setdiff(factor.names, num.f.names)`.
- Hoisted `num.f.names` and `has.industry` out of the per-asset loop (invariant).
- Added `exposure[, factor.names, drop = FALSE]` reordering to ensure column alignment
  with `factor.returns` before element-wise multiplication.

### `plot.pafm()` column-select on `cum.spec.ret` data.frame — FIXED (Phase 4)

`plot.pafm()` indexed `x$cum.spec.ret[i]` where `i` is an asset name like `"HAM1"`.
Since `cum.spec.ret` is a 1-column data.frame (from TSFM) or a named vector (from FFM),
`[i]` performed column-select on the data.frame case, failing with "undefined columns
selected".

**Fix (applied to `R/plot.pafm.r`):**
- Added type normalization at function entry: converts `cum.spec.ret` to a named numeric
  vector regardless of input type (data.frame or vector).
- Also wrapped `cum.ret.attr.f[i,]` in `unlist()` to prevent `c()` producing a list
  when concatenating a scalar with a data.frame row.

### `fitFfm()` `analysis` parameter length check — FIXED (Phase 5)

Line 294 checked `length(z.score) != 1` instead of `length(analysis) != 1`. The
`analysis` parameter's length was never validated.

**Fix:** Changed `length(z.score)` → `length(analysis)`.

### `fitFfm()` / `specFfm()` duplicate validation — FIXED (Phase 5)

8 identical input checks (data, asset.var, date.var, ret.var, exposure.vars,
ret.var-in-exposure.vars, weight.var, rob.stats) were duplicated between `fitFfm()`
and `specFfm()`. Since `fitFfm()` calls `specFfm()`, every check ran twice.

**Fix:** Removed the 8 duplicate checks from `fitFfm()`. `specFfm()` is now the
single validation authority for shared parameters. Added column-existence check in
`specFfm()` that validates all referenced columns exist in `data`.

### `fitTsfm()` missing column-existence validation — FIXED (Phase 5)

`fitTsfm()` had no checks for whether `asset.names`, `factor.names`, `mkt.name`, or
`rf.name` columns exist in `data`. Bad column names produced cryptic errors from
`xts` subsetting or `lm()` internals.

**Fix:** Added early column-existence validation for all four parameters, with clear
error messages naming the missing column(s).

### `fitTsfm.control()` duplicate `normalize` check and typo — FIXED (Phase 5)

The `normalize` parameter was validated twice (lines 266–267 and 279–281). The error
message on line 276 had a typo: "Invaid" instead of "Invalid".

**Fix:** Removed the duplicate check; corrected the typo.

### `extractRegressionStats()` MSCI+style non-conformable matrix multiplication — FIXED (Phase 6)

The MSCI branch of `extractRegressionStats()` (triggered when 2+ character exposures
are present) computed `K <- length(factor.names) - length(exposures.char)` and then
did `R_matrix %*% g[1:K]`. When numeric (style) exposures were also present, `K`
included those coefficients, making `g[1:K]` longer than `ncol(R_matrix)`. This caused
`"non-conformable arguments"` on any MSCI model with style variables.

Additionally, the MSCI beta exposure matrix (`beta.mic`) only contained the Market
intercept and categorical dummies — style exposure columns were missing. And
`restriction.mat` was never assigned (stayed `NULL`).

**Root causes:**
- `K` conflated categorical and style coefficient counts
- Style coefficients were not separated before R_matrix multiplication
- `beta` lacked style exposure columns
- `restriction.mat` not set in MSCI branch

**Fix (applied to `R/fitFfmDT.R`, `extractRegressionStats()` MSCI branch):**
- Replaced `K` with `K_cat = K1 + K2 - 1` (exactly `ncol(R_matrix)`)
- When `exposures.num > 0`: separates `g[1:K_cat]` (categorical) from
  `g[(K_cat+1):end]` (style), multiplies only categorical by R_matrix, reorders
  to match `factor.names` ordering (Market, style, categorical levels)
- Appends style exposure columns to `beta` with matching column order
- Sets `restriction.mat <- R_matrix` from last period

### `print.tsfm` roxygen example missing `make.names()` — FIXED (Phase 6)

The `print.tsfm` example used `mkt.name="SP500.TR"` but loaded `managers` without
`make.names()`. The column name is `"SP500 TR"` (with space). Phase 5's column-existence
check in `fitTsfm()` exposed this (previously it silently fell through).

**Fix:** Added `colnames(managers) <- make.names(colnames(managers))` to the example.

### `fmSdDecomp.ffm()` missing NA-zeroing in beta — FIXED (Phase 9)

`fmSdDecomp.ffm()` was the only risk decomposition method that did **not** do
`beta[is.na(beta)] <- 0` before constructing `beta.star`. All other methods (`.tsfm`,
`.sfm`, and all VaR/ES methods) zeroed NAs consistently.

**Fix:** Resolved automatically by switching to `make_beta_star()`, which always zeros
NAs internally.

### `normalize_fm_residuals()` POSIXct→Date timezone shift — FIXED (Phase 9.7)

`normalize_fm_residuals()` converted the residual index to Date via
`as.Date(zoo::index(z_xts))`. When the input had a `POSIXct` index with empty timezone
attribute (common for `tsfm` residuals from the `managers` dataset), `as.Date()` used
UTC, shifting dates back by one day on non-UTC systems. This caused `merge()` in
`portVaRDecomp.tsfm` and `fmVaRDecomp.tsfm` to see completely non-overlapping date
indices (132 + 120 = 252 rows instead of ~132), triggering "longer object length is not
a multiple of shorter object length" warnings and producing incorrect kernel-weighted
marginal VaR/ES estimates.

**Fix:** Detect `POSIXct` index and use the stored timezone (or `Sys.timezone()` when
the attribute is empty) for the `as.Date()` conversion.

### `extractRegressionStats()` Branch 2 column ordering inconsistency — FIXED (Phase 9.7)

Branch 2 (sector + intercept) of `extractRegressionStats()` built `fr_col_names` as
`c("Market", cat_levels, style)` while `factor.names` (from `build_factor_names()`) was
`c("Market", style, cat_levels)`. This mismatch required the post-hoc column reordering
hack at lines 1128-1137 to realign `beta` with `factor.returns`. Branch 3 (MSCI) used
`factor.names` directly and had no mismatch.

**Fix:** Unified branches 2 and 3 into a single code path using `factor.names` for
column ordering. The post-hoc cleanup code is now a no-op for intercept models.

### `.fmmc.proc()` Cartesian join in residual-factor merge — FIXED

**Severity:** Medium — produced incorrect Monte Carlo return distributions.

`.fmmc.proc()` at line 115 did:
```r
.data <- as.matrix(merge(as.matrix(factors.data), resid))
```
`as.matrix(factors.data)` stripped the xts class, so `merge()` dispatched to
`merge.data.frame`. With no shared column names between the factor matrix and
residual xts, this produced a Cartesian (cross) join: `T_factors × T_resid` rows
instead of `T` rows. The resulting `returns` matrix had `T^2` entries, making the
joint empirical density meaningless.

**Root causes (3 sites):**
1. `as.matrix()` before `merge()` strips the xts time index (line 115)
2. `as.matrix(factors.data[...])` in the NA-beta branch (line 110) also strips xts
3. `fitTsfm()` line 253: `as.Date(time(data.xts))` defaults to UTC, shifting dates
   by 1 day on non-UTC systems (same timezone pattern as Phase 9.7). This caused
   `merge.xts` to see non-overlapping Date vs POSIXct indices even after fixing (1).

**Fix (applied to 3 files):**
- `R/fmmc.R` line 110: Removed `as.matrix()`, added `drop = FALSE` to preserve xts.
- `R/fmmc.R` line 115: Removed inner `as.matrix()`. Added POSIXct→Date index
  conversion on `resid` (timezone-aware) before `merge()`.
- `R/fitTsfm.R` lines 253, 591: Replaced `as.Date(time(data.xts))` with
  timezone-aware conversion (`as.Date(idx, tz = tz)` where tz is sourced from
  the POSIXct attribute or `Sys.timezone()` as fallback).

### `assetDecomp()` normal ES sign bug — FIXED

**Severity:** Medium — normal-distribution ES had wrong sign.

`assetDecomp()` computed normal ES as:
```r
RM = drop(t(weights) %*% (apply(returns, 2, mean)) + port.Sd * dnorm(qnorm(p)) * (1/p))
```
The `+` should be `-`. For p = 0.05, `dnorm(qnorm(0.05)) / 0.05 ≈ 2.063`, so the
formula gave `mean + 2.063 * sigma` (positive) instead of `mean - 2.063 * sigma`
(negative, more extreme than VaR). The same sign error affected the marginal
component risk formula.

**Fix:** Changed `+` to `-` on both the portfolio ES (line 100) and marginal
component risk (line 101) formulas.

**Not affected:** Non-parametric ES (uses empirical quantiles, was always correct).

### `assetDecomp()` hard-coded column names — FIXED

`assetDecomp()` hard-coded `object$data[,"RETURN"]` and `object$data[,"DATE"]`
instead of using `object$ret.var` and `object$date.var`. This meant the function
only worked with datasets where the return column was literally named "RETURN" and
the date column "DATE" (e.g., `factorDataSetDjia5Yrs`).

**Fix:** Replaced `"RETURN"` → `object$ret.var` and `"DATE"` → `object$date.var`
on lines 53–54.

### `fitTsfm()` `as.Date()` timezone shift — FIXED

**Severity:** Low–Medium — date labels on all tsfm output shifted by 1 day on
non-UTC systems. Values unaffected.

`fitTsfm()` line 253 did `time(data.xts) <- as.Date(time(data.xts))`. The
`as.Date.POSIXct` method defaults to `tz = "UTC"`, so on a CET system,
midnight-CET dates (23:00 previous day UTC) shifted back by one day. Same pattern
on line 591 (`fitted.tsfm`).

**Fix:** Detect POSIXct index and use the stored timezone (or `Sys.timezone()` when
the attribute is empty) for the `as.Date()` conversion. Same pattern as the
Phase 9.7 fix in `normalize_fm_residuals`.

### `fitFfm()` `resid.scaleType` naming mismatch (`"robEWMA"` vs `"RobustEWMA"`) — FIXED

**Severity:** Medium — RobustEWMA residual scaling was completely unreachable through
the public `fitFfm()` API.

`fitFfm()` validated `resid.scaleType` against `c("stdDev","EWMA","robEWMA","GARCH")`.
`fitFfmDT()` and `calcAssetWeightsForRegression()` both did `toupper(resid.scaleType)`
then `match.arg()` against `c("STDDEV","EWMA","ROBUSTEWMA","GARCH")`. Since
`toupper("robEWMA")` = `"ROBEWMA"` ≠ `"ROBUSTEWMA"`, any user passing `"robEWMA"`
through `fitFfm()` got a cryptic `match.arg` error from `fitFfmDT()`.

**Fix (applied to `R/fitFfm.R`):**
- Changed `fitFfm()` validation to use `tolower()` matching, accepting both
  `"robEWMA"` (legacy) and `"RobustEWMA"` (canonical).
- Added normalization: `"robEWMA"` → `"RobustEWMA"` before passing to `fitFfmDT()`.
- Also made the `resid.scaleType != "stdDev"` guard case-insensitive.

### `plot.ffm()` / `plot.tsfm()` character `a.sub` assignment bug — FIXED

**Severity:** Low — character asset subsetting in group plots silently overwrote
`f.sub` instead of `a.sub`, producing wrong factor subsetting.

Both `plot.ffm.R` line 349 and `plot.tsfm.R` line 447 had:
```r
if (is.character(a.sub)) {
  f.sub <- which(x$asset.names==a.sub)   # BUG: should be a.sub <-
}
```
This assigned the asset index to `f.sub` (factor subset) instead of `a.sub` (asset
subset). The bug was latent because all tests used numeric indices.

**Fix:** Changed `f.sub <-` to `a.sub <-` and `==` to `%in%` (to support vector input)
in both files.

### `specFfm()` drops `weight.var` column from `dataDT` — FIXED

**Severity:** Medium — `weight.var` functionality was completely broken.

`specFfm()` line 317 selected only `c(date.var, asset.var, ret.var, exposure.vars)`
into `dataDT`, omitting `weight.var`. When `standardizeExposures()` later did
`dataDT[, w := get(weight.var)]`, it failed with "object not found" because the
column wasn't in the data.table.

**Fix:** Added `weight.var` to `keep_cols` when non-NULL before subsetting.

### `plot.ffm()` group which=3 undefined `asset.variable` — FIXED

**Severity:** Medium — group "Actual and Fitted" plot was completely broken.

`plot.ffm.R` line 402 used `get(asset.variable)` where `asset.variable` is a
function parameter with no default value. It should be `x$asset.var` (a slot on
the ffm object). Any call to `plot(ffm_obj, which = 3)` failed with
`"argument 'asset.variable' is missing, with no default"`.

**Fix:** Changed `get(asset.variable)` → `get(x$asset.var)`.

### `fitFfm()` `stdReturn=TRUE` was a no-op — FIXED

**Severity:** Medium — GARCH return standardization never took effect.

`fitFfm.R` line 304 called `standardizeReturns(specObj = spec1, ...)` without
assigning the result back to `spec1`. Since `standardizeReturns()` returns a
modified copy (it uses `data.table::copy()` internally), the original `spec1`
was unchanged and the model was always fit on raw returns regardless of
`stdReturn`.

**Fix:** Changed to `spec1 <- standardizeReturns(specObj = spec1, ...)`.

### `fitTsfmLagLeadBeta()` `rf.name` overwritten by `mkt.name` — FIXED

**Severity:** Medium — risk-free rate adjustment was always wrong when `rf.name`
was provided.

`fitTsfmLagLeadBeta.r` line 127 had:
```r
rf.name <- make.names(mkt.name)   # BUG: should be make.names(rf.name)
```

This set `rf.name` to the market factor name, so `fitTsfm()` subtracted the market
return instead of the risk-free rate from both assets and factors. The resulting
excess returns and alphas were systematically wrong.

**Fix:** Changed to `rf.name <- if (!is.null(rf.name)) make.names(rf.name) else NULL`,
also handling the `rf.name = NULL` case correctly.

### `plot.tsfmUpDn()` LSandRob path: 3 bugs — FIXED

**Severity:** Medium — the entire LSandRob comparison feature was broken, plus the
Robust-only legend path crashed unconditionally.

**Bug 1 — `eval(x$call)` fails outside original call environment** (line 88):
`fitTsfmUpDn()` stores `match.call()`, which captures literal expressions (e.g.,
`colnames(managers[,(1:6)])`). `plot.tsfmUpDn()` modified `x$call$fit.method` then
did `eval(x$call)` to refit with the alternative method. This fails because the
symbols from the original call context (like `managers`) aren't available inside the
plot method's environment.

**Bug 2 — Legend labels swapped when original model is Robust** (lines 150-154):
When the original model used `"Robust"` and the alternative was `"LS"`, the else
branch labeled `up.beta.alt` (from the LS model) as `"BetaRob"` and `up.beta`
(from the Robust model) as `"Beta"` — backwards.

**Bug 3 — Undefined `up.beta.alt`/`dn.beta.alt` when `LSandRob=FALSE` + Robust**
(lines 159-161): The non-LSandRob legend path for Robust models referenced
`up.beta.alt` and `dn.beta.alt`, which are only defined inside the `if (LSandRob)`
block. Any call to `plot(fit_robust, LSandRob=FALSE)` crashed with "object not found".

**Additional cosmetic fix:** `seq=""` (a no-op typo for `sep=""` in `paste()`) replaced
with `paste0()` throughout the legend code.

**Fix (applied to `R/plot.tsfmUpDn.r`):**
- Replaced `eval(x$call)` with direct `fitTsfmUpDn()` call using stored object data
  (`x$data` already has excess returns applied, so `rf.name=NULL`).
- Rewrote legend block: uses `x$Up$fit.method` to determine `orig.label` and
  `alt.label`, with correct assignment of `"Beta"`/`"BetaRob"` to original vs
  alternative model betas.
- Non-LSandRob path now only references `up.beta`/`dn.beta` (always defined).

## Performance Optimisations (Phase 2)

### `strip_lm()` — Memory-safe lm object storage

`fitFfmDT()` stores one `lm()` object per cross-section date. Each `lm` silently
captures the formula environment (pointer to the parent `data.table`), `$x`, `$y`, and
other heavy slots. At STOXX 1800 scale this creates ~120 hidden copies of the panel.

`strip_lm()` (defined in `fitFfmDT.R`) neutering after each fit:
- Sets `$call` to `call("lm")` (prevents refitting)
- Severs `.Environment` via `baseenv()` (breaks reference to parent data)
- Removes `$x` and `$y`
- Keeps `$model` (required by `predict.lm()` without `newdata`)

Applied at all 4 regression call sites (LS, ROB, WLS, W-Rob).

### Vectorized EWMA/GARCH recursions

All 5 row-by-row `set()` for-loops in `fitFfmDT.R` replaced:
- Loops #1–3, #5 → `stats::filter(method = "recursive")` (C-level)
- Loop #4 (Robust EWMA) → `Reduce(accumulate = TRUE)` (conditional recursion
  incompatible with `stats::filter`)

### R² extraction dedup

`convert.ffmSpec()` now reads `RegStatsObj$r2` directly instead of re-calling
`summary()` on every stored `lm` object.

### xts Conversion Churn — CLOSED (Not a bottleneck)

Profiling on `stocks145scores6` (145 assets × 300 months, WLS + EWMA sector model)
shows all `as.xts.data.table()` calls in `extractRegressionStats` combined cost ~5ms
(0.4% of `fitFfm()` wall time). The fitting loop (`fitFfmDT`) dominates at 87% of
wall time, with `lm()` × 300 cross-sections accounting for 48%. Within
`extractRegressionStats`, the real bottleneck is `data.frame()` construction in
data.table j-expressions (15% of total), not xts conversion. See `architecture.md`
Section 4.7 for the full breakdown. Future performance work should target `lm()` →
`.lm.fit()` or vectorized `:=` column extraction.

### repRisk `portfolio.only` Performance (Phase 10)

Profiled on `stocks145scores6` (145 assets × 60 months, WLS sector model) with
`wtsStocks145GmvLo` weights. 20 iterations via `bench::mark()`.

- **Full path** (asset + portfolio, 1 risk): 126.5 ms median, 18.8 MB
- **`portfolio.only`** (1–3 risks): ~50 ms median, 6.0 MB
- **Speedup:** ~2.5× faster, ~3× less memory

Asset-level VaR/ES is the bottleneck (130 ms, 16 MB per call); Sd decomposition
is negligible (<0.2 ms). The `portfolio.only` path avoids the 145-asset loop entirely.

**Known opportunity:** `portfolio.only` always computes all 3 risk types then filters.
For `risk = "Sd"` only, this wastes ~50 ms on unnecessary VaR/ES.
See `architecture.md` Section 4.7.1 for full breakdown.

## R Package Standards

- Use `testthat` (>= 3.0.0) for testing.
- Use roxygen2 for documentation.
- All code must pass `R CMD check` with 0 errors, 0 warnings.

## data.table Programming Rules

These rules are **mandatory** for all `data.table` code in this package. They exist to
ensure clean `R CMD check` results, predictable semantics, and zero reliance on
non-standard evaluation tricks that break in production.

### 1. Use `list()`, never `.()` shorthand

`.()` is an alias for `list()` inside `data.table` expressions but is harder to grep,
harder to read for non-data.table users, and creates ambiguity with other uses of `.`
in R (e.g., formula notation, magrittr placeholder).

```r
# WRONG
dt[, .(mean_ret = mean(ret)), by = .(date, sector)]

# CORRECT
dt[, list(mean_ret = mean(ret)), by = list(date, sector)]
```

### 2. Use `.SD` / `.SDcols`, never `..` prefix notation

The `..` prefix (`dt[, ..cols]`) is a convenience that silently reaches into the parent
scope. Use `.SD` with `.SDcols` for explicit, traceable column selection.

```r
# WRONG
cols <- c("ret", "mktcap")
dt[, ..cols]

# CORRECT
cols <- c("ret", "mktcap")
dt[, .SD, .SDcols = cols]
```

### 3. Declare NSE variables in function body to suppress R CMD check NOTEs

Any symbol used inside `data.table`'s `j` or `by` expressions that is not a column
name visible to the R parser will trigger a "no visible binding for global variable"
NOTE. Declare them as `NULL` at the top of the function body.

```r
myFunction <- function(dt) {
  # Due to NSE notes related to data.table in R CMD check
  ret <- mktcap <- sector <- NULL

  dt[, list(mean_ret = mean(ret)), by = sector]
}
```

Group all NSE declarations together, with a comment explaining why they exist.

### 4. No global variables — ever

Do not assign to or read from the global environment. All state must be passed through
function arguments and return values. No `<<-`, no `assign(..., envir = .GlobalEnv)`,
no `get()` on global names.

If you find yourself reaching for a global, you are missing a function parameter.

### 5. No Cartesian joins

Cartesian (cross) joins are **forbidden**. If a `data.table` merge or join produces
more rows than the larger of the two inputs, the logic is wrong.

A Cartesian join is almost always a symptom of:
- Missing or incorrect join keys
- Duplicate keys in one or both tables
- A flawed algorithm that should use a grouped operation instead

```r
# WRONG — will silently produce N×M rows
result <- dt1[dt2, on = "date", allow.cartesian = TRUE]

# If you think you need a Cartesian join, restructure the problem:
# - Add the missing key column
# - Deduplicate before joining
# - Use a grouped operation (by =) instead of a join
```

If `allow.cartesian = TRUE` appears anywhere in the codebase, it is a bug.

### 6. Prefer `setkeyv()` over `setkey()` for programmatic column names

When column names are stored in variables (which is common in this package via
`specObj$date.var`, `specObj$asset.var`, etc.), always use `setkeyv()`:

```r
# WRONG (only works with literal column names)
setkey(dt, date, asset)

# CORRECT (works with variable column names)
d_ <- specObj$date.var
a_ <- specObj$asset.var
setkeyv(dt, c(a_, d_))
```

### 7. Use `set()` only for scalar updates; prefer vectorized `:=` otherwise

The `set()` function is designed for updating individual cells by reference. Do not use
it inside `for` loops to iterate row-by-row over a data.table — this defeats the
purpose of data.table's vectorized engine.

```r
# WRONG — row-by-row loop
for (i in 1:nrow(dt)) {
  set(dt, i, "sigma2", lambda * dt$sigma2[i - 1] + (1 - lambda) * dt$x[i])
}

# CORRECT — vectorized recursive filter
dt[, sigma2 := as.numeric(
  stats::filter(x = (1 - lambda) * x, filter = lambda,
                method = "recursive", init = init_val)
), by = asset_id]
```

### 8. Use `get()` or `.SD` for programmatic column access in `j`, not bare strings

```r
# WRONG — returns the string, not the column values
dt[, "ret"]

# CORRECT options
dt[, get(ret_var)]
dt[, .SD, .SDcols = ret_var]
```

### 9. Always copy before modifying by reference if the input should not mutate

`data.table` modifies in place. If a function receives a `data.table` and should not
alter the caller's copy, use `data.table::copy()` before any `:=` or `set()` calls.

```r
myFunction <- function(dt) {
  dt <- data.table::copy(dt)
  dt[, new_col := 1]
  dt
}
```
