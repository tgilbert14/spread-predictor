-- Teams for one season. Parameter: season.
SELECT team_id, school, mascot, abbreviation, conference, color, alt_color, logo
FROM teams
WHERE season = ?
ORDER BY school;
