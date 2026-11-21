# Rankings: our Top 50, every system's own ranking beside it, and the
# committee's and the AP's for comparison.
#
# Our ranking is the blend the spread uses, turned into one number per team:
# how many points better than an average team it is on a neutral field. So
# the gap between two teams' ratings is exactly our neutral-site line for
# them. It ranks who would win, not who has earned the most. The committee
# and the AP poll rank the second thing, which is why they sit beside ours
# and are never mixed into it.

# Polls shown in the app, by the name the API gives them.
POLL_NAMES <- c(cfp = "Playoff Committee Rankings", ap = "AP Top 25")
POLL_LABELS <- c(cfp = "CFP", ap = "AP")

# How many teams the Rankings tab lists before "Show every team" is ticked.
RANKINGS_SHOWN <- 50

# The Rankings table's visible columns, then the columns it can sort by.
# Each sortable column has a hidden numeric key after the visible ones.
RANKINGS_VISIBLE <- c("", "Move", "Team", "Record", "Rating",
                      unname(MODEL_LABELS), unname(POLL_LABELS))
RANKINGS_SORTED <- c("rank", "change", "rating", names(MODEL_LABELS), names(POLL_NAMES))
# A team with no rank in a column sorts after every team that has one.
UNRANKED_KEY <- 999

#' This season's committee and AP rankings, matched to team ids.
#'
#' The rankings file is saved as the API returns it, with school names. A
#' ranked school that is not in the teams table (an FCS team in the AP poll,
#' say) is left out.
#'
#' @param root data/snapshots.
#' @param teams The season's teams, for the ids.
#' @return Rows of week, poll ("cfp" or "ap"), rank and team_id. No rows
#'   when the season has no rankings file yet.
load_polls <- function(root, season, teams) {
  empty <- data.frame(week = integer(), poll = character(), rank = integer(), team_id = integer(),
                      stringsAsFactors = FALSE)
  path <- extra_path("rankings", season, root)
  if (!file.exists(path)) return(empty)
  raw <- read_snapshot(path)
  raw <- select_columns(raw, list(
    season_type = c("season_type", "seasonType"), week = "week", poll = "poll",
    rank = "rank", school = "school"
  ), what = "poll rankings")
  raw <- raw[raw$season_type == "regular" & raw$poll %in% POLL_NAMES & !is.na(raw$rank), , drop = FALSE]
  if (nrow(raw) == 0) return(empty)
  polls <- data.frame(
    week = as.integer(raw$week),
    poll = names(POLL_NAMES)[match(raw$poll, POLL_NAMES)],
    rank = as.integer(raw$rank),
    team_id = as.integer(teams$team_id[match(team_key(raw$school), team_key(teams$school))]),
    stringsAsFactors = FALSE
  )
  polls <- polls[!is.na(polls$team_id), , drop = FALSE]
  polls <- polls[order(polls$week, polls$poll, polls$rank), , drop = FALSE]
  rownames(polls) <- NULL
  polls
}

#' Every team's rating in each system, in points, and the blend.
#'
#' Each system's rating is put on the scale its margins use (the same
#' arithmetic as rating_margins() and preseason_points() in R/predict.R),
#' then centered so the average rated team is 0. The blend weights the
#' systems a team has. For two teams rated by every system, the gap between
#' their blends is predict_matchup()'s neutral-site spread.
#'
#' @param week The regular-season week, for the preseason points Elo and
#'   Power get early on. NULL adds none.
#' @return A data frame: team_id, one column of points per system, and blend.
team_points <- function(teams, params, week = NULL) {
  models <- names(MODEL_LABELS)
  points <- teams[models]
  public <- params$public_scale
  for (model in models) {
    scale <- if (is.null(public)) NA else public$scale[match(model, public$model)]
    if (!is.na(scale)) points[[model]] <- points[[model]] * scale
  }
  points$elo <- teams$elo / params$k + params$elo_tier * teams$tier
  points$power <- params$power_scale * teams$power

  fade <- if (is.null(week)) 0 else preseason_fade(week)
  if (fade > 0) {
    z <- function(column) ifelse(is.na(teams[[column]]), 0, teams[[column]])
    early <- fade * (params$talent_points * z("talent_z") + params$returning_points * z("returning_z"))
    points$elo <- points$elo + early
    points$power <- points$power + early
  }
  for (model in models) points[[model]] <- points[[model]] - mean(points[[model]], na.rm = TRUE)

  weights <- vapply(models, function(m) as.numeric(params$weights[[m]]), numeric(1))
  values <- as.matrix(points)
  used <- sweep(!is.na(values), 2, weights, `*`)
  blend <- rowSums(ifelse(is.na(values), 0, values) * used) / rowSums(used)
  cbind(team_id = teams$team_id, points, blend = ifelse(is.finite(blend), blend, NA_real_))
}

