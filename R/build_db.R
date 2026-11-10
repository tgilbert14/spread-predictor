# Build cfb.sqlite from the snapshot CSVs, and check that it hangs together.
#
# The database is a build artifact: it is always rebuilt from scratch from
# data/snapshots/, never edited in place. Table definitions live in
# sql/schema.sql.

#' Drop and recreate the database from every snapshot CSV.
#'
#' Builds into a temp file next to the target and swaps it in at the end, so
#' a failed build leaves the previous database untouched.
#'
#' @return The database path, invisibly.
build_db <- function(snapshots_dir = PATHS$snapshots,
                     db_path = PATHS$database,
                     schema_path = PATHS$schema) {
  if (length(list.files(file.path(snapshots_dir, "games"), pattern = "\\.csv$")) == 0) {
    stop("No games snapshots found in ", snapshots_dir, ". Run Rscript scripts/backfill.R first.", call. = FALSE)
  }

  tmp_db <- paste0(db_path, ".building")
  unlink(tmp_db)
  on.exit(unlink(tmp_db))  # nothing left to remove once it is renamed

  con <- DBI::dbConnect(RSQLite::SQLite(), tmp_db)
  tryCatch(fill_db(con, snapshots_dir, schema_path), finally = DBI::dbDisconnect(con))

  if (!file.rename(tmp_db, db_path)) {
    stop("Built the database but could not replace ", db_path, ". Close anything that has it open and try again.", call. = FALSE)
  }
  message("Built ", db_path, ".")
  invisible(db_path)
}

#' Create the tables and load every snapshot into them, in one transaction.
fill_db <- function(con, snapshots_dir, schema_path) {
  for (statement in schema_statements(schema_path)) {
    DBI::dbExecute(con, statement)
  }
  DBI::dbWithTransaction(con, {
    load_table(con, "teams", read_season_files(file.path(snapshots_dir, "teams"), add_season = TRUE))
    load_table(con, "games", read_season_files(file.path(snapshots_dir, "games")))
    apply_neutral_overrides(con)
    load_table(con, "lines", read_season_files(file.path(snapshots_dir, "lines")))
    drop_orphan_lines(con)
    load_table(con, "ratings", read_ratings_files(file.path(snapshots_dir, "ratings")))
  })
}

#' Correct neutral-site flags the source has wrong.
#'
#' Snapshot files are never edited, so known mistakes are fixed here, from a
#' small hand-kept list with a reason for every row. The data audit's
#' neutral-games-by-season table is how new ones get noticed.
#'
#' @param path CSV with game_id, neutral_site (0 or 1) and reason.
apply_neutral_overrides <- function(con, path = file.path(PATHS$overrides, "neutral_site.csv")) {
  if (!file.exists(path)) return(invisible(0L))
  overrides <- utils::read.csv(path, stringsAsFactors = FALSE)
  if (!all(overrides$neutral_site %in% c(0, 1))) {
    stop(path, ": neutral_site must be 0 or 1 on every row.", call. = FALSE)
  }
  changed <- 0L
  for (i in seq_len(nrow(overrides))) {
    changed <- changed + DBI::dbExecute(
      con, "UPDATE games SET neutral_site = ? WHERE game_id = ? AND neutral_site <> ?",
      params = list(overrides$neutral_site[i], overrides$game_id[i], overrides$neutral_site[i])
    )
  }
  if (changed > 0) message("Corrected the neutral-site flag on ", changed, " game(s) from ", path, ".")
  invisible(changed)
}

#' Drop lines for games we do not track.
#'
#' The lines endpoint returns every game a sportsbook listed, including games
#' between two FCS teams. Our games table only has games with an FBS team, so
#' those lines can never be used. Removing them keeps the audit meaningful.
drop_orphan_lines <- function(con) {
  dropped <- DBI::dbExecute(con, "DELETE FROM lines WHERE game_id NOT IN (SELECT game_id FROM games)")
  if (dropped > 0) message("Dropped ", dropped, " line rows for games that are not in the games table.")
  invisible(dropped)
}

