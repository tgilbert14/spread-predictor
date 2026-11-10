-- Snapshots where every rating is missing, or every rating is the same.
-- Either way the file carries no information, usually a broken pull.
SELECT source, season, week, is_final,
       COUNT(*) AS n_rows,
       COUNT(rating) AS n_with_rating,
       COUNT(DISTINCT rating) AS n_distinct_values
FROM ratings
GROUP BY source, season, week, is_final
HAVING COUNT(rating) = 0 OR COUNT(DISTINCT rating) <= 1
ORDER BY source, season, week;
