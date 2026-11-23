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
#' schedule. Those have no sportsbook line yet, since lines are pulled with
#' the weekly refresh.
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
                      market_spread_home = NA_real_, market_at_freeze = NA_real_, market_move = NA_real_)
  list(games = games, week = as.integer(ahead$week[1]), ahead = TRUE)
}

#' @param app_data See docs/data-dictionary.md.
mod_slate_ui <- function(id, app_data) {
  ns <- shiny::NS(id)
  shown <- shown_slate(app_data)
  has_games <- nrow(shown$games) > 0

  body <- if (has_games) {
    htmltools::tagList(
      htmltools::p(
        class = "section-lede",
        if (shown$ahead) {
          htmltools::tagList(
            sprintf("Week %s is in the books, so this is a look ahead at week %s, in kickoff order. ",
                    app_data$meta$week, shown$week),
            "These are our lines alone: the sportsbooks' lines arrive with the next data refresh. "
          )
        } else {
          "Biggest gaps between our line and the market come first. "
        },
        htmltools::tags$strong("Tap any game"), " to open it in Matchup."
      ),
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
  rows <- lapply(seq_len(nrow(slate)), function(i) {
    game <- slate[i, , drop = FALSE]
    m <- slate_matchup(game)
    pred <- tryCatch(predict_matchup(m$a, m$b, m$site, app_data$teams, app_data$params,
                                     week = app_data$meta$week),
                     error = function(e) NULL)
    if (is.null(pred)) return(NULL)
    slate_row(pred, game, open_input_id, n_notes = sum(notes$game_id == game$game_id), ranks = ranks)
  })
  do.call(rbind, rows)
}

#' A single slate row. Team A is the away team and B the home team.
#'
#' @param n_notes How many game notes this game has, for its marker.
#' @param ranks Ranks named by team id, shown beside the names, or NULL.
#' @param share_link Add a link that opens the game in Matchup to the shared
#'   text. FALSE where the app cannot open a matchup from a link (basketball).
slate_row <- function(pred, game, open_input_id, n_notes = 0, ranks = NULL, share_link = TRUE) {
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
      slate_markers(if (is.null(game$market_move)) NA else game$market_move, n_notes)
    ),
    our = cell("Our line", esc(format_favorite(pred$spread, away, home))),
    market = cell("Market", if (has_line) esc(format_favorite(market, away, home)) else '<span class="muted">No line</span>'),
    gap = cell("Difference", if (has_line) {
      sprintf('<span class="gap-points">%s</span><span class="gap-side">%s</span>',
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
        list(targets = 4, orderData = SLATE_KEYS[["prob"]], className = "dt-right"),
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
      output$table <- DT::renderDT(
        slate_table(slate_rows(app_data, session$ns("open"), notes, shown$games), by_gap = !shown$ahead,
                    market = !shown$ahead)
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
