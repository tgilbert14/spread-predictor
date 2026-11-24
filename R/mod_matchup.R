# Matchup tab: pick two teams and a site, get the answer first, then the
# evidence. "Ratings as of" swaps in an earlier week's ratings (a snapshot,
# see R/snapshot.R). Everything recomputes from one reactive the moment an
# input changes. Picker behavior (swap, same-team prevention, site labels) runs in
# www/app.js so the pickers are never re-rendered.

SITE_ORDER <- c("a_home", "neutral", "b_home")

# UI ----------------------------------------------------------------------------

#' @param app_data See docs/data-dictionary.md.
#' @param initial list(a, b, site, week): the matchup to open with. `week`
#'   is the snapshot week; NULL opens this week.
mod_matchup_ui <- function(id, app_data, initial) {
  ns <- shiny::NS(id)
  teams <- app_data$teams
  has_trend <- length(snapshot_weeks(app_data)) >= 2
  school_of <- function(team_id) teams$school[teams$team_id == team_id]

  htmltools::div(
    class = "page-narrow",
    htmltools::tags$section(
      class = "picker-panel", `aria-label` = "Choose a matchup",
      id = ns("pickers"),
      `data-team-a` = ns("team_a"), `data-team-b` = ns("team_b"), `data-site` = ns("site"),
      htmltools::div(
        class = "picker-row",
        team_picker(ns("team_a"), "Team A", teams, initial$a),
        htmltools::tags$button(
          type = "button", class = "btn swap-btn", `data-swap` = ns("pickers"),
          `aria-label` = "Swap teams", title = "Swap teams", svg_icon("swap")
        ),
        team_picker(ns("team_b"), "Team B", teams, initial$b)
      ),
      site_control(ns("site"), school_of(initial$a), school_of(initial$b), initial$site),
      snapshot_control(ns, app_data, initial$week)
    ),
    shiny::uiOutput(ns("snapshot_banner")),
    answer_card(ns),
    htmltools::tags$section(
      class = "evidence", `aria-labelledby` = ns("evidence-title"),
      htmltools::tags$h2(id = ns("evidence-title"), class = "section-title", "Where the models land"),
      htmltools::tags$p(class = "section-lede",
                        "Each rating system's margin on one scale. The blend is what we use."),
      shiny::uiOutput(ns("model_plot")),
      shiny::uiOutput(ns("model_table"))
    ),
    if (has_trend) season_section(ns, app_data)
  )
}

#' "Ratings as of": the snapshot week, with a button that explains it.
#'
#' The explanation opens on a click, not a hover, so it works on a phone.
snapshot_control <- function(ns, app_data, selected = NULL) {
  choices <- snapshot_choices(app_data)
  if (is.null(selected)) selected <- app_data$meta$week
  htmltools::div(
    class = "snapshot-control",
    htmltools::div(
      class = "snapshot-label",
      htmltools::tags$label(class = "control-label", `for` = ns("week"), "Ratings as of"),
      bslib::popover(
        htmltools::tags$button(type = "button", class = "info-btn",
                               `aria-label` = "What is a snapshot?", svg_icon("info")),
        SNAPSHOT_HELP,
        title = "What is a snapshot?"
      )
    ),
    shiny::selectInput(ns("week"), label = NULL, choices = choices,
                       selected = as.character(selected), selectize = FALSE, width = "100%")
  )
}

#' The strip above the answer while an earlier week's ratings are on show.
snapshot_banner <- function(ns, week) {
  htmltools::div(
    class = "snapshot-banner", role = "status",
    svg_icon("info"),
    htmltools::span(sprintf("Snapshot: the ratings going into week %d.", week)),
    shiny::actionLink(ns("this_week"), "Back to this week")
  )
}

