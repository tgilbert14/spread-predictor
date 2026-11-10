# End-to-end dry run of build_db() and check_db() on fake snapshot files in a
# temp folder. Nothing here touches data/.

schema_file <- file.path(project_root, "sql", "schema.sql")

#' Write a small, complete set of fake snapshots under `root`.
#' Two FBS teams and one FCS team, two seasons, one weekly and one final
#' ratings file per source.
write_fake_snapshots <- function(root) {
  teams <- data.frame(
    team_id = c(8L, 2L), school = c("Arizona", "Arizona State"),
    mascot = c("Wildcats", "Sun Devils"), abbreviation = c("ARIZ", "ASU"),
    conference = "Big 12", color = c("#003366", "#8C1D40"),
    alt_color = c("#CC0033", "#FFC627"), logo = NA_character_
  )
  games <- function(season) {
    data.frame(
      game_id = season * 10L + 1:2, season = season, week = c(1L, 13L),
      season_type = "regular", start_date = sprintf("%d-09-01T02:00:00Z", season),
      completed = TRUE, neutral_site = FALSE,
      home_id = c(8L, 2L), home_team = c("Arizona", "Arizona State"), home_class = "fbs",
      home_points = c(38L, 21L), home_pregame_elo = c(1550, 1600),
      away_id = c(3001L, 8L), away_team = c("Northern Arizona", "Arizona"),
      away_class = c("fcs", "fbs"), away_points = c(3L, 24L), away_pregame_elo = c(NA, 1580)
    )
  }
  lines <- function(season) {
    data.frame(
      game_id = season * 10L + c(2L, 2L), provider = c("DraftKings", "Bovada"),
      spread = c(-2.5, -3), pulled_at = "2026-11-10T13:00:00Z"
    )
  }
  ratings <- function(season, week) {
    data.frame(
      season = season, week = week, team_id = c(8L, 2L),
      team = c("Arizona", "Arizona State"), rating = c(3.1, 7.4),
      pulled_at = "2026-11-10T13:00:00Z"
    )
  }

  quiet_write <- function(df, path) suppressMessages(write_snapshot(df, path))
  for (season in 2025:2026) {
    quiet_write(teams, snapshot_path("teams", season, root = root))
    quiet_write(games(season), snapshot_path("games", season, root = root))
    quiet_write(lines(season), snapshot_path("lines", season, root = root))
  }
  for (source in RATING_SOURCES) {
    quiet_write(ratings(2025, NA_integer_), snapshot_path("ratings", 2025, source, root = root))
    quiet_write(ratings(2026, 12L), snapshot_path("ratings", 2026, source, week = 12, root = root))
  }
  # An empty lines file, as written early in a season, must load fine.
  quiet_write(normalize_lines(data.frame()), snapshot_path("lines", 2024, root = root))
  write_fake_extras(root, quiet_write)
}

#' Extras files as the API returns them: school names, FCS teams included.
#' Each season has one FCS talent row, one returning name that matches only
#' loosely, and one game_stats row for a game we do not track.
write_fake_extras <- function(root, quiet_write) {
  for (season in 2025:2026) {
    quiet_write(data.frame(year = season, school = c("Arizona", "Arizona State", "Northern Arizona"),
                           talent = c(650.5, 700.25, 300)),
                extra_path("talent", season, root))
    quiet_write(data.frame(season = season, team = c("Arizona", "ARIZONA STATE"), conference = "Big 12",
                           total_ppa = 100, percent_ppa = c(0.55, 0.62)),
                extra_path("returning", season, root))
    quiet_write(data.frame(game_id = season * 10L + c(1L, 1L, 2L, 2L, 9L), season = season, week = 1L,
                           team = c("Arizona", "Northern Arizona", "Arizona State", "Arizona", "Somebody"),
                           opponent = "x", off_plays = 60,
                           off_success_rate = c(0.5, 0.3, 0.45, 0.41, 0.4),
                           def_success_rate = c(0.3, 0.5, 0.41, 0.45, 0.4)),
                extra_path("advanced", season, root))
  }
}

build_fake_db <- function(root, db) {
  suppressMessages(build_db(snapshots_dir = root, db_path = db, schema_path = schema_file))
}

test_that("schema.sql splits into the expected statements", {
  statements <- schema_statements(schema_file)
  expect_length(statements, 9)
  expect_true(all(grepl("^CREATE", statements)))
})

