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

# ---- Reports of quarterbacks listed out ---------------------------------------

report <- function(week, team, athlete, status, at = "2026-11-19T02:00:00Z") {
  data.frame(season = 2026L, week = week, team = team, athlete = athlete, status = status, source = "Report",
             source_url = "https://example.com", checked_at = at, stringsAsFactors = FALSE)
}

test_that("names match across spellings, and different players do not", {
  expect_true(same_player("Billy Edwards Jr.", "Billy Edwards"))
  expect_true(same_player("nico iamaleava", "Nico Iamaleava"))
  expect_true(same_player("J. Sagapolutele", "Jaron-Keawe Sagapolutele"))
  expect_false(same_player("Nico Iamaleava", "Madden Iamaleava"))
  expect_false(same_player("", "Nico Iamaleava"))
})

test_that("only an established starter who is listed out counts", {
  status <- rbind(report(12L, "Kofa", "Sam Stone", "out"), report(12L, "Ironwood", "Al Reed", "questionable"),
                  report(11L, "Saguaro", "Bo Lake", "out_for_season"), report(12L, "Rincon", "Cy Hale", "out"))
  mains <- data.frame(team = c("Kofa", "Ironwood", "Saguaro", "Rincon", "Kofa"), week = 12L,
                      main_name = c("Sam Stone", "Al Reed", "Bo Lake", "Dee Park", "Sam Stone"),
                      established = c(1, 1, 1, 1, 0), stringsAsFactors = FALSE)
  # Kofa: out. Ironwood: only questionable. Saguaro: out for the season since week 11.
  # Rincon: the player listed is not the main quarterback. Last row: not established.
  expect_identical(starter_out(status, mains), c(TRUE, FALSE, TRUE, FALSE, FALSE))
  expect_identical(starter_out(status, mains[0, ]), logical())
})

test_that("a later report wins, and one filed after kickoff does not count", {
  status <- rbind(report(12L, "Kofa", "Sam Stone", "out", "2026-11-19T02:00:00Z"),
                  report(12L, "Kofa", "Sam Stone", "probable", "2026-11-20T02:00:00Z"))
  main <- data.frame(team = "Kofa", week = 12L, main_name = "Sam Stone", established = 1, stringsAsFactors = FALSE)
  expect_false(starter_out(status, main))
  expect_true(starter_out(status[1, ], main))
  expect_false(starter_out(status[1, ], cbind(main, before = "2026-11-18T00:00:00Z")))
  expect_true(starter_out(status[1, ], cbind(main, before = "2026-11-21T20:00:00Z")))
})

test_that("the adjustment moves the line against the team whose quarterback is out", {
  expect_identical(qb_home_adjustment(TRUE, FALSE), -QB_OUT_POINTS)
  expect_identical(qb_home_adjustment(FALSE, TRUE), QB_OUT_POINTS)
  expect_identical(qb_home_adjustment(TRUE, TRUE), 0)
  expect_identical(qb_home_adjustment(FALSE, FALSE), 0)
})

test_that("the status file loads safely whatever shape it is in", {
  expect_identical(nrow(load_qb_status(tempfile(), 2026L)), 0L)
  path <- tempfile(fileext = ".csv")
  writeLines(c("season,week,team,athlete,status", "2026,12,Kofa,Sam Stone,Out for season", "2025,12,Kofa,Old Guy,out",
               "2026,,Kofa,No Week,out", "2026,12,,No Team,out"), path)
  loaded <- load_qb_status(path, 2026L)
  expect_identical(nrow(loaded), 1L)
  expect_identical(loaded$status, "out_for_season")
  expect_named(loaded, QB_STATUS_COLUMNS)
})

