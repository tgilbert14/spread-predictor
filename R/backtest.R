# Helpers for scripts/backtest.R, which re-tests the house models, the
# factors now in them, and the candidate factors that were tried and
# rejected. Nothing here is used by the app or by scripts/fit.R.
#
# Every number is out of sample: leave-one-season-out over FIT_SEASONS for
# the cross-validated (CV) numbers, and a fit on FIT_SEASONS scored on
# HOLDOUT_SEASON for the holdout numbers.
#
# The final house models are ELO_TERMS and POWER_TERMS in R/fit.R.

# Days between games that count as a bye (two weeks) or short rest.
BYE_REST_DAYS <- 13
SHORT_REST_DAYS <- 5

# Regular-season weeks treated as early season by the sigma candidate.
EARLY_WEEKS <- 1:4

# Bootstrap draws and seed for the paired intervals. Fixed so the results
# file only changes when the data or the code does.
BOOTSTRAP_DRAWS <- 2000
BOOTSTRAP_SEED <- 2026

# Factors to judge. A candidate adds terms to the final Elo and Power
# models, except the sigma candidate, which changes only the win
# probabilities and is judged on log loss instead of MAE. A factor already
# in the model is judged by taking it out (see house_terms_without()).
CANDIDATES <- list(
  success_rate = list(label = "Success rate in the Power target", in_model = TRUE),
  preseason = list(label = "Preseason talent and returning production", in_model = TRUE),
  rest = list(label = "Bye week or short rest",
              elo = c("bye_diff", "short_diff"), power = c("bye_diff", "short_diff")),
  curvature = list(label = "Blowout curvature",
                   elo = "I(elo_gap^3)", power = "I(power_gap^3)"),
  postseason = list(label = "Postseason shift",
                    elo = "elo_gap:postseason", power = "power_gap:postseason"),
  home_trend = list(label = "Home field trend by season",
                    elo = "home_trend", power = "home_trend"),
  conference_home = list(label = "Home field in conference games",
                         elo = "conference_home", power = "conference_home"),
  early_sigma = list(label = "Separate early-season sigma", sigma = TRUE)
)

# ---- Data -------------------------------------------------------------------

#' Games for the backtest: completed FBS games with every model input, the
#' closing line and the candidate factors, in the fit and holdout seasons.
#'
#' Besides the final Power rating gap, each game gets power_gap_points, the
#' gap from a Power rating learned from scores alone (success_share 0).
#'
#' Only games with a closing line are kept, so every row in every table is
#' scored on the same games.
backtest_games <- function(con) {
  all_games <- query_sql_file(con, "rating_games.sql", list(BURN_IN_SEASON))
  conferences <- query_sql_file(con, "team_conferences.sql")
  power <- power_ratings(all_games, conferences)
  points_only <- power_ratings(all_games, conferences,
                               utils::modifyList(POWER_RATING, list(success_share = 0)))$pregame

  games <- add_model_inputs(load_completed_games(con), power$pregame, load_preseason(con))
  at <- match(games$game_id, points_only$game_id)
  games$power_gap_points <- points_only$home_power[at] - points_only$away_power[at]
  games <- house_set(games, c(FIT_SEASONS, HOLDOUT_SEASON))

  lines <- median_spread(query_sql_file(con, "lines.sql"))
  games$line <- -lines$spread[match(games$game_id, lines$game_id)]
  games <- games[!is.na(games$line), , drop = FALSE]
  add_candidate_factors(games, rest_days(all_games))
}

#' Days since each team's previous game, for every game and both teams.
#'
#' Every game counts as a previous game, FCS opponents included. A team's
#' first game of the season has no previous game, so its rest is NA.
#'
#' @param games Rows of game_id, season, start_date, home_id, away_id.
#' @return game_id, home_rest, away_rest.
rest_days <- function(games) {
  sides <- rbind(
    data.frame(game_id = games$game_id, season = games$season, team_id = games$home_id,
               side = "home", start_date = games$start_date),
    data.frame(game_id = games$game_id, season = games$season, team_id = games$away_id,
               side = "away", start_date = games$start_date)
  )
  sides$date <- as.Date(substr(sides$start_date, 1, 10))
  sides <- sides[order(sides$season, sides$team_id, sides$date, sides$game_id), ]
  same_team <- c(FALSE, utils::head(sides$season, -1) == sides$season[-1] &
                   utils::head(sides$team_id, -1) == sides$team_id[-1])
  previous <- c(NA, utils::head(as.numeric(sides$date), -1))
  sides$rest <- ifelse(same_team, as.numeric(sides$date) - previous, NA_real_)

  home <- sides[sides$side == "home", ]
  away <- sides[sides$side == "away", ]
  data.frame(game_id = games$game_id,
             home_rest = home$rest[match(games$game_id, home$game_id)],
             away_rest = away$rest[match(games$game_id, away$game_id)])
}

