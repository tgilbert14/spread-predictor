demo <- complete_app_data(demo_app_data())

# Under a non-UTF-8 locale (Rscript often runs in "C"), strings built from
# "\u00b7" come back unmarked. Mark them so comparisons do not depend on locale.
as_utf8 <- function(x) {
  Encoding(x) <- "UTF-8"
  x
}
teams <- demo$teams
id_of <- function(school) teams$team_id[teams$school == school]

# A slate with one home game and one neutral game, lines in sportsbook style.
test_slate <- data.frame(
  game_id = 1:2, start_date = NA,
  home_id = c(id_of("Ironwood"), id_of("Kofa")),
  away_id = c(id_of("Mesquite"), id_of("Bajada")),
  neutral_site = c(FALSE, TRUE),
  market_spread_home = c(-4.5, NA)
)

test_that("load_app_data uses the demo when the file is missing", {
  loaded <- load_app_data(tempfile(fileext = ".rds"))
  expect_null(loaded$error)
  expect_true(loaded$data$meta$is_demo)
})

test_that("load_app_data explains a broken file and what to run", {
  bad <- tempfile(fileext = ".rds")
  writeLines("not an rds", bad)
  loaded <- load_app_data(bad)
  expect_match(loaded$error, "could not be read")
  expect_match(as.character(data_banner(loaded$data$meta, loaded$error)), "Rscript scripts/refresh.R", fixed = TRUE)
  expect_true(loaded$data$meta$is_demo)

  saveRDS(list(meta = list(), teams = data.frame(school = "x")), bad)
  expect_match(load_app_data(bad)$error, "params")
})

test_that("load_app_data fills in a missing slate and coverage", {
  path <- tempfile(fileext = ".rds")
  x <- demo_app_data()
  x$slate <- NULL
  x$coverage <- NULL
  x$meta$is_demo <- FALSE
  saveRDS(x, path)
  loaded <- load_app_data(path)
  expect_null(loaded$error)
  expect_equal(nrow(loaded$data$slate), 0)
  expect_equal(nrow(loaded$data$coverage), 0)
})

test_that("freshness_label and short_date read naturally", {
  expect_equal(short_date("2026-11-03"), "Nov 3")
  expect_equal(as_utf8(freshness_label(list(week = 11, ratings_date = "2026-11-10"))),
               "Ratings: week 11 · Nov 10")
})

test_that("data_notes flags early season and stale ratings, but not stale demo data", {
  early <- list(week = 2, ratings_date = "2026-09-07", is_demo = FALSE)
  expect_match(data_notes(early, today = as.Date("2026-09-08")), "Early season")

  old <- list(week = 11, ratings_date = "2026-11-01", is_demo = FALSE)
  expect_equal(data_notes(old, today = as.Date("2026-11-20")), "Ratings are more than 8 days old.")
  expect_length(data_notes(modifyList(old, list(is_demo = TRUE)), today = as.Date("2026-11-20")), 0)
  expect_length(data_notes(old, today = as.Date("2026-11-05")), 0)
})

test_that("team_initials prefers the abbreviation", {
  expect_equal(team_initials("Painted Desert", "PDS"), "PDS")
  expect_equal(team_initials("Painted Desert", NA), "PD")
  expect_equal(team_initials("Cochise A&M", ""), "CAM")
})

test_that("team_options carry search fields and readable badge text", {
  opts <- team_options(teams)
  expect_length(opts, nrow(teams))
  first <- opts[[1]]
  expect_true(all(c("value", "school", "mascot", "abbreviation", "conference", "bg", "fg") %in% names(first)))
  for (o in opts) expect_gte(contrast_ratio(o$fg, o$bg), MIN_TEXT_CONTRAST)
})

test_that("team_badge falls back to initials and labels logos", {
  no_logo <- as.character(team_badge(teams[1, ]))
  expect_match(no_logo, teams$abbreviation[1])
  expect_false(grepl("<img", no_logo))

  with_logo <- teams[1, ]
  with_logo$logo <- "https://example.com/logo.png"
  html <- as.character(team_badge(with_logo))
  expect_match(html, "has-logo")
  expect_match(html, sprintf('alt="%s logo"', with_logo$school))
})

test_that("slate_matchup puts the away team first and keeps the real site", {
  expect_equal(slate_matchup(test_slate[1, ]), list(a = id_of("Mesquite"), b = id_of("Ironwood"), site = "b_home"))
  expect_equal(slate_matchup(test_slate[2, ])$site, "neutral")
})

