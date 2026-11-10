# Data audit: checks that cfb.sqlite hangs together before the model uses it.
#
# Each check is a small function that takes a database connection and returns
# the rows that look wrong. Zero rows means the check passed. "info" checks
# are the exception: they always return a small table to read, not problems.
#
# Most checks are one query in sql/audit/. The few that need a median, a
# correlation or a pattern match pull their input with SQL and finish in R.
#
# audit_db() runs every check and returns one summary row per check.
# scripts/audit.R prints that summary and writes docs/data-audit.md.

AUDIT_SQL_DIR <- file.path("sql", "audit")

# Most flagged rows kept per check, so the report stays readable.
AUDIT_MAX_ROWS <- 25

# Severity levels, worst first.
#   error:   would corrupt the model if left in.
#   warning: worth a look, the model copes.
#   info:    a table to read, nothing to pass or fail.
AUDIT_SEVERITIES <- c("error", "warning", "info")


# ---- Helpers -----------------------------------------------------------------

#' Run one query file from sql/audit/ and return the rows.
audit_query <- function(con, file, sql_dir = AUDIT_SQL_DIR) {
  path <- file.path(sql_dir, file)
  if (!file.exists(path)) {
    stop("Audit query not found: ", path, ". Run the audit from the project root.", call. = FALSE)
  }
  DBI::dbGetQuery(con, paste(readLines(path, warn = FALSE), collapse = "\n"))
}

#' Make a check function that is just one query file.
audit_sql_check <- function(file) {
  force(file)
  function(con, sql_dir = AUDIT_SQL_DIR) audit_query(con, file, sql_dir)
}

#' Median spread per game, next to the final home margin.
#'
#' The median across sportsbooks is the closing line the pipeline uses.
#' Expected home margin is minus the spread (see docs/data-dictionary.md).
audit_median_lines <- function(lines) {
  if (nrow(lines) == 0) {
    return(data.frame(game_id = integer(), season = integer(), median_spread = numeric(),
                      home_margin = numeric(), n_providers = integer()))
  }
  by_game <- split(lines, lines$game_id)
  out <- do.call(rbind, lapply(by_game, function(g) {
    data.frame(
      game_id = g$game_id[1], season = g$season[1], week = g$week[1],
      home_team = g$home_team[1], away_team = g$away_team[1],
      home_points = g$home_points[1], away_points = g$away_points[1],
      n_providers = nrow(g),
      median_spread = stats::median(g$spread),
      home_margin = g$home_margin[1],
      stringsAsFactors = FALSE
    )
  }))
  rownames(out) <- NULL
  out
}

#' TRUE for strings like "2026-08-29T23:30:00.000Z" that parse as a time.
audit_is_iso_time <- function(x) {
  looks_right <- !is.na(x) & grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}", x)
  parsed <- as.POSIXct(sub("T", " ", substr(x, 1, 16)), tz = "UTC", format = "%Y-%m-%d %H:%M")
  looks_right & !is.na(parsed)
}

#' TRUE for colors like "#BA0C2F".
audit_is_hex_color <- function(x) {
  !is.na(x) & grepl("^#[0-9A-Fa-f]{6}$", x)
}


# ---- Checks that finish in R -------------------------------------------------

#' Games whose start_date is missing or not a parseable ISO 8601 time.
check_games_bad_start_date <- function(con, sql_dir = AUDIT_SQL_DIR) {
  games <- audit_query(con, "games_start_dates.sql", sql_dir)
  games[!audit_is_iso_time(games$start_date), , drop = FALSE]
}

#' Teams whose primary or alternate color is not a "#RRGGBB" hex string.
check_teams_bad_color <- function(con, sql_dir = AUDIT_SQL_DIR) {
  teams <- audit_query(con, "teams_colors.sql", sql_dir)
  teams[!audit_is_hex_color(teams$color) | !audit_is_hex_color(teams$alt_color), , drop = FALSE]
}

#' Seasons where the closing line does not track the real margin.
#'
#' If the spread sign were flipped, minus the spread would correlate
#' negatively with the home margin. Real markets sit around 0.6 to 0.8.
check_lines_sign <- function(con, sql_dir = AUDIT_SQL_DIR, min_correlation = 0.5) {
  games <- audit_median_lines(audit_query(con, "lines_with_results.sql", sql_dir))
  seasons <- split(games, games$season)
  out <- data.frame(
    season = as.integer(names(seasons)),
    n_games = vapply(seasons, nrow, integer(1)),
    correlation = vapply(seasons, function(s) {
      if (nrow(s) < 3) return(NA_real_)
      stats::cor(-s$median_spread, s$home_margin)
    }, numeric(1))
  )
  rownames(out) <- NULL
  out[is.na(out$correlation) | out$correlation < min_correlation, , drop = FALSE]
}

