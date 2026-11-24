# Research log

Ideas that were tested outside `scripts/backtest.R`, and what happened.
The standing candidates that script re-judges on every run are in
[backtest-results.md](backtest-results.md) instead.

Most entries can be rerun from `scripts/research/`:

| Script | Entries it reproduces |
|---|---|
| `scripts/research/spots.R` | Letdown, trap and look-ahead games |
| `scripts/research/scaling.R` | Re-scaling the field by season, opponent tiers, and rating drift |
| `scripts/research/market_blend.R` | How close the market is, and whether to blend it in |
| `scripts/research/travel.R` | Travel, time zones and altitude |
| `scripts/disagreement.R` | Which side covers when a model and the sportsbooks disagree |

The Girth Index and points-per-play entries used data from outside this
repo and have no script here. The public-ratings scale check became part
of the fit (`fit_public_scales()` in `R/fit.R`).

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

Rerun it with `Rscript scripts/research/spots.R`.

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

## Nov 11, 2026: travel, time zones and altitude, all of FBS

The earlier travel test only had coordinates for Power-4 programs. This one
uses every FBS team's home stadium (`data/snapshots/extras/locations/`),
6,052 games. Distance is stadium to stadium for true home games. Neutral
sites count as no travel edge, since neither stadium is the venue.

| Candidate | Games it applies to | Fitted size (points to the home team) | CV change in MAE [95% interval] | Holdout change | Verdict |
|---|---|---|---|---|---|
| Travel distance (log miles) | all home games | +0.6 per log-mile | -0.007 [-0.022, +0.008] | -0.037 | rejected |
| Visitor travels more than 1,000 miles | 882 | +0.9 | +0.002 [-0.007, +0.011] | -0.019 | rejected |
| Visitor travels more than 1,500 miles | 419 | +0.9 | +0.002 [-0.004, +0.009] | -0.010 | rejected |
| Visitor travels under 150 miles | 713 | -1.3 | +0.001 [-0.012, +0.014] | -0.018 | rejected |
| Time zones crossed | all home games | +0.5 per zone | -0.008 [-0.020, +0.004] | -0.015 | rejected |
| Visitor travels east 2 or more zones | 272 | +0.1 | +0.002 [-0.000, +0.004] | -0.002 | rejected |
| Visitor travels west 2 or more zones | 258 | +3.5 | -0.011 [-0.028, +0.007] | +0.040 | rejected |
| Low-elevation visitor at a high-elevation home | 199 | +2.7 | -0.003 [-0.016, +0.010] | -0.046 | rejected |

Every sign points the way you would expect: long trips cost the visitor
about a point, short ones give back about a point of home field, altitude
is worth a couple. None of it changes the average error by more than a
hundredth of a point, because each applies to a small share of games and
the effect is small next to a typical miss of 16. The "west 2 or more
zones" row is mostly trips to Hawaii and the Pacific coast, and it made
2026 worse. Rejected, and closed unless new data turns up.

## Nov 11, 2026: when a model and the sportsbooks disagree, which side covers?

Full tables are in `docs/market-disagreement.md`, written by
`scripts/disagreement.R`. Sportsbook opening lines came from a new
research pull (`data/snapshots/extras/lines_full/`).

What it says:

- **Against the closing line, it is a coin flip.** When our testable model
  (Elo and Power) and the closing line were 3 or more points apart, the
  sportsbook's side covered 50.9% of the time over 2,512 games (95%
  interval 48.9% to 52.8%). At 2, 4 and 5 points it is 51.1%, 51.2% and
  52.4%. Neither side reaches the 52.4% needed to break even at -110 in
  any reliable way. Elo alone and Power alone look the same.
- **It does not depend on the book.** DraftKings, Bovada and ESPN Bet
  closing lines all give 50% to 53% for the sportsbook's side.
- **Against the opening line the model does a little better, but not
  enough.** There the model's side covered 50.5% to 52% (1,785 games at 3
  or more, since 2021). Still short of break-even.
- **The line does move toward the model.** When the model and the opening
  line were 3 or more apart, 61% of the lines that moved went the model's
  way, by half a point on average, and more at bigger gaps. So the model
  sees something real that the opener has not priced, and the market has
  mostly priced it by kickoff.
- **No slice stands out.** Early season, late season, favorites, underdogs,
  home, away, and Elo and Power agreeing with each other all sit between
  50% and 52%. Single seasons swing from 47% to 55%, which is what chance
  looks like at 300 games.
