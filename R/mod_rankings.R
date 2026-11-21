# Rankings tab: our Top 50 with every system's rank beside it, how far each
# team moved since last week, and the committee's and AP's rankings for
# comparison. The numbers come from R/rankings.R.

# The table's column lists (RANKINGS_VISIBLE, RANKINGS_SORTED) live in
# R/rankings.R, which loads after the rating systems are named.

RANKINGS_HELP <- paste(
  "Rating is how many points better than an average team we make each one on a neutral field.",
  "It is the same blend of five rating systems that sets our spreads,",
  "so the gap between two teams here is our neutral-site line for them."
)

# UI ----------------------------------------------------------------------------

#' @param app_data See docs/data-dictionary.md.
mod_rankings_ui <- function(id, app_data) {
  ns <- shiny::NS(id)
  htmltools::div(
    class = "page-wide",
    htmltools::tags$section(
      class = "card", `aria-labelledby` = ns("title"),
      htmltools::div(
        class = "card-body",
        htmltools::tags$h2(id = ns("title"), class = "section-title",
                           shiny::textOutput(ns("title_text"), inline = TRUE)),
        htmltools::p(
          class = "section-lede",
          "Ranked by who we think would win, not by who has earned the most.",
          "Each system's own rank sits beside ours.",
          "The last three columns rank who has earned the most: our guess at the committee, the committee itself, and the AP.",
          "Tap a column heading to sort by it."
        ),
        htmltools::div(
          class = "rankings-controls",
          htmltools::div(
            class = "snapshot-control",
            htmltools::div(
              class = "snapshot-label",
              htmltools::tags$label(class = "control-label", `for` = ns("week"), "Rankings as of"),
              bslib::popover(
                htmltools::tags$button(type = "button", class = "info-btn",
                                       `aria-label` = "How are teams ranked?", svg_icon("info")),
                RANKINGS_HELP, title = "How are teams ranked?"
              )
            ),
            shiny::selectInput(ns("week"), label = NULL, choices = snapshot_choices(app_data),
                               selected = as.character(app_data$meta$week), selectize = FALSE, width = "100%")
          ),
          shiny::checkboxInput(ns("all"), "Show every team", value = FALSE)
        ),
        htmltools::div(class = "rank-wrap", DT::DTOutput(ns("table"))),
        shiny::uiOutput(ns("table_note"))
      )
    ),
    htmltools::tags$section(
      class = "evidence", `aria-labelledby` = ns("committee-title"),
      htmltools::tags$h2(id = ns("committee-title"), class = "section-title", "Next to the committee"),
      shiny::uiOutput(ns("committee"))
    )
  )
}

# Pieces built from a ranking -----------------------------------------------------

#' Places moved since last week: an arrow and a number, or a dash.
#' The arrow's direction carries the meaning, so color is only a second cue.
format_move <- function(change) {
  vapply(change, function(x) {
    if (is.na(x)) return('<span class="muted" aria-label="no comparison">&ndash;</span>')
    if (x == 0) return('<span class="muted" aria-label="no change">&ndash;</span>')
    sprintf('<span class="move %s" aria-label="%s %d">%s%d</span>',
            if (x > 0) "move-up" else "move-down", if (x > 0) "up" else "down", abs(x),
            if (x > 0) "&#9650;" else "&#9660;", abs(x))
  }, character(1))
}

#' A rank as text, or a muted dash for a team that has none.
format_rank <- function(rank) {
  ifelse(is.na(rank), '<span class="muted">&ndash;</span>', as.character(rank))
}

