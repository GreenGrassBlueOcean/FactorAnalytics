# Helper: generate a synthetic unbalanced panel with known delistings/entries.
# Used by test-unbalanced-panel.R and test-fmCov-invariants.R.

make_unbalanced_panel <- function(
    n_assets = 30,
    n_periods = 60,
    n_delist = 5,
    n_enter = 5,
    n_sectors = 4,
    seed = 7831
) {
  set.seed(seed)

  dates <- seq(as.Date("2015-01-01"), by = "month", length.out = n_periods)
  tickers <- paste0("A", sprintf("%03d", 1:n_assets))

  panel <- expand.grid(DATE = dates, TICKER = tickers, stringsAsFactors = FALSE)
  panel$RETURN <- rnorm(nrow(panel), mean = 0.005, sd = 0.04)
  panel$SECTOR <- rep_len(paste0("S", 1:n_sectors), n_assets)[
    match(panel$TICKER, tickers)
  ]
  panel$P2B <- rnorm(nrow(panel), mean = 1.0, sd = 0.5)
  panel$SIZE <- rnorm(nrow(panel), mean = 10, sd = 2)

  # Late-entering assets: absent before 1/3 of sample

  enter_assets <- tickers[(n_assets - n_enter + 1):n_assets]
  enter_date <- dates[n_periods %/% 3]
  panel <- panel[!(panel$TICKER %in% enter_assets & panel$DATE < enter_date), ]

  # Delisted assets: absent from 2/3 of sample onward
  delist_assets <- tickers[1:n_delist]
  delist_date <- dates[2 * n_periods %/% 3]
  panel <- panel[!(panel$TICKER %in% delist_assets & panel$DATE >= delist_date), ]

  list(
    data = panel,
    all_assets = tickers,
    final_assets = setdiff(tickers, delist_assets),
    delisted = delist_assets,
    entered = enter_assets,
    dates = dates
  )
}
