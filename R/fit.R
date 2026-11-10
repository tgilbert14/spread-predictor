# Fit the two house models (Elo and Power), validate them season by season,
# score the holdout season, and choose blend weights. The result is the
# params list that scripts/fit.R writes to data/params.json (see
# docs/data-dictionary.md).
#
# The house models fit only on numbers known before kickoff: CFBD's pregame
# Elo and our walk-forward Power rating. Season-final ratings are only ever
# used for the diagnostic labeled as leaked.
#
# Seasons (R/config.R): BURN_IN_SEASON warms up the Power rating and is not
# fit on. FIT_SEASONS are fit and cross-validated. HOLDOUT_SEASON is scored
# with parameters from FIT_SEASONS and never used to fit anything.

# Weekly-snapshot games needed before fitted blend weights are considered.
MIN_BLEND_GAMES <- 300

# How hard fitted blend weights are pulled toward equal, measured in games'
# worth of evidence. Keeps a few odd weeks from swinging the weights.
BLEND_SHRINK_GAMES <- 100

# Favorite win probability bins for the calibration table.
CALIBRATION_BREAKS <- seq(0.5, 1.0, by = 0.1)

# The forecasts scored in the accuracy tables, in display order.
FORECAST_LABELS <- c(
  elo = "Elo, power-conference corrected",
  power = "Power",
  house = "Elo and Power average",
  line = "Closing line"
)

# Column types of the table-like fields in params.json, matching
# demo_app_data()$params. read_params() uses these to rebuild data frames.
METRIC_COLUMNS <- c(model = "character", label = "character", n = "integer",
                    mae = "numeric", win_rate = "numeric", brier = "numeric")
PARAM_TABLES <- list(
  metrics = METRIC_COLUMNS,
  holdout = METRIC_COLUMNS,
  calibration = c(bin_low = "numeric", bin_high = "numeric", n = "integer",
                  predicted = "numeric", actual = "numeric"),
  folds = c(season = "integer", k = "numeric", elo_tier = "numeric", power_scale = "numeric",
            h = "numeric", sigma = "numeric", mae = "numeric"),
  leaked_diagnostic = c(model = "character", n = "integer", mae = "numeric")
)

# Single numbers in params.json.
PARAM_NUMBERS <- c("k", "elo_tier", "power_scale", "h", "h_elo", "h_power", "sigma")

# ---- Database access --------------------------------------------------------

#' Open an existing database read-only, or say how to build it.
connect_readonly <- function(db_path) {
  if (!file.exists(db_path)) {
    stop(sprintf("No database at '%s'. Build it with `Rscript scripts/refresh.R`, then try again.",
                 db_path), call. = FALSE)
  }
  DBI::dbConnect(RSQLite::SQLite(), db_path, flags = RSQLite::SQLITE_RO)
}

#' Run one query file from sql/ and return the rows.
#'
#' @param params Values for the `?` placeholders, in order.
query_sql_file <- function(con, file, params = NULL) {
  path <- file.path(dirname(PATHS$schema), file)
  sql <- paste(readLines(path, warn = FALSE), collapse = "\n")
  if (is.null(params)) {
    DBI::dbGetQuery(con, sql)
  } else {
    DBI::dbGetQuery(con, sql, params = unname(as.list(params)))
  }
}

#' Completed FBS-vs-FBS games with a home margin, all seasons.
load_completed_games <- function(con) {
  games <- query_sql_file(con, "fit_games.sql")
  games$neutral_site <- as.integer(games$neutral_site)
  games
}

#' Walk-forward Power ratings from every game in the database.
load_power_ratings <- function(con) {
  power_ratings(query_sql_file(con, "rating_games.sql", list(BURN_IN_SEASON)),
                query_sql_file(con, "team_conferences.sql"))
}

#' Closing line per game: the median spread across sportsbooks.
#'
#' @param lines Rows of game_id and spread, one per sportsbook.
#' @return game_id and spread (home-relative, -7 means home favored by 7).
median_spread <- function(lines) {
  if (nrow(lines) == 0) {
    return(data.frame(game_id = integer(), spread = numeric()))
  }
  spreads <- tapply(lines$spread, lines$game_id, stats::median)
  data.frame(game_id = as.integer(names(spreads)), spread = as.numeric(spreads))
}

