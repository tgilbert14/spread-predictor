-- Teams with no logo URL. The app falls back to text, so this is cosmetic.
SELECT season, team_id, school
FROM teams
WHERE logo IS NULL OR TRIM(logo) = ''
ORDER BY season, school;
