# Basketball pages: Matchup, Today and Top 50, under the Basketball menu.
# They reuse the football pages' pieces (pickers, headline, band, dot plot,
# tables), fed by the basketball model in R/cbb_model.R.

CBB_SLATE_VISIBLE <- c("Matchup", "Our line", "Market", "Difference", "Home win chance", "")
CBB_RANK_SORTED <- c("rank", "rating", "trank", "elo", "other")

CBB_HELP <- paste(
  "The line blends two rating systems. T-Rank rates each team's offense and defense per 100 possessions",
  "and its pace, so the same edge is worth more points in a faster game.",
  "Elo moves a team up or down after every result.",
  "Ratings are from the morning of the date shown, before that day's games."
)

#' "T-Rank through Nov 20" line shown on each basketball page.
cbb_freshness <- function(meta) {
  sprintf("%s season. Ratings through %s.", meta$season_label, short_date(meta$ratings_date))
}

# UI ----------------------------------------------------------------------------

#' The basketball Matchup page.
mod_cbb_matchup_ui <- function(id, cbb) {
  ns <- shiny::NS(id)
  teams <- cbb$teams
  initial <- cbb_default_matchup(cbb)
  school_of <- function(team_id) teams$school[teams$team_id == team_id]
  htmltools::div(
    class = "page-narrow",
    htmltools::p(class = "sport-line", htmltools::tags$strong("Men's college basketball."), cbb_freshness(cbb$meta)),
    htmltools::tags$section(
      class = "picker-panel", `aria-label` = "Choose a basketball matchup", id = ns("pickers"),
      `data-team-a` = ns("team_a"), `data-team-b` = ns("team_b"), `data-site` = ns("site"),
      htmltools::div(
        class = "picker-row",
        team_picker(ns("team_a"), "Team A", teams, initial$a),
        htmltools::tags$button(type = "button", class = "btn swap-btn", `data-swap` = ns("pickers"),
                               `aria-label` = "Swap teams", title = "Swap teams", svg_icon("swap")),
        team_picker(ns("team_b"), "Team B", teams, initial$b)
      ),
      site_control(ns("site"), school_of(initial$a), school_of(initial$b), initial$site)
    ),
    htmltools::tags$section(
      class = "answer", `aria-label` = "Prediction",
      shiny::htmlOutput(ns("headline"), container = function(...) {
        htmltools::tags$h2(..., class = "headline", `aria-live` = "polite", `aria-atomic` = "true")
      }),
      shiny::uiOutput(ns("band")),
      htmltools::div(
        class = "answer-facts",
        htmltools::p(
          class = "range-line",
          htmltools::span(class = "fact-label", "Likely range"),
          shiny::textOutput(ns("range"), inline = TRUE),
          htmltools::span(class = "range-note", "8 games in 10 land in this range.")
        ),
        shiny::uiOutput(ns("market")),
        shiny::uiOutput(ns("flags"))
      )
    ),
    htmltools::tags$section(
      class = "evidence", `aria-labelledby` = ns("evidence-title"),
      htmltools::tags$h2(
        id = ns("evidence-title"), class = "section-title", "Where the models land",
        bslib::popover(
          htmltools::tags$button(type = "button", class = "info-btn",
                                 `aria-label` = "How is the basketball line made?", svg_icon("info")),
          CBB_HELP, title = "How is the line made?"
        )
      ),
      htmltools::tags$p(class = "section-lede",
                        "Each rating system's margin on one scale. The blend is what we use."),
      shiny::uiOutput(ns("model_plot")),
      shiny::uiOutput(ns("model_table"))
    )
  )
}

#' The basketball Today page: the next few days' games.
mod_cbb_slate_ui <- function(id, cbb) {
  ns <- shiny::NS(id)
  body <- if (nrow(cbb$slate) > 0) {
    htmltools::tagList(
      htmltools::p(class = "section-lede",
                   "Biggest gaps between our line and the market come first. ",
                   htmltools::tags$strong("Tap any game"), " to open it in Matchup."),
      shiny::selectInput(ns("day"), "Day", choices = cbb_day_choices(cbb$slate), selectize = FALSE),
      htmltools::div(class = "slate-wrap", DT::DTOutput(ns("table")))
    )
  } else {
    empty_state("No games on the slate.",
                htmltools::p("Games fill in the next time the basketball data refreshes."))
  }
  htmltools::div(
    class = "page-wide",
    htmltools::p(class = "sport-line", htmltools::tags$strong("Men's college basketball."), cbb_freshness(cbb$meta)),
    htmltools::tags$section(
      class = "card", `aria-labelledby` = ns("title"),
      htmltools::div(class = "card-body",
                     htmltools::tags$h2(id = ns("title"), class = "section-title", "Upcoming games"), body)
    )
  )
}