#' Add the columns the candidate factors use.
add_candidate_factors <- function(games, rest) {
  at <- match(games$game_id, rest$game_id)
  is_bye <- function(days) as.integer(!is.na(days) & days >= BYE_REST_DAYS)
  is_short <- function(days) as.integer(!is.na(days) & days <= SHORT_REST_DAYS)
  games$bye_diff <- is_bye(rest$home_rest[at]) - is_bye(rest$away_rest[at])
  games$short_diff <- is_short(rest$home_rest[at]) - is_short(rest$away_rest[at])

  games$postseason <- as.integer(games$season_type == "postseason")
  games$home_trend <- games$home * (games$season - mean(FIT_SEASONS))
  same_conference <- !is.na(games$home_conference) &
    games$home_conference == games$away_conference &
    games$home_conference != "FBS Independents"
  games$conference_home <- games$home * as.integer(same_conference)
  games$early <- games$season_type == "regular" & games$week %in% EARLY_WEEKS
  games
}

# ---- Out-of-sample predictions ----------------------------------------------

#' Fit on `train` and predict `test`.
fit_predict <- function(train, test, terms) {
  unname(stats::predict(stats::lm(margin_formula(terms), data = train), newdata = test))
}

#' Leave-one-season-out predictions over the fit seasons, plus holdout
#' predictions from a fit on all of them.
#'
#' @return cv and holdout: predicted home margins, one per game in each set.
out_of_sample <- function(games, terms) {
  cv_games <- games[games$season %in% FIT_SEASONS, , drop = FALSE]
  cv <- rep(NA_real_, nrow(cv_games))
  for (season in FIT_SEASONS) {
    held_out <- cv_games$season == season
    cv[held_out] <- fit_predict(cv_games[!held_out, ], cv_games[held_out, ], terms)
  }
  list(cv = cv, holdout = fit_predict(cv_games, games[games$season == HOLDOUT_SEASON, ], terms))
}

#' Out-of-sample house blend: the average of an Elo model and a Power
#' model. The defaults are the final house models.
house_out_of_sample <- function(games, elo_terms = ELO_TERMS, power_terms = POWER_TERMS) {
  elo <- out_of_sample(games, elo_terms)
  power <- out_of_sample(games, power_terms)
  list(cv = (elo$cv + power$cv) / 2, holdout = (elo$holdout + power$holdout) / 2)
}

#' The final house models' terms with one of their factors taken out.
#'
#' @param factor "success_rate" (Power learns from scores alone) or
#'   "preseason" (no talent or returning production terms).
#' @return A list of elo and power terms.
house_terms_without <- function(factor) {
  switch(factor,
    success_rate = list(elo = ELO_TERMS,
                        power = sub("^power_gap$", "power_gap_points", POWER_TERMS)),
    preseason = list(elo = setdiff(ELO_TERMS, PRESEASON_TERMS),
                     power = setdiff(POWER_TERMS, PRESEASON_TERMS)),
    stop("Unknown factor '", factor, "'.", call. = FALSE)
  )
}

#' The model comparison: CV MAE and holdout MAE, all on the same games.
#'
#' The rows build up to the final house blend one step at a time, then show
#' the closing line as the benchmark.
compare_models <- function(games) {
  no_preseason <- house_terms_without("preseason")
  forecasts <- list(
    "Elo" = out_of_sample(games, c("elo_gap", "home")),
    "Elo with tier correction" = out_of_sample(games, no_preseason$elo),
    "Power on points only" = out_of_sample(games, c("power_gap_points", "home")),
    "Power with success rate" = out_of_sample(games, no_preseason$power),
    "House blend without preseason terms" =
      house_out_of_sample(games, no_preseason$elo, no_preseason$power),
    "House blend, final" = house_out_of_sample(games),
    "Closing line" = list(cv = games$line[games$season %in% FIT_SEASONS],
                          holdout = games$line[games$season == HOLDOUT_SEASON])
  )
  actual <- split_seasons(games)
  data.frame(
    model = names(forecasts),
    cv_mae = vapply(forecasts, function(f) mean(abs(actual$cv - f$cv)), numeric(1)),
    holdout_mae = vapply(forecasts, function(f) mean(abs(actual$holdout - f$holdout)), numeric(1)),
    row.names = NULL
  )
}

