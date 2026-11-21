# Basketball data: pull games, betting lines, teams and T-Rank ratings, and
# keep them as plain CSV files under data/basketball/.
#
# Two sources. CollegeBasketballData (the same provider and the same API key
# as football, drawing on the same monthly call limit) has games, lines, Elo
# and teams. barttorvik.com publishes T-Rank ratings and keeps a file for
# every day, with no key.
#
# One thing to keep straight: a T-Rank file dated D is taken after that
# day's games. So the ratings a team took into a game on day D are the file
# from the day before. cbb_ratings_before() is the only way ratings should
# be looked up.

CBB_PATHS <- list(
  root        = file.path("data", "basketball"),
  teams       = file.path("data", "basketball", "teams.csv"),
  games       = file.path("data", "basketball", "games"),
  ratings     = file.path("data", "basketball", "ratings"),
  predictions = file.path("data", "basketball", "predictions"),
  names       = file.path("data", "basketball", "team_names.csv"),
  params      = file.path("data", "basketball", "params.json"),
  app_data    = file.path("data", "basketball", "app_data.rds")
)

CBB_API <- "https://api.collegebasketballdata.com"
CBB_TRANK <- "https://barttorvik.com/timemachine/team_results/%s_team_results.json.gz"
# The API returns at most this many games per call, so long spans are
# pulled a month at a time.
CBB_API_ROW_CAP <- 3000

# ---- Seasons and days ----------------------------------------------------------

#' The season a date belongs to, named by the year it ends in: November
#' 2026 through April 2027 is the 2027 season.
cbb_season <- function(now = Sys.time()) {
  d <- as.POSIXlt(now, tz = "UTC")
  year <- d$year + 1900L
  if (d$mon + 1L >= 10L) year + 1L else year
}

#' "2026-27" for the 2027 season.
cbb_season_label <- function(season) sprintf("%d-%02d", season - 1L, season %% 100L)

#' The first day worth asking about in a season.
cbb_season_start <- function(season) as.Date(sprintf("%d-11-01", season - 1L))

#' The US Eastern calendar day of a tipoff. A 9pm game in the East is
#' already the next day in UTC, and it belongs with that evening's slate.
cbb_game_day <- function(start_date) {
  as.Date(parse_utc(start_date) - 5 * 3600, tz = "UTC")
}

# ---- CollegeBasketballData -------------------------------------------------------

#' One GET against the API, counted like the football calls.
cbb_api_get <- function(path, query = list()) {
  key <- Sys.getenv("CFBD_API_KEY")
  if (!nzchar(key)) {
    stop("CFBD_API_KEY is not set. The basketball API uses the same key as football. ",
         "Add the line CFBD_API_KEY=your-key to .Renviron in the project root, then run this again.",
         call. = FALSE)
  }
  pairs <- paste0(names(query), "=", vapply(query, function(v) utils::URLencode(as.character(v), reserved = TRUE), ""))
  address <- paste0(CBB_API, path, if (length(pairs) > 0) paste0("?", paste(pairs, collapse = "&")))
  options(spreadpredictor.api_calls = api_calls_made() + 1L)
  connection <- url(address, headers = c(Authorization = paste("Bearer", key)))
  on.exit(try(close(connection), silent = TRUE))
  text <- paste(readLines(connection, warn = FALSE, encoding = "UTF-8"), collapse = "")
  jsonlite::fromJSON(text)
}

#' Month-long (from, to) pairs covering a span, so no call hits the row cap.
cbb_month_chunks <- function(from, to) {
  starts <- seq(as.Date(from), as.Date(to), by = "30 days")
  data.frame(from = starts, to = pmin(starts + 29, as.Date(to)))
}

#' The teams table from the API's answer: one row per team with the columns
#' the app's badges and pickers use.
cbb_tidy_teams <- function(raw) {
  hex <- function(x) ifelse(is.na(x) | !nzchar(x), NA_character_, paste0("#", tolower(sub("^#", "", x))))
  logo <- vapply(raw$logos, function(x) if (length(x) > 0) as.character(x[[1]]) else NA_character_, character(1))
  teams <- data.frame(
    team_id = as.integer(raw$id), school = raw$school, mascot = raw$mascot,
    abbreviation = raw$abbreviation, conference = raw$conference,
    color = hex(raw$primaryColor), alt_color = hex(raw$secondaryColor), logo = logo,
    stringsAsFactors = FALSE
  )
  # Only Division I teams have a conference here.
  teams <- teams[!is.na(teams$conference) & nzchar(teams$conference), , drop = FALSE]
  teams[order(teams$school), , drop = FALSE]
}

