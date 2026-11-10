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
| Power | Our own rating, built only from game scores (`R/power_rating.R`) | Points |

### The Power rating

Each team's rating is a prior plus a conference shift and a team shift, fit
to this season's scores with a ridge penalty, so a team with few games stays
close to its prior. The prior is last season's conference average plus 70% of
the team's edge over it. A team new to the data starts 3 points below its
conference average. All FCS opponents are pooled into one team.

It is computed walk-forward, one week at a time (the postseason is one last
block). The rating for a game uses only games from earlier weeks, so it is a
fair "before kickoff" number we can fit and test on. The settings are in
`POWER_RATING` in `R/config.R`, with a reason for each.

### The power-conference correction

CFBD Elo understates the gap between power-conference teams (SEC, Big Ten,
Big 12, ACC, the Pac-12 through 2023, and Notre Dame) and everyone else. When
a power team hosts a non-power team, real margins and the closing line are
both about 22 to 23 points, and Elo says about 14. So the Elo margin gets a
fitted bonus of about 10.6 points per tier step. The list of power teams is
`POWER_CONFERENCES` and `POWER_TEAM_IDS` in `R/config.R`.

## From ratings to a spread

For Team A against Team B:

```
margin = w_sp  * (SP+ gap)
       + w_fpi * (FPI gap)
       + w_srs * (SRS gap)
       + w_elo * (Elo gap / k + elo_tier * tier gap)
       + w_power * power_scale * (Power gap)
       + h * site
```

- A "gap" is A's rating minus B's.
- `k` converts Elo points into game points. `tier gap` is +1 when only A is a
  power team, -1 when only B is, and 0 otherwise.
- `power_scale` is fitted and close to 1.
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
Power model: home margin = power_scale * Power gap + h_power * (not neutral)
```

The Elo values are CFBD's pregame Elo, and the Power values are our
walk-forward pregame ratings. Both were known before kickoff. This is the key
design choice in the project.

The app uses one home field, `h`, the mean of `h_elo` and `h_power`. They
come out within a fraction of a point of each other. `sigma` is the typical
miss of the house blend (the average of the two models) on games it did not
see.

### Seasons

- **2021 is burn-in.** The Power rating needs a season of results before its
  numbers mean anything, so nothing is fit on 2021.
- **2022 to 2025 are fit and cross-validated** (`FIT_SEASONS`).
- **The current season is a holdout** (`HOLDOUT_SEASON`). It is scored with
  parameters fit on 2022 to 2025 and never used to fit anything.

### Why not fit on SP+, FPI and SRS?

To test a model fairly, you predict each past game using only what was known
before kickoff. For SP+, FPI and SRS the data source only gives one value per
past season, and that value is the end-of-season number, which already
includes every result.

Fitting on those would be like grading a student on a test they had the
answer key for. The scores look great and mean nothing. This is called
look-ahead bias.

So:

- `k`, `elo_tier`, `power_scale`, `h` and `sigma` are fit on pregame Elo and
  pregame Power, which are clean.
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

- **Leave one season out.** Fit on three of the fit seasons, predict the
  fourth, repeat. Every prediction in the accuracy table was made without
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

`Rscript scripts/backtest.R` re-tests the models and the factors we tried and
left out (bye weeks and short rest, blowout curvature, a postseason shift, a
home-field trend, home field in conference games, a separate early-season
sigma). It writes [backtest-results.md](backtest-results.md). A factor is
kept only if its paired bootstrap 95% interval on the cross-validated change
lies wholly below zero and the holdout agrees. None does today.

## The pipeline

```
CFBD API
   |  scripts/snapshot.R  (weekly, automated)
   v
data/snapshots/*.csv        saved forever, committed to git
   |  build_db()
   v
cfb.sqlite                  rebuilt on demand, not committed
   |  scripts/fit.R         (once a season, or when you want)
   v
data/params.json            k, h, sigma, weights, accuracy numbers
   |  build_app_data()
   v
data/app_data.rds           the one file the app reads
   |
   v
Shiny app
```

A few choices worth knowing about:

- **Snapshot files are the source of truth.** The database can be deleted and
  rebuilt at any time. This keeps the project reproducible from a fresh
  clone.
- **Weekly files are never overwritten.** If a rating system revises its
  numbers later, we still have what it said at the time.
- **The app never calls the API or the database.** It reads one small file,
  which is why it starts fast and why predictions feel instant.
- **SQL lives in `sql/`** as plain files, so the same queries can run on
  DuckDB or Azure SQL with a different connection.

## Refitting

Refit once a season, or after the snapshot count passes about 300 games:

```bash
Rscript scripts/fit.R
Rscript scripts/refresh.R --offline
```

`fit.R` prints a gate report with `k`, `elo_tier`, `power_scale`, `h` and
`sigma` for each held-out season. They should be close to each other. If they aren't, look at the data before
trusting the fit.
