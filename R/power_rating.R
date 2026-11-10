# The Power rating: our own team rating, built only from game scores.
#
# Each team's rating is a prior (where we expected it to be) plus a
# conference shift and a team shift learned from this season's margins.
# The shifts are ridge-regularized, so a team with few games stays near its
# prior and the rating firms up as the season goes on.
#
# It is computed walk-forward, one block of games at a time (a regular-season
# week, then the whole postseason as one block). The rating used for a game
# comes only from games in earlier blocks, so it is what we would have known
# before kickoff. That makes it safe to backtest and to fit on.
#
# Settings live in POWER_RATING in R/config.R.

# Every non-FBS team is pooled into one "FCS" team. There are too few games
# against each one to rate them separately.
FCS_POOL_ID <- -1L

#' Walk-forward Power ratings.
#'
#' @param games Rows of game_id, season, week, season_type, neutral_site,
#'   home_id, home_class, home_points, away_id, away_class, away_points.
#'   Games of any division. Unplayed games (points NA) get a pregame rating
#'   but are not learned from.
#' @param conferences Rows of season, team_id, conference.
#' @param settings See POWER_RATING in R/config.R.
#' @return A list:
#'   pregame: game_id, home_power, away_power, the ratings before that
#'     game's block. FCS teams get the pooled FCS rating.
#'   current: team_id, power, after every played game of the latest season.
#'     FBS teams only.
power_ratings <- function(games, conferences, settings = POWER_RATING) {
  if (nrow(games) == 0) {
    stop("The Power rating needs games, and none were given. ",
         "Run `Rscript scripts/refresh.R --offline` to rebuild the database.", call. = FALSE)
  }
  games$home_key <- pooled_id(games$home_id, games$home_class)
  games$away_key <- pooled_id(games$away_id, games$away_class)

  home_power <- rep(NA_real_, nrow(games))
  away_power <- rep(NA_real_, nrow(games))
  last_season <- numeric()

  for (season in sort(unique(games$season))) {
    rows <- which(games$season == season)
    in_season <- conferences[conferences$season == season, , drop = FALSE]
    rated <- rate_season(games[rows, , drop = FALSE], in_season, last_season, settings)
    home_power[rows] <- rated$home_power
    away_power[rows] <- rated$away_power
    last_season <- rated$final
  }

  fbs <- names(last_season) != as.character(FCS_POOL_ID)
  list(
    pregame = data.frame(game_id = games$game_id, home_power = home_power, away_power = away_power),
    current = data.frame(team_id = as.integer(names(last_season)[fbs]),
                         power = unname(last_season[fbs]))
  )
}

#' Team id, or the pooled FCS id for any team that is not FBS.
pooled_id <- function(team_id, class) {
  ifelse(!is.na(class) & class == "fbs", team_id, FCS_POOL_ID)
}

#' Rate one season, block by block.
#'
#' @param games This season's games, with home_key and away_key.
#' @param conferences This season's rows of team_id and conference.
#' @param last_season Named ratings (by team id) at the end of last season.
#' @return home_power and away_power per game (pregame), and final: named
#'   ratings after every played game.
rate_season <- function(games, conferences, last_season, settings) {
  ids <- sort(unique(c(games$home_key, games$away_key)))
  conference <- team_conference(ids, conferences)
  prior <- season_prior(ids, conference, last_season, settings)

  # Each team's rating is prior + Z %*% shifts, where the shifts are one per
  # team and one per conference.
  conference_names <- sort(unique(conference))
  Z <- cbind(diag(length(ids)), 1 * outer(conference, conference_names, "=="))
  penalty <- c(rep(settings$team_shrink, length(ids)),
               rep(settings$conference_shrink, length(conference_names)))

  home <- match(games$home_key, ids)
  away <- match(games$away_key, ids)
  played <- !is.na(games$home_points) & !is.na(games$away_points)
  # Margin left over after home field and the priors, which is what the
  # shifts have to explain.
  residual <- (games$home_points - games$away_points) -
    settings$home_field * (1 - games$neutral_site) - (prior[home] - prior[away])

  block <- rating_block(games$week, games$season_type)
  rating <- prior
  home_power <- rep(NA_real_, nrow(games))
  away_power <- rep(NA_real_, nrow(games))
  for (b in sort(unique(block))) {
    now <- block == b
    home_power[now] <- rating[home[now]]
    away_power[now] <- rating[away[now]]

    learn <- played & block <= b
    if (!any(learn & now)) next
    D <- Z[home[learn], , drop = FALSE] - Z[away[learn], , drop = FALSE]
    shifts <- solve(crossprod(D) + diag(penalty), crossprod(D, residual[learn]))
    rating <- prior + drop(Z %*% shifts)
  }

  list(home_power = home_power, away_power = away_power,
       final = stats::setNames(rating, ids))
}

#' Regular-season week, with the whole postseason as one last block.
#'
#' CFBD numbers postseason weeks from 1 again, so they cannot be used as is.
rating_block <- function(week, season_type) {
  ifelse(season_type == "regular", week, Inf)
}

#' Each team's conference this season. The FCS pool is its own conference,
#' and an FBS team missing from the teams table goes in "Other".
team_conference <- function(ids, conferences) {
  conference <- conferences$conference[match(ids, conferences$team_id)]
  conference[is.na(conference)] <- "Other"
  conference[ids == FCS_POOL_ID] <- "FCS"
  conference
}

#' Where each team starts the season.
#'
#' A returning team keeps its conference's average from last season in full,
#' plus `carry` of its own edge over that average. A new team starts
#' `new_team_offset` below its conference average. The FCS pool carries its
#' rating over unchanged. In the first season everyone starts from zero.
#'
#' @param last_season Named ratings (by team id) from last season.
#' @return One rating per id.
season_prior <- function(ids, conference, last_season, settings) {
  last <- unname(last_season[as.character(ids)])
  conference_average <- stats::ave(last, conference, FUN = function(x) {
    if (all(is.na(x))) NA_real_ else mean(x, na.rm = TRUE)
  })
  # A conference with no returning teams borrows the overall average.
  overall <- if (all(is.na(last))) 0 else mean(last, na.rm = TRUE)
  conference_average[is.na(conference_average)] <- overall

  prior <- ifelse(is.na(last),
                  conference_average + settings$new_team_offset,
                  conference_average + settings$carry * (last - conference_average))

  fcs <- ids == FCS_POOL_ID
  fcs_last <- last_season[as.character(FCS_POOL_ID)]
  prior[fcs] <- if (is.na(fcs_last)) settings$fcs_start else fcs_last
  prior
}