#' The basketball Top 50 page.
mod_cbb_rankings_ui <- function(id, cbb) {
  ns <- shiny::NS(id)
  htmltools::div(
    class = "page-wide",
    htmltools::p(class = "sport-line", htmltools::tags$strong("Men's college basketball."), cbb_freshness(cbb$meta)),
    htmltools::tags$section(
      class = "card", `aria-labelledby` = ns("title"),
      htmltools::div(
        class = "card-body",
        htmltools::tags$h2(id = ns("title"), class = "section-title",
                           shiny::textOutput(ns("title_text"), inline = TRUE)),
        htmltools::p(
          class = "section-lede",
          "Two rankings of our own. Who would win is the blend behind our lines:",
          "points better than an average team on a neutral floor.",
          "Who has earned it looks only at results and how hard they were to get.",
          "Tap a column heading to sort by it."
        ),
        htmltools::div(
          class = "rankings-controls",
          htmltools::div(
            class = "segmented rank-by",
            shiny::radioButtons(ns("by"), "Rank by", inline = TRUE, width = "100%",
                                choiceNames = unname(RANKING_KINDS), choiceValues = names(RANKING_KINDS),
                                selected = "blend")
          ),
          shiny::checkboxInput(ns("all"), "Show every team", value = FALSE)
        ),
        ranking_view_input(ns("view")),
        htmltools::div(class = "rank-wrap", DT::DTOutput(ns("table"))),
        htmltools::p(class = "fine-print",
                     "Early in the season a few games decide a lot, so the earned-it ranking moves fast.",
                     "Elo starts every team level each fall and swings hard on early results,",
                     "so its ranks are rough until midseason. It is 3% of our line.")
      )
    )
  )
}

# Pieces ------------------------------------------------------------------------

#' "Today, Nov 21" style labels for the days on the slate.
cbb_day_choices <- function(slate) {
  days <- sort(unique(slate$day))
  labels <- vapply(days, function(day) {
    sprintf("%s, %s (%d games)", weekday_name(as.POSIXct(paste(day, "12:00:00"), tz = "UTC")),
            short_date(day), sum(slate$day == day))
  }, character(1))
  stats::setNames(days, labels)
}

#' Model-by-model table for a basketball prediction.
cbb_model_table <- function(pred) {
  m <- pred$models
  name_a <- pred$team_a$school
  name_b <- pred$team_b$school
  rating <- function(value, rank, model) {
    if (is.na(value)) return("No rating")
    text <- if (model == "trank") sprintf("%+.1f", value) else sprintf("%.0f", value)
    sprintf("%s (#%d)", text, as.integer(rank))
  }
  rows <- data.frame(
    model = m$label,
    a = mapply(rating, m$rating_a, m$rank_a, m$model),
    b = mapply(rating, m$rating_b, m$rank_b, m$model),
    margin = vapply(m$margin, function(x) if (is.na(x)) "No rating" else format_favorite(x, name_a, name_b), ""),
    weight = format_weight(m$weight), stringsAsFactors = FALSE
  )
  rows <- rbind(rows, data.frame(model = "Blend", a = "", b = "",
                                 margin = format_favorite(pred$spread, name_a, name_b), weight = "100%"))
  simple_table(
    rows,
    headers = list("Model", rating_header(pred$team_a), rating_header(pred$team_b), "Margin", "Weight"),
    numeric = c(FALSE, TRUE, TRUE, FALSE, TRUE),
    row_class = c(ifelse(m$weight == 0, "is-left-out", ""), "is-blend"),
    caption = paste("T-Rank's rating is points better than an average team per 100 possessions.",
                    "Elo uses its own scale. The weights were fit on last season's games.")
  )
}

#' One display row per slate game on a day, with football's row builder.
cbb_slate_rows <- function(cbb, day, open_input_id, ranks = NULL) {
  slate <- cbb$slate[cbb$slate$day == day, , drop = FALSE]
  preds <- lapply(seq_len(nrow(slate)), function(i) {
    matchup <- slate_matchup(slate[i, , drop = FALSE])
    tryCatch(cbb_predict(matchup$a, matchup$b, matchup$site, cbb$teams, cbb$params), error = function(e) NULL)
  })
  scale <- line_scale(preds, slate)
  rows <- lapply(seq_len(nrow(slate)), function(i) {
    if (is.null(preds[[i]])) return(NULL)
    slate_row(preds[[i]], slate[i, , drop = FALSE], open_input_id, ranks = ranks, share_link = FALSE,
              scale = scale)
  })
  do.call(rbind, rows)
}

