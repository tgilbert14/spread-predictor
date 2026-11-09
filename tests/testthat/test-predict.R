demo <- demo_app_data()
teams <- demo$teams
params <- demo$params

#' Two teams with hand-picked ratings, so margins are easy to check.
two_teams <- function(a = c(sp = 10, fpi = 10, srs = 10, elo = 1750),
                      b = c(sp = 0, fpi = 0, srs = 0, elo = 1500)) {
  out <- data.frame(team_id = 1:2, school = c("Alpha", "Beta"))
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
  expect_equal(pred$models$weight[pred$models$model != "fpi"], rep(1 / 3, 3))
  expect_true(any(grepl("FPI has no rating", pred$flags)))
})

test_that("models disagreeing by more than 7 points raises a flag", {
  agree <- predict_matchup("Alpha", "Beta", "neutral", two_teams(), params)
  expect_length(agree$flags, 0)

  at_limit <- two_teams(a = c(sp = 17, fpi = 10, srs = 10, elo = 1750))
  expect_length(predict_matchup("Alpha", "Beta", "neutral", at_limit, params)$flags, 0)

  past_limit <- two_teams(a = c(sp = 17.5, fpi = 10, srs = 10, elo = 1750))
  flags <- predict_matchup("Alpha", "Beta", "neutral", past_limit, params)$flags
  expect_true(any(grepl("disagree", flags)))
})

test_that("the interval is symmetric around the spread", {
  pred <- predict_matchup("Ironwood", "Bajada", "a_home", teams, params)
  expect_equal(pred$interval[["high"]] - pred$spread, pred$spread - pred$interval[["low"]])
  expect_lt(pred$interval[["low"]], pred$interval[["high"]])
})