# ---- Model inputs -----------------------------------------------------------

#' Completed FBS games with every input the house models use.
#'
#' Adds home (1 unless neutral), elo_gap (home minus away pregame Elo),
#' tier_diff (home power team minus away power team: -1, 0 or 1) and
#' power_gap (home minus away pregame Power rating).
#'
#' @param pregame_power The pregame table from power_ratings().
add_model_inputs <- function(games, pregame_power) {
  games$home <- 1L - games$neutral_site
  games$elo_gap <- games$home_pregame_elo - games$away_pregame_elo
  games$tier_diff <-
    as.integer(is_power_team(games$home_conference, games$home_id, games$season)) -
    as.integer(is_power_team(games$away_conference, games$away_id, games$season))
  at <- match(games$game_id, pregame_power$game_id)
  games$power_gap <- pregame_power$home_power[at] - pregame_power$away_power[at]
  games
}

#' Keep the games the house models can use: given seasons, every input known.
house_set <- function(games, seasons) {
  keep <- games$season %in% seasons & !is.na(games$elo_gap) & !is.na(games$power_gap)
  games[keep, , drop = FALSE]
}

# ---- House models -----------------------------------------------------------

#' Fit the Elo model and the Power model, each one regression with no intercept.
#'
#' Elo:   home_margin = elo_gap / k + elo_tier * tier_diff + h_elo * home
#' Power: home_margin = power_scale * power_gap + h_power * home
#'
#' @return k, elo_tier, h_elo, power_scale, h_power, and h, the shared home
#'   field the app uses (the mean of the two).
fit_house <- function(games) {
  elo <- stats::coef(stats::lm(home_margin ~ 0 + elo_gap + tier_diff + home, data = games))
  power <- stats::coef(stats::lm(home_margin ~ 0 + power_gap + home, data = games))
  if (anyNA(elo) || elo[["elo_gap"]] <= 0) {
    stop("The Elo fit failed. It needs games with different pregame Elos, some non-neutral sites, ",
         "and games between power and non-power teams. Check home_pregame_elo, away_pregame_elo ",
         "and the conferences in the teams table, then rebuild the database.", call. = FALSE)
  }
  if (anyNA(power) || power[["power_gap"]] <= 0) {
    stop("The Power fit failed. It needs a season of games before the fit seasons to warm up. ",
         "Check BURN_IN_SEASON and FIT_SEASONS in R/config.R, then rebuild the database.",
         call. = FALSE)
  }
  list(
    k = 1 / elo[["elo_gap"]], elo_tier = elo[["tier_diff"]], h_elo = elo[["home"]],
    power_scale = power[["power_gap"]], h_power = power[["home"]],
    h = mean(c(elo[["home"]], power[["home"]]))
  )
}

#' Predicted home margins: the Elo model, the Power model and their average.
#'
#' Each model uses its own home field. Their average then carries the mean
#' of the two, which is the shared h the app uses, so the house blend here is
#' exactly what the app computes from Elo and Power.
predict_house <- function(games, fit) {
  elo <- games$elo_gap / fit$k + fit$elo_tier * games$tier_diff + fit$h_elo * games$home
  power <- fit$power_scale * games$power_gap + fit$h_power * games$home
  data.frame(elo = elo, power = power, house = (elo + power) / 2)
}

#' SD of real margins around a prediction: the typical miss, in points.
miss_sd <- function(actual, predicted) {
  stats::sd(actual - predicted)
}

