demo <- complete_app_data(demo_app_data())
teams <- demo$teams
this_week <- demo$meta$week
id_of <- function(school) teams$team_id[teams$school == school]

test_that("the gap between two teams' blends is our neutral-site spread", {
  for (week in list(NULL, 2L, this_week)) {
    points <- team_points(teams, demo$params, week)
    pred <- predict_matchup("Ironwood", "Kofa", "neutral", teams, demo$params, week = week)
    gap <- points$blend[points$team_id == id_of("Ironwood")] - points$blend[points$team_id == id_of("Kofa")]
    expect_equal(gap, pred$spread)
  }
})

test_that("team_points centers every system and blends what a team has", {
  points <- team_points(teams, demo$params)
  expect_named(points, c("team_id", names(MODEL_LABELS), "blend"))
  for (model in names(MODEL_LABELS)) expect_equal(mean(points[[model]]), 0)

  # A team one system skipped is blended from the other four.
  gap <- teams
  gap$sp[1] <- NA
  partial <- team_points(gap, demo$params)
  expect_true(is.na(partial$sp[1]))
  expect_equal(partial$blend[1], mean(unlist(partial[1, c("fpi", "srs", "elo", "power")])))
  # A team no system rated has no blend, and so no place in the ranking.
  gap[1, names(MODEL_LABELS)] <- NA
  expect_true(is.na(team_points(gap, demo$params)$blend[1]))
})

test_that("records_before counts only earlier weeks", {
  results <- data.frame(week = c(1L, 2L, 3L), home_id = c(1L, 2L, 1L), away_id = c(2L, 3L, 3L),
                        home_points = c(20L, 10L, 30L), away_points = c(10L, 24L, 7L))
  expect_identical(records_before(results, 3L, 1:4), c("1-0", "0-2", "1-0", ""))
  expect_identical(records_before(results, 1L, 1:2), c("", ""))
})

ranking <- ranking_table(demo)

test_that("ranking_table ranks every team by the blend, best first", {
  expect_named(ranking, c("rank", "change", "team_id", "record", "rating",
                          names(MODEL_LABELS), "earned", "earned_change", "committee_style",
                          names(POLL_NAMES)))
  expect_identical(nrow(ranking), nrow(teams))
  expect_identical(ranking$rank, seq_len(nrow(teams)))
  expect_false(is.unsorted(rev(ranking$rating)))
  points <- team_points(teams, demo$params, this_week)
  expect_equal(ranking$rating, points$blend[match(ranking$team_id, points$team_id)])
  expect_identical(ranking$sp, teams$sp_rank[match(ranking$team_id, teams$team_id)])
})

test_that("places moved compare with the week before, and add up to nothing", {
  before <- ranking_table(demo, this_week - 1L)
  then <- before$rank[match(ranking$team_id, before$team_id)]
  expect_identical(ranking$change, then - ranking$rank)
  expect_identical(sum(ranking$change), 0L)
})

test_that("places moved are blank when the two weeks blend different systems", {
  # Week 8 is the demo's first with all five systems; week 7 has two.
  expect_true(all(is.na(ranking_table(demo, 8L)$change)))
  expect_false(anyNA(ranking_table(demo, 9L)$change))
  expect_false(anyNA(ranking_table(demo, 5L)$change))
  expect_true(all(is.na(ranking_table(demo, 1L)$change)))
})

test_that("poll ranks show for the week they were released, and only then", {
  released <- demo$polls[demo$polls$week == this_week & demo$polls$poll == "cfp", ]
  expect_identical(ranking$cfp[match(released$team_id, ranking$team_id)], released$rank)
  expect_identical(sum(!is.na(ranking$cfp)), nrow(released))
  expect_true(all(is.na(ranking_table(demo, 5L)$cfp)))
})

test_that("committee_similarity scores each ranking by places off, closest first", {
  toy <- data.frame(rank = 1:4, cfp = c(2L, 1L, 3L, NA), ap = c(2L, 1L, NA, 3L),
                    committee_style = c(2L, 1L, 4L, 3L), earned = c(1L, 2L, 3L, 4L))
  for (model in names(MODEL_LABELS)) toy[[model]] <- 1:4
  toy$sp <- c(2L, 1L, 3L, 4L)
  similarity <- committee_similarity(toy)
  expect_named(similarity, c("id", "label", "avg_gap", "n"))
  score <- function(id) similarity$avg_gap[similarity$id == id]
  expect_equal(score("sp"), 0)
  expect_equal(score("blend"), 2 / 3)
  expect_equal(score("committee_style"), 1 / 3)
  # The AP left the committee's third team out, so it counts as one past its last: 4th.
  expect_equal(score("ap"), 1 / 3)
  expect_identical(similarity$id[1], "sp")
  expect_false(is.unsorted(similarity$avg_gap))

  toy$cfp <- NA
  expect_identical(nrow(committee_similarity(toy)), 0L)
})