#' Display rows for the basketball ranking, with sort keys.
cbb_ranking_rows <- function(ranking, teams, by = "blend") {
  if (by == "earned") {
    ranking$other <- ranking$rank
    ranking$rank <- ranking$earned
  } else {
    ranking$other <- ranking$earned
  }
  at <- match(ranking$team_id, teams$team_id)
  team <- vapply(seq_along(at), function(i) {
    row <- teams[at[i], , drop = FALSE]
    sprintf('%s<span class="rank-conference">%s</span>', team_name_html(row, row$school),
            htmltools::htmlEscape(row$conference))
  }, character(1))
  rows <- data.frame(rank = ranking$rank, team = team, record = ranking$record,
                     rating = sprintf("%+.1f", ranking$rating), stringsAsFactors = FALSE)
  for (column in c("trank", "elo", "other")) rows[[column]] <- format_rank(ranking[[column]])
  for (column in CBB_RANK_SORTED) {
    rows[[paste0(column, "_key")]] <- ifelse(is.na(ranking[[column]]), UNRANKED_KEY, ranking[[column]])
  }
  rows
}

#' The basketball ranking as a sortable table.
cbb_rankings_table <- function(rows, by = "blend") {
  headers <- c("", "Team", "Record", "Rating", unname(CBB_MODEL_LABELS),
               if (by == "earned") "Would win" else "Earned")
  n_visible <- length(headers)
  key_of <- function(column) n_visible + match(column, CBB_RANK_SORTED) - 1
  sorted_by <- function(target, column, ...) c(list(targets = target, orderData = key_of(column)), list(...))
  DT::datatable(
    rows, colnames = c(headers, paste0(CBB_RANK_SORTED, "_key")),
    rownames = FALSE, escape = FALSE, selection = "none", style = "default", class = "rank-table",
    options = list(
      dom = "<'slate-search'f>t", paging = FALSE, info = FALSE, autoWidth = FALSE, order = list(),
      language = list(search = "", searchPlaceholder = "Find a team", zeroRecords = "No teams match that search."),
      columnDefs = list(
        list(targets = n_visible - 1 + seq_along(CBB_RANK_SORTED), visible = FALSE, searchable = FALSE),
        sorted_by(0, "rank", className = "dt-right rank-number", searchable = FALSE),
        list(targets = 2, orderable = FALSE, searchable = FALSE),
        sorted_by(3, "rating", className = "dt-right", orderSequence = list("desc", "asc"), searchable = FALSE),
        sorted_by(4, "trank", className = "dt-right", searchable = FALSE),
        sorted_by(5, "elo", className = "dt-right", searchable = FALSE),
        sorted_by(6, "other", className = "dt-right rank-earned", searchable = FALSE)
      )
    )
  )
}

#' Every team's basketball games: this season's results and the slate ahead.
cbb_team_games <- function(cbb) {
  shape <- function(df, played) {
    data.frame(game_id = df$game_id, home_id = df$home_id, away_id = df$away_id, neutral_site = df$neutral_site,
               start_date = if ("start_date" %in% names(df)) df$start_date else paste0(df$day, "T18:00:00Z"),
               when = as.numeric(as.Date(df$day)),
               home_points = if (played) df$home_points else rep(NA_integer_, nrow(df)),
               away_points = if (played) df$away_points else rep(NA_integer_, nrow(df)),
               stringsAsFactors = FALSE)
  }
  team_games(rbind(shape(cbb$results, TRUE), shape(cbb$slate, FALSE)), cbb$teams)
}

#' The games column for the basketball table: each team's last result, or
#' its next game on the slate with our line.
cbb_games_column <- function(cbb, sides, team_ids, view, ranks = NULL) {
  if (view == "last") {
    return(list(html = result_html(last_games(sides, team_ids), cbb$teams, ranks), header = "Last game"))
  }
  ahead <- sides[is.na(sides$points_for), , drop = FALSE]
  games <- next_games(ahead, team_ids)
  line <- our_lines(games, cbb$teams, function(team, opponent, site) {
    cbb_predict(team, opponent, site, cbb$teams, cbb$params)$spread
  })
  # The slate only reaches a few days ahead.
  list(html = upcoming_html(games, line, none = "None in the next few days", teams = cbb$teams, ranks = ranks,
                            market = market_lines(games, cbb$teams, cbb$slate)),
       header = "Next game")
}

