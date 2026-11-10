-- Completed FBS-vs-FBS games with no usable line, counted per season. These
-- games cannot be scored against the market.
WITH fit_games AS (
  SELECT g.game_id, g.season,
         CASE WHEN EXISTS (
           SELECT 1 FROM lines l WHERE l.game_id = g.game_id AND l.spread IS NOT NULL
         ) THEN 0 ELSE 1 END AS no_line
  FROM games g
  WHERE g.completed = 1 AND g.home_class = 'fbs' AND g.away_class = 'fbs'
)
SELECT season, SUM(no_line) AS n_without_line, COUNT(*) AS n_fbs_games
FROM fit_games
GROUP BY season
HAVING SUM(no_line) > 0
ORDER BY season;
