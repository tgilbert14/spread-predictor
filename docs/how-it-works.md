# How it works

A plain-language tour of the model and the pipeline. For exact column names
see the [data dictionary](data-dictionary.md).

## The short version

Five rating systems each say how good every team is. We turn each system's
opinion into a point margin for the matchup, average the five, and convert
the average into a win probability.

## The five systems

| System | What it is | Units |
|---|---|---|
| SP+ | Bill Connelly's efficiency-based rating | Points vs an average team |
| FPI | ESPN's Football Power Index | Points vs an average team |
| SRS | Simple Rating System: scoring margin adjusted for schedule | Points |
| Elo | A running rating that moves after every game | Elo points |
| Power | Our own rating, built from game scores and success rate (`R/power_rating.R`) | Points |

### The Power rating

Each team's rating is a prior plus a conference shift and a team shift, fit
to this season's games with a ridge penalty, so a team with few games stays
close to its prior.

What it learns from each game is mostly the score and partly success rate:
how consistently each team gained enough yards on a play to stay on
schedule. Success rate is a steadier sign of strength than the final score,
which bounces around with turnovers and late touchdowns. For each game:

```
target = 0.6 * home margin + 0.4 * 124 * (home success rate - success rate it allowed)
```

124 converts a success-rate gap into points (a regression of margin on it).
A game with no stats uses its margin alone. The prior is last season's conference average plus 70% of
the team's edge over it. A team new to the data starts 3 points below its
conference average. All FCS opponents are pooled into one team.

It is computed walk-forward, one week at a time (the postseason is one last
block). The rating for a game uses only games from earlier weeks, so it is a
fair "before kickoff" number we can fit and test on. The settings are in
`POWER_RATING` in `R/config.R`, with a reason for each.

### Preseason information

Early in a season, Elo and Power have few games to go on. So the Elo and
Power margins also get points for two things known before kickoff:

- **Roster talent**, the 247Sports talent composite.
- **Returning production**, the share of last season's production that is
  coming back.

Each is turned into a z-score among that season's FBS teams (how many
standard deviations above average). A team with no value counts as average.
The points fade in a straight line, full in week 1 and gone by week 7, and
are 0 in the postseason:

```
fade = max(0, 1 - (week - 1) / 6)
preseason points = fade * (talent_points * talent gap + returning_points * returning gap)
```

SP+, FPI and SRS get nothing extra. SP+ and FPI build in their own
preseason view.

### The power-conference correction

CFBD Elo understates the gap between power-conference teams (SEC, Big Ten,
Big 12, ACC, the Pac-12 through 2023, and Notre Dame) and everyone else. When
a power team hosts a non-power team, real margins and the closing line are
both about 22 to 23 points, and Elo says about 14. So the Elo margin gets a
fitted bonus per tier step, about 6 points in the current fit. It was about 9
before the preseason terms were added: most of these games are early-season
non-conference games, where the talent gap now explains part of the
difference. The list of power teams is `POWER_CONFERENCES` and
`POWER_TEAM_IDS` in `R/config.R`.

## From ratings to a spread

For Team A against Team B:

```
margin = w_sp  * (SP+ gap)
       + w_fpi * (FPI gap)
       + w_srs * (SRS gap)
       + w_elo * (Elo gap / k + elo_tier * tier gap + preseason points)
       + w_power * (power_scale * Power gap + preseason points)
       + h * site
```

- A "gap" is A's rating minus B's.
- `k` converts Elo points into game points. `tier gap` is +1 when only A is a
  power team, -1 when only B is, and 0 otherwise.
- `power_scale` is fitted and close to 1.
- `preseason points` is 0 from week 7 on (see above).
- `h` is home-field advantage in points. `site` is +1 when A is home, -1 when
  B is home, and 0 on a neutral field.
- The weights `w` add up to 1.

A positive margin means A is favored. The app always says this in words
("Georgia by 6.5") so nobody has to remember which way the sign points.

## From a spread to a win probability

Real games scatter around any prediction. We measure that scatter as `sigma`,
the typical size of a miss. Then:

```
P(A wins) = pnorm(margin / sigma)
```

The "most likely range" in the app is the middle 80% of that same bell curve.

## How the parameters are fit

Two "house" models are fit on games, each one regression with no intercept:

```
Elo model:   home margin = (1/k) * Elo gap + elo_tier * tier gap + h_elo * (not neutral)
                           + fade * (talent * talent gap + returning * returning gap)
Power model: home margin = power_scale * Power gap + h_power * (not neutral)
                           + fade * (talent * talent gap + returning * returning gap)
```

The Elo values are CFBD's pregame Elo, and the Power values are our
walk-forward pregame ratings. Talent and returning production are known
before the season. All of it was known before kickoff. This is the key
design choice in the project.

The app uses one home field, `h`, the mean of `h_elo` and `h_power`. They
come out within a fraction of a point of each other. In the same way it uses
one `talent_points` and one `returning_points`, each the mean of the two
models' estimates. `sigma` is the typical
miss of the house blend (the average of the two models) on games it did not
see.

### Seasons

- **2017 is burn-in.** The Power rating needs a season of results before its
  numbers mean anything, so nothing is fit on 2017.
- **2018, 2019 and 2021 to 2025 are fit and cross-validated** (`FIT_SEASONS`).
- **2020 is skipped.** The COVID season had short, conference-only schedules
  and empty stadiums. It stays in the Power rating's history, so 2021 starts
  from real results, but it is never fit or scored.
- **The current season is a holdout** (`HOLDOUT_SEASON`). It is scored with
  parameters fit on the fit seasons and never used to fit anything.

### Why not fit on SP+, FPI and SRS?

To test a model fairly, you predict each past game using only what was known
before kickoff. For SP+, FPI and SRS the data source only gives one value per
past season, and that value is the end-of-season number, which already
includes every result.

Fitting on those would be like grading a student on a test they had the
answer key for. The scores look great and mean nothing. This is called
look-ahead bias.

So:

- `k`, `elo_tier`, `power_scale`, `h`, `talent_points`, `returning_points`
  and `sigma` are fit on pregame Elo, pregame Power and preseason numbers,
  which are clean.
- The five blend weights start equal (20% each). A plain average of good
  forecasts is hard to beat.
- Every week, the pipeline saves what SP+, FPI, SRS and Elo say *before* that
  week's games. Once about 300 games have been played against saved
  snapshots, the weights can be fit honestly. Fitted weights replace equal
  ones only if they do better on weeks the fit never saw.

The model report tab includes a "leaked" table that scores SP+, FPI and SRS
using end-of-season ratings. It's there to catch bugs (a flipped sign shows up
immediately). It is never used to fit anything.

## How we check it

- **Leave one season out.** Fit on all but one of the fit seasons, predict
  that one, repeat. Every prediction in the accuracy table was made without
  seeing that season.
- **The holdout.** The current season's games, predicted with parameters
  that never saw them.
- **Mean absolute error (MAE).** The average miss in points.
- **Calibration.** When the model says 70%, does that team win about 70% of
  the time? The chart on the model report tab shows this.
- **Brier score.** One number for how good the probabilities are. Lower is
  better.
- **The closing line.** Sportsbook lines are the benchmark. We report their
  MAE on the same games. If our model ever beats the line by a lot, the first
  assumption should be a bug.

### Backtest

`Rscript scripts/backtest.R` re-tests the models step by step, the two
factors now in the model (success rate in the Power rating, and preseason
talent and returning production), and the factors we tried and left out (bye
weeks and short rest, blowout curvature, a postseason shift, a home-field
trend, home field in conference games, a separate early-season sigma). It
writes [backtest-results.md](backtest-results.md). A factor is kept only if
its paired bootstrap 95% interval on the cross-validated change lies wholly
below zero and the holdout agrees. The two factors in the model pass; the
others do not.

## Saving and grading predictions

Backtests say how the model would have done. The Scorecard says how it
actually did, on predictions made in the open.