#' Real home margins in the same two sets as out_of_sample().
split_seasons <- function(games) {
  list(cv = games$home_margin[games$season %in% FIT_SEASONS],
       holdout = games$home_margin[games$season == HOLDOUT_SEASON])
}

# ---- Win probabilities (for the sigma candidate) ----------------------------

#' Log loss of each decided game's win probability. Ties score NA.
log_loss <- function(predicted, actual, sigma) {
  p_home <- stats::pnorm(predicted / sigma)
  p_home <- pmin(pmax(p_home, 1e-6), 1 - 1e-6)
  ifelse(actual == 0, NA_real_, -log(ifelse(actual > 0, p_home, 1 - p_home)))
}

#' Per-game sigma from the training games: one value, or one for early weeks
#' and one for the rest.
fitted_sigma <- function(train, predicted_train, test, split_early) {
  miss <- train$home_margin - predicted_train
  if (!split_early) return(rep(stats::sd(miss), nrow(test)))
  ifelse(test$early, stats::sd(miss[train$early]), stats::sd(miss[!train$early]))
}

#' Out-of-sample log loss per game for the house blend, with one sigma or
#' with a separate early-season sigma. Sigma comes from each fit's own
#' training games (in-sample house blend residuals).
house_log_loss <- function(games, split_early) {
  cv_games <- games[games$season %in% FIT_SEASONS, , drop = FALSE]
  score <- function(train, test) {
    predict_both <- function(new) {
      (fit_predict(train, new, ELO_TERMS) + fit_predict(train, new, POWER_TERMS)) / 2
    }
    sigma <- fitted_sigma(train, predict_both(train), test, split_early)
    log_loss(predict_both(test), test$home_margin, sigma)
  }
  cv <- rep(NA_real_, nrow(cv_games))
  for (season in FIT_SEASONS) {
    held_out <- cv_games$season == season
    cv[held_out] <- score(cv_games[!held_out, ], cv_games[held_out, ])
  }
  list(cv = cv, holdout = score(cv_games, games[games$season == HOLDOUT_SEASON, ]))
}

# ---- Judging a candidate ----------------------------------------------------

#' Mean of paired per-game differences, with a bootstrap 95% interval.
#'
#' @param diff Candidate loss minus base loss, one per game. NA is dropped.
#' @return change, low, high.
paired_bootstrap <- function(diff, draws = BOOTSTRAP_DRAWS, seed = BOOTSTRAP_SEED) {
  diff <- diff[!is.na(diff)]
  set.seed(seed)
  means <- replicate(draws, mean(sample(diff, replace = TRUE)))
  interval <- stats::quantile(means, c(0.025, 0.975), names = FALSE)
  c(change = mean(diff), low = interval[1], high = interval[2])
}

#' "kept" or "rejected".
#'
#' A candidate is kept only if it helps: the 95% interval on its CV change
#' lies wholly below zero (lower loss), and the holdout change points the
#' same way. A factor that reliably makes things worse is rejected too.
verdict <- function(low, high, holdout_change) {
  ifelse(high < 0 & holdout_change < 0, "kept", "rejected")
}

