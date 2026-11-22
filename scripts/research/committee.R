# What does the playoff committee reward, and can a ranking built only from
# results reproduce its list?
#
# For every committee release since 2018 (2020 left out), this builds each
# team's resume going into that week from games already played, fits a score
# to the committee's order, and checks it on seasons the fit never saw. The
# write-up is in docs/research-log.md.
#
#   Rscript scripts/research/committee.R

source(file.path("scripts", "research", "common.R"))

SEASONS <- setdiff(2018:2025, 2020)
COMMITTEE_POLL <- "Playoff Committee Rankings"
# The team a resume is measured against: about the 10th best in the country.
REFERENCE_RANK <- COMMITTEE_MODEL$reference_rank

con <- connect_readonly(PATHS$database)
all_games <- query_sql_file(con, "rating_games.sql", list(BURN_IN_SEASON))
conferences <- query_sql_file(con, "team_conferences.sql")
teams <- DBI::dbGetQuery(con, "SELECT season, team_id, school, conference FROM teams")
DBI::dbDisconnect(con)
params <- read_params(PATHS$params)
# The committee never sees a bowl result, so neither does anything here.
regular <- all_games[all_games$season_type == "regular", , drop = FALSE]

#' One season's committee and AP rankings with team ids.
season_polls <- function(season) {
  raw <- read_snapshot(extra_path("rankings", season))
  raw <- raw[raw$season_type == "regular" & raw$poll %in% c(COMMITTEE_POLL, "AP Top 25"), ]
  ours <- teams[teams$season == season, ]
  raw$team_id <- ours$team_id[match(team_key(raw$school), team_key(ours$school))]
  raw[!is.na(raw$team_id), c("week", "poll", "rank", "team_id")]
}

#' Every FBS team's resume going into one week of one season, from
#' team_resumes() in R/rankings.R, the same code the app uses.
#'
#' @param power_weekly team_id, week, power for the season (regular season only).
#' @param power_final team_id, power after the last regular-season game.
resumes <- function(season, week, power_weekly, power_final) {
  ours <- teams[teams$season == season, ]
  rated <- power_weekly[power_weekly$week == week, ]
  if (nrow(rated) == 0) rated <- power_final
  rated <- rated[rated$team_id %in% ours$team_id, ]
  played <- regular[regular$season == season & regular$week < week & !is.na(regular$home_points), ]
  tier <- as.integer(is_power_team(ours$conference, ours$team_id, season))
  out <- team_resumes(played, stats::setNames(rated$power, rated$team_id),
                      stats::setNames(tier, ours$team_id), params$sigma, REFERENCE_RANK)
  cbind(season = season, week = week, out)
}

releases <- list()
for (season in SEASONS) {
  rated <- power_ratings(regular[regular$season <= season, ], conferences)
  polls <- season_polls(season)
  for (week in sort(unique(polls$week[polls$poll == COMMITTEE_POLL]))) {
    resume <- resumes(season, week, rated$weekly, rated$current)
    for (poll in c(cfp = COMMITTEE_POLL, ap = "AP Top 25")) {
      this <- polls[polls$poll == poll & polls$week == week, ]
      resume[[names(which(c(cfp = COMMITTEE_POLL, ap = "AP Top 25") == poll))]] <-
        this$rank[match(resume$team_id, this$team_id)]
    }
    releases[[paste(season, week)]] <- resume
  }
}
data <- do.call(rbind, releases)
data$release <- paste(data$season, data$week)
cat(sprintf("%d committee releases over %d seasons, %d ranked team-weeks.\n",
            length(releases), length(SEASONS), sum(!is.na(data$cfp))))

FEATURES <- c("losses", "wins", "record_strength", "schedule", "top25_wins", "power", "tier")
scaled <- data
for (f in FEATURES) scaled[[f]] <- (data[[f]] - mean(data[[f]])) / stats::sd(data[[f]])

