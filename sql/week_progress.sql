-- How far along each regular-season week of one season is: its games, how
-- many are finished, and the latest kickoff among those that are not.
-- Used to tell which week's results are all in.
-- Parameter: season.
SELECT
  week,
  COUNT(*) AS games,
  SUM(completed) AS completed,
  MAX(CASE WHEN completed = 0 THEN start_date END) AS last_open_kickoff
FROM games
WHERE season = ?
  AND season_type = 'regular'
GROUP BY week
ORDER BY week;
