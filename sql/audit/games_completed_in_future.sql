-- Completed games that kick off after the newest pull time in the data.
-- A result cannot exist before the game is played, so the date or the
-- completed flag is wrong. ISO 8601 text sorts in time order, so plain
-- text comparison of the first 19 characters works.
WITH newest AS (
  SELECT MAX(pulled_at) AS pulled_at
  FROM (SELECT pulled_at FROM lines UNION ALL SELECT pulled_at FROM ratings) p
)
SELECT g.game_id, g.season, g.week, g.start_date, n.pulled_at AS newest_pull,
       g.home_team, g.away_team
FROM games g
CROSS JOIN newest n
WHERE g.completed = 1
  AND SUBSTR(g.start_date, 1, 19) > SUBSTR(n.pulled_at, 1, 19)
ORDER BY g.start_date;
