-- Weekly snapshot ratings: what each system said before that week's games.
SELECT source, season, week, team_id, rating
FROM ratings
WHERE is_final = 0
  AND rating IS NOT NULL;
