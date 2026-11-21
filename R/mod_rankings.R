# Rankings tab: our Top 50 with every system's rank beside it, how far each
# team moved since last week, and the committee's and AP's rankings for
# comparison. The numbers come from R/rankings.R.

# The table's column lists (rankings_headers(), RANKINGS_SORTED) live in
# R/rankings.R, which loads after the rating systems are named.

RANKINGS_HELP <- paste(
  "Who would win: the blend of five rating systems that sets our spreads.",
  "Rating is points better than an average team on a neutral field,",
  "so the gap between two teams is our neutral-site line for them.",
  "Who has earned it: results only. Each win counts for more the better the opponent and the harder the site,",
  "measured against what a top-10 team would do with the same schedule.",
  "No credit for winning big, and no bonus for a conference."
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
          "Two rankings of our own. Who would win is the blend behind our spreads.",
          "Who has earned it looks only at results and how hard they were to get.",
          "Each rating system's rank sits beside them, then our guess at the committee, the committee itself, and the AP.",
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
          htmltools::div(
            class = "segmented rank-by",
            shiny::radioButtons(ns("by"), "Rank by", inline = TRUE, width = "100%",
                                choiceNames = unname(RANKING_KINDS), choiceValues = names(RANKING_KINDS),
                                selected = "blend")
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
#' @param ranking What ranking_table() returns, already in the order to show.
#' @param teams The teams table, for names, conferences and logos.
#' @param by "blend" or "earned": which of our rankings numbers the rows.
#'   The other one gets a column of its own.
ranking_rows <- function(ranking, teams, by = "blend") {
  # Line the chosen ranking up under the names the table sorts by.
  if (by == "earned") {
    ranking$other <- ranking$rank
    ranking$rank <- ranking$earned
    ranking$change <- ranking$earned_change
  } else {
    ranking$other <- ranking$earned
  }
  at <- match(ranking$team_id, teams$team_id)
  team <- vapply(seq_along(at), function(i) {
    row <- teams[at[i], , drop = FALSE]
    sprintf('%s<span class="rank-conference">%s</span>', team_name_html(row, row$school),
            htmltools::htmlEscape(row$conference))
  }, character(1))
  rows <- data.frame(rank = ranking$rank, move = format_move(ranking$change), team = team,
                     record = ranking$record, rating = sprintf("%+.1f", ranking$rating),
                     stringsAsFactors = FALSE)
  for (column in c(names(MODEL_LABELS), "other", "committee_style", names(POLL_NAMES))) {
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
rankings_table <- function(rows, by = "blend") {
  headers <- rankings_headers(by)
  n_visible <- length(headers)
  key_of <- function(column) n_visible + match(column, RANKINGS_SORTED) - 1
  sorted_by <- function(target, column, ...) c(list(targets = target, orderData = key_of(column)), list(...))
  ranks <- c(names(MODEL_LABELS), "other", "committee_style", names(POLL_NAMES))
  DT::datatable(
    rows,
    colnames = c(headers, paste0(RANKINGS_SORTED, "_key")),
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
                    className = paste("dt-right", if (ranks[i] == "other") "rank-earned"))
        })
      )
    )
  )
}

#' The sentences on how close our guess came, and which system is nearest.
closest_sentence <- function(similarity) {
  spots <- function(row) sprintf("%s (%.1f places off on average)", row$label, row$avg_gap)
  guess <- similarity[similarity$id == "committee_style", , drop = FALSE]
  systems <- similarity[similarity$id %in% c("blend", names(MODEL_LABELS)), , drop = FALSE]
  earned <- similarity[similarity$id == "earned", , drop = FALSE]
  ap <- similarity[similarity$id == "ap", , drop = FALSE]
  parts <- c(
    if (nrow(guess) == 1) sprintf("Our CFP guess is %.1f places off the committee this week, on average.", guess$avg_gap),
    if (nrow(earned) == 1) sprintf("Our earned-it ranking is %.1f off.", earned$avg_gap),
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
    earned = ifelse(is.na(committee$earned), "", as.character(committee$earned)),
    ours = committee$rank,
    ap = ifelse(is.na(committee$ap), "", as.character(committee$ap)),
    stringsAsFactors = FALSE
  )
  htmltools::tagList(
    htmltools::p(
      class = "section-lede",
      "The committee ranks what teams have earned so far.",
      "Our CFP guess tries to predict its list: it scores each team's results the way the committee has rewarded them in past seasons.",
      "That includes two things our own earned-it ranking leaves out on purpose: some credit for looking strong, and a bonus for power-conference teams."
    ),
    htmltools::p(class = "closest-line", closest_sentence(similarity)),
    htmltools::div(
      class = "committee-grid",
      simple_table(
        rows,
        headers = list("CFP", "Team", "Record", "Our CFP guess", "Earned it", "Would win", "AP"),
        numeric = c(TRUE, FALSE, FALSE, TRUE, TRUE, TRUE, TRUE),
        caption = paste("Our CFP guess scores results the way the committee has in past seasons.",
                        "Earned it and Would win are the team's places in our two rankings above."),
        html = c(FALSE, TRUE, FALSE, FALSE, FALSE, FALSE, FALSE)
      ),
      simple_table(
        data.frame(label = similarity$label, gap = sprintf("%.1f", similarity$avg_gap)),
        headers = list("Ranking", "Places off"),
        numeric = c(FALSE, TRUE),
        row_class = ifelse(similarity$id %in% c("committee_style", "earned", "blend"), "is-ours", ""),
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
    by <- shiny::reactive(if (identical(input$by, "earned")) "earned" else "blend")
    shown <- shiny::reactive({
      listed <- ranking()
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
    output$table <- DT::renderDT(rankings_table(ranking_rows(shown(), app_data$teams, by()), by()))
    output$table_note <- shiny::renderUI({
      notes <- c(
        "Record is going into that week's games.",
        if (by() == "blend" && all(is.na(ranking()$change))) {
          "Move needs the week before to blend the same systems, so it is blank here."
        },
        if (by() == "earned" && nrow(shown()) == 0) "No games have been played before this week, so no one has earned anything yet.",
        snapshot_missing_note(app_data$history, week())
      )
      htmltools::p(class = "fine-print", paste(notes, collapse = " "))
    })
    output$committee <- shiny::renderUI(committee_block(ranking(), app_data$teams, week()))
  })
}
