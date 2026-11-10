-- Every game the Power rating learns from or rates, any division, played or
-- not. Unplayed games have NULL points: they are rated but not learned from.
-- success_margin is the home team's offensive success rate minus the
-- success rate it allowed. It is NULL when the game has no stats.
-- Parameter: the first season to include.
SELECT
  g.game_id,
  g.season,
  g.week,
  g.season_type,
  g.start_date,
  g.neutral_site,
  g.home_id,
  g.home_class,
  g.home_points,
  g.away_id,
  g.away_class,
  g.away_points,
  s.off_success_rate - s.def_success_rate AS success_margin
FROM games g
LEFT JOIN game_stats s ON s.game_id = g.game_id AND s.team_id = g.home_id
WHERE g.season >= ?
ORDER BY g.season, g.week, g.game_id;
