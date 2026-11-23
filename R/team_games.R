# Each ranked team's last result and next game, for the "Last game" and
# "Next game" views of the ranking tables (football and basketball).
#
# Both sports keep games one row per game, home and away. Here they are
# turned into one row per team per game, so "this team's latest game" is a
# simple lookup.

# The three views a ranking table can show.
RANKING_VIEWS <- c(ranks = "Rankings", last = "Last game", `next` = "Next game")

#' One row per team per game.
#'
#' @param games Rows with home_id, away_id, neutral_site, start_date and
#'   `when` (a number that puts games in order: the week in football, the
#'   day in basketball). Finished games also have home_points and
#'   away_points. home_team and away_team, when present, name opponents that
#'   are not in `teams` (lower-division schools).
#' @param teams The teams table, for opponent names.
#' @return Rows of team_id, opponent_id, opponent, where ("vs" at home or on
#'   a neutral field, "at" on the road), site (the team's side, for a
#'   prediction, with the team as team A: "a_home", "b_home" or "neutral"), when, start_date, points_for
#'   and points_against (NA until played).
team_games <- function(games, teams) {
  empty <- data.frame(team_id = integer(), opponent_id = integer(), opponent = character(),
                      where = character(), site = character(), when = numeric(), start_date = character(),
                      points_for = integer(), points_against = integer(), stringsAsFactors = FALSE)
  if (!is.data.frame(games) || nrow(games) == 0) return(empty)
  column <- function(name, default) if (name %in% names(games)) games[[name]] else rep(default, nrow(games))
  neutral <- games$neutral_site %in% c(TRUE, 1)
  named <- function(ids, fallback) {
    school <- teams$school[match(ids, teams$team_id)]
    ifelse(is.na(school), ifelse(is.na(fallback), "a lower-division team", fallback), school)
  }
  side <- function(team, opponent, opponent_name, where, site, scored, allowed) {
    data.frame(team_id = team, opponent_id = opponent, opponent = named(opponent, opponent_name),
               where = where, site = site, when = as.numeric(games$when), start_date = games$start_date,
               points_for = scored, points_against = allowed, stringsAsFactors = FALSE)
  }
  home_points <- column("home_points", NA_integer_)
  away_points <- column("away_points", NA_integer_)
  rbind(
    side(games$home_id, games$away_id, column("away_team", NA_character_), "vs",
         ifelse(neutral, "neutral", "a_home"), home_points, away_points),
    side(games$away_id, games$home_id, column("home_team", NA_character_), ifelse(neutral, "vs", "at"),
         ifelse(neutral, "neutral", "b_home"), away_points, home_points)
  )
}

#' Each team's most recent finished game before a cutoff.
#'
#' @param before Only games with `when` below this count.
#' @return The matching team_games() row for each id, in order. Teams with
#'   no such game get a row of NAs.
last_games <- function(sides, team_ids, before = Inf) {
  played <- sides[!is.na(sides$points_for) & sides$when < before, , drop = FALSE]
  played <- played[order(-played$when, -xtfrm(played$start_date)), , drop = FALSE]
  played[match(team_ids, played$team_id), , drop = FALSE]
}

#' Each team's first game at or after a cutoff, played or not.
next_games <- function(sides, team_ids, from = -Inf) {
  ahead <- sides[sides$when >= from, , drop = FALSE]
  ahead <- ahead[order(ahead$when, ahead$start_date), , drop = FALSE]
  ahead[match(team_ids, ahead$team_id), , drop = FALSE]
}

#' "Sat, Nov 28" from a UTC kickoff time. Kickoffs are US evenings, which
#' are already the next day in UTC, so the clock is moved back first.
game_day <- function(start_date) {
  day <- as.Date(parse_utc(start_date) - 6 * 3600)
  ifelse(is.na(day), "", paste0(format(day, "%a"), ", ", short_date(day)))
}

