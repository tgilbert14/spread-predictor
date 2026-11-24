# The team page: one team's season on a single card. It opens in a dialog
# when a team's name is tapped in a ranking table.
#
# Everything on it comes from data the app already holds: this season's
# results and schedule, the weekly Power rating, the polls and our rankings.

#' A team's name as a button that opens its team page.
#'
#' The click is picked up in www/app.js and sent to the server as the
#' `team_open` input.
#'
#' @param team One-row data frame from the teams table.
#' @param rank Shown small before the name, or NA for none.
team_link_html <- function(team, school, rank = NA) {
  if (!is.data.frame(team) || nrow(team) != 1) return(team_name_html(team, school, rank))
  sprintf('<button type="button" class="team-link" data-team-id="%d" aria-label="%s, open team page">%s</button>',
          as.integer(team$team_id), htmltools::htmlEscape(school, attribute = TRUE),
          team_name_html(team, school, rank))
}

#' A small line chart as inline SVG: one value per week.
#'
#' @param weeks,values The points, in week order. NAs are skipped.
#' @param label Read out by screen readers in place of the picture.
#' @return An svg tag, or NULL with fewer than two points.
week_line <- function(weeks, values, label) {
  keep <- !is.na(values)
  weeks <- weeks[keep]
  values <- values[keep]
  if (length(values) < 2) return(NULL)
  span <- range(values)
  if (diff(span) == 0) span <- span + c(-1, 1)
  x <- (weeks - min(weeks)) / max(1, max(weeks) - min(weeks)) * 280 + 10
  y <- 70 - (values - span[1]) / diff(span) * 60
  htmltools::tags$svg(
    class = "week-line", viewBox = "0 0 300 80", role = "img", `aria-label` = label,
    preserveAspectRatio = "none",
    htmltools::tags$polyline(points = paste(sprintf("%.1f,%.1f", x, y), collapse = " ")),
    htmltools::tags$circle(cx = sprintf("%.1f", x[length(x)]), cy = sprintf("%.1f", y[length(y)]), r = 4)
  )
}

#' A team's poll ranking week by week, as a row of small chips.
#'
#' @return NULL when the team was never ranked in the poll this season.
poll_chips <- function(polls, team_id, poll, name) {
  rows <- polls[polls$poll == poll, , drop = FALSE]
  if (!team_id %in% rows$team_id) return(NULL)
  weeks <- sort(unique(rows$week))
  rank <- rows$rank[match(paste(weeks, team_id), paste(rows$week, rows$team_id))]
  htmltools::div(
    class = "poll-row",
    htmltools::span(class = "poll-name", name),
    htmltools::div(class = "poll-chips", lapply(seq_along(weeks), function(i) {
      htmltools::span(class = paste("poll-chip", if (is.na(rank[i])) "is-unranked"),
                      title = sprintf("Week %d", weeks[i]),
                      htmltools::span(class = "poll-week", sprintf("Wk %d", weeks[i])),
                      if (is.na(rank[i])) "NR" else rank[i])
    }))
  )
}

#' One number with its label, for the row of facts at the top of the page.
team_fact <- function(label, value) {
  htmltools::div(class = "team-fact", htmltools::span(class = "team-fact-value", value),
                 htmltools::span(class = "team-fact-label", label))
}

