# CFB Spread Predictor: a Shiny app that blends SP+, FPI, SRS, Elo and our own
# Power rating into a spread and win probability for any two teams, and keeps
# score of how its saved predictions did.
#
# Run from the project root:
#   Rscript -e 'shiny::runApp(".")'
# Shiny loads every file in R/ before this one, so nothing is sourced here.

library(shiny)
library(bslib, warn.conflicts = FALSE)  # bslib::page masks utils::page; harmless here

# Real data when it exists, the made-up demo otherwise. A bad file falls back
# to the demo too, with a banner that says what to run.
loaded <- load_app_data(PATHS$app_data)
app_data <- loaded$data

# Game notes are read straight from data/notes.csv, not the app data, so
# notes added during the week show up without a rebuild.
notes <- app_notes(app_data)

# The UI is a function of the request so a shared link (?a=...&b=...&site=...)
# opens straight on that matchup, with no flash of the default first.
ui <- function(request) {
  initial <- matchup_from_query(request$QUERY_STRING, app_data$teams, default_matchup(app_data))

  page_navbar(
    title = "CFB Spread Predictor",
    id = "tabs",
    theme = app_theme(),
    fillable = FALSE,
    window_title = "CFB Spread Predictor",
    lang = "en",
    header = tagList(
      tags$head(
        tags$meta(name = "theme-color", content = BRAND$navy),
        # Inline icon, so the browser does not ask the server for a favicon.
        tags$link(rel = "icon", href = paste0(
          "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16'%3E",
          "%3Ccircle cx='8' cy='8' r='7' fill='%235eead4'/%3E%3C/svg%3E"
        )),
        tags$link(rel = "stylesheet", href = "styles.css"),
        tags$script(src = "app.js")
      ),
      data_banner(app_data$meta, loaded$error)
    ),
    footer = app_footer(),
    nav_panel("Matchup", value = "matchup", mod_matchup_ui("matchup", app_data, initial)),
    nav_panel("This week", value = "slate", mod_slate_ui("slate", app_data)),
    nav_panel("Scorecard", value = "scorecard", mod_scorecard_ui("scorecard", app_data)),
    nav_panel("Model report", value = "report", mod_report_ui("report", app_data)),
    nav_spacer(),
    nav_item(span(class = "freshness", freshness_label(app_data$meta)))
  )
}

server <- function(input, output, session) {
  matchup <- mod_matchup_server("matchup", app_data, notes)

  # Called from inside the slate module, so pass the top-level session
  # explicitly; otherwise the tab id would get the module's namespace.
  open_matchup <- function(game) {
    if (!is.null(game)) matchup$load(game)
    nav_select("tabs", "matchup", session = session)
  }
  mod_slate_server("slate", app_data, notes, on_open = open_matchup)
  mod_scorecard_server("scorecard", app_data)
  mod_report_server("report", app_data)
}

shinyApp(ui, server)
