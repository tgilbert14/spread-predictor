fixture_db <- make_fixture_db()

#' Fit params on a fixture database.
fit_fixture <- function(db_path) {
  con <- connect_readonly(db_path)
  on.exit(DBI::dbDisconnect(con))
  with_project_root(fit_params(con))
}

params <- fit_fixture(fixture_db)

test_that("the fit recovers the true k, tier edge, home field and sigma", {
  expect_equal(params$k, FIXTURE_TRUTH$k, tolerance = 0.08)
  expect_lt(abs(params$elo_tier - FIXTURE_TRUTH$elo_tier), 1.5)
  expect_lt(abs(params$h_elo - FIXTURE_TRUTH$h), 1)
  expect_lt(abs(params$h - FIXTURE_TRUTH$h), 1.5)
  expect_equal(params$h, mean(c(params$h_elo, params$h_power)))
  # The fixture's Elo is close to the truth, and Power is noisier because
  # every fixture season redraws team strengths. So the house blend misses
  # by somewhat more than the true model's sigma.
  expect_gt(params$sigma, FIXTURE_TRUTH$sigma - 0.75)
  expect_lt(params$sigma, FIXTURE_TRUTH$sigma + 3)
  expect_lt(abs(params$sigma - mean(params$folds$sigma)), 0.5)
  expect_gt(params$power_scale, 0)
})

test_that("FCS games and games without pregame Elo are left out of the fit", {
  con <- connect_readonly(fixture_db)
  on.exit(DBI::dbDisconnect(con))
  games <- with_project_root(add_model_inputs(load_completed_games(con),
                                              load_power_ratings(con)$pregame,
                                              load_preseason(con)))
  fit_set <- house_set(games, FIT_SEASONS)
  expect_false(any(fit_set$game_id %% 10000 > 5000))
  expect_equal(nrow(fit_set), length(FIT_SEASONS) * 400)
  expect_false(anyNA(fit_set$power_gap))
})

test_that("the burn-in season is not fit on and the holdout is scored separately", {
  expect_identical(params$fit_seasons, FIT_SEASONS)
  expect_false(BURN_IN_SEASON %in% params$fit_seasons)
  expect_identical(params$holdout_season, HOLDOUT_SEASON)
  expect_identical(params$holdout$model, c("elo", "power", "house", "line"))
  expect_true(all(params$holdout$n > 0))
})

test_that("there is one fold per fit season", {
  expect_identical(params$folds$season, FIT_SEASONS)
  expect_named(params$folds, names(PARAM_TABLES$folds))
  expect_true(all(abs(params$folds$k / FIXTURE_TRUTH$k - 1) < 0.1))
})

test_that("every forecast is scored on the same games and the line is sharpest", {
  metrics <- params$metrics
  expect_identical(metrics$model, c("elo", "power", "house", "line"))
  expect_length(unique(metrics$n), 1)
  line <- metrics[metrics$model == "line", ]
  expect_true(all(line$mae < metrics$mae[metrics$model != "line"]))
  expect_true(all(line$brier < metrics$brier[metrics$model != "line"]))
})

test_that("the fit recovers the true preseason points and the app uses their mean", {
  # Only weeks 1 to 6 carry these terms, so they are noisier than k or h.
  expect_lt(abs(params$talent_points_elo - FIXTURE_TRUTH$talent), 1.5)
  expect_lt(abs(params$returning_points_elo - FIXTURE_TRUTH$returning), 1.5)
  expect_equal(params$talent_points, mean(c(params$talent_points_elo, params$talent_points_power)))
  expect_equal(params$returning_points,
               mean(c(params$returning_points_elo, params$returning_points_power)))
})

test_that("the house blend is the average of the Elo and Power models", {
  games <- data.frame(elo_gap = c(100, -50), tier_diff = c(1L, 0L), power_gap = c(4, -2),
                      home = c(1L, 0L), talent_early = c(1, 0), returning_early = c(-0.5, 0))
  fit <- list(k = 25, elo_tier = 10, h_elo = 3, talent_points_elo = 2, returning_points_elo = 1,
              power_scale = 0.9, h_power = 2, talent_points_power = 4, returning_points_power = 3)
  pred <- predict_house(games, fit)
  expect_equal(pred$elo, c(100 / 25 + 10 + 3 + 2 - 0.5, -2))
  expect_equal(pred$power, c(0.9 * 4 + 2 + 4 - 1.5, -1.8))
  expect_equal(pred$house, (pred$elo + pred$power) / 2)

  # The average equals using the mean preseason points in both models,
  # which is what the app does.
  shared <- modifyList(fit, list(talent_points_elo = 3, talent_points_power = 3,
                                 returning_points_elo = 2, returning_points_power = 2))
  expect_equal(predict_house(games, shared)$house, pred$house)
})

