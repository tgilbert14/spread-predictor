-- Every game's result, for grading saved predictions. Unplayed games have
-- completed = 0 and no points.
SELECT game_id, completed, home_points, away_points
FROM games;
