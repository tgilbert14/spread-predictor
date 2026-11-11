# Shared setup for the research scripts in this folder. Each script tests
# ideas that did not make it into the model, with the same keep rule as
# scripts/backtest.R, and prints its table. Results and what they mean are
# written up by hand in docs/research-log.md.
#
# The scripts read cfb.sqlite read-only and change nothing. Run them from
# the project root, for example:
#   Rscript scripts/research/travel.R

for (file in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(file)

#' Everything the research scripts start from.
#'
#' @return games (the backtest set, with `pred`, our out-of-sample house
#'   line, and `date`), all_games (every game of every class since the
#'   burn-in season, for looking up a team's previous and next game, with
#'   `line`, the closing line as a home margin, where there is one) and
#'   power (pregame Power ratings by game).
load_research_data <- function() {
  con <- connect_readonly(PATHS$database)
  on.exit(DBI::dbDisconnect(con))
  all_games <- query_sql_file(con, "rating_games.sql", list(BURN_IN_SEASON))
  power <- power_ratings(all_games, query_sql_file(con, "team_conferences.sql"))$pregame
  closing <- median_spread(query_sql_file(con, "lines.sql"))
  all_games$line <- -closing$spread[match(all_games$game_id, closing$game_id)]
  games <- backtest_games(con)
  games$pred <- house_predictions(games)
  games$date <- as.Date(substr(games$start_date, 1, 10))
  list(games = games, all_games = all_games, power = power)
}

#' Judge candidates with the usual keep rule and print one line each.
#'
#' Each candidate is one column of `games`, added to both house models.
#' Negative changes mean the candidate helps.
#'
#' @param candidates Labels, named by column.
print_verdicts <- function(games, candidates) {
  width <- max(nchar(candidates))
  for (column in names(candidates)) {
    result <- judge_candidate(games, list(label = candidates[[column]], elo = column, power = column), column)
    cat(sprintf("%-*s  CV %+.3f [%+.3f, %+.3f]  holdout %+.3f  %s\n", width, candidates[[column]],
                result$cv_change, result$cv_low, result$cv_high, result$holdout_change, result$verdict))
  }
}

#' Pregame Power cutoff for the top `n` FBS teams, by season and week.
#'
#' @return A function: given rows of `all_games`, the cutoff for each row.
power_cutoff <- function(all_games, power, n, fbs_teams = 134) {
  at <- match(all_games$game_id, power$game_id)
  key <- paste(all_games$season, all_games$week, all_games$season_type)
  cutoffs <- tapply(c(power$home_power[at], power$away_power[at]), c(key, key),
                    stats::quantile, probs = 1 - n / fbs_teams, na.rm = TRUE)
  function(rows) cutoffs[paste(rows$season, rows$week, rows$season_type)]
}