#' "Through the season": the two week-by-week charts.
season_section <- function(ns, app_data) {
  history <- app_data$history
  partial <- vapply(snapshot_weeks(app_data), function(week) {
    length(models_missing_in_week(history, week)) > 0
  }, logical(1))
  htmltools::tags$section(
    class = "evidence", `aria-labelledby` = ns("season-title"),
    htmltools::tags$h2(id = ns("season-title"), class = "section-title", "Through the season"),
    htmltools::tags$h3(class = "chart-title", "This matchup, week by week"),
    htmltools::tags$p(
      class = "section-lede",
      "Each system's line for these two teams, from the ratings it had going into each week.",
      "The dotted line marks the week on show.",
      if (any(partial)) "The blend is dashed in weeks where some systems were not saved yet."
    ),
    shiny::plotOutput(ns("matchup_trend"), height = "340px", click = ns("trend_click"),
                      hover = shiny::hoverOpts(ns("trend_hover"), delay = 60, delayType = "throttle")),
    htmltools::tags$p(class = "chart-readout",
                      shiny::textOutput(ns("trend_readout"), inline = TRUE),
                      htmltools::span(class = "range-note", "Hover or tap the chart to read another week.")),
    htmltools::tags$h3(class = "chart-title", "Team ratings, week by week"),
    htmltools::tags$p(
      class = "section-lede",
      "How each system has rated the two teams. Each system has its own panel",
      "because Elo runs on a different scale from the rest."
    ),
    shiny::plotOutput(ns("rating_trend"), height = "auto")
  )
}

#' Team search box. Options carry logo, colors and search fields; www/app.js
#' renders them. The plain grouped choices keep it working before JS loads.
team_picker <- function(id, label, teams, selected) {
  conferences <- sort(unique(teams$conference))
  htmltools::div(
    class = "picker",
    shiny::selectizeInput(
      id, label, choices = team_choices(teams), selected = selected, width = "100%",
      options = list(
        options = team_options(teams),
        optgroups = lapply(conferences, function(x) list(value = x, label = x)),
        optgroupField = "conference",
        lockOptgroupOrder = TRUE,
        labelField = "school",
        searchField = c("school", "mascot", "abbreviation"),
        sortField = list(list(field = "$score", direction = "desc"),
                         list(field = "school", direction = "asc")),
        placeholder = "Search school, mascot or abbreviation",
        dropdownParent = "body",
        render = I("window.cfbTeamRender")
      )
    )
  )
}

#' Three-way segmented control. The team names in the labels are updated by
#' www/app.js when a picker changes, so the control itself never re-renders.
site_control <- function(id, school_a, school_b, selected) {
  # One wrapping span per label keeps the space before "home" intact.
  home_label <- function(side, school) {
    htmltools::span(htmltools::span(class = "site-team", `data-side` = side, school), " home")
  }
  label_for <- function(site) {
    switch(site,
      a_home  = home_label("a", school_a),
      neutral = htmltools::span("Neutral"),
      b_home  = home_label("b", school_b)
    )
  }
  htmltools::div(
    class = "segmented",
    shiny::radioButtons(
      id, "Where is it played?", inline = TRUE, width = "100%",
      choiceNames = lapply(SITE_ORDER, label_for), choiceValues = SITE_ORDER,
      selected = selected
    )
  )
}

#' The answer: our line in words, the two teams' chances, the likely range,
#' the market's line beside ours, then any notes.
answer_card <- function(ns) {
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
      shiny::uiOutput(ns("flags")),
      htmltools::tags$button(
        id = ns("copy"), type = "button", class = "btn btn-copy", `data-summary` = "",
        svg_icon("copy"), htmltools::span(class = "btn-copy-label", "Copy summary")
      )
    ),
    shiny::uiOutput(ns("notes"))
  )
}

# Pieces built from a prediction ------------------------------------------------

#' The line in two parts: the answer, set large, and the context under it.
#'
#' The context places the favorite ("at home", "on the road") instead of
#' repeating a school name, so it reads the way people say it.
headline_parts <- function(pred) {
  name_a <- pred$team_a$school
  name_b <- pred$team_b$school
  if (round_half(pred$spread) == 0) {
    return(list(answer = "Pick'em",
                context = paste(name_a, "vs", name_b, site_phrase(pred$site, name_a, name_b))))
  }
  a_favored <- pred$spread > 0
  favorite_site <- if (a_favored) "a_home" else "b_home"
  where <- if (pred$site == "neutral") {
    "on a neutral field"
  } else if (pred$site == favorite_site) {
    "at home"
  } else {
    "on the road"
  }
  list(answer = format_favorite(pred$spread, name_a, name_b),
       context = paste("over", if (a_favored) name_b else name_a, where))
}