#' Games from the API's /games answer, with the median spread from /lines.
#'
#' @param raw_games,raw_lines Parsed answers for the same span.
#' @return One row per game. spread is sportsbook style for the home team:
#'   -6.5 means the home team is favored by 6.5.
cbb_tidy_games <- function(raw_games, raw_lines = NULL) {
  if (!is.data.frame(raw_games) || nrow(raw_games) == 0) return(cbb_empty_games())
  games <- data.frame(
    game_id = as.integer(raw_games$id), season = as.integer(raw_games$season),
    season_type = raw_games$seasonType, start_date = raw_games$startDate,
    status = raw_games$status, neutral_site = as.integer(raw_games$neutralSite %in% TRUE),
    home_id = as.integer(raw_games$homeTeamId), home_team = raw_games$homeTeam,
    away_id = as.integer(raw_games$awayTeamId), away_team = raw_games$awayTeam,
    home_points = as.integer(raw_games$homePoints), away_points = as.integer(raw_games$awayPoints),
    home_elo = as.numeric(raw_games$homeTeamEloStart), away_elo = as.numeric(raw_games$awayTeamEloStart),
    home_elo_end = as.numeric(raw_games$homeTeamEloEnd), away_elo_end = as.numeric(raw_games$awayTeamEloEnd),
    stringsAsFactors = FALSE
  )
  games$spread <- NA_real_
  if (is.data.frame(raw_lines) && nrow(raw_lines) > 0) {
    median_spread <- vapply(raw_lines$lines, function(books) {
      spreads <- if (is.data.frame(books)) suppressWarnings(as.numeric(books$spread)) else numeric()
      if (all(is.na(spreads))) NA_real_ else stats::median(spreads, na.rm = TRUE)
    }, numeric(1))
    games$spread <- median_spread[match(games$game_id, raw_lines$gameId)]
  }
  games[order(games$start_date, games$game_id), , drop = FALSE]
}

cbb_empty_games <- function() {
  data.frame(game_id = integer(), season = integer(), season_type = character(), start_date = character(),
             status = character(), neutral_site = integer(), home_id = integer(), home_team = character(),
             away_id = integer(), away_team = character(), home_points = integer(), away_points = integer(),
             home_elo = numeric(), away_elo = numeric(), home_elo_end = numeric(), away_elo_end = numeric(),
             spread = numeric(), stringsAsFactors = FALSE)
}

#' Pull games and lines for a span of days: two calls per month covered.
cbb_fetch_games <- function(season, from, to) {
  chunks <- cbb_month_chunks(from, to)
  parts <- lapply(seq_len(nrow(chunks)), function(i) {
    span <- list(season = season, startDateRange = format(chunks$from[i]), endDateRange = format(chunks$to[i]))
    games <- cbb_api_get("/games", span)
    if (is.data.frame(games) && nrow(games) >= CBB_API_ROW_CAP) {
      warning("The basketball API returned its maximum of ", CBB_API_ROW_CAP, " games for ",
              span$startDateRange, " to ", span$endDateRange, ", so some may be missing. ",
              "Shorten the span in cbb_month_chunks().", call. = FALSE)
    }
    cbb_tidy_games(games, cbb_api_get("/lines", span))
  })
  do.call(rbind, parts)
}

#' Add newly pulled games to the ones on file. A game pulled again replaces
#' its old row, so scores and lines stay current.
cbb_merge_games <- function(old, new) {
  if (is.null(old) || nrow(old) == 0) return(new)
  kept <- old[!old$game_id %in% new$game_id, , drop = FALSE]
  # A line can vanish from the API once a game is over. Keep the last one seen.
  lost <- match(new$game_id, old$game_id)
  new$spread <- ifelse(is.na(new$spread), old$spread[lost], new$spread)
  merged <- rbind(kept, new)
  merged <- merged[order(merged$start_date, merged$game_id), , drop = FALSE]
  rownames(merged) <- NULL
  merged
}

# ---- T-Rank -----------------------------------------------------------------------

