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
| **Phase 3 — API Hardening** | 🔲 Not started | Unbalanced panel tests pass. `fmCov` dimensionality verified. ||

## Test Infrastructure

- **Framework:** `testthat` 3.0+ (Edition 3). Configured in `DESCRIPTION` and
  `tests/testthat.R`.
- **Fixtures:** 26 `.rds` files in `tests/testthat/fixtures/`. 22 generated from
  **unmodified** v2.4.2 upstream code by `tests/testthat/helpers/generate_fixtures.R`;
  4 added in Phase 2 for vectorized EWMA/GARCH intermediate results.
  Each fixture stores only numeric components (no full `lm`/`ffm` objects).
- **Test files:** 10 files in `tests/testthat/`:
  - `test-fitFfm.R` — 5 FFM model branches + structure/dimension invariants
  - `test-fitTsfm.R` — 3 TSFM paths + manual `lm()` cross-validation
  - `test-fmCov.R` — Covariance matrices + identity verification
  - `test-riskDecomp.R` — fmSdDecomp, fmVaRDecomp, fmEsDecomp
  - `test-portDecomp.R` — Portfolio-level Sd/VaR/ES decomposition
  - `test-fmRsq.R` — R-squared computation
  - `test-fmTstats.R` — T-statistics computation
  - `test-input-validation.R` — Error handling, weight validation
  - `test-smoke-methods.R` — 91 smoke tests for S3 methods, plots, reporting (Phase 0.5)
  - `test-vectorize.R` — 15 assertions: EWMA/GARCH vectorization, Robust EWMA, stripped `lm` (Phase 2)
- **Total:** 269 assertions across 10 test files, 0 failures.
- **Coverage:** 46.4% (2,095 / 4,512 lines). Baseline established on commit `4b58a6e`.
- **Tolerances:** Coefficients/factor returns `1e-10`, covariance `1e-8`, risk decomp `1e-6`.
- **Setup:** `tests/testthat/setup.R` loads all bundled datasets and prepares the
  `dat145` subset used across multiple test files.

## Known Bugs (Discovered During Phase 0)

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

### `calcAssetWeightsForRegression` Robust EWMA used wrong column — FIXED (Phase 2)

The Robust EWMA branch referenced `resid.DT$var` (non-existent column) instead of
`resid.DT$resid.var`. Since `data.table` `$` does not partial-match, the expression
returned `NULL`, making all Robust EWMA weights `NA`.

**Fix:** Changed `resid.DT$var` → `resid.DT$resid.var` in the Robust EWMA path of
`calcAssetWeightsForRegression()`.

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
