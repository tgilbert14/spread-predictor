# Matchup tab: pick two teams and a site, get the answer first, then the
# evidence. Everything recomputes from one reactive the moment an input
# changes. Picker behavior (swap, same-team prevention, site labels) runs in
# www/app.js so the pickers are never re-rendered.

SITE_ORDER <- c("a_home", "neutral", "b_home")

# UI ----------------------------------------------------------------------------

#' @param app_data See docs/data-dictionary.md.
#' @param initial list(a, b, site): the matchup to open with.
mod_matchup_ui <- function(id, app_data, initial) {
  ns <- shiny::NS(id)
  teams <- app_data$teams
  school_of <- function(team_id) teams$school[teams$team_id == team_id]

  htmltools::div(
    class = "page-narrow",
    htmltools::tags$section(
      class = "card picker-card", `aria-label` = "Choose a matchup",
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
      site_control(ns("site"), school_of(initial$a), school_of(initial$b), initial$site)
    ),
    answer_card(ns),
    htmltools::tags$section(
      class = "card evidence-card", `aria-labelledby` = ns("evidence-title"),
      htmltools::div(
        class = "card-body",
        htmltools::tags$h2(id = ns("evidence-title"), class = "section-title", "Where the models land"),
        htmltools::tags$p(class = "section-lede",
                          "Each rating system's margin on one scale. The blend is what we use."),
        shiny::uiOutput(ns("model_plot")),
        shiny::uiOutput(ns("model_table"))
      )
    )
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
      id, "Where is the game played?", inline = TRUE, width = "100%",
      choiceNames = lapply(SITE_ORDER, label_for), choiceValues = SITE_ORDER,
      selected = selected
    )
  )
}

#' The answer: headline, win probability, likely range, market, notes.
answer_card <- function(ns) {
  htmltools::tags$section(
    class = "card answer-card", `aria-label` = "Prediction",
    htmltools::div(
      class = "card-body",
      htmltools::div(
        class = "answer-top",
        htmltools::tags$p(class = "eyebrow", "Our line"),
        htmltools::tags$button(
          id = ns("copy"), type = "button", class = "btn btn-copy", `data-summary` = "",
          svg_icon("copy"), htmltools::span(class = "btn-copy-label", "Copy summary")
        )
      ),
      shiny::textOutput(ns("headline"), container = function(...) {
        htmltools::tags$h2(..., class = "headline", `aria-live` = "polite", `aria-atomic` = "true")
      }),
      shiny::uiOutput(ns("prob_bar")),
      htmltools::div(
        class = "range-line",
        htmltools::span(class = "range-label", "Most likely range"),
        shiny::textOutput(ns("range"), inline = TRUE),
        htmltools::span(class = "range-note", "Covers 80% of outcomes")
      ),
      shiny::uiOutput(ns("market")),
      shiny::uiOutput(ns("flags"))
    )
  )
}

# Pieces built from a prediction ------------------------------------------------

