-- Returning production is a share of last season's output, so it belongs
-- between 0 and 1. The model pulls values outside that back into range
-- (R/fit.R), and this lists them so the size of the problem stays visible.
SELECT r.season, r.team_id, t.school, r.percent_ppa
FROM returning_production r
LEFT JOIN teams t ON t.season = r.season AND t.team_id = r.team_id
WHERE r.percent_ppa < 0 OR r.percent_ppa > 1
ORDER BY r.season, r.percent_ppa;
