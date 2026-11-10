-- A team with two returning-production values in one season. Joins would
-- pick one of the two without saying which.
SELECT season, team_id, COUNT(*) AS n_rows, MIN(percent_ppa) AS lowest, MAX(percent_ppa) AS highest
FROM returning_production
GROUP BY season, team_id
HAVING COUNT(*) > 1
ORDER BY season, team_id;
