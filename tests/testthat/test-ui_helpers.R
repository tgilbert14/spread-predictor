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
               "Ratings through week 11, Nov 10")
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

test_that("market_view gives the line, its win chance and our gap, only for the real site", {
  sigma <- demo$params$sigma
  pred <- predict_matchup("Ironwood", "Mesquite", "a_home", teams, demo$params)
  view <- market_view(pred, test_slate, sigma)
  expect_equal(view$margin, 4.5)
  expect_equal(view$line, "Ironwood by 4.5")
  expect_equal(view$chance, paste("Ironwood", format_prob(stats::pnorm(4.5 / sigma)), "to win"))
  side <- if (pred$spread - 4.5 > 0) "Ironwood" else "Mesquite"
  expect_match(as_utf8(view$gap), side)
  expect_match(view$gap, "^W.*\\.$")
  expect_equal(describe_market(view), "The market has Ironwood by 4.5.")

  # Same game from the other side reads the same way.
  flipped <- market_view(predict_matchup("Mesquite", "Ironwood", "b_home", teams, demo$params), test_slate, sigma)
  expect_equal(flipped$margin, -4.5)
  expect_equal(flipped$line, "Ironwood by 4.5")
  expect_match(flipped$chance, "^Ironwood ")

  # Wrong site, no line, or not on the slate: nothing.
  expect_null(market_view(predict_matchup("Ironwood", "Mesquite", "neutral", teams, demo$params), test_slate, sigma))
  expect_null(market_view(predict_matchup("Kofa", "Bajada", "neutral", teams, demo$params), test_slate, sigma))
  expect_null(market_view(predict_matchup("Kofa", "Ironwood", "neutral", teams, demo$params), test_slate, sigma))
  expect_null(describe_market(NULL))
  expect_null(market_fact(NULL))
})

test_that("a pick'em market line has no win chance", {
  pick <- test_slate
  pick$market_spread_home[1] <- 0.2
  view <- market_view(predict_matchup("Ironwood", "Mesquite", "a_home", teams, demo$params), pick, demo$params$sigma)
  expect_equal(view$line, "Pick'em")
  expect_null(view$chance)
  expect_equal(describe_market(view), "The market calls it a pick'em.")
})

test_that("market_record speaks only when the market was closer", {
  metrics <- data.frame(model = c("house", "line"), mae = c(12.6, 12.2))
  expect_match(market_record(metrics), "closer than ours, by about 0.5 points a game")
  expect_match(market_record(data.frame(model = c("house", "line"), mae = c(13.1, 12.2))), "about 1 point a game")
  expect_null(market_record(data.frame(model = c("house", "line"), mae = c(12.0, 12.2))))
  expect_null(market_record(data.frame(model = "house", mae = 12.6)))
  expect_null(market_record(NULL))
})

test_that("market_fact shows the market's number with our gap under it", {
  view <- list(margin = 4.5, line = "Ironwood by 4.5", chance = "Ironwood 61% to win",
               gap = "We're 2 points higher on Mesquite.")
  html <- as_utf8(as.character(market_fact(view, "On past games the market was closer.")))
  expect_match(html, "Market line")
  expect_match(html, "Ironwood by 4.5, Ironwood 61% to win")
  expect_match(html, "higher on Mesquite\\. On past games the market was closer\\.")
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

test_that("old app data with no scorecard or line movement loads as empty", {
  path <- tempfile(fileext = ".rds")
  x <- demo_app_data()
  x$scorecard <- NULL
  x$slate$market_at_freeze <- NULL
  x$slate$market_move <- NULL
  x$meta$is_demo <- FALSE
  saveRDS(x, path)
  loaded <- load_app_data(path)
  expect_null(loaded$error)
  expect_true(is_scorecard(loaded$data$scorecard))
  expect_identical(loaded$data$scorecard$season$games, 0L)
  expect_true(all(is.na(loaded$data$slate$market_move)))
})

test_that("line_move_note names the team the line moved toward, past the threshold only", {
  game <- data.frame(market_move = 3)
  expect_identical(line_move_note(game, "LSU", "Texas", "2026-11-10T13:02:00Z"),
                   "The line has moved 3 points toward LSU since Tuesday. That usually means news.")
  game$market_move <- -2.5
  expect_match(line_move_note(game, "LSU", "Texas", NA), "toward Texas since our prediction was saved")
  game$market_move <- 2
  expect_null(line_move_note(game, "LSU", "Texas"))
  game$market_move <- NA
  expect_null(line_move_note(game, "LSU", "Texas"))
  expect_null(line_move_note(NULL, "LSU", "Texas"))
  expect_identical(weekday_name("2026-11-13T21:00:00Z"), "Friday")
})

test_that("slate markers are words, not color alone", {
  expect_identical(slate_markers(NA, 0), "")
  expect_identical(slate_markers(1, 0), "")
  expect_match(slate_markers(-3, 0), ">Line moved 3<")
  expect_match(slate_markers(0, 1), ">1 note<")
  html <- slate_markers(4, 2)
  expect_match(html, "Line moved 4")
  expect_match(html, "2 notes")
})

test_that("game notes show their source as a safe link that opens a new tab", {
  notes <- demo_notes(demo)
  html <- as.character(game_notes(notes, "notes-title"))
  expect_match(html, "Notes for this game")
  expect_match(html, 'target="_blank" rel="noopener">Team injury report \\(demo\\)</a>, checked Nov 12')
  expect_match(html, "Availability, Ironwood|Availability, [A-Za-z]+")
  expect_match(html, "Conference office \\(demo\\), checked Nov 13")
  expect_null(game_notes(notes[0, ], "x"))

  # A link with no name shows its site; a non-web link is not made clickable.
  note <- notes[1, ]
  note$source <- NA
  expect_match(as.character(note_source(note)), ">example.com</a>")
  note$source <- "Tip"
  note$source_url <- "javascript:alert(1)"
  expect_false(grepl("<a", as.character(note_source(note))))
  note$source <- NA
  note$source_url <- NA
  expect_match(as.character(note_source(note)), "Checked Nov 12")
})

test_that("app_notes uses the demo notes in demo mode and keeps only slate games", {
  notes <- app_notes(demo)
  expect_identical(nrow(notes), 3L)
  expect_true(all(notes$game_id %in% demo$slate$game_id))

  real <- demo
  real$meta$is_demo <- FALSE
  path <- tempfile(fileext = ".csv")
  writeLines(c("season,week,game_id,team,category,note,source,source_url,checked_at",
               sprintf("2026,11,%d,,other,On the slate.,,,", demo$slate$game_id[1]),
               "2026,11,1,,other,Not on the slate.,,,"), path)
  expect_identical(app_notes(real, path)$note, "On the slate.")
})

test_that("slate rows carry markers for moved lines and notes", {
  rows <- slate_rows(demo, "open", demo_notes(demo))
  expect_identical(sum(grepl("Line moved", rows$matchup)), 2L)
  expect_identical(sum(grepl("2 notes", rows$matchup)), 1L)
  expect_identical(sum(grepl("1 note<", rows$matchup)), 1L)
})