#' Provider lines that look like the other books' line with the sign flipped.
#'
#' Flags a line when the other providers on that game agree on a favorite
#' by at least `min_spread` points and this provider has the same number
#' (within `tolerance`) for the other team. That is the signature of a
#' provider that swapped home and away, which happens most on neutral-site
#' and bowl games. With three or more books the median shrugs off one flip;
#' with two, or when the flip is in the majority, the closing line is wrong.
check_lines_flipped_sign <- function(con, sql_dir = AUDIT_SQL_DIR, min_spread = 3, tolerance = 1.5) {
  lines <- audit_query(con, "lines_by_game.sql", sql_dir)
  lines$others_median <- NA_real_
  for (rows in split(seq_len(nrow(lines)), lines$game_id)) {
    if (length(rows) < 2) next
    lines$others_median[rows] <- vapply(rows, function(i) {
      stats::median(lines$spread[setdiff(rows, i)])
    }, numeric(1))
  }
  flipped <- !is.na(lines$others_median) &
    abs(lines$others_median) >= min_spread &
    sign(lines$spread) == -sign(lines$others_median) &
    abs(lines$spread + lines$others_median) <= tolerance
  game_median <- tapply(lines$spread, lines$game_id, stats::median)
  out <- lines[flipped, c("game_id", "season", "season_type", "week", "neutral_site",
                          "home_team", "away_team", "home_points", "away_points",
                          "provider", "spread", "others_median")]
  out$closing_line <- as.numeric(game_median[as.character(out$game_id)])
  rownames(out) <- NULL
  out
}

#' Games where the closing line missed the final margin by more than 45.
#'
#' Usually a real blowout. A flipped home and away, or a wrong score, would
#' also land here, so a person should eyeball the list.
check_lines_worst_misses <- function(con, sql_dir = AUDIT_SQL_DIR, max_miss = 45) {
  games <- audit_median_lines(audit_query(con, "lines_with_results.sql", sql_dir))
  games$miss <- games$home_margin - (-games$median_spread)
  worst <- games[abs(games$miss) > max_miss, , drop = FALSE]
  worst[order(-abs(worst$miss)), , drop = FALSE]
}

#' Each provider's average miss against the final margin.
#'
#' consensus_mae is the median-of-providers line scored on the same games,
#' so `vs_consensus` above zero means that provider alone did worse than
#' the median the pipeline uses.
check_lines_provider_accuracy <- function(con, sql_dir = AUDIT_SQL_DIR) {
  lines <- audit_query(con, "lines_with_results.sql", sql_dir)
  if (nrow(lines) == 0) {
    return(data.frame(provider = character(), n_games = integer(), mae = numeric(),
                      consensus_mae = numeric(), vs_consensus = numeric()))
  }
  medians <- audit_median_lines(lines)
  lines$median_spread <- medians$median_spread[match(lines$game_id, medians$game_id)]
  by_provider <- split(lines, lines$provider)
  out <- data.frame(
    provider = names(by_provider),
    n_games = vapply(by_provider, nrow, integer(1)),
    mae = vapply(by_provider, function(p) mean(abs(p$home_margin + p$spread)), numeric(1)),
    consensus_mae = vapply(by_provider, function(p) mean(abs(p$home_margin + p$median_spread)), numeric(1)),
    stringsAsFactors = FALSE
  )
  out$vs_consensus <- out$mae - out$consensus_mae
  out[c("mae", "consensus_mae", "vs_consensus")] <- lapply(out[c("mae", "consensus_mae", "vs_consensus")], round, 2)
  rownames(out) <- NULL
  out[order(out$mae), , drop = FALSE]
}


# ---- The list of checks ------------------------------------------------------

#' One entry in the check list.
audit_check <- function(name, table, severity, looks_for, run) {
  stopifnot(severity %in% AUDIT_SEVERITIES)
  list(name = name, table = table, severity = severity, looks_for = looks_for, run = run)
}