**Saving.** On the first refresh of each week (Tuesday), `freeze_predictions()`
in `R/predictions.R` saves the app's line for every game on the slate to
`data/snapshots/predictions/{season}_wk{WW}.csv`: each system's margin, the
blend, the home win chance, and the market line at that moment. It uses the
same `predict_matchup()` the app does, so the saved line is the line people
saw.

Two rules keep it honest:

- **Saved before kickoff, or not at all.** If any game of the week has
  started, nothing is saved. A prediction written after kickoff could have
  seen part of the result, so it would prove nothing.
- **Never rewritten.** Later refreshes, a refit or new ratings never touch a
  saved file. Thursday's and Friday's refreshes find it and leave it alone.

**Grading.** Every refresh joins each saved prediction to its game. Once a
game is final, it gets:

- our miss: `|blend - final home margin|`
- the market's miss: `|(-market_spread_home) - final home margin|`, using the
  line saved with our prediction, so both forecasts had the same information
- whether we picked the winner, and who was closer (us, the market, or a tie)
- when our line and the market's were 3 or more points apart
  (`DISAGREE_POINTS`): whether the result landed on our side of the market
  line. A result exactly on the line (a push) counts for neither side.

These add up per week and for the season. The per-system table grades SP+,
FPI, SRS, Elo and Power on the same saved lines. It is the first honest test
of all five: the backtest can only test Elo and Power, because the others'
past ratings already include the results.

**The market line beside ours.** When the two teams on the Matchup tab really
play this week, and the site picked is the real one, the tab shows the
market's line under ours: the line, the win chance it implies (using the
same `sigma` as our own), how far we are from it, and one sentence on how the
two have compared on past games, taken from the fit's accuracy table. The
market is never part of our number. On past games the closing line has been
about half a point a game closer than we are, and when the two differ by a
lot the market has usually been right (see `docs/research-log.md`), so a big
gap is a prompt to look for news, not a sign we found something.

**Line movement.** The slate keeps the market line from the saved file, so the
app can show how far the market has moved since. A move of 2.5 points or
more (`LINE_MOVE_POINTS`) is flagged, because it usually means news, such as a
quarterback ruled out, that the ratings do not know yet.

**Game notes.** `data/notes.csv` holds short, sourced notes about this week's
games (availability, weather, other). A separate check outside this code adds
them on Thursdays and Fridays. The app reads the file directly, so notes show
up without rebuilding anything. Notes never change the number.

A few weeks of grades is a small sample. One game can swing by two
touchdowns, so judge the model on a season or more.

## The pipeline

```
CFBD API
   |  scripts/refresh.R   (three times a week, automated; runs every step below)
   v
data/snapshots/*.csv        saved forever, committed to git
                            (extras/: talent, returning production, game stats)
   |  build_db()
   v
cfb.sqlite                  rebuilt on demand, not committed
   |  scripts/fit.R         (once a season, or when you want)
   v
data/params.json            k, h, preseason points, sigma, weights, accuracy numbers
   |  build_app_data()      also grades the saved predictions
   v
data/app_data.rds           what the app shows, committed for the hosted app
   |  freeze_predictions()  saves this week's lines once, before kickoff,
   |                        to data/snapshots/predictions/
   v
Shiny app                   reads data/app_data.rds and data/notes.csv
```

A few choices worth knowing about:

- **Snapshot files are the source of truth.** The database can be deleted and
  rebuilt at any time. This keeps the project reproducible from a fresh
  clone.
- **Weekly files are never overwritten.** If a rating system revises its
  numbers later, we still have what it said at the time.
- **The app never calls the API or the database.** It reads two small files
  (the app data and the game notes), which is why it starts fast and why
  predictions feel instant.
- **SQL lives in `sql/`** as plain files, so the same queries can run on
  DuckDB or Azure SQL with a different connection.

## Refitting

Refit once a season, or after the snapshot count passes about 300 games:

```bash
Rscript scripts/fit.R
Rscript scripts/refresh.R --offline
```

`fit.R` prints a gate report with `k`, `elo_tier`, `power_scale`, `h`, the
preseason points and `sigma`, with the main ones for each held-out season. They should be close to each other. If they aren't, look at the data before
trusting the fit.
