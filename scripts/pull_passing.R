# Pull who threw the passes in every game: one API call per week of a
# season, skipping weeks already saved. The first run for past seasons is
# about 140 calls. After that the weekly snapshot adds one call a week.
#
# Run from the project root:
#   Rscript scripts/pull_passing.R              # every backfilled season
#   Rscript scripts/pull_passing.R 2025 2026    # just these seasons

if (file.exists(".Renviron")) readRenviron(".Renviron")
for (file in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(file)
options(warn = 1)

args <- suppressWarnings(as.integer(commandArgs(trailingOnly = TRUE)))
game_files <- list.files(file.path(PATHS$snapshots, "games"), pattern = "^[0-9]{4}\\.csv$", full.names = TRUE)
seasons <- as.integer(sub("\\.csv$", "", basename(game_files)))
if (length(args) > 0) seasons <- intersect(seasons, args)

reset_api_calls()
for (season in sort(seasons)) {
  games <- read_snapshot(file.path(PATHS$snapshots, "games", sprintf("%d.csv", season)))
  played <- games[games$season_type == "regular" & games$completed %in% c(TRUE, "TRUE", 1), , drop = FALSE]
  if (nrow(played) == 0) next
  pulled <- pull_passing(season, sort(unique(played$week)))
  message(season, ": pulled ", pulled, " week(s).")
}
message("Done. ", api_calls_made(), " API call(s).")