#' Judge one factor against the final house blend.
#'
#' A candidate is added to the final models. A factor already in them is
#' taken out instead, and the change is still "with it" minus "without it",
#' so negative always means the factor helps.
#'
#' @param name The factor's name in CANDIDATES.
#' @return One row: factor, metric, cv_change, cv_low, cv_high,
#'   holdout_change, verdict.
judge_candidate <- function(games, candidate, name) {
  actual <- split_seasons(games)
  if (isTRUE(candidate$sigma)) {
    base <- house_log_loss(games, split_early = FALSE)
    new <- house_log_loss(games, split_early = TRUE)
    metric <- "log loss"
    cv_diff <- new$cv - base$cv
    holdout_diff <- new$holdout - base$holdout
  } else {
    final <- house_out_of_sample(games)
    if (isTRUE(candidate$in_model)) {
      without <- house_terms_without(name)
      new <- final
      base <- house_out_of_sample(games, without$elo, without$power)
    } else {
      base <- final
      new <- house_out_of_sample(games, c(ELO_TERMS, candidate$elo), c(POWER_TERMS, candidate$power))
    }
    metric <- "MAE"
    cv_diff <- abs(actual$cv - new$cv) - abs(actual$cv - base$cv)
    holdout_diff <- abs(actual$holdout - new$holdout) - abs(actual$holdout - base$holdout)
  }
  cv <- paired_bootstrap(cv_diff)
  holdout_change <- mean(holdout_diff, na.rm = TRUE)
  data.frame(factor = candidate$label, metric = metric,
             cv_change = cv[["change"]], cv_low = cv[["low"]], cv_high = cv[["high"]],
             holdout_change = holdout_change,
             verdict = verdict(cv[["low"]], cv[["high"]], holdout_change))
}

# ---- Report -----------------------------------------------------------------

#' A data frame as a Markdown table. Numbers are formatted by the caller.
markdown_table <- function(df, headers = names(df)) {
  row_text <- function(values) paste0("| ", paste(values, collapse = " | "), " |")
  c(row_text(headers),
    row_text(rep("---", length(headers))),
    vapply(seq_len(nrow(df)), function(i) row_text(unlist(df[i, ])), character(1)))
}

#' The backtest results as Markdown lines.
backtest_markdown <- function(models, factors, n_cv, n_holdout) {
  # Log loss changes are much smaller than MAE changes, so they get a digit more.
  digits <- ifelse(factors$metric == "MAE", 3, 4)
  signed <- function(x) sprintf("%+.*f", digits, x)
  model_rows <- data.frame(model = models$model, cv = sprintf("%.3f", models$cv_mae),
                           holdout = sprintf("%.3f", models$holdout_mae))
  factor_rows <- data.frame(
    factor = factors$factor, metric = factors$metric,
    cv = signed(factors$cv_change),
    interval = sprintf("[%s, %s]", signed(factors$cv_low), signed(factors$cv_high)),
    holdout = signed(factors$holdout_change),
    verdict = factors$verdict
  )
  c(
    "# Backtest results",
    "",
    "Generated by `scripts/backtest.R`. Do not edit by hand; rerun the script instead.",
    "",
    sprintf("Completed FBS games with a closing line. Cross-validated (CV) numbers are leave-one-season-out over %s (%s games). Holdout numbers are %s games so far (%s games), predicted from a fit on those seasons only. %s is burn-in for the Power rating and is not scored. 2020 (the COVID season) stays in the Power rating's history but is never fit or scored.",
            format_seasons(FIT_SEASONS), format(n_cv, big.mark = ","), HOLDOUT_SEASON,
            format(n_holdout, big.mark = ","), BURN_IN_SEASON),
    "",
    "## Model comparison",
    "",
    "Mean absolute error of the predicted home margin, in points. Lower is better. The rows build up to the final house blend one step at a time: Elo alone, Elo with the power-conference correction, our Power rating learned from scores only and then also from success rate, the average of the two models, and finally that average with the early-season talent and returning production terms.",
    "",
    markdown_table(model_rows, c("Model", "CV MAE", "Holdout MAE")),
    "",
    "## Candidate factors",
    "",
    "Each candidate is added to both final house models (Elo and Power, each with the preseason terms), and the house blend is compared with and without it. The first two rows are factors already in the model; each is measured by taking it out of the final model, so the row shows what the model would lose without it. Either way, a change is the loss with the factor minus the loss without it, per game, so negative means the factor helps. The interval is a paired bootstrap 95% interval over games.",
    "",
    "A factor is kept only if the CV interval lies wholly below zero and the holdout change is also negative. The early-season sigma changes only win probabilities, so it is judged on log loss instead of MAE.",
    "",
    markdown_table(factor_rows, c("Factor", "Metric", "CV change", "95% interval", "Holdout change", "Verdict"))
  )
}
