# A small synthetic database with known answers, built from sql/schema.sql
# in a temp file. Fit tests check that the fit recovers FIXTURE_TRUTH.

FIXTURE_TRUTH <- list(k = 25, h = 2.5, sigma = 16)

# The current (snapshot) season and week in the fixture.
FIXTURE_SEASON <- 2026L
FIXTURE_WEEK <- 11L

# Slate games with hand-set lines, so tests can check the median.
FIXTURE_LINED_GAME <- 9100001L   # spreads -3, -4, -10: median -4
FIXTURE_UNLINED_GAME <- 9100002L # no lines

#' Run code with the project root as the working directory, like the scripts.
with_project_root <- function(code) {
  old <- setwd(project_root)
  on.exit(setwd(old))
  code
}

#' Create an empty database from sql/schema.sql.
create_schema <- function(con) {
  sql <- paste(readLines(file.path(project_root, "sql", "schema.sql")), collapse = "\n")
  sql <- gsub("--[^\n]*", "", sql)
  for (statement in strsplit(sql, ";")[[1]]) {
    if (nzchar(trimws(statement))) DBI::dbExecute(con, statement)
  }
}

#' Simulated games for one season, following the model exactly.
#'
#' The real margin is Elo margin + home field + market information + noise.
#' The closing line sees the market information and Elo does not, which
#' makes the line sharper than Elo, as it is in real life.
simulate_games <- function(season, n_games, strength, first_id, truth) {
  team_ids <- seq_along(strength)
  pairs <- t(replicate(n_games, sample(team_ids, 2)))
  pregame_elo <- function(ids) 1500 + truth$k * (strength[ids] + stats::rnorm(length(ids), 0, 1.5))
  neutral <- as.integer(stats::runif(n_games) < 0.1)
  home_elo <- pregame_elo(pairs[, 1])
  away_elo <- pregame_elo(pairs[, 2])
  elo_margin <- (home_elo - away_elo) / truth$k + truth$h * (1 - neutral)
  market_info <- stats::rnorm(n_games, 0, 10)
  noise <- stats::rnorm(n_games, 0, sqrt(truth$sigma^2 - 10^2))
  margin <- round(elo_margin + market_info + noise)

  data.frame(
    game_id = first_id + seq_len(n_games), season = season,
    week = sample(1:13, n_games, replace = TRUE), season_type = "regular",
    start_date = sprintf("%d-10-01T19:00:00Z", season), completed = 1L,
    neutral_site = neutral,
    home_id = pairs[, 1], home_team = paste("Team", pairs[, 1]), home_class = "fbs",
    home_points = pmax(margin, 0) + 10L, home_pregame_elo = home_elo,
    away_id = pairs[, 2], away_team = paste("Team", pairs[, 2]), away_class = "fbs",
    away_points = pmax(-margin, 0) + 10L, away_pregame_elo = away_elo,
    expected_line_margin = elo_margin + market_info,
    stringsAsFactors = FALSE
  )
}

#' Two or three sportsbooks per game, near the market's expected margin.
simulate_lines <- function(games, flip_lines) {
  has_line <- stats::runif(nrow(games)) < 0.85
  books <- c("Book A", "Book B", "Book C")
  rows <- lapply(which(has_line), function(i) {
    n_books <- sample(2:3, 1)
    spread <- -round((games$expected_line_margin[i] + stats::rnorm(n_books, 0, 1.5)) * 2) / 2
    if (flip_lines) spread <- -spread
    data.frame(game_id = games$game_id[i], provider = books[seq_len(n_books)],
               spread = spread, pulled_at = "2025-12-01T12:00:00Z")
  })
  do.call(rbind, rows)
}

#' Games that must never reach the fit: FBS vs FCS, and missing pregame Elo.
#' Their margins are absurd so that including them would wreck the estimates.
simulate_excluded_games <- function(season, n_teams, first_id) {
  fcs <- data.frame(
    game_id = first_id + 1:10, season = season, week = 2L, season_type = "regular",
    start_date = NA_character_, completed = 1L, neutral_site = 0L,
    home_id = 1:10, home_team = paste("Team", 1:10), home_class = "fbs",
    home_points = 90L, home_pregame_elo = 1500,
    away_id = 900L + 1:10, away_team = paste("FCS", 1:10), away_class = "fcs",
    away_points = 0L, away_pregame_elo = 1500
  )
  no_elo <- fcs
  no_elo$game_id <- first_id + 11:20
  no_elo$away_id <- 11:20
  no_elo$away_team <- paste("Team", 11:20)
  no_elo$away_class <- "fbs"
  no_elo$home_pregame_elo <- NA_real_
  rbind(fcs, no_elo)
}

#' Ratings rows for one source and snapshot.
ratings_rows <- function(source, season, week, is_final, strength, k, noise_sd, pulled_at) {
  rating <- strength + stats::rnorm(length(strength), 0, noise_sd)
  if (source == "elo") rating <- round(1500 + k * rating)
  data.frame(source = source, season = season, week = week, is_final = is_final,
             team_id = seq_along(strength), team = paste("Team", seq_along(strength)),
             rating = round(rating, 1), pulled_at = pulled_at)
}