#' Leave-one-season-out validation.
#'
#' Each fold's win probabilities use the sigma of its own training games, so
#' nothing about the held-out season leaks in.
#'
#' @return folds (one row per held-out season) and predictions (every game,
#'   with its out-of-fold elo, power and house margins and that fold's sigma).
validate_by_season <- function(games) {
  seasons <- sort(unique(games$season))
  if (length(seasons) < 2) {
    stop("Season-by-season validation needs at least two seasons of games. ",
         "Add seasons to FIT_SEASONS in R/config.R or load more history.", call. = FALSE)
  }
  folds <- lapply(seasons, function(season) {
    held_out <- games$season == season
    train <- games[!held_out, , drop = FALSE]
    fit <- fit_house(train)
    test <- cbind(games[held_out, , drop = FALSE], predict_house(games[held_out, , drop = FALSE], fit))
    test$sigma <- miss_sd(train$home_margin, predict_house(train, fit)$house)
    row <- data.frame(season = as.integer(season), k = fit$k, elo_tier = fit$elo_tier,
                      power_scale = fit$power_scale, h = fit$h, sigma = test$sigma[1],
                      mae = mean(abs(test$home_margin - test$house)))
    list(row = row, predictions = test)
  })
  list(
    folds = do.call(rbind, lapply(folds, `[[`, "row")),
    predictions = do.call(rbind, lapply(folds, `[[`, "predictions"))
  )
}

# ---- Metrics ----------------------------------------------------------------

#' Accuracy of predicted home margins.
#'
#' Ties have no winner, so they count toward MAE but not win rate or Brier.
#' A predicted margin of exactly 0 is a coin flip and scores half a win.
#'
#' @param sigma One value, or one per game.
#' @return One row: n, mae, win_rate, brier.
score_margins <- function(predicted, actual, sigma) {
  decided <- actual != 0
  picked_right <- ifelse(predicted == 0, 0.5, sign(predicted) == sign(actual))
  win_prob <- stats::pnorm(predicted / sigma)
  home_won <- actual > 0
  data.frame(
    n = length(actual),
    mae = mean(abs(actual - predicted)),
    win_rate = if (any(decided)) mean(picked_right[decided]) else NA_real_,
    brier = if (any(decided)) mean((win_prob[decided] - home_won[decided])^2) else NA_real_
  )
}

#' Stop if the closing lines point the wrong way.
#'
#' -spread should rise with the real home margin. If it falls, the spread
#' sign was flipped somewhere upstream and every comparison would be wrong.
check_line_sign <- function(line_margin, actual_margin) {
  if (length(line_margin) < 3) return(invisible(TRUE))
  r <- stats::cor(line_margin, actual_margin)
  if (!is.na(r) && r < 0) {
    stop(sprintf(paste0(
      "Closing lines point the wrong way: -spread and the real home margin have correlation %.2f. ",
      "lines.spread must be home-relative, with -7 meaning the home team is favored by 7 ",
      "(see docs/data-dictionary.md). Fix the sign in the ingest step and rebuild the database."), r),
      call. = FALSE)
  }
  invisible(TRUE)
}

#' Elo, Power, their average and the closing line, all on the same games.
#'
#' Only games with a closing line are scored, so the comparison is fair.
#' With no lines at all, the house models are scored on every game and the
#' line row is left out.
#'
#' @param predictions Rows with game_id, home_margin, elo, power, house and
#'   sigma (one per game).
#' @param sigma Used for the line's win probabilities. The line has no
#'   spread of outcomes of its own, so it borrows the model's.
#' @return Rows of model, label, n, mae, win_rate, brier.
score_forecasts <- function(predictions, lines, sigma) {
  if (nrow(predictions) == 0) return(as_param_table(NULL, METRIC_COLUMNS))
  scored <- merge(predictions, lines, by = "game_id")
  if (nrow(scored) == 0) {
    scored <- predictions
  } else {
    scored$line <- -scored$spread
    check_line_sign(scored$line, scored$home_margin)
  }
  models <- intersect(names(FORECAST_LABELS), names(scored))
  rows <- lapply(models, function(model) {
    model_sigma <- if (model == "line") sigma else scored$sigma
    cbind(data.frame(model = model, label = FORECAST_LABELS[[model]]),
          score_margins(scored[[model]], scored$home_margin, model_sigma))
  })
  do.call(rbind, rows)
}

