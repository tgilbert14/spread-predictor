#' Build app data from a fresh fixture. Returns the list and the paths used.
build_fixture_app_data <- function(snapshots = TRUE) {
  db <- make_fixture_db(snapshots = snapshots)
  params_path <- tempfile(fileext = ".json")
  out_path <- tempfile(fileext = ".rds")
  con <- connect_readonly(db)
  write_params(with_project_root(fit_params(con)), params_path)
  DBI::dbDisconnect(con)
  list(db = db, params_path = params_path, out_path = out_path,
       app = with_project_root(build_app_data(db, params_path, out_path)))
}

built <- build_fixture_app_data()
app <- built$app

test_that("app data has the shape in the data dictionary", {
  expect_named(app, c("meta", "teams", "params", "slate", "coverage", "scorecard"))
  expect_named(app$meta, c("season", "week", "ratings_date", "built_at", "is_demo"))
  expect_identical(app$meta$season, FIXTURE_SEASON)
  expect_identical(app$meta$week, FIXTURE_WEEK)
  expect_identical(app$meta$ratings_date, "2026-11-10")
  expect_false(app$meta$is_demo)

  team_columns <- c("team_id", "school", "mascot", "abbreviation", "conference", "color",
                    "alt_color", "logo", "tier", "talent_z", "returning_z", names(MODEL_LABELS),
                    paste0(names(MODEL_LABELS), "_rank"))
  expect_true(all(team_columns %in% names(app$teams)))
  expect_named(app$slate, c("game_id", "start_date", "home_id", "away_id",
                            "neutral_site", "market_spread_home", "market_at_freeze", "market_move"))
  expect_named(app$scorecard, c("games", "weeks", "season", "systems"))
  # No predictions saved in the project's own folder for the fixture season,
  # so nothing is graded and nothing has moved.
  expect_identical(nrow(app$scorecard$season), 1L)
  expect_named(app$coverage, c("source", "season", "week", "n_teams", "pulled_at"))
  expect_identical(app$params, read_params(built$params_path))
  expect_identical(readRDS(built$out_path), app)
})

test_that("column types match the demo data the app was built against", {
  demo <- demo_app_data()
  for (element in c("teams", "slate", "coverage")) {
    shared <- intersect(names(demo[[element]]), names(app[[element]]))
    expect_identical(vapply(app[[element]][shared], class, character(1)),
                     vapply(demo[[element]][shared], class, character(1)), label = element)
  }
})

test_that("ranks run from 1 for the best rating, share ties and keep NA", {
  teams <- app$teams
  for (source in names(MODEL_LABELS)) {
    rated <- !is.na(teams[[source]])
    best <- teams[[source]] == max(teams[[source]], na.rm = TRUE)
    expect_true(all(teams[[paste0(source, "_rank")]][which(best)] == 1L))
    expect_identical(is.na(teams[[paste0(source, "_rank")]]), !rated)
  }
  tied <- teams[teams$team_id %in% 1:2, ]
  expect_identical(tied$sp[1], tied$sp[2])
  expect_identical(tied$sp_rank[1], tied$sp_rank[2])
  expect_identical(sum(teams$sp > tied$sp[1]) + 1L, tied$sp_rank[1])

  expect_true(is.na(teams$fpi[teams$team_id == 3]))
})

