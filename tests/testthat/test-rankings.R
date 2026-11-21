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
                          names(MODEL_LABELS), "committee_style", names(POLL_NAMES)))
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
                    committee_style = c(2L, 1L, 4L, 3L))
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
  expect_identical(ncol(rows), length(RANKINGS_VISIBLE) + length(RANKINGS_SORTED))
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

  expect_identical(format_gap(c(2L, 9L, 5L, 4L, NA), c(6L, 2L, 5L, 5L, 1L)),
                   c("4 places higher", "7 places lower", "same", "1 place higher", ""))

  similarity <- data.frame(id = c("ap", "committee_style", "srs", "blend"),
                           label = c("AP poll", "Our CFP guess", "SRS", "Our blend"),
                           avg_gap = c(1.52, 2.56, 4.76, 5.24), n = 25L)
  line <- closest_sentence(similarity)
  expect_match(line, "Our CFP guess is 2.6 places off the committee this week, on average.", fixed = TRUE)
  expect_match(line, "The closest who-would-win ranking is SRS (4.8 places off on average).", fixed = TRUE)
  expect_match(line, "The AP poll, which also ranks by results, is 1.5 off.", fixed = TRUE)
})

test_that("the committee block shows its teams, or says there is no release", {
  html <- as.character(committee_block(ranking, teams, this_week))
  expect_match(html, "Places off", fixed = TRUE)
  expect_match(html, "Our CFP guess", fixed = TRUE)
  expect_match(html, "Top 50 vs CFP", fixed = TRUE)
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

test_that("committee_score rewards wins and punishes losses, and uses the stored weights", {
  resumes <- team_resumes(toy_games, toy_power, toy_tier, sigma = 16)
  score <- committee_score(resumes)
  expect_false(is.unsorted(rev(score)))
  expect_equal(score, drop(as.matrix(resumes[names(COMMITTEE_MODEL$weights)]) %*% COMMITTEE_MODEL$weights))
  expect_named(COMMITTEE_MODEL$weights, c("losses", "record_strength", "power", "tier"))
  expect_lt(COMMITTEE_MODEL$weights[["losses"]], 0)
  expect_gt(COMMITTEE_MODEL$weights[["record_strength"]], 0)
})

test_that("committee_style ranks every team that has played, from earlier weeks only", {
  style <- committee_style(demo, 10L)
  expect_named(style, c("team_id", "committee_style"))
  played <- demo$results[demo$results$week < 10L, ]
  expect_setequal(style$team_id, unique(c(played$home_id, played$away_id)))
  expect_identical(sort(style$committee_style), seq_len(nrow(style)))
  expect_identical(ranking_table(demo, 10L)$committee_style,
                   style$committee_style[match(ranking_table(demo, 10L)$team_id, style$team_id)])

  # Before any game there is nothing to judge.
  expect_identical(nrow(committee_style(demo, min(demo$results$week))), 0L)
  expect_true(all(is.na(ranking_table(demo, 3L)$committee_style)))
})
