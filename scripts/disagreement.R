# When a model and the sportsbooks disagree on a spread, which side covers?
#
# For every past game, compare each model's out-of-sample line with the
# sportsbook line, keep the games where they differ by at least 2, 3, 4, 5,
# 7 or 10 points, and count how often the sportsbook's side covered. Writes
# docs/market-disagreement.md. Reads cfb.sqlite read-only and the research
# files under data/snapshots/extras/lines_full/, and changes nothing else.
#
# Only Elo, Power and their average can be tested on history, because they
# are the only models whose past numbers do not already include the results.
# SP+, FPI, SRS and the five-system blend are graded from the predictions
# saved each week (data/snapshots/predictions/), so their table fills in as
# the season goes.
#
# Run from the project root (after scripts/refresh.R has built the database):
#   Rscript scripts/disagreement.R

for (file in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(file)

out_path <- file.path("docs", "market-disagreement.md")
BOOKS <- c("DraftKings", "Bovada", "ESPN Bet")
MAIN_THRESHOLDS <- c(2, 3, 4, 5)

# ---- Data -------------------------------------------------------------------

con <- connect_readonly(PATHS$database)
games <- backtest_games(con)
results <- load_completed_games(con)
DBI::dbDisconnect(con)

# Out-of-sample lines: each fit season is predicted by a fit on the other
# fit seasons, and the holdout season by a fit on all of them.
is_cv <- games$season %in% FIT_SEASONS
fill <- function(pred) {
  out <- numeric(nrow(games))
  out[is_cv] <- pred$cv
  out[!is_cv] <- pred$holdout
  out
}
games$elo <- fill(out_of_sample(games, ELO_TERMS))
games$power <- fill(out_of_sample(games, POWER_TERMS))
games$house <- (games$elo + games$power) / 2
MODELS <- c(house = "Elo and Power average (our testable model)", elo = "Elo", power = "Power")

read_lines_full <- function(season) {
  path <- extra_path("lines_full", season)
  if (!file.exists(path)) return(NULL)
  utils::read.csv(path, stringsAsFactors = FALSE)[c("game_id", "provider", "spread", "spread_open")]
}
lines_full <- do.call(rbind, lapply(sort(unique(games$season)), read_lines_full))
if (is.null(lines_full)) {
  stop("No files under data/snapshots/extras/lines_full/. Run the `extras` task of the ",
       "Weekly snapshot workflow (or `Rscript scripts/pull_extras.R`) first.", call. = FALSE)
}
consensus <- data.frame(game_id = games$game_id, line = games$line)
books <- lapply(stats::setNames(BOOKS, BOOKS), function(b) book_lines(lines_full, b, consensus))

# One opening line per game: the median of the books that posted one.
opens <- do.call(rbind, lapply(books, function(b) b[!is.na(b$open), c("game_id", "open")]))
open_line <- tapply(opens$open, opens$game_id, stats::median)
games$open <- as.numeric(open_line[as.character(games$game_id)])

# ---- Formatting -------------------------------------------------------------

pct <- function(x) ifelse(is.na(x), "", sprintf("%.1f%%", 100 * x))
show_ats <- function(table, first = NULL, show_gap = TRUE) {
  out <- data.frame(
    gap = sprintf("%s or more", format_points(table$threshold)),
    games = format(table$games, big.mark = ","),
    record = sprintf("%d-%d-%d", table$book_wins, table$book_losses, table$pushes),
    book = pct(table$book_pct),
    interval = ifelse(is.na(table$low), "", sprintf("%.1f%% to %.1f%%", 100 * table$low, 100 * table$high)),
    model = pct(1 - table$book_pct),
    ret = ifelse(is.na(table$book_return), "", sprintf("%+.1f", table$book_return))
  )
  headers <- c("Gap (points)", "Games", "Book side W-L-push", "Book side covers", "95% interval",
               "Model side covers", "Book side return per $100")
  if (!show_gap) {
    out <- out[-1]
    headers <- headers[-1]
  }
  if (!is.null(first)) {
    out <- cbind(data.frame(first = first$values), out)
    headers <- c(first$header, headers)
  }
  markdown_table(out, headers)
}
ats_for <- function(rows, model, line, thresholds = MAIN_THRESHOLDS) {
  ats_table(rows[[model]], rows[[line]], rows$home_margin, thresholds)
}

# ---- Tables -----------------------------------------------------------------

# 1. Each model against the closing line.
by_model <- do.call(rbind, lapply(names(MODELS), function(m) ats_for(games, m, "line", DISAGREE_THRESHOLDS)))
by_model_labels <- rep(unname(MODELS), each = length(DISAGREE_THRESHOLDS))

# 2. The same in separate bands, for the house model.
band_edges <- c(0, 1, 2, 3, 4, 5, 7, Inf)
band_labels <- c("Under 1", "1 to 2", "2 to 3", "3 to 4", "4 to 5", "5 to 7", "7 or more")
house_results <- ats_results(games$house, games$line, games$home_margin)
bands <- do.call(rbind, lapply(seq_along(band_labels), function(i) {
  inside <- abs(house_results$gap) >= band_edges[i] & abs(house_results$gap) < band_edges[i + 1]
  ats_row(house_results[inside, , drop = FALSE], 0)
}))

# 3. Against each sportsbook's own closing line (house model).
with_book <- function(book) {
  rows <- games[games$game_id %in% book$game_id, , drop = FALSE]
  rows$close <- book$close[match(rows$game_id, book$game_id)]
  rows$book_open <- book$open[match(rows$game_id, book$game_id)]
  rows
}
book_seasons <- vapply(books, function(b) {
  seasons <- range(games$season[games$game_id %in% b$game_id])
  sprintf("%s (%d to %d)", "", seasons[1], seasons[2])
}, character(1))
by_book <- do.call(rbind, lapply(BOOKS, function(b) ats_for(with_book(books[[b]]), "house", "close")))
by_book_labels <- rep(paste0(BOOKS, book_seasons), each = length(MAIN_THRESHOLDS))

# 4. Each model against the opening line.
opened <- games[!is.na(games$open), , drop = FALSE]
by_model_open <- do.call(rbind, lapply(names(MODELS), function(m) ats_for(opened, m, "open")))
by_model_open_labels <- rep(unname(MODELS), each = length(MAIN_THRESHOLDS))

# 5. Does the line move toward the model after it opens?
moves <- line_move_table(opened$house, opened$open, opened$line, MAIN_THRESHOLDS)

# 6. Where the house model disagrees by 3 or more: is any slice different?
three <- function(rows) ats_for(rows, "house", "line", 3)
favorite_side <- sign(games$house - games$line) == sign(games$line)
slices <- list(
  "All games" = games,
  "Weeks 1 to 4" = games[games$season_type == "regular" & games$week <= 4, ],
  "Week 5 on, and bowls" = games[!(games$season_type == "regular" & games$week <= 4), ],
  "Model likes the favorite more than the book does" = games[favorite_side, ],
  "Model likes the underdog more than the book does" = games[!favorite_side, ],
  "Model likes the home team more" = games[games$house > games$line, ],
  "Model likes the away team more" = games[games$house < games$line, ],
  "Elo and Power both 3 or more off, same side" =
    games[abs(games$elo - games$line) >= 3 & abs(games$power - games$line) >= 3 &
            sign(games$elo - games$line) == sign(games$power - games$line), ]
)
for (season in sort(unique(games$season))) {
  slices[[as.character(season)]] <- games[games$season == season, ]
}
by_slice <- do.call(rbind, lapply(slices, three))

# 7. Saved weekly predictions: all five systems and the blend, against the
#    line saved with them. Only games that have been played count.
saved_files <- list.files(file.path(PATHS$snapshots, "predictions"), pattern = "\\.csv$", full.names = TRUE)
saved <- do.call(rbind, lapply(saved_files, utils::read.csv, stringsAsFactors = FALSE))
saved$home_margin <- results$home_margin[match(saved$game_id, results$game_id)]
saved$line <- -saved$market_spread_home
played <- saved[!is.na(saved$home_margin) & !is.na(saved$line), , drop = FALSE]
SAVED_MODELS <- c(blend = "Five-system blend (the app's number)", sp = "SP+", fpi = "FPI", srs = "SRS",
                  elo = "Elo", power = "Power")
by_saved <- do.call(rbind, lapply(names(SAVED_MODELS), function(m) ats_for(played, m, "line")))
by_saved_labels <- rep(unname(SAVED_MODELS), each = length(MAIN_THRESHOLDS))

# ---- Report -----------------------------------------------------------------

n_games <- nrow(games)
headline <- by_model[by_model_labels == MODELS[["house"]] & by_model$threshold == 3, ]
report <- c(
  sprintf("_Generated file: written by scripts/disagreement.R on %s. Do not edit by hand; rerun the script._",
          format(Sys.Date())),
  "",
  "# When a model and the sportsbooks disagree, which side covers?",
  "",
  "This is a record of what happened in past games. It is not betting advice.",
  "",
  "## How to read it",
  "",
  "Say a model has Utah by 4.5 at Arizona and the sportsbook has Utah by 2.5. The gap is 2 points.",
  "The model's side is Utah giving 2.5. The sportsbook's side is Arizona getting 2.5.",
  "Each table counts how often the sportsbook's side covered in games with a gap that size.",
  "",
  sprintf("- **Games.** %s FBS games with a closing line, %s and %d. Each game is predicted by a model fitted without that game's season (the %d season by a fit on the earlier ones), so no number here has seen the result.",
          format(n_games, big.mark = ","), format_seasons(FIT_SEASONS), HOLDOUT_SEASON, HOLDOUT_SEASON),
  "- **Closing line.** The median spread across sportsbooks.",
  sprintf("- **Break-even.** At the usual price of -110 you need to win %.1f%% to break even. \"Return per $100\" is the average profit or loss per $100 risked at that price.",
          100 * BREAK_EVEN),
  "- **95% interval.** The range the true rate plausibly sits in, given the number of games. If it includes 50%, the result is not distinguishable from a coin flip.",
  "- **Pushes** (the result lands exactly on the line) are left out of the percentages.",
  "",
  "## The short answer",
  "",
  sprintf("When our testable model and the closing line were 3 or more points apart, the sportsbook's side covered %s of the time (%s games, 95%% interval %s). That is %s the %.1f%% needed to break even at -110.",
          pct(headline$book_pct), format(headline$games, big.mark = ","),
          sprintf("%.1f%% to %.1f%%", 100 * headline$low, 100 * headline$high),
          if (headline$book_pct > BREAK_EVEN) "above" else "below", 100 * BREAK_EVEN),
  "",
  "## 1. Each model against the closing line",
  "",
  show_ats(by_model, list(header = "Model", values = by_model_labels)),
  "",
  "## 2. The same games in separate bands (our testable model)",
  "",
  "Section 1 counts every game at or past each gap. This table splits them so each game is in one row.",
  "",
  show_ats(bands, list(header = "Gap band (points)", values = band_labels), show_gap = FALSE),
  "",
  "## 3. Against each sportsbook's own closing line (our testable model)",
  "",
  show_ats(by_book, list(header = "Sportsbook (seasons)", values = by_book_labels)),
  "",
  "## 4. Each model against the opening line",
  "",
  sprintf("The opening line is the first number a book posted, usually early in the week. Here the bet is graded against that opening number, as if it were placed then. Openers are in the data from 2021 (Bovada), 2023 (DraftKings) and 2024 (ESPN Bet): %s games.",
          format(nrow(opened), big.mark = ",")),
  "",
  show_ats(by_model_open, list(header = "Model", values = by_model_open_labels)),
  "",
  "## 5. Does the line move toward the model?",
  "",
  "If a model knows something the opening line does not, the line should drift toward the model by kickoff.",
  "",
  markdown_table(data.frame(
    gap = sprintf("%s or more", format_points(moves$threshold)),
    games = format(moves$games, big.mark = ","),
    toward = pct(moves$toward),
    avg = sprintf("%+.2f", moves$avg_move)
  ), c("Gap from the opening line (points)", "Games", "Lines that moved toward the model, of those that moved",
       "Average move toward the model (points)")),
  "",
  "## 6. Gaps of 3 or more, sliced (our testable model, closing line)",
  "",
  show_ats(by_slice, list(header = "Slice", values = names(slices)), show_gap = FALSE),
  "",
  "## 7. All five systems, from the predictions saved each week",
  "",
  "SP+, FPI and SRS cannot be tested on past seasons: the only past ratings available are end-of-season ones, which already include the results. So they are graded from the predictions the app saves every week before kickoff, against the line saved with them. This table grows through the season.",
  "",
  if (nrow(played) == 0) {
    sprintf("No saved predictions have been played yet (%d waiting for results).", nrow(saved))
  } else {
    c(sprintf("%d games played so far, out of %d saved. With this few games every row is noise.",
              nrow(played), nrow(saved)),
      "",
      show_ats(by_saved, list(header = "Model", values = by_saved_labels)))
  }
)
writeLines(report, out_path)
cat(report, sep = "\n")
cat(sprintf("\nWrote %s\n", out_path))
