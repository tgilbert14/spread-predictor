# Write manifest.json, which tells a Posit Connect or shinyapps.io server
# which files make up the app and which packages it needs.
#
# Only the app is listed: app.R, DESCRIPTION, R/, www/, the app data and the
# game notes. Tests, scripts, snapshots and the database are not deployed.
#
# Run from the project root (needs the rsconnect package, which the app
# itself does not use):
#   Rscript scripts/write_manifest.R

if (!requireNamespace("rsconnect", quietly = TRUE)) {
  stop("rsconnect is not installed. Install it with install.packages(\"rsconnect\"), ",
       "then run this again.", call. = FALSE)
}

app_files <- c(
  "app.R",
  "DESCRIPTION",
  list.files("R", recursive = TRUE, full.names = TRUE),
  list.files("www", recursive = TRUE, full.names = TRUE),
  file.path("data", "app_data.rds"),
  file.path("data", "notes.csv")
)

missing <- app_files[!file.exists(app_files)]
if (length(missing) > 0) {
  stop("These app files are missing: ", paste(missing, collapse = ", "), ". ",
       "Build the app data with `Rscript scripts/refresh.R --offline`, then run this again.",
       call. = FALSE)
}

rsconnect::writeManifest(appDir = ".", appFiles = app_files, appPrimaryDoc = "app.R")
message("Wrote manifest.json listing ", length(app_files), " files.")
