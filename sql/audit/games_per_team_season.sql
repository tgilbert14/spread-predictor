-- FBS teams with an implausible number of completed games in a finished
-- season: under 8 or over 16 (12 regular season, a title game and up to
-- four playoff games is the real maximum at 17, so over 16 is worth a look).
-- Only seasons before the newest one count as finished.
WITH appearances AS (
  SELECT season, home_id AS team_id FROM games WHERE completed = 1
  UNION ALL
  SELECT season, away_id FROM games WHERE completed = 1
),
finished AS (
  SELECT DISTINCT season FROM games
  WHERE season < (SELECT MAX(season) FROM games)
)
SELECT t.season, t.team_id, t.school, COUNT(a.team_id) AS n_games
FROM teams t
JOIN finished f ON f.season = t.season
LEFT JOIN appearances a ON a.season = t.season AND a.team_id = t.team_id
GROUP BY t.season, t.team_id, t.school
HAVING COUNT(a.team_id) < 8 OR COUNT(a.team_id) > 16
ORDER BY t.season, t.school;