#' The team page.
#'
#' @param app_data See docs/data-dictionary.md.
#' @param team_id The team to show.
#' @param sides What football_team_games() returns.
#' @return Tags for the page, or NULL when the team is not in the table.
team_page <- function(app_data, team_id, sides = football_team_games(app_data)) {
  teams <- app_data$teams
  team <- teams[teams$team_id %in% team_id, , drop = FALSE]
  if (nrow(team) != 1) return(NULL)
  games <- sides[sides$team_id == team$team_id, , drop = FALSE]
  games <- games[order(games$when, games$start_date), , drop = FALSE]
  played <- games[!is.na(games$points_for), , drop = FALSE]
  wins <- sum(played$points_for > played$points_against)
  ranks <- team_ranks(app_data)
  poll <- attr(ranks, "poll")
  ours <- ranking_table(app_data)
  mine <- ours[ours$team_id == team$team_id, , drop = FALSE]
  place <- function(rank) if (length(rank) == 1 && !is.na(rank)) paste0("No. ", rank) else "Unranked"

  facts <- list(
    team_fact("Record", if (nrow(played) > 0) sprintf("%d-%d", wins, nrow(played) - wins) else "0-0"),
    if (!is.na(poll)) team_fact(if (poll == "cfp") "Playoff committee" else "AP poll", place(rank_of(ranks, team$team_id))),
    team_fact("Who would win", place(mine$rank)),
    team_fact("Who has earned it", place(mine$earned)),
    if (nrow(played) > 0) team_fact("Points a game", sprintf("%.1f", mean(played$points_for))),
    if (nrow(played) > 0) team_fact("Allowed a game", sprintf("%.1f", mean(played$points_against)))
  )

  history <- app_data$history[app_data$history$team_id == team$team_id, , drop = FALSE]
  history <- history[order(history$week), , drop = FALSE]
  power <- week_line(history$week, history$power,
                     sprintf("%s's Power rating by week, from %.1f to %.1f.", team$school,
                             history$power[1], history$power[nrow(history)]))

  line <- our_lines(games, teams, function(a, b, site) {
    predict_matchup(a, b, site, teams, app_data$params, week = app_data$meta$week)$spread
  })
  schedule <- data.frame(
    week = games$when,
    game = upcoming_html(games, line, teams = teams, ranks = ranks,
                         market = market_lines(games, teams, market_table(app_data))),
    stringsAsFactors = FALSE
  )
  left <- sum(is.na(games$points_for))

  htmltools::div(
    class = "team-page",
    htmltools::div(
      class = "team-page-head",
      team_badge(team, "lg"),
      htmltools::div(
        htmltools::tags$h2(class = "team-page-name", team$school),
        htmltools::p(class = "team-page-sub", team$conference)
      )
    ),
    htmltools::div(class = "team-facts", facts),
    {
      sentence <- quarterback_sentence(app_data$quarterbacks[app_data$quarterbacks$team_id %in% team$team_id, , drop = FALSE])
      if (!is.null(sentence)) {
        htmltools::p(class = "team-qb", htmltools::tags$strong("Quarterback. "), sentence,
                     htmltools::span(class = "fine-print", " From the box scores."))
      }
    },
    if (!is.null(power)) {
      htmltools::div(
        class = "team-trend",
        htmltools::p(class = "chart-subhead", "Our Power rating, week by week"),
        power,
        htmltools::p(class = "fine-print",
                     sprintf("Points better than an average team. It started at %+.1f and is %+.1f now.",
                             history$power[!is.na(history$power)][1],
                             utils::tail(history$power[!is.na(history$power)], 1)))
      )
    },
    poll_chips(app_data$polls, team$team_id, "cfp", "Playoff committee"),
    poll_chips(app_data$polls, team$team_id, "ap", "AP poll"),
    htmltools::p(class = "chart-subhead",
                 if (left > 0) sprintf("Schedule: %d played, %d to go", nrow(played), left) else "Schedule"),
    if (nrow(schedule) > 0) {
      simple_table(schedule, headers = list("Week", "Game"), numeric = c(TRUE, FALSE), html = c(FALSE, TRUE),
                   caption = paste("Games still to play show our line.", rank_note(ranks)))
    } else {
      empty_state("No games yet.", "The schedule fills in when the data refreshes.")
    }
  )
}

#' The team page in a dialog.
team_modal <- function(app_data, team_id, sides = football_team_games(app_data)) {
  page <- team_page(app_data, team_id, sides)
  if (is.null(page)) return(NULL)
  shiny::modalDialog(page, title = NULL, easyClose = TRUE, size = "l",
                     footer = shiny::modalButton("Close"))
}
