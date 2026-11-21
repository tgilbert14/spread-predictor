# Basketball app data: everything the Basketball pages show, built from the
# files under data/basketball/ and saved as data/basketball/app_data.rds.

# How many days of games the Today page lists, starting today.
CBB_SLATE_DAYS <- 3
# The team a basketball resume is measured against. With about 365 teams,
# the 25th best is roughly what the 10th best is in football.
CBB_REFERENCE_RANK <- 25

#' Build and save the basketball app data.
#'
#' @param now The time to build for. Games from today (US Eastern) on are
#'   the slate, and ratings are the newest file from before today.
#' @return The app data list, invisibly: meta, teams, params, slate, results.
cbb_build_app_data <- function(now = Sys.time(), paths = CBB_PATHS) {
  season <- cbb_season(now)
  today <- cbb_game_day(format_utc(now))
  games_file <- file.path(paths$games, paste0(season, ".csv"))
  for (needed in c(paths$teams, games_file, paths$params)) {
    if (!file.exists(needed)) {
      stop("The basketball data is not complete: ", needed, " is missing. ",
           "Run `Rscript scripts/cbb_refresh.R` (and `Rscript scripts/cbb_fit.R` for the parameters).",
           call. = FALSE)
    }
  }
  ratings <- cbb_ratings_before(season, today + 1, paths$ratings)
  if (is.null(ratings)) {
    stop("No T-Rank ratings on file for the ", cbb_season_label(season), " season yet. ",
         "Run `Rscript scripts/cbb_refresh.R`.", call. = FALSE)
  }
  games <- read_snapshot(games_file)
  games$day <- cbb_game_day(games$start_date)
  params <- jsonlite::read_json(paths$params, simplifyVector = TRUE)
  teams <- cbb_team_table(read_snapshot(paths$teams), ratings, cbb_current_elo(games), cbb_aliases(paths$names))

  app_data <- list(
    meta = list(season = season, season_label = cbb_season_label(season), today = format(today),
                ratings_date = format(attr(ratings, "day")),
                built_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")),
    teams = teams,
    params = params,
    slate = cbb_slate(games, teams, today),
    results = cbb_results(games)
  )
  dir.create(dirname(paths$app_data), recursive = TRUE, showWarnings = FALSE)
  saveRDS(app_data, paths$app_data)
  invisible(app_data)
}

#' Games still to be played over the next few days, between two teams we
#' rate. Same columns as the football slate, plus the day.
cbb_slate <- function(games, teams, today, days = CBB_SLATE_DAYS) {
  upcoming <- games$status %in% c("scheduled", "in_progress") &
    games$day >= today & games$day < today + days &
    games$home_id %in% teams$team_id & games$away_id %in% teams$team_id
  slate <- games[upcoming, , drop = FALSE]
  slate <- slate[order(slate$start_date, slate$game_id), , drop = FALSE]
  data.frame(game_id = slate$game_id, start_date = slate$start_date, day = format(slate$day),
             home_id = slate$home_id, away_id = slate$away_id, neutral_site = slate$neutral_site == 1,
             market_spread_home = slate$spread, stringsAsFactors = FALSE)
}

#' This season's finished games, for records and resumes.
cbb_results <- function(games) {
  done <- games[games$status == "final" & !is.na(games$home_points) & !is.na(games$away_points), , drop = FALSE]
  data.frame(game_id = done$game_id, day = format(done$day), home_id = done$home_id, away_id = done$away_id,
             neutral_site = done$neutral_site == 1, home_points = done$home_points,
             away_points = done$away_points, stringsAsFactors = FALSE)
}

#' Load the basketball app data, or NULL when it is missing or unusable.
#' The Basketball menu only shows when this returns something.
cbb_load_app_data <- function(path = CBB_PATHS$app_data) {
  if (!file.exists(path)) return(NULL)
  x <- tryCatch(readRDS(path), error = function(e) NULL)
  parts <- c("meta", "teams", "params", "slate", "results")
  if (!is.list(x) || !all(parts %in% names(x)) || !is.data.frame(x$teams) || nrow(x$teams) < 2) return(NULL)
  x
}

#' Save today's predictions, once, for games that have not tipped off.
#'
#' Like football's weekly freeze: the file for a day is written the first
#' time this runs that day and never rewritten, so a line saved before
#' tipoff can be graded honestly later.
#'
#' @return TRUE if a file was written.
cbb_freeze <- function(app_data, now = Sys.time(), root = CBB_PATHS$predictions) {
  today <- app_data$meta$today
  path <- file.path(root, as.character(app_data$meta$season), paste0(gsub("-", "", today), ".csv"))
  slate <- app_data$slate[app_data$slate$day == today & parse_utc(app_data$slate$start_date) > now, , drop = FALSE]
  if (file.exists(path) || nrow(slate) == 0) return(invisible(FALSE))
  rows <- lapply(seq_len(nrow(slate)), function(i) {
    game <- slate[i, , drop = FALSE]
    site <- if (isTRUE(game$neutral_site)) "neutral" else "a_home"
    pred <- tryCatch(cbb_predict(game$home_id, game$away_id, site, app_data$teams, app_data$params),
                     error = function(e) NULL)
    if (is.null(pred)) return(NULL)
    margin <- function(id) pred$models$margin[pred$models$model == id]
    data.frame(game_id = game$game_id, day = today, start_date = game$start_date,
               home_id = game$home_id, home_team = pred$team_a$school,
               away_id = game$away_id, away_team = pred$team_b$school,
               neutral_site = as.integer(game$neutral_site),
               trank = round(margin("trank"), 2), elo = round(margin("elo"), 2),
               blend = round(pred$spread, 2), win_prob_home = round(pred$win_prob_a, 4),
               market_spread_home = game$market_spread_home,
               ratings_date = app_data$meta$ratings_date, fit_date = app_data$params$fit_date,
               frozen_at = format_utc(now), stringsAsFactors = FALSE)
  })
  rows <- do.call(rbind, rows)
  if (is.null(rows)) return(invisible(FALSE))
  write_snapshot(rows, path)
  invisible(TRUE)
}

# ---- Rankings ----------------------------------------------------------------------

#' The basketball ranking: every rated team, best first.
#'
#' @return rank (who would win, by the blend), team_id, record, rating (the
#'   blend, in points against an average team), each system's rank, and
#'   earned (who has earned it: record strength, as in football).
cbb_ranking_table <- function(app_data) {
  teams <- app_data$teams
  points <- cbb_team_points(teams, app_data$params)
  ranked <- function(x) as.integer(rank(-x, ties.method = "min", na.last = "keep"))
  out <- data.frame(rank = ranked(points$blend), team_id = teams$team_id, rating = points$blend,
                    trank = teams$trank_rank, elo = teams$elo_rank)

  results <- app_data$results
  winner <- ifelse(results$home_points > results$away_points, results$home_id, results$away_id)
  loser <- ifelse(results$home_points > results$away_points, results$away_id, results$home_id)
  wins <- table(factor(winner, levels = teams$team_id))
  losses <- table(factor(loser, levels = teams$team_id))
  out$record <- as.vector(ifelse(wins + losses == 0, "", sprintf("%d-%d", wins, losses)))

  out$earned <- NA_integer_
  power <- stats::setNames(points$blend, teams$team_id)
  if (nrow(results) > 0 && any(!is.na(power))) {
    resumes <- team_resumes(results, power, stats::setNames(rep(0L, nrow(teams)), teams$team_id),
                            app_data$params$sigma, reference_rank = CBB_REFERENCE_RANK,
                            home_field = app_data$params$home)
    out$earned <- ranked(resumes$record_strength)[match(out$team_id, resumes$team_id)]
  }
  out <- out[!is.na(out$rank), , drop = FALSE]
  out <- out[order(out$rank, out$team_id), c("rank", "team_id", "record", "rating", "trank", "elo", "earned")]
  rownames(out) <- NULL
  out
}

#' The game to open the basketball Matchup page on: the featured team's
#' next game on the slate, otherwise the slate game between the two
#' strongest teams, otherwise the top two teams on a neutral floor.
cbb_default_matchup <- function(app_data, featured = FEATURED_TEAM) {
  teams <- app_data$teams
  slate <- app_data$slate
  strength <- stats::setNames(cbb_team_points(teams, app_data$params)$blend, teams$team_id)
  featured_id <- teams$team_id[teams$school == featured]
  ours <- slate$home_id %in% featured_id | slate$away_id %in% featured_id
  if (any(ours)) return(slate_matchup(slate[which(ours)[1], , drop = FALSE]))
  if (nrow(slate) > 0) {
    combined <- strength[as.character(slate$home_id)] + strength[as.character(slate$away_id)]
    if (any(!is.na(combined))) return(slate_matchup(slate[which.max(combined), , drop = FALSE]))
  }
  top <- teams$team_id[order(-strength)][1:2]
  list(a = top[1], b = top[2], site = "neutral")
}
