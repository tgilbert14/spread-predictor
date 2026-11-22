# More on what the playoff committee rewards: does it help to know a team's
# best win and worst loss, its recent form, who beat whom, or where the
# committee had the team last week?
#
# Builds on scripts/research/committee.R (it runs that first, quietly, for
# the resumes and the fitting code). The write-up is in docs/research-log.md.
#
#   Rscript scripts/research/committee_extras.R

invisible(utils::capture.output(source(file.path("scripts", "research", "committee.R"))))

# ---- Extra inputs, per team and release ------------------------------------------

#' Each team's games before a week, with the opponent's Power as of that week.
sides_before <- function(season, week, power) {
  played <- regular[regular$season == season & regular$week < week & !is.na(regular$home_points), ]
  sides <- rbind(
    data.frame(team_id = played$home_id, opponent = played$away_id, week = played$week,
               won = played$home_points > played$away_points),
    data.frame(team_id = played$away_id, opponent = played$home_id, week = played$week,
               won = played$away_points > played$home_points)
  )
  sides$opponent_power <- unname(power[as.character(sides$opponent)])
  sides$opponent_power[is.na(sides$opponent_power)] <- min(power, na.rm = TRUE)
  sides
}

beaten <- character()  # "season winner loser week" for every result, for head-to-head
extra <- lapply(split(data, data$release), function(release) {
  season <- release$season[1]
  week <- release$week[1]
  power <- stats::setNames(release$power, release$team_id)
  sides <- sides_before(season, week, power)
  sides <- sides[sides$team_id %in% release$team_id, ]
  order_of <- sort(power, decreasing = TRUE)
  top10 <- names(order_of)[1:10]
  outside40 <- names(order_of)[-(1:40)]
  per_team <- function(values, f, empty) {
    out <- tapply(values, sides$team_id, f)
    out <- unname(out[as.character(release$team_id)])
    ifelse(is.na(out), empty, out)
  }
  wins <- sides$won
  reference <- order_of[REFERENCE_RANK]
  recent <- sides$week >= week - 3
  data.frame(
    release = release$release, team_id = release$team_id,
    best_win = per_team(ifelse(wins, sides$opponent_power, -Inf), max, -Inf),
    worst_loss = per_team(ifelse(!wins, sides$opponent_power, Inf), min, Inf),
    top10_wins = per_team(wins & as.character(sides$opponent) %in% top10, sum, 0),
    bad_losses = per_team(!wins & (as.character(sides$opponent) %in% outside40 |
                                     !as.character(sides$opponent) %in% names(power)), sum, 0),
    recent_losses = per_team(!wins & recent, sum, 0)
  )
})
extra <- do.call(rbind, extra)
data <- merge(data, extra, by = c("release", "team_id"), sort = FALSE)
# No wins or no losses: measure from the reference team so the input stays finite.
data$best_win <- ifelse(is.finite(data$best_win), data$best_win, min(data$best_win[is.finite(data$best_win)]))
data$worst_loss <- ifelse(is.finite(data$worst_loss), data$worst_loss, max(data$worst_loss[is.finite(data$worst_loss)]))

# Where the committee had each team in its previous release that season.
releases <- unique(data[c("season", "week", "release")])
releases <- releases[order(releases$season, releases$week), ]
releases$previous <- ave(releases$release, releases$season, FUN = function(x) c(NA, x[-length(x)]))
before <- data[c("release", "team_id", "cfp", "losses", "record_strength")]
names(before) <- c("previous", "team_id", "prev_cfp", "prev_losses", "prev_strength")
data$previous <- releases$previous[match(data$release, releases$release)]
data <- merge(data, before, by = c("previous", "team_id"), all.x = TRUE, sort = FALSE)
data$has_previous <- !is.na(data$previous)
data$prev_points <- ifelse(is.na(data$prev_cfp), 0, 26 - data$prev_cfp)
data$was_ranked <- as.numeric(!is.na(data$prev_cfp))
data$new_losses <- ifelse(data$has_previous, data$losses - data$prev_losses, 0)
data$strength_gain <- ifelse(data$has_previous, data$record_strength - data$prev_strength, 0)
data <- data[order(data$season, data$week, data$team_id), ]

results <- regular[!is.na(regular$home_points), ]
home_won <- results$home_points > results$away_points
head_to_head <- data.frame(season = results$season, week = results$week,
                           winner = ifelse(home_won, results$home_id, results$away_id),
                           loser = ifelse(home_won, results$away_id, results$home_id))

#' +1 where team i beat team j before the release, -1 where j beat i, 0 otherwise.
beat <- function(season, week, i, j) {
  earlier <- head_to_head[head_to_head$season == season & head_to_head$week < week, ]
  won <- paste(earlier$winner, earlier$loser)
  (paste(i, j) %in% won) - (paste(j, i) %in% won)
}

EXTRA <- c("best_win", "worst_loss", "top10_wins", "bad_losses", "recent_losses",
           "prev_points", "was_ranked", "new_losses", "strength_gain")
scaled <- data
for (f in c(FEATURES, EXTRA)) scaled[[f]] <- (data[[f]] - mean(data[[f]])) / stats::sd(data[[f]])

# ---- Fitting with an optional head-to-head term ---------------------------------