test_that("preseason z-scores are by season among FBS teams, with 0 for a missing value", {
  preseason <- data.frame(season = c(2025L, 2025L, 2025L, 2026L, 2026L),
                          team_id = c(1L, 2L, 3L, 1L, 2L),
                          talent = c(500, 700, NA, 10, 20),
                          percent_ppa = c(0.2, 0.4, 0.6, NA, NA))
  z <- preseason_z(preseason)
  expect_equal(z$talent_z, c(-sqrt(0.5), sqrt(0.5), 0, -sqrt(0.5), sqrt(0.5)))
  expect_equal(z$returning_z, c(-1, 0, 1, 0, 0))
})

test_that("model inputs carry faded preseason gaps", {
  games <- data.frame(game_id = 1:3, season = 2026L, week = c(1L, 4L, 1L),
                      season_type = c("regular", "regular", "postseason"), neutral_site = 0L,
                      home_id = 1L, away_id = 2L, home_conference = "SEC", away_conference = "SEC",
                      home_pregame_elo = 1600, away_pregame_elo = 1500)
  pregame <- data.frame(game_id = 1:3, home_power = 5, away_power = 0)
  preseason <- data.frame(season = 2026L, team_id = 1L, talent_z = 1.5, returning_z = -1)
  out <- add_model_inputs(games, pregame, preseason)
  # Team 2 has no preseason values, so it counts as average.
  expect_equal(out$talent_gap, rep(1.5, 3))
  expect_equal(out$fade, c(1, 0.5, 0))
  expect_equal(out$talent_early, c(1.5, 0.75, 0))
  expect_equal(out$returning_early, c(-1, -0.5, 0))
})

test_that("calibration has five bins covering 0.5 to 1", {
  cal <- params$calibration
  expect_equal(cal$bin_low, seq(0.5, 0.9, by = 0.1))
  expect_equal(cal$bin_high, seq(0.6, 1.0, by = 0.1))
  expect_true(all(cal$predicted >= cal$bin_low & cal$predicted <= cal$bin_high))
})

test_that("the leaked diagnostic covers sp, fpi and srs, or is empty without finals", {
  expect_identical(params$leaked_diagnostic$model, c("sp", "fpi", "srs"))
  empty <- leaked_diagnostic(data.frame(source = character(), season = integer(),
                                        team_id = integer(), rating = numeric()),
                             data.frame(season = 2021L, home_id = 1L, away_id = 2L,
                                        neutral_site = 0L, home_margin = 3),
                             h = 2.5)
  expect_identical(nrow(empty), 0L)
  expect_named(empty, c("model", "n", "mae"))
})

test_that("flipped line signs stop the fit with a clear message", {
  flipped <- make_fixture_db(flip_lines = TRUE)
  expect_error(fit_fixture(flipped), "Closing lines point the wrong way")
})

test_that("ties do not crash the scoring", {
  scored <- score_margins(predicted = c(3, -2, 0, 5), actual = c(7, 0, 4, -1), sigma = 16)
  expect_identical(scored$n, 4L)
  expect_equal(scored$win_rate, (1 + 0.5 + 0) / 3)
  all_ties <- score_margins(c(1, 2), c(0, 0), 16)
  expect_true(is.na(all_ties$win_rate) && is.na(all_ties$brier))
})

test_that("params round-trip through JSON into the demo shape", {
  path <- tempfile(fileext = ".json")
  write_params(params, path)
  back <- read_params(path)
  demo <- demo_app_data()$params

  expect_identical(names(back), names(demo))
  for (field in names(demo)) {
    expect_identical(class(back[[field]]), class(demo[[field]]), label = field)
    if (is.data.frame(demo[[field]])) {
      expect_identical(vapply(back[[field]], class, character(1)),
                       vapply(demo[[field]], class, character(1)), label = field)
    }
  }
  expect_named(back$weights, names(demo$weights))
  expect_named(back$power, names(POWER_RATING))
  for (field in PARAM_NUMBERS) expect_equal(back[[field]], params[[field]], tolerance = 1e-4, label = field)
  expect_equal(back$metrics$mae, params$metrics$mae, tolerance = 1e-4)
  expect_equal(back$holdout$mae, params$holdout$mae, tolerance = 1e-4)
  expect_equal(back$folds$elo_tier, params$folds$elo_tier, tolerance = 1e-4)
})

test_that("an empty leaked diagnostic survives the round trip with its columns", {
  path <- tempfile(fileext = ".json")
  p <- params
  p$leaked_diagnostic <- p$leaked_diagnostic[0, ]
  write_params(p, path)
  back <- read_params(path)$leaked_diagnostic
  expect_identical(nrow(back), 0L)
  expect_named(back, c("model", "n", "mae"))
})

test_that("read_params says what to do when the file is missing", {
  expect_error(read_params(tempfile()), "scripts/fit.R")
})

