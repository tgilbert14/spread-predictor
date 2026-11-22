# The projected playoff field: the 2026-27 bid rules (PLAYOFF in
# R/config.R) applied to a ranking, and the conference title games that
# decide four of the bids.

#' Each conference's title game winner, once it has been played.
#'
#' The data has no flag for title games, so they are found by when they
#' are played: each conference's one game against itself on the weekend
#' of the first Saturday in December (Thursday to Sunday, US time).
#' Rivalry games the weekend before and Army-Navy the week after fall
#' outside it. Now and then a postponed game is made up that weekend too
#' (Cal and Stanford in 2018); then the neutral-site game is the title game.
#' A conference still with more than one is left out rather than guessed.
#'
#' @param results Finished games: start_date (UTC), neutral_site, home_id,
#'   away_id, home_points, away_points.
#' @param teams The teams table, for conferences.
#' @return Rows of conference, team_id (the winner) and week. No rows
#'   before the title games are played.
conference_champions <- function(results, teams) {
  none <- data.frame(conference = character(), team_id = integer(), week = integer())
  if (nrow(results) == 0) return(none)
  # Late kickoffs on the West Coast are the next day in UTC.
  local_day <- as.Date(parse_utc(results$start_date) - 8 * 3600)
  december_1 <- as.Date(sprintf("%s-12-01", format(max(local_day), "%Y")))
  first_saturday <- december_1 + (6 - as.integer(format(december_1, "%w"))) %% 7
  home_conf <- teams$conference[match(results$home_id, teams$team_id)]
  away_conf <- teams$conference[match(results$away_id, teams$team_id)]
  title <- results[!is.na(home_conf) & !is.na(away_conf) & home_conf == away_conf & home_conf != "FBS Independents" &
                     local_day >= first_saturday - 2 & local_day <= first_saturday + 1, , drop = FALSE]
  if (nrow(title) == 0) return(none)
  title$conference <- teams$conference[match(title$home_id, teams$team_id)]
  shared <- title$conference %in% title$conference[duplicated(title$conference)]
  title <- title[!shared | title$neutral_site %in% TRUE, , drop = FALSE]
  title <- title[!title$conference %in% title$conference[duplicated(title$conference)], , drop = FALSE]
  if (nrow(title) == 0) return(none)
  winner <- ifelse(title$home_points > title$away_points, title$home_id, title$away_id)
  data.frame(conference = title$conference, team_id = as.integer(winner), week = as.integer(title$week))
}

#' Build the 12-team field from a ranking.
#'
#' Once a Power Four title game is played, its winner takes that bid. Until
#' then, each conference's champion is projected as its best-ranked team.
#'
#' @param ranking Rows of rank and team_id, best first. Our prediction of
#'   the committee's ranking, or the committee's own.
#' @param teams The teams table, for conferences and names.
#' @param champions What conference_champions() returns, or NULL.
#' @return One row per team in the field, by seed: seed, team_id, rank and
#'   how (why it is in: "Big Ten champion", "Big Ten leader" before its
#'   title game, "Group of Six", "Notre Dame", "At-large"). Fewer rows only
#'   if the ranking is too short. A champion the ranking leaves out is seeded
#'   last, with rank NA.
playoff_field <- function(ranking, teams, champions = NULL, rules = PLAYOFF) {
  ranking <- ranking[order(ranking$rank), c("rank", "team_id"), drop = FALSE]
  ranking$conference <- teams$conference[match(ranking$team_id, teams$team_id)]
  ranking$school <- teams$school[match(ranking$team_id, teams$team_id)]
  picks <- list()
  take <- function(row, how) picks[[length(picks) + 1]] <<- data.frame(team_id = row$team_id, rank = row$rank, how = how)

  for (conference in rules$power_four) {
    won <- champions$team_id[champions$conference %in% conference]
    if (length(won) == 1) {
      row <- ranking[ranking$team_id %in% won, , drop = FALSE]
      if (nrow(row) == 0) row <- data.frame(rank = NA_integer_, team_id = won)
      take(row[1, ], paste(conference, "champion"))
      next
    }
    best <- ranking[ranking$conference %in% conference, , drop = FALSE]
    if (nrow(best) > 0) take(best[1, ], paste(conference, "leader"))
  }
  small <- ranking[ranking$conference %in% rules$group_of_six, , drop = FALSE]
  if (nrow(small) > 0) take(small[1, ], "Group of Six")
  irish <- ranking[ranking$school %in% rules$notre_dame & ranking$rank <= rules$notre_dame_top, , drop = FALSE]
  chosen <- function() vapply(picks, function(p) as.numeric(p$team_id), numeric(1))
  if (nrow(irish) > 0 && !irish$team_id %in% chosen()) take(irish[1, ], "Notre Dame")

  for (i in seq_len(nrow(ranking))) {
    if (length(picks) >= rules$size) break
    if (!ranking$team_id[i] %in% chosen()) take(ranking[i, ], "At-large")
  }
  field <- do.call(rbind, picks)
  field <- field[order(field$rank, na.last = TRUE), , drop = FALSE]
  field$seed <- seq_len(nrow(field))
  rownames(field) <- NULL
  field[c("seed", "team_id", "rank", "how")]
}

#' What each seed does first: a bye, or the seed it plays and who hosts.
#'
#' @return One sentence per seed, in the order of `field`.
first_round <- function(field, teams, rules = PLAYOFF) {
  n <- nrow(field)
  school <- function(seed) teams$school[match(field$team_id[seed], teams$team_id)]
  vapply(field$seed, function(seed) {
    if (seed <= rules$byes) return("Bye to the quarterfinals")
    other <- n + rules$byes + 1 - seed
    if (other < 1 || other > n) return("")
    if (seed < other) sprintf("Hosts No. %d %s", other, school(other)) else sprintf("At No. %d %s", other, school(other))
  }, character(1))
}
