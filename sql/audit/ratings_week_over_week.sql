-- Large one-week changes in a team's rating: over 15 points for SP+, FPI
-- and SRS, or over 250 for Elo. Compares each weekly snapshot with the
-- previous weekly snapshot of the same source and season. Finds nothing
-- until a season has at least two weekly snapshots.
WITH weekly AS (
  SELECT source, season, week, team_id, team, rating
  FROM ratings
  WHERE is_final = 0 AND week IS NOT NULL AND rating IS NOT NULL
),
pairs AS (
  SELECT cur.source, cur.season, cur.week, cur.team_id, cur.team,
         prev.week AS previous_week,
         prev.rating AS previous_rating,
         cur.rating AS rating,
         cur.rating - prev.rating AS change
  FROM weekly cur
  JOIN weekly prev
    ON prev.source = cur.source
   AND prev.season = cur.season
   AND prev.team_id = cur.team_id
   AND prev.week = (
     SELECT MAX(w.week) FROM weekly w
     WHERE w.source = cur.source AND w.season = cur.season AND w.week < cur.week
   )
)
SELECT source, season, previous_week, week, team_id, team, previous_rating, rating, change
FROM pairs
WHERE (source = 'elo' AND ABS(change) > 250)
   OR (source <> 'elo' AND ABS(change) > 15)
ORDER BY ABS(change) DESC;
