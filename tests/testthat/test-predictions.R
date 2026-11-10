# Saving predictions, line movement and grading.

demo <- demo_app_data()
real_like <- demo
real_like$meta$is_demo <- FALSE

#' A database holding only this week's games, with chosen kickoff times.
week_db <- function(slate, completed = 0L) {
  path <- tempfile(fileext = ".sqlite")
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  on.exit(DBI::dbDisconnect(con))
  create_schema(con)
  DBI::dbAppendTable(con, "games", data.frame(
    game_id = slate$game_id, season = 2026L, week = 11L, season_type = "regular",
    start_date = slate$start_date, completed = completed, neutral_site = as.integer(slate$neutral_site),
    home_id = slate$home_id, home_team = "Home", home_class = "fbs",
    away_id = slate$away_id, away_team = "Away", away_class = "fbs"
  ))
  path
}

before_kickoff <- as.POSIXct("2026-11-10 13:00:00", tz = "UTC")
after_kickoff <- as.POSIXct("2026-11-14 21:00:00", tz = "UTC")

test_that("freeze writes the documented columns in order, matching the reference file", {
  root <- tempfile()
  db <- week_db(real_like$slate)
  expect_true(suppressMessages(with_project_root(freeze_predictions(real_like, db, root, now = before_kickoff))))

  path <- prediction_path(2026, 11, root)
  expect_identical(basename(path), "2026_wk11.csv")
  saved <- read_snapshot(path)
  expect_identical(names(saved), PREDICTION_COLUMNS)
  reference <- file.path(project_root, "data", "snapshots", "predictions", "2026_wk11.csv")
  expect_identical(readLines(path, n = 1), readLines(reference, n = 1))

  expect_identical(nrow(saved), nrow(real_like$slate))
  expect_identical(saved$frozen_at[1], "2026-11-10T13:00:00Z")
  expect_true(all(saved$neutral_site %in% c(0, 1)))
  expect_true(all(is.na(saved$market_spread_home) == is.na(real_like$slate$market_spread_home)))
})

test_that("saved margins are home-relative and match predict_matchup", {
  rows <- prediction_rows(real_like$slate, demo$teams, demo$params, 2026L, 11L)
  game <- real_like$slate[2, ]
  pred <- predict_matchup(game$home_id, game$away_id, "a_home", demo$teams, demo$params, week = 11L)
  expect_equal(rows$blend[2], round(pred$spread, 2))
  expect_equal(rows$win_prob_home[2], round(pred$win_prob_a, 4))
  expect_equal(rows$elo[2], round(pred$models$margin[pred$models$model == "elo"], 2))
  expect_identical(rows$home_id[2], game$home_id)
})

test_that("freeze never rewrites a saved file", {
  root <- tempfile()
  db <- week_db(real_like$slate)
  suppressMessages(with_project_root(freeze_predictions(real_like, db, root, now = before_kickoff)))
  path <- prediction_path(2026, 11, root)
  first <- unname(tools::md5sum(path))

  changed <- real_like
  changed$slate$market_spread_home <- changed$slate$market_spread_home + 3
  expect_message(written <- with_project_root(freeze_predictions(changed, db, root, now = before_kickoff)), "never rewritten")
  expect_false(written)
  expect_identical(unname(tools::md5sum(path)), first)
})

test_that("freeze refuses once any game of the week has kicked off", {
  root <- tempfile()
  expect_message(written <- with_project_root(freeze_predictions(real_like, week_db(real_like$slate), root, now = after_kickoff)),
                 "already kicked off")
  expect_false(written)
  expect_false(file.exists(prediction_path(2026, 11, root)))

  # A game already final counts too, even if its kickoff time is missing.
  played <- real_like$slate
  played$start_date[1] <- NA
  db <- week_db(played, completed = c(1L, rep(0L, nrow(played) - 1)))
  expect_message(written <- with_project_root(freeze_predictions(real_like, db, root, now = before_kickoff)),
                 "already kicked off")
  expect_false(written)
})

test_that("freeze never saves demo data", {
  root <- tempfile()
  expect_message(written <- freeze_predictions(demo, week_db(demo$slate), root, now = before_kickoff), "demo")
  expect_false(written)
})

test_that("line movement is positive toward the home team", {
  slate <- data.frame(game_id = 1:4, market_spread_home = c(-7, -3, 2, NA))
  saved <- data.frame(season = 2026L, week = 11L, game_id = c(1L, 2L, 3L, 4L),
                      market_spread_home = c(-4, -6, 2, -1))
  moved <- add_line_movement(slate, saved, 2026L, 11L)
  expect_equal(moved$market_at_freeze, c(-4, -6, 2, -1))
  # Home went from a 4-point to a 7-point favorite: 3 points toward home.
  expect_equal(moved$market_move[1], 3)
  # Home went from a 6-point to a 3-point favorite: 3 points toward the away team.
  expect_equal(moved$market_move[2], -3)
  expect_equal(moved$market_move[3], 0)
  expect_true(is.na(moved$market_move[4]))

  # Another week's file does not count.
  other_week <- add_line_movement(slate, transform(saved, week = 10L), 2026L, 11L)
  expect_true(all(is.na(other_week$market_at_freeze)))
})

