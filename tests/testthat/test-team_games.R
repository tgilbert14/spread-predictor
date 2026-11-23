# Last game and next game for the ranking tables (R/team_games.R).

league <- data.frame(team_id = 1:3, school = c("Kofa", "Ironwood", "Saguaro"), stringsAsFactors = FALSE)
games <- data.frame(
  home_id = c(1L, 2L, 3L, 1L), away_id = c(2L, 3L, 99L, 3L),
  home_team = c("Kofa", "Ironwood", "Saguaro", "Kofa"), away_team = c("Ironwood", "Saguaro", "Tiny Tech", "Saguaro"),
  neutral_site = c(FALSE, TRUE, FALSE, FALSE),
  start_date = c("2026-09-05T23:00:00Z", "2026-09-12T23:00:00Z", "2026-09-13T02:00:00Z", "2026-09-19T23:00:00Z"),
  when = c(1, 2, 2, 3),
  home_points = c(31L, 14L, 45L, NA), away_points = c(17L, 21L, 3L, NA),
  stringsAsFactors = FALSE
)
sides <- team_games(games, league)

test_that("every game gives each team a row from its own side", {
  expect_identical(nrow(sides), 8L)
  kofa <- sides[sides$team_id == 1 & sides$when == 1, ]
  expect_identical(kofa$opponent, "Ironwood")
  expect_identical(kofa$where, "vs")
  expect_identical(kofa$site, "a_home")
  expect_identical(c(kofa$points_for, kofa$points_against), c(31L, 17L))
  away <- sides[sides$team_id == 2 & sides$when == 1, ]
  expect_identical(c(away$where, away$site), c("at", "b_home"))
  # A neutral field reads "vs" for both teams.
  expect_identical(sides$where[sides$when == 2 & sides$team_id %in% 2:3 & sides$opponent_id %in% 2:3], c("vs", "vs"))
  # An opponent outside the teams table keeps the name the game carried.
  expect_identical(sides$opponent[sides$team_id == 3 & sides$opponent_id == 99], "Tiny Tech")
  expect_identical(nrow(team_games(games[0, ], league)), 0L)
})

test_that("last and next pick the right game for each team, in the order asked", {
  last <- last_games(sides, c(3L, 1L, 2L))
  expect_identical(last$team_id, c(3L, 1L, 2L))
  expect_identical(last$opponent, c("Tiny Tech", "Ironwood", "Saguaro"))  # Saguaro's later game that week
  expect_identical(last_games(sides, 3L, before = 2)$team_id, NA_integer_)  # nothing before week 2
  ahead <- next_games(sides, c(1L, 2L), from = 3)
  expect_identical(ahead$opponent[1], "Saguaro")
  expect_true(is.na(ahead$team_id[2]))  # Ironwood has no game left
  expect_identical(next_games(sides, 1L, from = 1)$opponent, "Ironwood")  # a past week: that week's game
})

test_that("cells read as plain results and matchups", {
  html <- result_html(last_games(sides, c(1L, 2L)))
  expect_match(html[1], ">W<", fixed = TRUE)
  expect_match(html[1], "31-17 vs Ironwood", fixed = TRUE)
  expect_match(html[2], ">L<", fixed = TRUE)
  expect_match(html[1], "Sat, Sep 5", fixed = TRUE)  # a US evening, not the next day in UTC
  expect_match(result_html(last_games(sides, 3L, before = 2)), "No game yet", fixed = TRUE)

  ahead <- next_games(sides, c(1L, 2L), from = 3)
  line <- our_lines(ahead, league, function(team, opponent, site) if (site == "a_home") 6.5 else NA)
  expect_identical(line, c("Our line: Kofa by 6.5", ""))
  html <- upcoming_html(ahead, line, none = "None soon")
  expect_match(html[1], "vs Saguaro", fixed = TRUE)
  expect_match(html[1], "Our line: Kofa by 6.5", fixed = TRUE)
  expect_match(html[2], "None soon", fixed = TRUE)
  # A game since played shows its result, and gets no line.
  expect_match(upcoming_html(next_games(sides, 1L, from = 1)), "31-17", fixed = TRUE)
  expect_identical(our_lines(next_games(sides, 3L, from = 2), league, function(...) 3), "")
})

test_that("a line the model cannot make is left out, not an error", {
  ahead <- next_games(sides, 1L, from = 3)
  expect_identical(our_lines(ahead, league, function(...) stop("no ratings")), "")
})

test_that("the football tables switch between rankings, last game and next game", {
  demo <- complete_app_data(demo_app_data())
  expect_true(is.data.frame(demo$upcoming))
  sides <- football_team_games(demo)
  ids <- utils::head(demo$teams$team_id, 5)
  last <- football_games_column(demo, sides, ids, demo$meta$week, "last")
  expect_identical(last$header, "Last game")
  expect_length(last$html, 5)
  ahead <- football_games_column(demo, sides, ids, demo$meta$week, "next")
  expect_identical(ahead$header, "Next game")
  expect_true(any(grepl("Our line:", ahead$html, fixed = TRUE)))
  # A week already played is labeled as that week's game.
  back <- min(demo$results$week)
  expect_identical(football_games_column(demo, sides, unique(demo$results$home_id[demo$results$week == back]),
                                         back, "next")$header, sprintf("Week %d game", back))

  upcoming <- upcoming_forecast(demo)
  if (!is.null(upcoming)) {
    html <- as.character(upcoming_forecast_table(upcoming, demo, "last", sides))
    expect_match(html, "Last game", fixed = TRUE)
    expect_false(grepl("Last ranking", html, fixed = TRUE))
  }
  expect_identical(ranking_view(NULL), "ranks")
  expect_identical(ranking_view("next"), "next")
  expect_identical(ranking_view("nonsense"), "ranks")
})

test_that("the latest ranking splits last from next at the first week still to play", {
  demo <- complete_app_data(demo_app_data())
  expect_identical(games_week(demo, demo$meta$week - 1L), demo$meta$week - 1L)  # a look back
  later <- demo
  later$meta$forecast_week <- demo$meta$week + 1L
  later$upcoming$week <- demo$meta$week + 1L
  expect_equal(games_week(later, later$meta$week), demo$meta$week + 1L)
  none <- demo
  none$upcoming <- none$upcoming[0, ]
  none$meta$forecast_week <- NA_integer_
  expect_equal(games_week(none, none$meta$week), none$meta$week)
})
