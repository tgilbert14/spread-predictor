-- Schema for cfb.sqlite.
-- The database is a build artifact. scripts/refresh.R (via R/build_db.R)
-- drops and recreates it from the CSV files in data/snapshots/.
-- Plain ANSI-style SQL on purpose, so it ports to DuckDB or Azure SQL.

CREATE TABLE teams (
  season        INTEGER NOT NULL,
  team_id       INTEGER NOT NULL,
  school        TEXT    NOT NULL,
  mascot        TEXT,
  abbreviation  TEXT,
  conference    TEXT,
  color         TEXT,     -- primary hex color, e.g. '#BA0C2F'
  alt_color     TEXT,     -- alternate hex color
  logo          TEXT,     -- logo URL, may be NULL
  PRIMARY KEY (season, team_id)
);

CREATE TABLE games (
  game_id           INTEGER PRIMARY KEY,
  season            INTEGER NOT NULL,
  week              INTEGER NOT NULL,
  season_type       TEXT    NOT NULL,   -- 'regular' or 'postseason'
  start_date        TEXT,               -- ISO 8601, UTC
  completed         INTEGER NOT NULL,   -- 0 or 1
  neutral_site      INTEGER NOT NULL,   -- 0 or 1
  home_id           INTEGER NOT NULL,
  home_team         TEXT    NOT NULL,
  home_class        TEXT,               -- 'fbs', 'fcs', ...
  home_points       INTEGER,
  home_pregame_elo  REAL,
  away_id           INTEGER NOT NULL,
  away_team         TEXT    NOT NULL,
  away_class        TEXT,
  away_points       INTEGER,
  away_pregame_elo  REAL
);

-- One row per game per sportsbook.
-- spread is home-relative, the CFBD convention: -7 means home favored by 7.
CREATE TABLE lines (
  game_id    INTEGER NOT NULL,
  provider   TEXT    NOT NULL,
  spread     REAL,
  pulled_at  TEXT,
  PRIMARY KEY (game_id, provider)
);

-- One row per team per rating system per snapshot.
-- is_final = 1: season-final values pulled after the fact (week is NULL).
--               These already include every result. Never fit on them.
-- is_final = 0: a weekly snapshot we captured ourselves. Safe to fit on.
CREATE TABLE ratings (
  source     TEXT    NOT NULL,   -- 'sp', 'fpi', 'srs', 'elo'
  season     INTEGER NOT NULL,
  week       INTEGER,
  is_final   INTEGER NOT NULL,
  team_id    INTEGER NOT NULL,
  team       TEXT,
  rating     REAL,
  pulled_at  TEXT
);

CREATE INDEX idx_ratings_lookup ON ratings (source, season, week, team_id);
CREATE INDEX idx_games_season   ON games (season, week);
