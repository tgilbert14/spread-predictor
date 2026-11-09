-- Completed FBS-vs-FBS games with a final score.
-- The season and pregame Elo filters are applied in R (R/fit.R), so these
-- same rows also feed the blend-weight fit, which does not need Elo.
SELECT
  game_id,
  season,
  week,
  season_type,
  neutral_site,
  home_id,
  away_id,
  home_pregame_elo,
  away_pregame_elo,
  home_points - away_points AS home_margin
FROM games
WHERE completed = 1
  AND home_class = 'fbs'
  AND away_class = 'fbs'
  AND home_points IS NOT NULL
  AND away_points IS NOT NULL
ORDER BY season, week, game_id;
