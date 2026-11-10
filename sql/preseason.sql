-- Each season's FBS teams with their preseason inputs: roster talent and the
-- share of last season's production returning. NULL when there is no value.
SELECT
  t.season,
  t.team_id,
  ta.talent,
  r.percent_ppa
FROM teams t
LEFT JOIN talent ta ON ta.season = t.season AND ta.team_id = t.team_id
LEFT JOIN returning_production r ON r.season = t.season AND r.team_id = t.team_id
ORDER BY t.season, t.team_id;