# The seam never gets closer to an edge than this (percent), so the smaller
# side always has room for its number. The printed percentages stay exact.
BAND_MIN_SHARE <- 22

#' The two teams' chances as one band in their colors, split where the odds
#' fall. Names sit above it, percentages inside it.
matchup_band <- function(pred, colors, ranks = NULL) {
  pct_a <- format_prob(pred$win_prob_a)
  pct_b <- format_prob(1 - pred$win_prob_a)
  share <- as.numeric(sub("%", "", pct_a))
  share <- min(max(share, BAND_MIN_SHARE), 100 - BAND_MIN_SHARE)
  label <- sprintf("Chance to win: %s %s, %s %s",
                   pred$team_a$school, pct_a, pred$team_b$school, pct_b)

  nameplate <- function(team, side) {
    rank <- if (is.null(ranks)) NA else rank_of(ranks, team$team_id)
    htmltools::span(class = paste("band-name", paste0("band-name-", side)),
                    team_badge(team, "md"),
                    htmltools::span(class = "band-school",
                                    if (!is.na(rank)) htmltools::span(class = "team-rank", rank), team$school))
  }
  field <- function(pct, color, side) {
    htmltools::span(
      class = paste("band-side", paste0("band-side-", side)),
      style = sprintf("background:%s;color:%s", color, readable_text_color(color)),
      htmltools::span(class = "band-pct", pct)
    )
  }
  htmltools::div(
    class = "band-wrap",
    htmltools::div(class = "band-names", `aria-hidden` = "true",
                   nameplate(pred$team_a, "a"), nameplate(pred$team_b, "b")),
    htmltools::div(
      class = "band", role = "img", `aria-label` = label, style = sprintf("--share:%s%%", share),
      field(pct_a, colors[["a"]], "a"), field(pct_b, colors[["b"]], "b")
    ),
    htmltools::p(class = "band-caption", "Chance to win")
  )
}

#' Short "IRN by 3.5" label for a dot, so it fits on a phone.
short_favorite <- function(margin, team_a, team_b) {
  short_a <- team_initials(team_a$school, team_a$abbreviation)
  short_b <- team_initials(team_b$school, team_b$abbreviation)
  if (round_half(margin) == 0) return("Even")
  paste(if (margin > 0) short_a else short_b, "by", format_points(margin))
}

#' Axis half-width in points: a touchdown multiple with room past the widest dot.
plot_limit <- function(margins) {
  widest <- max(abs(margins), na.rm = TRUE)
  max(7, ceiling((widest + 1.5) / 7) * 7)
}

#' "Where the models land": one shared axis, one row per model plus the blend.
#'
#' Team A is favored to the left, matching its place in the pickers and the
#' win probability bar. Rows keep labels from colliding when models agree.
#' Which side of its dot a value label sits on: "to-left" or "to-right".
#'
#' A dot out toward an edge gets its label on the side facing the middle,
#' where there is room. A dot near the middle gets it on the outside, so the
#' text never runs across the center line.
#'
#' @param x The dot's position, 0 to 100 percent of the track.
value_side <- function(x, near_middle = 25) {
  faces_middle <- abs(x - 50) >= near_middle
  if ((x <= 50) == faces_middle) "to-right" else "to-left"
}