#' A finished game as table text: a W or L chip, the score, the opponent.
#'
#' @param games Rows from last_games() or next_games().
#' @return HTML, one per row. A dash where there is no game.
result_html <- function(games) {
  won <- games$points_for > games$points_against
  ifelse(
    is.na(games$points_for), '<span class="muted">No game yet</span>',
    sprintf('<span class="game-cell"><span class="result-chip %s">%s</span><span>%d-%d %s %s<span class="game-when">%s</span></span></span>',
            ifelse(won, "is-win", "is-loss"), ifelse(won, "W", "L"),
            games$points_for, games$points_against, games$where, htmltools::htmlEscape(games$opponent),
            game_day(games$start_date))
  )
}

#' An upcoming game as table text: the opponent, the day, and our line.
#'
#' A game that has since been played (an earlier week's view) shows its
#' result instead.
#'
#' @param line One line of text per row ("Our line: Arizona by 3"), or NULL.
#' @param none What to say for a team with no game ahead.
upcoming_html <- function(games, line = NULL, none = "Nothing scheduled") {
  if (is.null(line)) line <- rep("", nrow(games))
  ifelse(
    is.na(games$team_id), sprintf('<span class="muted">%s</span>', none),
    ifelse(
      !is.na(games$points_for), result_html(games),
      sprintf('<span class="game-cell"><span>%s %s<span class="game-when">%s%s</span></span></span>',
              games$where, htmltools::htmlEscape(games$opponent), game_day(games$start_date),
              ifelse(nzchar(line), paste0(" · ", htmltools::htmlEscape(line)), ""))
    )
  )
}

#' "Our line: Arizona by 3" for each upcoming game, or "" where we cannot
#' price it (a lower-division opponent, or a game already played).
#'
#' @param predict function(team_id, opponent_id, site) giving the predicted
#'   margin for the team, or NA.
our_lines <- function(games, teams, predict) {
  vapply(seq_len(nrow(games)), function(i) {
    game <- games[i, , drop = FALSE]
    if (is.na(game$team_id) || !is.na(game$points_for) || !game$opponent_id %in% teams$team_id) return("")
    margin <- tryCatch(predict(game$team_id, game$opponent_id, game$site), error = function(e) NA_real_)
    if (is.na(margin)) return("")
    paste("Our line:", format_favorite(margin, teams$school[match(game$team_id, teams$team_id)], game$opponent))
  }, character(1))
}

#' The switch above a ranking table: rankings, last game or next game.
ranking_view_input <- function(input_id) {
  htmltools::div(
    class = "week-pills view-pills",
    shiny::radioButtons(input_id, label = "Show", inline = TRUE, selected = "ranks",
                        choiceNames = unname(RANKING_VIEWS), choiceValues = names(RANKING_VIEWS))
  )
}

#' The view picked, falling back to the rankings.
ranking_view <- function(value) if (length(value) == 1 && value %in% names(RANKING_VIEWS)) value else "ranks"

#' A ranking with one games column, as a table that matches the others.
#'
#' @param rank,team,record One per row: the place, the team's name as HTML,
#'   and its record.
#' @param games HTML from result_html() or upcoming_html().
#' @param header The games column's heading.
games_view_table <- function(rank, team, record, games, header) {
  DT::datatable(
    data.frame(rank = rank, team = team, record = record, games = games, stringsAsFactors = FALSE),
    colnames = c("", "Team", "Record", header),
    rownames = FALSE, escape = FALSE, selection = "none", style = "default", class = "rank-table games-view",
    options = list(
      dom = "<'slate-search'f>t", paging = FALSE, info = FALSE, autoWidth = FALSE, order = list(),
      language = list(search = "", searchPlaceholder = "Find a team", zeroRecords = "No teams match that search."),
      columnDefs = list(
        list(targets = 0, className = "dt-right rank-number", searchable = FALSE),
        list(targets = 2, orderable = FALSE, searchable = FALSE),
        list(targets = 3, orderable = FALSE)
      )
    )
  )
}
