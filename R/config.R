# Paths and constants shared by the pipeline and the app.
# All paths are relative to the project root. Run scripts from there.

PATHS <- list(
  snapshots = file.path("data", "snapshots"),
  database  = "cfb.sqlite",
  schema    = file.path("sql", "schema.sql"),
  params    = file.path("data", "params.json"),
  app_data  = file.path("data", "app_data.rds")
)

# Seasons used to fit k, home field and sigma. 2020 is skipped on purpose:
# the COVID season had odd schedules and empty stadiums.
TRAINING_SEASONS <- 2021:2025

# Rating systems we snapshot. These are also the folder names under
# data/snapshots/ratings/ and the rating column names in the teams table.
RATING_SOURCES <- c("sp", "fpi", "srs", "elo")

# Ratings older than this many days raise a "stale" note in the app.
STALE_AFTER_DAYS <- 8

# Through this week, ratings still lean on preseason priors.
EARLY_SEASON_LAST_WEEK <- 3
