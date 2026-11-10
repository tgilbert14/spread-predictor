# This week tab: every slate game with our line next to the market's.
# Clicking a game opens it, at its real site, on the Matchup tab.

# Hidden sort keys sit after the visible columns (0-based for DT).
SLATE_VISIBLE <- c("Matchup", "Our line", "Market", "Difference", "Home win chance", "")
SLATE_KEYS <- c(our = 6, market = 7, gap = 8, prob = 9)

#' @param app_data See docs/data-dictionary.md.
mod_slate_ui <- function(id, app_data) {
  ns <- shiny::NS(id)
  has_games <- nrow(app_data$slate) > 0

  body <- if (has_games) {
    htmltools::tagList(
      htmltools::p(
        class = "section-lede",
        "Biggest gaps between our line and the market come first. ",
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
          if (is.null(app_data$meta$week)) "This week's games" else sprintf("Week %s games", app_data$meta$week)
        ),
        body
      )
    )
  )
}

#' One display row per slate game, plus numeric keys for sorting.
#' Games whose teams cannot be predicted are skipped rather than shown broken.
slate_rows <- function(app_data, open_input_id) {
  slate <- app_data$slate
  rows <- lapply(seq_len(nrow(slate)), function(i) {
    game <- slate[i, , drop = FALSE]
    m <- slate_matchup(game)
    pred <- tryCatch(predict_matchup(m$a, m$b, m$site, app_data$teams, app_data$params,
                                     week = app_data$meta$week),
                     error = function(e) NULL)
    if (is.null(pred)) return(NULL)
    slate_row(pred, game, open_input_id)
  })
  do.call(rbind, rows)
}

#' A single slate row. Team A is the away team and B the home team.
slate_row <- function(pred, game, open_input_id) {
  away <- pred$team_a$school
  home <- pred$team_b$school
  esc <- htmltools::htmlEscape
  has_line <- !is.na(game$market_spread_home)
  market <- if (has_line) market_margin_for_a(game, pred$team_a$team_id) else NA
  gap <- pred$spread - market
  joiner <- if (isTRUE(game$neutral_site)) "vs" else "at"

  # Each cell carries its own label, shown only when rows stack as cards on phones.
  cell <- function(label, html) sprintf('<span class="cell-label">%s</span>%s', label, html)
  data.frame(
    matchup = sprintf('<span class="slate-team">%s</span> <span class="slate-at">%s</span> <span class="slate-team">%s</span>',
                      esc(away), joiner, esc(home)),
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
    open = sprintf(
      '<button type="button" class="btn btn-open" data-game-id="%s" data-input="%s" aria-label="Open %s %s %s in Matchup">Open%s</button>',
      game$game_id, open_input_id, esc(away), joiner, esc(home), as.character(svg_icon("chevron"))
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
slate_table <- function(rows) {
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
      order = list(list(SLATE_KEYS[["gap"]], "desc")),
      language = list(search = "", searchPlaceholder = "Find a team",
                      zeroRecords = "No games match that search."),
      columnDefs = list(
        list(targets = unname(SLATE_KEYS), visible = FALSE, searchable = FALSE),
        list(targets = 1, orderData = SLATE_KEYS[["our"]]),
        list(targets = 2, orderData = SLATE_KEYS[["market"]]),
        list(targets = 3, orderData = SLATE_KEYS[["gap"]], className = "dt-right"),
        list(targets = 4, orderData = SLATE_KEYS[["prob"]], className = "dt-right"),
        list(targets = 5, orderable = FALSE, searchable = FALSE, className = "dt-right")
      )
    )
  )
}

#' @param on_open Called with list(a, b, site) to open a game in Matchup, or
#'   with NULL to just switch to the Matchup tab.
mod_slate_server <- function(id, app_data, on_open) {
  shiny::moduleServer(id, function(input, output, session) {
    if (nrow(app_data$slate) > 0) {
      output$table <- DT::renderDT(slate_table(slate_rows(app_data, session$ns("open"))))
    }

    shiny::observeEvent(input$open, {
      game <- app_data$slate[app_data$slate$game_id == input$open, , drop = FALSE]
      shiny::req(nrow(game) == 1)
      on_open(slate_matchup(game))
    })
    shiny::observeEvent(input$go_matchup, on_open(NULL))
  })
}