model_plot <- function(pred, colors) {
  models <- pred$models
  limit <- plot_limit(c(models$margin, pred$spread))
  # Close games get field-goal ticks so the axis is never bare.
  step <- if (limit <= 7) 3 else if (limit <= 28) 7 else 14
  position <- function(margin) 50 - 50 * margin / limit

  dot_row <- function(label, margin, row_class = NULL) {
    if (is.na(margin)) {
      return(htmltools::div(
        class = paste("dp-row is-left-out", row_class),
        htmltools::span(class = "dp-label", label),
        htmltools::div(class = "dp-track", htmltools::span(class = "dp-missing", "No rating"))
      ))
    }
    x <- position(margin)
    htmltools::div(
      class = paste("dp-row", row_class),
      htmltools::span(class = "dp-label", label),
      htmltools::div(
        class = "dp-track",
        htmltools::span(class = "dp-dot", style = sprintf("left:%.2f%%", x)),
        htmltools::span(
          class = paste("dp-value", value_side(x)),
          style = sprintf("left:%.2f%%", x),
          short_favorite(margin, pred$team_a, pred$team_b)
        )
      )
    )
  }

  ticks <- step * seq_len(floor((limit - 1) / step))
  gridlines <- c(
    lapply(c(-ticks, ticks), function(t) {
      htmltools::span(class = "dp-gridline", style = sprintf("left:%.2f%%", position(t)))
    }),
    list(htmltools::span(class = "dp-gridline is-zero", style = "left:50%"))
  )
  tick_labels <- c(
    lapply(c(-ticks, ticks), function(t) {
      htmltools::span(class = "dp-tick", style = sprintf("left:%.2f%%", position(t)), format_points(t))
    }),
    list(htmltools::span(class = "dp-tick is-zero", style = "left:50%", "Even"))
  )

  name_a <- pred$team_a$school
  name_b <- pred$team_b$school
  summary <- paste0(
    "Where the models land, in points. ",
    paste(sprintf("%s: %s.", models$label, vapply(models$margin, function(x) {
      if (is.na(x)) "no rating" else format_favorite(x, name_a, name_b)
    }, character(1))), collapse = " "),
    sprintf(" Blend: %s.", format_favorite(pred$spread, name_a, name_b))
  )

  htmltools::div(
    class = "dotplot", role = "img", `aria-label` = summary,
    # The "1F" suffix is about 12% alpha, for the faint tint behind each half.
    style = sprintf("--team-a:%s;--team-b:%s;--team-a-tint:%s1F;--team-b-tint:%s1F",
                    colors[["a"]], colors[["b"]], colors[["a"]], colors[["b"]]),
    htmltools::div(
      class = "dp-ends", `aria-hidden` = "true",
      htmltools::span(class = "dp-end dp-end-a", htmltools::span(class = "swatch"),
                      paste(name_a, "favored")),
      htmltools::span(class = "dp-end dp-end-b", paste(name_b, "favored"),
                      htmltools::span(class = "swatch"))
    ),
    htmltools::div(
      class = "dp-body", `aria-hidden` = "true",
      htmltools::div(class = "dp-grid", gridlines),
      lapply(seq_len(nrow(models)), function(i) {
        dot_row(models$label[i], if (models$weight[i] > 0) models$margin[i] else NA)
      }),
      dot_row("Blend", pred$spread, "dp-blend")
    ),
    htmltools::div(class = "dp-axis", `aria-hidden` = "true",
                   htmltools::span(class = "dp-label"),
                   htmltools::div(class = "dp-ticks", tick_labels))
  )
}

#' Model-by-model table: ratings, ranks, margin in words, weight.
model_table <- function(pred) {
  m <- pred$models
  name_a <- pred$team_a$school
  name_b <- pred$team_b$school
  left_out <- m$weight == 0

  rows <- data.frame(
    model = m$label,
    a = mapply(format_rating_rank, m$rating_a, m$rank_a, m$model),
    b = mapply(format_rating_rank, m$rating_b, m$rank_b, m$model),
    margin = vapply(m$margin, function(x) {
      if (is.na(x)) "No rating" else format_favorite(x, name_a, name_b)
    }, character(1)),
    weight = format_weight(m$weight),
    stringsAsFactors = FALSE
  )
  rows <- rbind(rows, data.frame(model = "Blend", a = "", b = "",
                                 margin = format_favorite(pred$spread, name_a, name_b),
                                 weight = "100%"))

  simple_table(
    rows,
    # "rating (rank)" is dropped on phones so the headers do not wrap into towers.
    headers = list("Model", rating_header(pred$team_a), rating_header(pred$team_b), "Margin", "Weight"),
    numeric = c(FALSE, TRUE, TRUE, FALSE, TRUE),
    row_class = c(ifelse(left_out, "is-left-out", ""), "is-blend"),
    caption = paste("Ratings are points better than an average team, except Elo, which uses its own scale.",
                    "SP+, FPI and SRS margins are trimmed to the scale point spreads use, so they can be smaller than the rating gap.",
                    "Power is our own rating, built from game scores and success rate. Elo's margin includes the power-conference correction.")
  )
}

#' A ratings column header: the team's small logo, its name, and on wider
#' screens what the numbers under it are.
rating_header <- function(team) {
  htmltools::span(class = "rating-header", team_badge(team, "xs", decorative = TRUE),
                  htmltools::span(team$school, htmltools::span(class = "hide-sm", " rating (rank)")))
}