#' One rating per team per snapshot.
#'
#' The API sometimes lists a team twice in one pull, now and then with two
#' different values. We cannot tell which copy is right, so the copies are
#' averaged and the teams are named, rather than silently using whichever
#' came first.
#'
#' @param ratings A ratings snapshot (needs team_id, team, rating).
#' @param what Label for the message, such as the file path.
combine_duplicate_ratings <- function(ratings, what) {
  dup_ids <- unique(ratings$team_id[duplicated(ratings$team_id)])
  if (length(dup_ids) == 0) return(ratings)

  is_dup <- ratings$team_id %in% dup_ids
  differ <- vapply(dup_ids, function(id) {
    diff(range(ratings$rating[ratings$team_id == id], na.rm = TRUE)) > 0
  }, logical(1))
  if (any(differ)) {
    names_differ <- unique(ratings$team[ratings$team_id %in% dup_ids[differ]])
    warning(what, ": listed twice with different ratings, so the average is used: ",
            paste(names_differ, collapse = ", "), ".", call. = FALSE)
  }
  means <- tapply(ratings$rating[is_dup], ratings$team_id[is_dup], mean, na.rm = TRUE)
  keep <- !duplicated(ratings$team_id)
  out <- ratings[keep, , drop = FALSE]
  fix <- out$team_id %in% dup_ids
  out$rating[fix] <- as.numeric(means[as.character(out$team_id[fix])])
  out
}

#' Split schema.sql into single statements, dropping "--" comments.
schema_statements <- function(schema_path = PATHS$schema) {
  sql <- sub("--.*$", "", readLines(schema_path, warn = FALSE))
  statements <- trimws(strsplit(paste(sql, collapse = "\n"), ";", fixed = TRUE)[[1]])
  statements[nzchar(statements)]
}

#' Read every {season}.csv in a folder.
#'
#' @param add_season TRUE for teams files, which carry the season only in
#'   the file name.
#' @return A list of data frames, named by file path.
read_season_files <- function(dir, add_season = FALSE) {
  files <- list.files(dir, pattern = "^[0-9]{4}\\.csv$", full.names = TRUE)
  frames <- lapply(files, function(path) {
    df <- read_snapshot(path)
    if (add_season) df$season <- rep(as.integer(sub("\\.csv$", "", basename(path))), nrow(df))
    df
  })
  stats::setNames(frames, files)
}

#' Read every ratings file. Source and finality come from the path.
#' @return A list of data frames, named by file path.
read_ratings_files <- function(dir) {
  files <- list.files(dir, pattern = "^[0-9]{4}_(wk[0-9]{2}|final)\\.csv$", recursive = TRUE, full.names = TRUE)
  sources <- basename(dirname(files))
  unknown <- !sources %in% RATING_SOURCES
  if (any(unknown)) {
    warning("Skipped ratings files in unknown folders: ", paste(files[unknown], collapse = ", "), call. = FALSE)
  }
  frames <- lapply(files[!unknown], function(path) {
    df <- combine_duplicate_ratings(read_snapshot(path), path)
    df$source <- rep(basename(dirname(path)), nrow(df))
    df$is_final <- rep(as.integer(grepl("_final\\.csv$", path)), nrow(df))
    df
  })
  stats::setNames(frames, files[!unknown])
}

#' Append snapshot files to a table, in the table's column order.
#'
#' @param frames A list of data frames named by file path, so an error can
#'   say which file is wrong.
load_table <- function(con, table, frames) {
  columns <- DBI::dbListFields(con, table)
  n <- 0L
  for (path in names(frames)) {
    df <- frames[[path]]
    missing <- setdiff(columns, names(df))
    if (length(missing) > 0) {
      stop(
        path, " is missing column(s): ", paste(missing, collapse = ", "),
        ". See docs/data-dictionary.md for the expected layout.",
        call. = FALSE
      )
    }
    df <- df[columns]
    # SQLite has no boolean type: store TRUE/FALSE as 1/0.
    df[] <- lapply(df, function(x) if (is.logical(x)) as.integer(x) else x)
    DBI::dbAppendTable(con, table, df)
    n <- n + nrow(df)
  }
  message("Loaded ", n, " rows from ", length(frames), " file(s) into ", table, ".")
  invisible(n)
}