test_that("weights cover all five systems and always sum to 1", {
  expect_equal(sum(unlist(params$weights)), 1)
  expect_named(params$weights, BLEND_SYSTEMS)
  expect_equal(unname(unlist(equal_weights())), rep(0.2, 5))

  set.seed(7)
  X <- matrix(stats::rnorm(400 * 5, 0, 15), ncol = 5, dimnames = list(NULL, BLEND_SYSTEMS))
  w <- fit_blend_weights(X, stats::rnorm(400, 0, 10))
  expect_equal(sum(w), 1)
  expect_true(all(w >= 0))
})

test_that("blend weights favor the system that is actually right", {
  set.seed(11)
  truth <- stats::rnorm(1000, 0, 15)
  X <- cbind(sp = truth, fpi = truth + stats::rnorm(1000, 0, 12),
             srs = truth + stats::rnorm(1000, 0, 12), elo = truth + stats::rnorm(1000, 0, 12),
             power = truth + stats::rnorm(1000, 0, 12))
  y <- truth + stats::rnorm(1000, 0, 5)
  w <- fit_blend_weights(X, y)
  expect_identical(names(which.max(w)), "sp")
  # Shrinkage keeps the weaker systems in the blend.
  expect_true(all(w > 0))

  design <- list(X = X, y = y, week = rep(paste(2025, 1:10), each = 100))
  chosen <- choose_weights(design)
  expect_identical(chosen$method, "fitted")
  expect_equal(sum(unlist(chosen$weights)), 1)
})

test_that("choose_weights stays equal with too few snapshot games", {
  expect_identical(params$weights_method, "equal")
  expect_match(params$weights_note, "at least 300")
  expect_equal(unlist(params$weights), unlist(equal_weights()))

  small <- list(X = matrix(1, 50, 5, dimnames = list(NULL, BLEND_SYSTEMS)),
                y = rep(1, 50), week = rep(c("2026 1", "2026 2"), 25))
  expect_identical(choose_weights(small)$method, "equal")
})

test_that("blend_design matches snapshot week W to week W games and skips postseason", {
  games <- data.frame(season = 2026L, week = c(5L, 5L, 6L), season_type = c("regular", "postseason", "regular"),
                      home_id = 1L, away_id = 2L, neutral_site = 0L, home_margin = 10,
                      tier_diff = 1L, power_gap = 5, talent_early = 1 / 3, returning_early = 0)
  weekly <- do.call(rbind, lapply(RATING_SOURCES, function(source) {
    data.frame(source = source, season = 2026L, week = 5L, team_id = 1:2,
               rating = if (source == "elo") c(1600, 1500) else c(6, 0))
  }))
  fit <- list(k = 25, elo_tier = 10, power_scale = 0.8, h = 2, talent_points = 3, returning_points = 1)
  design <- blend_design(games, weekly, fit)
  expect_identical(nrow(design$X), 1L)
  expect_identical(colnames(design$X), BLEND_SYSTEMS)
  # Elo gets the tier edge; Power comes from the game itself, not a snapshot.
  # Both get the preseason point (3 * 1/3), as in the app.
  expect_equal(unname(design$X[1, ]), c(6, 6, 6, 4 + 10 + 1, 0.8 * 5 + 1))
  expect_equal(design$y, 8)
})

test_that("the gate report runs and every check gives a clear pass or look", {
  report <- gate_report(params)
  expect_true(any(grepl("Holdout season", report)))
  expect_match(report[length(report)], "^Gate: ")
  checks <- gate_checks(params)
  expect_type(checks$pass, "logical")
  expect_false(anyNA(checks$pass))
})

test_that("a sportsbook with home and away swapped is outvoted, not averaged in", {
  # Three books say home by 12; one has the same number for the other team.
  expect_equal(is_flipped_line(c(-12, -12.5, -12, 12)), c(FALSE, FALSE, FALSE, TRUE))
  lines <- data.frame(game_id = 1L, spread = c(-12, -12.5, 12))
  expect_equal(median_spread(lines)$spread, -12.25)

  # Two books: no way to tell who is right, so both stay.
  expect_equal(is_flipped_line(c(-12, 12)), c(FALSE, FALSE))
  # Near pick'em, books really do disagree on the favorite.
  expect_equal(is_flipped_line(c(-1, 1, -1.5)), c(FALSE, FALSE, FALSE))
})

test_that("preseason_z pulls impossible returning-production shares back into range", {
  preseason <- data.frame(season = 2021L, team_id = 1:4, talent = c(600, 700, 800, 900),
                          percent_ppa = c(-3.1, 0.4, 0.6, 1.7))
  z <- preseason_z(preseason)
  # Treated as shares of 0, 0.4, 0.6 and 1, so no team sits absurdly far out.
  expect_equal(z$returning_z, as.numeric(scale(c(0, 0.4, 0.6, 1))))
  expect_lt(max(abs(z$returning_z)), 2)
})
