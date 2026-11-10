-- How many sportsbooks quote each game, as a distribution per season.
WITH per_game AS (
  SELECT l.game_id, g.season, COUNT(*) AS n_providers
  FROM lines l
  JOIN games g ON g.game_id = l.game_id
  WHERE l.spread IS NOT NULL
  GROUP BY l.game_id, g.season
)
SELECT season, n_providers, COUNT(*) AS n_games
FROM per_game
GROUP BY season, n_providers
ORDER BY season, n_providers;
