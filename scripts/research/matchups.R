# Do matchups matter beyond the ratings? A rating says how good a team is
# overall. This asks whether it also matters how the two teams fit: a
# passing offense against a defense that is weak against the pass, or a top
# offense against a top defense.
#
# Each team's four units (pass offense, rush offense, pass defense, rush
# defense) are its points added per play so far that season, from games
# already played, set against the rest of the country (z-scores). A team
# needs MIN_GAMES behind it before its units count.
#
# Run from the project root:
#   Rscript scripts/research/matchups.R         # units adjusted for opponents
#   Rscript scripts/research/matchups.R --raw   # units as played

source(file.path("scripts", "research", "common.R"))
data <- load_research_data()
games <- data$games
MIN_GAMES <- 3

game_files <- list.files(file.path(PATHS$snapshots, "games"), pattern = "^[0-9]{4}\\.csv$", full.names = TRUE)
schedule <- do.call(rbind, lapply(game_files, function(f) {
  read_snapshot(f)[c("game_id", "start_date", "home_id", "away_id", "home_team", "away_team")]
}))
stat_files <- list.files(file.path(PATHS$snapshots, "extras", "advanced"), pattern = "^[0-9]{4}\\.csv$", full.names = TRUE)
stats <- do.call(rbind, lapply(stat_files, function(f) {
  read_snapshot(f)[c("game_id", "season", "team", "off_passing_plays_ppa", "off_rushing_plays_ppa",
                     "def_passing_plays_ppa", "def_rushing_plays_ppa")]
}))
stats <- passing_with_teams(stats, schedule)  # adds team_id and start_date
names(stats)[4:7] <- c("pass_off", "rush_off", "pass_def", "rush_def")
stats <- stats[order(stats$season, stats$team_id, stats$start_date, stats$game_id), ]

# Each unit going into a game: the average of the team's earlier games.
units <- c("pass_off", "rush_off", "pass_def", "rush_def")
key <- paste(stats$season, stats$team_id)
played <- stats::ave(rep(1, nrow(stats)), key, FUN = cumsum) - 1
for (unit in units) {
  value <- ifelse(is.na(stats[[unit]]), 0, stats[[unit]])
  before <- stats::ave(value, key, FUN = cumsum) - value
  stats[[paste0(unit, "_before")]] <- ifelse(played >= MIN_GAMES, before / played, NA)
}
# Second pass: adjust each game for the opponent. A passing day against a
# defense that gives up a lot of passing counts for less. Each game's number
# has the opponent's own average (before that game, against the country)
# taken off, then the team's adjusted games are averaged the same way.
ADJUST <- !("--raw" %in% commandArgs(trailingOnly = TRUE))
if (ADJUST) {
  other <- match(paste(stats$game_id, stats$team_id),
                 paste(stats$game_id, stats::ave(stats$team_id, stats$game_id, FUN = function(x) rev(x))))
  facing <- c(pass_off = "pass_def", rush_off = "rush_def", pass_def = "pass_off", rush_def = "rush_off")
  adjusted <- list()
  for (unit in units) {
    opponent <- stats[[paste0(facing[[unit]], "_before")]][other]
    usual <- stats::ave(opponent, stats$season, FUN = function(x) mean(x, na.rm = TRUE))
    adjusted[[unit]] <- stats[[unit]] - ifelse(is.na(opponent), 0, opponent - usual)
  }
  for (unit in units) {
    value <- ifelse(is.na(adjusted[[unit]]), 0, adjusted[[unit]])
    before <- stats::ave(value, key, FUN = cumsum) - value
    stats[[paste0(unit, "_before")]] <- ifelse(played >= MIN_GAMES, before / played, NA)
  }
}

# Against the country that season. Defense is flipped so higher is better.
for (unit in units) {
  column <- paste0(unit, "_before")
  center <- stats::ave(stats[[column]], stats$season, FUN = function(x) mean(x, na.rm = TRUE))
  scale <- stats::ave(stats[[column]], stats$season, FUN = function(x) stats::sd(x, na.rm = TRUE))
  z <- (stats[[column]] - center) / scale
  stats[[paste0(unit, "_z")]] <- if (grepl("_def$", unit)) -z else z
}
stats$off_z <- (stats$pass_off_z + stats$rush_off_z) / 2
stats$def_z <- (stats$pass_def_z + stats$rush_def_z) / 2

side <- function(id_column, unit) {
  at <- match(paste(games$game_id, games[[id_column]]), paste(stats$game_id, stats$team_id))
  stats[[unit]][at]
}
h <- function(unit) side("home_id", unit)
a <- function(unit) side("away_id", unit)
zero <- function(x) ifelse(is.na(x), 0, x)

# Style fit: how much an offense leans on the pass (over the run), times how
# much softer the defense it faces is against the pass (than the run).
fit_for <- function(off, def) (off("pass_off_z") - off("rush_off_z")) * (def("rush_def_z") - def("pass_def_z"))
games$style_fit <- zero(fit_for(h, a) - fit_for(a, h))
# Each kind of play on its own: the offense's edge over the defense it faces.
games$pass_edge <- zero((h("pass_off_z") - a("pass_def_z")) - (a("pass_off_z") - h("pass_def_z")))
games$rush_edge <- zero((h("rush_off_z") - a("rush_def_z")) - (a("rush_off_z") - h("rush_def_z")))
# Strength on strength: a top offense against a top defense.
games$strength_clash <- zero(pmax(h("off_z"), 0) * pmax(a("def_z"), 0) - pmax(a("off_z"), 0) * pmax(h("def_z"), 0))
# The weakest unit, for the opponent to attack.
weakest <- function(t) pmin(t("pass_off_z"), t("rush_off_z"), t("pass_def_z"), t("rush_def_z"))
games$weak_link <- zero(weakest(h) - weakest(a))

candidates <- c(
  style_fit = "Style fit: pass-leaning offense against a pass-soft defense",
  pass_edge = "Passing: offense's edge over the defense it faces",
  rush_edge = "Rushing: offense's edge over the defense it faces",
  strength_clash = "Top offense against top defense",
  weak_link = "Each team's weakest unit"
)
cat(if (ADJUST) "Units adjusted for the opponents faced.\n" else "Units as played, not adjusted for opponents.\n")
cat("Games with units for both teams:", sum(!is.na(h("off_z")) & !is.na(a("off_z"))), "of", nrow(games), "\n\n")
cat("Candidate: correlation with what our line missed (fit seasons)\n")
fit <- games[games$season %in% FIT_SEASONS, ]
for (column in names(candidates)) {
  used <- fit[[column]] != 0
  cat(sprintf("%-62s %+.3f\n", candidates[[column]], stats::cor(fit[[column]][used], (fit$home_margin - fit$pred)[used])))
}
cat("\n")
print_verdicts(games, candidates)
