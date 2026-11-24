# Do missing starters, other than the quarterback, explain where our line
# goes wrong? The idea: a top defense without its best players should not be
# rated like the full unit.
#
# There is no history of injury reports, so absences are read off the box
# scores, the same way as the quarterback study. Going into a game, a team's
# core players are its top rusher, top 3 receivers and top 6 tacklers of the
# season so far. A core player is out when he has no carry, catch or tackle
# in the game. Teams need 3 games played before they count.
#
# Limits: a receiver who played and caught nothing looks "out", and there is
# no line here for offensive linemen, who do not show in a box score.
#
# Needs the box scores first: Rscript scripts/research/pull_box_scores.R
# Run from the project root:
#   Rscript scripts/research/starters_out.R

source(file.path("scripts", "research", "common.R"))
data <- load_research_data()
games <- data$games

CORE <- c(rush = 1, rec = 3, def = 6)
MIN_GAMES <- 3

game_files <- list.files(file.path(PATHS$snapshots, "games"), pattern = "^[0-9]{4}\\.csv$", full.names = TRUE)
schedule <- do.call(rbind, lapply(game_files, function(f) {
  read_snapshot(f)[c("game_id", "season", "start_date", "home_id", "away_id", "home_team", "away_team")]
}))
box_files <- list.files(file.path("data", "research", "box"), pattern = "\\.csv\\.gz$", full.names = TRUE)
box <- do.call(rbind, lapply(box_files, utils::read.csv, stringsAsFactors = FALSE,
                             colClasses = c(athlete_id = "character")))
box <- passing_with_teams(box, schedule)
box$season <- schedule$season[match(box$game_id, schedule$game_id)]

# One row per team per game: how many core players were out, by unit, and
# the share of the team's production so far that they stood for.
team_absences <- function(team) {
  game_ids <- unique(team$game_id[order(team$start_date, team$game_id)])
  totals <- list(rush = numeric(), rec = numeric(), def = numeric())
  out <- vector("list", length(game_ids))
  previous <- NULL
  for (i in seq_along(game_ids)) {
    here <- team[team$game_id == game_ids[i], , drop = FALSE]
    row <- data.frame(game_id = game_ids[i], team_id = team$team_id[1], rush_out = 0, rec_out = 0, def_out = 0,
                      off_share = 0, def_share = 0, counted = as.integer(i > MIN_GAMES))
    if (i > MIN_GAMES) {
      played <- unique(here$athlete_id)
      share <- c(rush = 0, rec = 0, def = 0)
      for (kind in names(CORE)) {
        so_far <- sort(totals[[kind]], decreasing = TRUE)
        core <- utils::head(so_far, CORE[[kind]])
        missing <- !names(core) %in% played
        row[[paste0(kind, "_out")]] <- sum(missing)
        share[[kind]] <- sum(core[missing]) / max(sum(so_far), 1)
      }
      row$off_share <- (share[["rush"]] + share[["rec"]]) / 2
      row$def_share <- share[["def"]]
    }
    row$prev_out <- if (is.null(previous)) 0 else previous$rush_out + previous$rec_out + previous$def_out
    out[[i]] <- row
    previous <- row
    for (kind in names(CORE)) {
      rows <- here[here$kind == kind, , drop = FALSE]
      add <- tapply(rows$count, rows$athlete_id, sum)
      ids <- union(names(totals[[kind]]), names(add))
      merged <- stats::setNames(numeric(length(ids)), ids)
      merged[names(totals[[kind]])] <- totals[[kind]]
      merged[names(add)] <- merged[names(add)] + add
      totals[[kind]] <- merged
    }
  }
  do.call(rbind, out)
}
absences <- do.call(rbind, lapply(split(box, list(box$season, box$team_id), drop = TRUE), team_absences))
absences$all_out <- absences$rush_out + absences$rec_out + absences$def_out
absences$many_out <- as.integer(absences$all_out >= 3)
absences$def_many <- as.integer(absences$def_out >= 2)

flags <- c(
  all_out = "Core players out (count)",
  many_out = "3 or more core players out",
  rush_out = "Top rusher out",
  rec_out = "Top-3 receivers out (count)",
  def_out = "Top-6 tacklers out (count)",
  def_many = "2 or more top tacklers out",
  off_share = "Share of offense's touches missing",
  def_share = "Share of defense's tackles missing",
  prev_out = "Core players who missed the last game (known before kickoff)"
)
side <- function(id_column, flag) {
  at <- match(paste(games$game_id, games[[id_column]]), paste(absences$game_id, absences$team_id))
  ifelse(is.na(at), 0, absences[[flag]][at])
}
for (flag in names(flags)) games[[flag]] <- side("home_id", flag) - side("away_id", flag)

counted <- absences[absences$counted == 1, ]
cat("Team-games counted:", nrow(counted), "\n")
cat(sprintf("  top rusher out: %.1f%%   a top-3 receiver out: %.1f%%   a top-6 tackler out: %.1f%%   3+ out: %.1f%%\n\n",
            100 * mean(counted$rush_out > 0), 100 * mean(counted$rec_out > 0), 100 * mean(counted$def_out > 0),
            100 * mean(counted$many_out)))

cat("Flag: games where the two teams differ, points worse than our line per unit, and against the market\n")
fit <- games[games$season %in% FIT_SEASONS, ]
for (flag in names(flags)) {
  hit <- fit[[flag]] != 0
  slope <- function(target) -stats::coef(stats::lm(target[hit] ~ 0 + fit[[flag]][hit]))[[1]]
  market_rows <- hit & !is.na(fit$line)
  market <- -stats::coef(stats::lm((fit$home_margin - fit$line)[market_rows] ~ 0 + fit[[flag]][market_rows]))[[1]]
  cat(sprintf("%-62s %5d  %+6.2f  %+6.2f\n", flags[[flag]], sum(hit), slope(fit$home_margin - fit$pred), market))
}
cat("\n")
print_verdicts(games, flags)