#' Win probability bar in the two team colors, labeled with text on both ends.
prob_bar <- function(pred, colors) {
  pct_a <- format_prob(pred$win_prob_a)
  pct_b <- format_prob(1 - pred$win_prob_a)
  width_a <- as.numeric(sub("%", "", pct_a))
  label <- sprintf("Win probability: %s %s, %s %s",
                   pred$team_a$school, pct_a, pred$team_b$school, pct_b)

  end <- function(school, pct, color, side) {
    htmltools::span(
      class = paste("prob-end", paste0("prob-end-", side)),
      htmltools::tags$strong(class = "prob-pct", pct),
      htmltools::span(class = "swatch", style = sprintf("background:%s", color)),
      htmltools::span(class = "prob-school", school)
    )
  }
  htmltools::div(
    class = "prob",
    htmltools::div(
      class = "prob-labels", `aria-hidden` = "true",
      end(pred$team_a$school, pct_a, colors[["a"]], "a"),
      end(pred$team_b$school, pct_b, colors[["b"]], "b")
    ),
    htmltools::div(
      class = "prob-bar", role = "img", `aria-label` = label,
      htmltools::span(class = "prob-seg", style = sprintf("width:%s%%;background:%s", width_a, colors[["a"]])),
      htmltools::span(class = "prob-seg", style = sprintf("width:%s%%;background:%s", 100 - width_a, colors[["b"]]))
    ),
    htmltools::p(class = "prob-caption", "Chance to win")
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
model_plot <- function(pred, colors) {
  models <- pred$models
  limit <- plot_limit(c(models$margin, pred$spread))
  step <- if (limit <= 28) 7 else 14
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
        # Text sits on the side facing the middle, where there is always room.
        htmltools::span(
          class = paste("dp-value", if (x <= 50) "to-right" else "to-left"),
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
    headers = list("Model", rating_header(name_a), rating_header(name_b), "Margin", "Weight"),
    numeric = c(FALSE, TRUE, TRUE, FALSE, TRUE),
    row_class = c(ifelse(left_out, "is-left-out", ""), "is-blend"),
    caption = "Ratings are points better than an average team, except Elo, which uses its own scale."
  )
}

rating_header <- function(school) {
  htmltools::tagList(school, htmltools::span(class = "hide-sm", " rating (rank)"))
}

#' The address-bar query for a prediction, using school names so links read well.
matchup_query <- function(pred) {
  enc <- function(x) utils::URLencode(x, reserved = TRUE)
  sprintf("?a=%s&b=%s&site=%s", enc(pred$team_a$school), enc(pred$team_b$school), pred$site)
}

# Server ------------------------------------------------------------------------

#' @param app_data See docs/data-dictionary.md.
#' @return list(load = function(matchup)): opens list(a, b, site) in the tab.
mod_matchup_server <- function(id, app_data) {
  shiny::moduleServer(id, function(input, output, session) {
    teams <- app_data$teams
    notes <- data_notes(app_data$meta)

    # The single reactive everything else reads. Invalid or half-updated
    # inputs (for example mid-swap) are skipped rather than shown as errors.
    pred <- shiny::reactive({
      a <- suppressWarnings(as.integer(input$team_a))
      b <- suppressWarnings(as.integer(input$team_b))
      shiny::req(!is.na(a), !is.na(b), a != b, input$site %in% SITE_CHOICES)
      tryCatch(predict_matchup(a, b, input$site, teams, app_data$params),
               error = function(e) e)
    })

    ok_pred <- shiny::reactive({
      p <- pred()
      shiny::req(!inherits(p, "error"))
      p
    })
    colors <- shiny::reactive(pick_team_colors(ok_pred()$team_a, ok_pred()$team_b))

    output$headline <- shiny::renderText({
      p <- pred()
      if (inherits(p, "error")) {
        return(paste("We couldn't predict this matchup.", conditionMessage(p)))
      }
      format_headline(p)
    })
    output$prob_bar <- shiny::renderUI(prob_bar(ok_pred(), colors()))
    output$range <- shiny::renderText(format_interval(ok_pred()))
    output$market <- shiny::renderUI({
      text <- describe_market(ok_pred(), app_data$slate)
      if (!is.null(text)) htmltools::p(class = "market-line", text)
    })
    output$flags <- shiny::renderUI(flag_list(c(ok_pred()$flags, notes)))
    output$model_plot <- shiny::renderUI(model_plot(ok_pred(), colors()))
    output$model_table <- shiny::renderUI(model_table(ok_pred()))

    # Keep the copy text and the shareable URL in step with the prediction.
    shiny::observe({
      p <- ok_pred()
      session$sendCustomMessage("cfb-summary", list(id = session$ns("copy"), text = format_summary(p)))
      shiny::updateQueryString(matchup_query(p), mode = "replace")
    })

    list(
      load = function(matchup) {
        session$sendCustomMessage("cfb-set-matchup", list(
          container = session$ns("pickers"),
          a = as.character(matchup$a), b = as.character(matchup$b), site = matchup$site
        ))
      }
    )
  })
}
