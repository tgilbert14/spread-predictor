# Write manifest.json, which tells a Posit Connect or shinyapps.io server
# which files make up the app and which packages it needs.
#
# Only the app is listed: app.R, DESCRIPTION, R/, www/, the app data and the
# game notes. Tests, scripts, snapshots and the database are not deployed.
#
# Run from the project root (needs the rsconnect package, which the app
# itself does not use):
#   Rscript scripts/write_manifest.R
#
# To trim an existing manifest without rewriting it (no rsconnect needed):
#   Rscript scripts/write_manifest.R --prune-only

# Packages the running app never calls. cfbfastR only pulls data, which
# happens in the pipeline, and installing it on the server is slow.
PIPELINE_ONLY <- c("cfbfastR")

# The package names in one DESCRIPTION dependency field.
field_packages <- function(field) {
  if (is.null(field)) return(character(0))
  names <- trimws(gsub("\\(.*?\\)", "", strsplit(field, ",")[[1]]))
  setdiff(names[nzchar(names)], "R")
}

# Drop pipeline-only packages, then anything nothing else in the app needs.
prune_manifest <- function(path = "manifest.json") {
  manifest <- jsonlite::read_json(path)
  packages <- manifest$packages
  needs <- lapply(packages, function(p) {
    d <- p$description
    unlist(lapply(list(d$Depends, d$Imports, d$LinkingTo), field_packages))
  })

  app_imports <- field_packages(read.dcf("DESCRIPTION", fields = "Imports")[1, 1])
  keep <- character(0)
  queue <- setdiff(app_imports, PIPELINE_ONLY)
  while (length(queue) > 0) {
    keep <- union(keep, queue)
    queue <- setdiff(intersect(unlist(needs[queue]), names(packages)), keep)
  }

  dropped <- setdiff(names(packages), keep)
  manifest$packages <- packages[names(packages) %in% keep]
  jsonlite::write_json(manifest, path, auto_unbox = TRUE, pretty = TRUE, null = "null")
  message("Kept ", length(keep), " packages, dropped ", length(dropped), ".")
}

if ("--prune-only" %in% commandArgs(trailingOnly = TRUE)) {
  prune_manifest()
  quit(save = "no")
}

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
prune_manifest()
message("Wrote manifest.json listing ", length(app_files), " files.")
