# Snapshot, rebuild the database, then rebuild the app's data file.
#
# Run from the project root:
#   Rscript scripts/refresh.R             # pulls this week's snapshot first
#   Rscript scripts/refresh.R --offline   # uses only the files already on disk

# Pick up the API key from the project's .Renviron, even when R was started
# somewhere else (for example from RStudio with setwd()).
if (file.exists(".Renviron")) readRenviron(".Renviron")

for (file in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(file)
options(warn = 1)

offline <- "--offline" %in% commandArgs(trailingOnly = TRUE)

if (!offline) {
  ok <- tryCatch(run_snapshot(), error = function(e) {
    stop(conditionMessage(e), "\nTo rebuild from the files already on disk, run: ",
         "Rscript scripts/refresh.R --offline", call. = FALSE)
  })
  if (!all(ok)) {
    message("Some snapshot steps failed (see above). Continuing with the files on disk.")
  }
}

build_db()
report_db_checks(check_db())

if (!file.exists(PATHS$params)) {
  stop("The database is built, but ", PATHS$params, " does not exist yet. ",
       "Run Rscript scripts/fit.R, then run this script again.", call. = FALSE)
}

build_app_data()

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
