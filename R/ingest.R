# Ingest: pull data from CollegeFootballData through cfbfastR, map it to the
# columns in docs/data-dictionary.md, and write snapshot CSVs.
#
# This file only defines functions. cfbfastR is called as cfbfastR::fn() and
# only inside the fetch_*() wrappers, so the app can source this file on a
# machine where cfbfastR is not installed.
#
# Snapshot rules (see the data dictionary):
#   * Files are append-only. If a file is on disk, its API call is skipped.
#   * The one exception: the current season's games and lines files are
#     rewritten each run, because games get played.
#   * Every write goes to a temp file first, then is renamed into place.


# ---- Seasons and weeks -------------------------------------------------------

#' The season a date belongs to.
#'
#' A season runs August through the January bowls, so before August we are
#' still in (or just after) last year's season.
current_season <- function(now = Sys.time()) {
  d <- as.POSIXlt(now, tz = "UTC")
  year <- d$year + 1900L
  if (d$mon + 1L >= 8L) year else year - 1L
}

#' Parse CFBD timestamps like "2026-08-29T23:30:00.000Z" as UTC.
parse_utc <- function(x) {
  x <- sub("T", " ", substr(as.character(x), 1, 19), fixed = TRUE)
  as.POSIXct(x, tz = "UTC", tryFormats = c("%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M", "%Y-%m-%d"))
}