test_that("each source uses its own latest snapshot when one lags", {
  con <- connect_readonly(built$db)
  on.exit(DBI::dbDisconnect(con))
  elo_week_10 <- DBI::dbGetQuery(con, "SELECT team_id, rating FROM ratings
                                       WHERE source = 'elo' AND week = 10 AND season = 2026")
  sp_week_11 <- DBI::dbGetQuery(con, "SELECT team_id, rating FROM ratings
                                      WHERE source = 'sp' AND week = 11 AND season = 2026")
  teams <- app$teams
  expect_false(anyNA(teams$elo))
  expect_equal(teams$elo, elo_week_10$rating[match(teams$team_id, elo_week_10$team_id)])
  expect_equal(teams$sp, sp_week_11$rating[match(teams$team_id, sp_week_11$team_id)])
})

test_that("Power ratings come from every completed game and tier from the conference", {
  con <- connect_readonly(built$db)
  on.exit(DBI::dbDisconnect(con))
  games <- with_project_root(query_sql_file(con, "rating_games.sql", list(BURN_IN_SEASON)))
  conferences <- with_project_root(query_sql_file(con, "team_conferences.sql"))
  current <- power_ratings(games, conferences)$current

  teams <- app$teams
  rated <- !is.na(teams$power)
  expect_equal(mean(teams$power[rated]), 0)
  # Centered for display, so gaps between teams match the raw ratings.
  raw <- current$power[match(teams$team_id[rated], current$team_id)]
  expect_equal(teams$power[rated] - teams$power[rated][1], raw - raw[1])
  expect_identical(teams$tier, as.integer(teams$team_id <= FIXTURE_POWER_TEAMS))
})

test_that("teams carry this season's preseason z-scores", {
  con <- connect_readonly(built$db)
  on.exit(DBI::dbDisconnect(con))
  preseason <- with_project_root(load_preseason(con))
  preseason <- preseason[preseason$season == FIXTURE_SEASON, ]
  expect_false(anyNA(app$teams$talent_z))
  expect_gt(stats::sd(app$teams$talent_z), 0.5)
  expect_identical(app$teams$talent_z[app$teams$team_id == 5], 0)
  expect_equal(app$teams$talent_z, preseason$talent_z[match(app$teams$team_id, preseason$team_id)])
  expect_equal(app$teams$returning_z, preseason$returning_z[match(app$teams$team_id, preseason$team_id)])
})

test_that("the slate holds only unplayed FBS games, with the median line", {
  slate <- app$slate
  expect_identical(nrow(slate), 6L)
  expect_identical(slate$market_spread_home[slate$game_id == FIXTURE_LINED_GAME], -4)
  expect_true(is.na(slate$market_spread_home[slate$game_id == FIXTURE_UNLINED_GAME]))
  expect_type(slate$neutral_site, "logical")
})

test_that("predict_matchup works on the built data", {
  for (i in seq_len(nrow(app$slate))) {
    site <- if (app$slate$neutral_site[i]) "neutral" else "a_home"
    pred <- predict_matchup(app$slate$home_id[i], app$slate$away_id[i], site,
                            app$teams, app$params)
    expect_true(is.finite(pred$spread))
  }
  # Team 3 has no FPI rating this week, so FPI drops out with a note.
  rated <- app$teams$team_id[!is.na(app$teams$power) & app$teams$team_id != 3]
  pred <- predict_matchup(3, rated[1], "neutral", app$teams, app$params)
  expect_true(any(grepl("FPI has no rating", pred$flags)))

  # A team that has not played this season has no Power rating yet.
  unplayed <- app$teams$team_id[is.na(app$teams$power) & !is.na(app$teams$fpi)]
  pred <- predict_matchup(unplayed[1], rated[1], "neutral", app$teams, app$params)
  expect_true(any(grepl("Power has no rating", pred$flags)))
})

test_that("missing inputs fail with a plain next step", {
  expect_error(with_project_root(build_app_data(built$db, tempfile(), tempfile())),
               "scripts/fit.R")
  expect_error(with_project_root(build_app_data(tempfile(), built$params_path, tempfile())),
               "scripts/refresh.R")

  no_snapshots <- make_fixture_db(snapshots = FALSE)
  expect_error(with_project_root(build_app_data(no_snapshots, built$params_path, tempfile())),
               "scripts/snapshot.R")
})

test_that("saved predictions are graded and give the slate its line movement", {
  root <- tempfile()
  con <- connect_readonly(built$db)
  played <- DBI::dbGetQuery(con, "SELECT game_id, start_date, home_id, away_id, neutral_site
                                  FROM games WHERE season = 2026 AND week = 10")
  DBI::dbDisconnect(con)
  played$neutral_site <- played$neutral_site == 1
  played$market_spread_home <- -3
  this_week <- app$slate
  this_week$market_spread_home[this_week$game_id == FIXTURE_LINED_GAME] <- -6
  suppressMessages({
    write_snapshot(prediction_rows(played, app$teams, app$params, 2026L, 10L), prediction_path(2026, 10, root))
    write_snapshot(prediction_rows(this_week, app$teams, app$params, 2026L, 11L), prediction_path(2026, 11, root))
  })

  again <- suppressMessages(with_project_root(
    build_app_data(built$db, built$params_path, tempfile(), snapshots_root = root)
  ))
  lined <- again$slate[again$slate$game_id == FIXTURE_LINED_GAME, ]
  expect_identical(lined$market_at_freeze, -6)
  # From a 6-point home favorite to a 4-point one: 2 points toward the away team.
  expect_identical(lined$market_move, -2)

  card <- again$scorecard
  expect_gt(card$season$games, 0)
  expect_identical(card$weeks$week, 10L)
  unplayed <- card$games[card$games$week == 11, ]
  expect_gt(nrow(unplayed), 0)
  expect_true(all(is.na(unplayed$final_margin)))
})
