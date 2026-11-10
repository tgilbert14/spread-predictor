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
}

build_fake_db <- function(root, db) {
  suppressMessages(build_db(snapshots_dir = root, db_path = db, schema_path = schema_file))
}

test_that("schema.sql splits into the expected statements", {
  statements <- schema_statements(schema_file)
  expect_length(statements, 6)
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