test_that("load_polls keeps the committee and the AP, matched to team ids", {
  root <- tempfile()
  dir.create(file.path(root, "extras", "rankings"), recursive = TRUE)
  raw <- data.frame(
    season = 2026L, season_type = c("regular", "regular", "regular", "regular", "postseason"),
    week = c(11L, 11L, 11L, 11L, 1L),
    poll = c("Playoff Committee Rankings", "AP Top 25", "Coaches Poll", "AP Top 25", "AP Top 25"),
    rank = c(1L, 2L, 1L, 3L, 1L),
    school = c("Kofa", "cochise a&m", "Kofa", "Not A School", "Kofa")
  )
  utils::write.csv(raw, file.path(root, "extras", "rankings", "2026.csv"), row.names = FALSE)
  polls <- load_polls(root, 2026L, teams)
  expect_named(polls, c("week", "poll", "rank", "team_id"))
  expect_identical(polls$poll, c("ap", "cfp"))
  expect_identical(polls$team_id, c(id_of("Cochise A&M"), id_of("Kofa")))
  expect_identical(polls$rank, c(2L, 1L))

  expect_identical(nrow(load_polls(root, 2025L, teams)), 0L)
  expect_named(load_polls(root, 2025L, teams), names(polls))
})

test_that("the demo has made-up polls and old app data loads without any", {
  expect_setequal(unique(demo$polls$poll), names(POLL_NAMES))
  expect_true(all(demo$polls$team_id %in% teams$team_id))
  expect_false(anyDuplicated(demo$polls[c("week", "poll", "rank")]) > 0)

  old <- demo_app_data()
  old$polls <- NULL
  filled <- complete_app_data(old)
  expect_identical(nrow(filled$polls), 0L)
  expect_true(all(is.na(ranking_table(filled)$cfp)))
})

test_that("table rows carry a sort key for every sortable column", {
  rows <- ranking_rows(utils::head(ranking, 5), teams)
  expect_identical(nrow(rows), 5L)
  expect_identical(ncol(rows), length(rankings_headers()) + length(RANKINGS_SORTED))
  expect_identical(rows$rank_key, 1:5)
  expect_match(rows$team[1], "rank-conference", fixed = TRUE)
  expect_match(rows$rating[1], "^[+-][0-9]+\\.[0-9]$")
  # Unranked sorts last.
  unranked <- utils::head(ranking, 2)
  unranked$cfp <- c(NA, 4L)
  expect_identical(ranking_rows(unranked, teams)$cfp_key, c(UNRANKED_KEY, 4))
  expect_s3_class(rankings_table(rows), "datatables")
})

test_that("moves, gaps and the closest line read in plain words", {
  moves <- format_move(c(3L, -2L, 0L, NA))
  expect_match(moves[1], 'aria-label="up 3"', fixed = TRUE)
  expect_match(moves[2], 'aria-label="down 2"', fixed = TRUE)
  expect_match(moves[3], "no change", fixed = TRUE)
  expect_match(moves[4], "no comparison", fixed = TRUE)

  similarity <- data.frame(id = c("ap", "committee_style", "earned", "srs", "blend"),
                           label = c("AP poll", "Our CFP guess", "Who has earned it (ours)", "SRS",
                                     "Who would win (ours)"),
                           avg_gap = c(1.52, 2.56, 3.1, 4.76, 5.24), n = 25L)
  line <- closest_sentence(similarity)
  expect_match(line, "Our CFP guess is 2.6 places off the committee this week, on average.", fixed = TRUE)
  expect_match(line, "Our earned-it ranking is 3.1 off.", fixed = TRUE)
  expect_match(line, "The closest who-would-win ranking is SRS (4.8 places off on average).", fixed = TRUE)
  expect_match(line, "The AP poll, which also ranks by results, is 1.5 off.", fixed = TRUE)
})

