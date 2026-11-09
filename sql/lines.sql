-- Every sportsbook spread. The median per game (the closing line) is taken
-- in R, because MEDIAN is not portable SQL.
SELECT game_id, spread
FROM lines
WHERE spread IS NOT NULL;
