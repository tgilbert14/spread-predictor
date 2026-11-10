# Saved predictions and the scorecard.
#
# Each week, before the first kickoff, the pipeline saves our line for every
# slate game to data/snapshots/predictions/{season}_wk{WW}.csv. Once the games
# are final, each saved line is graded against the result, and against the
# market line saved next to it.
#
# Two rules keep the grades honest:
#   * A file is only written while every game of its week is still ahead.
#     A prediction saved after kickoff proves nothing.
#   * A file is never rewritten, even when the ratings or the model change.
#
# Margins in these files are home-relative: home points minus away points.
# market_spread_home is sportsbook style: -7 means the home team is favored by 7.

# Columns of a predictions file, in order, with their types.
PREDICTION_TYPES <- c(
  game_id = "integer", season = "integer", week = "integer", start_date = "character",
  home_id = "integer", home_team = "character", away_id = "integer", away_team = "character",
  neutral_site = "integer",
  sp = "numeric", fpi = "numeric", srs = "numeric", elo = "numeric", power = "numeric",
  blend = "numeric", win_prob_home = "numeric", sigma = "numeric",
  market_spread_home = "numeric", fit_date = "character", frozen_at = "character"
)
PREDICTION_COLUMNS <- names(PREDICTION_TYPES)

# Rows of the per-system table besides the five rating systems. (Built inside
# a function, because R/ files load in alphabetical order and MODEL_LABELS
# lives in R/predict.R.)
scorecard_labels <- function() c(MODEL_LABELS, blend = "Blend", market = "Market")


# ---- Saving ------------------------------------------------------------------

#' Path of one week's predictions file.
prediction_path <- function(season, week, root = PATHS$snapshots) {
  file.path(root, "predictions", sprintf("%d_wk%02d.csv", as.integer(season), as.integer(week)))
}

#' One row per game: each system's home margin, the blend and the home win
#' chance, exactly as the app shows them, plus the market line right now.
#'
#' Reuses predict_matchup() with the home team as Team A, so nothing here can
#' drift from the app. A game that cannot be predicted is left out with a note.
#'
#' @param games Rows like app_data$slate: game_id, start_date, home_id,
#'   away_id, neutral_site (logical) and market_spread_home.
#' @param week The week being predicted, for the early-season preseason points.
prediction_rows <- function(games, teams, params, season, week, frozen_at = format_utc()) {
  rows <- lapply(seq_len(nrow(games)), function(i) {
    game <- games[i, , drop = FALSE]
    neutral <- isTRUE(as.logical(game$neutral_site))
    pred <- tryCatch(
      predict_matchup(game$home_id, game$away_id, if (neutral) "neutral" else "a_home",
                      teams, params, week = week),
      error = function(e) NULL
    )
    if (is.null(pred)) {
      message("Left game ", game$game_id, " out of the saved predictions: it could not be predicted.")
      return(NULL)
    }
    # A system left out of this matchup gets an empty cell, not a number.
    margin <- stats::setNames(ifelse(pred$models$weight > 0, pred$models$margin, NA), pred$models$model)
    data.frame(
      game_id = game$game_id, season = season, week = week, start_date = game$start_date,
      home_id = pred$team_a$team_id, home_team = pred$team_a$school,
      away_id = pred$team_b$team_id, away_team = pred$team_b$school,
      neutral_site = as.integer(neutral),
      sp = round(margin[["sp"]], 2), fpi = round(margin[["fpi"]], 2), srs = round(margin[["srs"]], 2),
      elo = round(margin[["elo"]], 2), power = round(margin[["power"]], 2),
      blend = round(pred$spread, 2), win_prob_home = round(pred$win_prob_a, 4),
      sigma = round(params$sigma, 4), market_spread_home = game$market_spread_home,
      fit_date = as.character(params$fit_date), frozen_at = frozen_at,
      stringsAsFactors = FALSE
    )
  })
  as_param_table(do.call(rbind, rows), PREDICTION_TYPES)
}

#' TRUE when any game of the week is under way or played.
#'
#' @param kickoffs Rows of start_date and completed (week_kickoffs.sql).
week_has_started <- function(kickoffs, now = Sys.time()) {
  kickoff <- parse_utc(kickoffs$start_date)
  any(kickoffs$completed %in% c(1, TRUE)) || any(!is.na(kickoff) & kickoff <= now)
}

