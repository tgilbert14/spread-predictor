# Who played quarterback, from the box scores (R/passing.R, R/quarterbacks.R).

box <- function(game, week, athlete, attempts, yards = attempts * 7, team = 1L) {
  data.frame(game_id = game, season = 2026L, week = week, team = "Kofa", team_id = team,
             start_date = sprintf("2026-09-%02dT20:00:00Z", week), athlete_id = athlete,
             athlete = paste("QB", athlete), completions = attempts %/% 2L, attempts = attempts,
             yards = yards, stringsAsFactors = FALSE)
}
# A starts three games, misses two, then B takes over as the main quarterback.
passing <- rbind(box(1L, 1L, "A", 30L), box(2L, 2L, "A", 30L), box(2L, 2L, "B", 2L), box(3L, 3L, "A", 30L),
                 box(4L, 4L, "B", 35L), box(5L, 5L, "B", 35L), box(6L, 6L, "B", 35L), box(7L, 7L, "B", 35L))

test_that("a game flags the main quarterback as out only from what came before", {
  games <- quarterback_games(passing)
  expect_identical(games$game_id, 1:7)
  expect_true(is.na(games$main_qb[1]))          # nothing known going into the first game
  expect_identical(games$main_qb[2:4], rep("A", 3))
  expect_identical(games$out_now, c(0L, 0L, 0L, 1L, 1L, 1L, 0L))
  expect_identical(games$out_prev[5], 1L)       # known before kickoff of game 5
  expect_identical(games$games_out[c(4, 5, 6)], c(0L, 1L, 2L))
  # After game 6, B has thrown more than A, so B is the main quarterback and is not out.
  expect_identical(games$main_qb[7], "B")
  expect_identical(c(games$out_now[7], games$out_prev[7], games$games_out[7]), c(0L, 0L, 0L))
  expect_identical(games$starter[4], "B")
})

test_that("only an established starter counts as established", {
  games <- quarterback_games(passing)
  expect_identical(games$established[2], 0L)    # 30 attempts is under the minimum
  expect_identical(games$established[4], 1L)    # 90 of 92 attempts
  split <- rbind(box(1L, 1L, "A", 40L), box(1L, 1L, "B", 40L), box(2L, 2L, "A", 40L), box(2L, 2L, "B", 35L),
                 box(3L, 3L, "B", 30L))
  expect_identical(quarterback_games(split)$established[3], 0L)  # a time share, not a starter
})

test_that("yards per attempt waits for enough throws", {
  games <- quarterback_games(passing)
  expect_true(is.na(games$main_ypa[2]))
  expect_equal(games$main_ypa[4], 7)
})

test_that("the summary says who the quarterback is now and who opened the season", {
  status <- quarterback_summary(passing)
  expect_identical(status$starter, "QB B")
  expect_identical(status$starts, 4L)
  expect_identical(status$opener, "QB A")
  expect_identical(status$opener_last_week, 3L)
  expect_true(status$changed)
  expect_identical(quarterback_sentence(status),
                   "QB B has started the last 4 games. QB A, who opened the season as the starter, last played in week 3.")
  steady <- quarterback_summary(passing[passing$athlete_id == "A", ])
  expect_identical(quarterback_sentence(steady), "QB A has been the quarterback all season.")
  expect_identical(nrow(quarterback_summary(NULL)), 0L)
  expect_null(quarterback_sentence(status[0, ]))
})

test_that("box scores flatten to one row per passer, without the team total", {
  athlete <- function(id, name, stat) list(id = id, name = name, stat = stat)
  week <- list(list(id = 9L, teams = list(list(
    team = "Kofa", categories = list(list(name = "passing", types = list(
      list(name = "C/ATT", athletes = list(athlete("11", "QB One", "20/31"), athlete("12", "QB Two", "1/2"),
                                           athlete("-1", " Team", "21/33"))),
      list(name = "YDS", athletes = list(athlete("11", "QB One", "250"), athlete("12", "QB Two", "9")))
    )))
  ), list(team = "Ironwood", categories = list()))))
  rows <- passing_rows(week, 2026, 3)
  expect_identical(rows$athlete, c("QB One", "QB Two"))
  expect_identical(rows$attempts, c(31L, 2L))
  expect_identical(rows$completions, c(20L, 1L))
  expect_identical(rows$yards, c(250L, 9L))
  expect_identical(nrow(passing_rows(list(), 2026, 3)), 0L)
})

test_that("passing rows pick up team ids from the game, and drop names that match neither side", {
  raw <- data.frame(game_id = c(5L, 5L, 5L), team = c("Kofa", "Ironwood", "Nowhere"), stringsAsFactors = FALSE)
  games <- data.frame(game_id = 5L, start_date = "2026-09-05T20:00:00Z", home_id = 1L, away_id = 2L,
                      home_team = "Kofa", away_team = "Ironwood", stringsAsFactors = FALSE)
  joined <- passing_with_teams(raw, games)
  expect_identical(joined$team_id, c(1L, 2L))
})

test_that("a big gap to the market is flagged beside the game", {
  expect_match(slate_markers(NA, 0, gap = 8), "Big gap: check for news", fixed = TRUE)
  expect_match(slate_markers(NA, 0, gap = -7), "Big gap", fixed = TRUE)
  expect_identical(slate_markers(NA, 0, gap = 6.5), "")
  expect_identical(slate_markers(NA, 0), "")
})
