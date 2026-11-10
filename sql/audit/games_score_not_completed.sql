-- Games with a score that are not marked completed. Could be a game in
-- progress when the snapshot was taken, or a flag that never got updated.
SELECT game_id, season, week, start_date, home_team, home_points, away_team, away_points
FROM games
WHERE completed = 0
  AND (home_points IS NOT NULL OR away_points IS NOT NULL)
ORDER BY season, week, game_id;