#' Format a time as ISO 8601 UTC, the format of every pulled_at column.
format_utc <- function(time = Sys.time()) {
  format(time, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
}

#' Which week a snapshot taken at `now` belongs to.
#'
#' The answer comes from the schedule itself: it is the week of the next
#' regular-season kickoff. Ratings pulled now are what the systems say going
#' into that week's games.
#'
#' Going by the next kickoff, not the lowest unfinished week number, means a
#' game postponed from September to December does not drag the label back.
#'
#' @param games The season's games snapshot (needs week, season_type and
#'   start_date).
#' @param now The time of the snapshot.
#' @return A list: `season_type` ("regular" or "postseason"), `week`, and
#'   `started` (TRUE when that week already has a game under way or played,
#'   so the ratings may include some of its results). `season_type` and
#'   `week` are NA in the offseason. `week` is NA in the postseason.
snapshot_week <- function(games, now = Sys.time()) {
  kickoff <- as.numeric(parse_utc(games$start_date))
  now <- as.numeric(now)
  ahead <- !is.na(kickoff) & kickoff > now
  regular <- games$season_type == "regular"

  if (any(ahead & regular)) {
    next_game <- which.min(ifelse(ahead & regular, kickoff, Inf))
    week <- as.integer(games$week[next_game])
    in_week <- regular & games$week == week & !is.na(kickoff)
    return(list(season_type = "regular", week = week, started = any(kickoff[in_week] <= now)))
  }
  if (any(ahead & !regular)) {
    return(list(season_type = "postseason", week = NA_integer_, started = FALSE))
  }
  list(season_type = NA_character_, week = NA_integer_, started = FALSE)
}


# ---- Snapshot files ----------------------------------------------------------

#' Path of one snapshot file.
#'
#' @param kind "ratings", "teams", "games" or "lines".
#' @param source Rating source, for ratings only.
#' @param week CFBD week for a weekly ratings file. NULL means season-final.
snapshot_path <- function(kind, season, source = NULL, week = NULL, root = PATHS$snapshots) {
  if (kind != "ratings") {
    return(file.path(root, kind, sprintf("%d.csv", as.integer(season))))
  }
  if (!isTRUE(source %in% RATING_SOURCES)) {
    stop("Unknown rating source '", source, "'. Use one of: ", paste(RATING_SOURCES, collapse = ", "), ".")
  }
  label <- if (is.null(week)) "final" else sprintf("wk%02d", as.integer(week))
  file.path(root, "ratings", source, sprintf("%d_%s.csv", as.integer(season), label))
}

#' Read a snapshot CSV. Empty cells come back as NA.
read_snapshot <- function(path) {
  utils::read.csv(path, stringsAsFactors = FALSE, na.strings = "", encoding = "UTF-8")
}

#' Write a snapshot CSV without ever leaving a half-written file.
#'
#' @param overwrite FALSE (the default) keeps an existing file untouched.
#' @return TRUE if the file was written, invisibly.
write_snapshot <- function(df, path, overwrite = FALSE) {
  if (file.exists(path) && !overwrite) {
    message("Keeping ", path, ": snapshots are never overwritten.")
    return(invisible(FALSE))
  }
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  # Same folder as the target, so the rename is a simple atomic move.
  tmp <- tempfile(pattern = ".writing-", tmpdir = dirname(path), fileext = ".csv")
  on.exit(unlink(tmp), add = TRUE)
  utils::write.csv(df, tmp, row.names = FALSE, na = "", fileEncoding = "UTF-8")
  if (!file.rename(tmp, path)) {
    stop("Could not move the new file into place at ", path, ". Check folder permissions.")
  }
  message("Wrote ", path, " (", nrow(df), " rows).")
  invisible(TRUE)
}

#' Fetch and write one snapshot, skipping the API call if the file exists.
#'
#' @param fetch A function with no arguments that returns the data frame.
#' @param overwrite TRUE only for the current season's games and lines.
pull_snapshot <- function(path, fetch, overwrite = FALSE) {
  if (file.exists(path) && !overwrite) {
    message("Skipping ", path, ": already on disk.")
    return(invisible(FALSE))
  }
  write_snapshot(fetch(), path, overwrite = overwrite)
}

#' TRUE if a games file is missing or still has games without a final score.
games_unfinished <- function(path, now = Sys.time(), give_up_days = 14) {
  if (!file.exists(path)) return(TRUE)
  games <- read_snapshot(path)
  open <- !as.logical(games$completed) %in% TRUE
  # A game still open two weeks after kickoff was cancelled, not delayed.
  # Without this, one cancelled game would keep us calling the API all offseason.
  kickoff <- if ("start_date" %in% names(games)) parse_utc(games$start_date) else rep(as.POSIXct(NA), nrow(games))
  days_since <- as.numeric(difftime(now, kickoff, units = "days"))
  any(open & (is.na(days_since) | days_since < give_up_days))
}


# ---- Column mapping ----------------------------------------------------------

#' Pick contract columns out of a raw cfbfastR data frame.
#'
#' cfbfastR has renamed columns between versions, so each contract column has
#' a short list of candidate names, tried in order.
#'
#' @param spec Named list: contract column = candidate source names.
#' @param required Contract columns that must be found. Others become NA.
#' @param what Label for error messages, like "SP+ ratings".
select_columns <- function(raw, spec, required = names(spec), what = "data") {
  found <- vapply(spec, function(candidates) {
    hit <- intersect(candidates, names(raw))
    if (length(hit) == 0) NA_character_ else hit[1]
  }, character(1))

  missing <- intersect(required, names(found)[is.na(found)])
  if (length(missing) > 0) {
    stop(
      what, ": could not find column(s) ", paste(missing, collapse = ", "), ".\n",
      "Columns received: ", paste(names(raw), collapse = ", "), ".\n",
      "cfbfastR may have renamed them. Add the new name to the candidates in R/ingest.R.",
      call. = FALSE
    )
  }

  out <- lapply(names(spec), function(col) {
    if (is.na(found[[col]])) rep(NA, nrow(raw)) else first_value(raw[[found[[col]]]])
  })
  names(out) <- names(spec)
  as.data.frame(out, stringsAsFactors = FALSE, optional = TRUE)
}

#' Flatten a list-column (like logos) to its first value per row.
first_value <- function(x) {
  if (!is.list(x)) return(x)
  vapply(x, function(v) if (length(v) == 0) NA_character_ else as.character(v[[1]]), character(1))
}

#' Add the leading "#" to hex colors that lack it.
as_hex_color <- function(x) {
  x <- trimws(as.character(x))
  x[!is.na(x) & x == ""] <- NA
  ifelse(is.na(x) | startsWith(x, "#"), x, paste0("#", x))
}

#' A loose key for matching school names: no accents, case or punctuation.
#'
#' Accented letters are first spelled as their UTF-8 bytes ("<c3><a9>" for
#' e-acute), which behaves the same in every locale, unlike //TRANSLIT.
team_key <- function(x) {
  x <- iconv(as.character(x), from = "UTF-8", to = "ASCII", sub = "byte")
  folds <- c(
    "<c3><a0>" = "a", "<c3><a1>" = "a", "<c3><a4>" = "a", "<c3><a8>" = "e", "<c3><a9>" = "e",
    "<c3><89>" = "e", "<c3><ad>" = "i", "<c3><b1>" = "n", "<c3><b3>" = "o", "<c3><b6>" = "o",
    "<c3><ba>" = "u", "<c3><bc>" = "u"
  )
  for (bytes in names(folds)) x <- gsub(bytes, folds[[bytes]], x, fixed = TRUE)
  x <- gsub("<[0-9a-f]{2}>", "", x)  # any other non-ASCII character, like an okina
  gsub("[^a-z0-9]", "", tolower(x))
}

#' Short, readable list of names for messages.
name_list <- function(x, max = 25) {
  x <- sort(unique(x))
  more <- length(x) - max
  if (more > 0) x <- c(x[seq_len(max)], sprintf("and %d more", more))
  paste(x, collapse = ", ")
}


# ---- Normalizers: one per CFBD endpoint --------------------------------------

#' Map cfbfastR::cfbd_teams_fbs() output to the teams file columns.
normalize_teams <- function(raw) {
  teams <- select_columns(
    raw,
    spec = list(
      team_id      = c("team_id", "id", "teamId"),
      school       = c("school", "team"),
      mascot       = "mascot",
      abbreviation = c("abbreviation", "abbr"),
      conference   = "conference",
      color        = "color",
      alt_color    = c("alt_color", "alternate_color", "altColor"),
      logo         = c("logo", "logos_1", "logos")
    ),
    required = c("team_id", "school"),
    what = "FBS teams"
  )
  teams$team_id <- as.integer(teams$team_id)
  teams$color <- as_hex_color(teams$color)
  teams$alt_color <- as_hex_color(teams$alt_color)
  teams <- teams[!is.na(teams$team_id) & !is.na(teams$school), ]
  teams <- teams[!duplicated(teams$team_id), ]
  teams[order(teams$school), , drop = FALSE]
}

#' Map cfbfastR::cfbd_game_info() output to the games file columns.
normalize_games <- function(raw) {
  side <- function(prefix) {
    spec <- list(
      id          = c("id", "team_id"),
      team        = "team",
      class       = c("class", "classification", "division"),
      points      = c("points", "score"),
      pregame_elo = "pregame_elo"
    )
    lapply(spec, function(candidates) paste0(prefix, "_", candidates))
  }
  home <- side("home")
  away <- side("away")

  games <- select_columns(
    raw,
    spec = list(
      game_id          = c("game_id", "id"),
      season           = "season",
      week             = "week",
      season_type      = "season_type",
      start_date       = c("start_date", "start_time"),
      completed        = "completed",
      neutral_site     = "neutral_site",
      home_id          = home$id,
      home_team        = home$team,
      home_class       = home$class,
      home_points      = home$points,
      home_pregame_elo = home$pregame_elo,
      away_id          = away$id,
      away_team        = away$team,
      away_class       = away$class,
      away_points      = away$points,
      away_pregame_elo = away$pregame_elo
    ),
    required = c(
      "game_id", "season", "week", "season_type", "completed", "neutral_site",
      "home_id", "home_team", "home_class", "away_id", "away_team", "away_class"
    ),
    what = "Games"
  )

  for (col in c("game_id", "season", "week", "home_id", "away_id", "home_points", "away_points")) {
    games[[col]] <- as.integer(games[[col]])
  }
  for (col in c("home_pregame_elo", "away_pregame_elo")) {
    games[[col]] <- as.numeric(games[[col]])
  }
  games$completed <- as.logical(games$completed)
  games$neutral_site <- as.logical(games$neutral_site)
  games$home_class <- tolower(games$home_class)
  games$away_class <- tolower(games$away_class)

  no_id <- is.na(games$game_id) | is.na(games$home_id) | is.na(games$away_id)
  if (any(no_id)) {
    warning("Dropped ", sum(no_id), " game(s) with no game or team id.", call. = FALSE)
  }
  games <- games[!no_id, ]
  games <- games[!duplicated(games$game_id), ]
  games[order(games$start_date, games$game_id), , drop = FALSE]
}

#' Map cfbfastR::cfbd_betting_lines() output to the lines file columns.
#'
#' One row per game and sportsbook. `spread` is home-relative, sportsbook
#' style: -7 means the home team is favored by 7.
normalize_lines <- function(raw, pulled_at = format_utc()) {
  empty <- data.frame(
    game_id = integer(), provider = character(), spread = numeric(), pulled_at = character()
  )
  if (nrow(raw) == 0) return(empty)

  lines <- select_columns(
    raw,
    spec = list(game_id = c("game_id", "id"), provider = "provider", spread = "spread"),
    what = "Betting lines"
  )
  lines$game_id <- as.integer(lines$game_id)
  # cfbfastR documents spread as character in some versions.
  lines$spread <- suppressWarnings(as.numeric(lines$spread))
  lines$pulled_at <- rep(pulled_at, nrow(lines))
  lines <- lines[!is.na(lines$game_id) & !is.na(lines$provider), ]

  dupes <- duplicated(lines[c("game_id", "provider")])
  if (any(dupes)) {
    message("Lines: kept the first of ", sum(dupes), " repeated game and sportsbook row(s).")
  }
  lines <- lines[!dupes, ]
  lines[order(lines$game_id, lines$provider), , drop = FALSE]
}

#' Map one rating source's cfbfastR output to the ratings file columns.
#'
#' The ratings endpoints return school names, not ids, so team_id comes from
#' matching names to that season's teams file.
#'
#' @param source One of RATING_SOURCES.
#' @param week CFBD week, or NA for a season-final file.
#' @param teams That season's teams file (normalize_teams() output).
normalize_ratings <- function(raw, source, season, week, teams, pulled_at = format_utc()) {
  rating_candidates <- list(
    sp  = c("rating", "sp", "overall"),
    fpi = c("fpi", "rating"),
    srs = c("rating", "srs"),
    elo = c("elo", "rating")
  )
  ratings <- select_columns(
    raw,
    spec = list(
      team       = c("team", "school"),
      team_id    = c("team_id", "teamId"),
      conference = "conference",
      rating     = rating_candidates[[source]]
    ),
    required = c("team", "rating"),
    what = paste(source, "ratings")
  )

  # SP+ adds a "nationalAverages" row that is not a team.
  real_team <- !is.na(ratings$team) & nzchar(trimws(ratings$team)) & ratings$team != "nationalAverages"
  ratings <- ratings[real_team, ]

  ratings$rating <- suppressWarnings(as.numeric(ratings$rating))
  no_rating <- is.na(ratings$rating)
  if (any(no_rating)) {
    message(source, ": dropped ", sum(no_rating), " team(s) with no rating: ", name_list(ratings$team[no_rating]), ".")
  }
  ratings <- ratings[!no_rating, ]

  ratings$team_id <- as.integer(ratings$team_id)
  needs_id <- is.na(ratings$team_id)
  ratings$team_id[needs_id] <- match_team_ids(
    ratings$team[needs_id], ratings$conference[needs_id], teams, what = source
  )
  ratings <- ratings[!is.na(ratings$team_id), ]

  ratings <- combine_duplicate_ratings(ratings, paste(season, source))

  n <- nrow(ratings)
  data.frame(
    season    = rep(as.integer(season), n),
    week      = rep(as.integer(week), n),
    team_id   = ratings$team_id,
    team      = ratings$team,
    rating    = ratings$rating,
    pulled_at = rep(pulled_at, n),
    stringsAsFactors = FALSE
  )[order(ratings$team), , drop = FALSE]
}

#' Look up team ids by school name. Unmatched names come back NA.
#'
#' Teams from non-FBS conferences are expected not to match (SRS and Elo
#' cover FCS too), so they get a quiet message. A team from an FBS
#' conference that does not match is a real problem, so it gets a warning.
match_team_ids <- function(names, conferences, teams, what = "ratings") {
  ids <- teams$team_id[match(team_key(names), team_key(teams$school))]

  unmatched <- is.na(ids)
  fbs_conference <- is.na(conferences) | conferences %in% teams$conference
  not_fbs <- unmatched & !fbs_conference
  problem <- unmatched & fbs_conference

  if (any(not_fbs)) {
    message(what, ": skipped ", sum(not_fbs), " non-FBS team(s) not in the teams file.")
  }
  if (any(problem)) {
    warning(
      what, ": ", sum(problem), " team name(s) did not match the teams file and were left out: ",
      name_list(names[problem]), ". Compare the spelling with the teams file; team_key() decides what counts as a match.",
      call. = FALSE
    )
  }
  ids
}


# ---- cfbfastR wrappers -------------------------------------------------------
# Every API call goes through cfbd_fetch(), which counts it. Each call pulls a
# whole season, never one team, to stay inside the free tier's 1,000 calls a
# month.

#' Stop early, with next steps, if the API cannot be used.
require_cfbd <- function() {
  if (!requireNamespace("cfbfastR", quietly = TRUE)) {
    stop("cfbfastR is not installed. Run: Rscript scripts/setup.R", call. = FALSE)
  }
  if (!nzchar(Sys.getenv("CFBD_API_KEY"))) {
    stop(
      "CFBD_API_KEY is not set. Get a free key at https://collegefootballdata.com/key, ",
      "add the line CFBD_API_KEY=your-key to a file named .Renviron in the project root, ",
      "then run this again.",
      call. = FALSE
    )
  }
  invisible(TRUE)
}

#' Reset the count of API calls made in this run.
reset_api_calls <- function() options(spreadpredictor.api_calls = 0L)

#' Number of API calls made in this run.
api_calls_made <- function() getOption("spreadpredictor.api_calls", 0L)

#' Call one cfbfastR function and count it.
#'
#' cfbfastR catches its own errors and returns an empty data frame with a
#' message, so an empty result counts as a failure unless `allow_empty`.
cfbd_fetch <- function(fn, ..., allow_empty = FALSE) {
  options(spreadpredictor.api_calls = api_calls_made() + 1L)
  df <- getExportedValue("cfbfastR", fn)(...)
  if (!is.data.frame(df) || (nrow(df) == 0 && !allow_empty)) {
    stop(
      "cfbfastR::", fn, "() returned no data. See the message just above. Common causes: ",
      "an invalid CFBD_API_KEY, no API calls left this month, or no data yet for that season.",
      call. = FALSE
    )
  }
  as.data.frame(df)
}


fetch_teams <- function(season) cfbd_fetch("cfbd_teams_fbs", year = season)

#' Regular season and postseason in one call. division = "fbs" keeps games
#' with at least one FBS team.
fetch_games <- function(season) {
  cfbd_fetch("cfbd_game_info", year = season, season_type = "both", division = "fbs")
}

#' Lines can legitimately be empty early in a season, before books post them.
fetch_lines <- function(season, allow_empty = FALSE) {
  cfbd_fetch("cfbd_betting_lines", year = season, season_type = "both", allow_empty = allow_empty)
}

#' Ratings as the API has them right now. SP+, FPI and SRS take no week, so
#' for a past season this is the season-final rating. Elo is called without a
#' week too, which returns the latest rating: final for a past season, and
#' "through the last game played" during the season.
fetch_ratings <- function(source, season) {
  switch(source,
    sp  = cfbd_fetch("cfbd_ratings_sp", year = season),
    fpi = cfbd_fetch("cfbd_ratings_fpi", year = season),
    srs = cfbd_fetch("cfbd_ratings_srs", year = season),
    elo = cfbd_fetch("cfbd_ratings_elo", year = season, season_type = "both"),
    stop("Unknown rating source '", source, "'.")
  )
}

#' Log the key's tier and remaining calls. Never breaks a run.
log_api_key_info <- function(when) {
  tryCatch({
    options(spreadpredictor.api_calls = api_calls_made() + 1L)
    info <- suppressWarnings(cfbfastR::cfbd_api_key_info())
    fields <- intersect(
      c("patron_level", "tier_name", "monthly_limit", "used_calls", "remaining_calls", "reset_at"),
      names(info)
    )
    values <- vapply(fields, function(f) as.character(info[[f]][[1]]), character(1))
    if (length(values) == 0) {
      message("API key info (", when, "): not available.")
    } else {
      message("API key info (", when, "): ", paste(fields, values, sep = " = ", collapse = ", "))
    }
  }, error = function(e) {
    message("API key info (", when, "): could not be read (", conditionMessage(e), ").")
  })
  invisible(NULL)
}


# ---- Runs --------------------------------------------------------------------

#' Run one step, report a failure, and carry on with the next step.
#' @return TRUE if the step worked.
run_step <- function(label, expr) {
  tryCatch({
    force(expr)
    TRUE
  }, error = function(e) {
    message("FAILED: ", label, ". ", conditionMessage(e))
    FALSE
  })
}

#' Pull one season's teams file if it is not on disk yet.
pull_teams <- function(season, root) {
  pull_snapshot(snapshot_path("teams", season, root = root), function() {
    normalize_teams(fetch_teams(season))
  })
}

#' Pull one ratings file (weekly or final) if it is not on disk yet.
#' @param week CFBD week, or NULL for the season-final file.
pull_ratings <- function(source, season, week, root, pulled_at) {
  path <- snapshot_path("ratings", season, source = source, week = week, root = root)
  pull_snapshot(path, function() {
    teams <- read_snapshot(snapshot_path("teams", season, root = root))
    week_value <- if (is.null(week)) NA_integer_ else week
    normalize_ratings(fetch_ratings(source, season), source, season, week_value, teams, pulled_at)
  })
}

#' Pull a season's games and lines.
#'
#' @param overwrite TRUE for the weekly refresh of the current season.
#' @param allow_empty_lines TRUE for the current season, which may have no
#'   lines posted yet.
pull_games_and_lines <- function(season, root, pulled_at, overwrite, allow_empty_lines = overwrite) {
  c(
    games = run_step(paste(season, "games"), pull_snapshot(
      snapshot_path("games", season, root = root),
      function() normalize_games(fetch_games(season)),
      overwrite = overwrite
    )),
    lines = run_step(paste(season, "lines"), pull_snapshot(
      snapshot_path("lines", season, root = root),
      function() normalize_lines(fetch_lines(season, allow_empty = allow_empty_lines), pulled_at),
      overwrite = overwrite
    ))
  )
}

#' The weekly job: this week's ratings, plus fresh current-season games and lines.
#'
#' Ratings are only snapshotted ahead of a regular-season week. In the
#' postseason, games and lines are still refreshed. In the offseason nothing
#' is pulled unless the season's games file is missing results.
#'
#' @return A named logical vector, one entry per step, TRUE if it worked.
run_snapshot <- function(now = Sys.time(), root = PATHS$snapshots) {
  require_cfbd()
  reset_api_calls()
  log_api_key_info("start")
  on.exit({
    log_api_key_info("end")
    message("API calls this run: ", api_calls_made())
  })

  season <- current_season(now)
  pulled_at <- format_utc(now)
  ok <- c()

  # Games first: the schedule is what tells us which week this snapshot is for.
  games_file <- snapshot_path("games", season, root = root)
  if (games_unfinished(games_file, now)) {
    ok <- c(ok, pull_games_and_lines(season, root, pulled_at, overwrite = TRUE))
  }
  if (!file.exists(games_file)) {
    message("No games file for ", season, ", so the week is unknown. No ratings snapshotted.")
    return(ok)
  }
  upcoming <- snapshot_week(read_snapshot(games_file), now)

  if (is.na(upcoming$season_type)) {
    message("Offseason: no ", season, " games are left to play. No ratings to snapshot.")
  } else if (upcoming$season_type == "postseason") {
    message("Postseason: weekly ratings are only snapshotted for regular-season weeks.")
  } else {
    message("Snapshot for the ", season, " season, going into week ", upcoming$week, ".")
    if (upcoming$started) {
      message("Note: week ", upcoming$week, " has already kicked off, so a new ratings file ",
              "may include some of this week's results.")
    }
    ok["teams"] <- run_step(paste(season, "teams"), pull_teams(season, root))
    for (source in RATING_SOURCES) {
      ok[source] <- run_step(
        paste(season, "week", upcoming$week, source),
        pull_ratings(source, season, upcoming$week, root, pulled_at)
      )
    }
  }
  ok
}

#' One-time history pull: teams, games, lines and season-final ratings.
#'
#' Past seasons get everything. The current season gets teams, games and
#' lines only, since it has no final ratings yet. Anything on disk is skipped,
#' so this is safe to re-run after a failure.
#'
#' @return A named logical vector, one entry per step, TRUE if it worked.
run_backfill <- function(seasons = TRAINING_SEASONS, now = Sys.time(), root = PATHS$snapshots) {
  require_cfbd()
  reset_api_calls()
  log_api_key_info("start")
  on.exit({
    log_api_key_info("end")
    message("API calls this run: ", api_calls_made())
  })

  current <- current_season(now)
  pulled_at <- format_utc(now)
  ok <- c()

  for (season in sort(unique(c(seasons, current)))) {
    message("---- ", season, " ----")
    ok[paste(season, "teams")] <- run_step(paste(season, "teams"), pull_teams(season, root))
    steps <- pull_games_and_lines(
      season, root, pulled_at, overwrite = FALSE, allow_empty_lines = season == current
    )
    ok[paste(season, names(steps))] <- steps

    if (season < current) {
      for (source in RATING_SOURCES) {
        ok[paste(season, source, "final")] <- run_step(
          paste(season, source, "final ratings"),
          pull_ratings(source, season, week = NULL, root, pulled_at)
        )
      }
    }
  }
  ok
}
