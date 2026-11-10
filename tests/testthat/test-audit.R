# Tests for R/audit.R. Each test builds a tiny clean database from
# sql/schema.sql, plants one problem, and checks that the matching audit
# check catches it. A clean database must pass every check.

audit_root <- if (exists("project_root")) project_root else normalizePath(file.path("..", ".."))
if (!exists("audit_db")) source(file.path(audit_root, "R", "audit.R"))
audit_sql <- file.path(audit_root, "sql", "audit")

TEAM_IDS <- c(10L, 20L, 30L, 40L)

#' A small, clean database: one season, four FBS teams, six weeks of
#' completed games with two sportsbooks each, and two weekly rating snapshots.
clean_audit_db <- function() {
  con <- DBI::dbConnect(RSQLite::SQLite(), tempfile(fileext = ".sqlite"))
  schema <- sub("--.*$", "", readLines(file.path(audit_root, "sql", "schema.sql"), warn = FALSE))
  for (statement in strsplit(paste(schema, collapse = "\n"), ";", fixed = TRUE)[[1]]) {
    if (nzchar(trimws(statement))) DBI::dbExecute(con, statement)
  }

  DBI::dbAppendTable(con, "teams", data.frame(
    season = 2026L, team_id = TEAM_IDS, school = c("Alpha", "Bravo", "Charlie", "Delta"),
    mascot = "Mascots", abbreviation = c("ALP", "BRA", "CHA", "DEL"), conference = "Test Conference",
    color = "#BA0C2F", alt_color = "#FFFFFF", logo = "https://example.com/logo.png"
  ))

  # Each week, two games with no team twice; the pairings rotate.
  pairings <- list(c(10, 20, 30, 40), c(10, 30, 20, 40), c(10, 40, 20, 30))
  margins <- c(14, -7, 21, 3, -10, 28, 6, -17, 10, -3, 24, -14)
  games <- do.call(rbind, lapply(1:6, function(week) {
    p <- pairings[[(week - 1) %% 3 + 1]]
    if (week > 3) p <- p[c(2, 1, 4, 3)]  # swap home and away in the second half
    data.frame(home_id = as.integer(p[c(1, 3)]), away_id = as.integer(p[c(2, 4)]), week = week)
  }))
  n <- nrow(games)
  games <- data.frame(
    game_id = 1000L + seq_len(n), season = 2026L, week = as.integer(games$week),
    season_type = "regular",
    start_date = sprintf("2026-%s-%sT19:00:00.000Z", ifelse(games$week <= 3, "09", "10"),
                         sprintf("%02d", 5 + (games$week - 1) %% 3 * 7)),
    completed = 1L, neutral_site = 0L,
    home_id = games$home_id, home_team = "Home", home_class = "fbs",
    home_points = 30L + pmax(margins, 0L), home_pregame_elo = 1500,
    away_id = games$away_id, away_team = "Away", away_class = "fbs",
    away_points = 30L + pmax(-margins, 0L), away_pregame_elo = 1450
  )
  DBI::dbAppendTable(con, "games", games)

  # Books close near the real margin, so the sign check passes.
  DBI::dbAppendTable(con, "lines", rbind(
    data.frame(game_id = games$game_id, provider = "Book A", spread = -margins + 2, pulled_at = "2026-11-01T00:00:00Z"),
    data.frame(game_id = games$game_id, provider = "Book B", spread = -margins + 1, pulled_at = "2026-11-01T00:00:00Z")
  ))

  ratings <- expand.grid(source = c("sp", "fpi", "srs", "elo"), week = 1:2, team_id = TEAM_IDS,
                         stringsAsFactors = FALSE)
  base <- c(10, 20, 30, 40)[match(ratings$team_id, TEAM_IDS)] - 25
  ratings$rating <- ifelse(ratings$source == "elo", 1500 + base * 10, base) + ratings$week
  ratings$season <- 2026L
  ratings$is_final <- 0L
  ratings$team <- "Team"
  ratings$pulled_at <- "2026-10-01T00:00:00Z"
  DBI::dbAppendTable(con, "ratings", ratings[c("source", "season", "week", "is_final", "team_id", "team", "rating", "pulled_at")])
  con
}

