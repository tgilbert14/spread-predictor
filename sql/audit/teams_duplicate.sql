-- A team listed twice in one season.
SELECT season, team_id, MIN(school) AS school, COUNT(*) AS n_rows
FROM teams
GROUP BY season, team_id
HAVING COUNT(*) > 1
ORDER BY season, team_id;
