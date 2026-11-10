-- Games where sportsbooks disagree by more than 7 points. Books rarely sit
-- more than a point or two apart, so a wide gap usually means one provider
-- has home and away flipped or posted an early, stale number.
SELECT l.game_id, g.season, g.season_type, g.week, g.neutral_site, g.home_team, g.away_team,
       COUNT(*) AS n_providers,
       MIN(l.spread) AS lowest_spread,
       MAX(l.spread) AS highest_spread,
       MAX(l.spread) - MIN(l.spread) AS gap
FROM lines l
JOIN games g ON g.game_id = l.game_id
WHERE l.spread IS NOT NULL
GROUP BY l.game_id, g.season, g.season_type, g.week, g.neutral_site, g.home_team, g.away_team
HAVING MAX(l.spread) - MIN(l.spread) > 7
ORDER BY gap DESC, l.game_id;
