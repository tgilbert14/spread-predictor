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

## Nov 11, 2026: letdown, trap and look-ahead games

The idea: a team that just pulled off a big win comes out flat the next week
(BYU beats Notre Dame, then loses to UCF), or overlooks a weak opponent
before a big one. Each spot below was added to both house models and judged
by the usual rule. "Top 25" and "top 50" use our own pregame Power rating,
so nothing here peeks at later results.

| Spot the team is in | Games | Result vs our line | CV change in MAE [95% interval] | Holdout change | Verdict |
|---|---|---|---|---|---|
| Last week: won as an underdog of 7 or more | 415 | 1.1 worse | +0.000 [-0.009, +0.008] | -0.003 | rejected |
| Last week: beat a top-25 team | 513 | 0.8 worse | -0.000 [-0.007, +0.007] | -0.015 | rejected |
| Last week: beat the market line by 14 or more | 1,571 | 0.5 better | +0.002 [-0.004, +0.009] | +0.004 | rejected |
| Look-ahead: top-25 team next week, opponent outside the top 50 now | 724 | 0.3 better | +0.000 [-0.003, +0.004] | +0.008 | rejected |
| Sandwich: beat a top-25 team, now facing a team outside the top 50 | 224 | 0.5 worse | +0.001 [-0.002, +0.005] | -0.005 | rejected |
| Last week: lost as a favorite of 7 or more | 461 | 1.3 better | +0.001 [-0.009, +0.011] | -0.017 | rejected |
| Upset win and upset loss as one term | 848 | 1.2 worse after a win | -0.001 [-0.013, +0.011] | -0.019 | rejected |

"Result vs our line" is how many points the team in that spot did better or
worse than we predicted, on average, in the fit seasons.

What this says:

- There is a small lean in the direction people expect. Teams coming off an
  upset win play about a point worse than predicted, and teams coming off an
  upset loss about a point better. The market misses by about the same
  amount, so it is not pricing this in either.
- It is too small and too noisy to use. One point against a typical miss of
  16, in about one game in ten, moves the average error by a thousandth of a
  point. The combined term is the only one with a t-statistic past 2, and it
  is one of seven things tried, so it could easily be luck.
- It reads more like ratings overreacting to one surprising result than like
  a team being flat. Either way the fix would be the same term, and it does
  not pass.
- Look-ahead and sandwich spots show nothing at all.

The test script is not in the repo. It builds each flag from the previous
and next game per team and calls `judge_candidate()` from `R/backtest.R`.

## Nov 11, 2026: re-scaling the field by season, opponent tiers, and rating drift

Three ideas, all judged by the usual rule on the same games.

**1. Is the field more even some years, so the scale should change?**

| Season | Spread of team ratings (SD, points) | Top 10 vs teams 11 to 25 | Best-fit scale on our spreads | Our MAE | Market MAE |
|---|---|---|---|---|---|
| 2018 | 10.2 | 9.0 | 1.03 | 12.86 | 12.62 |
| 2019 | 11.4 | 11.2 | 1.12 | 12.72 | 12.16 |
| 2021 | 10.1 | 7.1 | 1.03 | 13.15 | 12.54 |
| 2022 | 10.5 | 8.5 | 0.96 | 12.28 | 12.02 |
| 2023 | 9.9 | 7.7 | 1.02 | 12.49 | 12.12 |
| 2024 | 11.2 | 7.5 | 1.02 | 12.53 | 12.07 |
| 2025 | 11.8 | 7.8 | 1.03 | 12.29 | 11.81 |
| 2026 | 11.5 | 7.7 | 0.97 | 12.09 | 11.55 |

The field does change. The top 10 was 9 to 11 points clear of the next 15
teams in 2018 and 2019, and has been 7 to 8.5 points clear every year since
2021. But the ratings are in points, so they already carry that: a flatter
top shows up as smaller rating gaps. The scale that turns a rating gap into
a spread stays within a few percent of 1 every year except 2019.

| Candidate | CV change in MAE [95% interval] | Holdout change | Verdict |
|---|---|---|---|
| Different scale since 2021 | -0.008 [-0.022, +0.005] | -0.007 | rejected |
| Scale drifts year to year | -0.008 [-0.019, +0.003] | -0.010 | rejected |
| Scale re-fit as each season goes (light) | -0.007 [-0.017, +0.002] | +0.028 | rejected |
| Scale re-fit as each season goes (heavy) | -0.010 [-0.025, +0.004] | +0.086 | rejected |
| Different scale late in the season | +0.001 [-0.014, +0.016] | -0.007 | rejected |

Our spreads are also well calibrated at every size: games we call by 14 to
21 are won by 17.9 on average against a predicted 17.1, and games we call
by 28 or more by 35.4 against 34.7.

**2. Should results against strong opponents count differently?**

| Candidate | CV change in MAE [95% interval] | Holdout change | Verdict |
|---|---|---|---|
| Different scale when two top-25 teams meet | +0.001 [-0.006, +0.008] | +0.005 | rejected |
| How a team has done against top-25 opponents this season | -0.003 [-0.017, +0.009] | -0.020 | rejected |
| How a team has done against our line this season, all games | -0.019 [-0.050, +0.013] | -0.037 | rejected |

