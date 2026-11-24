# Pull who carried, caught and tackled in every game since 2018, for the
# "missing starters" study (scripts/research/starters_out.R).
#
# One API call per week of a season, about 135 in all. Weeks already saved
# are skipped, so it is safe to run again. Saved one file per season under
# data/research/box/, zipped, one row per player per game per kind:
#   rush = carries, rec = catches, def = tackles.
# Research only: the app and the weekly refresh do not read these.
#
# Run from the project root:
#   Rscript scripts/research/pull_box_scores.R

if (file.exists(".Renviron")) readRenviron(".Renviron")
for (file in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(file)
options(warn = 1)

BOX_DIR <- file.path("data", "research", "box")
BOX_KINDS <- list(rush = c("rushing", "CAR"), rec = c("receiving", "REC"), def = c("defensive", "TOT"))

fetch_box_week <- function(season, week) {
  key <- Sys.getenv("CFBD_API_KEY", "placeholder")
  address <- sprintf("%s/games/players?year=%d&week=%d&seasonType=regular&classification=fbs",
                     CFBD_API, as.integer(season), as.integer(week))
  jsonlite::fromJSON(url(address, headers = c(Authorization = paste("Bearer", key))), simplifyVector = FALSE)
}

# One row per player per kind for a week of games.
box_rows <- function(games, week) {
  rows <- list()
  for (game in games) for (team in game$teams) for (kind in names(BOX_KINDS)) {
    category <- Filter(function(x) identical(x$name, BOX_KINDS[[kind]][1]), team$categories)
    if (length(category) == 0) next
    type <- Filter(function(x) identical(x$name, BOX_KINDS[[kind]][2]), category[[1]]$types)
    if (length(type) == 0 || length(type[[1]]$athletes) == 0) next
    athletes <- type[[1]]$athletes
    rows[[length(rows) + 1]] <- data.frame(
      game_id = as.integer(game$id), week = as.integer(week), team = team$team, kind = kind,
      athlete_id = vapply(athletes, function(a) as.character(a$id), character(1)),
      athlete = vapply(athletes, function(a) as.character(a$name), character(1)),
      count = suppressWarnings(as.numeric(vapply(athletes, function(a) as.character(a$stat), character(1)))),
      stringsAsFactors = FALSE
    )
  }
  if (length(rows) == 0) return(NULL)
  out <- do.call(rbind, rows)
  # Team totals come through as a made-up athlete.
  out[!grepl("^-", out$athlete_id) & tolower(trimws(out$athlete)) != "team" & !is.na(out$count), , drop = FALSE]
}

dir.create(BOX_DIR, recursive = TRUE, showWarnings = FALSE)
game_files <- list.files(file.path(PATHS$snapshots, "games"), pattern = "^[0-9]{4}\\.csv$", full.names = TRUE)
calls <- 0L
for (file in game_files) {
  season <- as.integer(sub("\\.csv$", "", basename(file)))
  games <- read_snapshot(file)
  played <- games[games$season_type == "regular" & games$completed %in% c(TRUE, "TRUE", 1), , drop = FALSE]
  path <- file.path(BOX_DIR, sprintf("%d.csv.gz", season))
  saved <- if (file.exists(path)) utils::read.csv(path, stringsAsFactors = FALSE, colClasses = c(athlete_id = "character")) else NULL
  todo <- setdiff(sort(unique(played$week)), unique(saved$week))
  for (week in todo) {
    saved <- rbind(saved, box_rows(fetch_box_week(season, week), week))
    calls <- calls + 1L
  }
  if (length(todo) > 0) {
    con <- gzfile(path, "w")
    utils::write.csv(saved, con, row.names = FALSE)
    close(con)
  }
  message(season, ": ", length(todo), " week(s) pulled, ", nrow(saved), " rows saved.")
}
message("Done. ", calls, " API call(s).")
