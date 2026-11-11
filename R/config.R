# Paths and constants shared by the pipeline and the app.
# All paths are relative to the project root. Run scripts from there.

PATHS <- list(
  snapshots = file.path("data", "snapshots"),
  database  = "cfb.sqlite",
  schema    = file.path("sql", "schema.sql"),
  params    = file.path("data", "params.json"),
  app_data  = file.path("data", "app_data.rds"),
  overrides = file.path("data", "overrides"),
  notes     = file.path("data", "notes.csv")
)

# Seasons to backfill from the API. More history means tighter answers when
# we test an idea. 2020 is pulled so ratings carry across it, but the COVID
# season (odd schedules, empty stadiums) is never fit or scored on.
TRAINING_SEASONS <- 2017:2025

# The first season only warms up the Power rating, which needs a season of
# results before its numbers mean anything. Nothing is fit on it.
BURN_IN_SEASON <- 2017L

# Seasons the model is fit and cross-validated on. 2020 is left out: the
# COVID season had short, conference-only schedules and empty stadiums, so
# it would teach the model the wrong home field and the wrong team gaps. It
# stays in the Power rating's chain so 2021 ratings start from real results.
FIT_SEASONS <- c(2018L, 2019L, 2021:2025)

# The season after the fit seasons is scored as a holdout: the fit never
# sees it, so it is an honest check on the current season to date.
HOLDOUT_SEASON <- max(FIT_SEASONS) + 1L

# Rating systems we snapshot. These are also the folder names under
# data/snapshots/ratings/ and the rating column names in the teams table.
RATING_SOURCES <- c("sp", "fpi", "srs", "elo")

# Every system in the blend: the snapshotted ones plus our own Power rating,
# which is computed from game results instead of being downloaded.
BLEND_SYSTEMS <- c(RATING_SOURCES, "power")

# The public systems that are already in points. Their past ratings include
# the results, so their scale is fitted against closing lines instead
# (fit_public_scales() in R/fit.R), on games from this regular-season week on
# plus the postseason, where season-final ratings are closest to what the
# systems said on game day. With fewer games than the minimum, a system is
# used point for point.
PUBLIC_SYSTEMS <- c("sp", "fpi", "srs")
PUBLIC_SCALE_FROM_WEEK <- 11L
PUBLIC_SCALE_MIN_GAMES <- 300L

# Settings for the Power rating (R/power_rating.R). Scores are not capped:
# caps of 28 and 38 points both predicted worse than no cap. Each game's
# target mixes the score with how consistently each team won its downs
# (success rate), which is less noisy than the score alone.
POWER_RATING <- list(
  team_shrink = 4,        # Pull on each team toward its prior; 3 to 6 all score within 0.03 points.
  conference_shrink = 1,  # Pull on each conference shift; weak, so a whole league can move fast.
  carry = 0.7,            # Share of last season's edge over its conference that carries over.
  home_field = 3,         # Points taken off home margins so ratings are neutral-field.
  new_team_offset = -3,   # A team new to the data starts this far below its conference average.
  fcs_start = -25,        # First-season rating of the single pooled FCS team.
  success_share = 0.4,    # Share of each game's target taken from success rate; 25% to 50% all score within 0.01.
  success_points = 124    # Points per unit of success-rate margin, from a regression of margin on it (2018 to 2025).
)

# Power conferences and the last season each counted as one. CFBD Elo
# understates the gap between these teams and everyone else, so the Elo model
# adds a fitted bonus per tier step. Inf means "still a power conference".
# The Pac-12 lost its power status when ten members left after 2023.
POWER_CONFERENCES <- c("SEC" = Inf, "Big Ten" = Inf, "Big 12" = Inf, "ACC" = Inf, "Pac-12" = 2023)

# Independents that count as power teams. 87 is Notre Dame.
POWER_TEAM_IDS <- c(87L)

#' Is each team a power team in that season?
#'
#' Vectorized over all three arguments.
#'
#' @param conference Conference name as in the teams table (may be NA).
#' @param team_id CFBD team id.
#' @param season Season year.
#' @return Logical, never NA.
is_power_team <- function(conference, team_id, season) {
  last_power_season <- unname(POWER_CONFERENCES[conference])
  in_power_conference <- !is.na(last_power_season) & season <= last_power_season
  in_power_conference | team_id %in% POWER_TEAM_IDS
}

# Ratings older than this many days raise a "stale" note in the app.
STALE_AFTER_DAYS <- 8

# Through this week, ratings still lean on preseason priors.
EARLY_SEASON_LAST_WEEK <- 3

# Preseason talent and returning production help the Elo and Power models
# early on, then fade out: full weight in week 1, none from week 1 plus this
# many weeks on. Fading over 6 weeks passed the backtest; using them all
# season did not.
PRESEASON_FADE_WEEKS <- 6

#' How much preseason information still counts in a game: 1 in week 1,
#' falling in a straight line to 0 by week 7, and 0 in the postseason.
#'
#' @param week CFBD week.
#' @param season_type "regular", or anything else for the postseason.
preseason_fade <- function(week, season_type = "regular") {
  fade <- pmax(0, 1 - (week - 1) / PRESEASON_FADE_WEEKS)
  fade[season_type != "regular"] <- 0
  fade
}

# A game where our line and the market's were at least this many points apart
# when the prediction was saved counts as a disagreement on the scorecard.
# Smaller gaps are mostly rounding and noise; 3 points is a field goal, the
# smallest gap that says the two forecasts really see the game differently.
DISAGREE_POINTS <- 3

# A market line that has moved this many points since our prediction was
# saved is flagged in the app. Lines rarely move that far on betting alone;
# a big move usually means news, such as a quarterback ruled out, that the
# rating systems do not know about yet.
LINE_MOVE_POINTS <- 2.5

# Kinds of game notes in data/notes.csv. Anything else is read as "other".
NOTE_CATEGORIES <- c("availability", "weather", "other")
