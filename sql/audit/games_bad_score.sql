-- Scores below zero or above 100. Neither happens in real FBS football.
SELECT game_id, season, week, home_team, home_points, away_team, away_points
FROM games
WHERE home_points < 0 OR away_points < 0
   OR home_points > 100 OR away_points > 100
ORDER BY season, week, game_id;
