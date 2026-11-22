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
  out$earned <- style$earned[at]
  # Our guess at the committee: from resumes alone before its first ranking,
  # from its last ranking and what has happened since after that.
  guess <- committee_forecast(app_data, week)
  out$committee_style <- guess$rank[match(out$team_id, guess$team_id)]
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
  resumes <- week_resumes(app_data, week)
  if (is.null(resumes)) {
    return(data.frame(team_id = integer(), earned = integer(), committee_style = integer()))
  }
  ranked <- function(score) as.integer(rank(-score, ties.method = "min"))
  data.frame(team_id = resumes$team_id, earned = ranked(resumes$record_strength),
             committee_style = ranked(committee_score(resumes)))
}

#' Every team's resume going into a week, or NULL when there is nothing to
#' judge yet (no games played, or no Power ratings for that week).
week_resumes <- function(app_data, week) {
  if (length(week) != 1 || is.na(week)) return(NULL)
  teams <- app_data$teams
  rated <- app_data$history[app_data$history$week == week, , drop = FALSE]
  power <- stats::setNames(rated$power, rated$team_id)
  played <- app_data$results[app_data$results$week < week, , drop = FALSE]
  if (nrow(played) == 0 || all(is.na(power))) return(NULL)
  team_resumes(played, power, stats::setNames(teams$tier, teams$team_id), app_data$params$sigma)
}

# Predicting the committee's next ranking -----------------------------------------

#' Which week's committee ranking comes next: the week after the latest one
#' whose games are all finished.
#'
#' A game still open two weeks after kickoff was cancelled, so it does not
#' hold its week back.
#'
#' @param progress Rows of week, games, completed and last_open_kickoff
#'   (week_progress.sql).
#' @return A week number, or NA before any week is finished.
forecast_week <- function(progress, now = Sys.time(), give_up_days = 14) {
  open_for <- as.numeric(difftime(now, parse_utc(progress$last_open_kickoff), units = "days"))
  finished <- progress$completed > 0 & (is.na(progress$last_open_kickoff) | open_for >= give_up_days)
  if (!any(finished)) return(NA_integer_)
  as.integer(max(progress$week[finished]) + 1L)
}

#' Our prediction of the committee's ranking for one week.
#'
#' Before the committee's first ranking of a season, teams are scored from
#' their resumes alone (COMMITTEE_MODEL). After that, the committee's last
#' ranking is the starting point, moved by what has happened since: new
#' losses and record strength gained (COMMITTEE_UPDATE). It uses only games
#' played before `week` and rankings released before it.
#'
#' @return Every team with a resume, best first: rank, team_id, score,
#'   prev_cfp (its place in the committee's last ranking, NA if unranked or
#'   there was none), and method ("resume" or "update"). No rows when there
#'   is nothing to go on.
committee_forecast <- function(app_data, week = app_data$meta$forecast_week) {
  empty <- data.frame(rank = integer(), team_id = integer(), score = numeric(), prev_cfp = integer(),
                      method = character(), stringsAsFactors = FALSE)
  resumes <- week_resumes(app_data, week)
  if (is.null(resumes)) return(empty)

  released <- app_data$polls[app_data$polls$poll == "cfp" & app_data$polls$week < week, , drop = FALSE]
  before <- if (nrow(released) > 0) week_resumes(app_data, max(released$week)) else NULL
  if (is.null(before)) {
    score <- committee_score(resumes)
    prev_cfp <- rep(NA_integer_, nrow(resumes))
    method <- "resume"
  } else {
    last <- released[released$week == max(released$week), , drop = FALSE]
    prev_cfp <- last$rank[match(resumes$team_id, last$team_id)]
    then <- match(resumes$team_id, before$team_id)
    since <- function(column) ifelse(is.na(then), 0, resumes[[column]] - before[[column]][then])
    inputs <- cbind(
      resumes[c("losses", "record_strength", "power", "tier")],
      prev_points = ifelse(is.na(prev_cfp), 0, 26 - prev_cfp),
      was_ranked = as.numeric(!is.na(prev_cfp)),
      new_losses = since("losses"),
      strength_gain = since("record_strength")
    )
    score <- committee_score(inputs, COMMITTEE_UPDATE$weights)
    method <- "update"
  }
  out <- data.frame(rank = as.integer(rank(-score, ties.method = "first")), team_id = resumes$team_id,
                    score = score, prev_cfp = as.integer(prev_cfp), method = method, stringsAsFactors = FALSE)
  out <- out[order(out$rank), , drop = FALSE]
  rownames(out) <- NULL
  out
}