#' How often favorites won, against how often the model said they would.
#'
#' Probabilities are folded onto the favorite, so they run from 0.5 to 1.
#'
#' @param predictions Rows with `predicted` (home margin), `sigma` and
#'   `home_margin` (the real one).
calibration_table <- function(predictions) {
  decided <- predictions[predictions$home_margin != 0, , drop = FALSE]
  p_home <- stats::pnorm(decided$predicted / decided$sigma)
  home_favored <- p_home >= 0.5
  p_favorite <- ifelse(home_favored, p_home, 1 - p_home)
  favorite_won <- ifelse(home_favored, decided$home_margin > 0, decided$home_margin < 0)

  n_bins <- length(CALIBRATION_BREAKS) - 1
  bin <- findInterval(p_favorite, CALIBRATION_BREAKS, rightmost.closed = TRUE)
  bin_mean <- function(x) {
    vapply(seq_len(n_bins), function(i) if (any(bin == i)) mean(x[bin == i]) else NA_real_,
           numeric(1))
  }
  data.frame(
    bin_low = CALIBRATION_BREAKS[-length(CALIBRATION_BREAKS)],
    bin_high = CALIBRATION_BREAKS[-1],
    n = tabulate(bin, nbins = n_bins),
    predicted = bin_mean(p_favorite),
    actual = bin_mean(favorite_won)
  )
}

#' Look up one rating per row by a composite key.
lookup_rating <- function(ratings, ratings_key, wanted_key) {
  ratings$rating[match(wanted_key, ratings_key)]
}

#' LEAKED: accuracy of season-final SP+, FPI and SRS on the same games.
#'
#' Final ratings already know these results, so this flatters them. It only
#' exists to catch bugs (a wrong join or sign shows up as a terrible MAE).
#' Never use it to fit or to judge the model.
#'
#' @param finals Rows of source, season, team_id, rating with is_final = 1.
leaked_diagnostic <- function(finals, games, h) {
  rows <- lapply(c("sp", "fpi", "srs"), function(source) {
    ratings <- finals[finals$source == source, , drop = FALSE]
    key <- paste(ratings$season, ratings$team_id)
    margin <- lookup_rating(ratings, key, paste(games$season, games$home_id)) -
      lookup_rating(ratings, key, paste(games$season, games$away_id)) +
      h * (1 - games$neutral_site)
    ok <- !is.na(margin)
    if (!any(ok)) return(NULL)
    data.frame(model = source, n = sum(ok), mae = mean(abs(games$home_margin[ok] - margin[ok])))
  })
  out <- do.call(rbind, rows)
  if (is.null(out)) as_param_table(NULL, PARAM_TABLES$leaked_diagnostic) else out
}

# ---- Blend weights ----------------------------------------------------------

#' Equal weight on every system in the blend.
equal_weights <- function() {
  as.list(stats::setNames(rep(1 / length(BLEND_SYSTEMS), length(BLEND_SYSTEMS)), BLEND_SYSTEMS))
}

#' Per-system home margins (before home field) for games with weekly snapshots.
#'
#' The snapshot labeled week W is what SP+, FPI, SRS and Elo said before
#' week W, so it is matched to week W games. Power needs no snapshot: its
#' walk-forward pregame rating is already on each game. Postseason games are
#' skipped because CFBD numbers their weeks from 1 again, which would match
#' the wrong snapshot.
#'
#' @param games Completed games from add_model_inputs().
#' @param fit The house fit: k, elo_tier, power_scale and h.
#' @return X (one column per system, games with every system present), y
#'   (home margin with home field removed) and week (a season-week label).
blend_design <- function(games, weekly, fit) {
  games <- games[games$season_type == "regular", , drop = FALSE]
  game_key <- function(team_id) paste(games$season, games$week, team_id)
  margins <- lapply(stats::setNames(RATING_SOURCES, RATING_SOURCES), function(source) {
    ratings <- weekly[weekly$source == source, , drop = FALSE]
    key <- paste(ratings$season, ratings$week, ratings$team_id)
    lookup_rating(ratings, key, game_key(games$home_id)) -
      lookup_rating(ratings, key, game_key(games$away_id))
  })
  margins$elo <- margins$elo / fit$k + fit$elo_tier * games$tier_diff
  margins$power <- fit$power_scale * games$power_gap

  X <- matrix(unlist(margins[BLEND_SYSTEMS]), ncol = length(BLEND_SYSTEMS),
              dimnames = list(NULL, BLEND_SYSTEMS))
  complete <- stats::complete.cases(X)
  list(
    X = X[complete, , drop = FALSE],
    y = (games$home_margin - fit$h * (1 - games$neutral_site))[complete],
    week = paste(games$season, games$week)[complete]
  )
}

