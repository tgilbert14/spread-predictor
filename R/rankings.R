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

# The two rankings of our own that the Rankings tab can list teams by.
RANKING_KINDS <- c(blend = "Who would win", earned = "Who has earned it")

# The columns the Rankings table can sort by. Each has a hidden numeric key
# after the visible columns. "other" is whichever of our two rankings the
# table is not listed by.
RANKINGS_SORTED <- c("rank", "change", "rating", names(MODEL_LABELS), "other", "committee_style",
                     names(POLL_NAMES))

#' The Rankings table's visible column headings.
#'
#' @param by "blend" or "earned": the ranking the table is listed by. The
#'   other one gets its own column.
rankings_headers <- function(by = "blend") {
  c("", "Move", "Team", "Record", "Rating", unname(MODEL_LABELS),
    if (by == "earned") "Would win" else "Earned", "CFP guess", unname(POLL_LABELS))
}
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
#'   record, rating (the blend, in points), each system's rank, earned (our
#'   who-has-earned-it rank) and earned_change, committee_style (our guess
#'   at the committee's rank), and the committee's and AP's rank (NA when
#'   unranked or not released).
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
  style <- committee_style(app_data, week)
  at <- match(out$team_id, style$team_id)
  out$committee_style <- style$committee_style[at]
  out$earned <- style$earned[at]
  earlier <- committee_style(app_data, before)
  out$earned_change <- earlier$earned[match(out$team_id, earlier$team_id)] - out$earned
  polls <- app_data$polls[app_data$polls$week == week, , drop = FALSE]
  for (poll in names(POLL_NAMES)) {
    released <- polls[polls$poll == poll, , drop = FALSE]
    out[[poll]] <- released$rank[match(out$team_id, released$team_id)]
  }
  out <- out[!is.na(out$rank), , drop = FALSE]
  out <- out[order(out$rank, out$team_id), c("rank", "change", "team_id", "record", "rating",
                                             names(MODEL_LABELS), "earned", "earned_change",
                                             "committee_style", names(POLL_NAMES))]
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
  others <- c(committee_style = "Our CFP guess", earned = "Who has earned it (ours)",
              blend = "Who would win (ours)", MODEL_LABELS, ap = "AP poll")
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

# The committee-style ranking ---------------------------------------------------

#' Every team's resume from the games it has played.
#'
#' Record strength is the heart of it: for each game, did the team win,
#' minus how often a reference team (about the 10th best in the country)
#' would have won that game at that site. Beating good teams adds a lot,
#' beating weak ones adds little, and losing to a weak one costs the most.
#'
#' @param played Finished games: home_id, away_id, home_points, away_points,
#'   neutral_site.
#' @param power Each FBS team's Power rating, named by team id. An opponent
#'   not in it (an FCS team) counts as the weakest team that is.
#' @param tier 1 for a power-conference team, 0 otherwise, named by team id.
#' @param sigma How far games land from a prediction, for the win chances.
#' @param reference_rank Which team to measure against: 10 is the 10th best.
#' @param home_field Points the home team gets, in the same units as `power`.
#' @return One row per team in `power` that has played: team_id, wins,
#'   losses, record_strength, schedule (average opponent Power), top25_wins
#'   (wins over the top 25 by Power), power and tier.
team_resumes <- function(played, power, tier, sigma, reference_rank = COMMITTEE_MODEL$reference_rank,
                         home_field = POWER_RATING$home_field) {
  power <- power[!is.na(power)]
  best_first <- sort(power, decreasing = TRUE)
  reference <- best_first[min(reference_rank, length(best_first))]
  top25 <- names(best_first)[seq_len(min(25, length(best_first)))]
  at_home <- 1 - as.numeric(played$neutral_site)

  sides <- rbind(
    data.frame(team_id = played$home_id, opponent = played$away_id, site = at_home,
               won = played$home_points > played$away_points),
    data.frame(team_id = played$away_id, opponent = played$home_id, site = -at_home,
               won = played$away_points > played$home_points)
  )
  sides <- sides[as.character(sides$team_id) %in% names(power), , drop = FALSE]
  sides$opponent_power <- unname(power[as.character(sides$opponent)])
  sides$opponent_power[is.na(sides$opponent_power)] <- min(power)
  expected <- stats::pnorm((reference - sides$opponent_power + home_field * sides$site) / sigma)
  sides$above <- sides$won - expected
  sides$top25_win <- sides$won & as.character(sides$opponent) %in% top25

  ids <- names(power)[names(power) %in% as.character(sides$team_id)]
  total <- function(values, f = sum) unname(tapply(values, as.character(sides$team_id), f)[ids])
  data.frame(
    team_id = as.integer(ids),
    wins = total(sides$won), losses = total(!sides$won),
    record_strength = total(sides$above),
    schedule = total(sides$opponent_power, mean),
    top25_wins = total(sides$top25_win),
    power = unname(power[ids]), tier = unname(tier[ids])
  )
}

#' The committee-style score for each resume: higher is better.
committee_score <- function(resumes, weights = COMMITTEE_MODEL$weights) {
  drop(as.matrix(resumes[names(weights)]) %*% weights)
}

#' Our two results rankings for one week.
#'
#' `earned` is our own answer to "who deserves it": teams in order of
#' record strength and nothing else. No credit for looking good, no bonus
#' for a conference. `committee_style` is our guess at the committee: the
#' same resumes scored the way the committee has scored teams in past
#' seasons, which does give credit for both.
#'
#' Both use only games played before that week and our own Power rating
#' (to judge how hard each opponent was), so they can be made any week.
#'
#' @return team_id, earned and committee_style (ranks, 1 is best) for every
#'   team that has played a game. No rows before any games.
committee_style <- function(app_data, week = app_data$meta$week) {
  teams <- app_data$teams
  rated <- app_data$history[app_data$history$week == week, , drop = FALSE]
  power <- stats::setNames(rated$power, rated$team_id)
  played <- app_data$results[app_data$results$week < week, , drop = FALSE]
  if (nrow(played) == 0 || all(is.na(power))) {
    return(data.frame(team_id = integer(), earned = integer(), committee_style = integer()))
  }
  resumes <- team_resumes(played, power, stats::setNames(teams$tier, teams$team_id), app_data$params$sigma)
  ranked <- function(score) as.integer(rank(-score, ties.method = "min"))
  data.frame(team_id = resumes$team_id, earned = ranked(resumes$record_strength),
             committee_style = ranked(committee_score(resumes)))
}

