# Fit the basketball model on one finished season and write
# data/basketball/params.json: each system's scale, home court, the blend
# weights and the typical miss.
#
# The fit uses the first part of the season and reports how the blend and
# the betting market did on the rest, which the fit never saw. Then it
# refits on the whole season for the numbers the app uses.
#
# Run from the project root:
#   Rscript scripts/cbb_fit.R          # fits on the 2024-25 season
#   Rscript scripts/cbb_fit.R 2027     # or name a season by the year it ended

for (file in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(file)

args <- commandArgs(trailingOnly = TRUE)
season <- if (length(args) > 0) as.integer(args[1]) else 2025L
games_file <- file.path(CBB_PATHS$games, paste0(season, ".csv"))
if (!file.exists(games_file)) {
  stop("No games file for the ", cbb_season_label(season), " season at ", games_file, ".", call. = FALSE)
}
rows <- cbb_fit_rows(read_snapshot(games_file), season, aliases = cbb_aliases())
message(nrow(rows), " finished games between two rated teams, ", sum(!is.na(rows$market)), " with a betting line.")

# An honest check first: fit on games before mid-January, score the rest.
split_day <- as.Date(sprintf("%d-01-15", season))
early <- cbb_fit(rows[rows$day < split_day, ], season)
late <- rows[rows$day >= split_day & !is.na(rows$market), ]
blend <- early$weights$trank * early$trank_scale * late$trank_gap +
  early$weights$elo * late$elo_gap / early$elo_k + early$home * late$home
check <- list(n = nrow(late), avg_miss = mean(abs(late$margin - blend)),
              market_avg_miss = mean(abs(late$margin - late$market)),
              winners = mean(sign(blend) == sign(late$margin)))
message(sprintf("Held-out check (%d games from %s on): our average miss %.2f, the market's %.2f.",
                check$n, format(split_day), check$avg_miss, check$market_avg_miss))

params <- cbb_fit(rows, season)
params$holdout <- check
dir.create(dirname(CBB_PATHS$params), recursive = TRUE, showWarnings = FALSE)
jsonlite::write_json(params, CBB_PATHS$params, auto_unbox = TRUE, pretty = TRUE, digits = 6)
message(sprintf("Weights: T-Rank %.0f%%, Elo %.0f%%. Home court %.1f points. Typical miss (sd) %.1f.",
                100 * params$weights$trank, 100 * params$weights$elo, params$home, params$sigma))
message("Wrote ", CBB_PATHS$params, ".")
