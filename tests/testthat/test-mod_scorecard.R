# Scorecard tab helpers and markup.

demo <- complete_app_data(demo_app_data())

test_that("the headline says the season in one plain sentence", {
  season <- data.frame(our_miss = 12.44, market_miss = 11.9)
  expect_identical(scorecard_headline(season), "Off by 12.4 points a game. The market: 11.9.")
  season$market_miss <- NA
  expect_identical(scorecard_headline(season), "Off by 12.4 points a game.")
  expect_identical(scorecard_context(data.frame(season = 2026L, games = 1L), 1),
                   "2026 season to date, 1 game over 1 week.")
})

test_that("records, finals and closer read naturally", {
  expect_identical(format_record(c(7, 0), c(19, 0)), c("7 of 19", "None"))
  expect_identical(format_final("Kofa", "Ironwood", 17L, 31L), "Ironwood 31, Kofa 17")
  expect_identical(format_final("Kofa", "Ironwood", 31L, 17L), "Kofa 31, Ironwood 17")
  expect_identical(format_closer(c("us", "market", "tie", NA), c(3, 9, 2, 5), c(5.5, 5, 2, NA)),
                   c("Us, by 2.5", "Market, by 4", "Even", "No line"))
})

test_that("game rows read away first with home-relative margins turned around", {
  games <- data.frame(away_team = "Kofa", home_team = "Ironwood", neutral_site = 0L,
                      blend = 7, market_spread_home = 3, home_points = 20L, away_points = 24L,
                      final_margin = -4L, our_error = 11, market_error = 1, closer = "market")
  rows <- scorecard_game_rows(games)
  expect_match(rows$our, "Ironwood by 7")
  expect_match(rows$market, "Kofa by 3")
  expect_match(rows$final, "Kofa 24, Ironwood 20")
  expect_match(rows$closer, "Market, by 10")
  expect_match(rows$matchup, "Kofa</span> <span class=\"slate-at\">at</span>")
})

test_that("the empty state says what is saved and when results appear", {
  html <- as.character(scorecard_empty(data.frame(week = c(11L, 11L, 11L))))
  expect_match(html, "We saved 3 predictions for week 11 before the first kickoff.")
  expect_match(html, "next data refresh")
  expect_match(as.character(scorecard_empty(data.frame(week = integer()))), "No predictions saved yet")

  empty <- demo
  empty$scorecard <- empty_scorecard(2026L)
  expect_match(as.character(mod_scorecard_ui("s", empty)), "No predictions saved yet")
})

test_that("the demo scorecard renders every section", {
  html <- as.character(mod_scorecard_ui("s", demo))
  expect_match(html, "Off by [0-9.]+ points a game\\. The market: [0-9.]+\\.")
  for (text in c("Games graded", "Winners picked", "Closer than the market",
                 "When we disagreed by 3 or more", "Week by week", "All five systems, graded",
                 "first honest look", "too little to judge a model", "Week 10 games")) {
    expect_match(html, text, fixed = TRUE)
  }
  expect_false(grepl("—", html))  # no em dashes
})
