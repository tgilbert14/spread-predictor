demo <- demo_app_data()
teams <- demo$teams
params <- demo$params

#' Two teams with hand-picked ratings, so margins are easy to check.
#' With the demo's k of 25 and power_scale of 1, every model says Alpha by 10
#' when both teams are in the same tier.
two_teams <- function(a = c(sp = 10, fpi = 10, srs = 10, elo = 1750, power = 10),
                      b = c(sp = 0, fpi = 0, srs = 0, elo = 1500, power = 0),
                      tier = c(0L, 0L), talent_z = c(0, 0), returning_z = c(0, 0)) {
  out <- data.frame(team_id = 1:2, school = c("Alpha", "Beta"), tier = tier,
                    talent_z = talent_z, returning_z = returning_z)
  for (model in names(a)) {
    out[[model]] <- c(a[[model]], b[[model]])
    out[[paste0(model, "_rank")]] <- rank(-out[[model]], ties.method = "min")
  }
  out
}

test_that("swapping teams flips the spread exactly and win probs sum to 1", {
  ab <- predict_matchup("Saguaro State", "Kofa", "neutral", teams, params)
  ba <- predict_matchup("Kofa", "Saguaro State", "neutral", teams, params)
  expect_identical(ab$spread, -ba$spread)
  expect_equal(ab$win_prob_a + ba$win_prob_a, 1)

  home <- predict_matchup("Saguaro State", "Kofa", "a_home", teams, params)
  away <- predict_matchup("Kofa", "Saguaro State", "b_home", teams, params)
  expect_equal(home$spread, -away$spread)
})

test_that("neutral spread is the midpoint of the two home sites", {
  neutral <- predict_matchup("Catalina", "Arroyo", "neutral", teams, params)$spread
  a_home <- predict_matchup("Catalina", "Arroyo", "a_home", teams, params)$spread
  b_home <- predict_matchup("Catalina", "Arroyo", "b_home", teams, params)$spread
  expect_equal(neutral, (a_home + b_home) / 2)
  expect_equal(a_home - neutral, params$h)
})

test_that("a team cannot play itself", {
  expect_error(predict_matchup("Catalina", "catalina", "neutral", teams, params),
               "two different teams")
})

test_that("an unknown team gives a clear message", {
  expect_error(predict_matchup("Nowhere U", "Catalina", "neutral", teams, params),
               "Team not found: 'Nowhere U'")
})

test_that("teams can be found by team_id or by name in any case", {
  id <- teams$team_id[teams$school == "Mogollon"]
  by_id <- predict_matchup(id, "Kofa", "neutral", teams, params)
  by_name <- predict_matchup("  mOGOLLON ", "Kofa", "neutral", teams, params)
  expect_identical(by_id$team_a$school, "Mogollon")
  expect_identical(by_id$spread, by_name$spread)
})

test_that("a missing rating drops that model and renormalizes the weights", {
  t <- two_teams()
  t$fpi[1] <- NA
  pred <- predict_matchup("Alpha", "Beta", "neutral", t, params)
  expect_equal(pred$models$weight[pred$models$model == "fpi"], 0)
  expect_equal(sum(pred$models$weight), 1)
  expect_equal(pred$models$weight[pred$models$model != "fpi"], rep(1 / 4, 4))
  expect_true(any(grepl("FPI has no rating", pred$flags)))
})

test_that("models disagreeing by more than 7 points raises a flag", {
  agree <- predict_matchup("Alpha", "Beta", "neutral", two_teams(), params)
  expect_length(agree$flags, 0)

  at_limit <- two_teams(a = c(sp = 17, fpi = 10, srs = 10, elo = 1750, power = 10))
  expect_length(predict_matchup("Alpha", "Beta", "neutral", at_limit, params)$flags, 0)

  past_limit <- two_teams(a = c(sp = 17.5, fpi = 10, srs = 10, elo = 1750, power = 10))
  flags <- predict_matchup("Alpha", "Beta", "neutral", past_limit, params)$flags
  expect_true(any(grepl("disagree", flags)))
})

test_that("the interval is symmetric around the spread", {
  pred <- predict_matchup("Ironwood", "Bajada", "a_home", teams, params)
  expect_equal(pred$interval[["high"]] - pred$spread, pred$spread - pred$interval[["low"]])
  expect_lt(pred$interval[["low"]], pred$interval[["high"]])
})