test_that("the committee block shows its teams, or says there is no release", {
  html <- as.character(committee_block(ranking, teams, this_week))
  expect_match(html, "Places off", fixed = TRUE)
  expect_match(html, "Our CFP guess", fixed = TRUE)
  expect_match(html, "Earned it", fixed = TRUE)
  expect_match(html, "Would win", fixed = TRUE)
  none <- as.character(committee_block(ranking_table(demo, 5L), teams, 5L))
  expect_match(none, "No committee ranking for week 5.", fixed = TRUE)
})

test_that("simple_table leaves marked columns as HTML and escapes the rest", {
  html <- as.character(simple_table(data.frame(a = "<b>x</b>", b = "<b>y</b>"), html = c(TRUE, FALSE)))
  expect_match(html, "<td class=\"\"><b>x</b></td>", fixed = TRUE)
  expect_match(html, "&lt;b&gt;y&lt;/b&gt;", fixed = TRUE)
})

# The committee-style ranking ---------------------------------------------------

# Four teams. A beat everyone, B lost only to A, C lost to A and B, D lost to
# all three. Power puts them in the same order, ten points apart.
toy_games <- data.frame(
  home_id = c(1L, 1L, 1L, 2L, 2L, 3L), away_id = c(2L, 3L, 4L, 3L, 4L, 4L),
  home_points = 30L, away_points = 10L, neutral_site = TRUE
)
toy_power <- c("1" = 30, "2" = 20, "3" = 10, "4" = 0)
toy_tier <- c("1" = 1L, "2" = 1L, "3" = 0L, "4" = 0L)

test_that("team_resumes counts results and scores them against the reference team", {
  resumes <- team_resumes(toy_games, toy_power, toy_tier, sigma = 16, reference_rank = 2)
  expect_named(resumes, c("team_id", "wins", "losses", "record_strength", "schedule",
                          "top25_wins", "power", "tier"))
  expect_identical(resumes$team_id, 1:4)
  expect_equal(resumes$wins, c(3, 2, 1, 0))
  expect_equal(resumes$losses, c(0, 1, 2, 3))
  expect_equal(resumes$schedule, c(10, 40 / 3, 50 / 3, 20))
  expect_identical(resumes$tier, unname(toy_tier))

  # Team 1 went 3-0. The reference team (rated 20) would be even against
  # team 2 and a favorite against 3 and 4, so three wins beat its par.
  par <- stats::pnorm(c(0, 10, 20) / 16)
  expect_equal(resumes$record_strength[1], sum(1 - par))
  expect_false(is.unsorted(rev(resumes$record_strength)))
})

test_that("a win counts for more at the other team's place than at home", {
  one <- toy_games[1, ]
  one$neutral_site <- FALSE
  home_win <- team_resumes(one, toy_power, toy_tier, sigma = 16, reference_rank = 2)
  flipped <- one
  flipped[c("home_id", "away_id")] <- one[c("away_id", "home_id")]
  flipped[c("home_points", "away_points")] <- one[c("away_points", "home_points")]
  road_win <- team_resumes(flipped, toy_power, toy_tier, sigma = 16, reference_rank = 2)
  expect_gt(road_win$record_strength[road_win$team_id == 1], home_win$record_strength[home_win$team_id == 1])
})

test_that("an opponent we do not rate counts as the weakest team we do", {
  fcs <- data.frame(home_id = 1L, away_id = 999L, home_points = 40L, away_points = 3L, neutral_site = TRUE)
  cupcake <- data.frame(home_id = 1L, away_id = 4L, home_points = 40L, away_points = 3L, neutral_site = TRUE)
  expect_equal(team_resumes(fcs, toy_power, toy_tier, 16, 2)$record_strength,
               team_resumes(cupcake, toy_power, toy_tier, 16, 2)$record_strength[1])
  expect_identical(team_resumes(fcs, toy_power, toy_tier, 16, 2)$team_id, 1L)
})

test_that("committee_score is the weighted sum of the inputs it is given", {
  resumes <- team_resumes(toy_games, toy_power, toy_tier, sigma = 16)
  weights <- c(losses = -2, record_strength = 1)
  expect_equal(committee_score(resumes, weights), -2 * resumes$losses + resumes$record_strength)
  expect_false(is.unsorted(rev(committee_score(resumes, weights))))
})

