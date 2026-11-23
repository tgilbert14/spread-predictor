-- Regular-season games in one season that have not been played yet, for
-- showing each team's next game. Team names are kept because an opponent
-- from a lower division is not in the teams table.
-- Parameters: season.
SELECT game_id, week, start_date, home_id, away_id, home_team, away_team, neutral_site
FROM games
WHERE season = ?
  AND season_type = 'regular'
  AND completed = 0
ORDER BY week, start_date, game_id;
