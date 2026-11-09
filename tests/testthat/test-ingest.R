# Tests for R/ingest.R. No API calls: the raw inputs below are fake data
# frames shaped like cfbfastR output.

fake_teams_raw <- function() {
  data.frame(
    id = c(8L, 2L, 23L),
    school = c("Arizona", "Arizona State", "San José State"),
    mascot = c("Wildcats", "Sun Devils", "Spartans"),
    abbreviation = c("ARIZ", "ASU", "SJSU"),
    conference = c("Big 12", "Big 12", "Mountain West"),
    classification = "fbs",
    color = c("#003366", "8C1D40", "#0055A2"),
    alternate_color = c("#cc0033", "#FFC627", NA),
    logos_1 = c("http://a.png", "http://b.png", NA),
    logos_2 = "http://dark.png",
    stringsAsFactors = FALSE
  )
}

# Shaped like the real thing: each week is a Tuesday-to-Tuesday window.
fake_calendar <- function() {
  data.frame(
    season = "2026",
    week = c(1L, 2L, 11L, 12L, 13L, 1L),
    season_type = c(rep("regular", 5), "postseason"),
    first_game_start = c(
      "2026-07-25T07:00:00.000Z", "2026-09-01T07:00:00.000Z", "2026-11-03T08:00:00.000Z",
      "2026-11-10T08:00:00.000Z", "2026-11-17T08:00:00.000Z", "2026-12-08T08:00:00.000Z"
    ),
    last_game_start = c(
      "2026-09-01T06:59:00.000Z", "2026-09-08T06:59:00.000Z", "2026-11-10T07:59:00.000Z",
      "2026-11-17T07:59:00.000Z", "2026-11-24T07:59:00.000Z", "2027-01-13T07:59:00.000Z"
    ),
    stringsAsFactors = FALSE
  )
}

utc <- function(x) as.POSIXct(x, tz = "UTC")

test_that("current_season rolls over in August", {
  expect_equal(current_season(utc("2026-11-10 13:00:00")), 2026L)
  expect_equal(current_season(utc("2027-01-10 13:00:00")), 2026L)
  expect_equal(current_season(utc("2027-07-31 13:00:00")), 2026L)
  expect_equal(current_season(utc("2027-08-01 13:00:00")), 2027L)
})

test_that("snapshot_week labels the week whose games have not started", {
  cal <- fake_calendar()

  # The Tuesday cron, just after week 12's window opens: week 12.
  expect_equal(snapshot_week(cal, utc("2026-11-10 13:00:00")), list(season_type = "regular", week = 12L))

  # Monday, or Saturday with games under way: the next week.
  expect_equal(snapshot_week(cal, utc("2026-11-16 13:00:00"))$week, 13L)
  expect_equal(snapshot_week(cal, utc("2026-11-14 18:00:00"))$week, 13L)

  # Preseason, inside week 1's long window: week 1.
  expect_equal(snapshot_week(cal, utc("2026-08-10 13:00:00"))$week, 1L)

  # After the regular season ends: postseason.
  expect_equal(snapshot_week(cal, utc("2026-12-01 13:00:00"))$season_type, "postseason")

  # Nothing left: offseason, no crash.
  off <- snapshot_week(cal, utc("2027-01-10 13:00:00"))
  expect_true(is.na(off$season_type))
  expect_true(is.na(off$week))
})

test_that("snapshot_week accepts the raw CFBD calendar column names", {
  cal <- fake_calendar()
  names(cal)[names(cal) == "last_game_start"] <- "endDate"
  names(cal)[names(cal) == "season_type"] <- "seasonType"
  expect_equal(snapshot_week(cal, utc("2026-11-10 13:00:00"))$week, 12L)
  expect_error(snapshot_week(cal["week"]), "CFBD calendar.*Columns received: week")
})

test_that("snapshot_path follows the data dictionary layout", {
  expect_equal(snapshot_path("ratings", 2026, "sp", 11, root = "s"), file.path("s", "ratings", "sp", "2026_wk11.csv"))
  expect_equal(snapshot_path("ratings", 2026, "elo", 3, root = "s"), file.path("s", "ratings", "elo", "2026_wk03.csv"))
  expect_equal(snapshot_path("ratings", 2023, "fpi", root = "s"), file.path("s", "ratings", "fpi", "2023_final.csv"))
  expect_equal(snapshot_path("games", 2024, root = "s"), file.path("s", "games", "2024.csv"))
  expect_error(snapshot_path("ratings", 2024, "massey", root = "s"), "Unknown rating source")
})

