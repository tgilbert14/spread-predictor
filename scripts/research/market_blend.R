# How close is the closing line, and does our number add anything to it?
#
# Compares our out-of-sample house line with the closing line, checks our
# spreads against results by size, and fits the best mix of the two.
#
# Result (Nov 2026): the market misses by about half a point less per game,
# our spreads are well calibrated at every size, and the best mix is 98%
# market. See docs/research-log.md and docs/market-disagreement.md.

source(file.path("scripts", "research", "common.R"))
games <- load_research_data()$games
fit <- games[games$season %in% FIT_SEASONS, ]
holdout <- games[games$season == HOLDOUT_SEASON, ]

mae <- function(rows, column) mean(abs(rows$home_margin - rows[[column]]))
picked <- function(rows, column) {
  decided <- rows[[column]] != 0 & rows$home_margin != 0
  mean(sign(rows[[column]][decided]) == sign(rows$home_margin[decided]))
}
cat("Average miss and winners picked: fit seasons, then holdout\n")
for (column in c("pred", "line")) {
  cat(sprintf("%-5s  %.2f  %.1f%%   %.2f  %.1f%%\n", if (column == "pred") "Ours" else "Line",
              mae(fit, column), 100 * picked(fit, column), mae(holdout, column), 100 * picked(holdout, column)))
}
apart <- abs(games$pred - games$line)
cat(sprintf("\nOur line and the market's: %.2f apart on average, within 3 in %.0f%% of games, 7 or more apart in %.0f%%.\n",
            mean(apart), 100 * mean(apart <= 3), 100 * mean(apart >= 7)))

cat("\nOur spreads by size: games, predicted margin for our favorite, actual margin\n")
size <- cut(abs(games$pred), c(0, 3, 7, 14, 21, 28, Inf))
favorite <- sign(games$pred)
for (level in levels(size)) {
  rows <- size == level
  cat(sprintf("%-9s %5d  %5.1f  %5.1f\n", level, sum(rows), mean(abs(games$pred[rows])),
              mean((favorite * games$home_margin)[rows])))
}

# The best mix, fitted on the other fit seasons each time.
mix <- rep(NA_real_, nrow(fit))
for (season in FIT_SEASONS) {
  held_out <- fit$season == season
  mix[held_out] <- stats::predict(stats::lm(home_margin ~ 0 + line + pred, data = fit[!held_out, ]),
                                  newdata = fit[held_out, ])
}
weights <- stats::coef(stats::lm(home_margin ~ 0 + line + pred, data = fit))
cv <- paired_bootstrap(abs(fit$home_margin - mix) - abs(fit$home_margin - fit$line))
cat(sprintf("\nBest mix: %.0f%% market, %.0f%% ours. Against the market alone: CV %+.3f [%+.3f, %+.3f].\n",
            100 * weights[["line"]], 100 * weights[["pred"]], cv[["change"]], cv[["low"]], cv[["high"]]))
