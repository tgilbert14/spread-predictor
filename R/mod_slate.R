# This week tab: every slate game with our line next to the market's.
# Clicking a game opens it, at its real site, on the Matchup tab.

# Hidden sort keys sit after the visible columns (0-based for DT).
SLATE_VISIBLE <- c("Matchup", "Our line", "Market", "Difference", "Home win chance", "")
SLATE_KEYS <- c(our = 6, market = 7, gap = 8, prob = 9)

#' The games the This week tab shows.
#'
#' Normally that is this week's slate. Once every game on it has been
#' played, the tab would sit empty until the next data refresh, so it looks
#' ahead instead: the next week's games between teams we rate, from the
#' schedule, with the sportsbook line for each game that has one.
#'
#' @return list(games, week, ahead): rows shaped like app_data$slate, the
#'   week they belong to, and TRUE when they are next week's.
shown_slate <- function(app_data) {
  slate <- app_data$slate
  week <- app_data$meta$week
  if (nrow(slate) > 0) return(list(games = slate, week = week, ahead = FALSE))
  ahead <- app_data$upcoming
  if (is.data.frame(ahead) && nrow(ahead) > 0) {
    rated <- ahead$home_id %in% app_data$teams$team_id & ahead$away_id %in% app_data$teams$team_id
    ahead <- ahead[rated & (is.null(week) | ahead$week > week), , drop = FALSE]
  }
  if (!is.data.frame(ahead) || nrow(ahead) == 0) return(list(games = slate, week = week, ahead = FALSE))
  ahead <- ahead[ahead$week == min(ahead$week), , drop = FALSE]
  ahead <- ahead[order(ahead$start_date, ahead$game_id), , drop = FALSE]
  games <- data.frame(game_id = ahead$game_id, start_date = ahead$start_date, home_id = ahead$home_id,
                      away_id = ahead$away_id, neutral_site = ahead$neutral_site %in% c(TRUE, 1),
                      market_spread_home = if ("market_spread_home" %in% names(ahead)) {
                        as.numeric(ahead$market_spread_home)
                      } else {
                        NA_real_
                      },
                      market_at_freeze = NA_real_, market_move = NA_real_)
  list(games = games, week = as.integer(ahead$week[1]), ahead = TRUE)
}

#' `a` unless it is missing, NULL or empty, then `b`.
`%|na|%` <- function(a, b) if (is.null(a) || length(a) != 1 || is.na(a) || !nzchar(a)) b else a

#' @param app_data See docs/data-dictionary.md.
mod_slate_ui <- function(id, app_data) {
  ns <- shiny::NS(id)
  shown <- shown_slate(app_data)
  has_games <- nrow(shown$games) > 0
  has_market <- any(!is.na(shown$games$market_spread_home))

  body <- if (has_games) {
    htmltools::tagList(
      htmltools::p(
        class = "section-lede",
        if (shown$ahead) {
          sprintf("Week %s is in the books, so this is a look ahead at week %s. ", app_data$meta$week, shown$week)
        },
        if (has_market) {
          "Biggest gaps between our line and the market come first. "
        } else {
          "These are our lines alone, in kickoff order: the sportsbooks' lines arrive with the next data refresh. "
        },
        htmltools::tags$strong("Tap any game"), " to open it in Matchup."
      ),
      if (has_market) {
        htmltools::div(
          class = "line-key",
          chart_legend("Our line", "Market"),
          htmltools::span(class = "line-key-note",
                          "On each track, left favors the away team and right the home team. ",
                          sprintf("A gap of %d or more is marked.", DISAGREE_POINTS))
        )
      },
      htmltools::div(class = "slate-wrap", DT::DTOutput(ns("table")))
    )
  } else {
    empty_state(
      "No games on this week's slate yet.",
      htmltools::p("The schedule fills in the next time the data refreshes. You can still pick any two teams."),
      shiny::actionButton(ns("go_matchup"), "Pick a matchup", class = "btn-primary")
    )
  }

  htmltools::div(
    class = "page-wide",
    htmltools::tags$section(
      class = "card", `aria-labelledby` = ns("title"),
      htmltools::div(
        class = "card-body",
        htmltools::tags$h2(
          id = ns("title"), class = "section-title",
          if (is.null(shown$week)) "This week's games" else sprintf("Week %s games", shown$week),
          if (shown$ahead) htmltools::span(class = "pill", "Look ahead")
        ),
        body
      )
    )
  )
}

