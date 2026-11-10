-- A game whose home and away team are the same team.
SELECT game_id, season, week, home_id, home_team, away_id, away_team
FROM games
WHERE home_id = away_id
ORDER BY season, week, game_id;
