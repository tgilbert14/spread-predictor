-- Neutral-site games per season and season type. Nothing to fix; a sudden
-- jump or drop would point to a change in how the flag is filled.
SELECT season, season_type, SUM(neutral_site) AS n_neutral, COUNT(*) AS n_games
FROM games
GROUP BY season, season_type
ORDER BY season, season_type;