test_that("committee_style ranks every team that has played, from earlier weeks only", {
  style <- committee_style(demo, 10L)
  expect_named(style, c("team_id", "earned", "committee_style"))
  played <- demo$results[demo$results$week < 10L, ]
  expect_setequal(style$team_id, unique(c(played$home_id, played$away_id)))
  expect_identical(sort(style$committee_style), seq_len(nrow(style)))
  # The table's CFP guess is the forecast for that week, not this plain score.
  guess <- committee_forecast(demo, 10L)
  expect_identical(ranking_table(demo, 10L)$committee_style,
                   guess$rank[match(ranking_table(demo, 10L)$team_id, guess$team_id)])

  # Before any game there is nothing to judge.
  expect_identical(nrow(committee_style(demo, min(demo$results$week))), 0L)
  expect_true(all(is.na(ranking_table(demo, 3L)$committee_style)))
})

# Who has earned it -------------------------------------------------------------

test_that("the earned-it ranking is record strength and nothing else", {
  style <- committee_style(demo, 10L)
  rated <- demo$history[demo$history$week == 10L, ]
  resumes <- team_resumes(demo$results[demo$results$week < 10L, ],
                          stats::setNames(rated$power, rated$team_id),
                          stats::setNames(teams$tier, teams$team_id), demo$params$sigma)
  expect_identical(style$earned, as.integer(rank(-resumes$record_strength, ties.method = "min")))
  expect_identical(min(style$earned), 1L)

  # Conference never enters it.
  flipped <- demo
  flipped$teams$tier <- 1L - teams$tier
  expect_identical(committee_style(flipped, 10L)$earned, style$earned)
})

test_that("ranking_table carries the earned rank and how far it moved", {
  now <- ranking_table(demo, 10L)
  before <- ranking_table(demo, 9L)
  expect_identical(now$earned_change, before$earned[match(now$team_id, before$team_id)] - now$earned)
  # The first week with any results has nothing earlier to compare with.
  first <- ranking_table(demo, min(demo$results$week) + 1L)
  expect_true(all(is.na(first$earned_change)))
  expect_false(all(is.na(first$earned)))
})

test_that("rows can be numbered by either ranking, with the other beside it", {
  listed <- ranking_table(demo, 10L)
  listed <- listed[order(listed$earned), ][1:5, ]
  rows <- ranking_rows(listed, teams, by = "earned")
  expect_identical(rows$rank, listed$earned)
  expect_equal(rows$rank_key, listed$earned)
  expect_identical(rows$other, as.character(listed$rank))
  expect_identical(ranking_rows(listed, teams)$other, as.character(listed$earned))

  expect_identical(rankings_headers("blend")[11], "Earned")
  expect_identical(rankings_headers("earned")[11], "Would win")
  expect_identical(length(rankings_headers("earned")), length(rankings_headers("blend")))
  expect_s3_class(rankings_table(rows, "earned"), "datatables")
  expect_named(RANKING_KINDS, c("blend", "earned"))
})

# Predicting the committee ---------------------------------------------------------

test_that("the next ranking is for the week after the last one fully played", {
  now <- as.POSIXct("2026-11-22 14:00:00", tz = "UTC")
  progress <- data.frame(week = 11:13, games = c(60L, 62L, 58L), completed = c(60L, 62L, 0L),
                         last_open_kickoff = c(NA, NA, "2026-11-29T00:00:00.000Z"))
  expect_identical(forecast_week(progress, now), 13L)
  # One late game still open: week 12 is not in yet.
  progress$completed[2] <- 61L
  progress$last_open_kickoff[2] <- "2026-11-22T04:00:00.000Z"
  expect_identical(forecast_week(progress, now), 12L)
  # The same game still open two weeks on was cancelled, not delayed.
  expect_identical(forecast_week(progress, now + 15 * 86400), 13L)
  expect_identical(forecast_week(progress[3, ], now), NA_integer_)
})

