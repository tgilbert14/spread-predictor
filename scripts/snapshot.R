# Weekly job: snapshot this week's SP+, FPI, SRS and Elo ratings, and
# refresh the current season's games and lines. The GitHub Action runs this.
# About 8 API calls, plus 2 to log the key's remaining calls.
#
# Run from the project root:
#   Rscript scripts/snapshot.R

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
