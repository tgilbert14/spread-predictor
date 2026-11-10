test_that("a factor is kept only when it reliably helps in CV and in the holdout", {
  expect_identical(verdict(low = -0.08, high = -0.01, holdout_change = -0.05), "kept")
  # The interval includes zero.
  expect_identical(verdict(low = -0.08, high = 0.01, holdout_change = -0.05), "rejected")
  # The holdout disagrees.
  expect_identical(verdict(low = -0.08, high = -0.01, holdout_change = 0.02), "rejected")
  # Reliably worse is not a reason to keep a factor.
  expect_identical(verdict(low = 0.01, high = 0.08, holdout_change = 0.05), "rejected")
  expect_identical(verdict(c(-0.2, -0.2), c(-0.1, 0.1), c(-0.1, -0.1)), c("kept", "rejected"))
})

test_that("the paired bootstrap is repeatable and brackets the mean change", {
  set.seed(1)
  diff <- stats::rnorm(500, -0.1, 1)
  first <- paired_bootstrap(diff)
  expect_identical(paired_bootstrap(diff), first)
  expect_equal(first[["change"]], mean(diff))
  expect_true(first[["low"]] < first[["change"]] && first[["change"]] < first[["high"]])
})

test_that("rest days count FCS games and start fresh each season", {
  games <- data.frame(
    game_id = 1:4, season = c(2025L, 2025L, 2025L, 2026L),
    start_date = c("2025-09-01T19:00:00Z", "2025-09-06T19:00:00Z", "2025-09-20T19:00:00Z",
                   "2026-09-05T19:00:00Z"),
    home_id = c(1L, 900L, 1L, 1L), away_id = c(2L, 1L, 2L, 2L)
  )
  rest <- rest_days(games)
  # Team 1: first game, then 5 days later at an FCS team, then 14 days later.
  expect_equal(rest$home_rest, c(NA, NA, 14, NA))
  expect_equal(rest$away_rest, c(NA, 5, 19, NA))
})

test_that("factors in the model are judged by taking them out of the final models", {
  no_preseason <- house_terms_without("preseason")
  expect_false(any(PRESEASON_TERMS %in% c(no_preseason$elo, no_preseason$power)))
  expect_true(all(setdiff(ELO_TERMS, PRESEASON_TERMS) %in% no_preseason$elo))

  no_success <- house_terms_without("success_rate")
  expect_identical(no_success$elo, ELO_TERMS)
  expect_true("power_gap_points" %in% no_success$power)
  expect_false("power_gap" %in% no_success$power)
  expect_error(house_terms_without("weather"), "Unknown factor")
})
