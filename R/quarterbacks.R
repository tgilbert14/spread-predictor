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
#'   the opener threw a pass), changed (TRUE when the starter is not the
#'   opener), main (the most passes all season: the main quarterback going
#'   into the next game), established (1 when he is an established
#'   starter) and missed_last (TRUE when an established main quarterback
#'   threw no passes in the latest game). No rows when there is no passing
#'   data.
quarterback_summary <- function(passing) {
  empty <- data.frame(team_id = integer(), starter = character(), starts = integer(), opener = character(),
                      opener_last_week = integer(), changed = logical(), main = character(),
                      established = integer(), missed_last = logical(), stringsAsFactors = FALSE)
  if (is.null(passing) || nrow(passing) == 0) return(empty)
  passing <- passing[order(passing$team_id, passing$start_date, passing$game_id, -passing$attempts), , drop = FALSE]
  rows <- lapply(split(passing, passing$team_id), function(team) {
    leaders <- team[!duplicated(team$game_id), , drop = FALSE]  # most attempts in each game
    current <- leaders$athlete_id[nrow(leaders)]
    run <- rle(rev(leaders$athlete_id == current))
    opener <- leaders$athlete_id[1]
    threw <- team[team$athlete_id == opener & team$attempts > 0, , drop = FALSE]
    totals <- tapply(team$attempts, team$athlete_id, sum)
    main <- names(totals)[which.max(totals)]
    data.frame(team_id = team$team_id[1], starter = leaders$athlete[nrow(leaders)],
               starts = as.integer(run$lengths[1]), opener = leaders$athlete[1],
               opener_last_week = as.integer(max(threw$week)), changed = current != opener,
               main = team$athlete[match(main, team$athlete_id)],
               established = as.integer(totals[[main]] >= QB_MIN_ATTEMPTS &&
                                          totals[[main]] / sum(totals) >= QB_ESTABLISHED_SHARE),
               missed_last = totals[[main]] >= QB_MIN_ATTEMPTS &&
                 totals[[main]] / sum(totals) >= QB_ESTABLISHED_SHARE &&
                 !any(team$athlete_id == main & team$attempts > 0 & team$game_id == leaders$game_id[nrow(leaders)]),
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

# ---- Quarterbacks listed out, and what that does to a line ---------------------

# data/qb_status.csv: one row each time a report gives a quarterback's
# status. The Thursday and Friday availability check adds to it.
QB_STATUS_COLUMNS <- c("season", "week", "team", "athlete", "status", "source", "source_url", "checked_at")
# The statuses that count as not playing.
QB_OUT_STATUSES <- c("out", "out_for_season")

#' One season of reported quarterback statuses.
#'
#' Tolerates a missing or empty file and missing columns. Rows with no team,
#' athlete or status are dropped.
#'
#' @return A data frame with QB_STATUS_COLUMNS (zero rows when there is nothing).
load_qb_status <- function(path = PATHS$qb_status, season) {
  empty <- data.frame(season = integer(), week = integer(), team = character(), athlete = character(),
                      status = character(), source = character(), source_url = character(),
                      checked_at = character(), stringsAsFactors = FALSE)
  if (!file.exists(path)) return(empty)
  raw <- tryCatch(utils::read.csv(path, stringsAsFactors = FALSE, colClasses = "character"),
                  error = function(e) NULL)
  if (is.null(raw) || nrow(raw) == 0) return(empty)
  for (column in setdiff(QB_STATUS_COLUMNS, names(raw))) raw[[column]] <- NA_character_
  raw <- raw[QB_STATUS_COLUMNS]
  raw$season <- suppressWarnings(as.integer(raw$season))
  raw$week <- suppressWarnings(as.integer(raw$week))
  raw$status <- tolower(trimws(gsub("[ -]+", "_", raw$status)))
  keep <- raw$season %in% season & !is.na(raw$week) & nzchar(trimws(raw$team)) & nzchar(trimws(raw$athlete)) &
    !is.na(raw$status) & nzchar(raw$status)
  raw <- raw[keep & !is.na(keep), , drop = FALSE]
  rownames(raw) <- NULL
  raw
}

#' TRUE where two spellings name the same player: the same last name and
#' first initial, ignoring case, punctuation and a Jr. or III on the end.
same_player <- function(a, b) {
  key <- function(name) {
    name <- tolower(gsub("[^A-Za-z ]", "", name))
    words <- strsplit(trimws(name), " +")
    vapply(words, function(w) {
      w <- w[!w %in% c("jr", "sr", "ii", "iii", "iv")]
      if (length(w) == 0) return(NA_character_)
      paste(substr(w[1], 1, 1), w[length(w)])
    }, character(1))
  }
  ka <- key(a)
  kb <- key(b)
  !is.na(ka) & !is.na(kb) & ka == kb
}

#' Which teams have their established starting quarterback listed out.
#'
#' A report counts for the week it was filed for. "Out for the season"
#' counts for every week after it too. The newest report for a player
#' wins, so a later "probable" clears an earlier "out".
#'
#' @param status Rows of load_qb_status().
#' @param mains One row per team to check: team (the school, as reports
#'   spell it), week, main_name (its main quarterback going into that
#'   week's game), established (1 or TRUE when he is an established
#'   starter) and, optionally, before (only reports filed before this UTC
#'   time count: the kickoff).
#' @return One logical per row of `mains`.
starter_out <- function(status, mains) {
  if (nrow(mains) == 0) return(logical())
  before <- if ("before" %in% names(mains)) mains$before else rep(NA_character_, nrow(mains))
  vapply(seq_len(nrow(mains)), function(i) {
    if (is.na(mains$main_name[i]) || !mains$established[i] %in% c(1, TRUE)) return(FALSE)
    rows <- status[status$team == mains$team[i] & same_player(status$athlete, mains$main_name[i]) &
                     (status$week == mains$week[i] | (status$status == "out_for_season" & status$week < mains$week[i])),
                   , drop = FALSE]
    if (!is.na(before[i])) rows <- rows[!is.na(rows$checked_at) & rows$checked_at < before[i], , drop = FALSE]
    if (nrow(rows) == 0) return(FALSE)
    rows$status[order(rows$week, rows$checked_at, decreasing = TRUE)][1] %in% QB_OUT_STATUSES
  }, logical(1))
}

#' Points to add to the home team's margin for quarterbacks listed out.
qb_home_adjustment <- function(home_out, away_out, points = QB_OUT_POINTS) {
  points * (as.numeric(away_out) - as.numeric(home_out))
}

#' The teams whose established starter is listed out for an upcoming week.
#'
#' @param app_data With `quarterbacks` (where each job stands now) and
#'   `qb_status` (the reports).
#' @return A data frame of team_id and athlete. No rows when none.
qb_out_teams <- function(app_data, week) {
  none <- data.frame(team_id = integer(), athlete = character(), stringsAsFactors = FALSE)
  status <- app_data$qb_status
  now <- app_data$quarterbacks
  if (!is.data.frame(status) || nrow(status) == 0 || !is.data.frame(now) || nrow(now) == 0 ||
      !"main" %in% names(now)) return(none)
  school <- app_data$teams$school[match(now$team_id, app_data$teams$team_id)]
  mains <- data.frame(team = school, week = week, main_name = now$main, established = now$established,
                      stringsAsFactors = FALSE)
  out <- !is.na(school) & starter_out(status, mains)
  data.frame(team_id = now$team_id[out], athlete = now$main[out], stringsAsFactors = FALSE)
}

#' Grade the quarterback adjustment on games already played.
#'
#' For each graded game, the adjusted line is our saved line plus the
#' adjustment for any established starter a report had listed out before
#' kickoff. Only reports filed before kickoff count, so this is what the
#' adjusted line would have said at the time.
#'
#' @param games Graded games (scorecard$games rows with a final margin).
#' @param qb_games The season's quarterback_games(): who the main
#'   quarterback was going into each game.
#' @return The adjusted games only: game_id, week, home_team, away_team,
#'   out (who was out), blend, adjusted, market (home margins, market may
#'   be NA), final_margin and the three misses.
grade_qb_adjustment <- function(games, qb_games, status, teams) {
  none <- data.frame(game_id = integer(), week = integer(), home_team = character(), away_team = character(),
                     out = character(), blend = numeric(), adjusted = numeric(), market = numeric(),
                     final_margin = numeric(), our_miss = numeric(), adjusted_miss = numeric(),
                     market_miss = numeric(), stringsAsFactors = FALSE)
  if (!is.data.frame(games) || nrow(games) == 0 || !is.data.frame(qb_games) || nrow(qb_games) == 0 ||
      !is.data.frame(status) || nrow(status) == 0) return(none)
  side <- function(id_column, name_column) {
    at <- match(paste(games$game_id, games[[id_column]]), paste(qb_games$game_id, qb_games$team_id))
    mains <- data.frame(team = games[[name_column]], week = games$week, main_name = qb_games$main_name[at],
                        established = qb_games$established[at], before = games$start_date,
                        stringsAsFactors = FALSE)
    list(out = starter_out(status, mains), name = qb_games$main_name[at])
  }
  home <- side("home_id", "home_team")
  away <- side("away_id", "away_team")
  hit <- home$out | away$out
  if (!any(hit)) return(none)
  adjusted <- games$blend + qb_home_adjustment(home$out, away$out)
  who <- ifelse(home$out & away$out, paste(home$name, "and", away$name),
                ifelse(home$out, paste0(home$name, " (", games$home_team, ")"),
                       paste0(away$name, " (", games$away_team, ")")))
  out <- data.frame(
    game_id = games$game_id, week = games$week, home_team = games$home_team, away_team = games$away_team,
    out = who, blend = games$blend, adjusted = adjusted, market = -games$market_spread_home,
    final_margin = games$final_margin, our_miss = abs(games$final_margin - games$blend),
    adjusted_miss = abs(games$final_margin - adjusted),
    market_miss = abs(games$final_margin + games$market_spread_home), stringsAsFactors = FALSE
  )[hit, , drop = FALSE]
  rownames(out) <- NULL
  out
}

#' Teams whose established starting quarterback is out or may be: listed
#' out in a report for the week, or absent from the latest game.
#'
#' Used to flag teams in the committee prediction. The committee may weigh
#' a key player's absence, but it is too rare to learn a size for (30 ranked
#' team-weeks since 2018), so it is shown, not scored.
#'
#' @return team_id, athlete and why ("listed out" or "missed the last game").
qb_flagged_teams <- function(app_data, week) {
  listed <- qb_out_teams(app_data, week)
  now <- app_data$quarterbacks
  missed <- if (is.data.frame(now) && "missed_last" %in% names(now)) now[now$missed_last %in% TRUE, , drop = FALSE] else NULL
  out <- data.frame(team_id = listed$team_id, athlete = listed$athlete,
                    why = rep("listed out", nrow(listed)), stringsAsFactors = FALSE)
  if (!is.null(missed) && nrow(missed) > 0) {
    extra <- missed[!missed$team_id %in% out$team_id, , drop = FALSE]
    out <- rbind(out, data.frame(team_id = extra$team_id, athlete = extra$main,
                                 why = rep("missed the last game", nrow(extra)), stringsAsFactors = FALSE))
  }
  out
}

# ---- Other starters listed out -------------------------------------------------

# data/availability.csv: every starter, other than a quarterback, that a
# report lists out or doubtful. Nothing in the model reads it yet. It is
# being collected so the cost of losing other starters can be tested once
# there is a season of it (docs/research-log.md, Nov. 24). The app only
# marks a team that has STARTERS_OUT_FLAG or more out.
AVAILABILITY_COLUMNS <- c("season", "week", "team", "athlete", "position", "status", "source", "source_url",
                          "checked_at")

#' One season of starters listed out, other than quarterbacks.
#'
#' Tolerates a missing or empty file and missing columns, like
#' load_qb_status().
load_availability <- function(path = PATHS$availability, season) {
  empty <- as.data.frame(stats::setNames(replicate(length(AVAILABILITY_COLUMNS), character(), simplify = FALSE),
                                         AVAILABILITY_COLUMNS), stringsAsFactors = FALSE)
  empty$season <- integer()
  empty$week <- integer()
  if (!file.exists(path)) return(empty)
  raw <- tryCatch(utils::read.csv(path, stringsAsFactors = FALSE, colClasses = "character"),
                  error = function(e) NULL)
  if (is.null(raw) || nrow(raw) == 0) return(empty)
  for (column in setdiff(AVAILABILITY_COLUMNS, names(raw))) raw[[column]] <- NA_character_
  raw <- raw[AVAILABILITY_COLUMNS]
  raw$season <- suppressWarnings(as.integer(raw$season))
  raw$week <- suppressWarnings(as.integer(raw$week))
  raw$status <- tolower(trimws(gsub("[ -]+", "_", raw$status)))
  keep <- raw$season %in% season & !is.na(raw$week) & nzchar(trimws(raw$team)) & nzchar(trimws(raw$athlete)) &
    !is.na(raw$status) & nzchar(raw$status)
  raw <- raw[keep & !is.na(keep), , drop = FALSE]
  rownames(raw) <- NULL
  raw
}

#' How many starters each team has listed out for a week.
#'
#' The newest report for a player wins, and "out for the season" carries to
#' later weeks, as with quarterbacks.
#'
#' @return Counts named by team (the school). Teams with none are left out.
starters_out <- function(availability, week) {
  rows <- availability[availability$week == week |
                         (availability$status == "out_for_season" & availability$week < week), , drop = FALSE]
  if (nrow(rows) == 0) return(stats::setNames(integer(), character()))
  rows <- rows[order(rows$week, rows$checked_at, decreasing = TRUE), , drop = FALSE]
  latest <- rows[!duplicated(paste(rows$team, tolower(rows$athlete))), , drop = FALSE]
  out <- latest[latest$status %in% QB_OUT_STATUSES, , drop = FALSE]
  counts <- table(out$team)
  stats::setNames(as.integer(counts), names(counts))
}
