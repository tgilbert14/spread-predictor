-- Teams that are in that season's (FBS) teams table but are marked as some
-- other class in a game. Such games are left out of the fit. Most likely
-- during a move up from FCS.
SELECT g.season, g.game_id, 'home' AS side, g.home_team AS team, g.home_class AS class
FROM games g
JOIN teams t ON t.season = g.season AND t.team_id = g.home_id
WHERE g.home_class IS NULL OR g.home_class <> 'fbs'
UNION ALL
SELECT g.season, g.game_id, 'away', g.away_team, g.away_class
FROM games g
JOIN teams t ON t.season = g.season AND t.team_id = g.away_id
WHERE g.away_class IS NULL OR g.away_class <> 'fbs'
ORDER BY 1, 2;
