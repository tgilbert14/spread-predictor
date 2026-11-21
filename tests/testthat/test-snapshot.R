demo <- complete_app_data(demo_app_data())
teams <- demo$teams
id_of <- function(school) teams$team_id[teams$school == school]
this_week <- demo$meta$week

test_that("snapshot_weeks lists every week so far, oldest first", {
  expect_identical(snapshot_weeks(demo), seq_len(this_week))
  # History from a later week is ignored, and this week is always offered.
  odd <- demo
  odd$history <- demo$history[demo$history$week %in% c(3L, 5L), ]
  odd$history$week[odd$history$week == 5L] <- 99L
  expect_identical(snapshot_weeks(odd), c(3L, this_week))
})

test_that("snapshot_choices label this week and the weeks missing a system", {
  choices <- snapshot_choices(demo)
  expect_identical(unname(choices), as.character(rev(seq_len(this_week))))
  expect_identical(names(choices)[1], "Week 11 (this week)")
  expect_identical(names(choices)[choices == "9"], "Week 9")
  expect_identical(names(choices)[choices == "3"], "Week 3 (Elo and Power only)")
})

test_that("models_missing_in_week names the systems with nothing saved", {
  expect_identical(models_missing_in_week(demo$history, 9L), character())
  expect_identical(models_missing_in_week(demo$history, 3L), c("sp", "fpi", "srs"))
})

test_that("snapshot_teams swaps in that week's ratings and ranks them again", {
  expect_identical(snapshot_teams(demo, this_week), teams)
  expect_identical(snapshot_teams(demo, NULL), teams)

  then <- snapshot_teams(demo, 9L)
  rows <- demo$history[demo$history$week == 9L, ]
  rows <- rows[match(then$team_id, rows$team_id), ]
  for (model in names(MODEL_LABELS)) {
    expect_equal(then[[model]], rows[[model]])
    expect_identical(then[[paste0(model, "_rank")]],
                     as.integer(rank(-rows[[model]], ties.method = "min")))
  }
  # Everything that is not a rating stays as it is today.
  same <- setdiff(names(teams), c(names(MODEL_LABELS), paste0(names(MODEL_LABELS), "_rank")))
  expect_identical(then[same], teams[same])

  early <- snapshot_teams(demo, 3L)
  expect_true(all(is.na(early$sp)))
  expect_true(all(is.na(early$sp_rank)))
  expect_false(anyNA(early$power_rank))
})

test_that("week_from_query reads a week we hold and ignores anything else", {
  expect_identical(week_from_query("?a=Kofa&b=Rincon&week=9", demo), 9L)
  expect_identical(week_from_query("week=3", demo), 3L)
  expect_identical(week_from_query("?week=40", demo), this_week)
  expect_identical(week_from_query("?week=soon", demo), this_week)
  expect_identical(week_from_query("?a=Kofa", demo), this_week)
  expect_identical(week_from_query(NULL, demo), this_week)
})

test_that("a snapshot missing whole systems says so once, in plain words", {
  expect_null(snapshot_missing_note(demo$history, 9L))
  note <- snapshot_missing_note(demo$history, 3L)
  expect_identical(note, "SP+, FPI and SRS were not saved before week 8, so this snapshot blends Elo and Power only.")

  pred <- predict_matchup("Ironwood", "Kofa", "neutral", snapshot_teams(demo, 3L), demo$params, week = 3L)
  flags <- snapshot_flags(pred, demo$history, 3L)
  expect_identical(flags[1], note)
  expect_false(any(grepl("no rating for one of these teams", flags)))
  # The early-season note from the prediction itself is kept.
  expect_true(any(grepl("^Early season", flags)))
})

test_that("a team one system skipped still gets the prediction's own note", {
  gap <- demo
  gap$history$sp[gap$history$week == 9L & gap$history$team_id == id_of("Kofa")] <- NA
  pred <- predict_matchup("Ironwood", "Kofa", "neutral", snapshot_teams(gap, 9L), gap$params, week = 9L)
  expect_true(missing_models_flag("SP+") %in% snapshot_flags(pred, gap$history, 9L))
})

test_that("snapshot_result finds the game in either order, with the saved lines", {
  game <- demo$results[demo$results$week == 9L, ][1, ]
  saved <- demo$scorecard$games[demo$scorecard$games$game_id == game$game_id, ]
  result <- snapshot_result(demo, 9L, game$away_id, game$home_id)
  school <- function(id) teams$school[teams$team_id == id]

  expect_identical(result, snapshot_result(demo, 9L, game$home_id, game$away_id))
  expect_identical(result$final, format_final(school(game$home_id), school(game$away_id),
                                              game$home_points, game$away_points))
  expect_identical(result$saved, format_favorite(saved$blend, school(game$home_id), school(game$away_id)))
  expect_identical(result$market,
                   format_favorite(-saved$market_spread_home, school(game$home_id), school(game$away_id)))

  # The same two teams did not play in another week.
  expect_null(snapshot_result(demo, 3L, game$home_id, game$away_id))
  expect_null(snapshot_result_fact(NULL))
  html <- as.character(snapshot_result_fact(result))
  expect_match(html, "Final score", fixed = TRUE)
  expect_match(html, "The line we saved that week", fixed = TRUE)
})

