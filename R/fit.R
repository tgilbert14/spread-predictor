# Fit the Elo model (k, home field, sigma), validate it season by season,
# and choose blend weights. The result is the params list that
# scripts/fit.R writes to data/params.json (see docs/data-dictionary.md).
#
# Everything here fits on pregame Elo or weekly snapshots, both of which
# were known before kickoff. Season-final ratings are only ever used for the
# diagnostic labeled as leaked.

# Weekly-snapshot games needed before fitted blend weights are considered.
MIN_BLEND_GAMES <- 300

# How hard fitted blend weights are pulled toward equal, measured in games'
# worth of evidence. Keeps a few odd weeks from swinging the weights.
BLEND_SHRINK_GAMES <- 100

# Favorite win probability bins for the calibration table.
CALIBRATION_BREAKS <- seq(0.5, 1.0, by = 0.1)

# Column types of the table-like fields in params.json, matching
# demo_app_data()$params. read_params() uses these to rebuild data frames.
PARAM_TABLES <- list(
  metrics = c(model = "character", label = "character", n = "integer",
              mae = "numeric", win_rate = "numeric", brier = "numeric"),
  calibration = c(bin_low = "numeric", bin_high = "numeric", n = "integer",
                  predicted = "numeric", actual = "numeric"),
  folds = c(season = "integer", k = "numeric", h = "numeric",
            sigma = "numeric", mae = "numeric"),
  leaked_diagnostic = c(model = "character", n = "integer", mae = "numeric")
)

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

# ---- Elo fit and validation -------------------------------------------------

#' Keep the games the Elo model is fit on: training seasons, both Elos known.
elo_fit_set <- function(games, seasons = TRAINING_SEASONS) {
  keep <- games$season %in% seasons &
    !is.na(games$home_pregame_elo) & !is.na(games$away_pregame_elo)
  games[keep, , drop = FALSE]
}

#' Fit home_margin = elo_gap / k + h * home in one regression, no intercept.
#'
#' @return A list of k, h and sigma (residual SD, in points).
fit_elo <- function(games) {
  elo_gap <- games$home_pregame_elo - games$away_pregame_elo
  home <- 1 - games$neutral_site
  fit <- stats::lm(games$home_margin ~ 0 + elo_gap + home)
  slope <- stats::coef(fit)[["elo_gap"]]
  h <- stats::coef(fit)[["home"]]
  if (is.na(slope) || is.na(h) || slope <= 0) {
    stop("The Elo fit failed: it needs games with different pregame Elos and some non-neutral sites. ",
         "Check that home_pregame_elo and away_pregame_elo are filled in, then rebuild the database.",
         call. = FALSE)
  }
  list(k = 1 / slope, h = h, sigma = summary(fit)$sigma)
}

#' Expected home margin from pregame Elo and a fitted model.
predict_elo_margin <- function(games, fit) {
  (games$home_pregame_elo - games$away_pregame_elo) / fit$k +
    fit$h * (1 - games$neutral_site)
}

