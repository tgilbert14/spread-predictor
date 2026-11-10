-- FBS teams with no talent value or no returning-production value, per
-- season. The model treats a missing value as average (a z-score of 0), so a
-- handful is fine; a whole season missing means a file was not pulled.
SELECT t.season,
       COUNT(*) AS n_fbs_teams,
       SUM(CASE WHEN ta.team_id IS NULL THEN 1 ELSE 0 END) AS n_no_talent,
       SUM(CASE WHEN r.team_id IS NULL THEN 1 ELSE 0 END) AS n_no_returning
FROM teams t
LEFT JOIN talent ta ON ta.season = t.season AND ta.team_id = t.team_id
LEFT JOIN returning_production r ON r.season = t.season AND r.team_id = t.team_id
GROUP BY t.season
ORDER BY t.season;
