# Build data/app_data.rds: everything the app shows except the game notes.
# The shape is set in docs/data-dictionary.md and matches demo_app_data().

#' Build and save the app data.
#'
#' The current season is the latest one with weekly snapshots, and the week
#' is the latest snapshot week in it. Saved predictions (under
#' `snapshots_root`) are graded into the scorecard and give the slate its
#' line movement.
#'
#' @param now The time of the build, for telling which week's games are all in.
#' @return The app data list, invisibly.
build_app_data <- function(db_path = PATHS$database, params_path = PATHS$params,
                           out_path = PATHS$app_data, snapshots_root = PATHS$snapshots,
                           now = Sys.time()) {
  params <- read_params(params_path)
  con <- connect_readonly(db_path)
  on.exit(DBI::dbDisconnect(con))

  coverage <- query_sql_file(con, "snapshot_coverage.sql")
  if (nrow(coverage) == 0) {
    stop("The database has no weekly rating snapshots yet. Run `Rscript scripts/snapshot.R` ",
         "to capture this week's ratings, rebuild the database, then try again.", call. = FALSE)
  }
  season <- max(coverage$season)
  week <- max(coverage$week[coverage$season == season])
  latest <- latest_snapshots(coverage, season)
  predictions <- load_predictions(snapshots_root)
  power <- season_power(con, season)
  teams <- current_teams(con, season, latest, power)
  # The week whose committee ranking comes next. Its ratings row is added to
  # the history so that ranking can be predicted before the weekly snapshot.
  next_release <- forecast_week(query_sql_file(con, "week_progress.sql", list(season)), now)
  history_weeks <- seq_len(max(week, next_release, na.rm = TRUE))

  app_data <- list(
    meta = list(
      season = as.integer(season),
      week = as.integer(week),
      ratings_date = substr(max(latest$pulled_at, na.rm = TRUE), 1, 10),
      built_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
      is_demo = FALSE,
      forecast_week = next_release
    ),
    teams = teams,
    params = params,
    slate = add_line_movement(current_slate(con, season, week), predictions, season, week),
    coverage = coverage,
    scorecard = build_scorecard(predictions, query_sql_file(con, "game_results.sql"), season),
    history = rating_history(con, season, history_weeks, teams$team_id, power_through(power, history_weeks)),
    results = season_results(con, season),
    polls = load_polls(snapshots_root, season, teams),
    forecasts = load_forecasts(snapshots_root, season)
  )

  dir.create(dirname(out_path), recursive = TRUE, showWarnings = FALSE)
  saveRDS(app_data, out_path)
  invisible(app_data)
}

#' Each source's latest weekly snapshot in a season.
#'
#' Sources are taken one at a time because one can lag a week behind the
#' others, and a week-old rating beats no rating.
latest_snapshots <- function(coverage, season) {
  in_season <- coverage[coverage$season == season, , drop = FALSE]
  in_season <- in_season[order(in_season$source, -in_season$week), , drop = FALSE]
  in_season[!duplicated(in_season$source), , drop = FALSE]
}

#' The season's teams with one rating and one rank column per system, tier
#' (1 for a power team, 0 otherwise), and talent_z and returning_z (preseason
#' z-scores, 0 for a team with no value).
#'
#' Rank 1 is the best rating. Tied teams share the better rank, and a team
#' with no rating has no rank.
#'
#' @param power What season_power() returns.
current_teams <- function(con, season, latest, power = season_power(con, season)) {
  teams <- query_sql_file(con, "season_teams.sql", list(season))
  if (nrow(teams) == 0) {
    stop(sprintf("No teams for the %d season in the database. Run `Rscript scripts/refresh.R`, then try again.",
                 season), call. = FALSE)
  }
  weekly <- query_sql_file(con, "weekly_ratings.sql")
  for (source in RATING_SOURCES) {
    week <- latest$week[latest$source == source]
    ratings <- weekly[weekly$source == source & weekly$season == season &
                        weekly$week %in% week, , drop = FALSE]
    teams[[source]] <- ratings$rating[match(teams$team_id, ratings$team_id)]
  }
  teams$power <- current_power(power$current, teams$team_id)
  for (model in names(MODEL_LABELS)) {
    teams[[paste0(model, "_rank")]] <-
      as.integer(rank(-teams[[model]], ties.method = "min", na.last = "keep"))
  }
  teams$tier <- as.integer(is_power_team(teams$conference, teams$team_id, season))

  preseason <- load_preseason(con)
  preseason <- preseason[preseason$season == season, , drop = FALSE]
  at <- match(teams$team_id, preseason$team_id)
  teams$talent_z <- ifelse(is.na(at), 0, preseason$talent_z[at])
  teams$returning_z <- ifelse(is.na(at), 0, preseason$returning_z[at])
  teams
}

#' Power ratings through `season`: what power_ratings() returns.
season_power <- function(con, season) {
  games <- query_sql_file(con, "rating_games.sql", list(BURN_IN_SEASON))
  if (!season %in% games$season) {
    stop(sprintf("The Power rating needs the %d schedule, and the database has no %d games. ",
                 season, season),
         "Run `Rscript scripts/refresh.R` to load them, then try again.", call. = FALSE)
  }
  games <- games[games$season <= season, , drop = FALSE]
  power_ratings(games, query_sql_file(con, "team_conferences.sql"))
}