#' Leave-one-season-out validation.
#'
#' @return folds (one row per held-out season) and predictions (every game,
#'   with its out-of-fold `predicted` margin and that fold's `sigma`).
validate_by_season <- function(games) {
  seasons <- sort(unique(games$season))
  if (length(seasons) < 2) {
    stop("Season-by-season validation needs at least two seasons of games. ",
         "Add seasons to TRAINING_SEASONS in R/config.R or load more history.", call. = FALSE)
  }
  folds <- lapply(seasons, function(season) {
    held_out <- games$season == season
    fit <- fit_elo(games[!held_out, , drop = FALSE])
    test <- games[held_out, , drop = FALSE]
    test$predicted <- predict_elo_margin(test, fit)
    test$sigma <- fit$sigma
    row <- data.frame(season = as.integer(season), k = fit$k, h = fit$h, sigma = fit$sigma,
                      mae = mean(abs(test$home_margin - test$predicted)))
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

#' Out-of-fold Elo vs the closing line, on the games that have a line.
#'
#' Both rows are scored on the same games so the comparison is fair. With no
#' lines at all, only the Elo row is returned, scored on every game.
#'
#' @param sigma Used for the line's win probabilities. The line has no
#'   spread-of-outcomes of its own, so it borrows the model's.
compare_to_line <- function(predictions, lines, sigma) {
  scored <- merge(predictions, lines, by = "game_id")
  if (nrow(scored) == 0) {
    elo <- score_margins(predictions$predicted, predictions$home_margin, predictions$sigma)
    return(cbind(data.frame(model = "elo", label = "Elo (out of fold)"), elo))
  }
  line_margin <- -scored$spread
  check_line_sign(line_margin, scored$home_margin)
  rbind(
    cbind(data.frame(model = "elo", label = "Elo (out of fold)"),
          score_margins(scored$predicted, scored$home_margin, scored$sigma)),
    cbind(data.frame(model = "line", label = "Closing line"),
          score_margins(line_margin, scored$home_margin, sigma))
  )
}

#' How often favorites won, against how often the model said they would.
#'
#' Probabilities are folded onto the favorite, so they run from 0.5 to 1.
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

#' Equal weight on every rating system.
equal_weights <- function() {
  as.list(stats::setNames(rep(1 / length(RATING_SOURCES), length(RATING_SOURCES)),
                          RATING_SOURCES))
}

#' Per-model home margins for games that have weekly snapshots.
#'
#' The snapshot labeled week W is what the systems said before week W, so it
#' is matched to week W games. Postseason games are skipped because CFBD
#' numbers their weeks from 1 again, which would match the wrong snapshot.
#'
#' @return X (one column per model, games with every model present), y (home
#'   margin with home field removed) and week (a season-week label per row).
blend_design <- function(games, weekly, k, h) {
  games <- games[games$season_type == "regular", , drop = FALSE]
  game_key <- function(team_id) paste(games$season, games$week, team_id)
  margins <- lapply(RATING_SOURCES, function(source) {
    ratings <- weekly[weekly$source == source, , drop = FALSE]
    key <- paste(ratings$season, ratings$week, ratings$team_id)
    gap <- lookup_rating(ratings, key, game_key(games$home_id)) -
      lookup_rating(ratings, key, game_key(games$away_id))
    if (source == "elo") gap / k else gap
  })
  X <- matrix(unlist(margins), ncol = length(RATING_SOURCES),
              dimnames = list(NULL, RATING_SOURCES))
  complete <- stats::complete.cases(X)
  list(
    X = X[complete, , drop = FALSE],
    y = (games$home_margin - h * (1 - games$neutral_site))[complete],
    week = paste(games$season, games$week)[complete]
  )
}

#' Non-negative blend weights, shrunk toward equal, summing to 1.
#'
#' The shrinkage is a ridge penalty written as extra rows, one per model,
#' each saying "this weight is equal". They are scaled so the penalty is
#' worth about `shrink_games` real games.
fit_blend_weights <- function(X, y, shrink_games = BLEND_SHRINK_GAMES) {
  equal <- unlist(equal_weights())
  scale <- sqrt(shrink_games * mean(X^2))
  A <- rbind(X, scale * diag(ncol(X)))
  b <- c(y, scale * equal)
  w <- nnls::nnls(A, b)$x
  if (sum(w) <= 0) return(equal)
  stats::setNames(w / sum(w), colnames(X))
}

#' Leave-one-week-out MAE for fitted and for equal weights.
blend_cv_mae <- function(design, shrink_games = BLEND_SHRINK_GAMES) {
  equal <- unlist(equal_weights())
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
fit_params <- function(con, seasons = TRAINING_SEASONS) {
  completed <- load_completed_games(con)
  games <- elo_fit_set(completed, seasons)
  if (nrow(games) == 0) {
    stop(sprintf("No completed FBS games with pregame Elo in seasons %s. Run `Rscript scripts/refresh.R` to load them.",
                 paste(range(seasons), collapse = "-")), call. = FALSE)
  }

  fit <- fit_elo(games)
  validation <- validate_by_season(games)
  lines <- median_spread(query_sql_file(con, "lines.sql"))
  blend <- choose_weights(
    blend_design(completed, query_sql_file(con, "weekly_ratings.sql"), fit$k, fit$h)
  )

  list(
    fit_date = format(Sys.Date()),
    training_seasons = sort(unique(as.integer(games$season))),
    k = fit$k,
    h = fit$h,
    sigma = fit$sigma,
    weights = blend$weights,
    weights_method = blend$method,
    weights_note = blend$note,
    metrics = compare_to_line(validation$predictions, lines, fit$sigma),
    calibration = calibration_table(validation$predictions),
    folds = validation$folds,
    leaked_diagnostic = leaked_diagnostic(query_sql_file(con, "final_ratings.sql"), games, fit$h)
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
  params$training_seasons <- as.integer(params$training_seasons)
  for (field in c("k", "h", "sigma")) params[[field]] <- as.numeric(params[[field]])

  # Weights were rounded when written, so renormalize to sum to exactly 1.
  weights <- vapply(params$weights, as.numeric, numeric(1))
  params$weights <- as.list(weights / sum(weights))

  for (field in names(PARAM_TABLES)) {
    params[[field]] <- as_param_table(params[[field]], PARAM_TABLES[[field]])
  }
  params
}

# ---- Gate report ------------------------------------------------------------

#' Pass or check flags for the Phase 2 gate. Thresholds are sanity bounds
#' for college football, not targets: a miss means look closer, not fail.
gate_checks <- function(params) {
  metrics <- params$metrics
  elo_mae <- metrics$mae[metrics$model == "elo"]
  line_mae <- metrics$mae[metrics$model == "line"]
  # A bin's actual win rate wobbles with its size, so judge the calibration
  # gap in standard errors rather than a fixed number of points.
  cal <- params$calibration[params$calibration$n >= 30, , drop = FALSE]
  cal_se <- sqrt(cal$predicted * (1 - cal$predicted) / cal$n)
  data.frame(
    check = c(
      "k is between 15 and 40 Elo points per point",
      "home field is between 0 and 5 points",
      "sigma is between 12 and 20 points",
      "every fold's k is within 10% of the full fit",
      "the closing line beats Elo on MAE (the market should be sharper)",
      "calibration is within 3 standard errors in every bin with 30+ games"
    ),
    pass = c(
      params$k >= 15 && params$k <= 40,
      params$h >= 0 && params$h <= 5,
      params$sigma >= 12 && params$sigma <= 20,
      all(abs(params$folds$k / params$k - 1) <= 0.10),
      length(line_mae) == 1 && line_mae < elo_mae,
      all(abs(cal$predicted - cal$actual) <= 3 * cal_se)
    )
  )
}

#' The Phase 2 gate report, as lines of text.
gate_report <- function(params) {
  show <- function(df) utils::capture.output(print(df, row.names = FALSE, digits = 3))
  checks <- gate_checks(params)
  c(
    sprintf("Phase 2 gate report (fit %s on seasons %s)", params$fit_date,
            paste(params$training_seasons, collapse = ", ")),
    "",
    sprintf("  k      %6.2f  Elo points per point of margin", params$k),
    sprintf("  h      %6.2f  home field, points", params$h),
    sprintf("  sigma  %6.2f  SD of real margin around the prediction", params$sigma),
    "",
    "Leave-one-season-out folds", show(params$folds),
    "",
    "Out-of-fold accuracy (both rows on the same games)", show(params$metrics),
    "",
    "Calibration (favorite win probability, out of fold)", show(params$calibration),
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