#' Non-negative blend weights, shrunk toward equal, summing to 1.
#'
#' The shrinkage is a ridge penalty written as extra rows, one per system,
#' each saying "this weight is equal". They are scaled so the penalty is
#' worth about `shrink_games` real games.
fit_blend_weights <- function(X, y, shrink_games = BLEND_SHRINK_GAMES) {
  equal <- unlist(equal_weights())[colnames(X)]
  scale <- sqrt(shrink_games * mean(X^2))
  A <- rbind(X, scale * diag(ncol(X)))
  b <- c(y, scale * equal)
  w <- nnls::nnls(A, b)$x
  if (sum(w) <= 0) return(equal / sum(equal))
  stats::setNames(w / sum(w), colnames(X))
}

#' Leave-one-week-out MAE for fitted and for equal weights.
blend_cv_mae <- function(design, shrink_games = BLEND_SHRINK_GAMES) {
  equal <- unlist(equal_weights())[colnames(design$X)]
  errors <- lapply(unique(design$week), function(week) {
    test <- design$week == week
    w <- fit_blend_weights(design$X[!test, , drop = FALSE], design$y[!test], shrink_games)
    X_test <- design$X[test, , drop = FALSE]
    cbind(fitted = abs(design$y[test] - drop(X_test %*% w)),
          equal = abs(design$y[test] - drop(X_test %*% equal)))
  })
  colMeans(do.call(rbind, errors))
}

#' Pick the blend weights, and say why.
#'
#' Fitted weights are adopted only with enough snapshot games and only if
#' they beat equal weights out of sample. Otherwise equal weights stand.
#'
#' @param design Result of blend_design().
#' @return weights (named list), method ("equal" or "fitted") and note.
choose_weights <- function(design, min_games = MIN_BLEND_GAMES) {
  n <- nrow(design$X)
  n_weeks <- length(unique(design$week))
  if (n < min_games || n_weeks < 2) {
    return(list(
      weights = equal_weights(), method = "equal",
      note = sprintf("Equal weights: %d games have weekly snapshots from every system, and fitting needs at least %d across two or more weeks.",
                     n, min_games)
    ))
  }
  cv <- blend_cv_mae(design)
  if (cv[["fitted"]] < cv[["equal"]]) {
    return(list(
      weights = as.list(fit_blend_weights(design$X, design$y)), method = "fitted",
      note = sprintf("Fitted weights: leave-one-week-out MAE %.2f vs %.2f for equal weights, over %d games.",
                     cv[["fitted"]], cv[["equal"]], n)
    ))
  }
  list(
    weights = equal_weights(), method = "equal",
    note = sprintf("Equal weights: fitted weights did not beat them out of sample (MAE %.2f vs %.2f, over %d games).",
                   cv[["fitted"]], cv[["equal"]], n)
  )
}

# ---- Putting it together ----------------------------------------------------

