# Snapshot, rebuild the database, rebuild the app's data file, save this
# week's predictions before kickoff, grade the saved ones, and audit the data.
#
# Run from the project root:
#   Rscript scripts/refresh.R                 # pulls this week's snapshot first
#   Rscript scripts/refresh.R --results-only  # new results, lines and polls, but no new
#                                             # ratings snapshot and no game predictions saved
#   Rscript scripts/refresh.R --offline       # uses only the files already on disk

# Pick up the API key from the project's .Renviron, even when R was started
# somewhere else (for example from RStudio with setwd()).
if (file.exists(".Renviron")) readRenviron(".Renviron")

for (file in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(file)
options(warn = 1)

offline <- "--offline" %in% commandArgs(trailingOnly = TRUE)
# Sunday and Monday runs: the weekend's results are in, the new week's
# ratings may not be. Those are snapshotted, and game predictions saved, on
# Tuesday.
results_only <- "--results-only" %in% commandArgs(trailingOnly = TRUE)

if (!offline) {
  ok <- tryCatch(run_snapshot(ratings = !results_only), error = function(e) {
    stop(conditionMessage(e), "\nTo rebuild from the files already on disk, run: ",
         "Rscript scripts/refresh.R --offline", call. = FALSE)
  })
  if (!all(ok)) {
    message("Some snapshot steps failed (see above). Continuing with the files on disk.")
  }
  # Who threw the passes last weekend: one API call for each week not saved
  # yet, plus the latest week again in case a game was not final last time.
  # A failure here never stops the refresh.
  tryCatch({
    season <- latest_snapshot_season()
    games <- read_snapshot(file.path(PATHS$snapshots, "games", sprintf("%d.csv", season)))
    played <- games[games$season_type == "regular" & games$completed %in% c(TRUE, "TRUE", 1), , drop = FALSE]
    if (nrow(played) > 0) {
      weeks <- sort(unique(played$week))
      pulled <- pull_passing(season, weeks, refresh = max(weeks))
      message("Passing box scores: pulled ", pulled, " week(s).")
    }
  }, error = function(e) message("Could not pull passing box scores: ", conditionMessage(e)))
}

build_db()
report_db_checks(check_db())

if (!file.exists(PATHS$params)) {
  stop("The database is built, but ", PATHS$params, " does not exist yet. ",
       "Run Rscript scripts/fit.R, then run this script again.", call. = FALSE)
}

# Building the app data also grades every saved prediction against the
# results now in the database (the scorecard).
app_data <- build_app_data()

# Save this week's predictions, once, before the first kickoff. A new file
# changes the scorecard and the line movement, so rebuild to include it.
if (!results_only && freeze_predictions(app_data)) app_data <- build_app_data()
message(scorecard_message(app_data$scorecard))

# Save our prediction of the committee's next ranking, once, as soon as the
# week's games are all in and before the committee releases it.
if (freeze_committee_forecast(complete_app_data(app_data))) {
  message("Saved our prediction of the committee's week ", app_data$meta$forecast_week, " ranking.")
  app_data <- build_app_data()
}

# Keep what the committee's rankings have taught us on record: the weights
# (the next season starts from them) and the reasoning in plain words.
write_committee_learned(complete_app_data(app_data), COMMITTEE_LEARNED_PATH)
writeLines(committee_notes_markdown(complete_app_data(app_data)), file.path("docs", "committee-notes.md"),
           useBytes = TRUE)

# Check the data every time it changes. Problems are reported, not fatal:
# the report says which ones matter.
con <- DBI::dbConnect(RSQLite::SQLite(), PATHS$database, flags = RSQLite::SQLITE_RO)
audit <- tryCatch(list(summary = audit_db(con), counts = audit_table_counts(con)),
                  finally = DBI::dbDisconnect(con))
writeLines(audit_markdown(audit$summary, audit$counts), file.path("docs", "data-audit.md"), useBytes = TRUE)
flagged <- audit$summary[audit$summary$severity %in% c("error", "warning") & audit$summary$n_flagged > 0, ]
if (nrow(flagged) > 0) {
  message("\nData audit flagged ", nrow(flagged), " check(s). See docs/data-audit.md: ",
          paste(flagged$check, collapse = ", "), ".")
} else {
  message("\nData audit: no problems found.")
}

message("\nRefresh done. Wrote ", PATHS$app_data, ".")
