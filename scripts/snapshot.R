# Weekly job: snapshot this week's SP+, FPI, SRS and Elo ratings, and
# refresh the current season's games, lines and game stats. The first run of
# a season also pulls its teams, talent and returning production. The GitHub
# Action runs this. About 7 API calls a week (10 the first week of a season),
# plus 2 to log the key's remaining calls.
#
# Run from the project root:
#   Rscript scripts/snapshot.R

# Pick up the API key from the project's .Renviron, even when R was started
# somewhere else (for example from RStudio with setwd()).
if (file.exists(".Renviron")) readRenviron(".Renviron")

for (file in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(file)
options(warn = 1)  # show name-matching warnings where they happen

ok <- run_snapshot()

if (!all(ok)) {
  message("\nThese steps failed: ", paste(names(ok)[!ok], collapse = ", "),
          ". Files from the other steps were kept. Run this again to retry; ",
          "files already on disk will not be pulled twice.")
  quit(save = "no", status = 1)
}
message("\nSnapshot done.")