#' Fit everything and return the params list described in the data dictionary.
fit_params <- function(con, fit_seasons = FIT_SEASONS, holdout_season = HOLDOUT_SEASON) {
  games <- add_model_inputs(load_completed_games(con), load_power_ratings(con)$pregame)
  fit_set <- house_set(games, fit_seasons)
  if (nrow(fit_set) == 0) {
    stop(sprintf("No completed FBS games with pregame Elo and Power ratings in seasons %s. Run `Rscript scripts/refresh.R` to load them.",
                 paste(range(fit_seasons), collapse = "-")), call. = FALSE)
  }

  fit <- fit_house(fit_set)
  validation <- validate_by_season(fit_set)
  oof <- validation$predictions
  sigma <- miss_sd(oof$home_margin, oof$house)
  lines <- median_spread(query_sql_file(con, "lines.sql"))

  holdout_set <- house_set(games, holdout_season)
  holdout <- cbind(holdout_set, predict_house(holdout_set, fit))
  holdout$sigma <- rep(sigma, nrow(holdout))

  fit$sigma <- sigma
  blend <- choose_weights(blend_design(games, query_sql_file(con, "weekly_ratings.sql"), fit))

  list(
    fit_date = format(Sys.Date()),
    fit_seasons = sort(unique(as.integer(fit_set$season))),
    holdout_season = as.integer(holdout_season),
    k = fit$k,
    elo_tier = fit$elo_tier,
    power_scale = fit$power_scale,
    h = fit$h,
    h_elo = fit$h_elo,
    h_power = fit$h_power,
    sigma = sigma,
    power = POWER_RATING,
    weights = blend$weights,
    weights_method = blend$method,
    weights_note = blend$note,
    metrics = score_forecasts(oof, lines, sigma),
    holdout = score_forecasts(holdout, lines, sigma),
    calibration = calibration_table(data.frame(predicted = oof$house, sigma = oof$sigma,
                                               home_margin = oof$home_margin)),
    folds = validation$folds,
    leaked_diagnostic = leaked_diagnostic(query_sql_file(con, "final_ratings.sql"), fit_set, fit$h)
  )
}

# ---- params.json ------------------------------------------------------------

#' Write params as pretty JSON. Tables become arrays of row objects.
write_params <- function(params, path = PATHS$params) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  jsonlite::write_json(params, path, auto_unbox = TRUE, pretty = TRUE, digits = 4, na = "null")
  invisible(path)
}

#' Rebuild one table-like params field as a data frame with fixed columns.
#'
#' JSON loses the columns of an empty table and turns whole numbers into
#' integers, so the column list and types come from PARAM_TABLES instead.
as_param_table <- function(rows, types) {
  n <- if (is.data.frame(rows)) nrow(rows) else 0
  columns <- lapply(names(types), function(column) {
    values <- if (is.data.frame(rows)) rows[[column]] else NULL
    if (is.null(values)) values <- rep(NA, n)
    match.fun(paste0("as.", types[[column]]))(values)
  })
  as.data.frame(stats::setNames(columns, names(types)), stringsAsFactors = FALSE)
}

#' Read params.json into the same shape as demo_app_data()$params.
read_params <- function(path = PATHS$params) {
  if (!file.exists(path)) {
    stop(sprintf("No fitted parameters at '%s'. Run `Rscript scripts/fit.R` first.", path),
         call. = FALSE)
  }
  params <- jsonlite::read_json(path, simplifyVector = TRUE)
  params$fit_seasons <- as.integer(params$fit_seasons)
  params$holdout_season <- as.integer(params$holdout_season)
  for (field in PARAM_NUMBERS) params[[field]] <- as.numeric(params[[field]])
  params$power <- lapply(params$power, as.numeric)

  # Weights were rounded when written, so renormalize to sum to exactly 1.
  weights <- vapply(params$weights, as.numeric, numeric(1))
  params$weights <- as.list(weights / sum(weights))

  for (field in names(PARAM_TABLES)) {
    params[[field]] <- as_param_table(params[[field]], PARAM_TABLES[[field]])
  }
  params
}

# ---- Gate report ------------------------------------------------------------

#' MAE of one forecast in a metrics table, or NA when it is not there.
forecast_mae <- function(metrics, model) {
  mae <- metrics$mae[metrics$model == model]
  if (length(mae) == 1) mae else NA_real_
}