#' The current season: weekly snapshots, a few played games, and this week's
#' slate. Elo lags a week behind the other sources, as one source can.
simulate_current_season <- function(strength, truth) {
  season <- FIXTURE_SEASON
  week <- FIXTURE_WEEK
  snapshots <- list(
    list(sources = c("sp", "fpi", "srs", "elo"), week = week - 1L, pulled_at = "2026-11-03T13:00:00Z"),
    list(sources = c("sp", "fpi", "srs"), week = week, pulled_at = "2026-11-10T13:00:00Z")
  )
  ratings <- do.call(rbind, lapply(snapshots, function(s) {
    do.call(rbind, lapply(s$sources, ratings_rows, season = season, week = s$week, is_final = 0L,
                          strength = strength, k = truth$k, noise_sd = 2, pulled_at = s$pulled_at))
  }))
  # A tie in SP+ for the rank test, and a team FPI has not rated this week.
  this_week <- ratings$season == season & ratings$week == week
  ratings$rating[this_week & ratings$source == "sp" & ratings$team_id == 2] <-
    ratings$rating[this_week & ratings$source == "sp" & ratings$team_id == 1]
  ratings <- ratings[!(this_week & ratings$source == "fpi" & ratings$team_id == 3), ]

  played <- simulate_games(season, 40, strength, 9000000L, truth)
  played$week <- week - 1L
  slate <- simulate_games(season, 8, strength, FIXTURE_LINED_GAME - 1L, truth)
  slate$week <- week
  slate$completed <- 0L
  slate$home_points <- NA_integer_
  slate$away_points <- NA_integer_
  # One game this week already played, and one against an FCS team: neither
  # belongs on the slate.
  slate$completed[7] <- 1L
  slate$away_class[8] <- "fcs"

  lines <- data.frame(game_id = FIXTURE_LINED_GAME, provider = c("Book A", "Book B", "Book C"),
                      spread = c(-3, -4, -10), pulled_at = "2026-11-10T13:00:00Z")
  other <- slate$game_id[3:6]
  lines <- rbind(lines, data.frame(game_id = other, provider = "Book A", spread = -7,
                                   pulled_at = "2026-11-10T13:00:00Z"))
  list(games = rbind(played, slate), ratings = ratings, lines = lines)
}

#' Build the fixture database and return its path.
#'
#' @param flip_lines Write every spread with the wrong sign.
#' @param snapshots Include the current season's weekly snapshots.
make_fixture_db <- function(path = tempfile(fileext = ".sqlite"), seasons = 2021:2025,
                            games_per_season = 400, n_teams = 60, flip_lines = FALSE,
                            snapshots = TRUE, seed = 42) {
  set.seed(seed)
  truth <- FIXTURE_TRUTH
  games <- list()
  lines <- list()
  ratings <- list()
  teams <- list()

  for (season in c(seasons, FIXTURE_SEASON)) {
    teams[[length(teams) + 1]] <- data.frame(
      season = season, team_id = seq_len(n_teams), school = paste("Team", seq_len(n_teams)),
      mascot = "Mascots", abbreviation = sprintf("T%02d", seq_len(n_teams)),
      conference = "Fixture", color = "#123456", alt_color = "#FFFFFF", logo = NA_character_
    )
  }

  for (season in seasons) {
    strength <- stats::rnorm(n_teams, 0, 10)
    played <- simulate_games(season, games_per_season, strength, season * 10000L, truth)
    games[[length(games) + 1]] <- played
    games[[length(games) + 1]] <- simulate_excluded_games(season, n_teams, season * 10000L + 5000L)
    lines[[length(lines) + 1]] <- simulate_lines(played, flip_lines)
    ratings[[length(ratings) + 1]] <- do.call(rbind, lapply(
      c("sp", "fpi", "srs"), ratings_rows, season = season, week = NA_integer_, is_final = 1L,
      strength = strength, k = truth$k, noise_sd = 2, pulled_at = "2026-01-20T12:00:00Z"))
  }

  current <- simulate_current_season(stats::rnorm(n_teams, 0, 10), truth)
  games[[length(games) + 1]] <- current$games
  lines[[length(lines) + 1]] <- current$lines
  if (snapshots) ratings[[length(ratings) + 1]] <- current$ratings

  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  on.exit(DBI::dbDisconnect(con))
  create_schema(con)
  table_columns <- function(table) DBI::dbListFields(con, table)
  write_rows <- function(table, rows) {
    rows <- do.call(rbind, lapply(rows, function(r) r[, intersect(names(r), table_columns(table))]))
    DBI::dbAppendTable(con, table, rows)
  }
  write_rows("teams", teams)
  write_rows("games", games)
  write_rows("lines", lines)
  write_rows("ratings", ratings)
  path
}
