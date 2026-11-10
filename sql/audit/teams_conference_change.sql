-- Teams whose conference differs from the season before. Real realignment,
-- listed so a surprise stands out.
SELECT cur.team_id, cur.school, prev.season AS from_season, prev.conference AS from_conference,
       cur.season AS to_season, cur.conference AS to_conference
FROM teams cur
JOIN teams prev ON prev.team_id = cur.team_id AND prev.season = cur.season - 1
WHERE COALESCE(prev.conference, '') <> COALESCE(cur.conference, '')
ORDER BY cur.season, cur.school;
