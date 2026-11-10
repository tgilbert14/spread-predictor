-- Row counts per snapshot next to the number of FBS teams that season.
-- Extra rows mean a team is in the file twice or a non-FBS team got in.
SELECT r.source, r.season, r.week, r.is_final,
       COUNT(*) AS n_rows,
       COUNT(DISTINCT r.team_id) AS n_distinct_teams,
       (SELECT COUNT(*) FROM teams t WHERE t.season = r.season) AS n_fbs_teams
FROM ratings r
GROUP BY r.source, r.season, r.week, r.is_final
ORDER BY r.source, r.season, r.is_final, r.week;