#' One display row per ranked team, plus numeric keys for sorting.
#'
#' @param ranking What ranking_table() returns.
#' @param teams The teams table, for names, conferences and logos.
ranking_rows <- function(ranking, teams) {
  at <- match(ranking$team_id, teams$team_id)
  team <- vapply(seq_along(at), function(i) {
    row <- teams[at[i], , drop = FALSE]
    sprintf('%s<span class="rank-conference">%s</span>', team_name_html(row, row$school),
            htmltools::htmlEscape(row$conference))
  }, character(1))
  rows <- data.frame(rank = ranking$rank, move = format_move(ranking$change), team = team,
                     record = ranking$record, rating = sprintf("%+.1f", ranking$rating),
                     stringsAsFactors = FALSE)
  for (column in c(names(MODEL_LABELS), "committee_style", names(POLL_NAMES))) {
    rows[[column]] <- format_rank(ranking[[column]])
  }
  for (column in RANKINGS_SORTED) {
    key <- ranking[[column]]
    # Biggest climbers first when the Move column is sorted descending.
    rows[[paste0(column, "_key")]] <- if (column == "change") ifelse(is.na(key), 0, key) else ifelse(is.na(key), UNRANKED_KEY, key)
  }
  rows
}

#' The ranking as a sortable DT that matches the rest of the app.
rankings_table <- function(rows) {
  n_visible <- length(RANKINGS_VISIBLE)
  key_of <- function(column) n_visible + match(column, RANKINGS_SORTED) - 1
  sorted_by <- function(target, column, ...) c(list(targets = target, orderData = key_of(column)), list(...))
  ranks <- c(names(MODEL_LABELS), "committee_style", names(POLL_NAMES))
  DT::datatable(
    rows,
    colnames = c(RANKINGS_VISIBLE, paste0(RANKINGS_SORTED, "_key")),
    rownames = FALSE, escape = FALSE, selection = "none",
    style = "default", class = "rank-table",
    options = list(
      dom = "<'slate-search'f>t",
      paging = FALSE, info = FALSE, autoWidth = FALSE,
      order = list(),  # ranked order until someone sorts
      language = list(search = "", searchPlaceholder = "Find a team",
                      zeroRecords = "No teams match that search."),
      columnDefs = c(
        list(
          list(targets = n_visible - 1 + seq_along(RANKINGS_SORTED), visible = FALSE, searchable = FALSE),
          sorted_by(0, "rank", className = "dt-right rank-number", searchable = FALSE),
          sorted_by(1, "change", orderSequence = list("desc", "asc"), searchable = FALSE),
          list(targets = 3, orderable = FALSE, searchable = FALSE),
          sorted_by(4, "rating", className = "dt-right", orderSequence = list("desc", "asc"), searchable = FALSE)
        ),
        lapply(seq_along(ranks), function(i) {
          sorted_by(4 + i, ranks[i], searchable = FALSE,
                    className = paste("dt-right", if (ranks[i] == "committee_style") "rank-earned"))
        })
      )
    )
  )
}

#' "3 places higher", "1 place lower" or "same": where we have a team next
#' to where the committee has it.
format_gap <- function(ours, theirs) {
  gap <- theirs - ours
  ifelse(is.na(gap), "",
         ifelse(gap == 0, "same",
                sprintf("%d %s %s", abs(gap), ifelse(abs(gap) == 1, "place", "places"),
                        ifelse(gap > 0, "higher", "lower"))))
}

#' The sentences on how close our guess came, and which system is nearest.
closest_sentence <- function(similarity) {
  spots <- function(row) sprintf("%s (%.1f places off on average)", row$label, row$avg_gap)
  guess <- similarity[similarity$id == "committee_style", , drop = FALSE]
  systems <- similarity[similarity$id %in% c("blend", names(MODEL_LABELS)), , drop = FALSE]
  ap <- similarity[similarity$id == "ap", , drop = FALSE]
  parts <- c(
    if (nrow(guess) == 1) sprintf("Our CFP guess is %.1f places off the committee this week, on average.", guess$avg_gap),
    if (nrow(systems) > 0) sprintf("The closest who-would-win ranking is %s.", spots(systems[1, , drop = FALSE])),
    if (nrow(ap) == 1) sprintf("The AP poll, which also ranks by results, is %.1f off.", ap$avg_gap)
  )
  paste(parts, collapse = " ")
}

