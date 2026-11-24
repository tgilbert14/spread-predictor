# Who played quarterback: each team's passers in every game, from the box
# scores. This is how the model finds out, without reading any news, that a
# team's main quarterback did not play.
#
# Saved one file per season under data/snapshots/extras/passing/, one row
# per passer per game. cfbfastR's version of this endpoint returns the stats
# nested, so this reads the API directly and flattens it.

CFBD_API <- "https://api.collegefootballdata.com"

#' Path of one season's passing file.
passing_path <- function(season, root = PATHS$snapshots) extra_path("passing", season, root)

#' One week of passing box scores, straight from the API. Counts as one call.
#'
#' @return The parsed JSON: a list of games.
fetch_passing_week <- function(season, week) {
  options(spreadpredictor.api_calls = api_calls_made() + 1L)
  key <- Sys.getenv("CFBD_API_KEY", "placeholder")
  address <- sprintf("%s/games/players?year=%d&week=%d&seasonType=regular&category=passing&classification=fbs",
                     CFBD_API, as.integer(season), as.integer(week))
  con <- url(address, headers = c(Authorization = paste("Bearer", key)))
  jsonlite::fromJSON(con, simplifyVector = FALSE)
}

#' Flatten one week's passing box scores.
#'
#' @param games What fetch_passing_week() returns.
#' @return One row per passer per game: game_id, season, week, team,
#'   athlete_id, athlete, completions, attempts, yards. No rows for a week
#'   with no games.
passing_rows <- function(games, season, week) {
  empty <- data.frame(game_id = integer(), season = integer(), week = integer(), team = character(),
                      athlete_id = character(), athlete = character(), completions = integer(),
                      attempts = integer(), yards = integer(), stringsAsFactors = FALSE)
  rows <- list()
  for (game in games) {
    for (team in game$teams) {
      passing <- Filter(function(category) identical(category$name, "passing"), team$categories)
      if (length(passing) == 0) next
      stat <- function(type) {
        found <- Filter(function(t) identical(t$name, type), passing[[1]]$types)
        if (length(found) == 0) return(list())
        stats::setNames(lapply(found[[1]]$athletes, function(a) a$stat),
                        vapply(found[[1]]$athletes, function(a) as.character(a$id), character(1)))
      }
      names_by_id <- unlist(lapply(passing[[1]]$types, function(t) {
        stats::setNames(vapply(t$athletes, function(a) as.character(a$name), character(1)),
                        vapply(t$athletes, function(a) as.character(a$id), character(1)))
      }))
      throws <- stat("C/ATT")
      yards <- stat("YDS")
      for (id in names(throws)) {
        # Team totals come through as a made-up athlete; skip them.
        if (grepl("^-", id) || identical(tolower(names_by_id[[id]]), "team")) next
        parts <- suppressWarnings(as.integer(strsplit(throws[[id]], "/", fixed = TRUE)[[1]]))
        if (length(parts) != 2 || anyNA(parts)) next
        rows[[length(rows) + 1]] <- data.frame(
          game_id = as.integer(game$id), season = as.integer(season), week = as.integer(week),
          team = team$team, athlete_id = id, athlete = names_by_id[[id]],
          completions = parts[1], attempts = parts[2],
          yards = suppressWarnings(as.integer(yards[[id]] %||% NA)), stringsAsFactors = FALSE
        )
      }
    }
  }
  if (length(rows) == 0) empty else do.call(rbind, rows)
}

#' `a`, or `b` when `a` is NULL.
`%||%` <- function(a, b) if (is.null(a)) b else a

#' Pull the weeks of a season's passing that are not on disk yet.
#'
#' @param weeks The regular-season weeks that have been played.
#' @param refresh Weeks to pull again even if saved (the latest week, whose
#'   games may not all have been final last time).
#' @return The number of weeks pulled.
pull_passing <- function(season, weeks, root = PATHS$snapshots, refresh = integer()) {
  path <- passing_path(season, root)
  saved <- if (file.exists(path)) read_snapshot(path) else NULL
  have <- if (is.null(saved)) integer() else unique(saved$week)
  todo <- sort(unique(c(setdiff(weeks, have), intersect(refresh, weeks))))
  for (week in todo) {
    rows <- passing_rows(fetch_passing_week(season, week), season, week)
    saved <- rbind(saved[!saved$week %in% week, , drop = FALSE], rows)
  }
  if (length(todo) > 0 && !is.null(saved) && nrow(saved) > 0) {
    saved <- saved[order(saved$week, saved$game_id, saved$team, -saved$attempts), , drop = FALSE]
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    write_snapshot(saved, path, overwrite = TRUE)
  }
  length(todo)
}

#' The newest season with a saved games file.
latest_snapshot_season <- function(root = PATHS$snapshots) {
  files <- list.files(file.path(root, "games"), pattern = "^[0-9]{4}\\.csv$")
  max(as.integer(sub("\\.csv$", "", files)))
}

#' Every saved season of passing, as one table.
load_passing <- function(root = PATHS$snapshots, seasons = NULL) {
  files <- list.files(file.path(root, "extras", "passing"), pattern = "^[0-9]{4}\\.csv$", full.names = TRUE)
  if (!is.null(seasons)) files <- files[as.integer(sub("\\.csv$", "", basename(files))) %in% seasons]
  if (length(files) == 0) return(NULL)
  all <- do.call(rbind, lapply(files, read_snapshot))
  all$athlete_id <- as.character(all$athlete_id)
  all
}
