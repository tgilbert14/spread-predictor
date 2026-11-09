-- FBS-vs-FBS games not yet played in one season and week.
-- Parameters: season, week.
SELECT game_id, start_date, home_id, away_id, neutral_site
FROM games
WHERE season = ?
  AND week = ?
  AND completed = 0
  AND home_class = 'fbs'
  AND away_class = 'fbs'
ORDER BY start_date, game_id;
