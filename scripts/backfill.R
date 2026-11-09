# One-time history pull for TRAINING_SEASONS plus the current season:
# teams, games (regular and postseason), lines, and season-final ratings.
# About 40 API calls the first time. Files already on disk are skipped, so
# re-running only pulls what is missing.
#
# Run from the project root:
#   Rscript scripts/backfill.R

for (file in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(file)
options(warn = 1)  # show name-matching warnings where they happen

ok <- run_backfill(TRAINING_SEASONS)

if (!all(ok)) {
  message("\nThese steps failed: ", paste(names(ok)[!ok], collapse = ", "),
          ". Run this again to retry just those.")
  quit(save = "no", status = 1)
}
message("\nBackfill done. Next: Rscript scripts/refresh.R --offline")
