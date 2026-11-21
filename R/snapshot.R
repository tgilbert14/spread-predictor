# Snapshots: looking at a matchup through the ratings of an earlier week.
#
# app_data$history holds what every system said about every team going into
# each week so far. A snapshot swaps those ratings into the teams table, so
# the same prediction code answers "what did the ratings say back then?".
#
# The spread for a past week uses that week's ratings with today's fitted
# settings. It is not always the line we saved that week: the settings can
# be refit in between. For a game that was played, snapshot_result() carries
# the saved line and the final score so both can be shown.

SNAPSHOT_HELP <- paste(
  "A snapshot is what the rating systems said going into that week's games.",
  "The spread uses those ratings with today's model settings,",
  "so it can differ a little from the line we saved that week."
)

#' The weeks a snapshot can show, oldest first. Always includes this week.
snapshot_weeks <- function(app_data) {
  current <- as.integer(app_data$meta$week)
  weeks <- as.integer(app_data$history$week)
  sort(unique(c(weeks[weeks <= current], current)))
}

#' Which systems have no ratings at all for a week.
#'
#' @return Model ids, such as c("sp", "fpi", "srs"), possibly empty.
models_missing_in_week <- function(history, week) {
  rows <- history[history$week == week, , drop = FALSE]
  models <- names(MODEL_LABELS)
  models[vapply(models, function(m) all(is.na(rows[[m]])), logical(1))]
}

#' Choices for the "Ratings as of" selector, newest week first.
#'
#' A week where only some systems have ratings says so in its label.
#'
#' @return Week numbers (as text) named by their labels.
snapshot_choices <- function(app_data) {
  current <- as.integer(app_data$meta$week)
  weeks <- rev(snapshot_weeks(app_data))
  labels <- vapply(weeks, function(week) {
    if (week == current) return(sprintf("Week %d (this week)", week))
    missing <- models_missing_in_week(app_data$history, week)
    if (length(missing) == 0) return(sprintf("Week %d", week))
    have <- MODEL_LABELS[setdiff(names(MODEL_LABELS), missing)]
    sprintf("Week %d (%s only)", week, paste(have, collapse = " and "))
  }, character(1))
  stats::setNames(as.character(weeks), labels)
}

#' The teams table as it stood going into a week.
#'
#' This week's table is returned as is. For an earlier week the five rating
#' columns come from the history and the ranks are worked out again.
#' Everything else about a team (name, colors, tier) stays the same.
snapshot_teams <- function(app_data, week) {
  teams <- app_data$teams
  if (is.null(week) || week == app_data$meta$week) return(teams)
  rows <- app_data$history[app_data$history$week == week, , drop = FALSE]
  at <- match(teams$team_id, rows$team_id)
  for (model in names(MODEL_LABELS)) {
    teams[[model]] <- rows[[model]][at]
    teams[[paste0(model, "_rank")]] <-
      as.integer(rank(-teams[[model]], ties.method = "min", na.last = "keep"))
  }
  teams
}

#' Read the snapshot week from the address bar, e.g. "?a=Kofa&b=Rincon&week=9".
#' Anything missing or not a week we hold opens this week.
week_from_query <- function(query, app_data) {
  current <- as.integer(app_data$meta$week)
  params <- if (is.null(query) || !nzchar(query)) list() else shiny::parseQueryString(query)
  week <- suppressWarnings(as.integer(params$week))
  if (length(week) == 1 && !is.na(week) && week %in% snapshot_weeks(app_data)) week else current
}

#' The note for a snapshot week where some systems were never saved, or NULL.
snapshot_missing_note <- function(history, week) {
  missing <- models_missing_in_week(history, week)
  if (length(missing) == 0) return(NULL)
  first_saved <- suppressWarnings(min(history$week[!is.na(history[[missing[1]]])]))
  since <- if (is.finite(first_saved)) sprintf(" before week %d", first_saved) else ""
  have <- MODEL_LABELS[setdiff(names(MODEL_LABELS), missing)]
  sprintf("%s %s not saved%s, so this snapshot blends %s only.",
          format_list(MODEL_LABELS[missing]), if (length(missing) == 1) "was" else "were",
          since, format_list(have))
}

