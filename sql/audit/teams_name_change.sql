-- A team_id whose school name differs from the season before. Ratings are
-- matched by name, so a rename can quietly break that match.
SELECT cur.team_id, prev.season AS from_season, prev.school AS from_school,
       cur.season AS to_season, cur.school AS to_school
FROM teams cur
JOIN teams prev ON prev.team_id = cur.team_id AND prev.season = cur.season - 1
WHERE prev.school <> cur.school
ORDER BY cur.season, cur.team_id;