#' "Next to the committee": who tracks the committee most closely, then its
#' 25 teams with our rank beside each.
committee_block <- function(ranking, teams, week) {
  committee <- ranking[!is.na(ranking$cfp), , drop = FALSE]
  if (nrow(committee) == 0) {
    return(empty_state(
      sprintf("No committee ranking for week %d.", week),
      htmltools::p("The playoff committee starts ranking teams in early November and updates every Tuesday.",
                   "Its rankings show up here as they are released.")
    ))
  }
  committee <- committee[order(committee$cfp), , drop = FALSE]
  similarity <- committee_similarity(ranking)
  school <- teams$school[match(committee$team_id, teams$team_id)]
  rows <- data.frame(
    cfp = committee$cfp,
    team = vapply(seq_along(school), function(i) {
      team_name_html(teams[teams$team_id == committee$team_id[i], , drop = FALSE], school[i])
    }, character(1)),
    record = committee$record,
    guess = ifelse(is.na(committee$committee_style), "", as.character(committee$committee_style)),
    ours = committee$rank,
    gap = format_gap(committee$rank, committee$cfp),
    ap = ifelse(is.na(committee$ap), "", as.character(committee$ap)),
    stringsAsFactors = FALSE
  )
  htmltools::tagList(
    htmltools::p(
      class = "section-lede",
      "The committee ranks what teams have earned so far. Our Top 50 ranks who would win.",
      "Our CFP guess sits in between: it scores each team's results the way the committee has rewarded them in past seasons,",
      "using only the games played and our own Power rating."
    ),
    htmltools::p(class = "closest-line", closest_sentence(similarity)),
    htmltools::div(
      class = "committee-grid",
      simple_table(
        rows,
        headers = list("CFP", "Team", "Record", "Our CFP guess", "Top 50", "Top 50 vs CFP", "AP"),
        numeric = c(TRUE, FALSE, FALSE, TRUE, TRUE, FALSE, TRUE),
        caption = paste("Our CFP guess ranks teams by what they have earned, the way the committee has in past seasons.",
                        "Top 50 is the team's place in our who-would-win ranking above."),
        html = c(FALSE, TRUE, FALSE, FALSE, FALSE, FALSE, FALSE)
      ),
      simple_table(
        data.frame(label = similarity$label, gap = sprintf("%.1f", similarity$avg_gap)),
        headers = list("Ranking", "Places off"),
        numeric = c(FALSE, TRUE),
        row_class = ifelse(similarity$id == "committee_style", "is-blend", ""),
        caption = paste("Places off: across the committee's 25 teams, how far each ranking has them on average.",
                        "Smaller is closer. A team the AP leaves out counts as 26th.")
      )
    )
  )
}

# Server ------------------------------------------------------------------------

#' @param app_data See docs/data-dictionary.md.
mod_rankings_server <- function(id, app_data) {
  shiny::moduleServer(id, function(input, output, session) {
    this_week <- as.integer(app_data$meta$week)
    weeks <- snapshot_weeks(app_data)
    week <- shiny::reactive({
      picked <- suppressWarnings(as.integer(input$week))
      if (length(picked) == 1 && picked %in% weeks) picked else this_week
    })
    ranking <- shiny::reactive(ranking_table(app_data, week()))
    shown <- shiny::reactive({
      if (isTRUE(input$all)) ranking() else utils::head(ranking(), RANKINGS_SHOWN)
    })

    output$title_text <- shiny::renderText({
      if (isTRUE(input$all)) "Every team, ranked" else sprintf("Top %d", RANKINGS_SHOWN)
    })
    output$table <- DT::renderDT(rankings_table(ranking_rows(shown(), app_data$teams)))
    output$table_note <- shiny::renderUI({
      notes <- c(
        "Record is going into that week's games.",
        if (all(is.na(ranking()$change))) "Move needs the week before to blend the same systems, so it is blank here.",
        snapshot_missing_note(app_data$history, week())
      )
      htmltools::p(class = "fine-print", paste(notes, collapse = " "))
    })
    output$committee <- shiny::renderUI(committee_block(ranking(), app_data$teams, week()))
  })
}
