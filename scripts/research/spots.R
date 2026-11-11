# Letdown, trap and look-ahead games: does a team play worse than its
# rating the week after a big win, or the week before a big game?
#
# Each spot is a flag on a team for one game, built from its previous or
# next game that season. A game's factor is the home team's flag minus the
# away team's. "Top 25" and "top 50" use our own pregame Power rating, so
# nothing here looks at later results.
#
# Result (Nov 2026): teams off an upset win run about a point worse than
# our line and teams off an upset loss about a point better, but no spot
# passes the keep rule. See docs/research-log.md.

source(file.path("scripts", "research", "common.R"))
data <- load_research_data()
games <- data$games
all_games <- data$all_games
power <- data$power

# How big an upset, and how big a beat of the line, counts.
UPSET_POINTS <- 7
BEAT_LINE_POINTS <- 14

at <- match(all_games$game_id, power$game_id)
all_games$home_power <- power$home_power[at]
all_games$away_power <- power$away_power[at]
all_games$margin <- all_games$home_points - all_games$away_points
top25 <- power_cutoff(all_games, power, 25)(all_games)
top50 <- power_cutoff(all_games, power, 50)(all_games)

#' One row per team per game, from that team's side.
team_side <- function(side) {
  other <- if (side == "home") "away" else "home"
  sign <- if (side == "home") 1 else -1
  opponent_power <- all_games[[paste0(other, "_power")]]
  data.frame(game_id = all_games$game_id, season = all_games$season, side = side,
             team_id = all_games[[paste0(side, "_id")]], start_date = all_games$start_date,
             margin = sign * all_games$margin, line = sign * all_games$line,
             opp_top25 = opponent_power >= top25, opp_top50 = opponent_power >= top50)
}
teams <- rbind(team_side("home"), team_side("away"))
teams <- teams[order(teams$season, teams$team_id, teams$start_date, teams$game_id), ]

n <- nrow(teams)
same_team_before <- c(FALSE, teams$season[-1] == teams$season[-n] & teams$team_id[-1] == teams$team_id[-n])
same_team_after <- c(same_team_before[-1], FALSE)
last_game <- function(x) ifelse(same_team_before, c(NA, x[-n]), NA)
next_game <- function(x) ifelse(same_team_after, c(x[-1], NA), NA)
flag <- function(x) as.integer(!is.na(x) & x)

won_last <- last_game(teams$margin) > 0
teams$upset_win <- flag(won_last & last_game(teams$line) <= -UPSET_POINTS)
teams$big_win <- flag(won_last & last_game(teams$opp_top25))
teams$beat_line <- flag(last_game(teams$margin) - last_game(teams$line) >= BEAT_LINE_POINTS)
teams$lookahead <- flag(next_game(teams$opp_top25) & !teams$opp_top50)
teams$sandwich <- flag(teams$big_win == 1 & !teams$opp_top50)
teams$bad_loss <- flag(!won_last & last_game(teams$line) >= UPSET_POINTS)
teams$revert <- teams$upset_win - teams$bad_loss

spots <- c(
  upset_win = "Last week: won as an underdog of 7 or more",
  big_win = "Last week: beat a top-25 team",
  beat_line = "Last week: beat the market line by 14 or more",
  lookahead = "Top-25 team next week, opponent outside the top 50 now",
  sandwich = "Beat a top-25 team, now facing a team outside the top 50",
  bad_loss = "Last week: lost as a favorite of 7 or more",
  revert = "Upset win and upset loss as one term"
)
home <- teams[teams$side == "home", ]
away <- teams[teams$side == "away", ]
for (spot in names(spots)) {
  games[[spot]] <- home[[spot]][match(games$game_id, home$game_id)] -
    away[[spot]][match(games$game_id, away$game_id)]
}

# How teams in each spot did against our line and against the market, in
# the fit seasons. Positive means better than predicted.
cat("Spot: games, points better than our line, points better than the market line\n")
fit <- games[games$season %in% FIT_SEASONS, ]
for (spot in names(spots)) {
  in_spot <- fit[[spot]] != 0
  vs_ours <- ((fit$home_margin - fit$pred) * fit[[spot]])[in_spot]
  vs_market <- ((fit$home_margin - fit$line) * fit[[spot]])[in_spot]
  cat(sprintf("%-58s %5d  %+5.2f  %+5.2f\n", spots[[spot]], sum(in_spot), mean(vs_ours), mean(vs_market)))
}
cat("\n")
print_verdicts(games, spots)
