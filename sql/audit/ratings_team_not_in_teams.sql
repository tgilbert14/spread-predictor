-- Rating rows whose team_id is not in that season's teams table. Ratings are
-- matched to team ids by name, so this means a name matched the wrong year
-- or the teams file is missing a team.
SELECT r.source, r.season, r.week, r.team_id, r.team, r.rating
FROM ratings r
WHERE NOT EXISTS (SELECT 1 FROM teams t WHERE t.season = r.season AND t.team_id = r.team_id)
ORDER BY r.source, r.season, r.team;