test_that("write_snapshot never overwrites unless asked, and leaves no temp files", {
  dir <- withr::local_tempdir()
  path <- file.path(dir, "ratings", "sp", "2026_wk11.csv")

  expect_true(suppressMessages(write_snapshot(data.frame(x = 1), path)))
  expect_false(suppressMessages(write_snapshot(data.frame(x = 2), path)))
  expect_equal(read_snapshot(path)$x, 1)

  expect_true(suppressMessages(write_snapshot(data.frame(x = 3), path, overwrite = TRUE)))
  expect_equal(read_snapshot(path)$x, 3)

  expect_equal(list.files(dirname(path), all.files = TRUE, no.. = TRUE), "2026_wk11.csv")
})

test_that("pull_snapshot skips the API call when the file exists", {
  dir <- withr::local_tempdir()
  path <- file.path(dir, "teams", "2026.csv")
  calls <- 0
  fetch <- function() {
    calls <<- calls + 1
    data.frame(x = calls)
  }

  suppressMessages(pull_snapshot(path, fetch))
  suppressMessages(pull_snapshot(path, fetch))
  expect_equal(calls, 1)

  # Current-season games and lines are refreshed on purpose.
  suppressMessages(pull_snapshot(path, fetch, overwrite = TRUE))
  expect_equal(calls, 2)
  expect_equal(read_snapshot(path)$x, 2)
})

test_that("a failed fetch leaves no file behind", {
  dir <- withr::local_tempdir()
  path <- file.path(dir, "lines", "2026.csv")
  expect_error(pull_snapshot(path, function() stop("API down")), "API down")
  expect_false(file.exists(path))
})

test_that("select_columns names the columns it actually received", {
  raw <- data.frame(school = "Arizona", points = 1)
  expect_error(
    select_columns(raw, list(team = "team", rating = "rating"), what = "Test"),
    "could not find column\\(s\\) team, rating.*Columns received: school, points"
  )
})

test_that("normalize_teams maps cfbfastR columns and fixes colors", {
  teams <- normalize_teams(fake_teams_raw())
  expect_named(teams, c("team_id", "school", "mascot", "abbreviation", "conference", "color", "alt_color", "logo"))
  expect_type(teams$team_id, "integer")
  expect_equal(teams$color[teams$school == "Arizona State"], "#8C1D40")
  expect_equal(teams$logo[teams$school == "Arizona"], "http://a.png")
  expect_true(is.na(teams$alt_color[teams$school == "San José State"]))
})

test_that("normalize_teams flattens a list-column of logos", {
  raw <- fake_teams_raw()
  raw$logos_1 <- NULL
  raw$logos <- list("http://a.png", character(), c("http://c.png", "http://d.png"))
  teams <- normalize_teams(raw)
  expect_equal(teams$logo[teams$school == "San José State"], "http://c.png")
  expect_true(is.na(teams$logo[teams$school == "Arizona State"]))
})

test_that("normalize_games maps cfbfastR names, including home_division", {
  raw <- data.frame(
    game_id = c(401L, 402L), season = 2026L, week = c(11L, 11L), season_type = "regular",
    start_date = c("2026-11-08T03:00:00.000Z", "2026-11-08T19:00:00.000Z"),
    start_time_tbd = FALSE, completed = c(TRUE, FALSE), neutral_site = c(FALSE, TRUE),
    home_id = c(8L, 2L), home_team = c("Arizona", "Arizona State"), home_division = c("fbs", "FBS"),
    home_points = c(31L, NA), home_pregame_elo = c(1600L, 1700L),
    away_id = c(2L, 3001L), away_team = c("Arizona State", "Northern Arizona"), away_division = c("fbs", "fcs"),
    away_points = c(24L, NA), away_pregame_elo = c(1650L, NA),
    venue = "Somewhere", stringsAsFactors = FALSE
  )
  games <- normalize_games(raw)
  expect_named(games, c(
    "game_id", "season", "week", "season_type", "start_date", "completed", "neutral_site",
    "home_id", "home_team", "home_class", "home_points", "home_pregame_elo",
    "away_id", "away_team", "away_class", "away_points", "away_pregame_elo"
  ))
  expect_equal(games$home_class, c("fbs", "fbs"))
  expect_equal(games$away_class, c("fbs", "fcs"))
  expect_type(games$home_pregame_elo, "double")
  expect_equal(games$neutral_site, c(FALSE, TRUE))

  raw$home_division <- NULL
  expect_error(normalize_games(raw), "home_class.*Columns received")
})