test_that("default_matchup picks a real slate game, or the top two teams", {
  m <- default_matchup(demo)
  game <- find_slate_game(demo$slate, m$a, m$b)
  expect_false(is.null(game))
  expect_equal(m, slate_matchup(game))

  no_slate <- demo
  no_slate$slate <- demo$slate[0, ]
  m2 <- default_matchup(no_slate)
  expect_equal(m2$site, "neutral")
  expect_false(m2$a == m2$b)
})

test_that("matchup_from_query restores valid links and ignores bad values", {
  fallback <- list(a = id_of("Kofa"), b = id_of("Bajada"), site = "b_home")

  ok <- matchup_from_query("?a=ironwood&b=Cochise%20A%26M&site=a_home", teams, fallback)
  expect_equal(ok, list(a = id_of("Ironwood"), b = id_of("Cochise A&M"), site = "a_home"))

  expect_equal(matchup_from_query("", teams, fallback), fallback)
  expect_equal(matchup_from_query(NULL, teams, fallback), fallback)

  bad_site <- matchup_from_query("?a=Ironwood&b=Mesquite&site=moon", teams, fallback)
  expect_equal(bad_site$site, "neutral")

  bad_team <- matchup_from_query("?a=Nowhere&b=Ironwood", teams, fallback)
  expect_equal(bad_team$b, id_of("Ironwood"))
  expect_false(bad_team$a == bad_team$b)

  same <- matchup_from_query("?a=Kofa&b=Kofa", teams, fallback)
  expect_false(same$a == same$b)
})

test_that("market_margin_for_a respects the sportsbook sign convention", {
  game <- test_slate[1, ]  # Ironwood home, favored by 4.5
  expect_equal(market_margin_for_a(game, id_of("Ironwood")), 4.5)
  expect_equal(market_margin_for_a(game, id_of("Mesquite")), -4.5)
})

test_that("describe_market says it in words and only for the real site", {
  pred <- predict_matchup("Ironwood", "Mesquite", "a_home", teams, demo$params)
  text <- as_utf8(describe_market(pred, test_slate))
  expect_match(text, "^Market: Ironwood by 4.5 · ")

  gap <- pred$spread - 4.5
  side <- if (gap > 0) "Ironwood" else "Mesquite"
  expect_match(text, side)

  # Same game from the other side reads the same way.
  flipped <- predict_matchup("Mesquite", "Ironwood", "b_home", teams, demo$params)
  expect_match(describe_market(flipped, test_slate), "Market: Ironwood by 4.5")

  # Wrong site, no line, or not on the slate: nothing.
  expect_null(describe_market(predict_matchup("Ironwood", "Mesquite", "neutral", teams, demo$params), test_slate))
  expect_null(describe_market(predict_matchup("Kofa", "Bajada", "neutral", teams, demo$params), test_slate))
  expect_null(describe_market(predict_matchup("Kofa", "Ironwood", "neutral", teams, demo$params), test_slate))
})

test_that("market_gap_phrase handles agreement and singular points", {
  expect_equal(market_gap_phrase(0.2, "A", "B"), "we agree")
  expect_equal(market_gap_phrase(1, "A", "B"), "we're 1 point higher on A")
  expect_equal(market_gap_phrase(-2.4, "A", "B"), "we're 2.5 points higher on B")
})

test_that("ratings and weights format for tables", {
  expect_equal(as_utf8(format_rating(-3.64, "sp")), "−3.6")
  expect_equal(format_rating(1755.4, "elo"), "1755")
  expect_equal(format_rating_rank(12.4, 3, "fpi"), "12.4 (#3)")
  expect_equal(format_rating_rank(NA, 3, "fpi"), "No rating")
  expect_equal(format_weight(c(0.25, 0, NA)), c("25%", "Left out", "Left out"))
})

test_that("data_banner shows demo or error notices only when needed", {
  expect_null(data_banner(list(is_demo = FALSE)))
  expect_match(as.character(data_banner(list(is_demo = TRUE))), "made up")
  expect_match(as.character(data_banner(list(is_demo = FALSE), "Broken file")), "Broken file")
})

test_that("flag_list and simple_table build markup", {
  expect_null(flag_list(character()))
  expect_match(as.character(flag_list("Models disagree by more than 7 points.")), "Models disagree")
  html <- as.character(simple_table(data.frame(a = "x", b = "1"), c("A", "B"), numeric = c(FALSE, TRUE)))
  expect_match(html, '<th scope="col" class="num">B</th>', fixed = TRUE)
})
