# Learning how the playoff committee ranks, from its own rankings (R/committee.R).

demo <- complete_app_data(demo_app_data())
teams <- demo$teams
school_id <- function(school) teams$team_id[teams$school == school]
cfp <- demo$polls[demo$polls$poll == "cfp", ]
first_week <- min(cfp$week)

test_that("inputs carry the resume, and the last ranking once there is one", {
  before_any <- committee_inputs(demo, first_week)
  expect_true(all(c("team_id", UPDATE_INPUTS, "prev_cfp") %in% names(before_any)))
  expect_true(is.na(attr(before_any, "previous")))
  expect_true(all(is.na(before_any$prev_cfp)))
  expect_true(all(before_any[c("prev_points", "was_ranked", "new_losses", "strength_gain", "held_top", "conf_champ")] == 0))

  inputs <- committee_inputs(demo, 11L)
  expect_identical(attr(inputs, "previous"), 10L)
  last <- cfp[cfp$week == 10L, ]
  expect_identical(inputs$prev_cfp, last$rank[match(inputs$team_id, last$team_id)])
  expect_equal(inputs$prev_points, ifelse(is.na(inputs$prev_cfp), 0, 26 - inputs$prev_cfp))
  now <- week_resumes(demo, 11L)
  then <- week_resumes(demo, 10L)
  at <- match(inputs$team_id, then$team_id)
  expect_equal(inputs$new_losses, now$losses - then$losses[at])
  expect_equal(inputs$strength_gain, now$record_strength - then$record_strength[at])
  top <- inputs[inputs$prev_cfp %in% 1L, ]
  expect_identical(top$held_top, as.numeric(top$new_losses == 0))
  expect_true(all(inputs$held_top[!inputs$prev_cfp %in% 1L] == 0))
  expect_null(committee_inputs(demo, min(demo$results$week)))
})

test_that("pairs put the committee's preferred team first", {
  inputs <- data.frame(team_id = 1:4, losses = c(0, 1, 2, 3), record_strength = c(3, 2, 1, 0))
  ranking <- data.frame(rank = 1:2, team_id = c(1L, 2L))
  pairs <- committee_pairs(inputs, ranking, c("losses", "record_strength"))
  # 1 over 2, 3, 4; 2 over 3, 4.
  expect_identical(nrow(pairs), 5L)
  expect_true(all(pairs[, "losses"] < 0))
  expect_true(all(pairs[, "record_strength"] > 0))
  expect_identical(nrow(committee_pairs(inputs, ranking[0, ], "losses")), 0L)
})

test_that("the fit recovers the direction of what decides the order", {
  set.seed(11)
  n <- 400
  pairs <- cbind(good = stats::rnorm(n), noise = stats::rnorm(n))
  # The preferred team usually has more of "good"; "noise" says nothing.
  keep <- stats::plogis(2 * pairs[, "good"]) > stats::runif(n)
  pairs[!keep, ] <- -pairs[!keep, ]
  weights <- fit_committee_weights(pairs)
  expect_named(weights, c("good", "noise"))
  expect_gt(weights[["good"]], 1)
  expect_lt(abs(weights[["noise"]]), 0.5)
  # Held back hard, the weights stay near where they start.
  expect_lt(max(abs(fit_committee_weights(pairs, ridge = 1e6))), 0.01)
  prior <- c(good = 0.3, noise = 0.8)
  expect_equal(fit_committee_weights(pairs, prior, ridge = 1e6), prior, tolerance = 0.01)
})

test_that("the forecast steps up as there is more to learn from", {
  # Nothing released yet: record strength alone.
  first <- committee_forecast(demo, first_week, prior = NULL)
  expect_true(all(first$method == "record"))
  resumes <- week_resumes(demo, first_week)
  expect_identical(first$team_id[1], resumes$team_id[which.max(resumes$record_strength)])

  # One ranking out, no week-to-week example yet: what that ranking rewards.
  second <- committee_forecast(demo, first_week + 1L, prior = NULL)
  expect_true(all(second$method == "resume"))

  # Two out: starting from the last ranking.
  third <- committee_forecast(demo, first_week + 2L, prior = NULL)
  expect_true(all(third$method == "update"))
  expect_identical(third$rank, seq_len(nrow(third)))
  expect_identical(nrow(committee_forecast(demo, NA_integer_)), 0L)
})

