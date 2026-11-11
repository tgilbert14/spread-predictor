# Three related ideas:
#   1. The field is more even some years, so the scale that turns a rating
#      gap into a spread should change by season.
#   2. Results against strong opponents should count differently.
#   3. An opponent should be judged by how good it turned out to be, not by
#      its rating on game day.
#
# Result (Nov 2026): the field does change, but the ratings are in points
# and already carry it. Nothing passes the keep rule. Idea 3 is already how
# the Power rating works, and patching Elo for it changes nothing.
# See docs/research-log.md.

source(file.path("scripts", "research", "common.R"))
data <- load_research_data()
games <- data$games
all_games <- data$all_games
power <- data$power
games$miss <- games$home_margin - games$pred

# ---- 1. The field by season --------------------------------------------------

at <- match(all_games$game_id, power$game_id)
ratings <- rbind(
  data.frame(season = all_games$season, team_id = all_games$home_id, class = all_games$home_class,
             power = power$home_power[at], start_date = all_games$start_date),
  data.frame(season = all_games$season, team_id = all_games$away_id, class = all_games$away_class,
             power = power$away_power[at], start_date = all_games$start_date)
)
ratings <- ratings[ratings$class == "fbs" & !is.na(ratings$power), ]
ratings <- ratings[order(ratings$season, ratings$team_id, ratings$start_date), ]
# Each team's rating before its last game of the season.
late <- ratings[!duplicated(ratings[c("season", "team_id")], fromLast = TRUE), ]

cat("Season: spread of ratings (SD), top 10 minus teams 11 to 25, best-fit scale on our spreads, our MAE, market MAE\n")
for (season in sort(unique(games$season))) {
  ranked <- sort(late$power[late$season == season], decreasing = TRUE)
  rows <- games[games$season == season, ]
  scale <- stats::coef(stats::lm(home_margin ~ 0 + pred, data = rows))[[1]]
  cat(sprintf("%d  %5.1f  %5.1f  %5.2f  %6.2f  %6.2f\n", season, stats::sd(ranked),
              mean(ranked[1:10]) - mean(ranked[11:25]), scale, mean(abs(rows$miss)),
              mean(abs(rows$home_margin - rows$line))))
}

# ---- 2 and 3. Candidates ------------------------------------------------------

top25 <- power_cutoff(all_games, power, 25)
in_all <- match(games$game_id, all_games$game_id)
cutoff <- top25(all_games[in_all, ])
games$home_top25 <- power$home_power[at][in_all] >= cutoff
games$away_top25 <- power$away_power[at][in_all] >= cutoff

games$since_2021 <- as.integer(games$season >= 2021)
games$trend <- games$season - mean(FIT_SEASONS)
games$late <- as.integer(games$season_type == "postseason" | games$week >= 9)
games$top_matchup <- as.integer(games$home_top25 & games$away_top25)

#' A running average per team, as home minus away.
#'
#' For each team, the average of its misses against our line over its
#' earlier games this season that count, with `shrink` extra games at zero.
#'
#' @param counts_home,counts_away Which games count for the home team and
#'   for the away team.
earlier_average <- function(counts_home, counts_away, shrink) {
  sides <- rbind(
    data.frame(row = seq_len(nrow(games)), season = games$season, team_id = games$home_id,
               date = games$date, miss = games$miss, counts = counts_home, sign = 1),
    data.frame(row = seq_len(nrow(games)), season = games$season, team_id = games$away_id,
               date = games$date, miss = -games$miss, counts = counts_away, sign = -1)
  )
  sides <- sides[order(sides$season, sides$team_id, sides$date, sides$row), ]
  team <- paste(sides$season, sides$team_id)
  counted <- ifelse(sides$counts, sides$miss, 0)
  earlier_sum <- stats::ave(counted, team, FUN = cumsum) - counted
  earlier_n <- stats::ave(as.numeric(sides$counts), team, FUN = cumsum) - sides$counts
  as.numeric(tapply(sides$sign * earlier_sum / (earlier_n + shrink), sides$row, sum))
}
# A game against a top-25 opponent counts for the team that faced it.
games$big_game <- earlier_average(games$away_top25, games$home_top25, shrink = 2)

