-- Teams with no school name. The app shows names, and ratings are matched
-- to teams by name.
SELECT season, team_id, school, mascot, conference
FROM teams
WHERE school IS NULL OR TRIM(school) = ''
ORDER BY season, team_id;