#' The path of one day's T-Rank file.
cbb_ratings_path <- function(season, day, root = CBB_PATHS$ratings) {
  file.path(root, as.character(season), paste0(format(as.Date(day), "%Y%m%d"), ".csv"))
}

#' One day's T-Rank ratings from the site's own rows.
#'
#' The site sends each team as a plain list of values with no names. The
#' positions used here: 2 team, 3 conference, 5 adjusted offense, 7 adjusted
#' defense, 45 adjusted tempo.
cbb_tidy_trank <- function(rows) {
  pick <- function(i) vapply(rows, function(r) as.character(r[[i]]), character(1))
  data.frame(team = pick(2), conference = pick(3), adj_o = as.numeric(pick(5)),
             adj_d = as.numeric(pick(7)), tempo = as.numeric(pick(45)), stringsAsFactors = FALSE)
}

#' Download one day's T-Rank file. NULL when the site has none for that day
#' (today's does not exist until the day is over).
cbb_fetch_trank <- function(day) {
  tmp <- tempfile(fileext = ".json.gz")
  on.exit(unlink(tmp))
  address <- sprintf(CBB_TRANK, format(as.Date(day), "%Y%m%d"))
  ok <- tryCatch({
    suppressWarnings(utils::download.file(address, tmp, quiet = TRUE, mode = "wb",
                                          headers = c("User-Agent" = "Mozilla/5.0")))
    file.exists(tmp) && file.size(tmp) > 1000
  }, error = function(e) FALSE)
  if (!ok) return(NULL)
  rows <- tryCatch(jsonlite::fromJSON(gzfile(tmp), simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(rows) || length(rows) < 100) return(NULL)
  cbb_tidy_trank(rows)
}

#' The days a season has T-Rank files for, oldest first.
cbb_rating_days <- function(season, root = CBB_PATHS$ratings) {
  files <- list.files(file.path(root, as.character(season)), pattern = "^[0-9]{8}\\.csv$")
  sort(as.Date(sub("\\.csv$", "", files), format = "%Y%m%d"))
}

#' The ratings teams took into a day's games: the newest file from before
#' that day. NULL when there is none.
#'
#' @param day The day of the games.
#' @return The file's rows, with attribute "day" for the file's own date.
cbb_ratings_before <- function(season, day, root = CBB_PATHS$ratings) {
  days <- cbb_rating_days(season, root)
  earlier <- days[days < as.Date(day)]
  if (length(earlier) == 0) return(NULL)
  ratings <- read_snapshot(cbb_ratings_path(season, max(earlier), root))
  attr(ratings, "day") <- max(earlier)
  ratings
}

# ---- The refresh ------------------------------------------------------------------

#' Bring the basketball files up to date.
#'
#' Teams are pulled once a season. Games and lines are pulled from the last
#' few days through the next week (or the whole season so far, the first
#' time). Every missing T-Rank day up to yesterday is downloaded.
#'
#' @return The number of API calls made, invisibly.
cbb_pull <- function(now = Sys.time(), paths = CBB_PATHS, look_back = 4, look_ahead = 7) {
  reset_api_calls()
  season <- cbb_season(now)
  today <- cbb_game_day(format_utc(now))

  if (!file.exists(paths$teams)) {
    write_snapshot(cbb_tidy_teams(cbb_api_get("/teams", list(season = season))), paths$teams)
  }

  games_file <- file.path(paths$games, paste0(season, ".csv"))
  old <- if (file.exists(games_file)) read_snapshot(games_file) else NULL
  from <- if (is.null(old)) cbb_season_start(season) else today - look_back
  new <- cbb_fetch_games(season, from, today + look_ahead)
  write_snapshot(cbb_merge_games(old, new), games_file, overwrite = TRUE)

  have <- cbb_rating_days(season, paths$ratings)
  first <- if (length(have) == 0) cbb_season_start(season) else max(have) + 1
  if (first < today) {
    for (day in as.list(seq(first, today - 1, by = "day"))) {
      ratings <- cbb_fetch_trank(day)
      if (is.null(ratings)) {
        message("No T-Rank file for ", format(day), ".")
      } else {
        write_snapshot(ratings, cbb_ratings_path(season, day, paths$ratings))
      }
      Sys.sleep(0.4)  # one small file at a time, gently
    }
  }
  message("API calls this run: ", api_calls_made())
  invisible(api_calls_made())
}