#' The notes under a snapshot's answer.
#'
#' The prediction's own "no rating for one of these teams" note is swapped
#' for the plainer snapshot one when the whole system is missing that week.
snapshot_flags <- function(pred, history, week) {
  missing <- models_missing_in_week(history, week)
  left_out <- pred$models$model[is.na(pred$models$margin)]
  flags <- pred$flags
  if (length(left_out) > 0 && all(left_out %in% missing)) {
    flags <- setdiff(flags, missing_models_flag(MODEL_LABELS[left_out]))
  }
  c(snapshot_missing_note(history, week), flags)
}

#' How a past week's game between two teams turned out, or NULL.
#'
#' @param app_data Needs results (finished games) and scorecard$games (saved
#'   predictions).
#' @return list(final, saved, market): the final score in words, the line we
#'   saved that week and the market's line at the time. saved and market are
#'   NULL for a game with no saved prediction.
snapshot_result <- function(app_data, week, a_id, b_id) {
  results <- app_data$results
  hit <- results$week == week &
    ((results$home_id == a_id & results$away_id == b_id) |
       (results$home_id == b_id & results$away_id == a_id))
  if (!any(hit)) return(NULL)
  game <- results[which(hit)[1], , drop = FALSE]
  school <- function(team_id) app_data$teams$school[match(team_id, app_data$teams$team_id)]
  home <- school(game$home_id)
  away <- school(game$away_id)

  saved <- app_data$scorecard$games
  saved <- saved[saved$game_id == game$game_id, , drop = FALSE]
  has_saved <- nrow(saved) == 1
  has_market <- has_saved && !is.na(saved$market_spread_home)
  list(
    final = format_final(home, away, game$home_points, game$away_points),
    saved = if (has_saved) format_favorite(saved$blend, home, away),
    market = if (has_market) format_favorite(-saved$market_spread_home, home, away)
  )
}

#' The "How it turned out" row under a snapshot's answer.
snapshot_result_fact <- function(result) {
  if (is.null(result)) return(NULL)
  then <- c(if (!is.null(result$saved)) sprintf("The line we saved that week: %s.", result$saved),
            if (!is.null(result$market)) sprintf("The market then: %s.", result$market))
  htmltools::p(
    class = "market-line",
    htmltools::span(class = "fact-label", "Final score"),
    htmltools::span(class = "market-value", result$final),
    if (length(then) > 0) htmltools::span(class = "range-note", paste(then, collapse = " "))
  )
}

#' Each system's margin and the blend for one matchup, week by week.
#'
#' @param teams_by_week Teams tables named by week (snapshot_teams()).
#' @return One row per week and line: week, model ("blend" for the blend),
#'   label, margin (A minus B), and complete (FALSE in a week where the
#'   blend is missing a system).
matchup_trend <- function(a_id, b_id, site, teams_by_week, params) {
  rows <- lapply(names(teams_by_week), function(week) {
    pred <- tryCatch(
      predict_matchup(a_id, b_id, site, teams_by_week[[week]], params, week = as.integer(week)),
      error = function(e) NULL
    )
    if (is.null(pred)) return(NULL)
    used <- pred$models$weight > 0
    data.frame(
      week = as.integer(week),
      model = c(pred$models$model, "blend"),
      label = c(pred$models$label, "Blend"),
      margin = c(ifelse(used, pred$models$margin, NA_real_), pred$spread),
      complete = all(used),
      stringsAsFactors = FALSE
    )
  })
  trend <- do.call(rbind, rows)
  trend[!is.na(trend$margin), , drop = FALSE]
}

#' Two teams' ratings in every system, week by week.
#'
#' @return One row per week, team and system: week, team_id, model, label,
#'   rating. Weeks where a system has no rating are left out.
rating_trend <- function(history, team_ids) {
  rows <- history[history$team_id %in% team_ids, , drop = FALSE]
  long <- do.call(rbind, lapply(names(MODEL_LABELS), function(model) {
    data.frame(week = rows$week, team_id = rows$team_id, model = model,
               label = MODEL_LABELS[[model]], rating = rows[[model]], stringsAsFactors = FALSE)
  }))
  long[!is.na(long$rating), , drop = FALSE]
}