test_that("a played game with no saved prediction shows the final score alone", {
  unsaved <- demo
  game <- demo$results[demo$results$week == 9L, ][1, ]
  unsaved$scorecard$games <- demo$scorecard$games[demo$scorecard$games$game_id != game$game_id, ]
  result <- snapshot_result(unsaved, 9L, game$home_id, game$away_id)
  expect_null(result$saved)
  expect_null(result$market)
  expect_false(grepl("saved that week", as.character(snapshot_result_fact(result))))
})

weeks <- snapshot_weeks(demo)
teams_by_week <- stats::setNames(lapply(weeks, function(w) snapshot_teams(demo, w)), weeks)
a <- id_of("Ironwood")
b <- id_of("Kofa")
trend <- matchup_trend(a, b, "a_home", teams_by_week, demo$params)
pred <- predict_matchup(a, b, "a_home", teams, demo$params, week = this_week)

test_that("matchup_trend matches a prediction made on each week's ratings", {
  expect_named(trend, c("week", "model", "label", "margin", "complete"))
  expect_identical(sort(unique(trend$week)), weeks)
  for (week in c(3L, 9L, this_week)) {
    then <- predict_matchup(a, b, "a_home", teams_by_week[[as.character(week)]], demo$params, week = week)
    rows <- trend[trend$week == week, ]
    expect_equal(rows$margin[rows$model == "blend"], then$spread)
    expect_equal(rows$margin[rows$model == "power"], then$models$margin[then$models$model == "power"])
  }
  # Weeks with no saved SP+ have no SP+ row, and the blend is marked partial.
  expect_false(any(trend$model == "sp" & trend$week < 8L))
  expect_false(any(trend$complete[trend$week < 8L]))
  expect_true(all(trend$complete[trend$week >= 8L]))
})

test_that("rating_trend is the two teams' history in long form", {
  ratings <- rating_trend(demo$history, c(a, b))
  expect_named(ratings, c("week", "team_id", "model", "label", "rating"))
  expect_setequal(ratings$team_id, c(a, b))
  expect_false(anyNA(ratings$rating))
  expect_identical(sum(ratings$model == "power"), 2L * length(weeks))
  expect_identical(sum(ratings$model == "sp"), 2L * sum(weeks >= 8L))
  now <- ratings[ratings$week == this_week & ratings$team_id == a & ratings$model == "elo", ]
  expect_equal(now$rating, teams$elo[teams$team_id == a])
})

test_that("the trend charts build, wide and narrow, and with a single week", {
  colors <- pick_team_colors(pred$team_a, pred$team_b)
  ratings <- rating_trend(demo$history, c(a, b))
  for (narrow in c(FALSE, TRUE)) {
    expect_no_error(ggplot2::ggplot_build(matchup_trend_plot(trend, pred, 9L, narrow)))
  }
  expect_no_error(ggplot2::ggplot_build(rating_trend_plot(ratings, pred, colors, 9L, columns = 2)))
  one_week <- trend[trend$week == this_week, ]
  expect_no_error(ggplot2::ggplot_build(matchup_trend_plot(one_week, pred, this_week)))
  expect_no_error(ggplot2::ggplot_build(
    rating_trend_plot(ratings[ratings$week == this_week, ], pred, colors, this_week)
  ))
})

test_that("every system on the chart has its own color", {
  expect_setequal(names(MODEL_COLORS), names(MODEL_LABELS))
  expect_false(anyDuplicated(MODEL_COLORS) > 0)
  expect_true(all(is_hex_color(MODEL_COLORS)))
})

test_that("the chart readout and descriptions put the numbers in words", {
  readout <- matchup_trend_readout(trend, 3L, pred)
  expect_match(readout, "^Week 3: Elo ")
  expect_match(readout, "Blend ", fixed = TRUE)
  expect_false(grepl("SP+", readout, fixed = TRUE))
  expect_match(matchup_trend_readout(trend, 9L, pred), "^Week 9: SP\\+ ")
  expect_null(matchup_trend_readout(trend, 40L, pred))

  expect_match(matchup_trend_alt(trend, pred), "in week 1 to .* in week 11\\.$")
  expect_match(matchup_trend_alt(trend[trend$week == 11L, ], pred), "one week so far")
  alt <- rating_trend_alt(rating_trend(demo$history, c(a, b)), pred)
  expect_match(alt, "Ironwood's Power rating went from", fixed = TRUE)
  expect_match(alt, "Kofa's Power rating went from", fixed = TRUE)

  expect_identical(week_breaks(1:6), 1:6)
  expect_identical(week_breaks(1:12), seq(2L, 12L, by = 2L))
  expect_identical(margin_labels(pred$team_a, pred$team_b)(c(NA, 0)), c("", "Even"))
})
