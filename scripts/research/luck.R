# Are teams that have been lucky overrated by our line? Two kinds of luck,
# both measured only from games already played that season:
#
# - Scoreboard luck: how much a team has outscored what its plays were
#   worth. Points added per play, summed over a game, say what the score
#   "should" have been. Turnovers, special teams and short fields are most
#   of the difference, and they do not repeat much.
# - Close-game luck: wins in games decided by 7 or fewer, beyond half.
#
# Started from UCLA in week 13 of 2026: 10-1 with several close wins, and
# the sportsbooks made it a 7-point home underdog.
#
# Run from the project root:
#   Rscript scripts/research/luck.R

source(file.path("scripts", "research", "common.R"))
data <- load_research_data()
games <- data$games
MIN_GAMES <- 3
CLOSE_POINTS <- 7

game_files <- list.files(file.path(PATHS$snapshots, "games"), pattern = "^[0-9]{4}\\.csv$", full.names = TRUE)
schedule <- do.call(rbind, lapply(game_files, function(f) {
  read_snapshot(f)[c("game_id", "start_date", "home_id", "away_id", "home_team", "away_team", "home_points", "away_points")]
}))
stat_files <- list.files(file.path(PATHS$snapshots, "extras", "advanced"), pattern = "^[0-9]{4}\\.csv$", full.names = TRUE)
stats <- do.call(rbind, lapply(stat_files, function(f) {
  read_snapshot(f)[c("game_id", "season", "team", "off_total_ppa", "def_total_ppa")]
}))
stats <- passing_with_teams(stats, schedule)
at <- match(stats$game_id, schedule$game_id)
home <- schedule$home_id[at] == stats$team_id
stats$margin <- ifelse(home, 1, -1) * (schedule$home_points[at] - schedule$away_points[at])
stats$play_margin <- stats$off_total_ppa - stats$def_total_ppa
stats <- stats[!is.na(stats$margin) & !is.na(stats$play_margin), ]
stats <- stats[order(stats$season, stats$team_id, stats$start_date, stats$game_id), ]

stats$score_luck <- stats$margin - stats$play_margin
close <- abs(stats$margin) <= CLOSE_POINTS
stats$close_luck <- ifelse(close, (stats$margin > 0) - 0.5, 0)

key <- paste(stats$season, stats$team_id)
played <- stats::ave(rep(1, nrow(stats)), key, FUN = cumsum) - 1
before <- function(x) stats::ave(x, key, FUN = cumsum) - x
stats$score_luck_before <- ifelse(played >= MIN_GAMES, before(stats$score_luck) / played, NA)   # points a game
stats$close_luck_before <- ifelse(played >= MIN_GAMES, before(stats$close_luck), NA)            # wins beyond half
# The last three games only: is it recent luck that matters?
recent <- function(x) stats::ave(x, key, FUN = function(v) {
  n <- length(v); if (n == 0) return(v)
  vapply(seq_len(n), function(i) if (i <= 3) NA_real_ else mean(v[(i - 3):(i - 1)]), numeric(1))
})
stats$score_luck_recent <- recent(stats$score_luck)

side <- function(id_column, column) {
  at <- match(paste(games$game_id, games[[id_column]]), paste(stats$game_id, stats$team_id))
  stats[[column]][at]
}
zero <- function(x) ifelse(is.na(x), 0, x)
for (column in c("score_luck_before", "close_luck_before", "score_luck_recent")) {
  games[[column]] <- zero(side("home_id", column)) - zero(side("away_id", column))
}

candidates <- c(
  score_luck_before = "Scoreboard luck: points a game beyond what the plays were worth",
  close_luck_before = "Close-game luck: wins beyond half in games within 7",
  score_luck_recent = "Scoreboard luck over the last three games"
)
cat("How a play margin tracks the real margin: correlation", round(stats::cor(stats$margin, stats$play_margin), 2),
    ", slope", round(stats::coef(stats::lm(margin ~ play_margin, stats))[2], 2), "\n")
cat("Does luck repeat? A team's scoreboard luck so far against its luck in the next game: correlation",
    round(stats::cor(stats$score_luck_before, stats$score_luck, use = "complete.obs"), 2), "\n\n")
cat("Candidate: games, and points our line missed by per unit of luck (fit seasons)\n")
fit <- games[games$season %in% FIT_SEASONS, ]
for (column in names(candidates)) {
  used <- fit[[column]] != 0
  slope <- stats::coef(stats::lm(I(home_margin - pred) ~ 0 + x, data.frame(home_margin = fit$home_margin[used],
                                                                         pred = fit$pred[used], x = fit[[column]][used])))
  cat(sprintf("%-66s %5d  %+.3f\n", candidates[[column]], sum(used), slope))
}
cat("\n")
print_verdicts(games, candidates)
