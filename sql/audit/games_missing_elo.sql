-- Completed FBS-vs-FBS games missing a pregame Elo. The Elo fit needs both,
-- so these games drop out of the fit set.
SELECT game_id, season, week, season_type, start_date,
       home_team, home_pregame_elo, away_team, away_pregame_elo
FROM games
WHERE completed = 1
  AND home_class = 'fbs' AND away_class = 'fbs'
  AND (home_pregame_elo IS NULL OR away_pregame_elo IS NULL)
ORDER BY season, week, game_id;
