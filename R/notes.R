# Game notes: short, sourced facts about this week's games (a starter ruled
# out, a storm in the forecast) that the rating systems cannot know.
#
# They live in data/notes.csv, which a separate weekly check outside this
# codebase appends to on Thursdays and Fridays. The app reads the file
# directly at startup, so new notes show up without rebuilding the app data.
# The file is hand-fed, so the reader forgives loose formatting.

NOTE_COLUMNS <- c("season", "week", "game_id", "team", "category", "note",
                  "source", "source_url", "checked_at")

#' The notes for one season and week.
#'
#' Tolerates a missing or empty file, stray whitespace, missing columns and
#' rows with no team or url. A row with no game_id or no note text cannot be
#' shown, so it is dropped. An unknown category is read as "other".
#'
#' @param path Usually PATHS$notes.
#' @return A data frame with NOTE_COLUMNS (zero rows when there is nothing).
load_notes <- function(path, season, week) {
  # A missing or empty file is an error to read.csv; here it just means no
  # notes. Warnings (such as no newline at the end) are harmless.
  raw <- tryCatch(
    suppressWarnings(utils::read.csv(path, colClasses = "character", check.names = FALSE,
                                     na.strings = "", strip.white = TRUE,
                                     fileEncoding = "UTF-8-BOM")),
    error = function(e) NULL
  )
  if (is.null(raw)) raw <- data.frame()
  names(raw) <- tolower(trimws(names(raw)))

  notes <- as.data.frame(lapply(stats::setNames(NOTE_COLUMNS, NOTE_COLUMNS), function(column) {
    values <- if (column %in% names(raw)) trimws(raw[[column]]) else rep(NA_character_, nrow(raw))
    values[!is.na(values) & values == ""] <- NA
    values
  }), stringsAsFactors = FALSE)

  notes$season <- suppressWarnings(as.integer(notes$season))
  notes$week <- suppressWarnings(as.integer(notes$week))
  notes$game_id <- suppressWarnings(as.integer(notes$game_id))
  notes$category <- tolower(notes$category)
  notes$category[!notes$category %in% NOTE_CATEGORIES] <- "other"

  keep <- notes$season %in% season & notes$week %in% week & !is.na(notes$game_id) & !is.na(notes$note)
  notes <- notes[keep, , drop = FALSE]
  rownames(notes) <- NULL
  notes
}