#' Recreate a table without its keys, so a test can plant a duplicate the
#' schema would otherwise refuse.
drop_constraints <- function(con, table) {
  DBI::dbExecute(con, sprintf("CREATE TABLE loose AS SELECT * FROM %s", table))
  DBI::dbExecute(con, sprintf("DROP TABLE %s", table))
  DBI::dbExecute(con, sprintf("ALTER TABLE loose RENAME TO %s", table))
}

#' Run one check by name on a connection.
run_check <- function(con, name) {
  checks <- audit_checks()
  check <- checks[[match(name, vapply(checks, `[[`, "", "name"))]]
  check$run(con, audit_sql)
}

#' Plant a problem in a clean database and return the rows a check flags.
flagged_after <- function(name, ...) {
  con <- clean_audit_db()
  on.exit(DBI::dbDisconnect(con))
  for (statement in list(...)) {
    if (is.function(statement)) statement(con) else DBI::dbExecute(con, statement)
  }
  run_check(con, name)
}


test_that("a clean database passes every check", {
  con <- clean_audit_db()
  on.exit(DBI::dbDisconnect(con))
  summary <- audit_db(con, sql_dir = audit_sql)

  checked <- summary[summary$severity != "info", ]
  expect_equal(checked$check[checked$result != "pass"], character(0))
  expect_false(audit_has_errors(summary))
  # Info checks always return a table to read, and never fail to run.
  info <- summary[summary$severity == "info", ]
  expect_true(all(info$result == "info"))
})

test_that("every check has a name, a description and a known severity", {
  checks <- audit_checks()
  names <- vapply(checks, `[[`, "", "name")
  expect_false(any(duplicated(names)))
  expect_true(all(vapply(checks, function(c) c$severity %in% AUDIT_SEVERITIES, TRUE)))
  expect_true(all(nzchar(vapply(checks, `[[`, "", "looks_for"))))
})