#' Save this week's predictions, once, before the first kickoff.
#'
#' Never rewrites a file, and never writes once any game of the week has
#' kicked off. Both cases are reported with a plain message, not an error,
#' so the rest of the refresh carries on.
#'
#' @param app_data Built by build_app_data(): its meta, teams, params and slate.
#' @return TRUE if a new file was written, invisibly.
freeze_predictions <- function(app_data = readRDS(PATHS$app_data), db_path = PATHS$database,
                               root = PATHS$snapshots, now = Sys.time()) {
  season <- app_data$meta$season
  week <- app_data$meta$week
  path <- prediction_path(season, week, root)

  if (isTRUE(app_data$meta$is_demo)) {
    message("Not saving predictions: this is demo data.")
    return(invisible(FALSE))
  }
  if (file.exists(path)) {
    message("Predictions for week ", week, " are already saved in ", path,
            ". Saved predictions are never rewritten.")
    return(invisible(FALSE))
  }
  con <- connect_readonly(db_path)
  kickoffs <- tryCatch(query_sql_file(con, "week_kickoffs.sql", list(season, week)),
                       finally = DBI::dbDisconnect(con))
  if (week_has_started(kickoffs, now)) {
    message("Not saving predictions for week ", week, ": a game has already kicked off, and a ",
            "prediction saved after kickoff proves nothing. Next week's are saved on the first ",
            "refresh before its first game.")
    return(invisible(FALSE))
  }
  if (nrow(app_data$slate) == 0) {
    message("No games on the week ", week, " slate, so there are no predictions to save.")
    return(invisible(FALSE))
  }

  rows <- prediction_rows(app_data$slate, app_data$teams, app_data$params, season, week,
                          frozen_at = format_utc(now))
  invisible(write_snapshot(rows, path))
}


# ---- Reading -----------------------------------------------------------------

#' Every saved predictions file, stacked. Zero rows when there are none.
load_predictions <- function(root = PATHS$snapshots) {
  files <- list.files(file.path(root, "predictions"), pattern = "^[0-9]{4}_wk[0-9]{2}\\.csv$",
                      full.names = TRUE)
  rows <- lapply(files, function(path) as_param_table(read_snapshot(path), PREDICTION_TYPES))
  as_param_table(do.call(rbind, rows), PREDICTION_TYPES)
}

#' Add the market line at the time of saving, and how far it has moved since.
#'
#' market_move is in points of expected home margin, positive when the market
#' has moved toward the home team. The expected home margin is minus the
#' spread, so the move is the old spread minus the new one.
#'
#' @param slate app_data$slate.
#' @param predictions Saved predictions; only this season and week are used.
add_line_movement <- function(slate, predictions, season, week) {
  frozen <- predictions[predictions$season == season & predictions$week == week, , drop = FALSE]
  slate$market_at_freeze <- frozen$market_spread_home[match(slate$game_id, frozen$game_id)]
  slate$market_move <- slate$market_at_freeze - slate$market_spread_home
  slate
}


# ---- Grading -----------------------------------------------------------------

#' Grade saved predictions against final scores.
#'
#' Per game: the final home margin, how far we missed, how far the market
#' (the line saved with the prediction) missed, whether we picked the winner,
#' who was closer, and, when we disagreed with the market by DISAGREE_POINTS
#' or more, whether the result landed on our side of the market line. A
#' result exactly on the line (a push) counts for neither side.
#'
#' Games not yet played keep their row, with NA in every result column.
#'
#' @param predictions Rows from load_predictions().
#' @param results Rows of game_id, completed, home_points, away_points.
#' @return predictions plus home_points, away_points, final_margin,
#'   our_error, market_error, picked_winner, closer ("us", "market" or
#'   "tie"), disagreed and our_side.
grade_predictions <- function(predictions, results) {
  games <- predictions
  at <- match(games$game_id, results$game_id)
  played <- !is.na(at) & results$completed[at] %in% c(1, TRUE) &
    !is.na(results$home_points[at]) & !is.na(results$away_points[at])
  games$home_points <- as.integer(ifelse(played, results$home_points[at], NA))
  games$away_points <- as.integer(ifelse(played, results$away_points[at], NA))

  margin <- games$home_points - games$away_points
  market_margin <- -games$market_spread_home
  games$final_margin <- margin
  games$our_error <- abs(games$blend - margin)
  games$market_error <- abs(market_margin - margin)
  games$picked_winner <- sign(games$blend) == sign(margin)

  # Rounded so a tie in the miss is a tie, not a floating-point accident.
  edge <- round(games$market_error - games$our_error, 2)
  games$closer <- ifelse(edge > 0, "us", ifelse(edge < 0, "market", "tie"))

  gap <- round(games$blend - market_margin, 2)
  landed <- round(margin - market_margin, 2)
  games$disagreed <- abs(gap) >= DISAGREE_POINTS
  games$our_side <- ifelse(games$disagreed & landed != 0, sign(landed) == sign(gap), NA)
  games
}

