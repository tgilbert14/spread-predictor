-- Every game the Power rating learns from or rates, any division, played or
-- not. Unplayed games have NULL points: they are rated but not learned from.
-- Parameter: the first season to include.
SELECT
  game_id,
  season,
  week,
  season_type,
  start_date,
  neutral_site,
  home_id,
  home_class,
  home_points,
  away_id,
  away_class,
  away_points
FROM games
WHERE season >= ?
ORDER BY season, week, game_id;
