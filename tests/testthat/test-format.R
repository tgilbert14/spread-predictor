#' A minimal prediction result, enough for the format functions.
fake_pred <- function(spread, site = "neutral", win_prob_a = 0.5) {
  list(
    team_a = data.frame(school = "Alpha"),
    team_b = data.frame(school = "Beta"),
    site = site,
    spread = spread,
    win_prob_a = win_prob_a,
    interval = c(low = spread - 20, high = spread + 20)
  )
}

test_that("spreads round to the nearest half point", {
  expect_equal(round_half(c(3.2, 3.3, 3.7, -6.8)), c(3, 3.5, 3.5, -7))
  expect_identical(format_points(c(7, 6.5, -3.2)), c("7", "6.5", "3"))
})

test_that("under a quarter point is a pick'em, never a signed zero", {
  for (margin in c(0, 0.1, -0.1, 0.24, -0.24)) {
    expect_identical(format_favorite(margin, "Alpha", "Beta"), "Pick'em")
    headline <- format_headline(fake_pred(margin))
    expect_match(headline, "^Pick'em")
    expect_no_match(headline, "-0|by 0")
  }
  expect_identical(format_favorite(0.3, "Alpha", "Beta"), "Alpha by 0.5")
})

test_that("probabilities print as whole percents between 1% and 99%", {
  expect_identical(format_prob(c(0, 0.001, 0.5, 0.996, 1)), c("1%", "1%", "50%", "99%", "99%"))
})

test_that("the headline names the site", {
  expect_identical(format_headline(fake_pred(7)), "Alpha by 7 over Beta on a neutral field")
  expect_identical(format_headline(fake_pred(7, "a_home")), "Alpha by 7 over Beta at Alpha")
  expect_identical(format_headline(fake_pred(7, "b_home")), "Alpha by 7 over Beta at Beta")
})

test_that("the favorite is named correctly when B is favored", {
  pred <- fake_pred(-10.4, "a_home", win_prob_a = 0.26)
  expect_identical(format_headline(pred), "Beta by 10.5 over Alpha at Alpha")
  expect_identical(format_favorite(-3, "Alpha", "Beta"), "Beta by 3")
  expect_identical(format_interval(pred), "Beta by 30.5 to Alpha by 9.5")
  expect_identical(format_summary(pred),
                   "Beta by 10.5 over Alpha at Alpha. Win probability: Alpha 26%, Beta 74%.")
})