#' One display row per slate game, plus numeric keys for sorting.
#' Games whose teams cannot be predicted are skipped rather than shown broken.
#'
#' @param notes This week's game notes (app_notes()), counted per game.
#' @param slate The games to show: shown_slate()$games.
slate_rows <- function(app_data, open_input_id, notes = NULL, slate = shown_slate(app_data)$games) {
  ranks <- team_ranks(app_data)
  preds <- lapply(seq_len(nrow(slate)), function(i) {
    m <- slate_matchup(slate[i, , drop = FALSE])
    tryCatch(predict_matchup(m$a, m$b, m$site, app_data$teams, app_data$params, week = app_data$meta$week),
             error = function(e) NULL)
  })
  scale <- line_scale(preds, slate)
  rows <- lapply(seq_len(nrow(slate)), function(i) {
    if (is.null(preds[[i]])) return(NULL)
    game <- slate[i, , drop = FALSE]
    slate_row(preds[[i]], game, open_input_id, n_notes = sum(notes$game_id == game$game_id), ranks = ranks,
              scale = scale)
  })
  do.call(rbind, rows)
}

#' How many points the ends of the line tracks stand for: the biggest line
#' on the page, ours or the market's, so every row shares one scale.
#'
#' @param preds One prediction per slate game (NULL where there is none).
#' @return A number of points, at least 7 and at most 40.
line_scale <- function(preds, slate) {
  ours <- vapply(preds, function(p) if (is.null(p)) NA_real_ else abs(p$spread), numeric(1))
  biggest <- suppressWarnings(max(c(ours, abs(slate$market_spread_home)), na.rm = TRUE))
  if (!is.finite(biggest)) return(NA_real_)
  min(max(ceiling(biggest / 7) * 7, 7), 40)
}

#' Our line and the market's on one small track, for a table cell.
#'
#' The middle is a pick'em. Left favors the away team, right the home team.
#' A line past the end of the track is drawn at the end.
#'
#' @param ours,market Predicted margins for the away team (positive means
#'   the away team is favored).
#' @param scale What line_scale() returns.
#' @return HTML text, or "" when there is no market line or no scale.
line_track <- function(ours, market, scale, away, home) {
  if (is.na(market) || is.null(scale) || is.na(scale)) return("")
  at <- function(margin) min(max(50 - margin / scale * 50, 3), 97)
  left <- min(at(ours), at(market))
  sprintf(paste0(
    '<span class="line-track" role="img" aria-label="Our line %s, the market %s.">',
    '<span class="line-track-link" style="left:%.1f%%;width:%.1f%%"></span>',
    '<span class="line-track-dot is-market" style="left:%.1f%%"></span>',
    '<span class="line-track-dot is-ours" style="left:%.1f%%"></span>',
    '<span class="line-track-ends" aria-hidden="true"><span>%s</span><span>%s</span></span></span>'),
    htmltools::htmlEscape(format_favorite(ours, away, home), attribute = TRUE),
    htmltools::htmlEscape(format_favorite(market, away, home), attribute = TRUE),
    left, abs(at(ours) - at(market)), at(market), at(ours),
    htmltools::htmlEscape(away), htmltools::htmlEscape(home))
}