#' Our own top 25, for the numbers beside basketball team names. There is
#' no poll in the basketball data.
cbb_team_ranks <- function(ranking, top = 25) {
  best <- ranking[!is.na(ranking$rank) & ranking$rank <= top, , drop = FALSE]
  stats::setNames(as.integer(best$rank), best$team_id)
}

# Server ------------------------------------------------------------------------

#' @return list(load = function(matchup)): opens list(a, b, site) on the page.
mod_cbb_matchup_server <- function(id, cbb) {
  shiny::moduleServer(id, function(input, output, session) {
    pred <- shiny::reactive({
      a <- suppressWarnings(as.integer(input$team_a))
      b <- suppressWarnings(as.integer(input$team_b))
      shiny::req(!is.na(a), !is.na(b), a != b, input$site %in% SITE_CHOICES)
      tryCatch(cbb_predict(a, b, input$site, cbb$teams, cbb$params), error = function(e) e)
    })
    ok_pred <- shiny::reactive({
      p <- pred()
      shiny::req(!inherits(p, "error"))
      p
    })
    colors <- shiny::reactive(pick_team_colors(ok_pred()$team_a, ok_pred()$team_b))

    output$headline <- shiny::renderUI({
      p <- pred()
      if (inherits(p, "error")) {
        return(htmltools::span(class = "headline-context",
                               paste("We couldn't predict this matchup.", conditionMessage(p))))
      }
      parts <- headline_parts(p)
      parts$context <- sub("neutral field", "neutral floor", parts$context, fixed = TRUE)
      htmltools::tagList(htmltools::span(class = "headline-answer", parts$answer),
                         " ", htmltools::span(class = "headline-context", parts$context))
    })
    output$band <- shiny::renderUI(matchup_band(ok_pred(), colors(), cbb_team_ranks(cbb_ranking_table(cbb))))
    output$range <- shiny::renderText(format_interval(ok_pred()))
    output$market <- shiny::renderUI(market_fact(market_view(ok_pred(), cbb$slate, cbb$params$sigma)))
    output$flags <- shiny::renderUI(flag_list(ok_pred()$flags))
    output$model_plot <- shiny::renderUI(model_plot(ok_pred(), colors()))
    output$model_table <- shiny::renderUI(cbb_model_table(ok_pred()))

    list(load = function(matchup) {
      session$sendCustomMessage("cfb-set-matchup", list(
        container = session$ns("pickers"),
        a = as.character(matchup$a), b = as.character(matchup$b), site = matchup$site
      ))
    })
  })
}

#' @param on_open Called with list(a, b, site) to open a game in Matchup.
mod_cbb_slate_server <- function(id, cbb, on_open) {
  shiny::moduleServer(id, function(input, output, session) {
    if (nrow(cbb$slate) == 0) return(invisible(NULL))
    output$table <- DT::renderDT({
      shiny::req(input$day %in% cbb$slate$day)
      slate_table(cbb_slate_rows(cbb, input$day, session$ns("open"), cbb_team_ranks(cbb_ranking_table(cbb))))
    })
    shiny::observeEvent(input$open, {
      game <- cbb$slate[cbb$slate$game_id == input$open, , drop = FALSE]
      shiny::req(nrow(game) == 1)
      on_open(slate_matchup(game))
    })
  })
}

mod_cbb_rankings_server <- function(id, cbb) {
  shiny::moduleServer(id, function(input, output, session) {
    ranking <- cbb_ranking_table(cbb)
    by <- shiny::reactive(if (identical(input$by, "earned")) "earned" else "blend")
    shown <- shiny::reactive({
      listed <- ranking
      if (by() == "earned") {
        listed <- listed[!is.na(listed$earned), , drop = FALSE]
        listed <- listed[order(listed$earned, listed$rank), , drop = FALSE]
      }
      if (isTRUE(input$all)) listed else utils::head(listed, RANKINGS_SHOWN)
    })
    output$title_text <- shiny::renderText({
      kind <- tolower(RANKING_KINDS[[by()]])
      if (isTRUE(input$all)) sprintf("Every team: %s", kind) else sprintf("Top %d: %s", RANKINGS_SHOWN, kind)
    })
    sides <- cbb_team_games(cbb)
    output$table <- DT::renderDT({
      view <- ranking_view(input$view)
      rows <- cbb_ranking_rows(shown(), cbb$teams, by())
      if (view == "ranks") return(cbb_rankings_table(rows, by()))
      games <- cbb_games_column(cbb, sides, shown()$team_id, view, cbb_team_ranks(ranking))
      games_view_table(rows$rank, rows$team, rows$record, games$html, games$header)
    })
  })
}