- **SP+, FPI, SRS and the five-system blend cannot be tested on history.**
  They are graded from the weekly saved predictions, and section 7 of the
  file fills in as those games are played.

This matches the earlier finding that the best mix of our number and the
closing line is 98% line. It is a record of past results, not betting
advice.

## Nov 21, 2026: what does the playoff committee reward?

**Question.** Our rankings say who would win. The committee ranks who has
earned the most. Which of our numbers is closest to the committee, and can
a ranking built only from results reproduce its list?

**Data.** Every committee release from 2018 to 2025 except 2020: 41
releases, 1,025 ranked team-weeks. For each one, every FBS team's resume
going into that week, from regular-season games already played and the
Power rating as it stood then. No bowl results, since the committee never
sees them. Script: `scripts/research/committee.R`.

**How close is each ranking to the committee?** Average places off across
the committee's 25 teams, and how many of its top 12 the ranking shares.

| Ranking | Places off | Top 12 shared |
|---|---|---|
| AP poll, same week | 1.27 | 11.5 |
| Record strength alone | 3.76 | 10.3 |
| Fewest losses, then Power | 5.20 | 9.6 |
| Power rating (who would win) | 8.73 | 8.9 |

Record strength is wins minus what a reference team, about the 10th best
in the country, would be expected to win against the same schedule at the
same sites.

**Fitting a score to the committee.** A score is a weighted sum of resume
inputs. The weights were fit so that, across every pair of teams the
committee put in order, the higher-ranked team tends to get the higher
score. Each season was scored with weights fit on the other six.

| Inputs | Places off | Top 12 shared |
|---|---|---|
| Record strength + Power | 3.40 | 10.5 |
| + losses | 3.29 | 10.7 |
| + power-conference flag | 2.73 | 11.0 |
| + average opponent and top-25 wins | 2.70 | 10.9 |
| + wins | 2.64 | 11.0 |

**What it says.**

- **The committee ranks results, not strength.** Our Power rating alone is
  8.7 places off. Record strength alone is 3.8.
- **It still gives some credit for being good.** Adding Power to record
  strength helps, so a team that looks strong sits a little higher than
  its results alone would put it.
- **Losses count on their own**, beyond what they do to record strength.
- **Power-conference teams get a bonus.** The flag is the biggest single
  step after the basics. It is worth about two losses.
- **More inputs barely help.** Average opponent strength, top-25 wins and
  win count together move the answer by 0.1. The four-input score is the
  one in the app.
- **It holds up season by season**: 2.1 to 3.6 places off in each left-out
  season, and 10.8 to 11.3 of the top 12.
- **On 2026, which no fit has seen,** it is 2.5 places off in each of the
  three releases so far, and has 22 of the committee's 25 teams.

**What it cannot see.** Head-to-head results, conference titles, injuries
and anything said in the room. The AP poll is closer than any formula here
because voters see those things too.

**Decision.** Two rankings came out of this.

- "Our CFP guess": the four-input score, shown next to the committee's and
  the AP's ranks. It predicts the committee, bonus and all.
- "Who has earned it": record strength alone. It is our own answer to who
  deserves what, so it deliberately leaves out the two things the fit says
  the committee adds on top of results: credit for looking strong and the
  power-conference bonus. It is 3.8 places from the committee on history,
  and that gap is the point, not a flaw.

Both are kept apart from the who-would-win ranking. The weights live in `COMMITTEE_MODEL` in
`R/config.R` and should be refit with the script after each season.

## Nov 22, 2026: predicting the committee week to week

**Question.** The four-input score explains the committee's order from
results alone. What else does the committee use? It says it weighs
head-to-head results and quality wins. And does knowing its previous
ranking help predict the next one?

**Data.** The same 41 releases as before. Script:
`scripts/research/committee_extras.R`. Everything is scored on seasons left
out of the fit.

**Things the committee says it values, added to the four inputs.**

| Added input | Places off | Top 12 shared |
|---|---|---|
| None (the four inputs) | 2.73 | 11.0 |
| Best win and worst loss | 2.64 | 11.0 |
| Top-10 wins and bad losses | 2.69 | 11.0 |
| Losses in the last three weeks | 2.70 | 11.0 |
| Head-to-head | 2.67 | 11.0 |

None of them matters much. Head-to-head does get a clear positive weight
in the fit, so the committee does respect it, but it only decides a few
close pairs a year. Record strength already carries most of what "quality
wins" and "bad losses" say.

**The committee's own last ranking.** On the 34 releases after a season's
first:

| Prediction | Places off | Top 12 shared | Same No. 1 |
|---|---|---|---|
| The four inputs | 2.71 | 11.0 | 68% |
| Last week's ranking, unchanged | 1.90 | 11.0 | 76% |
| Four inputs + last week's rank | 1.97 | 11.3 | 71% |
| + new losses and record strength gained | 1.33 | 11.4 | 82% |
| + head-to-head | 1.31 | 11.5 | 82% |
| AP poll, same week | 1.21 | 11.6 | 94% |

**What it says.**

- **The committee anchors on itself.** Last week's ranking, left alone,
  beats any score built from results. Its heaviest input by far is where
  it had a team seven days ago.
- **It then reacts to the week.** A new loss drops a team. A win moves a
  team up in proportion to how hard the win was. Adding those two cuts the
  error from 1.9 to 1.3 places.
- **That gets within a tenth of a place of the AP poll**, with no human
  input at all.
- **Head-to-head adds 0.02 places.** Not worth the extra moving part.

**On 2026.** Worked out after the fact, from only what was known going
into each week: 2.6 places off in week 10 (the first release, resumes
only), then 1.7 and 1.6 in weeks 11 and 12, with all 12 of the committee's
top 12 in both.

**Decision.** The app's CFP guess now uses the week-to-week model whenever
the committee has a previous ranking that season, and the resume score
before that. The prediction is saved each week before the release and
graded after. Weights: `COMMITTEE_UPDATE` in `R/config.R`.

## Nov 22, 2026: learning the committee from this season only

**Decision first.** The committee prediction now learns its weights only
from 2026's committee rankings, and learns again every time a new one is
released. Past seasons shaped which inputs it uses, not their weights.

**Why.** The committee's rules changed for the 2026 season, so its 2018 to
2025 rankings describe a different process. Weights fit on them could be
wrong in ways their accuracy on old seasons cannot show.

**What that costs, so far.** Each week predicted from only the rankings
before it:

| Week | This season only | Weights from 2018 to 2025 |
|---|---|---|
| 10 (first ranking) | 3.9 places off | 2.6 |
| 11 | 2.4 | 1.7 |
| 12 | 1.8 | 1.6 |

Week 10 has nothing to learn from yet and uses strength of record alone.
Week 11 has one ranking but no week-to-week example. By week 12 the gap is
small. Holding the fit back more or less (tested from 1 to 100) changed
week 12 by under 0.1 places.

**A new input: a No. 1 that keeps winning.** In week 12 the committee kept
9-1 Georgia at No. 1 over 10-0 Utah after both won. Our model had Utah
first, and would have again for week 13 by a hair. An input for "No. 1
last time and no loss since" lets the fit learn that from the committee's
own choice. It moved nothing else and puts Georgia back at No. 1 for week
13. It rests on one example so far, held back like everything else.

**Week 13's saved prediction was re-saved** with this model on Sunday, Nov
22, before the committee's release. The first version, saved that morning
with the 2018 to 2025 weights, had Utah first and Georgia second.

## Nov 22, 2026: past seasons as the starting point

**Change.** The committee's 2026 rules kept the same ingredients and
changed their weight. So instead of learning from this season alone, the
weights now start from a fit on 2018 to 2025 (`scripts/committee_prior.R`)
and each 2026 ranking pulls them toward this season's emphasis.

**Each week predicted only from what came before it:**

| Week | Past seasons as start | This season only |
|---|---|---|
| 10 | 2.56 places off | 3.88 |
| 11 | 1.84 | 2.44 |
| 12 | 1.64 | 1.80 |
| Average | 2.01 | 2.71 |

How hard the fit is held toward the start (3 to 100) changed the average by
0.02 or less. Week 13 is Georgia, Utah, Notre Dame, Miami, Texas either
way at the top. Its saved prediction was re-saved with this version on
Nov. 22, still before the committee's release.

## 2026-11-22: wins over ranked teams

The week 13 prediction had Arizona (19 last time) passing USC (18). The
whole edge was Arizona's win at Kansas State counting for more than USC's
win over Maryland. They never played, and the committee says that for close
teams it looks at results against ranked teams: USC beat No. 14 Ohio State,
Arizona has no ranked wins. The model had no input for that, so we added
`ranked_wins` (wins over teams in the committee's last ranking) to the
update model.

**Each season predicted from the others' weights (update model, every
ranking after the first):**

