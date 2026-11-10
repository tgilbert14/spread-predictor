-- A team rated twice in one snapshot. Joins pick one of the two values
-- without saying which, so the rating used is a coin flip.
SELECT source, season, week, is_final, team_id, MIN(team) AS team,
       COUNT(*) AS n_rows, MIN(rating) AS lowest, MAX(rating) AS highest
FROM ratings
GROUP BY source, season, week, is_final, team_id
HAVING COUNT(*) > 1
ORDER BY source, season, week, team_id;
