#' A synthetic season: every team plays once a week against a random opponent.
#'
#' The real margin is the strength gap plus home field plus a little noise,
#' so the Power rating has a known answer to find.
synthetic_season <- function(season, strength, weeks = 12, noise_sd = 4, first_id = season * 1000L) {
  ids <- seq_along(strength)
  games <- do.call(rbind, lapply(seq_len(weeks), function(week) {
    pairs <- matrix(sample(ids), ncol = 2)
    data.frame(season = season, week = week, home_id = pairs[, 1], away_id = pairs[, 2])
  }))
  margin <- round(strength[games$home_id] - strength[games$away_id] + POWER_RATING$home_field +
                    stats::rnorm(nrow(games), 0, noise_sd))
  games$game_id <- first_id + seq_len(nrow(games))
  games$season_type <- "regular"
  games$neutral_site <- 0L
  games$home_class <- "fbs"
  games$away_class <- "fbs"
  games$home_points <- pmax(margin, 0) + 20L
  games$away_points <- pmax(-margin, 0) + 20L
  games
}

#' Two conferences of equal size, by team id.
synthetic_conferences <- function(seasons, n_teams) {
  expand <- expand.grid(team_id = seq_len(n_teams), season = seasons)
  expand$conference <- ifelse(expand$team_id %% 2 == 0, "Even", "Odd")
  expand
}

set.seed(2026)
n_teams <- 20
strength <- stats::rnorm(n_teams, 0, 10)
games <- rbind(synthetic_season(2024, strength), synthetic_season(2025, strength))
conferences <- synthetic_conferences(2024:2025, n_teams)
rated <- power_ratings(games, conferences)

test_that("Power recovers known team strengths", {
  current <- rated$current[order(rated$current$team_id), ]
  expect_identical(current$team_id, seq_len(n_teams))
  expect_gt(stats::cor(current$power, strength), 0.97)
  # Gaps, not levels, are what matter: the fitted slope should be close to 1.
  slope <- stats::coef(stats::lm(current$power ~ strength))[[2]]
  expect_lt(abs(slope - 1), 0.15)
})

test_that("pregame ratings use only games from earlier weeks", {
  # Week 1 of the first season: nothing has been played yet, so every team
  # sits at its prior.
  first_week <- rated$pregame[games$season == 2024 & games$week == 1, ]
  expect_true(all(first_week$home_power == first_week$home_power[1]))

  # Change a week 8 score. Pregame ratings through week 8 must not move;
  # week 9 onward must.
  changed <- games
  target <- which(changed$season == 2025 & changed$week == 8)[1]
  changed$home_points[target] <- changed$home_points[target] + 40L
  after <- power_ratings(changed, conferences)$pregame

  through_week_8 <- games$season < 2025 | games$week <= 8
  expect_identical(after$home_power[through_week_8], rated$pregame$home_power[through_week_8])
  expect_identical(after$away_power[through_week_8], rated$pregame$away_power[through_week_8])
  expect_false(isTRUE(all.equal(after$home_power[!through_week_8],
                                rated$pregame$home_power[!through_week_8])))
})

test_that("current ratings use every completed game and skip unplayed ones", {
  last_week <- max(games$week[games$season == 2025])
  without_last <- games[!(games$season == 2025 & games$week == last_week), ]
  expect_false(isTRUE(all.equal(power_ratings(without_last, conferences)$current$power,
                                rated$current$power)))

  # An unplayed game next week changes nothing, and its pregame ratings are
  # the current ones.
  unplayed <- games[games$season == 2025 & games$week == last_week, ][1, ]
  unplayed$game_id <- 999999L
  unplayed$week <- last_week + 1L
  unplayed$home_points <- NA_integer_
  unplayed$away_points <- NA_integer_
  with_unplayed <- power_ratings(rbind(games, unplayed), conferences)
  expect_equal(with_unplayed$current, rated$current)
  next_game <- with_unplayed$pregame[with_unplayed$pregame$game_id == 999999L, ]
  expect_equal(next_game$home_power, rated$current$power[rated$current$team_id == unplayed$home_id])
})

test_that("the postseason is one block after the regular season", {
  expect_identical(rating_block(c(1, 14, 1, 2), c("regular", "regular", "postseason", "postseason")),
                   c(1, 14, Inf, Inf))
})

test_that("all FCS opponents are pooled into one team", {
  fcs_games <- synthetic_season(2024, strength, weeks = 1, first_id = 5000L)[1:3, ]
  fcs_games$week <- 13L
  fcs_games$away_id <- c(801L, 802L, 803L)
  fcs_games$away_class <- c("fcs", "fcs", "d2")
  fcs_games$game_id <- 5001:5003
  with_fcs <- power_ratings(rbind(games, fcs_games), conferences)
  fcs_rows <- with_fcs$pregame[with_fcs$pregame$game_id %in% 5001:5003, ]

  # Every non-FBS team has the same rating: the pooled one, from its start value.
  expect_true(all(fcs_rows$away_power == POWER_RATING$fcs_start))
  # The pool is not reported as a team.
  expect_false(any(with_fcs$current$team_id %in% c(801L, 802L, 803L, FCS_POOL_ID)))
})

test_that("a team new to the data starts below its conference average", {
  new_id <- n_teams + 1L
  new_game <- games[games$season == 2025, ][1, ]
  new_game$game_id <- 7001L
  new_game$week <- 0L
  new_game$home_id <- new_id
  conf <- rbind(conferences, data.frame(team_id = new_id, season = 2025L, conference = "Odd"))
  with_new <- power_ratings(rbind(games, new_game), conf)

  final_2024 <- power_ratings(games[games$season == 2024, ], conferences)$current
  odd_average <- mean(final_2024$power[final_2024$team_id %% 2 == 1])
  pregame <- with_new$pregame$home_power[with_new$pregame$game_id == 7001L]
  expect_equal(pregame, odd_average + POWER_RATING$new_team_offset)
})

test_that("returning teams keep their conference average plus part of their edge", {
  final_2024 <- power_ratings(games[games$season == 2024, ], conferences)$current
  conference <- ifelse(final_2024$team_id %% 2 == 0, "Even", "Odd")
  average <- stats::ave(final_2024$power, conference)
  expected <- average + POWER_RATING$carry * (final_2024$power - average)

  prior <- season_prior(final_2024$team_id, conference,
                        stats::setNames(final_2024$power, final_2024$team_id), POWER_RATING)
  expect_equal(prior, expected)
})

test_that("power_ratings says what to do with no games", {
  expect_error(power_ratings(games[0, ], conferences), "scripts/refresh.R")
})

test_that("is_power_team follows the conference list, the Pac-12 cutoff and Notre Dame", {
  expect_identical(is_power_team(c("SEC", "Big Ten", "Big 12", "ACC"), 1:4, 2026),
                   rep(TRUE, 4))
  expect_identical(is_power_team(c("Sun Belt", "Mountain West", NA), 1:3, 2026), rep(FALSE, 3))
  expect_identical(is_power_team("Pac-12", 5L, c(2022, 2023, 2024, 2026)),
                   c(TRUE, TRUE, FALSE, FALSE))
  expect_identical(is_power_team(c("FBS Independents", NA), c(87L, 87L), 2026), c(TRUE, TRUE))
  expect_identical(is_power_team("FBS Independents", 88L, 2026), FALSE)
})
