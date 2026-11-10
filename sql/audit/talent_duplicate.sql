-- A team with two talent values in one season. Joins would pick one of the
-- two without saying which.
SELECT season, team_id, COUNT(*) AS n_rows, MIN(talent) AS lowest, MAX(talent) AS highest
FROM talent
GROUP BY season, team_id
HAVING COUNT(*) > 1
ORDER BY season, team_id;
