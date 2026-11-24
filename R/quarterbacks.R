# Each team's quarterback situation going into every game, worked out from
# the passing box scores (R/passing.R). Nothing here reads news.
#
# The "main quarterback" is the one who has thrown the most passes for the
# team so far that season. He is "out" for a game when he threw none.

# A quarterback needs this many attempts before his passing numbers are
# trusted enough to say how good he is.
QB_MIN_ATTEMPTS <- 60

# An established starter has thrown at least this share of his team's passes
# so far, over at least QB_MIN_ATTEMPTS. That leaves out early-season
# quarterback battles, where "the main quarterback sat" means little.
QB_ESTABLISHED_SHARE <- 0.75

#' Attach team ids to the passing rows.
#'
#' @param passing Rows from load_passing().
#' @param games Game rows with game_id, start_date, home_id, away_id,
#'   home_team and away_team.
#' @return `passing` with team_id and start_date. Rows whose team name
#'   matches neither side of the game are dropped.
passing_with_teams <- function(passing, games) {
  at <- match(passing$game_id, games$game_id)
  home <- !is.na(at) & passing$team == games$home_team[at]
  away <- !is.na(at) & passing$team == games$away_team[at]
  passing$team_id <- ifelse(home, games$home_id[at], ifelse(away, games$away_id[at], NA))
  passing$start_date <- games$start_date[at]
  passing[!is.na(passing$team_id), , drop = FALSE]
}

#' One row per team per game: who the main quarterback was going in, and
#' what happened to him.
#'
#' Everything named "before" or "prev" uses only earlier games, so it is
#' known before kickoff. `out_now` is only known afterwards (or from an
#' availability report).
#'
#' @param passing What passing_with_teams() returns.
#' @return game_id, season, team_id, start_date and:
#'   main_qb, main_name: the main quarterback going in (NA in a team's
#'     first game of a season);
#'   out_now: 1 when he threw no passes in this game;
#'   out_prev: 1 when the main quarterback going into the previous game
#'     threw no passes in it;
#'   games_out: how many games in a row he had missed going in;
#'   main_ypa: his yards per attempt going in (NA under QB_MIN_ATTEMPTS);
#'   established: 1 when he was an established starter going in;
#'   starter, starter_name: who threw the most passes in this game.
quarterback_games <- function(passing) {
  passing <- passing[order(passing$season, passing$team_id, passing$start_date, passing$game_id), , drop = FALSE]
  groups <- split(passing, list(passing$season, passing$team_id), drop = TRUE)
  rows <- lapply(groups, function(team) {
    game_ids <- unique(team$game_id)
    attempts <- numeric()   # season to date, by athlete
    yards <- numeric()
    names_by_id <- character()
    missed <- 0L
    out <- vector("list", length(game_ids))
    out_last <- 0L
    for (i in seq_along(game_ids)) {
      game <- team[team$game_id == game_ids[i], , drop = FALSE]
      main <- if (length(attempts) > 0) names(attempts)[which.max(attempts)] else NA_character_
      threw <- stats::setNames(game$attempts, game$athlete_id)
      out_now <- as.integer(!is.na(main) && !(main %in% names(threw)[threw > 0]))
      out[[i]] <- data.frame(
        game_id = game_ids[i], season = game$season[1], team_id = game$team_id[1],
        start_date = game$start_date[1], main_qb = main,
        main_name = if (is.na(main)) NA_character_ else names_by_id[[main]],
        out_now = out_now, out_prev = out_last, games_out = missed,
        main_ypa = if (!is.na(main) && attempts[[main]] >= QB_MIN_ATTEMPTS) yards[[main]] / attempts[[main]] else NA_real_,
        established = as.integer(!is.na(main) && attempts[[main]] >= QB_MIN_ATTEMPTS &&
                                   attempts[[main]] / sum(attempts) >= QB_ESTABLISHED_SHARE),
        starter = game$athlete_id[which.max(game$attempts)],
        starter_name = game$athlete[which.max(game$attempts)], stringsAsFactors = FALSE
      )
      out_last <- out_now
      missed <- if (out_now == 1) missed + 1L else 0L
      for (j in seq_len(nrow(game))) {
        id <- game$athlete_id[j]
        attempts[id] <- (if (id %in% names(attempts)) attempts[[id]] else 0) + game$attempts[j]
        yards[id] <- (if (id %in% names(yards)) yards[[id]] else 0) + ifelse(is.na(game$yards[j]), 0, game$yards[j])
        names_by_id[id] <- game$athlete[j]
      }
      # A backup who has now thrown more than the old starter becomes the
      # main quarterback, and the count of missed games starts over.
      if (!is.na(main) && names(attempts)[which.max(attempts)] != main) {
        missed <- 0L
        out_last <- 0L
      }
    }
    do.call(rbind, out)
  })
  result <- do.call(rbind, rows)
  rownames(result) <- NULL
  result
}

#' Where each team's quarterback job stands right now, for the app.
#'
#' @param passing One season of passing rows with team ids
#'   (passing_with_teams()).
#' @return One row per team: team_id, starter (who threw the most passes in
#'   the latest game), starts (how many games in a row he has led), opener
#'   (who led in the season's first game), opener_last_week (the last week
#'   the opener threw a pass) and changed (TRUE when the starter is not the
#'   opener). No rows when there is no passing data.
quarterback_summary <- function(passing) {
  empty <- data.frame(team_id = integer(), starter = character(), starts = integer(), opener = character(),
                      opener_last_week = integer(), changed = logical(), stringsAsFactors = FALSE)
  if (is.null(passing) || nrow(passing) == 0) return(empty)
  passing <- passing[order(passing$team_id, passing$start_date, passing$game_id, -passing$attempts), , drop = FALSE]
  rows <- lapply(split(passing, passing$team_id), function(team) {
    leaders <- team[!duplicated(team$game_id), , drop = FALSE]  # most attempts in each game
    current <- leaders$athlete_id[nrow(leaders)]
    run <- rle(rev(leaders$athlete_id == current))
    opener <- leaders$athlete_id[1]
    threw <- team[team$athlete_id == opener & team$attempts > 0, , drop = FALSE]
    data.frame(team_id = team$team_id[1], starter = leaders$athlete[nrow(leaders)],
               starts = as.integer(run$lengths[1]), opener = leaders$athlete[1],
               opener_last_week = as.integer(max(threw$week)), changed = current != opener,
               stringsAsFactors = FALSE)
  })
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}

#' One sentence on a team's quarterback, or NULL when we know nothing.
#'
#' @param status One row of quarterback_summary(), or no rows.
quarterback_sentence <- function(status) {
  if (!is.data.frame(status) || nrow(status) != 1) return(NULL)
  games <- function(n) if (n == 1) "the last game" else sprintf("the last %d games", n)
  if (!status$changed) return(sprintf("%s has been the quarterback all season.", status$starter))
  sprintf("%s has started %s. %s, who opened the season as the starter, last played in week %d.",
          status$starter, games(status$starts), status$opener, status$opener_last_week)
}
