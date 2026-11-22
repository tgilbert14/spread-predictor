# The small HTML charts (R/charts.R).

test_that("the scale zooms to the values and keeps every one on the track", {
  scale <- chart_scale(c(12.1, 12.5, 12.8))
  expect_lt(scale$low, 12.1)
  expect_gt(scale$high, 12.8)
  expect_true(all(scale$at > 0 & scale$at < 100))
  expect_false(is.unsorted(scale$at))
  # Equal values still get a track with room on both sides.
  flat <- chart_scale(c(10, 10))
  expect_gt(flat$high, flat$low)
  expect_equal(flat$at[1], flat$at[2])
})

test_that("a dot chart prints every number and marks ours and the benchmark", {
  html <- as.character(dot_chart(c("Market", "Blend", "Power"), c(12.1, 12.5, 12.8),
                                 highlight = c(FALSE, TRUE, FALSE), benchmark = c(TRUE, FALSE, FALSE),
                                 note = "Left is better."))
  for (text in c("Market", "Blend", "Power", "12.1", "12.5", "12.8", "Left is better.", "Benchmark")) {
    expect_match(html, text, fixed = TRUE)
  }
  expect_identical(lengths(regmatches(html, gregexpr("chart-ref", html))), 3L)  # the line runs through every row
  expect_match(html, "is-ours", fixed = TRUE)
})

test_that("a dumbbell row copes with a week that has no market line", {
  html <- as.character(dumbbell_chart(c("Week 1", "Week 2"), c(12, 13), c(11.5, NA)))
  expect_identical(lengths(regmatches(html, gregexpr("chart-link", html))), 1L)
  expect_match(html, "11.5", fixed = TRUE)
})

test_that("the versus bar splits by count and drops empty sides", {
  html <- as.character(versus_bar(3, 1))
  expect_match(html, "--share:75.00%", fixed = TRUE)
  expect_false(grepl("is-even", html))
  expect_match(as.character(versus_bar(1, 1, even = 2)), "is-even", fixed = TRUE)
  expect_null(versus_bar(0, 0))
})

test_that("a ring fills by its share and shows an empty ring when there is nothing to count", {
  expect_match(as.character(ring_stat("Winners", 0.5, "50%", "Half.")), sprintf("--filled:%.1f", pi * 42), fixed = TRUE)
  expect_match(as.character(ring_stat("Winners", NA, "None", "No games.")), "--filled:0.0", fixed = TRUE)
})

test_that("swing rows grow toward whoever was closer and open on a tap", {
  html <- as.character(swing_chart(c("A at B", "C at D"), c(4, -8), c("4", "8"), hover = c("first", "second")))
  expect_match(html, "<button", fixed = TRUE)
  expect_match(html, "--size:25.0%", fixed = TRUE)  # 4 of the longest 8, half the track
  expect_match(html, "--size:50.0%", fixed = TRUE)
  expect_match(html, "second", fixed = TRUE)
  expect_false(grepl("<button", as.character(swing_chart("A at B", 4, "4"))))
  expect_null(swing_chart(character(), numeric(), character()))
})

test_that("the tile grid says in words which tiles are missing", {
  ok <- matrix(c(TRUE, FALSE), 1, 2)
  html <- as.character(tile_grid("2026, week 12", c("SP+", "FPI"), ok))
  expect_match(html, "is-missing", fixed = TRUE)
  expect_match(html, ">Missing<", fixed = TRUE)
  expect_match(html, ">Saved<", fixed = TRUE)
})

test_that("the scorecard's biggest calls show both sides and survive odd weeks", {
  demo <- complete_app_data(demo_app_data())
  games <- demo$scorecard$games
  games <- games[!is.na(games$final_margin), , drop = FALSE]
  html <- as.character(scorecard_calls(games))
  expect_match(html, "We were closer", fixed = TRUE)
  expect_match(html, "Our line:", fixed = TRUE)
  no_line <- transform(games, market_error = NA_real_)
  expect_match(as.character(scorecard_calls(no_line)), "No market line", fixed = TRUE)
})

test_that("the model report draws charts and keeps the tables behind them", {
  demo <- complete_app_data(demo_app_data())
  html <- as.character(mod_report_ui("r", demo))
  for (text in c("Rate every team", "Read the full explanation", "dot-chart", "share-strip",
                 "See the numbers", "tile-grid")) {
    expect_match(html, text, fixed = TRUE)
  }
})
