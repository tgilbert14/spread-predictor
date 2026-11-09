-- Season-final ratings. These already include every result, so they are
-- only used for the leaked diagnostic, never for fitting.
SELECT source, season, team_id, rating
FROM ratings
WHERE is_final = 1
  AND rating IS NOT NULL;
