-- Class values outside the set CFBD uses. A new spelling (say 'FBS' or
-- 'I-A') would silently drop games from the fit, which keeps only 'fbs'.
SELECT side, class, COUNT(*) AS n_games
FROM (
  SELECT 'home' AS side, home_class AS class FROM games
  UNION ALL
  SELECT 'away', away_class FROM games
) c
WHERE class IS NULL OR class NOT IN ('fbs', 'fcs', 'ii', 'iii')
GROUP BY side, class
ORDER BY side, class;
