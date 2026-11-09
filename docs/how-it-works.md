# How it works

A plain-language tour of the model and the pipeline. For exact column names
see the [data dictionary](data-dictionary.md).

## The short version

Four rating systems each say how good every team is. We turn each system's
opinion into a point margin for the matchup, average the four, and convert
the average into a win probability.

## The four systems

| System | What it is | Units |
|---|---|---|
| SP+ | Bill Connelly's efficiency-based rating | Points vs an average team |
| FPI | ESPN's Football Power Index | Points vs an average team |
| SRS | Simple Rating System: scoring margin adjusted for schedule | Points |
| Elo | A running rating that moves after every game | Elo points |

## From ratings to a spread

For Team A against Team B:

```
margin = w_sp  * (SP+ gap)
       + w_fpi * (FPI gap)
       + w_srs * (SRS gap)
       + w_elo * (Elo gap / k)
       + h * site
```

- A "gap" is A's rating minus B's.
- `k` converts Elo points into game points.
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

`k`, `h` and `sigma` come from one regression on five seasons of FBS games:

```
home margin = (1/k) * (home Elo - away Elo) + h * (not neutral)
```

The Elo values are each team's rating *before* that game. This is the key
design choice in the project.

### Why only Elo?

To test a model fairly, you predict each past game using only what was known
before kickoff. The data source gives pregame Elo for every game. For SP+,
FPI and SRS it only gives one value per season, and for past seasons that
value is the end-of-season number, which already includes every result.

Fitting on those would be like grading a student on a test they had the
answer key for. The scores look great and mean nothing. This is called
look-ahead bias.

So:

- `k`, `h` and `sigma` are fit on pregame Elo, which is clean.
- The four blend weights start equal (25% each). A plain average of good
  forecasts is hard to beat.
- Every week, the pipeline saves what all four systems say *before* that
  week's games. Once about 300 games have been played against saved
  snapshots, the weights can be fit honestly. Fitted weights replace equal
  ones only if they do better on weeks the fit never saw.

The model report tab includes a "leaked" table that scores SP+, FPI and SRS
using end-of-season ratings. It's there to catch bugs (a flipped sign shows up
immediately). It is never used to fit anything.

## How we check it

- **Leave one season out.** Fit on four seasons, predict the fifth, repeat.
  Every prediction in the accuracy table was made without seeing that season.
- **Mean absolute error (MAE).** The average miss in points.
- **Calibration.** When the model says 70%, does that team win about 70% of
  the time? The chart on the model report tab shows this.
- **Brier score.** One number for how good the probabilities are. Lower is
  better.
- **The closing line.** Sportsbook lines are the benchmark. We report their
  MAE on the same games. If our model ever beats the line by a lot, the first
  assumption should be a bug.

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

`fit.R` prints a report with `k`, `h` and `sigma` for each held-out season.
They should be close to each other. If they aren't, look at the data before
trusting the fit.