# Idea 3, for Elo: have a team's earlier opponents gotten better or worse
# since they played? For each one, its Elo now minus its Elo on game day,
# averaged with two extra games at zero.
con <- connect_readonly(PATHS$database)
completed <- load_completed_games(con)
DBI::dbDisconnect(con)
completed$date <- as.Date(substr(completed$start_date, 1, 10))
elo <- rbind(
  data.frame(season = completed$season, date = completed$date, team_id = completed$home_id,
             elo = completed$home_pregame_elo, opp_id = completed$away_id, opp_elo = completed$away_pregame_elo),
  data.frame(season = completed$season, date = completed$date, team_id = completed$away_id,
             elo = completed$away_pregame_elo, opp_id = completed$home_id, opp_elo = completed$home_pregame_elo)
)
elo <- elo[order(elo$season, elo$team_id, elo$date), ]
by_team <- split(elo, paste(elo$season, elo$team_id))
opponent_drift <- function(season, team_id, date) {
  played <- by_team[[paste(season, team_id)]]
  played <- played[played$date < date, ]
  if (is.null(played) || nrow(played) == 0) return(0)
  elo_now <- vapply(played$opp_id, function(opp) {
    history <- by_team[[paste(season, opp)]]
    history <- history[history$date <= date, ]
    if (is.null(history) || nrow(history) == 0) NA_real_ else history$elo[nrow(history)]
  }, numeric(1))
  change <- elo_now - played$opp_elo
  sum(change, na.rm = TRUE) / (sum(!is.na(change)) + 2)
}
games$drift <- mapply(opponent_drift, games$season, games$home_id, games$date) -
  mapply(opponent_drift, games$season, games$away_id, games$date)

scale_terms <- list(
  since_2021 = "Different scale since 2021 (NIL and portal era)",
  trend = "Scale drifts year to year",
  late = "Different scale late in the season",
  top_matchup = "Different scale when two top-25 teams meet"
)
cat("\nScale candidates: each multiplies the rating gap\n")
width <- max(nchar(unlist(scale_terms)))
for (column in names(scale_terms)) {
  result <- judge_candidate(games, list(label = scale_terms[[column]],
                                        elo = paste0("elo_gap:", column),
                                        power = paste0("power_gap:", column)), column)
  cat(sprintf("%-*s  CV %+.3f [%+.3f, %+.3f]  holdout %+.3f  %s\n", width, scale_terms[[column]],
              result$cv_change, result$cv_low, result$cv_high, result$holdout_change, result$verdict))
}
cat("\nOpponent-tier candidates\n")
print_verdicts(games, c(
  big_game = "How a team has played against top-25 opponents this season",
  form_diff = "How a team has played against our line this season, all games",
  drift = "Earlier opponents' Elo now against their Elo on game day"
))

# ---- 1 again. Re-fit the scale as each season goes -----------------------------

# Stretch or shrink our spread by how the season's earlier games have gone:
# the slope of the miss on the spread so far, pulled toward zero by
# `shrink_games` games' worth of an average spread.
running_scale <- function(shrink_games) {
  adjust <- numeric(nrow(games))
  penalty <- shrink_games * mean(games$pred^2)
  for (season in unique(games$season)) {
    rows <- which(games$season == season)
    for (i in rows) {
      earlier <- rows[games$date[rows] < games$date[i]]
      adjust[i] <- sum(games$pred[earlier] * games$miss[earlier]) / (sum(games$pred[earlier]^2) + penalty)
    }
  }
  abs(games$home_margin - games$pred * (1 + adjust)) - abs(games$miss)
}
cat("\nScale re-fit as each season goes\n")
for (shrink_games in c(300, 100)) {
  change <- running_scale(shrink_games)
  cv <- paired_bootstrap(change[games$season %in% FIT_SEASONS])
  cat(sprintf("Shrunk by %d games  CV %+.3f [%+.3f, %+.3f]  holdout %+.3f\n", shrink_games,
              cv[["change"]], cv[["low"]], cv[["high"]], mean(change[games$season == HOLDOUT_SEASON])))
}
