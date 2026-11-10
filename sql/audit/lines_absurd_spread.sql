-- Spreads bigger than 70 points either way. The biggest real college lines
-- are in the 60s, so anything past 70 is almost surely a typo or a total.
SELECT l.game_id, l.provider, l.spread, g.season, g.home_team, g.away_team
FROM lines l
LEFT JOIN games g ON g.game_id = l.game_id
WHERE l.spread > 70 OR l.spread < -70
ORDER BY l.game_id, l.provider;
