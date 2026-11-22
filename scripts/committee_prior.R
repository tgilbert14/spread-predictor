# Fit the committee weights that a season starts from, on earlier seasons'
# committee rankings, and save them as data/committee_learned.json.
#
# The committee's rules for 2026 kept the same ingredients but changed how
# much each one counts. So earlier seasons are a starting point, not the
# answer: during a season the weights are pulled from here toward what that
# season's own rankings show (R/committee.R).
#
# Run from the project root, once, and again only to rebuild the start:
#   Rscript scripts/committee_prior.R            # 2018 to 2025, 2020 left out
#
# It refuses to overwrite a file the refresh has already written for a
# later season, since that file carries that season's learning.

for (file in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(file)

SEASONS <- setdiff(2018:2025, 2020)

con <- connect_readonly(PATHS$database)
all_games <- query_sql_file(con, "rating_games.sql", list(BURN_IN_SEASON))
conferences <- query_sql_file(con, "team_conferences.sql")
params <- read_params(PATHS$params)

#' A past season in the shape the committee code reads: teams with tier,
#' weekly Power, finished regular-season games and the committee's rankings.
season_app_data <- function(season) {
  teams <- query_sql_file(con, "season_teams.sql", list(season))
  teams$tier <- as.integer(is_power_team(teams$conference, teams$team_id, season))
  power <- power_ratings(all_games[all_games$season <= season & all_games$season_type == "regular", ], conferences)
  weekly <- power_through(power, seq_len(max(power$weekly$week) + 1L))
  weekly$power <- weekly$power - stats::ave(weekly$power, weekly$week)
  results <- season_results(con, season)
  list(meta = list(season = season), teams = teams, params = list(sigma = params$sigma),
       history = weekly[weekly$team_id %in% teams$team_id, ],
       results = results, polls = load_polls(PATHS$snapshots, season, teams))
}

resume_pairs <- list()
update_pairs <- list()
for (season in SEASONS) {
  app <- season_app_data(season)
  released <- app$polls[app$polls$poll == "cfp", ]
  for (week in sort(unique(released$week))) {
    inputs <- committee_inputs(app, week)
    if (is.null(inputs)) next
    ranking <- released[released$week == week, ]
    resume_pairs[[length(resume_pairs) + 1]] <- committee_pairs(inputs, ranking, RESUME_INPUTS)
    if (!is.na(attr(inputs, "previous"))) {
      update_pairs[[length(update_pairs) + 1]] <- committee_pairs(inputs, ranking, UPDATE_INPUTS)
    }
  }
  message(season, ": ", length(unique(released$week)), " rankings")
}
DBI::dbDisconnect(con)

learned <- list(resume = fit_committee_weights(do.call(rbind, resume_pairs)),
                update = fit_committee_weights(do.call(rbind, update_pairs)))
path <- COMMITTEE_LEARNED_PATH
if (file.exists(path)) {
  existing <- jsonlite::read_json(path, simplifyVector = TRUE)
  if (isTRUE(existing$season > max(SEASONS))) {
    # Keep that season's learning, and give it this start.
    existing$prior <- lapply(learned, function(w) as.list(round(w, 5)))
    jsonlite::write_json(existing, path, auto_unbox = TRUE, pretty = TRUE, null = "null", digits = NA)
    message("Set the starting weights in ", path, " (season ", existing$season, ").")
    quit(save = "no")
  }
}
saved <- list(season = max(SEASONS), written = format(Sys.Date()),
              rankings_used = list(resume = length(resume_pairs), update = length(update_pairs)),
              seasons = SEASONS, learned = lapply(learned, function(w) as.list(round(w, 5))), prior = NULL)
jsonlite::write_json(saved, path, auto_unbox = TRUE, pretty = TRUE, null = "null", digits = NA)
message("Wrote ", path, ": starting weights from ", length(resume_pairs), " rankings.")
