# Helpers for scripts/disagreement.R, which asks one question: when a model
# and the sportsbooks disagree on a spread, which side covers?
#
# Nothing here is used by the app or by scripts/fit.R.
#
# Every margin is home minus away. A "line" is the sportsbook spread turned
# into a home margin, so a spread of -7 is a line of +7.

# How far apart the model and the line must be, in points, for a game to
# count in each row of the tables.
DISAGREE_THRESHOLDS <- c(2, 3, 4, 5, 7, 10)

# Share of bets you must win to break even at the standard price of -110
# (risk 110 to win 100).
BREAK_EVEN <- 110 / 210

# An opening line this far from the same book's closing line is treated as
# a data error and dropped. Real lines rarely move this much.
MAX_LINE_MOVE <- 10

#' Grade each game against the spread, from the model's point of view.
#'
#' The model's side is the team the model likes more than the line does.
#' With the model at home by 4.5 and the line at home by 2.5, the model's
#' side is the home team giving 2.5, and the sportsbook's side is the away
#' team getting 2.5.
#'
#' @param model,line,actual Home margins: the model's, the line's, the result.
#' @return gap (model minus line) and model_side_won: TRUE, FALSE, or NA
#'   for a push (the result landed exactly on the line) or no gap at all.
ats_results <- function(model, line, actual) {
  gap <- model - line
  cover <- sign(actual - line)
  side <- sign(gap)
  data.frame(gap = gap, model_side_won = ifelse(cover == 0 | side == 0, NA, cover == side))
}

#' Wilson 95% interval for a share, as c(low, high).
wilson_interval <- function(wins, n, z = stats::qnorm(0.975)) {
  if (n == 0) return(c(NA_real_, NA_real_))
  p <- wins / n
  center <- (p + z^2 / (2 * n)) / (1 + z^2 / n)
  half <- z * sqrt(p * (1 - p) / n + z^2 / (4 * n^2)) / (1 + z^2 / n)
  c(center - half, center + half)
}

#' Profit per 100 risked at -110, for a share of bets won.
return_per_100 <- function(win_share) 100 * (win_share * 100 / 110 - (1 - win_share))

#' One row of the table: bets where the gap is at least `threshold`.
#'
#' @param results From ats_results(). Rows with an NA gap are ignored.
#' @return threshold, games, pushes, book_wins, book_losses, book_pct (how
#'   often the sportsbook's side covered, pushes left out), low and high
#'   (its 95% interval) and book_return (per 100 risked at -110).
ats_row <- function(results, threshold) {
  hit <- !is.na(results$gap) & abs(results$gap) >= threshold
  won <- results$model_side_won[hit]
  decided <- sum(!is.na(won))
  book_wins <- sum(!won, na.rm = TRUE)
  interval <- wilson_interval(book_wins, decided)
  share <- if (decided > 0) book_wins / decided else NA_real_
  data.frame(threshold = threshold, games = sum(hit), pushes = sum(is.na(won)),
             book_wins = book_wins, book_losses = decided - book_wins,
             book_pct = share, low = interval[1], high = interval[2],
             book_return = return_per_100(share))
}

#' The full table for one model against one line: a row per threshold.
ats_table <- function(model, line, actual, thresholds = DISAGREE_THRESHOLDS) {
  results <- ats_results(model, line, actual)
  do.call(rbind, lapply(thresholds, function(t) ats_row(results, t)))
}

#' One book's closing and opening lines as home margins, one row per game.
#'
#' Drops rows with no spread, a sign that disagrees with the consensus line
#' (home and away swapped), and opening lines more than MAX_LINE_MOVE from
#' the close.
#'
#' @param lines_full Rows of game_id, provider, spread and spread_open.
#' @param consensus game_id and line (the median closing line, home margin).
#' @return game_id, close, open (NA when the book gave no usable opener).
book_lines <- function(lines_full, provider, consensus) {
  rows <- lines_full[lines_full$provider == provider & !is.na(lines_full$spread), , drop = FALSE]
  rows <- rows[!duplicated(rows$game_id), , drop = FALSE]
  close <- -rows$spread
  open <- -rows$spread_open
  middle <- consensus$line[match(rows$game_id, consensus$game_id)]
  flipped <- !is.na(middle) & abs(middle) >= 3 & abs(close + middle) <= 1.5 & sign(close) != sign(middle)
  open[!is.na(open) & abs(open - close) > MAX_LINE_MOVE] <- NA
  data.frame(game_id = rows$game_id, close = close, open = open)[!flipped, , drop = FALSE]
}

#' Did the line move toward the model between open and close?
#'
#' @param model,open,close Home margins.
#' @return One row per threshold on the opening gap: games, toward (share
#'   of lines that moved toward the model, among those that moved), and
#'   avg_move (points moved toward the model, negative means away).
line_move_table <- function(model, open, close, thresholds = DISAGREE_THRESHOLDS) {
  gap <- model - open
  toward <- sign(gap) * (close - open)
  do.call(rbind, lapply(thresholds, function(t) {
    hit <- !is.na(gap) & !is.na(toward) & abs(gap) >= t
    moved <- hit & toward != 0
    data.frame(threshold = t, games = sum(hit),
               toward = if (any(moved)) mean(toward[moved] > 0) else NA_real_,
               avg_move = if (any(hit)) mean(toward[hit]) else NA_real_)
  }))
}
