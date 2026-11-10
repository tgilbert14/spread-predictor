# Re-test the house models and the candidate factors on the real data, and
# write docs/backtest-results.md. Reads cfb.sqlite read-only and changes
# nothing else, so it is safe to run any time.
#
# Run from the project root (after scripts/fit.R or scripts/refresh.R has
# built the database):
#   Rscript scripts/backtest.R

for (file in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(file)

out_path <- file.path("docs", "backtest-results.md")

con <- connect_readonly(PATHS$database)
games <- tryCatch(backtest_games(con), finally = DBI::dbDisconnect(con))

models <- compare_models(games)
factors <- do.call(rbind, lapply(CANDIDATES, judge_candidate, games = games))

report <- backtest_markdown(models, factors,
                            n_cv = sum(games$season %in% FIT_SEASONS),
                            n_holdout = sum(games$season == HOLDOUT_SEASON))
writeLines(report, out_path)

cat(report, sep = "\n")
cat(sprintf("\nWrote %s\n", out_path))
