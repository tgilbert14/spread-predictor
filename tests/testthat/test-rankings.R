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
                          names(MODEL_LABELS), names(POLL_NAMES)))
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
  toy <- data.frame(rank = 1:4, cfp = c(2L, 1L, 3L, NA), ap = c(2L, 1L, NA, 3L))
  for (model in names(MODEL_LABELS)) toy[[model]] <- 1:4
  toy$sp <- c(2L, 1L, 3L, 4L)
  similarity <- committee_similarity(toy)
  expect_named(similarity, c("id", "label", "avg_gap", "n"))
  score <- function(id) similarity$avg_gap[similarity$id == id]
  expect_equal(score("sp"), 0)
  expect_equal(score("blend"), 2 / 3)
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

  similarity <- data.frame(id = c("ap", "srs", "blend"), label = c("AP poll", "SRS", "Our blend"),
                           avg_gap = c(1.52, 4.76, 5.24), n = 25L)
  line <- closest_sentence(similarity)
  expect_match(line, "Closest to the committee this week: AP poll (1.5 places off on average).", fixed = TRUE)
  expect_match(line, "Among the rating systems, SRS (4.8 places off on average) comes nearest.", fixed = TRUE)
  expect_match(line, "Our blend is 5.2 places off.", fixed = TRUE)
})

test_that("the committee block shows its teams, or says there is no release", {
  html <- as.character(committee_block(ranking, teams, this_week))
  expect_match(html, "Places off", fixed = TRUE)
  expect_match(html, "We have them", fixed = TRUE)
  none <- as.character(committee_block(ranking_table(demo, 5L), teams, 5L))
  expect_match(none, "No committee ranking for week 5.", fixed = TRUE)
})

test_that("simple_table leaves marked columns as HTML and escapes the rest", {
  html <- as.character(simple_table(data.frame(a = "<b>x</b>", b = "<b>y</b>"), html = c(TRUE, FALSE)))
  expect_match(html, "<td class=\"\"><b>x</b></td>", fixed = TRUE)
  expect_match(html, "&lt;b&gt;y&lt;/b&gt;", fixed = TRUE)
})