#' Pairs the committee ordered: every ranked team over each team ranked
#' below it, and over the best unranked teams. Each pair is entered both
#' ways round so the fit has no intercept to lean on.
committee_pairs <- function(rows, features) {
  pairs <- lapply(split(rows, rows$release), function(r) {
    ranked <- r[!is.na(r$cfp), ]
    ranked <- ranked[order(ranked$cfp), ]
    near <- r[is.na(r$cfp), ]
    near <- near[order(-near$record_strength), ][seq_len(min(25, nrow(near))), ]
    pool <- rbind(ranked, near)
    n <- nrow(ranked)
    better <- rep(seq_len(n), times = nrow(pool) - seq_len(n))
    worse <- unlist(lapply(seq_len(n), function(i) seq(i + 1, nrow(pool))))
    as.matrix(pool[better, features, drop = FALSE]) - as.matrix(pool[worse, features, drop = FALSE])
  })
  d <- do.call(rbind, pairs)
  data.frame(y = rep(c(1, 0), each = nrow(d)), rbind(d, -d))
}

fit_committee <- function(rows, features) {
  pairs <- committee_pairs(rows, features)
  model <- suppressWarnings(stats::glm(y ~ . - 1, data = pairs, family = stats::binomial()))
  stats::coef(model)
}

#' Score one release: places off across the committee's 25, and how many of
#' its top 4 and top 12 the ranking also has in its own top 4 and top 12.
grade <- function(rows, score) {
  ours <- rank(-score, ties.method = "min")
  ranked <- !is.na(rows$cfp)
  hit <- function(n) length(intersect(rows$team_id[ours <= n], rows$team_id[ranked & rows$cfp <= n]))
  c(off = mean(abs(ours[ranked] - rows$cfp[ranked])), top4 = hit(4), top12 = hit(12),
    first = as.numeric(any(ours == 1 & ranked & rows$cfp == 1)))
}

grade_all <- function(score) {
  graded <- vapply(split(seq_len(nrow(data)), data$release), function(i) grade(data[i, ], score[i]), numeric(4))
  rowMeans(graded)
}

#' Leave one season out: fit on the others, score the one left out.
out_of_sample <- function(features) {
  score <- rep(NA_real_, nrow(scaled))
  for (season in SEASONS) {
    held <- scaled$season == season
    beta <- fit_committee(scaled[!held, ], features)
    score[held] <- as.matrix(scaled[held, features, drop = FALSE]) %*% beta
  }
  score
}

report <- function(label, score) {
  g <- grade_all(score)
  cat(sprintf("%-46s %5.2f places off   top 4: %.2f of 4   top 12: %5.2f of 12   same No. 1: %3.0f%%\n",
              label, g[["off"]], g[["top4"]], g[["top12"]], 100 * g[["first"]]))
}

cat("\nSimple yardsticks (no fitting):\n")
report("AP poll, same week", -ifelse(is.na(data$ap), 26, data$ap))
report("Power rating (who would win)", data$power)
report("Record strength alone", data$record_strength)
report("Fewest losses, then Power", -data$losses * 100 + data$power)

cat("\nFitted to the committee, scored on seasons left out:\n")
candidates <- list(
  "Record strength + Power" = c("record_strength", "power"),
  "Losses + record strength + Power" = c("losses", "record_strength", "power"),
  "  + power-conference flag" = c("losses", "record_strength", "power", "tier"),
  "  + schedule and top-25 wins" = c("losses", "record_strength", "power", "tier", "schedule", "top25_wins"),
  "Everything" = FEATURES
)
for (label in names(candidates)) report(label, out_of_sample(candidates[[label]]))

chosen <- c("losses", "record_strength", "power", "tier")
beta <- fit_committee(scaled, chosen)
cat("\nWeights on the chosen four (each input scaled to the same spread, so sizes compare):\n")
print(round(beta, 2))
cat("\nIn their own units:\n")
print(round(beta / vapply(chosen, function(f) stats::sd(data[[f]]), numeric(1)), 4))

cat("\nBy season, the chosen four, out of sample:\n")
score <- out_of_sample(chosen)
for (season in SEASONS) {
  i <- data$season == season
  graded <- vapply(split(which(i), data$release[i]), function(k) grade(data[k, ], score[k]), numeric(4))
  cat(sprintf("  %d  %4.2f places off   top 12: %4.1f of 12\n", season, mean(graded["off", ]), mean(graded["top12", ])))
}
