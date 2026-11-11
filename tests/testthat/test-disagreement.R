test_that("ats_results grades the model's side, with pushes and ties left out", {
  # Model has home by 4.5, line has home by 2.5: the model's side is home -2.5.
  expect_true(ats_results(4.5, 2.5, 7)$model_side_won)    # home wins by 7, covers
  expect_false(ats_results(4.5, 2.5, 1)$model_side_won)   # home wins by 1, away covers
  expect_false(ats_results(4.5, 2.5, -3)$model_side_won)  # away wins outright
  # Model lower on home than the line: the model's side is the away team.
  expect_true(ats_results(1, 6, 3)$model_side_won)
  expect_false(ats_results(1, 6, 10)$model_side_won)
  # A push, and a game with no gap, count for neither side.
  expect_true(is.na(ats_results(5, 3, 3)$model_side_won))
  expect_true(is.na(ats_results(3, 3, 10)$model_side_won))
  expect_equal(ats_results(4.5, 2.5, 7)$gap, 2)
})

test_that("ats_row counts games at or past the gap and reports the book's side", {
  results <- ats_results(model = c(5, 5, 5, 0, 1, 9), line = c(2, 2, 2, 4, 0, 9),
                         actual = c(10, 0, 2, 0, 5, 3))
  row <- ats_row(results, 3)
  # Gaps: 3, 3, 3, -4, 1, 0. Four reach 3: a model win, a book win, a push, a model win.
  expect_equal(row$games, 4)
  expect_equal(row$pushes, 1)
  expect_equal(row$book_wins, 1)
  expect_equal(row$book_losses, 2)
  expect_equal(row$book_pct, 1 / 3)
  expect_true(row$low < 1 / 3 && row$high > 1 / 3)

  empty <- ats_row(results, 50)
  expect_equal(empty$games, 0)
  expect_true(is.na(empty$book_pct))
})

test_that("break-even and return at -110 agree", {
  expect_equal(return_per_100(BREAK_EVEN), 0)
  expect_equal(return_per_100(1), 100 * 100 / 110)
  expect_equal(return_per_100(0), -100)
  expect_equal(return_per_100(0.5), -100 * (1 - 100 / 110) / 2)
})

test_that("wilson_interval brackets the share and handles no games", {
  interval <- wilson_interval(50, 100)
  expect_equal(mean(interval), 0.5)
  expect_true(interval[1] > 0.39 && interval[2] < 0.61)
  expect_true(all(is.na(wilson_interval(0, 0))))
})

test_that("book_lines turns spreads into home margins and drops bad rows", {
  lines <- data.frame(
    game_id = c(1L, 2L, 3L, 4L, 1L),
    provider = c("A", "A", "A", "A", "B"),
    spread = c(-7, 10, NA, -3, -6.5),
    spread_open = c(-6, -10, -2, 20, NA)
  )
  consensus <- data.frame(game_id = 1:4, line = c(7, 10, 2, 3))
  out <- book_lines(lines, "A", consensus)
  # Game 2's sign disagrees with the consensus (home and away swapped) and
  # game 3 has no spread. Game 4's opener is 23 points from its close.
  expect_equal(out$game_id, c(1L, 4L))
  expect_equal(out$close, c(7, 3))
  expect_equal(out$open, c(6, NA))
})

test_that("line_move_table measures movement toward the model", {
  # Model above the opener in games 1 and 2, below it in game 3.
  out <- line_move_table(model = c(10, 10, 0), open = c(6, 6, 4), close = c(7, 5, 4), thresholds = c(3, 5))
  expect_equal(out$games, c(3, 0))
  # One moved toward, one away, one did not move.
  expect_equal(out$toward[1], 0.5)
  expect_equal(out$avg_move[1], 0)
  expect_true(is.na(out$toward[2]))
})
