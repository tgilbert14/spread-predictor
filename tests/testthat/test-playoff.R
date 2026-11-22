# The projected playoff field (R/playoff.R).

league <- data.frame(
  team_id = 1:20,
  school = c("Notre Dame", paste("Team", 2:20)),
  conference = c("FBS Independents", rep("SEC", 5), rep("Big Ten", 4), rep("ACC", 3), rep("Big 12", 3),
                 "Sun Belt", "Mountain West", "Mountain West", "SEC"),
  stringsAsFactors = FALSE
)
by_rank <- function(ids) data.frame(rank = seq_along(ids), team_id = ids)

test_that("conference leaders, the best small-conference team and Notre Dame get in, then the best of the rest", {
  # SEC teams hold the top five; the Big 12's best is 15th; Notre Dame is 9th.
  ranking <- by_rank(c(2:6, 7, 8, 11, 1, 9, 12, 14, 10, 13, 15, 16, 17, 18, 19, 20))
  field <- playoff_field(ranking, league)
  expect_named(field, c("seed", "team_id", "rank", "how"))
  expect_identical(nrow(field), 12L)
  expect_identical(field$seed, 1:12)
  expect_false(is.unsorted(field$rank))
  how <- stats::setNames(field$how, field$team_id)
  expect_identical(unname(how["2"]), "SEC leader")
  expect_identical(unname(how["7"]), "Big Ten leader")
  expect_identical(unname(how["11"]), "ACC leader")
  expect_identical(unname(how["14"]), "Big 12 leader")
  expect_identical(unname(how["1"]), "Notre Dame")
  # Team 17 (Sun Belt) is the best small-conference team, though 16th.
  expect_identical(unname(how["17"]), "Group of Six")
  # Champions ranked low push at-large teams out: the 11th and 12th ranked miss.
  expect_false(any(c(12L, 10L) %in% field$team_id))
  expect_identical(sum(field$how == "At-large"), 6L)
})

test_that("Notre Dame outside the top 12 gets no special place", {
  ranking <- by_rank(c(2:15, 1, 16:20))  # Notre Dame 15th
  field <- playoff_field(ranking, league)
  expect_false(1L %in% field$team_id)
  expect_false("Notre Dame" %in% field$how)
})

test_that("a team that is both a champion and high enough is counted once", {
  ranking <- by_rank(c(1, 2, 7, 11, 14, 17, 3, 4, 5, 6, 8, 9, 10, 12, 13, 15, 16, 18, 19, 20))
  field <- playoff_field(ranking, league)
  expect_false(anyDuplicated(field$team_id) > 0)
  expect_identical(nrow(field), 12L)
})

test_that("the first round pairs 5 with 12 down to 8 with 9, and the top four rest", {
  ranking <- by_rank(c(2:6, 7, 8, 11, 1, 9, 12, 14, 10, 13, 15, 16, 17, 18, 19, 20))
  field <- playoff_field(ranking, league)
  first <- first_round(field, league)
  expect_identical(first[1:4], rep("Bye to the quarterfinals", 4))
  school <- function(seed) league$school[match(field$team_id[seed], league$team_id)]
  expect_identical(first[5], paste("Hosts No. 12", school(12)))
  expect_identical(first[12], paste("At No. 5", school(5)))
  expect_identical(first[8], paste("Hosts No. 9", school(9)))
  expect_identical(first[9], paste("At No. 8", school(8)))
})

test_that("the bid rules name real conferences", {
  teams <- demo_app_data()$teams
  expect_identical(PLAYOFF$size, 12)
  expect_length(PLAYOFF$power_four, 4)
  expect_length(PLAYOFF$group_of_six, 6)
  real <- readRDS(file.path(project_root, "data", "app_data.rds"))$teams
  expect_true(all(c(PLAYOFF$power_four, PLAYOFF$group_of_six) %in% real$conference))
  expect_true(PLAYOFF$notre_dame %in% real$school)
})

test_that("the field section needs a prediction with enough teams", {
  demo <- complete_app_data(demo_app_data())
  none <- demo
  none$meta$forecast_week <- NA_integer_
  expect_null(playoff_section("t", none))
  # The made-up league has no Power Four conferences, but the section still
  # fills twelve places from the ranking.
  html <- as.character(playoff_section("t", demo))
  expect_match(html, "Projected playoff field", fixed = TRUE)
  expect_identical(lengths(regmatches(html, gregexpr("<tr", html))), 13L)
})

test_that("title games are the one same-conference game on the first December weekend", {
  games <- data.frame(
    start_date = c("2026-12-05T17:00:00.000Z",  # SEC title game
                   "2026-12-06T01:00:00.000Z",  # Big Ten, Friday night out west
                   "2026-11-28T20:00:00.000Z",  # SEC rivalry game, a week earlier
                   "2026-12-12T20:00:00.000Z",  # Mountain West, a week later
                   "2026-12-05T20:00:00.000Z"), # SEC v Big Ten, not a title game
    neutral_site = c(TRUE, TRUE, FALSE, TRUE, TRUE),
    week = c(14L, 14L, 13L, 15L, 14L),
    home_id = c(2L, 7L, 3L, 18L, 4L), away_id = c(3L, 8L, 2L, 19L, 9L),
    home_points = c(20, 10, 30, 21, 14), away_points = c(17, 24, 7, 14, 10)
  )
  champs <- conference_champions(games, league)
  expect_setequal(champs$conference, c("SEC", "Big Ten"))
  expect_identical(champs$team_id[champs$conference == "SEC"], 2L)
  expect_identical(champs$team_id[champs$conference == "Big Ten"], 8L)
  expect_identical(nrow(conference_champions(games[3, ], league)), 0L)
  # A made-up game the same weekend: the neutral-site one is the title game.
  makeup <- transform(games[1, ], neutral_site = FALSE, home_id = 4L, away_id = 5L)
  champs <- conference_champions(rbind(games[1:2, ], makeup), league)
  expect_identical(champs$team_id[champs$conference == "SEC"], 2L)
})

test_that("a real champion takes its conference's bid, even ranked low", {
  ranking <- by_rank(c(2:6, 7, 8, 11, 1, 9, 12, 14, 10, 13, 15, 16, 17, 18, 19, 20))
  champs <- data.frame(conference = "SEC", team_id = 20L, week = 14L)
  field <- playoff_field(ranking, league, champs)
  how <- stats::setNames(field$how, field$team_id)
  expect_identical(unname(how["20"]), "SEC champion")
  expect_identical(unname(how["2"]), "At-large")
  expect_identical(unname(how["7"]), "Big Ten leader")
  expect_equal(field$team_id[12], 20)
  # A champion missing from the ranking is seeded last.
  field <- playoff_field(ranking[ranking$team_id != 20, ], league, champs)
  expect_equal(field$team_id[12], 20)
  expect_true(is.na(field$rank[12]))
})
