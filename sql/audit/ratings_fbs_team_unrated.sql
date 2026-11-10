-- FBS teams with no rating from a source, for each snapshot that source has
-- in that season. The app shows these as blank and the blend leans on the
-- other systems.
WITH snapshots AS (
  SELECT DISTINCT source, season, week, is_final FROM ratings
)
SELECT s.source, s.season, s.week, s.is_final, t.team_id, t.school
FROM snapshots s
JOIN teams t ON t.season = s.season
WHERE NOT EXISTS (
  SELECT 1 FROM ratings r
  WHERE r.source = s.source AND r.season = s.season AND r.team_id = t.team_id
    AND r.is_final = s.is_final
    AND (r.week = s.week OR (r.week IS NULL AND s.week IS NULL))
    AND r.rating IS NOT NULL
)
ORDER BY s.source, s.season, s.week, t.school;
