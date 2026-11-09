# Turn model numbers into the words and figures people read.
# The rules live here, in one place, so every tab rounds the same way.

#' Round to the nearest half point, the way spreads are quoted.
round_half <- function(x) round(x * 2) / 2

#' Drop a trailing ".0" so 7 prints as "7" and 6.5 as "6.5".
format_points <- function(x) {
  x <- round_half(abs(x))
  ifelse(x == round(x), sprintf("%d", as.integer(round(x))), sprintf("%.1f", x))
}

#' Win probability as a whole percent, kept between 1 and 99.
#' No football game is a sure thing, so we never print 0% or 100%.
format_prob <- function(p) {
  pct <- pmin(pmax(round(p * 100), 1), 99)
  paste0(pct, "%")
}

#' Where the game is played, in words.
site_phrase <- function(site, name_a, name_b) {
  switch(site,
    neutral = "on a neutral field",
    a_home  = paste("at", name_a),
    b_home  = paste("at", name_b)
  )
}

#' "Team by X" for a margin, or "Pick'em" when it rounds to zero.
#' We never show a signed number on its own. Sign conventions confuse people.
#'
#' @param margin A minus B.
format_favorite <- function(margin, name_a, name_b) {
  if (round_half(margin) == 0) return("Pick'em")
  favorite <- if (margin > 0) name_a else name_b
  paste(favorite, "by", format_points(margin))
}

#' The one-line answer shown at the top of the Matchup tab.
#'
#' @param pred Result of predict_matchup().
format_headline <- function(pred) {
  name_a <- pred$team_a$school
  name_b <- pred$team_b$school
  where <- site_phrase(pred$site, name_a, name_b)
  if (round_half(pred$spread) == 0) {
    return(sprintf("Pick'em: %s vs %s %s", name_a, name_b, where))
  }
  favorite <- if (pred$spread > 0) name_a else name_b
  underdog <- if (pred$spread > 0) name_b else name_a
  sprintf("%s by %s over %s %s", favorite, format_points(pred$spread), underdog, where)
}

#' The likely range of outcomes, e.g. "Texas by 14 to Georgia by 27".
format_interval <- function(pred) {
  name_a <- pred$team_a$school
  name_b <- pred$team_b$school
  paste(
    format_favorite(pred$interval[["low"]], name_a, name_b),
    "to",
    format_favorite(pred$interval[["high"]], name_a, name_b)
  )
}

#' Plain-text summary for the "Copy summary" button.
format_summary <- function(pred) {
  sprintf(
    "%s. Win probability: %s %s, %s %s.",
    format_headline(pred),
    pred$team_a$school, format_prob(pred$win_prob_a),
    pred$team_b$school, format_prob(1 - pred$win_prob_a)
  )
}
