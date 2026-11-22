# The projected playoff field: the 2026-27 bid rules (PLAYOFF in
# R/config.R) applied to a ranking.

#' Build the 12-team field from a ranking.
#'
#' Until the conference title games are played, each conference's champion
#' is projected as its best-ranked team.
#'
#' @param ranking Rows of rank and team_id, best first. Our prediction of
#'   the committee's ranking, or the committee's own.
#' @param teams The teams table, for conferences and names.
#' @return One row per team in the field, by seed: seed, team_id, rank and
#'   how (why it is in: "Big Ten champion", "Group of Six", "Notre Dame",
#'   "At-large"). Fewer rows only if the ranking is too short.
playoff_field <- function(ranking, teams, rules = PLAYOFF) {
  ranking <- ranking[order(ranking$rank), c("rank", "team_id"), drop = FALSE]
  ranking$conference <- teams$conference[match(ranking$team_id, teams$team_id)]
  ranking$school <- teams$school[match(ranking$team_id, teams$team_id)]
  picks <- list()
  take <- function(row, how) picks[[length(picks) + 1]] <<- data.frame(team_id = row$team_id, rank = row$rank, how = how)

  for (conference in rules$power_four) {
    best <- ranking[ranking$conference %in% conference, , drop = FALSE]
    if (nrow(best) > 0) take(best[1, ], paste(conference, "champion"))
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
  field <- field[order(field$rank), , drop = FALSE]
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