test_that("grading uses the main quarterback going into each game and only reports before kickoff", {
  games <- data.frame(game_id = 1:2, week = 12L, start_date = "2026-11-21T20:00:00Z", home_id = c(1L, 3L),
                      away_id = c(2L, 4L), home_team = c("Kofa", "Saguaro"), away_team = c("Ironwood", "Rincon"),
                      blend = c(7, -3), market_spread_home = c(-4, NA), final_margin = c(2, -10),
                      stringsAsFactors = FALSE)
  qb_games <- data.frame(game_id = c(1L, 1L, 2L, 2L), team_id = 1:4,
                         main_name = c("Sam Stone", "Al Reed", "Bo Lake", "Cy Hale"), established = 1L,
                         stringsAsFactors = FALSE)
  status <- rbind(report(12L, "Kofa", "Sam Stone", "out"), report(12L, "Rincon", "Cy Hale", "out", "2026-11-22T02:00:00Z"))
  graded <- grade_qb_adjustment(games, qb_games, status, NULL)
  expect_identical(graded$game_id, 1L)                       # Rincon's report came after kickoff
  expect_equal(graded$adjusted, 7 - QB_OUT_POINTS)
  expect_equal(c(graded$our_miss, graded$adjusted_miss, graded$market_miss), c(5, 1.5, 2))
  expect_match(graded$out, "Sam Stone (Kofa)", fixed = TRUE)
  expect_identical(nrow(grade_qb_adjustment(games, qb_games, status[0, ], NULL)), 0L)
})

test_that("the slate shows the adjusted line and a marker when a starter is out", {
  demo <- complete_app_data(demo_app_data())
  game <- demo$slate[1, ]
  pred <- predict_matchup(game$away_id, game$home_id, "b_home", demo$teams, demo$params, week = demo$meta$week)
  plain <- slate_row(pred, game, "open")
  expect_false(grepl("adj-line", plain$our, fixed = TRUE))
  hit <- slate_row(pred, game, "open", qb_out = c(away = FALSE, home = TRUE))
  expect_match(hit$our, "With QB out", fixed = TRUE)
  expect_match(hit$matchup, paste(pred$team_b$school, "QB out"), fixed = TRUE)
  expect_match(hit$our, htmltools::htmlEscape(format_favorite(pred$spread + QB_OUT_POINTS, pred$team_a$school, pred$team_b$school)),
               fixed = TRUE)
  # With no reports the demo's slate is unchanged.
  expect_identical(nrow(qb_out_teams(demo, demo$meta$week)), 0L)
  expect_null(scorecard_qb_section(demo))
})

test_that("the summary notices an established starter who missed the latest game", {
  out_now <- rbind(box(1L, 1L, "A", 30L), box(2L, 2L, "A", 30L), box(3L, 3L, "A", 30L), box(4L, 4L, "B", 20L))
  expect_true(quarterback_summary(out_now)$missed_last)
  expect_false(quarterback_summary(out_now[1:3, ])$missed_last)
  # Not established yet: nothing to flag.
  expect_false(quarterback_summary(rbind(box(1L, 1L, "A", 30L), box(2L, 2L, "B", 20L)))$missed_last)
})

test_that("the committee prediction flags a team whose starter is out", {
  demo <- complete_app_data(demo_app_data())
  upcoming <- upcoming_forecast(demo)
  skip_if(is.null(upcoming))
  team <- demo$teams[demo$teams$team_id == upcoming$rows$team_id[2], ]
  demo$quarterbacks <- data.frame(team_id = team$team_id, starter = "QB B", starts = 1L, opener = "QB A",
                                  opener_last_week = 9L, changed = TRUE, main = "QB A", established = 1L,
                                  missed_last = TRUE, stringsAsFactors = FALSE)
  flagged <- qb_flagged_teams(demo, upcoming$week)
  expect_identical(flagged$why, "missed the last game")
  html <- as.character(upcoming_forecast_table(upcoming, demo))
  expect_match(html, "QB missed last game", fixed = TRUE)
  expect_match(html, "flagged and not scored", fixed = TRUE)
  # A report that he is out says so in fewer words.
  demo$qb_status <- report(upcoming$week, team$school, "QB A", "out")
  expect_identical(qb_flagged_teams(demo, upcoming$week)$why, "listed out")
  expect_match(as.character(upcoming_forecast_table(upcoming, demo)), ">QB out<", fixed = TRUE)
})
