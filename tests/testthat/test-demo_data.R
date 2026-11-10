demo <- demo_app_data()

test_that("demo data has every element and column in the data dictionary", {
  expect_named(demo, c("meta", "teams", "params", "slate", "coverage"))
  expect_named(demo$meta, c("season", "week", "ratings_date", "built_at", "is_demo"))
  expect_true(demo$meta$is_demo)

  team_columns <- c("team_id", "school", "mascot", "abbreviation", "conference", "color",
                    "alt_color", "logo", "tier", "talent_z", "returning_z", names(MODEL_LABELS),
                    paste0(names(MODEL_LABELS), "_rank"))
  expect_true(all(team_columns %in% names(demo$teams)))
  expect_false(anyDuplicated(demo$teams$team_id) > 0)

  expect_named(demo$slate, c("game_id", "start_date", "home_id", "away_id",
                             "neutral_site", "market_spread_home"))
  expect_named(demo$coverage, c("source", "season", "week", "n_teams", "pulled_at"))
})

test_that("demo params have every field in the data dictionary", {
  p <- demo$params
  expect_true(all(c("fit_date", "fit_seasons", "holdout_season", "k", "elo_tier",
                    "power_scale", "h", "h_elo", "h_power", "talent_points", "returning_points",
                    "sigma", "power", "weights",
                    "weights_method", "weights_note", "metrics", "holdout", "calibration",
                    "folds", "leaked_diagnostic") %in% names(p)))
  expect_equal(sum(unlist(p$weights)), 1)
  expect_named(p$weights, BLEND_SYSTEMS)
  for (table in names(PARAM_TABLES)) {
    expect_named(p[[table]], names(PARAM_TABLES[[table]]))
  }
})

test_that("every demo slate game predicts without error", {
  for (i in seq_len(nrow(demo$slate))) {
    game <- demo$slate[i, ]
    site <- if (game$neutral_site) "neutral" else "a_home"
    pred <- predict_matchup(game$home_id, game$away_id, site, demo$teams, demo$params)
    expect_true(is.finite(pred$spread))
    expect_true(pred$win_prob_a > 0 && pred$win_prob_a < 1)
  }
})