test_that("a committee prediction is saved once, and never after the release", {
  real <- demo
  real$meta$is_demo <- FALSE
  real$meta$forecast_week <- 12L
  real$history <- rbind(demo$history, transform(demo$history[demo$history$week == 11L, ], week = 12L))
  root <- withr::local_tempdir()
  now <- as.POSIXct("2026-11-15 14:00:00", tz = "UTC")

  expect_true(suppressMessages(freeze_committee_forecast(real, root, now)))
  saved <- read_snapshot(forecast_path(2026L, 12L, root))
  expect_equal(nrow(saved), min(FORECAST_SAVED, nrow(committee_forecast(real, 12L))))
  expect_identical(saved$rank, seq_len(nrow(saved)))
  expect_true(all(saved$made == "before"))
  expect_identical(saved$saved_at[1], "2026-11-15T14:00:00Z")
  expect_identical(saved$school[1], teams$school[teams$team_id == saved$team_id[1]])
  expect_false(freeze_committee_forecast(real, root, now + 3600))  # never rewritten

  loaded <- load_forecasts(root, 2026L)
  expect_named(loaded, c("week", "rank", "team_id", "score", "prev_cfp", "method", "made"))
  expect_identical(loaded$team_id, saved$team_id)
  expect_identical(nrow(load_forecasts(root, 2025L)), 0L)
  expect_named(load_forecasts(withr::local_tempdir(), 2026L), names(loaded))

  # Week 11's ranking is already out, so a prediction of it would prove nothing.
  late <- real
  late$meta$forecast_week <- 11L
  expect_false(suppressMessages(freeze_committee_forecast(late, withr::local_tempdir(), now)))
  expect_false(freeze_committee_forecast(demo, withr::local_tempdir(), now))  # demo data
  none <- real
  none$meta$forecast_week <- NA_integer_
  expect_false(freeze_committee_forecast(none, withr::local_tempdir(), now))
})

test_that("saved predictions are graded against the real ranking", {
  polls <- data.frame(week = 12L, poll = "cfp", rank = 1:4, team_id = c(10L, 20L, 30L, 40L))
  ours <- data.frame(week = 12L, rank = 1:4, team_id = c(20L, 10L, 30L, 50L), score = 4:1,
                     prev_cfp = NA_integer_, method = "update", made = "before")
  record <- forecast_record(ours, polls)
  expect_named(record, c("week", "made", "method", "places_off", "exact", "in_25", "top12", "top4"))
  # Off by 1, 1, 0, and team 40 is not on our list: one past its end, 5th, so off by 1.
  expect_equal(record$places_off, 3 / 4)
  expect_identical(record$exact, 1L)
  expect_identical(record$in_25, 3L)
  expect_identical(record$top4, 3L)
  # A prediction with no release yet is not graded.
  expect_identical(nrow(forecast_record(transform(ours, week = 13L), polls)), 0L)

  demo_record <- forecast_record(demo$forecasts, demo$polls)
  expect_identical(demo_record$week, 10:11)
  expect_true(all(demo_record$made == "before"))
})

test_that("the prediction section shows the next ranking only until it is released", {
  expect_null(upcoming_forecast(demo))  # week 11's ranking is out in the demo
  ahead <- demo
  ahead$meta$forecast_week <- 12L
  ahead$history <- rbind(demo$history, transform(demo$history[demo$history$week == 11L, ], week = 12L))
  upcoming <- upcoming_forecast(ahead)
  expect_identical(upcoming$week, 12L)
  expect_false(upcoming$saved)
  expect_lte(nrow(upcoming$rows), 25L)
  html <- as.character(upcoming_forecast_table(upcoming, ahead))
  expect_match(html, "Not saved yet", fixed = TRUE)
  expect_match(html, "Last ranking", fixed = TRUE)

  ahead$forecasts <- rbind(demo$forecasts, cbind(week = 12L, committee_forecast(ahead, 12L), made = "before"))
  expect_true(upcoming_forecast(ahead)$saved)
  expect_match(as.character(upcoming_forecast_table(upcoming_forecast(ahead), ahead)), "Saved before the release", fixed = TRUE)

  section <- as.character(forecast_section("t", demo))
  expect_match(section, "Predicting the committee", fixed = TRUE)
  expect_match(section, "Places off", fixed = TRUE)
  empty <- demo
  empty$forecasts <- demo$forecasts[0, ]
  empty$meta$forecast_week <- NA_integer_
  expect_null(forecast_section("t", empty))
})

test_that("ratings after the last games stand in for weeks past the schedule", {
  power <- list(weekly = data.frame(team_id = c(1L, 2L, 1L, 2L), week = c(1L, 1L, 2L, 2L), power = 1:4),
                current = data.frame(team_id = 1:2, power = c(9, 8)))
  expect_identical(power_through(power, 1:2), power$weekly)
  extended <- power_through(power, 1:3)
  expect_equal(extended$power[extended$week == 3L], c(9, 8))
  expect_identical(nrow(extended), 6L)
})