#' Path of one saved committee prediction.
forecast_path <- function(season, week, root = PATHS$snapshots) {
  file.path(root, "cfp_predictions", sprintf("%d_wk%02d.csv", as.integer(season), as.integer(week)))
}

#' Save our prediction of the committee's next ranking, once.
#'
#' It is written the first time this runs after the week's games are all
#' in, and never rewritten. If the committee has already released that
#' week's ranking, nothing is saved: a prediction made after the answer is
#' out proves nothing.
#'
#' @return TRUE if a file was written, invisibly.
freeze_committee_forecast <- function(app_data, root = PATHS$snapshots, now = Sys.time()) {
  week <- app_data$meta$forecast_week
  if (isTRUE(app_data$meta$is_demo) || is.null(week) || is.na(week)) return(invisible(FALSE))
  path <- forecast_path(app_data$meta$season, week, root)
  if (file.exists(path)) return(invisible(FALSE))
  if (any(app_data$polls$poll == "cfp" & app_data$polls$week >= week)) {
    message("Not saving a committee prediction for week ", week, ": its ranking is already out.")
    return(invisible(FALSE))
  }
  forecast <- utils::head(committee_forecast(app_data, week), FORECAST_SAVED)
  if (nrow(forecast) == 0) return(invisible(FALSE))
  forecast <- cbind(season = app_data$meta$season, week = week, forecast,
                    school = app_data$teams$school[match(forecast$team_id, app_data$teams$team_id)],
                    made = "before", saved_at = format_utc(now))
  write_snapshot(forecast, path)
  invisible(TRUE)
}

#' This season's saved committee predictions.
#'
#' @return Rows of week, rank, team_id, score, prev_cfp, method and made
#'   ("before" the release, or "after" for ones worked out later to fill in
#'   history). No rows when none are saved.
load_forecasts <- function(root = PATHS$snapshots, season) {
  empty <- data.frame(week = integer(), rank = integer(), team_id = integer(), score = numeric(),
                      prev_cfp = integer(), method = character(), made = character(), stringsAsFactors = FALSE)
  files <- list.files(file.path(root, "cfp_predictions"), pattern = sprintf("^%d_wk[0-9]{2}\\.csv$", as.integer(season)),
                      full.names = TRUE)
  if (length(files) == 0) return(empty)
  rows <- do.call(rbind, lapply(files, read_snapshot))
  out <- data.frame(week = as.integer(rows$week), rank = as.integer(rows$rank), team_id = as.integer(rows$team_id),
                    score = as.numeric(rows$score), prev_cfp = as.integer(rows$prev_cfp),
                    method = as.character(rows$method), made = as.character(rows$made), stringsAsFactors = FALSE)
  out[order(out$week, out$rank), , drop = FALSE]
}

#' How each saved prediction did against the committee's real ranking.
#'
#' @param forecasts What load_forecasts() returns.
#' @param polls app_data$polls.
#' @return One row per graded week: week, made, method, places_off (average
#'   over the committee's 25; a team we left off our list counts as one
#'   place past its end), exact (teams in exactly the right place), in_25,
#'   top12 and top4 (teams shared with the committee's).
forecast_record <- function(forecasts, polls) {
  committee <- polls[polls$poll == "cfp", , drop = FALSE]
  weeks <- intersect(unique(forecasts$week), unique(committee$week))
  rows <- lapply(sort(weeks), function(week) {
    ours <- forecasts[forecasts$week == week, , drop = FALSE]
    theirs <- committee[committee$week == week, , drop = FALSE]
    predicted <- ours$rank[match(theirs$team_id, ours$team_id)]
    predicted[is.na(predicted)] <- max(ours$rank) + 1L
    shared <- function(n) length(intersect(ours$team_id[ours$rank <= n], theirs$team_id[theirs$rank <= n]))
    data.frame(week = week, made = ours$made[1], method = ours$method[1],
               places_off = mean(abs(predicted - theirs$rank)), exact = sum(predicted == theirs$rank),
               in_25 = shared(25), top12 = shared(12), top4 = shared(4), stringsAsFactors = FALSE)
  })
  if (length(rows) == 0) {
    return(data.frame(week = integer(), made = character(), method = character(), places_off = numeric(),
                      exact = integer(), in_25 = integer(), top12 = integer(), top4 = integer()))
  }
  do.call(rbind, rows)
}

