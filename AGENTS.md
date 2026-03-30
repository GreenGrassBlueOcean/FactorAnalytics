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
| **Phase 4 — Testing & Bug Fixes** | ✅ Complete | Unbalanced panel bug fixed. fmCov invariants. Coverage expansion. PA integration test. xts churn profiled → deferred. 8 pre-existing bugs fixed. 458 assertions across 19 test files, 0 failures, 0 skips. Commit `7039a0a`. |
| **Phase 5 — Input Validation** | ✅ Complete | fitFfm/specFfm dedup (8 checks consolidated). Column-existence checks in specFfm + fitTsfm. `analysis` length bug fixed. fitTsfm.control duplicate + typo fixed. 470 assertions across 19 test files, 0 failures. |
| **Phase 6 — MSCI Branch Testing** | ✅ Complete | MSCI+style extraction bug fixed. 135 MSCI-specific assertions (LS/WLS/W-Rob × pure/style, paFm, downstream methods). `print.tsfm` example fix. `return.cov`/`resid.cov`/`model.MSCI` added to ffm object. Fast CI. 605 assertions across 20 test files, 0 failures. R CMD check clean. |
| **Phase 7 — Shared model.matrix Helper** | ✅ Complete | Extracted `build_beta_star`, `build_restriction_matrix`, `apply_restriction` helpers. 3 code sites → 1 source of truth for categorical design matrix pipeline. Dead code removed (`formula.expochar`, `formulaL`, `beta.expochar`, `beta1`/`beta2` columns). 623 assertions across 21 test files, 0 failures. R CMD check clean. |
| **Phase 8 — extractRegressionStats Cleanup** | ✅ Complete | Extracted `build_factor_names` (6-way factor.names logic → 1 helper) + `map_coefficients_to_factor_returns` (sector/MSCI coefficient mapping dedup). `.()` → `list()` cleanup in `extractRegressionStats`. Dead NSE vars removed (`factor.returns1`, `factor.returns2`). 645 assertions across 22 test files, 0 failures. R CMD check clean. |
| **Phase 9 — S3 Method Consolidation** | ✅ Complete | 4 shared risk helpers (`make_beta_star`, `make_factor_star_cov`, `normalize_fm_residuals`, `make_resid_diag`) in `R/helpers-risk.R`. Integrated into 8 files / 15+ methods. `fmSdDecomp.ffm` NA-zeroing inconsistency fixed. 690 assertions across 23 test files, 0 failures. R CMD check clean. |
| **Phase 9.6 — riskDecomp Dispatcher** | ✅ Complete | `riskDecomp.R` 762→~200 lines: thin dispatcher to 6 specialized methods. Portfolio residual normalization bug eliminated from `repRisk` path. Orphaned `@importFrom` directives relocated to correct files. 67 dispatch assertions. 757 total assertions across 24 test files, 0 failures. R CMD check clean (0 errors, 0 warnings, 1 note). |

## Test Infrastructure

- **Framework:** `testthat` 3.0+ (Edition 3). Configured in `DESCRIPTION` and
  `tests/testthat.R`.
- **Fixtures:** 26 `.rds` files in `tests/testthat/fixtures/`. 16 generated from
  **unmodified** v2.4.2 upstream code by `tests/testthat/helpers/generate_fixtures.R`;
  4 added in Phase 2 for vectorized EWMA/GARCH intermediate results;
  6 portDecomp fixtures regenerated after the portfolio residual normalization
  bug fix (commit `7fc0fe3`) with corrected slot names.
  Each fixture stores only numeric components (no full `lm`/`ffm` objects).
- **Test files:** 24 files in `tests/testthat/`:
  - `test-fitFfm.R` — 5 FFM model branches + structure/dimension invariants
  - `test-fitTsfm.R` — 3 TSFM paths + manual `lm()` cross-validation
  - `test-fmCov.R` — Covariance matrices + identity verification
  - `test-riskDecomp.R` — fmSdDecomp, fmVaRDecomp, fmEsDecomp
  - `test-portDecomp.R` — Portfolio-level Sd/VaR/ES decomposition
  - `test-fmRsq.R` — R-squared computation
  - `test-fmTstats.R` — T-statistics computation
  - `test-input-validation.R` — Error handling, weight validation, column-existence checks (Phase 5)
  - `test-smoke-methods.R` — 91 smoke tests for S3 methods, plots, reporting (Phase 0.5)
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
  - `test-helpers-extract-stats.R` — 22 assertions: build_factor_names (6 model configs + round-trip), map_coefficients_to_factor_returns (sector/MSCI/pure, exact match against fitted models) (Phase 8)
  - `test-helpers-risk.R` — 33 assertions: make_beta_star (asset/portfolio/ffm), make_factor_star_cov (structure/round-trip/NULL colnames), normalize_fm_residuals (asset/portfolio correctness), make_resid_diag (multi/single asset) (Phase 9)
  - `test-riskDecomp-dispatch.R` — 67 assertions: riskDecomp dispatch equivalence (Sd/VaR/ES × asset/port × tsfm/ffm), invert convention, input validation, repRisk smoke (Phase 9.6)
- **Total:** 757 assertions across 24 test files, 0 failures, 0 skips.
- **Coverage:** 57.8% (post-Phase 9, commit `526d2c3`). Baseline was 46.4% at commit `4b58a6e`.
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
