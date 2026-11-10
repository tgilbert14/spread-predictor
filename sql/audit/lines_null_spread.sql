-- Line rows with no spread. The pipeline skips them, so they only matter
-- if a game has nothing else.
SELECT l.game_id, l.provider, g.season, g.home_team, g.away_team
FROM lines l
LEFT JOIN games g ON g.game_id = l.game_id
WHERE l.spread IS NULL
ORDER BY g.season, l.game_id, l.provider;