test_that("normalize_lines makes spread numeric and keeps one row per game and book", {
  raw <- data.frame(
    game_id = c(401L, 401L, 401L, 402L),
    provider = c("DraftKings", "Bovada", "DraftKings", "ESPN Bet"),
    spread = c("-3.5", "-3", "-4", NA),
    formatted_spread = "x", stringsAsFactors = FALSE
  )
  lines <- suppressMessages(normalize_lines(raw, pulled_at = "2026-11-10T13:00:00Z"))
  expect_named(lines, c("game_id", "provider", "spread", "pulled_at"))
  expect_equal(nrow(lines), 3)
  expect_equal(lines$spread[lines$provider == "DraftKings"], -3.5)
  expect_true(all(lines$pulled_at == "2026-11-10T13:00:00Z"))

  empty <- normalize_lines(data.frame())
  expect_equal(nrow(empty), 0)
  expect_named(empty, c("game_id", "provider", "spread", "pulled_at"))
})

test_that("normalize_ratings drops the SP+ national averages row and joins by name", {
  teams <- normalize_teams(fake_teams_raw())
  raw <- data.frame(
    year = 2026L,
    team = c("Arizona", "Arizona State", "San Jose State", "nationalAverages"),
    conference = c("Big 12", "Big 12", "Mountain West", NA),
    rating = c(5.2, 12.1, -3.4, 0),
    offense_rating = 30,
    stringsAsFactors = FALSE
  )
  ratings <- normalize_ratings(raw, "sp", 2026, 12, teams, pulled_at = "2026-11-10T13:00:00Z")
  expect_named(ratings, c("season", "week", "team_id", "team", "rating", "pulled_at"))
  expect_equal(nrow(ratings), 3)
  # Accent-insensitive match: "San Jose State" finds "San José State".
  expect_equal(ratings$team_id[ratings$team == "San Jose State"], 23L)
  expect_true(all(ratings$week == 12L))
})

test_that("normalize_ratings uses each source's rating column", {
  teams <- normalize_teams(fake_teams_raw())
  fpi <- data.frame(year = 2025L, team = "Arizona", conference = "Big 12", fpi = 4.5, resume_ranks_fpi = 40L)
  out <- normalize_ratings(fpi, "fpi", 2025, NA, teams)
  expect_equal(out$rating, 4.5)
  expect_true(is.na(out$week))

  elo <- data.frame(year = 2025L, team = "Arizona State", conference = "Big 12", elo = 1712)
  expect_equal(normalize_ratings(elo, "elo", 2025, NA, teams)$rating, 1712)

  expect_error(normalize_ratings(elo, "fpi", 2025, NA, teams), "fpi ratings.*Columns received: year, team, conference, elo")
})

test_that("unmatched FBS names warn, non-FBS teams are skipped quietly", {
  teams <- normalize_teams(fake_teams_raw())
  raw <- data.frame(
    year = 2026L,
    team = c("Arizona", "Arizona St.", "Northern Arizona"),
    conference = c("Big 12", "Big 12", "Big Sky"),
    division = c("fbs", "fbs", "fcs"),
    rating = c(1, 2, 3),
    stringsAsFactors = FALSE
  )
  expect_warning(
    expect_message(out <- normalize_ratings(raw, "srs", 2026, 12, teams), "skipped 1 non-FBS"),
    "Arizona St\\."
  )
  expect_equal(out$team, "Arizona")
})

test_that("games_unfinished spots missing files and games without results", {
  dir <- withr::local_tempdir()
  path <- file.path(dir, "2026.csv")
  expect_true(games_unfinished(path))
  suppressMessages(write_snapshot(data.frame(game_id = 1:2, completed = c(TRUE, FALSE)), path))
  expect_true(games_unfinished(path))
  suppressMessages(write_snapshot(data.frame(game_id = 1:2, completed = c(TRUE, TRUE)), path, overwrite = TRUE))
  expect_false(games_unfinished(path))
})

# ---- Whole runs, with the API replaced by fake data -------------------------

#' Stand-in for cfbd_fetch(): counts calls and returns cfbfastR-shaped frames.
fake_cfbd_fetch <- function(fn, ..., allow_empty = FALSE) {
  options(spreadpredictor.api_calls = api_calls_made() + 1L)
  year <- list(...)$year
  ratings <- function(column) {
    df <- data.frame(year = year, team = c("Arizona", "Arizona State"), conference = "Big 12", x = c(4, 9))
    names(df)[names(df) == "x"] <- column
    df
  }
  switch(fn,
    cfbd_calendar = fake_calendar(),
    cfbd_teams_fbs = fake_teams_raw(),
    cfbd_game_info = data.frame(
      game_id = year * 10L + 1L, season = year, week = 1L, season_type = "regular",
      start_date = sprintf("%d-09-01T02:00:00.000Z", year), completed = TRUE, neutral_site = FALSE,
      home_id = 8L, home_team = "Arizona", home_division = "fbs", home_points = 30L, home_pregame_elo = 1500L,
      away_id = 2L, away_team = "Arizona State", away_division = "fbs", away_points = 20L, away_pregame_elo = 1520L
    ),
    cfbd_betting_lines = data.frame(game_id = year * 10L + 1L, provider = "DraftKings", spread = "-3.5"),
    cfbd_ratings_sp = rbind(ratings("rating"), data.frame(year = year, team = "nationalAverages", conference = NA, rating = 0)),
    cfbd_ratings_fpi = ratings("fpi"),
    cfbd_ratings_srs = ratings("rating"),
    cfbd_ratings_elo = ratings("elo")
  )
}

