-- Sportsbook spreads for one season and week. Parameters: season, week.
SELECT l.game_id, l.spread
FROM lines AS l
JOIN games AS g ON g.game_id = l.game_id
WHERE g.season = ?
  AND g.week = ?
  AND l.spread IS NOT NULL;
