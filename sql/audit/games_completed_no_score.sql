-- Games marked completed with a score missing. The fit drops them quietly,
-- so the model would lose the game without anyone noticing.
SELECT game_id, season, week, start_date, home_team, home_points, away_team, away_points
FROM games
WHERE completed = 1
  AND (home_points IS NULL OR away_points IS NULL)
ORDER BY season, week, game_id;