#' Wins and losses going into a week, per team.
#'
#' @param results app_data$results: this season's finished games.
#' @param week Only games from earlier weeks count.
#' @return "8-2" style records, one per team id, "" for a team with no games.
records_before <- function(results, week, team_ids) {
  played <- results[results$week < week, , drop = FALSE]
  home_won <- played$home_points > played$away_points
  winners <- ifelse(home_won, played$home_id, played$away_id)
  losers <- ifelse(home_won, played$away_id, played$home_id)
  wins <- table(factor(winners, levels = team_ids))
  losses <- table(factor(losers, levels = team_ids))
  as.vector(ifelse(wins + losses == 0, "", sprintf("%d-%d", wins, losses)))
}

#' The full ranking for one week: every team, best first.
#'
#' @param week A week the app holds (snapshot_weeks()).
#' @return One row per team with a blend rating: rank, change (places gained
#'   since the week before, NA when there is no fair comparison), team_id,
#'   record, rating (the blend, in points), each system's rank, and the
#'   committee's and AP's rank (NA when unranked or not released).
ranking_table <- function(app_data, week = app_data$meta$week) {
  teams <- snapshot_teams(app_data, week)
  ranked <- function(x) as.integer(rank(-x, ties.method = "min", na.last = "keep"))
  blend <- team_points(teams, app_data$params, week)$blend

  out <- data.frame(rank = ranked(blend), team_id = teams$team_id, rating = blend)
  out$change <- out$rank * NA_integer_
  # Places moved since last week only mean something when both weeks blend
  # the same systems. Otherwise a team "moves" because the yardstick changed.
  before <- week - 1L
  if (before %in% snapshot_weeks(app_data) &&
      setequal(models_missing_in_week(app_data$history, before),
               models_missing_in_week(app_data$history, week))) {
    then <- snapshot_teams(app_data, before)
    then_rank <- ranked(team_points(then, app_data$params, before)$blend)
    out$change <- then_rank[match(out$team_id, then$team_id)] - out$rank
  }
  out$record <- records_before(app_data$results, week, teams$team_id)
  for (model in names(MODEL_LABELS)) out[[model]] <- teams[[paste0(model, "_rank")]]
  polls <- app_data$polls[app_data$polls$week == week, , drop = FALSE]
  for (poll in names(POLL_NAMES)) {
    released <- polls[polls$poll == poll, , drop = FALSE]
    out[[poll]] <- released$rank[match(out$team_id, released$team_id)]
  }
  out <- out[!is.na(out$rank), , drop = FALSE]
  out <- out[order(out$rank, out$team_id), c("rank", "change", "team_id", "record", "rating",
                                             names(MODEL_LABELS), names(POLL_NAMES))]
  rownames(out) <- NULL
  out
}

#' How closely each ranking tracks the committee's, for one week.
#'
#' For each of the committee's ranked teams, how many places away does the
#' other ranking have it? The average of those gaps is the score. A team the
#' AP leaves unranked counts as one place past its last ranked team.
#'
#' @param ranking What ranking_table() returns for a week with a committee
#'   release.
#' @return One row per ranking, closest first: id, label, avg_gap, n (the
#'   committee teams it could be compared on). No rows without a release.
committee_similarity <- function(ranking) {
  committee <- ranking[!is.na(ranking$cfp), , drop = FALSE]
  others <- c(blend = "Our blend", MODEL_LABELS, ap = "AP poll")
  if (nrow(committee) == 0) {
    return(data.frame(id = character(), label = character(), avg_gap = numeric(), n = integer()))
  }
  rows <- lapply(names(others), function(id) {
    theirs <- if (id == "blend") committee$rank else committee[[id]]
    if (id == "ap" && any(!is.na(ranking$ap))) theirs[is.na(theirs)] <- max(ranking$ap, na.rm = TRUE) + 1L
    gaps <- abs(theirs - committee$cfp)
    data.frame(id = id, label = others[[id]], avg_gap = mean(gaps, na.rm = TRUE),
               n = sum(!is.na(gaps)), stringsAsFactors = FALSE)
  })
  out <- do.call(rbind, rows)
  out <- out[out$n > 0, , drop = FALSE]
  out <- out[order(out$avg_gap), , drop = FALSE]
  rownames(out) <- NULL
  out
}