#' Each team's Power rating after every completed game so far this season.
#'
#' Only gaps between ratings matter for a spread, so the ratings are shifted
#' to average zero across these teams. That way they read like the others:
#' points better than an average FBS team.
#'
#' @param current team_id and power, from season_power()$current.
current_power <- function(current, team_ids) {
  power <- current$power[match(team_ids, current$team_id)]
  power - mean(power, na.rm = TRUE)
}

#' Weekly Power ratings, with the ratings after the last games played
#' standing in for any week past the end of the schedule so far.
#'
#' The weekly table only has the weeks that have games. After the last one
#' (championship weekend, say) the next ranking still needs ratings that
#' include it, and `current` has them.
#'
#' @param power What season_power() returns.
power_through <- function(power, weeks) {
  weekly <- power$weekly
  beyond <- weeks[weeks > max(weekly$week)]
  if (length(beyond) == 0) return(weekly)
  rbind(weekly, do.call(rbind, lapply(beyond, function(week) {
    data.frame(team_id = power$current$team_id, week = as.integer(week), power = power$current$power)
  })))
}

#' What every system said about every team going into each week so far.
#'
#' SP+, FPI and SRS come from the weekly snapshots, so they are missing for
#' weeks before the snapshots started. Elo comes from the snapshot when there
#' is one, and otherwise from the Elo each team took into its game that week.
#' Power is our own, so it covers every week.
#'
#' @param weeks Regular-season weeks to cover, usually 1 to the current week.
#' @param power_weekly team_id, week, power, from season_power()$weekly.
#' @return One row per team and week: week, team_id and one rating column
#'   per system, NA where a system has nothing for that week.
rating_history <- function(con, season, weeks, team_ids, power_weekly) {
  history <- expand.grid(team_id = team_ids, week = as.integer(weeks))
  key <- function(df) paste(df$team_id, df$week)

  weekly <- query_sql_file(con, "weekly_ratings.sql")
  weekly <- weekly[weekly$season == season, , drop = FALSE]
  for (source in RATING_SOURCES) {
    saved <- weekly[weekly$source == source, , drop = FALSE]
    history[[source]] <- as.numeric(saved$rating[match(key(history), key(saved))])
  }
  game_elo <- query_sql_file(con, "elo_by_week.sql", list(season, season))
  history$elo <- ifelse(is.na(history$elo), elo_entering_week(history, game_elo), history$elo)

  power <- power_weekly$power[match(key(history), key(power_weekly))]
  power <- stats::ave(power, history$team_id, FUN = fill_idle_weeks)
  history$power <- power - stats::ave(power, history$week, FUN = function(x) mean(x, na.rm = TRUE))

  history <- history[order(history$week, history$team_id), c("week", "team_id", names(MODEL_LABELS))]
  rownames(history) <- NULL
  history
}

#' Fill the weeks with no games at all, in week order.
#'
#' A rating only changes when games are played. So a week nobody played
#' carries the rating of the next week that has one, or the last one known.
fill_idle_weeks <- function(x) {
  known <- which(!is.na(x))
  if (length(known) == 0) return(x)
  for (i in which(is.na(x))) {
    later <- known[known > i]
    x[i] <- x[if (length(later) > 0) later[1] else known[length(known)]]
  }
  x
}

#' The Elo each team took into each week, from its games.
#'
#' Elo only changes when a team plays. So in a bye week a team's Elo is
#' whatever it takes into its next game.
#'
#' @param history Rows of team_id and week.
#' @param game_elo Rows of team_id, week and elo: one per game played or
#'   scheduled.
#' @return One Elo per row of `history`, NA when the team has no game that
#'   week or later.
elo_entering_week <- function(history, game_elo) {
  game_elo <- game_elo[order(game_elo$team_id, game_elo$week), , drop = FALSE]
  by_team <- split(game_elo, game_elo$team_id)
  vapply(seq_len(nrow(history)), function(i) {
    games <- by_team[[as.character(history$team_id[i])]]
    if (is.null(games)) return(NA_real_)
    next_game <- which(games$week >= history$week[i])
    if (length(next_game) == 0) NA_real_ else as.numeric(games$elo[next_game[1]])
  }, numeric(1))
}

#' This season's finished regular-season games.
season_results <- function(con, season) {
  results <- query_sql_file(con, "season_results.sql", list(season))
  results$neutral_site <- results$neutral_site == 1
  results
}

#' This week's unplayed FBS games, with the median sportsbook spread.
current_slate <- function(con, season, week) {
  slate <- query_sql_file(con, "slate_games.sql", list(season, week))
  slate$neutral_site <- slate$neutral_site == 1
  lines <- median_spread(query_sql_file(con, "slate_lines.sql", list(season, week)))
  slate$market_spread_home <- lines$spread[match(slate$game_id, lines$game_id)]
  slate
}
