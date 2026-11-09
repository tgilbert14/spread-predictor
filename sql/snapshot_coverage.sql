-- One row per weekly snapshot we hold, for the app's coverage table.
SELECT
  source,
  season,
  week,
  COUNT(*) AS n_teams,
  MAX(pulled_at) AS pulled_at
FROM ratings
WHERE is_final = 0
GROUP BY source, season, week
ORDER BY season, week, source;