# A hand-made week. Margins are home minus away; spreads are sportsbook style.
#   1: we were closer, disagreed by 4, landed on our side.
#   2: disagreed by exactly 3, final exactly on the market line (a push).
#   3: same miss as the market (a tie), disagreed, landed on our side.
#   4: not played yet.
#   5: disagreed, landed on the market's side, wrong winner.
#   6: no market line.
hand_predictions <- function() {
  p <- as_param_table(data.frame(
    game_id = 1:6, season = 2026L, week = c(10L, 10L, 10L, 12L, 11L, 11L),
    start_date = sprintf("2026-11-%02dT19:00:00Z", 1:6),
    home_id = 1:6, home_team = paste("Home", 1:6), away_id = 11:16, away_team = paste("Away", 1:6),
    neutral_site = 0L,
    blend = c(7, 4, 3, 2, -5, 6),
    market_spread_home = c(-3, -1, -7, -2, -1, NA)
  ), PREDICTION_TYPES)
  p$sp <- p$blend + 1
  p$sp[6] <- NA
  p
}
hand_results <- data.frame(
  game_id = 1:6, completed = c(1L, 1L, 1L, 0L, 1L, 1L),
  home_points = c(10L, 21L, 26L, NA, 28L, 17L),
  away_points = c(0L, 20L, 21L, NA, 14L, 20L)
)

test_that("grading math matches a hand-made example", {
  g <- grade_predictions(hand_predictions(), hand_results)
  expect_equal(g$final_margin, c(10, 1, 5, NA, 14, -3))
  expect_equal(g$our_error, c(3, 3, 2, NA, 19, 9))
  expect_equal(g$market_error, c(7, 0, 2, NA, 13, NA))
  expect_identical(g$picked_winner, c(TRUE, TRUE, TRUE, NA, FALSE, FALSE))
  expect_identical(g$closer, c("us", "market", "tie", NA, "market", NA))
  expect_identical(g$disagreed, c(TRUE, TRUE, TRUE, FALSE, TRUE, NA))
  expect_identical(g$our_side, c(TRUE, NA, TRUE, NA, FALSE, NA))
})

test_that("an unplayed game keeps its row with empty results", {
  g <- grade_predictions(hand_predictions(), hand_results)
  unplayed <- g[g$game_id == 4, ]
  expect_identical(nrow(unplayed), 1L)
  expect_true(is.na(unplayed$home_points) && is.na(unplayed$our_error) && is.na(unplayed$closer))

  # A game with no row in the results at all is unplayed too.
  g <- grade_predictions(hand_predictions(), hand_results[hand_results$game_id != 6, ])
  expect_true(is.na(g$final_margin[g$game_id == 6]))
})

test_that("summaries count graded games only, per week and for the season", {
  card <- build_scorecard(hand_predictions(), hand_results, 2026L)
  s <- card$season
  expect_identical(s$season, 2026L)
  expect_identical(s$games, 5L)
  expect_equal(s$our_miss, 36 / 5)
  expect_identical(s$market_games, 4L)
  expect_equal(s$market_miss, 22 / 4)
  expect_identical(s$winners, 3L)
  expect_equal(s$winner_share, 3 / 5)
  expect_identical(s$closer, 1L)
  expect_identical(s$ties, 1L)
  expect_identical(s$disagree_games, 3L)
  expect_identical(s$disagree_our_side, 2L)

  expect_identical(card$weeks$week, c(10L, 11L))
  expect_identical(card$weeks$games, c(3L, 2L))
  expect_equal(card$weeks$our_miss, c(8 / 3, 14))
  expect_identical(nrow(card$games), 6L)
})

test_that("the systems table scores each system on the games it rated", {
  systems <- build_scorecard(hand_predictions(), hand_results, 2026L)$systems
  expect_identical(systems$system, c(names(MODEL_LABELS), "blend", "market"))
  expect_identical(systems$label[systems$system == "market"], "Market")
  blend <- systems[systems$system == "blend", ]
  expect_equal(blend$avg_miss, 36 / 5)
  expect_equal(systems$avg_miss[systems$system == "market"], 22 / 4)
  sp <- systems[systems$system == "sp", ]
  expect_identical(sp$games, 4L)
  expect_equal(sp$avg_miss, mean(c(2, 4, 1, 18)))
  expect_identical(systems$games[systems$system == "fpi"], 0L)
  expect_true(is.na(systems$avg_miss[systems$system == "fpi"]))
})

test_that("the scorecard keeps only the asked-for season", {
  other <- hand_predictions()
  other$season <- 2025L
  card <- build_scorecard(rbind(hand_predictions(), other), hand_results, 2026L)
  expect_identical(nrow(card$games), 6L)
})

test_that("an empty scorecard has the same shape and says nothing is graded", {
  empty <- empty_scorecard(2026L)
  full <- build_scorecard(hand_predictions(), hand_results, 2026L)
  for (part in c("games", "weeks", "season", "systems")) {
    expect_identical(names(empty[[part]]), names(full[[part]]), label = part)
  }
  expect_identical(empty$season$games, 0L)
  expect_identical(nrow(empty$games), 0L)
  expect_match(scorecard_message(empty), "no games graded")
  expect_match(scorecard_message(full), "5 games graded")
})

test_that("load_predictions stacks every file and ignores stray files", {
  root <- tempfile()
  dir.create(file.path(root, "predictions"), recursive = TRUE)
  expect_identical(nrow(load_predictions(root)), 0L)
  expect_identical(names(load_predictions(root)), PREDICTION_COLUMNS)

  p <- hand_predictions()
  suppressMessages({
    write_snapshot(p[p$week == 10, ], prediction_path(2026, 10, root))
    write_snapshot(p[p$week == 11, ], prediction_path(2026, 11, root))
  })
  writeLines("junk", file.path(root, "predictions", "notes.txt"))
  loaded <- suppressMessages(load_predictions(root))
  expect_identical(nrow(loaded), 5L)
  expect_identical(class(loaded$neutral_site), "integer")
  expect_true(all(is.na(loaded$fpi)))
})
