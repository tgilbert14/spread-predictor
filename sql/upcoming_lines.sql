-- Sportsbook spreads for one season's games that have not been played yet,
-- so games beyond this week's slate can show the market line too.
-- Parameters: season.
SELECT l.game_id, l.spread
FROM lines AS l
JOIN games AS g ON g.game_id = l.game_id
WHERE g.season = ?
  AND g.season_type = 'regular'
  AND g.completed = 0
  AND l.spread IS NOT NULL;