#' Every check, in report order.
audit_checks <- function() {
  list(
    # Games
    audit_check("games_duplicate_id", "games", "error",
      "The same game_id stored more than once.", audit_sql_check("games_duplicate_id.sql")),
    audit_check("games_same_matchup_same_date", "games", "error",
      "The same two teams meeting twice on one date under different game ids.",
      audit_sql_check("games_same_matchup_same_date.sql")),
    audit_check("games_completed_no_score", "games", "error",
      "Completed games with a missing score.", audit_sql_check("games_completed_no_score.sql")),
    audit_check("games_score_not_completed", "games", "warning",
      "Games with a score that are not marked completed.", audit_sql_check("games_score_not_completed.sql")),
    audit_check("games_bad_score", "games", "error",
      "Scores below 0 or above 100.", audit_sql_check("games_bad_score.sql")),
    audit_check("games_completed_in_future", "games", "error",
      "Completed games that start after the newest data pull.", audit_sql_check("games_completed_in_future.sql")),
    audit_check("games_team_plays_itself", "games", "error",
      "Games where the home and away team are the same.", audit_sql_check("games_team_plays_itself.sql")),
    audit_check("games_fbs_team_not_in_teams", "games", "error",
      "Teams marked FBS in a game but missing from that season's teams table.",
      audit_sql_check("games_fbs_team_not_in_teams.sql")),
    audit_check("games_class_vs_teams", "games", "warning",
      "Teams in the FBS teams table but marked as another class in a game (left out of the fit).",
      audit_sql_check("games_class_vs_teams.sql")),
    audit_check("games_unexpected_class", "games", "error",
      "Class values other than fbs, fcs, ii or iii.", audit_sql_check("games_unexpected_class.sql")),
    audit_check("games_missing_elo", "games", "warning",
      "Completed FBS-vs-FBS games missing a pregame Elo (they drop out of the Elo fit).",
      audit_sql_check("games_missing_elo.sql")),
    audit_check("games_elo_out_of_range", "games", "error",
      "Pregame Elo below 500 or above 2600.", audit_sql_check("games_elo_out_of_range.sql")),
    audit_check("games_team_twice_same_day", "games", "error",
      "A team listed in two games on the same date.", audit_sql_check("games_team_twice_same_day.sql")),
    audit_check("games_per_team_season", "games", "warning",
      "FBS teams with fewer than 8 or more than 16 completed games in a finished season.",
      audit_sql_check("games_per_team_season.sql")),
    audit_check("games_bad_week", "games", "warning",
      "Regular-season weeks outside 1 to 16, postseason games not in week 1, or an unknown season type.",
      audit_sql_check("games_bad_week.sql")),
    audit_check("games_bad_start_date", "games", "error",
      "Start dates that are missing or cannot be read as a date and time.", check_games_bad_start_date),
    audit_check("games_neutral_by_season", "games", "info",
      "Neutral-site games per season, so a sudden change stands out.", audit_sql_check("games_neutral_by_season.sql")),

    # Lines
    audit_check("lines_orphan_game", "lines", "warning",
      "Lines for a game_id that is not in games.", audit_sql_check("lines_orphan_game.sql")),
    audit_check("lines_null_spread", "lines", "info",
      "Line rows with no spread (skipped by the pipeline).", audit_sql_check("lines_null_spread.sql")),
    audit_check("lines_absurd_spread", "lines", "error",
      "Spreads bigger than 70 points either way.", audit_sql_check("lines_absurd_spread.sql")),
    audit_check("lines_providers_per_game", "lines", "info",
      "How many sportsbooks quote each game, per season.", audit_sql_check("lines_providers_per_game.sql")),
    audit_check("lines_provider_disagreement", "lines", "warning",
      "Games where sportsbooks disagree by more than 7 points.", audit_sql_check("lines_provider_disagreement.sql")),
    audit_check("lines_flipped_sign", "lines", "warning",
      "A provider's spread that matches the other books' line for the other team (home and away swapped).",
      check_lines_flipped_sign),
    audit_check("lines_missing_for_fbs_games", "lines", "warning",
      "Completed FBS-vs-FBS games with no usable line, per season.", audit_sql_check("lines_missing_for_fbs_games.sql")),
    audit_check("lines_sign", "lines", "error",
      "Seasons where minus the closing spread does not track the home margin (correlation under 0.5).",
      check_lines_sign),
    audit_check("lines_worst_misses", "lines", "info",
      "Games where the closing line missed the final margin by more than 45 points.", check_lines_worst_misses),
    audit_check("lines_provider_accuracy", "lines", "info",
      "Average miss of each provider against the final margin, next to the median-of-providers line.",
      check_lines_provider_accuracy),

    # Ratings
    audit_check("ratings_duplicate", "ratings", "error",
      "A team rated twice in one snapshot.", audit_sql_check("ratings_duplicate.sql")),
    audit_check("ratings_team_not_in_teams", "ratings", "error",
      "Ratings for a team_id that is not in that season's teams table.", audit_sql_check("ratings_team_not_in_teams.sql")),
    audit_check("ratings_fbs_team_unrated", "ratings", "warning",
      "FBS teams with no rating in a snapshot from that source.", audit_sql_check("ratings_fbs_team_unrated.sql")),
    audit_check("ratings_rows_by_snapshot", "ratings", "info",
      "Rows per snapshot next to the number of FBS teams that season.", audit_sql_check("ratings_rows_by_snapshot.sql")),
    audit_check("ratings_out_of_range", "ratings", "error",
      "Ratings outside -45 to 45 (SP+, FPI, SRS) or 500 to 2600 (Elo), or an unknown source.",
      audit_sql_check("ratings_out_of_range.sql")),
    audit_check("ratings_constant_or_missing", "ratings", "error",
      "Snapshots where every rating is missing or identical.", audit_sql_check("ratings_constant_or_missing.sql")),
    audit_check("ratings_week_over_week", "ratings", "warning",
      "One-week rating changes over 15 points (SP+, FPI, SRS) or 250 (Elo). Needs two weekly snapshots.",
      audit_sql_check("ratings_week_over_week.sql")),

    # Teams
    audit_check("teams_duplicate", "teams", "error",
      "A team listed twice in one season.", audit_sql_check("teams_duplicate.sql")),
    audit_check("teams_missing_school", "teams", "error",
      "Teams with no school name.", audit_sql_check("teams_missing_school.sql")),
    audit_check("teams_bad_color", "teams", "warning",
      "Colors that are not a #RRGGBB hex code.", check_teams_bad_color),
    audit_check("teams_missing_logo", "teams", "warning",
      "Teams with no logo.", audit_sql_check("teams_missing_logo.sql")),
    audit_check("teams_conference_change", "teams", "info",
      "Teams that changed conference from one season to the next (real realignment).",
      audit_sql_check("teams_conference_change.sql")),
    audit_check("teams_name_change", "teams", "warning",
      "A team_id whose school name changes between seasons.", audit_sql_check("teams_name_change.sql")),

    # Talent, returning production and game stats
    audit_check("talent_duplicate", "talent", "error",
      "A team with two talent values in one season.", audit_sql_check("talent_duplicate.sql")),
    audit_check("returning_duplicate", "returning_production", "error",
      "A team with two returning-production values in one season.", audit_sql_check("returning_duplicate.sql")),
    audit_check("returning_out_of_range", "returning_production", "warning",
      "Returning-production shares below 0 or above 1 (the model pulls them back into range).",
      audit_sql_check("returning_out_of_range.sql")),
    audit_check("preseason_missing_by_season", "talent", "info",
      "FBS teams with no talent or no returning-production value, per season (they count as average).",
      audit_sql_check("preseason_missing_by_season.sql")),
    audit_check("game_stats_duplicate", "game_stats", "error",
      "A team with two rows of stats for one game.", audit_sql_check("game_stats_duplicate.sql")),
    audit_check("game_stats_bad_success_rate", "game_stats", "error",
      "Success rates outside 0 to 1.", audit_sql_check("game_stats_bad_success_rate.sql")),
    audit_check("game_stats_missing_for_fbs_games", "game_stats", "warning",
      "Seasons where over 3% of completed FBS-vs-FBS games have no stats for the home team.",
      audit_sql_check("game_stats_missing_for_fbs_games.sql"))
  )
}


