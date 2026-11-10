-- A team with two rows of stats for one game. The Power rating would learn
-- from whichever the join picked.
SELECT game_id, team_id, COUNT(*) AS n_rows
FROM game_stats
GROUP BY game_id, team_id
HAVING COUNT(*) > 1
ORDER BY game_id, team_id;