#' Gate checks on a built database.
#'
#' @return A list of data frames:
#'   * `games`: games per season and season type, with FBS-vs-FBS and
#'     completed counts.
#'   * `ratings`: rating rows per source, season and week.
#'   * `unjoined`: FBS teams that play in `games` but have no row in `teams`,
#'     or no rating from a source that has ratings for that season.
#'   And `ok`: TRUE when there are games and nothing fails to join.
check_db <- function(db_path = PATHS$database) {
  if (!file.exists(db_path)) {
    stop("No database at ", db_path, ". Run build_db() first.", call. = FALSE)
  }
  con <- DBI::dbConnect(RSQLite::SQLite(), db_path, flags = RSQLite::SQLITE_RO)
  on.exit(DBI::dbDisconnect(con))

  games <- DBI::dbGetQuery(con, "
    SELECT season, season_type,
           COUNT(*) AS n_games,
           SUM(home_class = 'fbs' AND away_class = 'fbs') AS n_fbs_vs_fbs,
           SUM(completed) AS n_completed
    FROM games
    GROUP BY season, season_type
    ORDER BY season, season_type")

  ratings <- DBI::dbGetQuery(con, "
    SELECT source, season, week, is_final, COUNT(*) AS n_teams
    FROM ratings
    GROUP BY source, season, week, is_final
    ORDER BY source, season, is_final, week")

  # Sources are only checked for seasons where they have any ratings at all.
  # A season with no ratings shows up in the coverage table instead.
  unjoined <- DBI::dbGetQuery(con, "
    WITH fbs AS (
      SELECT DISTINCT season, home_id AS team_id, home_team AS team FROM games WHERE home_class = 'fbs'
      UNION
      SELECT DISTINCT season, away_id, away_team FROM games WHERE away_class = 'fbs'
    ),
    sources AS (SELECT DISTINCT source, season FROM ratings),
    rated   AS (SELECT DISTINCT source, season, team_id FROM ratings)
    SELECT f.season, f.team_id, f.team, 'teams' AS missing_from
    FROM fbs f
    LEFT JOIN teams t ON t.season = f.season AND t.team_id = f.team_id
    WHERE t.team_id IS NULL
    UNION ALL
    SELECT f.season, f.team_id, f.team, 'ratings: ' || s.source
    FROM fbs f
    JOIN sources s ON s.season = f.season
    LEFT JOIN rated r ON r.source = s.source AND r.season = f.season AND r.team_id = f.team_id
    WHERE r.team_id IS NULL
    ORDER BY 1, 4, 3")

  list(
    games = games,
    ratings = ratings,
    unjoined = unjoined,
    ok = nrow(games) > 0 && nrow(unjoined) == 0
  )
}

#' Print check_db() results in a form that is quick to scan.
report_db_checks <- function(checks) {
  cat("\nGames per season:\n")
  print(checks$games, row.names = FALSE)

  cat("\nRating snapshots (rows per source, season and week; is_final = 1 is season-final):\n")
  print(checks$ratings, row.names = FALSE)

  if (nrow(checks$unjoined) == 0) {
    cat("\nEvery FBS team in games joins to teams and ratings.\n")
  } else {
    cat("\nFBS teams in games that do not join (", nrow(checks$unjoined), " rows):\n", sep = "")
    print(utils::head(checks$unjoined, 50), row.names = FALSE)
    cat("Usually a school name that differs between endpoints. See match_team_ids() in R/ingest.R.\n")
  }
  invisible(checks)
}
