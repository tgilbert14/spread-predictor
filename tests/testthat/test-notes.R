# Reading data/notes.csv, which is fed by hand outside this codebase.

write_notes <- function(lines) {
  path <- tempfile(fileext = ".csv")
  writeLines(lines, path)
  path
}
header <- "season,week,game_id,team,category,note,source,source_url,checked_at"

test_that("the real notes file exists with the documented header", {
  path <- file.path(project_root, "data", "notes.csv")
  expect_true(file.exists(path))
  expect_identical(readLines(path, n = 1), header)
  expect_identical(strsplit(header, ",")[[1]], NOTE_COLUMNS)
})

test_that("a missing, empty or header-only file means no notes", {
  for (path in c(tempfile(fileext = ".csv"), write_notes(character()), write_notes(header))) {
    notes <- load_notes(path, 2026, 11)
    expect_identical(nrow(notes), 0L)
    expect_identical(names(notes), NOTE_COLUMNS)
  }
})

test_that("notes are trimmed, filtered to the week, and tolerate gaps", {
  path <- write_notes(c(
    paste0(" ", header, " "),
    "2026, 11 ,401,  LSU ,Availability, QB ruled out. ,ESPN, https://espn.com/x ,2026-11-12",
    "2026,11,402,,weather,Rain expected.,,,2026-11-13T15:00:00Z",
    "2026,11,403,Texas,injury,Kicker questionable.,Team site,,",
    "2026,11,,Texas,other,No game id.,x,,",
    "2026,11,404,Texas,other,,x,,",
    "2026,10,405,Texas,other,Last week.,x,,",
    "2025,11,406,Texas,other,Last season.,x,,"
  ))
  notes <- load_notes(path, 2026, 11)
  expect_identical(notes$game_id, c(401L, 402L, 403L))
  expect_identical(notes$team, c("LSU", NA, "Texas"))
  expect_identical(notes$note[1], "QB ruled out.")
  expect_identical(notes$source_url, c("https://espn.com/x", NA, NA))
  expect_identical(notes$category, c("availability", "weather", "other"))
  expect_true(is.na(notes$source[2]))
})

test_that("missing columns and a file with no final newline still load", {
  path <- tempfile(fileext = ".csv")
  cat("season,week,game_id,note\n2026,11,401,Snow likely.", file = path)
  notes <- load_notes(path, 2026, 11)
  expect_identical(nrow(notes), 1L)
  expect_identical(notes$category, "other")
  expect_true(is.na(notes$source_url))
})
