-- Finished regular-season games in one season, for showing how a past
-- week's matchup turned out.
-- Parameters: season.
SELECT game_id, week, start_date, home_id, away_id, neutral_site, home_points, away_points
FROM games
WHERE season = ?
  AND season_type = 'regular'
  AND completed = 1
  AND home_points IS NOT NULL
  AND away_points IS NOT NULL
ORDER BY week, start_date, game_id;