| Season | Without | With ranked wins |
|---|---|---|
| 2018 | 1.46 places off | 1.50 |
| 2019 | 1.44 | 1.57 |
| 2021 | 1.47 | 1.34 |
| 2022 | 1.34 | 1.17 |
| 2023 | 1.14 | 1.16 |
| 2024 | 1.34 | 1.51 |
| 2025 | 1.34 | 1.26 |
| 2026 | 1.66 | 1.36 |
| Average | 1.40 | 1.36 |

Mixed season to season, better on average and clearly better on this
season. Pairs put in the right order went from 97.3% to 97.5%. Kept.
With it, the week 13 prediction has USC 15 and Arizona 16, still close
(about 56% USC). It also moved Texas above Miami, Texas Tech above
Tennessee and Oregon above Iowa. The prediction was re-saved on Nov. 22,
before the committee's release.

## 2026-11-22: a pass over the week 13 top 25

Went through the predicted top 25 team by team, looking for things the
model misses. Each idea was tested a season at a time (2018 to 2025 and
2026, update model, average places off for the committee's top 25).

| Idea | Average | 2026 | Kept? |
|---|---|---|---|
| Model as it was (with ranked wins) | 1.358 | 1.36 | |
| Input: ranked last time and no loss since | 1.371 | 1.46 | No |
| Input: losses to unranked teams | 1.376 | 1.50 | No |
| Input: new loss to an unranked team | 1.356 | 1.60 | No |
| Rule: head-to-head swap for close neighbors | 1.344 | 1.32 | Yes |
| Rule: winners drop at most 1 place | 1.322 | 1.40 | Changed |
| Same, only for teams that played and won | 1.330 | 1.36 | |
| Both rules, winners that played | 1.314 | 1.32 | Yes |

What prompted it: Alabama was predicted to drop from 3 to 6 after beating
an FCS team, because two of its old wins (Kentucky, South Carolina) lost
value when those teams lost. The committee almost never does that: of 667
ranked teams that did not lose, 7 dropped two or more places and 2 fell
out. The one 2026 case was Indiana falling 4 to 9 on a bye, which is why
the rule only covers teams that played and won.

Week 13 now has Alabama 4th instead of 6th, with Texas and Miami each one
place lower. The rest of the top 25
held. Not added, but worth watching: Liberty (10-1, AP 22) is unranked in
our prediction and Boise State (24th) holds the Group of Six spot after
losing to San Diego State. If the committee swaps them, the playoff field
changes.

## 2026-11-22: head-to-head in groups

The committee's procedure ranks a few teams at a time (a pool of about six,
place three, add more), and head-to-head is one of the first things
compared inside a group. Our rule only let next-door neighbors swap. Tried
windows of 2 to 6 places and score gaps of 1, 2, 3 and "always":

| Window | Gap 1 | Gap 2 | Gap 3 | Always |
|---|---|---|---|---|
| 2 (neighbors) | 1.314 | 1.311 | 1.315 | 1.315 |
| 3 | 1.314 | 1.316 | 1.322 | 1.322 |
| 4 | 1.316 | **1.305** | 1.336 | 1.377 |
| 5 | 1.319 | 1.313 | 1.355 | 1.492 |
| 6 | 1.327 | 1.340 | 1.370 | 1.637 |

(Average places off, with the keep-winners rule on.) Honoring every
head-to-head in a group of 5 or 6 is clearly worse: the committee does not
always let it win. Window 4 with gap 2 (about four places of score) was
best, better than the old rule in 6 of 8 seasons and 1.32 to 1.24 on 2026.
The gain is small and was picked from 20 tries, so treat it as a lean,
not proof. Kept.

Week 13 change: Tennessee (beat Alabama, close in score) moves above
Alabama, then the keep-winners rule puts Alabama back at 4. Net: Tennessee
7th, Texas Tech 8th. Both won, Tennessee was 3 places ahead last time.

## 2026-11-24: does a missing quarterback explain our misses?

**What prompted it.** USC at UCLA in week 13: we had UCLA by 4.5, the
sportsbooks USC by 7. Our line is built from ratings only and knows
nothing about who is on the field.

**Data.** Who threw the passes in every game, 2018 to 2026, from the box
scores (`scripts/pull_passing.R`, 135 API calls once, one a week after
that). The main quarterback is whoever has thrown the most passes for the
team so far that season. He is out when he threw none in a game. An
established starter has at least 75% of the team's passes over at least 60
attempts, which leaves out early-season quarterback battles.

**How teams did against our line** (fit seasons, `scripts/research/qb_out.R`):

