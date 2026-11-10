# Build data/app_data.rds, the only file the app reads.
# The shape is set in docs/data-dictionary.md and matches demo_app_data().

#' Build and save the app data.
#'
#' The current season is the latest one with weekly snapshots, and the week
#' is the latest snapshot week in it.
#'
#' @return The app data list, invisibly.
build_app_data <- function(db_path = PATHS$database, params_path = PATHS$params,
                           out_path = PATHS$app_data) {
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

  app_data <- list(
    meta = list(
      season = as.integer(season),
      week = as.integer(week),
      ratings_date = substr(max(latest$pulled_at, na.rm = TRUE), 1, 10),
      built_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
      is_demo = FALSE
    ),
    teams = current_teams(con, season, latest),
    params = params,
    slate = current_slate(con, season, week),
    coverage = coverage
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
current_teams <- function(con, season, latest) {
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
  teams$power <- current_power(con, season, teams$team_id)
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

#' Each team's Power rating after every completed game so far this season.
#'
#' Only gaps between ratings matter for a spread, so the ratings are shifted
#' to average zero across these teams. That way they read like the others:
#' points better than an average FBS team.
current_power <- function(con, season, team_ids) {
  games <- query_sql_file(con, "rating_games.sql", list(BURN_IN_SEASON))
  if (!season %in% games$season) {
    stop(sprintf("The Power rating needs the %d schedule, and the database has no %d games. ",
                 season, season),
         "Run `Rscript scripts/refresh.R` to load them, then try again.", call. = FALSE)
  }
  games <- games[games$season <= season, , drop = FALSE]
  current <- power_ratings(games, query_sql_file(con, "team_conferences.sql"))$current
  power <- current$power[match(team_ids, current$team_id)]
  power - mean(power, na.rm = TRUE)
}

#' This week's unplayed FBS games, with the median sportsbook spread.
current_slate <- function(con, season, week) {
  slate <- query_sql_file(con, "slate_games.sql", list(season, week))
  slate$neutral_site <- slate$neutral_site == 1
  lines <- median_spread(query_sql_file(con, "slate_lines.sql", list(season, week)))
  slate$market_spread_home <- lines$spread[match(slate$game_id, lines$game_id)]
  slate
}
