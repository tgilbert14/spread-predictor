-- The same two teams listed as meeting twice on one date (UTC), under
-- different game ids. Usually one game stored twice.
-- Teams are put in a fixed order (lower id first) so home and away swapped
-- still counts as the same matchup.
WITH matchups AS (
  SELECT game_id,
         SUBSTR(start_date, 1, 10) AS game_date,
         CASE WHEN home_id < away_id THEN home_id ELSE away_id END AS team_1,
         CASE WHEN home_id < away_id THEN away_id ELSE home_id END AS team_2,
         home_team, away_team
  FROM games
)
SELECT a.game_id, b.game_id AS other_game_id, a.game_date, a.home_team, a.away_team
FROM matchups a
JOIN matchups b
  ON a.team_1 = b.team_1
 AND a.team_2 = b.team_2
 AND a.game_date = b.game_date
 AND a.game_id < b.game_id
ORDER BY a.game_date, a.game_id;
