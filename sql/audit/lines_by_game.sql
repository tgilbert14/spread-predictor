-- Input for the flipped-sign check, which is done in R: every usable
-- spread, with the game it belongs to when that game is in games.
SELECT l.game_id, l.provider, l.spread,
       g.season, g.season_type, g.week, g.neutral_site, g.completed,
       g.home_team, g.away_team, g.home_points, g.away_points
FROM lines l
JOIN games g ON g.game_id = l.game_id
WHERE l.spread IS NOT NULL
ORDER BY l.game_id, l.provider;
