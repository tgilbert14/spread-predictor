-- Success rates are shares of plays, so anything outside 0 to 1 is broken
-- data that would push the Power rating's target far off.
SELECT s.game_id, g.season, g.week, s.team_id, s.off_success_rate, s.def_success_rate
FROM game_stats s
LEFT JOIN games g ON g.game_id = s.game_id
WHERE s.off_success_rate < 0 OR s.off_success_rate > 1
   OR s.def_success_rate < 0 OR s.def_success_rate > 1
ORDER BY g.season, g.week, s.game_id;