| Situation | Games | Points worse than our line | Worse than the market |
|---|---|---|---|
| Main QB out, any | 1,239 | 1.4 | -0.5 |
| Established starter out | 482 | 3.5 | 1.4 |
| ...the first game he misses | 359 | 4.0 | 1.8 |
| ...a later game | 133 | 2.0 | 0.2 |
| Established starter missed the last game | 240 | 0.9 | -0.4 |

**Keep rule** (same as every other factor):

| Factor | CV change | Holdout | Verdict |
|---|---|---|---|
| Established starter out | -0.026 [-0.053, -0.001] | -0.065 | kept |
| ...the first game he misses | -0.024 [-0.050, +0.003] | -0.011 | rejected |
| Established starter missed the last game | +0.000 [-0.005, +0.005] | -0.024 | rejected |
| Out, scaled by how good he was | -0.001 [-0.014, +0.014] | -0.036 | rejected |
| Main QB out, any | -0.004 [-0.023, +0.014] | -0.054 | rejected |

**What it means.**
- An established starter being out is worth about 3.5 points, and it
  passes, narrowly: the top of the interval is -0.001. The size is steady
  from 2021 on (3.1 to 6.0 by season) after two flat seasons.
- Scaling by the quarterback's yards per attempt did not help.
- "He missed the last game" does not pass on its own, because many come
  back. Alabama's starter sat out a 47-0 win over an FCS team in week 12.
  So the box scores can say who to watch, but the adjustment needs a
  report that he is out this week.
- After two missed games the effect is gone: the ratings have caught up.

**And USC at UCLA?** Not explained by this. UCLA's starter went out in week
6 and the backup has started six games (5-1), so he is now the main
quarterback by our own rule and the ratings mostly reflect him. The market
line is real (most books USC by 6.5 to 7) and at least one other
ratings-based model also likes UCLA. The market is doubting UCLA for
reasons a ratings model does not see.

**Built from it.**
- The passing pull, weekly, and each team's quarterback situation on its
  team page.
- A "Big gap: check for news" marker on games where we and the market
  differ by 7 or more.
- The adjusted line. The Thursday and Friday availability check records
  each quarterback's status in `data/qb_status.csv`. When the player
  listed out is the team's established starter by the box scores, This
  week and Matchup show a second line with `QB_OUT_POINTS` (3.5) taken off
  his team. Our own line is left as it is, so the two can be compared.
- The Scorecard grades the adjusted line beside ours and the market's,
  using only reports filed before kickoff.

**First grades.** Seeded from this season's notes, the adjustment applied
to two week 12 games. It helped one (Northwestern at Minnesota: our miss
10.9, adjusted 7.4) and hurt the other (New Mexico at Wyoming: 4.9 to
8.4). Two games say nothing yet. Ohio State, Oregon and UCLA were listed
out too, but their backups had already taken over as the main
quarterback, so no adjustment applied, as the study says it should not.

**To revisit.** The size is a constant in `R/config.R`. Once a season of
graded games exists, refit it, and drop the adjustment if it has not
helped.

## 2026-11-24: do matchups matter beyond the ratings?

A rating says how good a team is overall. The question was whether it also
matters how two teams fit: a passing offense against a defense that is weak
against the pass, or a top offense against a top defense.

Each team's four units (pass offense, rush offense, pass defense, rush
defense) are its points added per play so far that season, from games
already played, set against the rest of the country
(`scripts/research/matchups.R`). 4,913 games had units for both teams.

| Candidate | CV change | Holdout | Verdict |
|---|---|---|---|
| Style fit: pass-leaning offense against a pass-soft defense | -0.001 [-0.012, +0.011] | -0.020 | rejected |
| Passing: offense's edge over the defense it faces | +0.008 [-0.009, +0.026] | -0.027 | rejected |
| Rushing: offense's edge over the defense it faces | -0.001 [-0.019, +0.019] | -0.017 | rejected |
| Top offense against top defense | -0.010 [-0.024, +0.004] | -0.021 | rejected |
| Each team's weakest unit | +0.003 [-0.018, +0.024] | -0.002 | rejected |

Nothing passes. Top offense against top defense is the closest. Two limits
on this test: the units are not adjusted for the opponents each team has
faced, and the unit numbers are noisy early in a season.

**Injuries to other positions** (a top defense missing its best safety)
cannot be tested yet. We have no measure of what one defender is worth, and
no history of availability reports to learn from. The availability check
would have to record every starter listed out for a season first.