# ---- Running the audit -------------------------------------------------------

#' Run every check and return one summary row per check.
#'
#' A check that fails to run (say, a broken query) is reported as an error
#' with the message, rather than stopping the whole audit.
#'
#' @return A data frame: `check`, `table`, `looks_for`, `severity`, `result`
#'   ("pass", "flagged" or "info"), `n_flagged`, and `rows`, a list column
#'   holding up to `max_rows` flagged rows per check.
audit_db <- function(con, sql_dir = AUDIT_SQL_DIR, max_rows = AUDIT_MAX_ROWS) {
  checks <- audit_checks()
  results <- lapply(checks, function(check) {
    rows <- tryCatch(
      check$run(con, sql_dir),
      error = function(e) data.frame(problem = paste("The check could not run:", conditionMessage(e)))
    )
    n <- nrow(rows)
    result <- if (check$severity == "info") "info" else if (n == 0) "pass" else "flagged"
    if (check$severity == "info" && "problem" %in% names(rows)) result <- "flagged"
    rownames(rows) <- NULL
    list(row = data.frame(
      check = check$name, table = check$table, looks_for = check$looks_for,
      severity = check$severity, result = result, n_flagged = n,
      stringsAsFactors = FALSE
    ), rows = utils::head(rows, max_rows))
  })
  summary <- do.call(rbind, lapply(results, `[[`, "row"))
  summary$rows <- lapply(results, `[[`, "rows")
  summary
}

