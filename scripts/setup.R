# One-time setup: install the packages this project needs and check for an
# API key. Safe to re-run: it only installs what is missing or too old.
#
# Run from the project root:
#   Rscript scripts/setup.R

# Pick up the API key from the project's .Renviron, even when R was started
# somewhere else (for example from RStudio with setwd()).
if (file.exists(".Renviron")) readRenviron(".Renviron")

if (!file.exists("DESCRIPTION")) {
  stop("Run this from the project root, the folder that has the DESCRIPTION file.", call. = FALSE)
}

if (identical(getOption("repos")[["CRAN"]], "@CRAN@")) {
  options(repos = c(CRAN = "https://cloud.r-project.org"))
}

#' Package names and minimum versions from DESCRIPTION's Imports and Suggests.
description_packages <- function(path = "DESCRIPTION") {
  fields <- read.dcf(path, fields = c("Imports", "Suggests"))
  entries <- trimws(unlist(strsplit(fields[!is.na(fields)], ",")))
  entries <- entries[nzchar(entries)]
  data.frame(
    package = trimws(sub("\\(.*$", "", entries)),
    min_version = ifelse(grepl(">=", entries), trimws(sub(".*>=\\s*([^)]+)\\).*", "\\1", entries)), NA),
    stringsAsFactors = FALSE
  )
}

#' TRUE if a package is installed and at least the minimum version.
is_ready <- function(package, min_version) {
  if (!requireNamespace(package, quietly = TRUE)) return(FALSE)
  is.na(min_version) || utils::packageVersion(package) >= min_version
}

#' cfbfastR is on CRAN, with the sportsdataverse r-universe as a fallback.
install_cfbfastR <- function() {
  try(utils::install.packages("cfbfastR"))
  if (!requireNamespace("cfbfastR", quietly = TRUE)) {
    utils::install.packages("cfbfastR", repos = c("https://sportsdataverse.r-universe.dev", getOption("repos")))
  }
}

packages <- description_packages()
needed <- packages[!mapply(is_ready, packages$package, packages$min_version), ]

if (nrow(needed) == 0) {
  message("All packages are already installed.")
} else {
  message("Installing: ", paste(needed$package, collapse = ", "))
  others <- setdiff(needed$package, "cfbfastR")
  if (length(others) > 0) utils::install.packages(others)
  if ("cfbfastR" %in% needed$package) install_cfbfastR()
}

still_missing <- packages$package[!mapply(is_ready, packages$package, packages$min_version)]
if (length(still_missing) > 0) {
  stop(
    "These packages did not install: ", paste(still_missing, collapse = ", "),
    ". Scroll up for the reason, fix it, then run this script again.",
    call. = FALSE
  )
}

has_key <- nzchar(Sys.getenv("CFBD_API_KEY"))
message("\nPackages are ready.")
message(if (has_key) "CFBD_API_KEY is set." else "CFBD_API_KEY is NOT set yet.")
message("
Next steps:
  1. ", if (has_key) "(done) " else "", "Get a free API key at https://collegefootballdata.com/key and put
     this line in a file named .Renviron in the project root (git ignores it):
       CFBD_API_KEY=your-key
  2. Pull history, once (about 40 API calls of the 1,000 a month free tier):
       Rscript scripts/backfill.R
  3. Fit the model (this builds the database first):
       Rscript scripts/fit.R
  4. Take this week's snapshot, build the app data, and run the app:
       Rscript scripts/refresh.R
       Rscript -e 'shiny::runApp()'
  5. For weekly updates on GitHub, add the same key as a repository secret
     named CFBD_API_KEY (Settings > Secrets and variables > Actions).

In RStudio, open Spread-predictor.Rproj and use source(\"scripts/backfill.R\")
in place of each Rscript line.")
