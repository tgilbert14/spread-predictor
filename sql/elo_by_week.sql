-- Each team's Elo going into each of its regular-season games in one season.
-- Elo only moves when a team plays, so these fill in the weeks before the
-- weekly snapshots started.
-- Parameters: season, season.
SELECT week, home_id AS team_id, home_pregame_elo AS elo
FROM games
WHERE season = ?
  AND season_type = 'regular'
  AND home_pregame_elo IS NOT NULL
UNION ALL
SELECT week, away_id AS team_id, away_pregame_elo AS elo
FROM games
WHERE season = ?
  AND season_type = 'regular'
  AND away_pregame_elo IS NOT NULL
ORDER BY team_id, week;
