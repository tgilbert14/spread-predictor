# Pull research data: team talent, returning production and per-game
# efficiency stats for every backfilled season. About 18 API calls the first
# time, none after that (files on disk are never pulled twice).
#
# These tables are only used to test ideas in scripts/backtest.R.
#
# Run from the project root:
#   Rscript scripts/pull_extras.R

# Pick up the API key from the project's .Renviron, even when R was started
# somewhere else (for example from RStudio with setwd()).
if (file.exists(".Renviron")) readRenviron(".Renviron")

for (file in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(file)
options(warn = 1)

ok <- run_extras()

if (!all(ok)) {
  message("\nThese pulls failed: ", paste(names(ok)[!ok], collapse = ", "),
          ". The others were kept. Run this again to retry.")
  quit(save = "no", status = 1)
}
message("\nResearch data is up to date.")