#' The pool the committee's order is learned from: its 25 and the 25 best of
#' the rest by record strength.
release_pool <- function(r) {
  ranked <- r[!is.na(r$cfp), ]
  ranked <- ranked[order(ranked$cfp), ]
  near <- r[is.na(r$cfp), ]
  near <- near[order(-near$record_strength), ][seq_len(min(25, nrow(near))), ]
  list(pool = rbind(ranked, near), n = nrow(ranked))
}

pairs_with <- function(rows, features, h2h = FALSE) {
  parts <- lapply(split(rows, rows$release), function(r) {
    p <- release_pool(r)
    better <- rep(seq_len(p$n), times = nrow(p$pool) - seq_len(p$n))
    worse <- unlist(lapply(seq_len(p$n), function(i) seq(i + 1, nrow(p$pool))))
    d <- as.matrix(p$pool[better, features, drop = FALSE]) - as.matrix(p$pool[worse, features, drop = FALSE])
    if (h2h) d <- cbind(d, h2h = beat(r$season[1], r$week[1], p$pool$team_id[better], p$pool$team_id[worse]))
    d
  })
  d <- do.call(rbind, parts)
  data.frame(y = rep(c(1, 0), each = nrow(d)), rbind(d, -d))
}

fit_with <- function(rows, features, h2h = FALSE) {
  stats::coef(suppressWarnings(stats::glm(y ~ . - 1, data = pairs_with(rows, features, h2h),
                                          family = stats::binomial())))
}

#' Score teams in a release. With head-to-head, the best 40 by plain score
#' are re-scored by how many of the other 39 each would be ranked above.
score_release <- function(r, beta, features) {
  plain <- drop(as.matrix(r[, features, drop = FALSE]) %*% beta[features])
  if (!"h2h" %in% names(beta)) return(plain)
  top <- order(-plain)[seq_len(min(40, length(plain)))]
  ids <- r$team_id[top]
  above <- vapply(seq_along(top), function(k) {
    edge <- plain[top[k]] - plain[top] + beta[["h2h"]] * beat(r$season[1], r$week[1], ids[k], ids)
    sum(stats::plogis(edge[-k]))
  }, numeric(1))
  out <- plain - max(plain) - 100  # everyone else stays below, in plain order
  out[top] <- above
  out
}

out_of_sample_with <- function(rows, features, h2h = FALSE) {
  score <- rep(NA_real_, nrow(rows))
  for (season in SEASONS) {
    held <- rows$season == season
    beta <- fit_with(rows[!held, ], features, h2h)
    for (release in unique(rows$release[held])) {
      i <- which(rows$release == release)
      score[i] <- score_release(rows[i, ], beta, features)
    }
  }
  score
}

report_on <- function(label, rows, score) {
  graded <- vapply(split(seq_len(nrow(rows)), rows$release), function(i) grade(rows[i, ], score[i]), numeric(4))
  g <- rowMeans(graded)
  cat(sprintf("%-52s %5.2f places off   top 4: %.2f   top 12: %5.2f   same No. 1: %3.0f%%\n",
              label, g[["off"]], g[["top4"]], g[["top12"]], 100 * g[["first"]]))
  invisible(g)
}

base <- c("losses", "record_strength", "power", "tier")
cat(sprintf("\nEvery release (%d), scored on seasons left out:\n", length(unique(scaled$release))))
report_on("The four inputs in the app", scaled, out_of_sample_with(scaled, base))
report_on("  + best win and worst loss", scaled, out_of_sample_with(scaled, c(base, "best_win", "worst_loss")))
report_on("  + top-10 wins and bad losses", scaled, out_of_sample_with(scaled, c(base, "top10_wins", "bad_losses")))
report_on("  + losses in the last three weeks", scaled, out_of_sample_with(scaled, c(base, "recent_losses")))
report_on("  + head-to-head", scaled, out_of_sample_with(scaled, base, h2h = TRUE))

later <- scaled[scaled$has_previous, ]
anchor <- c(base, "prev_points", "was_ranked")
cat(sprintf("\nReleases after a season's first (%d), where last week's ranking is known:\n",
            length(unique(later$release))))
report_on("The four inputs in the app", later, out_of_sample_with(later, base))
report_on("Last week's committee ranking, unchanged", later, later$prev_points + later$was_ranked)
report_on("AP poll, same week", later, -ifelse(is.na(later$ap), 26, later$ap))
report_on("Four inputs + last week's rank", later, out_of_sample_with(later, anchor))
report_on("  + new losses and record strength gained", later,
          out_of_sample_with(later, c(anchor, "new_losses", "strength_gain")))
report_on("  + head-to-head", later, out_of_sample_with(later, c(anchor, "new_losses", "strength_gain"), h2h = TRUE))

chosen <- c(anchor, "new_losses", "strength_gain")
beta <- fit_with(later, chosen)
cat("\nWeights for the week-to-week model (inputs on one scale, so sizes compare):\n")
print(round(beta, 2))
cat("\nIn their own units:\n")
print(round(beta / vapply(chosen, function(f) stats::sd(data[[f]]), numeric(1)), 4))
cat("\nHead-to-head weight in the from-scratch model (scaled inputs):", round(fit_with(scaled, base, TRUE)[["h2h"]], 2), "\n")