#' The line-movement note for a slate game, with the weekday its
#' prediction was saved, or NULL.
slate_line_note <- function(game, app_data) {
  if (is.null(game)) return(NULL)
  school <- function(team_id) app_data$teams$school[match(team_id, app_data$teams$team_id)]
  saved <- app_data$scorecard$games
  frozen_at <- saved$frozen_at[match(game$game_id, saved$game_id)]
  line_move_note(game, school(game$home_id), school(game$away_id), frozen_at)
}

#' The address-bar query for a prediction, using school names so links read well.
#'
#' @param week The snapshot week, or NULL for this week (left out of the link).
matchup_query <- function(pred, week = NULL) {
  enc <- function(x) utils::URLencode(x, reserved = TRUE)
  query <- sprintf("?a=%s&b=%s&site=%s", enc(pred$team_a$school), enc(pred$team_b$school), pred$site)
  if (is.null(week)) query else sprintf("%s&week=%d", query, as.integer(week))
}

# Server ------------------------------------------------------------------------

#' @param app_data See docs/data-dictionary.md.
#' @param notes This week's game notes (app_notes()).
#' @return list(load = function(matchup)): opens list(a, b, site) in the tab.
mod_matchup_server <- function(id, app_data, notes) {
  shiny::moduleServer(id, function(input, output, session) {
    data_flags <- data_notes(app_data$meta)
    this_week <- as.integer(app_data$meta$week)
    weeks <- snapshot_weeks(app_data)
    # Every week's teams table, built once. A snapshot only swaps the table.
    teams_by_week <- stats::setNames(lapply(weeks, function(w) snapshot_teams(app_data, w)), weeks)

    # The week whose ratings are on show. Anything unexpected means this week.
    week <- shiny::reactive({
      picked <- suppressWarnings(as.integer(input$week))
      if (length(picked) == 1 && picked %in% weeks) picked else this_week
    })
    is_snapshot <- shiny::reactive(week() != this_week)

    # The single reactive everything else reads. Invalid or half-updated
    # inputs (for example mid-swap) are skipped rather than shown as errors.
    pred <- shiny::reactive({
      a <- suppressWarnings(as.integer(input$team_a))
      b <- suppressWarnings(as.integer(input$team_b))
      shiny::req(!is.na(a), !is.na(b), a != b, input$site %in% SITE_CHOICES)
      tryCatch(predict_matchup(a, b, input$site, teams_by_week[[as.character(week())]],
                               app_data$params, week = week()),
               error = function(e) e)
    })

    ok_pred <- shiny::reactive({
      p <- pred()
      shiny::req(!inherits(p, "error"))
      p
    })
    colors <- shiny::reactive(pick_team_colors(ok_pred()$team_a, ok_pred()$team_b))
    # The games on the This week tab: this week's, or next week's once this
    # week is played. Their market lines show here too.
    shown_games <- shown_slate(app_data)$games
    # The real game between these two teams this week, or NULL. A snapshot
    # is about an earlier week, so this week's game does not apply to it.
    slate_game <- shiny::reactive({
      if (is_snapshot()) return(NULL)
      find_slate_game(shown_games, ok_pred()$team_a$team_id, ok_pred()$team_b$team_id)
    })

    output$headline <- shiny::renderUI({
      p <- pred()
      if (inherits(p, "error")) {
        return(htmltools::span(class = "headline-context",
                               paste("We couldn't predict this matchup.", conditionMessage(p))))
      }
      parts <- headline_parts(p)
      htmltools::tagList(htmltools::span(class = "headline-answer", parts$answer),
                         " ", htmltools::span(class = "headline-context", parts$context))
    })
    output$band <- shiny::renderUI(matchup_band(ok_pred(), colors(), team_ranks(app_data)))
    output$range <- shiny::renderText(format_interval(ok_pred()))
    # This week's market line. A snapshot shows how the game turned out instead.
    market <- shiny::reactive({
      if (is_snapshot()) return(NULL)
      market_view(ok_pred(), shown_games, app_data$params$sigma)
    })
    record <- market_record(app_data$params$metrics)
    output$market <- shiny::renderUI({
      if (!is_snapshot()) return(market_fact(market(), record))
      p <- ok_pred()
      snapshot_result_fact(snapshot_result(app_data, week(), p$team_a$team_id, p$team_b$team_id))
    })
    output$flags <- shiny::renderUI({
      if (is_snapshot()) return(flag_list(snapshot_flags(ok_pred(), app_data$history, week())))
      flag_list(c(ok_pred()$flags, slate_line_note(slate_game(), app_data), data_flags))
    })
    output$snapshot_banner <- shiny::renderUI({
      if (is_snapshot()) snapshot_banner(session$ns, week())
    })
    shiny::observeEvent(input$this_week, {
      shiny::updateSelectInput(session, "week", selected = as.character(this_week))
    })
    output$notes <- shiny::renderUI({
      game <- slate_game()
      if (is.null(game)) return(NULL)
      game_notes(notes[notes$game_id == game$game_id, , drop = FALSE], session$ns("notes-title"))
    })
    output$model_plot <- shiny::renderUI(model_plot(ok_pred(), colors()))
    output$model_table <- shiny::renderUI(model_table(ok_pred()))

    # Through the season: the same matchup on every week's ratings.
    trend <- shiny::reactive({
      p <- ok_pred()
      matchup_trend(p$team_a$team_id, p$team_b$team_id, p$site, teams_by_week, app_data$params)
    })
    plot_width <- function(output_id) {
      session$clientData[[paste0("output_", session$ns(output_id), "_width")]]
    }
    is_narrow <- function(output_id) {
      width <- plot_width(output_id)
      !is.null(width) && width < 520
    }
    output$matchup_trend <- shiny::renderPlot(
      matchup_trend_plot(trend(), ok_pred(), week(), is_narrow("matchup_trend")),
      bg = "transparent", alt = shiny::reactive(matchup_trend_alt(trend(), ok_pred()))
    )
    # The week spelled out under the chart: the one on show until the reader
    # hovers or taps another.
    readout_week <- shiny::reactiveVal(this_week)
    shiny::observeEvent(week(), readout_week(week()))
    point_at <- function(event) {
      if (is.null(event$x)) return()
      readout_week(min(max(round(event$x), min(weeks)), max(weeks)))
    }
    shiny::observeEvent(input$trend_hover, point_at(input$trend_hover))
    shiny::observeEvent(input$trend_click, point_at(input$trend_click))
    output$trend_readout <- shiny::renderText(matchup_trend_readout(trend(), readout_week(), ok_pred()))

    ratings <- shiny::reactive({
      p <- ok_pred()
      # The history can run one week past the snapshots, for the committee
      # prediction. The chart stops where the snapshots do.
      rating_trend(app_data$history[app_data$history$week <= this_week, , drop = FALSE],
                   c(p$team_a$team_id, p$team_b$team_id))
    })
    # Three panels across, or two on a phone.
    rating_columns <- shiny::reactive(if (is_narrow("rating_trend")) 2 else 3)
    output$rating_trend <- shiny::renderPlot(
      rating_trend_plot(ratings(), ok_pred(), colors(), week(), rating_columns()),
      height = function() 60 + 190 * ceiling(length(MODEL_LABELS) / rating_columns()),
      bg = "transparent", alt = shiny::reactive(rating_trend_alt(ratings(), ok_pred()))
    )

    # Keep the copy text and the shareable URL in step with the prediction.
    shiny::observe({
      p <- ok_pred()
      snapshot <- if (is_snapshot()) sprintf("Snapshot from the ratings going into week %d.", week())
      summary <- paste(c(snapshot, format_summary(p), describe_market(market())), collapse = " ")
      session$sendCustomMessage("cfb-summary", list(id = session$ns("copy"), text = summary))
      shiny::updateQueryString(matchup_query(p, if (is_snapshot()) week()), mode = "replace")
    })

    list(
      load = function(matchup) {
        # A game opened from this week's slate is always shown on this week's ratings.
        shiny::updateSelectInput(session, "week", selected = as.character(this_week))
        session$sendCustomMessage("cfb-set-matchup", list(
          container = session$ns("pickers"),
          a = as.character(matchup$a), b = as.character(matchup$b), site = matchup$site
        ))
      }
    )
  })
}
