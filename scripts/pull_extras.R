# Pull the extras for every backfilled season: team talent, returning
# production and per-game efficiency stats. About 30 API calls the first
# time (3 per season), none after that (files on disk are never pulled twice).
# It also pulls two research-only tables that the model does not use: every
# sportsbook's line with its opening spread, and stadium coordinates.
#
# The model uses them: talent and returning production early in the season,
# per-game success rates in the Power rating. The weekly snapshot keeps the
# current season's files up to date, so this is a one-time job, like
# scripts/backfill.R.
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
message("\nTalent, returning production, game stats and the research tables are up to date.")
