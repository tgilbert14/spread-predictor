-- Pregame Elo outside 500 to 2600. Real values sit around 700 to 2400.
SELECT game_id, season, week, home_team, home_pregame_elo, away_team, away_pregame_elo
FROM games
WHERE home_pregame_elo < 500 OR home_pregame_elo > 2600
   OR away_pregame_elo < 500 OR away_pregame_elo > 2600
ORDER BY season, week, game_id;