test_that("build_db loads every snapshot and check_db passes", {
  root <- withr::local_tempdir()
  db <- file.path(withr::local_tempdir(), "cfb.sqlite")
  write_fake_snapshots(root)
  build_fake_db(root, db)

  con <- DBI::dbConnect(RSQLite::SQLite(), db)
  on.exit(DBI::dbDisconnect(con))
  count <- function(table) DBI::dbGetQuery(con, paste("SELECT COUNT(*) AS n FROM", table))$n
  expect_equal(count("teams"), 4)
  expect_equal(count("games"), 4)
  expect_equal(count("lines"), 4)
  expect_equal(count("ratings"), 16)
  expect_equal(count("talent"), 4)
  expect_equal(count("returning_production"), 4)
  expect_equal(count("game_stats"), 8)

  finals <- DBI::dbGetQuery(con, "SELECT DISTINCT is_final, week FROM ratings WHERE season = 2025")
  expect_equal(finals$is_final, 1L)
  expect_true(is.na(finals$week))
  expect_setequal(DBI::dbGetQuery(con, "SELECT DISTINCT source FROM ratings")$source, RATING_SOURCES)
  expect_equal(DBI::dbGetQuery(con, "SELECT DISTINCT completed FROM games")$completed, 1L)

  checks <- check_db(db)
  expect_true(checks$ok)
  expect_equal(nrow(checks$unjoined), 0)
  expect_equal(checks$games$n_games, c(2, 2))
  expect_equal(checks$games$n_fbs_vs_fbs, c(1, 1))
  expect_equal(nrow(checks$ratings), 8)
  expect_output(report_db_checks(checks), "Every FBS team in games joins")
})

test_that("check_db reports FBS teams that do not join", {
  root <- withr::local_tempdir()
  db <- file.path(withr::local_tempdir(), "cfb.sqlite")
  write_fake_snapshots(root)

  # Drop Arizona State from the 2026 SP+ snapshot.
  sp_path <- snapshot_path("ratings", 2026, "sp", week = 12, root = root)
  sp <- read_snapshot(sp_path)
  suppressMessages(write_snapshot(sp[sp$team != "Arizona State", ], sp_path, overwrite = TRUE))

  build_fake_db(root, db)
  checks <- check_db(db)
  expect_false(checks$ok)
  expect_equal(checks$unjoined$team, "Arizona State")
  expect_equal(checks$unjoined$missing_from, "ratings: sp")
  expect_equal(checks$unjoined$season, 2026)
})

test_that("rebuilding replaces the old database, and a failed build keeps it", {
  root <- withr::local_tempdir()
  db <- file.path(withr::local_tempdir(), "cfb.sqlite")
  write_fake_snapshots(root)
  build_fake_db(root, db)
  build_fake_db(root, db)  # a second build must not double the rows
  expect_equal(check_db(db)$games$n_games, c(2, 2))

  # Break a snapshot: a games file missing a required column.
  bad <- read_snapshot(snapshot_path("games", 2026, root = root))
  bad$home_id <- NULL
  suppressMessages(write_snapshot(bad, snapshot_path("games", 2026, root = root), overwrite = TRUE))

  expect_error(build_fake_db(root, db), "missing column\\(s\\): home_id")
  expect_true(file.exists(db))
  expect_false(file.exists(paste0(db, ".building")))
  expect_equal(check_db(db)$games$n_games, c(2, 2))
})

test_that("build_db and check_db give plain errors when files are missing", {
  dir <- withr::local_tempdir()
  expect_error(build_db(file.path(dir, "nope"), file.path(dir, "x.sqlite"), schema_file), "backfill")
  expect_error(check_db(file.path(dir, "x.sqlite")), "build_db")
})

test_that("combine_duplicate_ratings averages a team listed twice and names it", {
  ratings <- data.frame(
    team_id = c(1L, 2L, 2L, 3L, 3L),
    team = c("A", "B", "B", "C", "C"),
    rating = c(5, -20.4, -24.8, 7, 7),
    stringsAsFactors = FALSE
  )
  # B's copies disagree, so it is named. C's copies agree, so it is not.
  expect_warning(out <- combine_duplicate_ratings(ratings, "srs file"), "srs file.*average is used: B\\.")
  expect_equal(out$team_id, 1:3)
  expect_equal(out$rating, c(5, -22.6, 7))

  clean <- ratings[c(1, 2, 4), ]
  expect_silent(same <- combine_duplicate_ratings(clean, "srs file"))
  expect_equal(same, clean)
})