test_that("Elo adds the tier edge for a power team against a non-power team", {
  same_tier <- predict_matchup("Alpha", "Beta", "neutral", two_teams(), params)
  margin_of <- function(pred, model) pred$models$margin[pred$models$model == model]
  expect_equal(margin_of(same_tier, "elo"), 10)

  power_vs_other <- predict_matchup("Alpha", "Beta", "neutral", two_teams(tier = c(1L, 0L)), params)
  expect_equal(margin_of(power_vs_other, "elo"), 10 + params$elo_tier)
  other_vs_power <- predict_matchup("Alpha", "Beta", "neutral", two_teams(tier = c(0L, 1L)), params)
  expect_equal(margin_of(other_vs_power, "elo"), 10 - params$elo_tier)

  # Only Elo gets the correction; the other systems already see the gap.
  for (model in setdiff(names(MODEL_LABELS), "elo")) {
    expect_equal(margin_of(power_vs_other, model), margin_of(same_tier, model), label = model)
  }
})

test_that("SP+, FPI and SRS margins use their fitted scales, and 1 when there is none", {
  p <- demo$params
  base <- predict_matchup("Ironwood", "Mesquite", "neutral", teams, p)$models
  p$public_scale <- data.frame(model = c("sp", "fpi"), scale = c(0.8, 0.5), n = 500L)
  scaled <- predict_matchup("Ironwood", "Mesquite", "neutral", teams, p)$models
  ratio <- stats::setNames(scaled$margin / base$margin, scaled$model)
  expect_equal(ratio[["sp"]], 0.8)
  expect_equal(ratio[["fpi"]], 0.5)
  expect_equal(unname(ratio[c("srs", "elo", "power")]), c(1, 1, 1))

  p$public_scale <- NULL
  expect_equal(predict_matchup("Ironwood", "Mesquite", "neutral", teams, p)$models$margin, base$margin)
})

test_that("Power margin is power_scale times the rating gap, plus home field", {
  p <- params
  p$power_scale <- 0.8
  pred <- predict_matchup("Alpha", "Beta", "a_home", two_teams(), p)
  expect_equal(pred$models$margin[pred$models$model == "power"], 0.8 * 10 + p$h)
  expect_identical(pred$models$label, unname(MODEL_LABELS))
  expect_identical(nrow(pred$models), 5L)
})

test_that("preseason points are zero without a week and from week 7 on", {
  t <- two_teams(talent_z = c(1.5, -0.5), returning_z = c(0.5, 1))
  none <- predict_matchup("Alpha", "Beta", "neutral", t, params)
  for (week in c(7L, 11L)) {
    late <- predict_matchup("Alpha", "Beta", "neutral", t, params, week = week)
    expect_identical(late$models$margin, none$models$margin, label = paste("week", week))
    expect_false(any(grepl("Early season", late$flags)))
  }
  expect_equal(none$models$margin, rep(10, 5))
})

test_that("early in the season only Elo and Power get preseason points", {
  t <- two_teams(talent_z = c(1.5, -0.5), returning_z = c(0.5, 1))
  late <- predict_matchup("Alpha", "Beta", "neutral", t, params, week = 9L)
  margin_of <- function(pred, model) pred$models$margin[pred$models$model == model]
  # Alpha has more talent (gap 2) and less returning production (gap -0.5).
  week_1_points <- params$talent_points * 2 + params$returning_points * -0.5

  week_1 <- predict_matchup("Alpha", "Beta", "neutral", t, params, week = 1L)
  week_4 <- predict_matchup("Alpha", "Beta", "neutral", t, params, week = 4L)
  for (model in c("elo", "power")) {
    expect_equal(margin_of(week_1, model), margin_of(late, model) + week_1_points, label = model)
    expect_equal(margin_of(week_4, model), margin_of(late, model) + week_1_points / 2, label = model)
  }
  for (model in c("sp", "fpi", "srs")) {
    expect_identical(margin_of(week_1, model), margin_of(late, model), label = model)
  }
  expect_gt(week_1_points, 0)
  expect_gt(week_1$spread, late$spread)
  expect_true(any(grepl("Early season", week_1$flags)))

  # Swapping the teams flips the preseason points too.
  swapped <- predict_matchup("Beta", "Alpha", "neutral", t, params, week = 1L)
  expect_equal(swapped$spread, -week_1$spread)
})