The last row is the nearest miss. Added to only one of the two house models
it passes (Elo only: -0.020 [-0.037, -0.002], holdout -0.031; Power only:
-0.018 [-0.032, -0.003], holdout -0.022). Added to both, the gain is the
same and the interval is wider. It says the ratings are a little slow to
believe a team that keeps beating expectations. The gain is about 0.02
points per game. Not added: it is tiny, it passed only in some of twelve
versions tried, and it would add a running residual to the pipeline. Worth
a retest at the December refit.

**3. Rating when they played versus rating now**

The Power rating already does this. Each week it re-solves the whole season
at once, so an early win over a team that later collapsed is marked down
automatically. Elo does not: it locks in the opponent's rating on game day.
Adding "how much have a team's past opponents' Elo moved since" changed
nothing (CV +0.002 [-0.001, +0.004], holdout +0.001), with or without Power
in the mix. Rejected.

## Nov 11, 2026: how close is the market, and should we blend it in?

The market here is the closing line, the median across sportsbooks. Our
number is the house blend (Elo and Power), out of sample. 5,490 games in
the fit seasons, 562 in 2026.

| | Fit seasons | 2026 |
|---|---|---|
| Our average miss | 12.61 | 12.09 |
| Market's average miss | 12.19 | 11.55 |
| We pick the winner | 72.4% | 73.0% |
| Market picks the winner | 73.1% | 75.6% |

Our line and the market's are 3.1 points apart on average (correlation
0.96). They are within 3 points in 58% of games and 7 or more apart in 7%.

When we disagree, the market is usually right:

| We differ by at least | Games | Our miss | Market's miss | Result on our side of the market line |
|---|---|---|---|---|
| 3 | 2,512 | 13.10 | 12.18 | 49.1% |
| 5 | 1,139 | 14.04 | 12.42 | 47.6% |
| 7 | 446 | 15.15 | 12.88 | 48.4% |
| 10 | 99 | 16.80 | 12.34 | 42.9% |

The last column is a coin flip at every size. The model does not find
games where the market is wrong.

Blending the two: the best mix is 98% market and 2% ours, and the 2% is
noise (it makes the market slightly worse out of sample: CV +0.006
[+0.001, +0.010]). Once you have the closing line, our number adds nothing
to it.

Decision: the market stays out of the blend. Putting it in would turn our
number into the market's number with extra steps. It stays what it is now:
the benchmark on the Scorecard, and a flag in the app. A large gap between
us and the market should be read as "the market likely knows something we
do not", not as an edge.

## Nov 11, 2026: are the public ratings on a points scale?

SP+, FPI and SRS go into the blend point for point: a 10-point rating gap
counts as a 10-point spread. Elo and Power are different. Their scales are
fitted. The three public ones cannot be fitted against results, because
their past ratings already include the results. They can be checked against
the closing line, which was set before the game.

Test: for late-season games (week 11 on, plus bowls) in 2018, 2019 and 2021
to 2025, regress the closing line on each system's season-final rating gap
plus a home term. 1,816 games. The slope is how much of the rating gap the
market uses.

| System | Scale the market uses [95% interval] | By season, 2018 to 2025 | Home field implied |
|---|---|---|---|
| SP+ | 0.79 [0.78, 0.81] | 0.83, 0.88, 0.82, 0.76, 0.76, 0.74, 0.75 | 2.6 |
| FPI | 0.95 [0.94, 0.97] | 0.97, 0.99, 0.96, 0.98, 0.87, 0.93, 0.93 | 2.5 |
| SRS | 0.94 [0.92, 0.96] | 0.88, 0.92, 1.00, 1.05, 0.92, 0.96, 0.92 | 2.6 |

SP+ is stretched: its ratings spread teams out about 25% more than a point
spread does, every season. FPI and SRS are close to point for point. The
home field the market implies (2.5 to 2.6) matches ours (2.5).

Season-final ratings are a slightly noisy stand-in for the ratings on game
day, which pulls these slopes down a little. FPI and SRS landing near 0.95
says that effect is small, so most of SP+'s 0.79 is real.

This week's saved predictions agree. Across the 67 week 11 games, the slope
of the market line on each system's margin is 0.69 for SP+, 0.86 for FPI,
0.83 for SRS, 0.84 for Elo and 0.95 for Power. SP+ is the furthest from the
market of the five (4.1 points a game, against 2.2 for FPI and Power).

What it would do: with SP+ at 0.79, FPI at 0.95 and SRS at 0.94 (numbers
from past seasons, not from this week), the blend's average distance from
the market this week drops from 2.08 points to 1.70, and the share of games
where we differ by 3 or more drops from 27% to 19%.

Status: in the model as of Nov 11, 2026. `fit_public_scales()` in `R/fit.R`
estimates the three scales this way at every fit, `data/params.json` stores
them as `public_scale`, and `rating_margins()` applies them. Week 11
predictions were saved before the change and stay as they were, so the
Scorecard grades the scaled version from week 12 on.
