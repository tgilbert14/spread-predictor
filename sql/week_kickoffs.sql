-- Kickoff time of every regular-season game in one season and week, played
-- or not. Used to refuse saving predictions once any of them has started.
-- Parameters: season, week.
SELECT game_id, start_date, completed
FROM games
WHERE season = ?
  AND week = ?
  AND season_type = 'regular';
