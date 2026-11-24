# Does a missing quarterback explain where our line goes wrong, and by how
# much? Started from USC at UCLA in week 13 of 2026: we had UCLA by 4.5, the
# market USC by 7, and UCLA's quarterback was out.
#
# The main quarterback is whoever has thrown the most passes for the team so
# far that season. He is out when he threw none in a game. A game's factor
# is the home team's flag minus the away team's, as in the other studies.
#
# Run from the project root:
#   Rscript scripts/research/qb_out.R

source(file.path("scripts", "research", "common.R"))
data <- load_research_data()
games <- data$games

game_files <- list.files(file.path(PATHS$snapshots, "games"), pattern = "^[0-9]{4}\\.csv$", full.names = TRUE)
schedule <- do.call(rbind, lapply(game_files, function(f) {
  read_snapshot(f)[c("game_id", "start_date", "home_id", "away_id", "home_team", "away_team")]
}))
qb <- quarterback_games(passing_with_teams(load_passing(), schedule))

# How good the missing quarterback was: his yards per attempt against the
# average main quarterback's, in standard deviations. Unknown counts as average.
typical <- stats::median(qb$main_ypa, na.rm = TRUE)
spread <- stats::sd(qb$main_ypa, na.rm = TRUE)
qb$quality <- ifelse(is.na(qb$main_ypa), 0, (qb$main_ypa - typical) / spread)

qb$out_first <- as.integer(qb$out_now == 1 & qb$out_prev == 0)   # the first game he misses
qb$out_known <- as.integer(qb$out_now == 1 & qb$out_prev == 1)   # still out: the box scores already showed it
qb$out_now_good <- qb$out_now * pmax(qb$quality, 0)              # extra cost of losing a good one
qb$out_prev_good <- qb$out_prev * pmax(qb$quality, 0)

# The same flags for established starters only.
qb$est_out <- qb$out_now * qb$established
qb$est_first <- qb$out_first * qb$established
qb$est_known <- qb$out_known * qb$established
qb$est_prev <- qb$out_prev * qb$established
qb$est_out_good <- qb$est_out * pmax(qb$quality, 0)

# Two sizes instead of one: the first game he misses costs more than later ones.
qb$est_tiered <- qb$est_first * 4 / 3.5 + qb$est_known * 2 / 3.5
# Box scores alone, no report needed: he missed the last game, at a discount
# for the ones who come back.
qb$est_prev_only <- qb$est_prev

flags <- c(
  out_now = "Main QB out (known only from a report, or afterwards)",
  out_first = "  ...the first game he misses",
  out_known = "  ...a later game (box scores already showed it)",
  out_prev = "Main QB missed the last game (known before kickoff)",
  out_now_good = "Main QB out, scaled by how good he was",
  out_prev_good = "Missed the last game, scaled by how good he was",
  est_out = "Established starter out",
  est_first = "  ...the first game he misses",
  est_known = "  ...a later game",
  est_prev = "Established starter missed the last game",
  est_out_good = "Established starter out, scaled by how good he was",
  est_tiered = "Established starter out: first game 4, later games 2"
)
side <- function(id_column, flag) {
  at <- match(paste(games$game_id, games[[id_column]]), paste(qb$game_id, qb$team_id))
  ifelse(is.na(at), 0, qb[[flag]][at])
}
for (flag in names(flags)) games[[flag]] <- side("home_id", flag) - side("away_id", flag)

cat("Games in the study:", nrow(games), " team-games with a main QB out:", sum(qb$out_now), "\n\n")
cat("Flag: games, points worse than our line, points worse than the market line\n")
fit <- games[games$season %in% FIT_SEASONS, ]
for (flag in c("out_now", "out_first", "out_known", "out_prev", "est_out", "est_first", "est_known", "est_prev")) {
  hit <- fit[[flag]] != 0
  ours <- -((fit$home_margin - fit$pred) * sign(fit[[flag]]))[hit]
  market <- -((fit$home_margin - fit$line) * sign(fit[[flag]]))[hit]
  cat(sprintf("%-55s %5d  %+5.2f (se %.2f)  %+5.2f\n", flags[[flag]], sum(hit), mean(ours),
              stats::sd(ours) / sqrt(sum(hit)), mean(market, na.rm = TRUE)))
}
cat("\nBy how many games in a row he had already missed:\n")
at_home <- match(paste(fit$game_id, fit$home_id), paste(qb$game_id, qb$team_id))
at_away <- match(paste(fit$game_id, fit$away_id), paste(qb$game_id, qb$team_id))
long <- rbind(data.frame(resid = fit$home_margin - fit$pred, qb[at_home, c("out_now", "games_out", "quality", "established")]),
              data.frame(resid = -(fit$home_margin - fit$pred), qb[at_away, c("out_now", "games_out", "quality", "established")]))
long <- long[!is.na(long$out_now) & long$out_now == 1 & long$established == 1, ]
cat("(established starters only)\n")
for (k in 0:3) {
  x <- long$resid[if (k < 3) long$games_out == k else long$games_out >= 3]
  cat(sprintf("  missed %s before: %4d team-games, %+5.2f vs our line\n", if (k < 3) k else "3+", length(x), mean(x)))
}
cat("\nBy how good he was (yards per attempt before the game):\n")
for (band in list(c(-Inf, -0.5), c(-0.5, 0.5), c(0.5, Inf))) {
  x <- long$resid[long$quality > band[1] & long$quality <= band[2]]
  cat(sprintf("  quality %5.1f to %4.1f sd: %4d team-games, %+5.2f vs our line\n", band[1], band[2], length(x), mean(x)))
}
cat("\n")
print_verdicts(games, flags)
