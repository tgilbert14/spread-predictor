# Turn two teams and a set of fitted parameters into a spread and win
# probability. Everything here is plain arithmetic on an in-memory table, so
# the app can call it on every input change.
#
# Sign convention used everywhere in this project:
#   margin = Team A points minus Team B points. Positive means A is favored.

# The five rating systems, in display order. Names are column names in the
# teams table; values are the labels people see.
MODEL_LABELS <- c(sp = "SP+", fpi = "FPI", srs = "SRS", elo = "Elo", power = "Power")

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
#' @param teams Teams table with one rating column per model (sp, fpi, srs,
#'   elo, power), matching rank columns (sp_rank, ...), tier (1 for a power
#'   team, 0 otherwise), and talent_z and returning_z (preseason z-scores).
#' @param params Fitted parameters: k (Elo points per game point), elo_tier
#'   (points per tier step), power_scale (points per Power point), h (home
#'   field, in points), talent_points and returning_points (week 1 points per
#'   z-score gap), sigma (SD of actual margin around the prediction) and
#'   weights (named, one per model, summing to 1).
#' @param week The regular-season week being predicted. NULL (the default)
#'   adds no preseason points.
#' @return A list: team_a and team_b (one-row data frames), site, spread
#'   (A minus B), win_prob_a, interval (low and high margin), models (one row
#'   per rating system) and flags (character vector, possibly empty).
predict_matchup <- function(team_a, team_b, site = "neutral", teams, params, week = NULL) {
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

  models$margin <- rating_margins(models, a$tier - b$tier, params) + home_edge
  # Elo and Power lean on preseason information early on. SP+, FPI and SRS
  # already build in their own, so they get nothing extra.
  early <- preseason_points(a, b, params, week)
  ours <- models$model %in% c("elo", "power")
  models$margin[ours] <- models$margin[ours] + early

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
    flags <- c(flags, sprintf("%s %s no rating for one of these teams, so %s left out.",
                              paste(missing_models, collapse = " and "),
                              if (length(missing_models) == 1) "has" else "have",
                              if (length(missing_models) == 1) "it was" else "they were"))
  }
  if (early != 0) {
    flags <- c(flags, "Early season: the Elo and Power numbers also lean on preseason roster talent and returning production.")
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

#' Preseason points for A over B, added to the Elo and Power margins.
#'
#' Roster talent and returning production gaps (in z-scores), times their
#' fitted points, times preseason_fade(week): full in week 1, gone by week 7.
#'
#' @param a,b One-row team data frames with talent_z and returning_z.
#' @param week Regular-season week, or NULL for none.
#' @return Points, A minus B. 0 when week is NULL or 7 or later.
preseason_points <- function(a, b, params, week) {
  fade <- if (is.null(week)) 0 else preseason_fade(week)
  if (fade == 0) return(0)
  gap <- function(column) {
    z <- c(a[[column]], b[[column]])
    z[is.na(z)] <- 0
    z[1] - z[2]
  }
  fade * (params$talent_points * gap("talent_z") + params$returning_points * gap("returning_z"))
}

#' Each model's margin before home field, A minus B.
#'
#' SP+, FPI and SRS are in points, but they spread teams out more than point
#' spreads do, so each gap is multiplied by its fitted scale
#' (params$public_scale; 1 when there is none). Elo is not in points, so its
#' gap is divided by k, and it gets elo_tier points per tier step because
#' CFBD Elo understates the gap between power-conference teams and everyone
#' else. Power is in points but is rescaled by its fitted power_scale.
#'
#' @param models Rows of model, rating_a and rating_b.
#' @param tier_diff Team A's tier minus Team B's: -1, 0 or 1.
rating_margins <- function(models, tier_diff, params) {
  margin <- models$rating_a - models$rating_b
  public <- params$public_scale
  if (!is.null(public)) {
    scale <- public$scale[match(models$model, public$model)]
    margin <- margin * ifelse(is.na(scale), 1, scale)
  }
  elo <- models$model == "elo"
  margin[elo] <- margin[elo] / params$k + params$elo_tier * tier_diff
  power <- models$model == "power"
  margin[power] <- params$power_scale * margin[power]
  margin
}
