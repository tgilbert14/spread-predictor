-- Game ids that appear more than once. Every other table joins on game_id,
-- so a repeat would double count that game.
SELECT game_id, COUNT(*) AS n_rows
FROM games
GROUP BY game_id
HAVING COUNT(*) > 1
ORDER BY game_id;