test_that("games checks catch a planted problem", {
  expect_gt(nrow(flagged_after("games_duplicate_id",
    function(con) drop_constraints(con, "games"),
    "INSERT INTO games SELECT * FROM games WHERE game_id = 1001")), 0)
  expect_gt(nrow(flagged_after("games_same_matchup_same_date",
    "INSERT INTO games (game_id, season, week, season_type, start_date, completed, neutral_site,
       home_id, home_team, home_class, away_id, away_team, away_class)
     SELECT 2001, season, week, season_type, start_date, 0, 0, away_id, away_team, away_class,
            home_id, home_team, home_class
     FROM games WHERE game_id = 1001")), 0)
  expect_gt(nrow(flagged_after("games_completed_no_score",
    "UPDATE games SET home_points = NULL WHERE game_id = 1001")), 0)
  expect_gt(nrow(flagged_after("games_score_not_completed",
    "UPDATE games SET completed = 0 WHERE game_id = 1001")), 0)
  expect_gt(nrow(flagged_after("games_bad_score",
    "UPDATE games SET home_points = 150 WHERE game_id = 1001")), 0)
  expect_gt(nrow(flagged_after("games_completed_in_future",
    "UPDATE games SET start_date = '2030-01-01T00:00:00.000Z' WHERE game_id = 1001")), 0)
  expect_gt(nrow(flagged_after("games_team_plays_itself",
    "UPDATE games SET away_id = home_id WHERE game_id = 1001")), 0)
  expect_gt(nrow(flagged_after("games_fbs_team_not_in_teams",
    "UPDATE games SET home_id = 99 WHERE game_id = 1001")), 0)
  expect_gt(nrow(flagged_after("games_class_vs_teams",
    "UPDATE games SET away_class = 'fcs' WHERE game_id = 1001")), 0)
  expect_gt(nrow(flagged_after("games_unexpected_class",
    "UPDATE games SET home_class = 'FBS' WHERE game_id = 1001")), 0)
  expect_gt(nrow(flagged_after("games_missing_elo",
    "UPDATE games SET home_pregame_elo = NULL WHERE game_id = 1001")), 0)
  expect_gt(nrow(flagged_after("games_elo_out_of_range",
    "UPDATE games SET away_pregame_elo = 3000 WHERE game_id = 1001")), 0)
  expect_gt(nrow(flagged_after("games_team_twice_same_day",
    "INSERT INTO games (game_id, season, week, season_type, start_date, completed, neutral_site,
       home_id, home_team, home_class, away_id, away_team, away_class)
     SELECT 2002, season, week, season_type, start_date, 0, 0, home_id, home_team, home_class,
            77, 'Some FCS team', 'fcs'
     FROM games WHERE game_id = 1001")), 0)
  # A finished season (2025, before the newest) where team 10 played no games.
  expect_gt(nrow(flagged_after("games_per_team_season",
    "INSERT INTO teams (season, team_id, school) VALUES (2025, 10, 'Alpha')",
    "INSERT INTO games (game_id, season, week, season_type, start_date, completed, neutral_site,
       home_id, home_team, home_class, away_id, away_team, away_class, home_points, away_points)
     VALUES (2003, 2025, 1, 'regular', '2025-09-01T19:00:00.000Z', 1, 0, 88, 'X', 'fcs', 89, 'Y', 'fcs', 7, 3)")), 0)
  expect_gt(nrow(flagged_after("games_bad_week",
    "UPDATE games SET week = 20 WHERE game_id = 1001")), 0)
  expect_gt(nrow(flagged_after("games_bad_start_date",
    "UPDATE games SET start_date = 'next Saturday' WHERE game_id = 1001")), 0)
})

test_that("lines checks catch a planted problem", {
  expect_gt(nrow(flagged_after("lines_orphan_game",
    "INSERT INTO lines VALUES (999, 'Book A', -3, '2026-11-01T00:00:00Z')")), 0)
  expect_gt(nrow(flagged_after("lines_null_spread",
    "UPDATE lines SET spread = NULL WHERE game_id = 1001 AND provider = 'Book A'")), 0)
  expect_gt(nrow(flagged_after("lines_absurd_spread",
    "UPDATE lines SET spread = 80 WHERE game_id = 1001 AND provider = 'Book A'")), 0)
  expect_gt(nrow(flagged_after("lines_provider_disagreement",
    "UPDATE lines SET spread = spread + 10 WHERE game_id = 1001 AND provider = 'Book A'")), 0)
  expect_gt(nrow(flagged_after("lines_flipped_sign",
    "DELETE FROM lines WHERE game_id = 1001",
    "INSERT INTO lines VALUES (1001, 'Book A', -7, NULL), (1001, 'Book B', -7.5, NULL), (1001, 'Book C', 7, NULL)")), 0)
  expect_gt(nrow(flagged_after("lines_missing_for_fbs_games",
    "DELETE FROM lines WHERE game_id = 1001")), 0)
  expect_gt(nrow(flagged_after("lines_sign",
    "UPDATE lines SET spread = -spread")), 0)
  expect_gt(nrow(flagged_after("lines_worst_misses",
    "UPDATE games SET home_points = 90, away_points = 0 WHERE game_id = 1001",
    "UPDATE lines SET spread = 3 WHERE game_id = 1001")), 0)
  expect_equal(nrow(flagged_after("lines_providers_per_game")), 1)

  accuracy <- flagged_after("lines_provider_accuracy")
  expect_setequal(accuracy$provider, c("Book A", "Book B"))
  expect_equal(accuracy$mae[accuracy$provider == "Book A"], 2)
})

test_that("ratings checks catch a planted problem", {
  expect_gt(nrow(flagged_after("ratings_duplicate",
    "INSERT INTO ratings SELECT * FROM ratings WHERE source = 'srs' AND week = 1 AND team_id = 10")), 0)
  expect_gt(nrow(flagged_after("ratings_team_not_in_teams",
    "INSERT INTO ratings VALUES ('sp', 2026, 1, 0, 99, 'Nobody', 1.5, NULL)")), 0)
  expect_gt(nrow(flagged_after("ratings_fbs_team_unrated",
    "DELETE FROM ratings WHERE source = 'sp' AND week = 1 AND team_id = 10")), 0)
  expect_gt(nrow(flagged_after("ratings_out_of_range",
    "UPDATE ratings SET rating = 5000 WHERE source = 'elo' AND week = 1 AND team_id = 10")), 0)
  expect_gt(nrow(flagged_after("ratings_constant_or_missing",
    "UPDATE ratings SET rating = 1 WHERE source = 'fpi' AND week = 2")), 0)
  expect_gt(nrow(flagged_after("ratings_week_over_week",
    "UPDATE ratings SET rating = rating + 20 WHERE source = 'sp' AND week = 2 AND team_id = 10")), 0)

  counts <- flagged_after("ratings_rows_by_snapshot")
  expect_equal(nrow(counts), 8)  # four sources, two weeks
  expect_true(all(counts$n_rows == counts$n_fbs_teams))
})

test_that("week-over-week stays quiet with a single weekly snapshot", {
  expect_equal(nrow(flagged_after("ratings_week_over_week", "DELETE FROM ratings WHERE week = 2")), 0)
})

test_that("teams checks catch a planted problem", {
  expect_gt(nrow(flagged_after("teams_duplicate",
    function(con) drop_constraints(con, "teams"),
    "INSERT INTO teams SELECT * FROM teams WHERE team_id = 10")), 0)
  expect_gt(nrow(flagged_after("teams_missing_school",
    "UPDATE teams SET school = '' WHERE team_id = 10")), 0)
  expect_gt(nrow(flagged_after("teams_bad_color",
    "UPDATE teams SET color = 'red' WHERE team_id = 10")), 0)
  expect_gt(nrow(flagged_after("teams_missing_logo",
    "UPDATE teams SET logo = NULL WHERE team_id = 10")), 0)
  expect_gt(nrow(flagged_after("teams_conference_change",
    "INSERT INTO teams (season, team_id, school, conference) VALUES (2025, 10, 'Alpha', 'Old Conference')")), 0)
  expect_gt(nrow(flagged_after("teams_name_change",
    "INSERT INTO teams (season, team_id, school, conference) VALUES (2025, 10, 'Old Alpha', 'Test Conference')")), 0)
})

test_that("an error check that flags rows makes the audit fail, and the report says so", {
  con <- clean_audit_db()
  on.exit(DBI::dbDisconnect(con))
  DBI::dbExecute(con, "UPDATE games SET home_points = 150 WHERE game_id = 1001")
  summary <- audit_db(con, sql_dir = audit_sql)
  expect_true(audit_has_errors(summary))

  report <- audit_markdown(summary, audit_table_counts(con), date = as.Date("2026-11-09"))
  expect_match(report[1], "Generated file: written by scripts/audit.R on 2026-11-09")
  expect_true(any(grepl("### games_bad_score (error)", report, fixed = TRUE)))
  expect_false(any(grepl("\u2014", report)))  # no em dashes
})

test_that("a check that cannot run is reported, not fatal", {
  con <- clean_audit_db()
  on.exit(DBI::dbDisconnect(con))
  DBI::dbExecute(con, "DROP TABLE lines")
  summary <- audit_db(con, sql_dir = audit_sql)
  expect_equal(summary$result[summary$check == "lines_absurd_spread"], "flagged")
  expect_match(summary$rows[[match("lines_absurd_spread", summary$check)]]$problem, "could not run")
})
