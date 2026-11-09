# Snapshot, rebuild the database, then rebuild the app's data file.
#
# Run from the project root:
#   Rscript scripts/refresh.R             # pulls this week's snapshot first
#   Rscript scripts/refresh.R --offline   # uses only the files already on disk

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
message("\nRefresh done. Wrote ", PATHS$app_data, ".")