#' Pass or look flags for the model gate. Thresholds are sanity bounds for
#' college football, not targets: a miss means look closer, not fail.
gate_checks <- function(params) {
  cv_house <- forecast_mae(params$metrics, "house")
  holdout_house <- forecast_mae(params$holdout, "house")
  # A bin's actual win rate wobbles with its size, so judge the calibration
  # gap in standard errors rather than a fixed number of points.
  cal <- params$calibration[params$calibration$n >= 30, , drop = FALSE]
  cal_se <- sqrt(cal$predicted * (1 - cal$predicted) / cal$n)
  data.frame(
    check = c(
      "k is between 15 and 40 Elo points per point",
      "the power-conference edge is between 5 and 15 points",
      "the Power scale is between 0.7 and 1.3",
      "home field is between 0 and 5 points",
      "the Elo and Power home fields are within 1 point of each other",
      "sigma is between 12 and 20 points",
      "every fold's k is within 10% of the full fit",
      "the closing line beats the house blend on MAE (the market should be sharper)",
      "the house blend beats Elo alone on cross-validated MAE",
      "the holdout MAE of the house blend is within 1 point of its cross-validated MAE",
      "calibration is within 3 standard errors in every bin with 30+ games"
    ),
    pass = c(
      params$k >= 15 && params$k <= 40,
      params$elo_tier >= 5 && params$elo_tier <= 15,
      params$power_scale >= 0.7 && params$power_scale <= 1.3,
      params$h >= 0 && params$h <= 5,
      abs(params$h_elo - params$h_power) <= 1,
      params$sigma >= 12 && params$sigma <= 20,
      all(abs(params$folds$k / params$k - 1) <= 0.10),
      isTRUE(forecast_mae(params$metrics, "line") < cv_house),
      isTRUE(cv_house < forecast_mae(params$metrics, "elo")),
      isTRUE(abs(holdout_house - cv_house) <= 1),
      all(abs(cal$predicted - cal$actual) <= 3 * cal_se)
    )
  )
}

#' The model gate report, as lines of text.
gate_report <- function(params) {
  show <- function(df) utils::capture.output(print(df, row.names = FALSE, digits = 3))
  checks <- gate_checks(params)
  power <- params$power
  c(
    sprintf("Model gate report (fit %s on seasons %s, holdout %s)", params$fit_date,
            paste(params$fit_seasons, collapse = ", "), params$holdout_season),
    "",
    sprintf("  k            %6.2f  Elo points per point of margin", params$k),
    sprintf("  elo_tier     %6.2f  points added to Elo per power-conference tier step", params$elo_tier),
    sprintf("  power_scale  %6.3f  points of margin per point of Power gap", params$power_scale),
    sprintf("  h            %6.2f  home field, points (Elo model %.2f, Power model %.2f)",
            params$h, params$h_elo, params$h_power),
    sprintf("  sigma        %6.2f  SD of real margin around the house blend, out of fold", params$sigma),
    sprintf("  Power settings: %s",
            paste(sprintf("%s %s", names(power), unlist(power)), collapse = ", ")),
    "",
    "Leave-one-season-out folds (mae is the house blend)", show(params$folds),
    "",
    "Out-of-fold accuracy (every row on the same games)", show(params$metrics),
    "",
    sprintf("Holdout season %s (fit on %s only)", params$holdout_season,
            paste(range(params$fit_seasons), collapse = " to ")),
    if (nrow(params$holdout) > 0) show(params$holdout) else "  (no completed holdout games yet)",
    "",
    "Calibration (favorite win probability, house blend, out of fold)", show(params$calibration),
    "",
    "LEAKED diagnostic: season-final ratings already know these results.",
    "For catching bugs only. Do not use it to judge the model.",
    if (nrow(params$leaked_diagnostic) > 0) show(params$leaked_diagnostic) else "  (no season-final ratings in the database)",
    "",
    sprintf("Blend weights (%s): %s", params$weights_method,
            paste(sprintf("%s %.3f", names(params$weights), unlist(params$weights)), collapse = ", ")),
    paste0("  ", params$weights_note),
    "",
    "Checks",
    sprintf("  [%s] %s", ifelse(checks$pass, "PASS", "LOOK"), checks$check),
    "",
    if (all(checks$pass)) "Gate: PASS" else "Gate: LOOK CLOSER at the items marked LOOK"
  )
}
