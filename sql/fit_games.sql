-- Completed FBS-vs-FBS games with a final score and each team's conference.
-- The season and pregame Elo filters are applied in R (R/fit.R), so these
-- same rows also feed the blend-weight fit, which does not need Elo.
SELECT
  g.game_id,
  g.season,
  g.week,
  g.season_type,
  g.start_date,
  g.neutral_site,
  g.home_id,
  g.away_id,
  ht.conference AS home_conference,
  at.conference AS away_conference,
  g.home_pregame_elo,
  g.away_pregame_elo,
  g.home_points - g.away_points AS home_margin
FROM games g
LEFT JOIN teams ht ON ht.season = g.season AND ht.team_id = g.home_id
LEFT JOIN teams at ON at.season = g.season AND at.team_id = g.away_id
WHERE g.completed = 1
  AND g.home_class = 'fbs'
  AND g.away_class = 'fbs'
  AND g.home_points IS NOT NULL
  AND g.away_points IS NOT NULL
ORDER BY g.season, g.week, g.game_id;
