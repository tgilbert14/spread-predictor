-- Lines for a game_id that is not in games. Harmless to the fit (it joins
-- on games) but points to a games file that is missing games.
SELECT l.game_id, COUNT(*) AS n_providers, MIN(l.pulled_at) AS pulled_at
FROM lines l
WHERE NOT EXISTS (SELECT 1 FROM games g WHERE g.game_id = l.game_id)
GROUP BY l.game_id
ORDER BY l.game_id;
