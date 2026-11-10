-- Teams marked 'fbs' in a game but missing from that season's teams table.
-- The app and the ratings both key on the teams table, so these teams would
-- have no name, colors or ratings.
SELECT g.season, g.game_id, 'home' AS side, g.home_id AS team_id, g.home_team AS team
FROM games g
WHERE g.home_class = 'fbs'
  AND NOT EXISTS (SELECT 1 FROM teams t WHERE t.season = g.season AND t.team_id = g.home_id)
UNION ALL
SELECT g.season, g.game_id, 'away', g.away_id, g.away_team
FROM games g
WHERE g.away_class = 'fbs'
  AND NOT EXISTS (SELECT 1 FROM teams t WHERE t.season = g.season AND t.team_id = g.away_id)
ORDER BY 1, 2;