#' TRUE if any "error" check flagged rows.
audit_has_errors <- function(summary) {
  any(summary$severity == "error" & summary$result == "flagged")
}

#' Row counts per table, for the report header.
audit_table_counts <- function(con) {
  tables <- c("teams", "games", "lines", "ratings", "talent", "returning_production", "game_stats")
  counts <- vapply(tables, function(t) {
    as.integer(DBI::dbGetQuery(con, paste("SELECT COUNT(*) AS n FROM", t))$n)
  }, integer(1))
  data.frame(table = tables, n_rows = counts, row.names = NULL)
}


# ---- Report ------------------------------------------------------------------

#' A data frame as a Markdown table.
audit_markdown_table <- function(df) {
  if (nrow(df) == 0) return("(no rows)")
  cells <- lapply(df, function(x) {
    x <- if (is.numeric(x)) format(x, trim = TRUE, drop0trailing = TRUE) else as.character(x)
    x[is.na(x) | x == "NA"] <- ""
    gsub("|", "\\|", x, fixed = TRUE)
  })
  header <- paste0("| ", paste(names(df), collapse = " | "), " |")
  divider <- paste0("|", paste(rep("---", ncol(df)), collapse = "|"), "|")
  body <- do.call(paste, c(cells, sep = " | "))
  c(header, divider, paste0("| ", body, " |"))
}

#' Plain-language result for the summary table.
audit_result_label <- function(severity, result) {
  ifelse(result == "pass", "Pass",
    ifelse(result == "info", "For information",
      ifelse(severity == "error", "Problem", "Worth a look")))
}

#' The audit as Markdown lines, for docs/data-audit.md.
#'
#' A short summary table comes first, then details only for checks that
#' flagged something or are informational.
audit_markdown <- function(summary, counts, date = Sys.Date()) {
  n_errors <- sum(summary$severity == "error" & summary$result == "flagged")
  n_warnings <- sum(summary$severity == "warning" & summary$result == "flagged")
  count_text <- paste(sprintf("%s %s", format(counts$n_rows, big.mark = ",", trim = TRUE), counts$table), collapse = ", ")

  out <- c(
    sprintf("_Generated file: written by scripts/audit.R on %s from cfb.sqlite (%s). Do not edit by hand; rerun the script._",
            format(date), count_text),
    "",
    "# Data audit",
    "",
    sprintf("Checked on %s. Rows checked: %s.", format(date), count_text),
    "",
    if (n_errors == 0) {
      "No check that could corrupt the model found anything."
    } else {
      sprintf("**%d check(s) that could corrupt the model found problems.** See the details below.", n_errors)
    },
    sprintf("%d other check(s) flagged rows worth a look.", n_warnings),
    "",
    "Severity: **error** would corrupt the model, **warning** is worth a look, **info** is a table to read.",
    "",
    "## Summary",
    "",
    audit_markdown_table(data.frame(
      Check = summary$check,
      `What it looks for` = summary$looks_for,
      Severity = summary$severity,
      Result = audit_result_label(summary$severity, summary$result),
      `Rows flagged` = ifelse(summary$result == "info", "", summary$n_flagged),
      check.names = FALSE
    )),
    "",
    "## Details"
  )

  for (i in which(summary$result != "pass")) {
    rows <- summary$rows[[i]]
    shown <- if (summary$n_flagged[i] > nrow(rows)) {
      sprintf("Showing the first %d of %d rows.", nrow(rows), summary$n_flagged[i])
    } else {
      sprintf("%d row(s).", summary$n_flagged[i])
    }
    out <- c(out, "", sprintf("### %s (%s)", summary$check[i], summary$severity[i]), "",
             summary$looks_for[i], shown, "", audit_markdown_table(rows))
  }
  c(out, "")
}

#' Print the summary to the console in a form that is quick to scan.
audit_print <- function(summary, counts) {
  cat("\nRows audited:\n")
  print(counts, row.names = FALSE)
  cat("\n")
  view <- data.frame(
    check = summary$check,
    severity = summary$severity,
    result = audit_result_label(summary$severity, summary$result),
    rows = ifelse(summary$result == "info", "", summary$n_flagged)
  )
  print(view, row.names = FALSE, right = FALSE)
  for (i in which(summary$result == "flagged")) {
    cat(sprintf("\n%s (%s): %s\n", summary$check[i], summary$severity[i], summary$looks_for[i]))
    print(utils::head(summary$rows[[i]], 10), row.names = FALSE)
  }
  invisible(summary)
}
