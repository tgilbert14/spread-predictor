-- Ratings outside a sane range for their system: -45 to 45 points for
-- SP+, FPI and SRS, and 500 to 2600 for Elo.
SELECT source, season, week, team_id, team, rating
FROM ratings
WHERE (source IN ('sp', 'fpi', 'srs') AND (rating < -45 OR rating > 45))
   OR (source = 'elo' AND (rating < 500 OR rating > 2600))
   OR source NOT IN ('sp', 'fpi', 'srs', 'elo')
ORDER BY source, season, week, rating;
