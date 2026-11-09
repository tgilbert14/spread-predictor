# Turn two teams and a set of fitted parameters into a spread and win
# probability. Everything here is plain arithmetic on an in-memory table, so
# the app can call it on every input change.
#
# Sign convention used everywhere in this project:
#   margin = Team A points minus Team B points. Positive means A is favored.

# The four rating systems, in display order. Names are column names in the
# teams table; values are the labels people see.
MODEL_LABELS <- c(sp = "SP+", fpi = "FPI", srs = "SRS", elo = "Elo")

SITE_CHOICES <- c("neutral", "a_home", "b_home")

# Models further apart than this (in points) raise a "models disagree" flag.
DISAGREEMENT_POINTS <- 7

# Width of the "most likely range" shown next to the spread.
INTERVAL_COVERAGE <- 0.80

#' Find one team's row by school name or CFBD team id.
#'
#' @param team School name (case-insensitive) or numeric team_id.
#' @param teams The teams table from app_data (see docs/data-dictionary.md).
#' @return A one-row data frame.
find_team <- function(team, teams) {
  if (is.numeric(team)) {
    row <- teams[teams$team_id == team, , drop = FALSE]
  } else {
    row <- teams[tolower(teams$school) == tolower(trimws(team)), , drop = FALSE]
  }
  if (nrow(row) != 1) {
    stop(sprintf("Team not found: '%s'. Use a school name or team_id from the teams table.", team),
         call. = FALSE)
  }
  row
}

#' Predict a matchup.
#'
#' @param team_a,team_b School name or team_id.
#' @param site "neutral", "a_home" or "b_home".
#' @param teams Teams table with one rating column per model (sp, fpi, srs, elo)
#'   and matching rank columns (sp_rank, ...).
#' @param params Fitted parameters: k (Elo points per game point), h (home
#'   field, in points), sigma (SD of actual margin around the prediction) and
#'   weights (named, one per model, summing to 1).
#' @return A list: team_a and team_b (one-row data frames), site, spread
#'   (A minus B), win_prob_a, interval (low and high margin), models (one row
#'   per rating system) and flags (character vector, possibly empty).
predict_matchup <- function(team_a, team_b, site = "neutral", teams, params) {
  site <- match.arg(site, SITE_CHOICES)
  a <- find_team(team_a, teams)
  b <- find_team(team_b, teams)
  if (a$team_id == b$team_id) {
    stop("Pick two different teams.", call. = FALSE)
  }

  site_sign <- c(neutral = 0, a_home = 1, b_home = -1)[[site]]
  home_edge <- params$h * site_sign

  model_ids <- names(MODEL_LABELS)
  models <- data.frame(
    model    = model_ids,
    label    = unname(MODEL_LABELS),
    rating_a = vapply(model_ids, function(m) as.numeric(a[[m]]), numeric(1)),
    rank_a   = vapply(model_ids, function(m) as.numeric(a[[paste0(m, "_rank")]]), numeric(1)),
    rating_b = vapply(model_ids, function(m) as.numeric(b[[m]]), numeric(1)),
    rank_b   = vapply(model_ids, function(m) as.numeric(b[[paste0(m, "_rank")]]), numeric(1)),
    weight   = vapply(model_ids, function(m) as.numeric(params$weights[[m]]), numeric(1)),
    stringsAsFactors = FALSE,
    row.names = NULL
  )

  # Elo is not in points, so its gap is divided by k. The others already are.
  points_per_unit <- ifelse(models$model == "elo", 1 / params$k, 1)
  models$margin <- (models$rating_a - models$rating_b) * points_per_unit + home_edge

  # A team can be missing from one system. Drop that system for this matchup
  # and let the remaining weights fill the gap, rather than failing.
  usable <- !is.na(models$margin) & models$weight > 0
  if (!any(usable)) {
    stop("No rating system has both teams, so there is nothing to blend.", call. = FALSE)
  }
  models$weight[!usable] <- 0
  models$weight <- models$weight / sum(models$weight)

  spread <- sum(models$weight[usable] * models$margin[usable])
  z <- stats::qnorm(1 - (1 - INTERVAL_COVERAGE) / 2)

  flags <- character()
  missing_models <- models$label[is.na(models$margin)]
  if (length(missing_models) > 0) {
    flags <- c(flags, sprintf("%s has no rating for one of these teams, so it was left out.",
                              paste(missing_models, collapse = " and ")))
  }
  if (diff(range(models$margin[usable])) > DISAGREEMENT_POINTS) {
    flags <- c(flags, sprintf("Models disagree by more than %d points.", DISAGREEMENT_POINTS))
  }

  list(
    team_a     = a,
    team_b     = b,
    site       = site,
    spread     = spread,
    win_prob_a = stats::pnorm(spread / params$sigma),
    interval   = c(low = spread - z * params$sigma, high = spread + z * params$sigma),
    models     = models,
    flags      = flags
  )
}