#' A single slate row. Team A is the away team and B the home team.
#'
#' @param n_notes How many game notes this game has, for its marker.
#' @param ranks Ranks named by team id, shown beside the names, or NULL.
#' @param share_link Add a link that opens the game in Matchup to the shared
#'   text. FALSE where the app cannot open a matchup from a link (basketball).
#' @param scale What line_scale() returns, to draw the line track. NULL
#'   leaves the track out.
slate_row <- function(pred, game, open_input_id, n_notes = 0, ranks = NULL, share_link = TRUE, scale = NULL) {
  ranked <- function(team) if (is.null(ranks)) NA else rank_of(ranks, team$team_id)
  away <- pred$team_a$school
  home <- pred$team_b$school
  esc <- htmltools::htmlEscape
  has_line <- !is.na(game$market_spread_home)
  market <- if (has_line) market_margin_for_a(game, pred$team_a$team_id) else NA
  gap <- shown_gap(pred$spread, market)
  joiner <- if (isTRUE(game$neutral_site)) "vs" else "at"

  # Each cell carries its own label, shown only when rows stack as cards on phones.
  cell <- function(label, html) sprintf('<span class="cell-label">%s</span>%s', label, html)
  data.frame(
    matchup = paste0(
      matchup_html(team_name_html(pred$team_a, away, ranked(pred$team_a)), joiner,
                   team_name_html(pred$team_b, home, ranked(pred$team_b))),
      slate_markers(if (is.null(game$market_move)) NA else game$market_move, n_notes,
                    gap = if (has_line) gap else NA)
    ),
    our = cell("Our line", esc(format_favorite(pred$spread, away, home))),
    market = cell("Market", if (has_line) esc(format_favorite(market, away, home)) else '<span class="muted">No line</span>'),
    gap = cell("Difference", if (has_line) {
      # A gap of DISAGREE_POINTS or more is the kind the Scorecard tracks.
      sprintf('<span class="gap-cell">%s<span class="gap-text"><span class="gap-points%s">%s</span><span class="gap-side">%s</span></span></span>',
              line_track(pred$spread, market, scale, pred$team_a$abbreviation %|na|% away,
                         pred$team_b$abbreviation %|na|% home),
              if (abs(round_half(gap)) >= DISAGREE_POINTS) " is-big" else "",
              format_points(gap), esc(gap_side(gap, away, home)))
    } else {
      '<span class="muted">No line</span>'
    }),
    # The home team is the second name in the matchup, so the number is enough.
    prob = cell("Home win chance", format_prob(1 - pred$win_prob_a)),
    open = paste0(
      share_button(
        sprintf("%s %s %s: our line is %s%s. %s win chance %s.", away, joiner, home,
                format_favorite(pred$spread, away, home),
                if (has_line) sprintf(", the market has %s", format_favorite(market, away, home)) else "",
                home, format_prob(1 - pred$win_prob_a)),
        query = if (share_link) matchup_query(pred) else "",
        label = sprintf("Share %s %s %s", away, joiner, home)
      ),
      sprintf(
        '<button type="button" class="btn btn-open" data-game-id="%s" data-input="%s" aria-label="Open %s %s %s in Matchup">Open%s</button>',
        game$game_id, open_input_id, esc(away), joiner, esc(home), as.character(svg_icon("chevron"))
      )
    ),
    our_key = abs(pred$spread),
    market_key = if (has_line) abs(market) else -1,
    # Games with no line sort last when the biggest gaps come first.
    gap_key = if (has_line) abs(round_half(gap)) else -1,
    prob_key = 1 - pred$win_prob_a,
    stringsAsFactors = FALSE
  )
}

#' Which team we like more than the market does, for the Difference column.
gap_side <- function(gap, away, home) {
  if (format_points(gap) == "0") return("matches market")
  paste("higher on", if (gap > 0) away else home)
}

#' The DT widget, stripped down to a sortable list that matches the theme.
#' @param by_gap Start sorted by the biggest gap to the market. FALSE keeps
#'   the order given (kickoff order), for games with no market line yet.
#' @param market FALSE hides the Market and Difference columns, for games
#'   with no market line to show.
slate_table <- function(rows, by_gap = TRUE, market = TRUE) {
  DT::datatable(
    rows,
    colnames = c(SLATE_VISIBLE, names(SLATE_KEYS)),
    rownames = FALSE, escape = FALSE, selection = "none",
    # Plain DataTables styling; www/styles.css themes it. (The bootstrap5
    # style in DT 0.31 points at a stylesheet it does not ship.)
    style = "default", class = "slate-table",
    options = list(
      dom = "<'slate-search'f>t",
      paging = FALSE, info = FALSE, autoWidth = FALSE,
      order = if (by_gap) list(list(SLATE_KEYS[["gap"]], "desc")) else list(),
      language = list(search = "", searchPlaceholder = "Find a team",
                      zeroRecords = "No games match that search."),
      columnDefs = list(
        list(targets = c(unname(SLATE_KEYS), if (!market) c(2, 3)), visible = FALSE, searchable = FALSE),
        list(targets = 1, orderData = SLATE_KEYS[["our"]]),
        list(targets = 2, orderData = SLATE_KEYS[["market"]]),
        list(targets = 3, orderData = SLATE_KEYS[["gap"]], className = "dt-right"),
        list(targets = 4, orderData = SLATE_KEYS[["prob"]], className = "dt-right slate-prob"),
        list(targets = 5, orderable = FALSE, searchable = FALSE, className = "dt-right")
      )
    )
  )
}

#' @param notes This week's game notes (app_notes()).
#' @param on_open Called with list(a, b, site) to open a game in Matchup, or
#'   with NULL to just switch to the Matchup tab.
mod_slate_server <- function(id, app_data, notes, on_open) {
  shiny::moduleServer(id, function(input, output, session) {
    shown <- shown_slate(app_data)
    if (nrow(shown$games) > 0) {
      has_market <- any(!is.na(shown$games$market_spread_home))
      output$table <- DT::renderDT(
        slate_table(slate_rows(app_data, session$ns("open"), notes, shown$games), by_gap = has_market,
                    market = has_market)
      )
    }

    shiny::observeEvent(input$open, {
      game <- shown$games[shown$games$game_id == input$open, , drop = FALSE]
      shiny::req(nrow(game) == 1)
      on_open(slate_matchup(game))
    })
    shiny::observeEvent(input$go_matchup, on_open(NULL))
  })
}
