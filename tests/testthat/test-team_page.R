# The team page, team links, toss-ups, the Group of Six race and sharing.

demo <- complete_app_data(demo_app_data())

test_that("a team's name becomes a button that opens its page", {
  team <- demo$teams[1, ]
  html <- team_link_html(team, team$school, 3L)
  expect_match(html, sprintf('data-team-id="%d"', team$team_id), fixed = TRUE)
  expect_match(html, "open team page", fixed = TRUE)
  expect_match(html, ">3</span>", fixed = TRUE)
  # No team row: the plain name, not a dead button.
  expect_false(grepl("<button", team_link_html(NULL, "Nowhere State"), fixed = TRUE))
})

test_that("the team page shows the facts, the trend and every game", {
  team <- demo$teams[1, ]
  html <- as.character(team_page(demo, team$team_id))
  for (text in c(team$school, "Record", "Who would win", "Who has earned it", "Schedule")) {
    expect_match(html, text, fixed = TRUE)
  }
  sides <- football_team_games(demo)
  games <- sum(sides$team_id == team$team_id)
  expect_identical(lengths(regmatches(html, gregexpr("game-cell", html))), games)
  expect_null(team_page(demo, -1L))
  expect_null(team_modal(demo, -1L))
  expect_s3_class(team_modal(demo, team$team_id), "shiny.tag")
})

test_that("the week line needs two points and skips gaps", {
  expect_null(week_line(1L, 5, "one point"))
  expect_null(week_line(1:3, c(NA, 2, NA), "one real point"))
  svg <- as.character(week_line(1:4, c(1, NA, 3, 2), "Trend"))
  expect_match(svg, 'aria-label="Trend"', fixed = TRUE)
  expect_identical(lengths(regmatches(svg, gregexpr("[0-9.]+,[0-9.]+", svg))), 3L)
  expect_match(as.character(week_line(1:3, c(2, 2, 2), "Flat")), "polyline", fixed = TRUE)
})

test_that("poll chips mark the weeks a team was unranked", {
  polls <- data.frame(week = c(1L, 1L, 2L), poll = "ap", rank = c(1L, 2L, 1L), team_id = c(7L, 8L, 7L))
  html <- as.character(poll_chips(polls, 8L, "ap", "AP poll"))
  expect_match(html, "is-unranked", fixed = TRUE)
  expect_match(html, "NR", fixed = TRUE)
  expect_null(poll_chips(polls, 99L, "ap", "AP poll"))
})

test_that("toss-ups are neighbors whose scores are nearly level", {
  expect_identical(tossups(c(10, 9.8, 8, 7.9, 5)), c(2L, NA, 4L, NA, NA))
  expect_identical(tossups(c(10, 9)), c(NA_integer_, NA_integer_))
  expect_identical(tossups(NULL), integer())
  expect_identical(tossups(c(3, NA, 2.9)), rep(NA_integer_, 3))
})

test_that("the committee table tags a toss-up with the team below", {
  upcoming <- upcoming_forecast(demo)
  skip_if(is.null(upcoming))
  upcoming$rows$score <- seq(50, by = -2, length.out = nrow(upcoming$rows))
  upcoming$rows$score[2] <- upcoming$rows$score[1] - 0.1
  html <- as.character(upcoming_forecast_table(upcoming, demo))
  below <- demo$teams$school[match(upcoming$rows$team_id[2], demo$teams$team_id)]
  expect_match(html, paste("Toss-up with", below), fixed = TRUE)
  expect_identical(lengths(regmatches(html, gregexpr('class="tossup"', html))), 1L)
})

test_that("the Group of Six race lists the small-conference teams in order", {
  teams <- demo$teams
  teams$conference[1:3] <- PLAYOFF$group_of_six[1:3]
  app <- demo
  app$teams <- teams
  guess <- data.frame(rank = seq_len(nrow(teams)), team_id = rev(teams$team_id),
                      score = seq(40, by = -1, length.out = nrow(teams)), prev_cfp = NA_integer_)
  html <- as.character(group_of_six_race(guess, app, demo$meta$week))
  expect_match(html, "The Group of Six race", fixed = TRUE)
  expect_match(html, "Leads", fixed = TRUE)
  expect_match(html, "back", fixed = TRUE)
  # The best-ranked of the three comes first.
  at <- vapply(teams$school[3:1], function(s) regexpr(s, html, fixed = TRUE)[1], numeric(1))
  expect_false(is.unsorted(at))
  one <- app
  one$teams$conference[2:3] <- "SEC"
  expect_null(group_of_six_race(guess, one, demo$meta$week))
})

test_that("a share button carries the sentence and the link safely", {
  html <- share_button('Kofa at "Ironwood": our line is Kofa by 3.', "?a=Kofa&b=Ironwood&site=b_home", "Share it")
  expect_match(html, "data-share=", fixed = TRUE)
  expect_match(html, "&quot;Ironwood&quot;", fixed = TRUE)
  expect_match(html, "data-query=\"?a=Kofa&amp;b=Ironwood&amp;site=b_home\"", fixed = TRUE)
  rows <- slate_rows(demo, "open")
  expect_true(all(grepl("btn-share", rows$open, fixed = TRUE)))
  expect_true(all(grepl("our line is", rows$open, fixed = TRUE)))
})
