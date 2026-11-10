# Research log

Ideas that were tested by hand, outside `scripts/backtest.R`, usually because
they needed data that is not in this repo. Everything the script can
reproduce is in [backtest-results.md](backtest-results.md) instead.

Same rule every time: an idea goes into the model only if the 95% interval on
its cross-validated change lies wholly below zero and the holdout season
moves the same way. Changes are in points of average miss. Negative is
better.

## Nov 10, 2026: Girth Index features

Source: the Power-4 Girth Index project (recruiting classes from 2016 on for
the 67 Power-4 programs: listed height, weight, position and rating). Tested
on top of the final model. The features only apply to games between two
Girth Index programs: 2,322 of the 5,490 cross-validation games and 231 of
the 562 holdout games. Each feature is built from a team's last four classes
and z-scored by season.

| Feature | CV change [95% interval] | Holdout change | Verdict |
|---|---|---|---|
| Trench size gap (average listed weight of OL and DL signees) | +0.002 [-0.010, +0.014] | -0.009 | rejected |
| Defensive line size gap alone | -0.001 [-0.015, +0.012] | -0.004 | rejected |
| Offensive line size gap alone | +0.009 [+0.002, +0.016] | -0.007 | rejected |
| Blue-chip share gap | +0.007 [-0.006, +0.018] | +0.001 | rejected |
| Average recruit rating gap | +0.007 [-0.003, +0.016] | +0.004 | rejected |
| Trench size gap, early season only | -0.007 [-0.016, +0.003] | +0.010 | rejected |
| Visitor travels more than 1,000 miles | +0.003 [-0.002, +0.007] | -0.005 | rejected |
| Travel distance (log miles) | -0.009 [-0.023, +0.006] | -0.042 | rejected, worth a retest |

What this says:

- The size and rating gaps do point the right way (bigger and better-rated
  lines win by a bit more), but the ratings already know it. Blue-chip share
  and average rating overlap with the talent composite that is already in
  the model.
- Travel distance is the one to revisit. It leans the right way in both
  samples but could only be tested on Power-4 games, because that is where
  we have campus coordinates. A fair test needs venue coordinates for every
  FBS team, which is one API pull.
- The Girth Index has one roster snapshot (2026), so anything built on
  current roster size, depth or development cannot be backtested yet. If
  rosters are saved each summer, that becomes testable in a few years.

## Nov 9, 2026: points per play instead of success rate

Using per-game points added per play (PPA) in the Power rating's target, in
place of success rate. At a 50/50 mix with the score: CV +0.019
[-0.006, +0.045], holdout -0.061. It helped in 2026 but not across past
seasons. Rejected. Success rate passed the same test and is in the model.