#' Summary of a set of graded games. Unplayed games are ignored.
#'
#' @return One row: games, our_miss, market_games, market_miss, winners,
#'   winner_share, closer (games where we beat the market), ties,
#'   disagree_games (graded disagreements that were not pushes) and
#'   disagree_our_side.
score_games <- function(games) {
  graded <- games[!is.na(games$final_margin), , drop = FALSE]
  n <- nrow(graded)
  lined <- !is.na(graded$market_error)
  average <- function(x) if (length(x) > 0) mean(x) else NA_real_
  data.frame(
    games = n,
    our_miss = average(graded$our_error),
    market_games = sum(lined),
    market_miss = average(graded$market_error[lined]),
    winners = sum(graded$picked_winner),
    winner_share = if (n > 0) sum(graded$picked_winner) / n else NA_real_,
    closer = sum(graded$closer %in% "us"),
    ties = sum(graded$closer %in% "tie"),
    disagree_games = sum(!is.na(graded$our_side)),
    disagree_our_side = sum(graded$our_side %in% TRUE)
  )
}

#' One summary row per week that has at least one graded game.
scorecard_weeks <- function(games) {
  graded <- games[!is.na(games$final_margin), , drop = FALSE]
  weeks <- unique(graded[c("season", "week")])
  weeks <- weeks[order(weeks$season, weeks$week), , drop = FALSE]
  rows <- lapply(seq_len(nrow(weeks)), function(i) {
    in_week <- graded$season == weeks$season[i] & graded$week == weeks$week[i]
    cbind(weeks[i, , drop = FALSE], score_games(graded[in_week, , drop = FALSE]))
  })
  if (length(rows) == 0) {
    return(cbind(data.frame(season = integer(), week = integer()), score_games(graded)[0, ]))
  }
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}

#' Average miss of every system, the blend and the market on graded games.
#'
#' Each system is scored on the games it rated, so counts can differ a little.
scorecard_systems <- function(games) {
  graded <- games[!is.na(games$final_margin), , drop = FALSE]
  labels <- scorecard_labels()
  rows <- lapply(names(labels), function(system) {
    miss <- if (system == "market") graded$market_error else abs(graded[[system]] - graded$final_margin)
    miss <- miss[!is.na(miss)]
    data.frame(system = system, label = labels[[system]], games = length(miss),
               avg_miss = if (length(miss) > 0) mean(miss) else NA_real_,
               stringsAsFactors = FALSE)
  })
  do.call(rbind, rows)
}

#' The scorecard for one season: graded games, weekly and season summaries,
#' and the per-system table. See docs/data-dictionary.md.
build_scorecard <- function(predictions, results, season) {
  games <- grade_predictions(predictions[predictions$season %in% season, , drop = FALSE], results)
  games <- games[order(games$week, games$start_date, games$game_id), , drop = FALSE]
  rownames(games) <- NULL
  list(
    games = games,
    weeks = scorecard_weeks(games),
    season = cbind(data.frame(season = as.integer(season)), score_games(games)),
    systems = scorecard_systems(games)
  )
}

#' A scorecard with nothing saved yet, in the same shape.
empty_scorecard <- function(season = NA_integer_) {
  results <- data.frame(game_id = integer(), completed = integer(),
                        home_points = integer(), away_points = integer())
  build_scorecard(as_param_table(NULL, PREDICTION_TYPES), results, season)
}

#' One line for the refresh log.
scorecard_message <- function(scorecard) {
  s <- scorecard$season
  if (s$games == 0) {
    saved <- nrow(scorecard$games)
    return(sprintf("Scorecard: no games graded yet (%d saved prediction%s waiting for results).",
                   saved, if (saved == 1) "" else "s"))
  }
  sprintf("Scorecard: %d games graded. Average miss %.1f points, the market's %.1f.",
          s$games, s$our_miss, s$market_miss)
}
