# Basketball refresh: pull the newest games, lines and T-Rank ratings,
# rebuild the basketball app data, and save today's predictions before
# tipoff.
#
# Run from the project root:
#   Rscript scripts/cbb_refresh.R             # pulls first (2 API calls, 3 the first time)
#   Rscript scripts/cbb_refresh.R --offline   # rebuilds from the files on disk

if (file.exists(".Renviron")) readRenviron(".Renviron")
for (file in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(file)
options(warn = 1)

if (!"--offline" %in% commandArgs(trailingOnly = TRUE)) cbb_pull()

if (!file.exists(CBB_PATHS$params)) {
  stop("The files are pulled, but ", CBB_PATHS$params, " does not exist yet. ",
       "Run Rscript scripts/cbb_fit.R, then run this script again.", call. = FALSE)
}
app_data <- cbb_build_app_data()
message(sprintf("Basketball app data built: %d teams, %d games on the slate, ratings from %s.",
                nrow(app_data$teams), nrow(app_data$slate), app_data$meta$ratings_date))
if (cbb_freeze(app_data)) message("Saved today's predictions.")
message("Wrote ", CBB_PATHS$app_data, ".")
