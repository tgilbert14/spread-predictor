-- Input for the R checks on lines: every usable spread on a completed
-- FBS-vs-FBS game, next to the final home margin.
SELECT l.game_id, l.provider, l.spread,
       g.season, g.week, g.start_date, g.neutral_site,
       g.home_team, g.away_team, g.home_points, g.away_points,
       g.home_points - g.away_points AS home_margin
FROM lines l
JOIN games g ON g.game_id = l.game_id
WHERE l.spread IS NOT NULL
  AND g.completed = 1
  AND g.home_class = 'fbs' AND g.away_class = 'fbs'
  AND g.home_points IS NOT NULL AND g.away_points IS NOT NULL
ORDER BY g.season, l.game_id, l.provider;