#' Swap functions in the global env (where helper-load.R sources R/) for the
#' rest of the calling test.
local_replace <- function(..., env = parent.frame()) {
  fakes <- list(...)
  originals <- mget(names(fakes), envir = globalenv())
  list2env(fakes, envir = globalenv())
  withr::defer(list2env(originals, envir = globalenv()), envir = env)
}

local_fake_api <- function(env = parent.frame()) {
  local_replace(
    cfbd_fetch = fake_cfbd_fetch,
    require_cfbd = function() invisible(TRUE),
    log_api_key_info = function(when) invisible(NULL),
    env = env
  )
}

snapshot_files <- function(root) sort(list.files(root, recursive = TRUE))

test_that("a weekly snapshot pulls each file once and refreshes games and lines", {
  local_fake_api()
  root <- withr::local_tempdir()
  tuesday <- utc("2026-11-10 13:00:00")

  ok <- suppressMessages(run_snapshot(now = tuesday, root = root))
  expect_true(all(ok))
  expect_equal(api_calls_made(), 8)  # calendar, teams, 4 ratings, games, lines
  expect_equal(snapshot_files(root), sort(c(
    "games/2026.csv", "lines/2026.csv", "teams/2026.csv",
    sprintf("ratings/%s/2026_wk12.csv", RATING_SOURCES)
  )))
  expect_equal(nrow(read_snapshot(file.path(root, "ratings/sp/2026_wk12.csv"))), 2)

  # Same week again: only the calendar, games and lines are called.
  suppressMessages(run_snapshot(now = tuesday + 3600, root = root))
  expect_equal(api_calls_made(), 3)
  expect_equal(read_snapshot(file.path(root, "ratings/sp/2026_wk12.csv"))$pulled_at[1], "2026-11-10T13:00:00Z")
  expect_equal(read_snapshot(file.path(root, "lines/2026.csv"))$pulled_at[1], "2026-11-10T14:00:00Z")
})

test_that("postseason and offseason snapshots take no ratings", {
  local_fake_api()
  root <- withr::local_tempdir()

  suppressMessages(run_snapshot(now = utc("2026-12-01 13:00:00"), root = root))
  expect_false(any(grepl("^ratings", snapshot_files(root))))
  expect_true(file.exists(file.path(root, "games/2026.csv")))

  # Offseason with a finished games file: only the calendar call.
  suppressMessages(run_snapshot(now = utc("2027-01-25 13:00:00"), root = root))
  expect_equal(api_calls_made(), 1)
})

test_that("backfill pulls past seasons in full and skips what is on disk", {
  local_fake_api()
  root <- withr::local_tempdir()
  now <- utc("2026-11-10 13:00:00")

  ok <- suppressMessages(run_backfill(seasons = 2024:2025, now = now, root = root))
  expect_true(all(ok))
  expect_equal(api_calls_made(), 2 * 7 + 3)  # past: teams, games, lines, 4 finals. current: 3.
  expect_true(file.exists(file.path(root, "ratings/elo/2025_final.csv")))
  expect_false(file.exists(file.path(root, "ratings/elo/2026_final.csv")))
  expect_true(all(is.na(read_snapshot(file.path(root, "ratings/fpi/2024_final.csv"))$week)))

  suppressMessages(run_backfill(seasons = 2024:2025, now = now, root = root))
  expect_equal(api_calls_made(), 0)
})

test_that("one failed step does not stop the others", {
  local_fake_api()
  real_fetch_ratings <- fetch_ratings
  local_replace(fetch_ratings = function(source, season) {
    if (source == "fpi") stop("FPI is down")
    real_fetch_ratings(source, season)
  })
  root <- withr::local_tempdir()
  ok <- suppressMessages(run_snapshot(now = utc("2026-11-10 13:00:00"), root = root))
  expect_false(ok[["fpi"]])
  expect_true(all(ok[names(ok) != "fpi"]))
  expect_false(file.exists(file.path(root, "ratings/fpi/2026_wk12.csv")))
  expect_true(file.exists(file.path(root, "ratings/elo/2026_wk12.csv")))
})