test_that("drop_orphan_lines removes lines for games we do not track", {
  con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  withr::defer(DBI::dbDisconnect(con))
  DBI::dbWriteTable(con, "games", data.frame(game_id = 1:2))
  DBI::dbWriteTable(con, "lines", data.frame(game_id = c(1L, 2L, 99L), spread = c(-3, 7, 1)))
  expect_message(dropped <- drop_orphan_lines(con), "Dropped 1 line")
  expect_equal(dropped, 1)
  expect_equal(DBI::dbGetQuery(con, "SELECT game_id FROM lines ORDER BY game_id")$game_id, 1:2)
})

test_that("apply_neutral_overrides fixes only the listed games", {
  con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  withr::defer(DBI::dbDisconnect(con))
  DBI::dbWriteTable(con, "games", data.frame(game_id = 1:3, neutral_site = c(1L, 0L, 1L)))
  path <- withr::local_tempfile(fileext = ".csv")
  write.csv(data.frame(game_id = c(1, 2), neutral_site = c(0, 1), reason = "test"), path, row.names = FALSE)

  expect_message(changed <- apply_neutral_overrides(con, path), "Corrected the neutral-site flag on 2")
  expect_equal(changed, 2)
  expect_equal(DBI::dbGetQuery(con, "SELECT neutral_site FROM games ORDER BY game_id")$neutral_site, c(0L, 1L, 1L))

  # No file means nothing to do, not an error.
  expect_equal(apply_neutral_overrides(con, file.path(tempdir(), "missing.csv")), 0L)
})

test_that("extras rows get team ids by name, and unmatched rows are dropped with one message each", {
  root <- withr::local_tempdir()
  db <- file.path(withr::local_tempdir(), "cfb.sqlite")
  write_fake_snapshots(root)
  messages <- testthat::capture_messages(build_db(snapshots_dir = root, db_path = db, schema_path = schema_file))
  expect_true(any(grepl("talent: dropped 2 row", messages)))
  expect_true(any(grepl("game_stats: dropped 2 row", messages)))
  expect_false(any(grepl("returning_production: dropped", messages)))

  con <- DBI::dbConnect(RSQLite::SQLite(), db)
  on.exit(DBI::dbDisconnect(con))
  talent <- DBI::dbGetQuery(con, "SELECT team_id, talent FROM talent WHERE season = 2026 ORDER BY team_id")
  expect_equal(talent$team_id, c(2L, 8L))
  expect_equal(talent$talent, c(700.25, 650.5))
  # "ARIZONA STATE" matches Arizona State only through team_key().
  returning <- DBI::dbGetQuery(con, "SELECT team_id, percent_ppa FROM returning_production WHERE season = 2026 ORDER BY team_id")
  expect_equal(returning$percent_ppa, c(0.62, 0.55))
  stats <- DBI::dbGetQuery(con, "SELECT game_id, team_id, off_success_rate FROM game_stats WHERE game_id = 20262 ORDER BY team_id")
  expect_equal(stats$team_id, c(2L, 8L))
  expect_equal(stats$off_success_rate, c(0.45, 0.41))
  # The FCS team in a game we track keeps its row, under its own id.
  expect_equal(DBI::dbGetQuery(con, "SELECT team_id FROM game_stats WHERE game_id = 20261 AND off_success_rate = 0.3")$team_id, 3001L)
})

test_that("school_ids and game_team_ids match exactly first, then loosely", {
  teams <- data.frame(season = c(2025L, 2026L, 2026L), team_id = c(8L, 8L, 23L),
                      school = c("Arizona", "Arizona", "San Jos\u00e9 State"))
  expect_equal(school_ids(c("Arizona", "San Jose State", "Arizona", "Idaho"), c(2026, 2026, 2024, 2026), teams),
               c(8L, 23L, NA, NA))

  games <- data.frame(game_id = 1L, home_id = 23L, home_team = "San Jos\u00e9 State",
                      away_id = 8L, away_team = "Arizona")
  expect_equal(game_team_ids(c(1L, 1L, 1L, 2L), c("San Jose State", "Arizona", "Idaho", "Arizona"), games),
               c(23L, 8L, NA, NA))
})
