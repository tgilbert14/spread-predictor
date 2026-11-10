-- Seasons where more than 3% of completed FBS-vs-FBS games have no stats
-- for the home team. Those games fall back to the plain score in the Power
-- rating, which is fine now and then but not for a big share of a season.
WITH fbs_games AS (
  SELECT g.game_id, g.season,
         CASE WHEN EXISTS (
           SELECT 1 FROM game_stats s WHERE s.game_id = g.game_id AND s.team_id = g.home_id
         ) THEN 0 ELSE 1 END AS no_stats
  FROM games g
  WHERE g.completed = 1 AND g.home_class = 'fbs' AND g.away_class = 'fbs'
)
SELECT season, SUM(no_stats) AS n_without_stats, COUNT(*) AS n_fbs_games,
       ROUND(100.0 * SUM(no_stats) / COUNT(*), 1) AS pct_without_stats
FROM fbs_games
GROUP BY season
HAVING 100.0 * SUM(no_stats) / COUNT(*) > 3
ORDER BY season;