test_that("a forecast never learns from the ranking it is predicting, or later ones", {
  week <- first_week + 2L
  later <- demo
  later$polls <- rbind(demo$polls, transform(demo$polls[demo$polls$week == week, ], week = week + 1L))
  expect_identical(committee_forecast(later, week), committee_forecast(demo, week))
  learned <- learn_committee(demo, week, NULL)
  expect_identical(learned$n_resume, 2L)
  expect_identical(learned$n_update, 1L)
})

test_that("last season's weights are where a new season starts, and only then", {
  dir <- withr::local_tempdir()
  path <- file.path(dir, "learned.json")
  expect_null(committee_prior(path, 2027L))

  last_season <- demo
  last_season$meta$season <- 2026L
  learned <- write_committee_learned(last_season, path)
  saved <- jsonlite::read_json(path, simplifyVector = TRUE)
  expect_identical(saved$season, 2026L)
  expect_identical(saved$rankings_used$update, learned$n_update)

  # Next season starts from what 2026 learned.
  prior <- committee_prior(path, 2027L)
  expect_equal(prior$update, round(learned$update, 5))
  expect_equal(prior$resume, round(learned$resume, 5))
  # During 2026 itself nothing carries over: it is not its own prior.
  expect_null(committee_prior(path, 2026L))

  # With a prior, the first ranking of a season is predicted from it.
  start <- committee_forecast(demo, first_week, prior = prior)
  expect_true(all(start$method == "resume"))
})

test_that("guesses for every week are stored and used instead of being worked out again", {
  guesses <- committee_guesses(demo)
  expect_setequal(unique(guesses$week), unique(guesses$week[guesses$week %in% demo$history$week]))
  week <- first_week + 1L
  expect_identical(committee_guess(demo, week), committee_forecast(demo, week))  # nothing stored
  stored <- demo
  stored$committee_guesses <- transform(guesses, rank = rev(rank))
  expect_identical(committee_guess(stored, week)$rank, rev(guesses$rank)[guesses$week == week])
})

test_that("moves between rankings record losses and who did the beating", {
  moves <- committee_moves(demo)
  expect_named(moves, c("week", "team_id", "from", "to", "lost", "beaten_by", "beaten_by_rank", "margin"))
  expect_setequal(unique(moves$week), sort(unique(cfp$week))[-1])
  one <- moves[moves$week == 11L, ]
  played <- demo$results[demo$results$week >= 10L & demo$results$week < 11L, ]
  losers <- ifelse(played$home_points > played$away_points, played$away_id, played$home_id)
  expect_identical(one$lost, as.integer(one$team_id %in% losers))
  single <- demo
  single$polls <- demo$polls[demo$polls$week == 10L, ]
  expect_null(committee_moves(single))
})

test_that("lessons are plain sentences, each with a real example", {
  lessons <- committee_lessons(demo)
  expect_gt(length(lessons), 2)
  for (lesson in lessons) {
    expect_named(lesson, c("rule", "example"))
    expect_match(lesson$rule, "\\.$")
    expect_match(lesson$example, "week [0-9]+")
  }
  none <- demo
  none$polls <- demo$polls[0, ]
  expect_length(committee_lessons(none), 0)
  single <- demo
  single$polls <- demo$polls[demo$polls$week == 10L, ]
  expect_length(committee_lessons(single), 0)
})

test_that("the notes file holds the lessons, the weights and the record", {
  notes <- paste(committee_notes_markdown(demo, as.Date("2026-11-22")), collapse = "\n")
  expect_match(notes, "Generated file", fixed = TRUE)
  expect_match(notes, "## What it has done this season", fixed = TRUE)
  expect_match(notes, "being No. 1 last time and not losing since", fixed = TRUE)
  expect_match(notes, "biggest misses", fixed = TRUE)
})

test_that("the info button lists the lessons", {
  html <- as.character(committee_rules_popover(demo))
  expect_match(html, "How the committee ranks teams", fixed = TRUE)
  expect_match(html, committee_lessons(demo)[[1]]$rule, fixed = TRUE)
  single <- demo
  single$polls <- demo$polls[demo$polls$week == 10L, ]
  expect_match(as.character(committee_rules_popover(single)), "Nothing learned yet", fixed = TRUE)
})
