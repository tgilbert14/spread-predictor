-- Regular-season week numbers outside 1 to 16, and postseason games not in
-- week 1 (CFBD puts the whole postseason in week 1).
SELECT game_id, season, season_type, week, start_date, home_team, away_team
FROM games
WHERE (season_type = 'regular' AND (week < 1 OR week > 16))
   OR (season_type = 'postseason' AND week <> 1)
   OR season_type NOT IN ('regular', 'postseason')
ORDER BY season, week, game_id;
