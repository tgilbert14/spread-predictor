-- A team listed in two different games on one date (UTC).
WITH appearances AS (
  SELECT game_id, season, SUBSTR(start_date, 1, 10) AS game_date, home_id AS team_id, home_team AS team FROM games
  UNION ALL
  SELECT game_id, season, SUBSTR(start_date, 1, 10), away_id, away_team FROM games
)
SELECT a.season, a.game_date, a.team_id, a.team, a.game_id, b.game_id AS other_game_id
FROM appearances a
JOIN appearances b
  ON a.team_id = b.team_id
 AND a.game_date = b.game_date
 AND a.game_id < b.game_id
ORDER BY a.game_date, a.team;
