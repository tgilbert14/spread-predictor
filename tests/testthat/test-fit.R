fixture_db <- make_fixture_db()

#' Fit params on a fixture database.
fit_fixture <- function(db_path) {
  con <- connect_readonly(db_path)
  on.exit(DBI::dbDisconnect(con))
  with_project_root(fit_params(con))
}

params <- fit_fixture(fixture_db)

test_that("the fit recovers the true k, home field and sigma", {
  expect_equal(params$k, FIXTURE_TRUTH$k, tolerance = 0.08)
  expect_lt(abs(params$h - FIXTURE_TRUTH$h), 1)
  expect_lt(abs(params$sigma - FIXTURE_TRUTH$sigma), 0.75)
})

test_that("FCS games and games without pregame Elo are left out", {
  con <- connect_readonly(fixture_db)
  on.exit(DBI::dbDisconnect(con))
  games <- elo_fit_set(with_project_root(load_completed_games(con)))
  expect_false(any(games$game_id %% 10000 > 5000))
  expect_equal(nrow(games), 5 * 400)
})

test_that("there is one fold per training season", {
  expect_identical(params$folds$season, 2021:2025)
  expect_true(all(abs(params$folds$k / FIXTURE_TRUTH$k - 1) < 0.1))
})

test_that("the closing line is sharper than Elo on the same games", {
  elo <- params$metrics[params$metrics$model == "elo", ]
  line <- params$metrics[params$metrics$model == "line", ]
  expect_identical(elo$n, line$n)
  expect_lt(line$mae, elo$mae)
  expect_lt(line$brier, elo$brier)
})

test_that("calibration has five bins covering 0.5 to 1", {
  cal <- params$calibration
  expect_equal(cal$bin_low, seq(0.5, 0.9, by = 0.1))
  expect_equal(cal$bin_high, seq(0.6, 1.0, by = 0.1))
  expect_true(all(cal$predicted >= cal$bin_low & cal$predicted <= cal$bin_high))
})

test_that("the leaked diagnostic covers sp, fpi and srs, or is empty without finals", {
  expect_identical(params$leaked_diagnostic$model, c("sp", "fpi", "srs"))
  empty <- leaked_diagnostic(data.frame(source = character(), season = integer(),
                                        team_id = integer(), rating = numeric()),
                             data.frame(season = 2021L, home_id = 1L, away_id = 2L,
                                        neutral_site = 0L, home_margin = 3),
                             h = 2.5)
  expect_identical(nrow(empty), 0L)
  expect_named(empty, c("model", "n", "mae"))
})

test_that("flipped line signs stop the fit with a clear message", {
  flipped <- make_fixture_db(flip_lines = TRUE)
  expect_error(fit_fixture(flipped), "Closing lines point the wrong way")
})

test_that("ties do not crash the scoring", {
  scored <- score_margins(predicted = c(3, -2, 0, 5), actual = c(7, 0, 4, -1), sigma = 16)
  expect_identical(scored$n, 4L)
  expect_equal(scored$win_rate, (1 + 0.5 + 0) / 3)
  all_ties <- score_margins(c(1, 2), c(0, 0), 16)
  expect_true(is.na(all_ties$win_rate) && is.na(all_ties$brier))
})

test_that("params round-trip through JSON into the demo shape", {
  path <- tempfile(fileext = ".json")
  write_params(params, path)
  back <- read_params(path)
  demo <- demo_app_data()$params

  expect_true(all(names(demo) %in% names(back)))
  expect_identical(setdiff(names(back), names(demo)), "weights_note")
  for (field in names(demo)) {
    expect_identical(class(back[[field]]), class(demo[[field]]), label = field)
    if (is.data.frame(demo[[field]])) {
      expect_identical(vapply(back[[field]], class, character(1)),
                       vapply(demo[[field]], class, character(1)), label = field)
    }
  }
  expect_named(back$weights, names(demo$weights))
  expect_equal(back$k, params$k, tolerance = 1e-4)
  expect_equal(back$metrics$mae, params$metrics$mae, tolerance = 1e-4)
})

test_that("an empty leaked diagnostic survives the round trip with its columns", {
  path <- tempfile(fileext = ".json")
  p <- params
  p$leaked_diagnostic <- p$leaked_diagnostic[0, ]
  write_params(p, path)
  back <- read_params(path)$leaked_diagnostic
  expect_identical(nrow(back), 0L)
  expect_named(back, c("model", "n", "mae"))
})

test_that("read_params says what to do when the file is missing", {
  expect_error(read_params(tempfile()), "scripts/fit.R")
})

test_that("weights always sum to 1", {
  expect_equal(sum(unlist(params$weights)), 1)
  expect_named(params$weights, RATING_SOURCES)

  set.seed(7)
  X <- matrix(stats::rnorm(400 * 4, 0, 15), ncol = 4, dimnames = list(NULL, RATING_SOURCES))
  w <- fit_blend_weights(X, stats::rnorm(400, 0, 10))
  expect_equal(sum(w), 1)
  expect_true(all(w >= 0))
})

test_that("blend weights favor the system that is actually right", {
  set.seed(11)
  truth <- stats::rnorm(1000, 0, 15)
  X <- cbind(sp = truth, fpi = truth + stats::rnorm(1000, 0, 12),
             srs = truth + stats::rnorm(1000, 0, 12), elo = truth + stats::rnorm(1000, 0, 12))
  y <- truth + stats::rnorm(1000, 0, 5)
  w <- fit_blend_weights(X, y)
  expect_identical(names(which.max(w)), "sp")
  # Shrinkage keeps the weaker systems in the blend.
  expect_true(all(w > 0))

  design <- list(X = X, y = y, week = rep(paste(2025, 1:10), each = 100))
  chosen <- choose_weights(design)
  expect_identical(chosen$method, "fitted")
  expect_equal(sum(unlist(chosen$weights)), 1)
})

test_that("choose_weights stays equal with too few snapshot games", {
  expect_identical(params$weights_method, "equal")
  expect_match(params$weights_note, "at least 300")
  expect_equal(unlist(params$weights), unlist(equal_weights()))

  small <- list(X = matrix(1, 50, 4, dimnames = list(NULL, RATING_SOURCES)),
                y = rep(1, 50), week = rep(c("2026 1", "2026 2"), 25))
  expect_identical(choose_weights(small)$method, "equal")
})

test_that("blend_design matches snapshot week W to week W games and skips postseason", {
  games <- data.frame(season = 2026L, week = c(5L, 5L, 6L), season_type = c("regular", "postseason", "regular"),
                      home_id = 1L, away_id = 2L, neutral_site = 0L, home_margin = 10)
  weekly <- do.call(rbind, lapply(RATING_SOURCES, function(source) {
    data.frame(source = source, season = 2026L, week = 5L, team_id = 1:2,
               rating = if (source == "elo") c(1600, 1500) else c(6, 0))
  }))
  design <- blend_design(games, weekly, k = 25, h = 2)
  expect_identical(nrow(design$X), 1L)
  expect_equal(unname(design$X[1, ]), c(6, 6, 6, 4))
  expect_equal(design$y, 8)
})