## 2026-11-24: does the committee drop a team whose quarterback is out?

The committee's protocol lets it weigh a key player's absence. Added an
input to the week-to-week model: the team's established starter missed its
latest game. Each season predicted from the others, as before.

| | Average places off | 2026 |
|---|---|---|
| Model as it is | 1.305 | 1.24 |
| + starter out | 1.320 | 1.28 |
| + starter newly out | 1.307 | 1.24 |

The learned weight points the right way (about a quarter to half a place
down) but the prediction gets no better. It is rare: 30 ranked team-weeks
since 2018. Ranked teams that kept winning moved up 1.1 places with the
starter out and 1.2 with him in. Where it has clearly mattered is the
playoff cut on Selection Day (Florida State in 2023), which is one case.

Decision: not scored. The committee prediction flags the team instead
("QB out" or "QB missed last game"), so the reader can weigh it.

## 2026-11-24: three more tries at accuracy, none kept

Run with `scripts/research/qb_out.R`, `matchups.R` and `luck.R`. Same keep
rule as always: the cross-validated change must sit wholly below zero and
the held-out seasons must improve too.

**A bigger adjustment for a first missed game.** Tried 4 points when the
starter is newly out and 2 once the backup has played, in place of a flat
3.5. Cross-validated change -0.027 [-0.055, +0.000], holdout -0.043. No
better than the flat number and it fails the rule by a hair. The flat 3.5
stays.

**Matchups, adjusted for opponents.** The earlier matchup test used raw
unit numbers. This pass adjusts each offense and defense for who it has
played (`matchups.R`, or `--raw` for the old version). All five candidates
are still rejected. The ratings already carry most of what a unit matchup
would add.

**Luck.** Three ideas: teams that outscored what their yardage says they
should have, teams with a lopsided record in one-score games, and the same
over the last four games. None passes. Luck in one half of a season says
almost nothing about the other half (correlation 0.04), and the blend
already leans on points rather than wins, so there is little left to
correct.

**What this leaves.** The one thing the model does not see is who is on
the field. The quarterback adjustment covers the biggest case. For the
rest we need a record, so the Thursday and Friday availability check now
writes every starter listed out or doubtful to `data/availability.csv`.
Nothing reads it for the line yet. After a season of it, test whether
"N starters out" moves games by more than the market already shows. Until
then the app only marks a team with 4 or more starters out
(`STARTERS_OUT_FLAG`), so This week stays readable.

## 2026-11-24: do missing starters, other than the quarterback, move games?

There is no history of injury reports, so absences were read off the box
scores, like the quarterback study. `scripts/research/pull_box_scores.R`
saved who carried, caught and tackled in every game since 2017 (150 API
calls, files in `data/research/box/`). Going into a game, a team's core
players are its top rusher, top 3 receivers and top 6 tacklers so far that
season. A core player is out when he has no carry, catch or tackle in the
game. 11,404 team-games, run with `scripts/research/starters_out.R`.

| Factor | Points worse than our line | Cross-validated change | Holdout | |
|---|---|---|---|---|
| Each core player out | 0.56 | -0.012 [-0.032, +0.008] | -0.004 | rejected |
| Top rusher out | 1.06 | -0.004 [-0.014, +0.005] | -0.003 | rejected |
| Each top-3 receiver out | 0.61 | +0.002 [-0.010, +0.013] | -0.003 | rejected |
| Each top-6 tackler out | 0.49 | -0.003 [-0.018, +0.010] | +0.005 | rejected |
| 2 or more top tacklers out | 0.54 | -0.002 [-0.007, +0.004] | +0.000 | rejected |
| 3 or more core players out | none | +0.002 [-0.001, +0.006] | -0.001 | rejected |
| Missed the last game (known before kickoff) | 0.40 | -0.001 [-0.015, +0.011] | -0.005 | rejected |

Scaling by how much of the team's production the missing players stood for
does no better.

What it says: the direction is right. A team missing a core player does
about half a point worse than our line, and about a point without its top
rusher. But that is small next to a typical miss of 12 points, and it does
not improve the predictions. A quarterback is worth 3.5. No other single
position comes close, and stacking absences ("3 or more out") shows
nothing.

Limits: a receiver who played and caught nothing counts as out, which
waters the receiver number down. Offensive linemen do not appear in a box
score at all. Both are reasons to keep the availability record going, since
reports name linemen and say who is truly out.

Decision: no adjustment for other positions. The "4 or more starters out"
marker stays as a note for the reader, not a change to the line.
