# Basketball: ingestion helpers, the model, the app data and the page pieces.

#' A small made-up league: ratings files for two days, games, and params.
cbb_fixture <- function() {
  root <- withr::local_tempdir(.local_envir = parent.frame())
  paths <- lapply(CBB_PATHS, function(p) file.path(root, sub("^data/basketball/?", "", p)))
  paths$root <- root
  schools <- c("Alder", "Birch St.", "Cedar", "Dogwood", "Elm", "Fir")
  teams <- data.frame(team_id = 1:6, school = c("Alder", "Birch State", "Cedar", "Dogwood", "Elm", "Fir"),
                      mascot = "Trees", abbreviation = c("ALD", "BIR", "CED", "DOG", "ELM", "FIR"),
                      conference = rep(c("North", "South"), each = 3),
                      color = "#224466", alt_color = "#ffffff", logo = NA_character_, stringsAsFactors = FALSE)
  dir.create(dirname(paths$teams), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(teams, paths$teams, row.names = FALSE)
  ratings <- function(shift) {
    data.frame(team = schools, conference = "X", adj_o = c(120, 115, 110, 105, 100, 95) + shift,
               adj_d = c(95, 97, 100, 102, 105, 108), tempo = c(64, 66, 68, 70, 72, 68))
  }
  for (day in c("2026-11-18", "2026-11-19")) {
    path <- cbb_ratings_path(2027L, day, paths$ratings)
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    utils::write.csv(ratings(if (day == "2026-11-19") 1 else 0), path, row.names = FALSE)
  }
  game <- function(id, start, status, home, away, hp = NA, ap = NA, spread = NA, neutral = 0L) {
    data.frame(game_id = id, season = 2027L, season_type = "regular", start_date = start, status = status,
               neutral_site = neutral, home_id = home, home_team = teams$school[home],
               away_id = away, away_team = teams$school[away], home_points = hp, away_points = ap,
               home_elo = 1500 + 20 * (6 - home), away_elo = 1500 + 20 * (6 - away),
               home_elo_end = if (is.na(hp)) NA else 1500 + 20 * (6 - home) + 5,
               away_elo_end = if (is.na(hp)) NA else 1500 + 20 * (6 - away) - 5,
               spread = spread, stringsAsFactors = FALSE)
  }
  games <- rbind(
    game(1L, "2026-11-18T00:00:00.000Z", "final", 1L, 2L, 80L, 70L, -6.5),
    game(2L, "2026-11-19T22:00:00.000Z", "final", 3L, 4L, 60L, 66L, -2),
    game(3L, "2026-11-19T23:00:00.000Z", "final", 5L, 99L, 90L, 50L),
    game(4L, "2026-11-21T00:00:00.000Z", "scheduled", 2L, 1L, spread = 3.5),
    game(5L, "2026-11-21T02:00:00.000Z", "scheduled", 4L, 6L, neutral = 1L),
    game(6L, "2026-11-22T00:00:00.000Z", "scheduled", 6L, 99L),
    game(7L, "2026-11-30T00:00:00.000Z", "scheduled", 1L, 3L)
  )
  dir.create(paths$games, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(games, file.path(paths$games, "2027.csv"), row.names = FALSE, na = "")
  utils::write.csv(data.frame(school = "Birch State", trank = "Birch St."), paths$names, row.names = FALSE)
  params <- list(fit_date = "2026-11-01", fit_season = 2026L, trank_scale = 1, elo_k = 30, home = 3,
                 average_tempo = 68, sigma = 11, weights = list(trank = 0.9, elo = 0.1))
  jsonlite::write_json(params, paths$params, auto_unbox = TRUE)
  list(paths = paths, teams = teams, games = games, params = params)
}
now <- as.POSIXct("2026-11-20 15:00:00", tz = "UTC")

test_that("seasons are named by the year they end in, and days by US Eastern time", {
  expect_identical(cbb_season(as.POSIXct("2026-11-21", tz = "UTC")), 2027L)
  expect_identical(cbb_season(as.POSIXct("2027-03-15", tz = "UTC")), 2027L)
  expect_identical(cbb_season(as.POSIXct("2027-10-01", tz = "UTC")), 2028L)
  expect_identical(cbb_season_label(2027L), "2026-27")
  expect_identical(cbb_season_start(2027L), as.Date("2026-11-01"))
  # A 9pm Eastern tip is the next day in UTC but belongs to that evening.
  expect_identical(cbb_game_day("2026-11-22T02:00:00.000Z"), as.Date("2026-11-21"))
  expect_identical(cbb_game_day("2026-11-21T17:00:00.000Z"), as.Date("2026-11-21"))
})

test_that("long spans are pulled a month at a time", {
  chunks <- cbb_month_chunks("2026-11-01", "2026-12-15")
  expect_identical(chunks$from, as.Date(c("2026-11-01", "2026-12-01")))
  expect_identical(chunks$to, as.Date(c("2026-11-30", "2026-12-15")))
  expect_identical(nrow(cbb_month_chunks("2026-11-18", "2026-11-28")), 1L)
})

test_that("games are tidied with the median spread across books", {
  raw <- data.frame(id = 1:2, season = 2027L, seasonType = "regular",
                    startDate = c("2026-11-20T00:00:00.000Z", "2026-11-19T00:00:00.000Z"),
                    status = c("scheduled", "final"), neutralSite = c(TRUE, FALSE),
                    homeTeamId = c(10L, 11L), homeTeam = c("A", "B"), awayTeamId = c(12L, 13L),
                    awayTeam = c("C", "D"), homePoints = c(NA, 70L), awayPoints = c(NA, 60L),
                    homeTeamEloStart = c(1500, 1600), awayTeamEloStart = c(1400, 1550),
                    homeTeamEloEnd = c(NA, 1610), awayTeamEloEnd = c(NA, 1540))
  lines <- data.frame(gameId = 1:2)
  lines$lines <- list(data.frame(provider = c("X", "Y", "Z"), spread = c(-3, -4, -10)), data.frame())
  games <- cbb_tidy_games(raw, lines)
  expect_named(games, names(cbb_empty_games()))
  expect_identical(games$game_id, 2:1)  # ordered by tipoff
  expect_identical(games$spread, c(NA, -4))
  expect_identical(games$neutral_site, c(0L, 1L))
  expect_identical(nrow(cbb_tidy_games(data.frame())), 0L)
})

test_that("a re-pulled game replaces its old row and keeps the last line seen", {
  old <- cbb_empty_games()[1:2, ]
  old$game_id <- 1:2
  old$start_date <- c("2026-11-19T00:00:00.000Z", "2026-11-20T00:00:00.000Z")
  old$status <- "scheduled"
  old$spread <- c(-3, -7)
  new <- old[2, ]
  new$status <- "final"
  new$home_points <- 70L
  new$spread <- NA
  merged <- cbb_merge_games(old, new)
  expect_identical(merged$game_id, 1:2)
  expect_identical(merged$status, c("scheduled", "final"))
  expect_identical(merged$spread, c(-3, -7))
  expect_identical(cbb_merge_games(NULL, new), new)
})

test_that("T-Rank rows are read by position", {
  row <- as.list(rep(0, 45))
  row[[2]] <- "Houston"; row[[3]] <- "B12"; row[[5]] <- 124.1; row[[7]] <- 85.3; row[[45]] <- 61.9
  expect_identical(cbb_tidy_trank(list(row)),
                   data.frame(team = "Houston", conference = "B12", adj_o = 124.1, adj_d = 85.3, tempo = 61.9))
})

test_that("ratings for a day's games come from an earlier day, never the same day", {
  fixture <- cbb_fixture()
  root <- fixture$paths$ratings
  expect_identical(cbb_rating_days(2027L, root), as.Date(c("2026-11-18", "2026-11-19")))
  # A file dated the 19th already knows the 19th's results, so games on the
  # 19th use the 18th's file.
  expect_identical(attr(cbb_ratings_before(2027L, "2026-11-19", root), "day"), as.Date("2026-11-18"))
  expect_identical(attr(cbb_ratings_before(2027L, "2026-11-20", root), "day"), as.Date("2026-11-19"))
  expect_identical(attr(cbb_ratings_before(2027L, "2026-12-25", root), "day"), as.Date("2026-11-19"))
  expect_null(cbb_ratings_before(2027L, "2026-11-18", root))
  expect_null(cbb_ratings_before(2026L, "2026-11-20", root))
})

test_that("school names match across the two sources", {
  expect_identical(cbb_key(c("St. John's", "Saint Johns", "Texas A&M", "Iowa State")),
                   c("stjohns", "stjohns", "texasaandm", "iowast"))
  expect_identical(cbb_key("San José State"), cbb_key("San Jose St."))
  expect_identical(cbb_key("San Jos<U+00E9> State"), "sanjosest")

  trank <- c("Connecticut", "Iowa St.", "East Texas A&M")
  aliases <- data.frame(school = c("UConn", "East Texas A&M"), trank = c("Connecticut", "Texas A&M Commerce"))
  expect_identical(cbb_match_trank(c("UConn", "Iowa State", "Nowhere"), trank, aliases), c(1L, 2L, NA))
  # An alias T-Rank no longer uses falls back to the school's own name.
  expect_identical(cbb_match_trank("East Texas A&M", trank, aliases), 3L)
  expect_identical(cbb_match_trank("UConn", trank), NA_integer_)
})

test_that("the same efficiency gap is worth more points in a faster game", {
  slow <- cbb_trank_gap(20, 62, 10, 62, 68)
  fast <- cbb_trank_gap(20, 74, 10, 74, 68)
  expect_gt(fast, slow)
  expect_equal(cbb_trank_gap(20, 68, 10, 68, 68), 10 * 68 / 100)
  expect_equal(cbb_trank_gap(10, 70, 20, 64, 68), -cbb_trank_gap(20, 64, 10, 70, 68))
})

fixture <- cbb_fixture()
app <- cbb_build_app_data(now, fixture$paths)

test_that("the basketball app data has what the pages need", {
  expect_named(app, c("meta", "teams", "params", "slate", "results"))
  expect_identical(app$meta$season, 2027L)
  expect_identical(app$meta$season_label, "2026-27")
  expect_identical(app$meta$today, "2026-11-20")
  # Built on the 20th: the newest file from before the 21st.
  expect_identical(app$meta$ratings_date, "2026-11-19")
  expect_identical(readRDS(fixture$paths$app_data), app)
  expect_identical(cbb_load_app_data(fixture$paths$app_data), app)
  expect_null(cbb_load_app_data(file.path(fixture$paths$root, "missing.rds")))

  teams <- app$teams
  expect_equal(teams$em, c(26, 19, 11, 4, -4, -12))  # the alias found "Birch St."
  expect_identical(teams$trank_rank, 1:6)
  # Elo is what each team left its last game with.
  expect_equal(teams$elo[1:2], c(1605, 1575))
  expect_true(is.na(teams$elo[6]))
})

test_that("the slate is the next few days' unplayed games between rated teams", {
  slate <- app$slate
  expect_identical(slate$game_id, 4:5)  # game 6 is against an unrated team, game 7 is too far off
  expect_identical(slate$day, c("2026-11-20", "2026-11-20"))
  expect_identical(slate$neutral_site, c(FALSE, TRUE))
  expect_identical(slate$market_spread_home, c(3.5, NA))
  expect_identical(app$results$game_id, 1:3)
})

test_that("a prediction blends the two systems and flips with the teams", {
  pred <- cbb_predict("Alder", "Cedar", "a_home", app$teams, app$params)
  gap <- cbb_trank_gap(26, 64, 11, 68, 68)
  expect_equal(pred$models$margin[pred$models$model == "trank"], gap + 3)
  elo <- app$teams$elo
  expect_equal(pred$models$margin[pred$models$model == "elo"], (elo[1] - elo[3]) / 30 + 3)
  expect_equal(pred$spread, 0.9 * (gap + 3) + 0.1 * ((elo[1] - elo[3]) / 30 + 3))
  expect_equal(pred$win_prob_a, stats::pnorm(pred$spread / 11))
  flipped <- cbb_predict("Cedar", "Alder", "b_home", app$teams, app$params)
  expect_equal(flipped$spread, -pred$spread)
  expect_named(pred, names(predict_matchup("Ironwood", "Kofa", "neutral", demo_app_data()$teams,
                                           demo_app_data()$params)))

  # A team with no Elo yet is predicted from T-Rank alone, and says so.
  no_elo <- cbb_predict("Alder", "Fir", "neutral", app$teams, app$params)
  expect_equal(no_elo$models$weight, c(1, 0))
  expect_match(no_elo$flags, "Elo has no rating", fixed = TRUE)
  expect_error(cbb_predict("Alder", "Alder", "neutral", app$teams, app$params), "two different teams")
})

test_that("team points are centered and the ranking follows the blend", {
  points <- cbb_team_points(app$teams, app$params)
  expect_equal(points$trank, (app$teams$em - mean(app$teams$em)) * app$teams$tempo / 100)
  expect_false(anyNA(points$blend))  # Fir has no Elo and is ranked on T-Rank
  ranking <- cbb_ranking_table(app)
  expect_named(ranking, c("rank", "team_id", "record", "rating", "trank", "elo", "earned"))
  expect_identical(ranking$rank, 1:6)
  expect_identical(ranking$record[match(c(1L, 2L, 6L), ranking$team_id)], c("1-0", "0-1", ""))
  # Dogwood won on the road, Alder won at home, Elm beat an unrated team.
  expect_identical(ranking$team_id[order(ranking$earned)][1:2], c(4L, 1L))
  expect_true(is.na(ranking$earned[ranking$team_id == 6L]))
})

test_that("the fit recovers a known scale, home court and weights", {
  # Both systems see the true gap. T-Rank sees it clearly, Elo through a lot
  # of noise, so the fit should lean on T-Rank and still find home court.
  set.seed(7)
  n <- 6000
  truth <- stats::rnorm(n, 0, 10)
  rows <- data.frame(trank_gap = truth / 1.1 + stats::rnorm(n, 0, 1), elo_gap = 30 * truth + stats::rnorm(n, 0, 240),
                     home = stats::rbinom(n, 1, 0.8), average_tempo = 68, market = NA_real_)
  rows$margin <- truth + 3 * rows$home + stats::rnorm(n, 0, 4)
  rows$market[1:100] <- rows$margin[1:100]
  fit <- cbb_fit(rows, 2025L)
  expect_lt(abs(fit$home - 3), 0.4)
  expect_equal(fit$weights$trank + fit$weights$elo, 1)
  expect_gt(fit$weights$trank, 0.75)
  expect_lt(abs(fit$trank_scale - 1.1), 0.1)
  expect_lt(fit$sigma, 5)
  expect_identical(fit$n_lined, 100L)
  expect_equal(fit$market_avg_miss, 0)

  # A system that is pure noise gets no weight at all.
  rows$elo_gap <- stats::rnorm(n, 0, 150)
  expect_gt(cbb_fit(rows, 2025L)$weights$trank, 0.97)
})

test_that("fit rows use the day before's ratings and skip unrated teams", {
  rows <- cbb_fit_rows(fixture$games, 2027L, fixture$paths$ratings, cbb_aliases(fixture$paths$names))
  # Game 1 tips on the 17th Eastern, before any ratings. Game 3 has an unrated team.
  # Game 2 is on the 19th, so it uses the 18th's file.
  expect_identical(rows$game_id, 2L)
  expect_equal(rows$trank_gap, cbb_trank_gap(10, 68, 3, 70, 68))  # the 18th's file, not the 19th's
  expect_equal(rows$market, 2)
})

test_that("today's predictions are saved once, before tipoff", {
  root <- fixture$paths$predictions
  expect_true(cbb_freeze(app, now, root))
  file <- file.path(root, "2027", "20261120.csv")
  saved <- read_snapshot(file)
  expect_identical(saved$game_id, 4:5)
  expect_equal(saved$blend[1], round(cbb_predict(2L, 1L, "a_home", app$teams, app$params)$spread, 2))
  expect_identical(saved$market_spread_home, c(3.5, NA))
  expect_false(cbb_freeze(app, now, root))  # never rewritten
  # Nothing to save once every game has tipped.
  expect_false(cbb_freeze(app, now + 86400, withr::local_tempdir()))
})

test_that("the basketball Matchup opens on the featured team, then the best game", {
  expect_equal(cbb_default_matchup(app, "Fir"), slate_matchup(app$slate[2, ]))
  expect_equal(cbb_default_matchup(app, "Nowhere"), slate_matchup(app$slate[1, ]))
  empty <- app
  empty$slate <- app$slate[0, ]
  expect_equal(cbb_default_matchup(empty, "Nowhere"), list(a = 1L, b = 2L, site = "neutral"))
})

test_that("the page pieces build", {
  pred <- cbb_predict("Alder", "Cedar", "neutral", app$teams, app$params)
  expect_match(as.character(cbb_model_table(pred)), "T-Rank", fixed = TRUE)
  expect_match(as.character(model_plot(pred, pick_team_colors(pred$team_a, pred$team_b))), "Blend", fixed = TRUE)
  rows <- cbb_slate_rows(app, "2026-11-20", "open")
  expect_identical(nrow(rows), 2L)
  expect_match(rows$matchup[1], "Alder", fixed = TRUE)
  expect_named(cbb_day_choices(app$slate), "Friday, Nov 20 (2 games)")
  ranking <- cbb_ranking_table(app)
  for (by in names(RANKING_KINDS)) {
    table_rows <- cbb_ranking_rows(ranking[!is.na(ranking$earned), ], app$teams, by)
    expect_s3_class(cbb_rankings_table(table_rows, by), "datatables")
  }
  expect_match(cbb_freshness(app$meta), "2026-27 season. Ratings through Nov 19.", fixed = TRUE)
  expect_match(as.character(mod_cbb_matchup_ui("m", app)), "college basketball", fixed = TRUE)
})

test_that("building without the files says what to run", {
  empty <- lapply(CBB_PATHS, function(p) file.path(withr::local_tempdir(), basename(p)))
  expect_error(cbb_build_app_data(now, empty), "scripts/cbb_refresh.R", fixed = TRUE)
})
