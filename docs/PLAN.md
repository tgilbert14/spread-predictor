# Neutral-Site CFB Spread Predictor: Build Plan

Rev 2 · Nov 9, 2026 · @tim

> **Build notes (Nov 9, 2026).** The project was built from this plan. A few
> things changed along the way:
>
> - Dependencies are listed in `DESCRIPTION` and installed by
>   `scripts/setup.R`, instead of an `renv` lockfile. Run `renv::init()` if
>   you want one.
> - Tables use `DT` instead of `reactable`.
> - Commands live in `scripts/` (`setup`, `backfill`, `fit`, `snapshot`,
>   `refresh`) instead of the project root.
> - Ratings are not snapshotted in the postseason, because CFBD restarts week
>   numbers there. See the data dictionary.
> - In "Where the models land", Team A is on the left, matching the pickers.
>
> The README and the other files in `docs/` describe the project as built.

## What changed from rev 1

| Area | Rev 1 | Rev 2 | Why |
|---|---|---|---|
| Weekly rating history | Open question | Answered: only Elo has it | SP+, FPI and SRS endpoints take `year` and `team` only. No `week`. The original backtest would have leaked results into the fit. |
| First task | Ingest history | Start weekly snapshots today | Every week we don't snapshot SP+/FPI/SRS is data we can never get back. |
| Blend weights | nnls on 2021 to 2025 | Equal weights on day one, fitted weights only once they beat equal weights on snapshot data | We can't honestly fit four weights yet. Equal-weight averages are a strong baseline anyway. |
| k, h, sigma | Fit on all four models | Fit on Elo only, using pregame Elo from `/games` | That data is leak-free and costs one call per season. |
| Validation | One holdout season, MAE only | Leave-one-season-out, MAE plus calibration | One holdout season is noisy, and a win probability needs a calibration check. |
| Phase 3 gate | Blend must beat every model | Blend must not be meaningfully worse than the best model | The old gate can fail on noise and tempts tuning against the test set. |
| Team crosswalk | Its own phase | A join check inside ingest | Everything comes from CFBD, so we key on CFBD team id. |
| Storage | SQLite as source of truth | Append-only snapshot files in git, SQLite rebuilt from them | Reproducible from a clean clone. Snapshots survive a corrupted db. |
| Refresh | Run a command by hand | Scheduled GitHub Action, manual command as fallback | A missed week is permanent. Don't depend on remembering. |
| App | Two pickers, a card, a table | Full UI spec (see UI and UX) | The original left the experience undefined. |
| Stack | Shiny | Shiny + bslib + modules + renv | Matches how we already build apps. |

## Goal and scope

Build an R/Shiny tool that takes any two FBS teams and returns a neutral-site spread and win probability from a blend of four public rating systems.

Be honest about the claim. A blend of ratings is usually steadier than any one system, but the closing line is the benchmark and we should expect to land a bit behind it. The app's value is that it prices any matchup, including ones with no line, and shows where the models disagree.

Done means:

- Pick Team A and Team B, choose neutral / A home / B home, get one spread and one win probability.
- See each model's number (SP+, FPI, SRS, Elo) so disagreement is visible.
- k, h and sigma are fit on leak-free history. Blend weights are documented as provisional until snapshot data supports fitting them.
- Ratings snapshot automatically every week.
- A model report tab shows how accurate the tool has been.

Out of scope for v1: injuries, weather, totals, FCS teams, scraping Massey or Sagarin, using the closing line as a model input.

## Data sources

Everything comes from the CollegeFootballData (CFBD) API through `cfbfastR` (3.1.0 or later). Every call needs a key sent as a Bearer token. Store it in `.Renviron` as `CFBD_API_KEY`.

| Input | Endpoint | cfbfastR function | Units | Point-in-time history? |
|---|---|---|---|---|
| SP+ | `/ratings/sp` | `cfbd_ratings_sp(year)` | points vs average | No. Season level only. |
| FPI | `/ratings/fpi` | `cfbd_ratings_fpi(year)` | points vs average | No. Season level only. |
| SRS | `/ratings/srs` | `cfbd_ratings_srs(year)` | points | No. Season level only. |
| Elo (current) | `/ratings/elo` | `cfbd_ratings_elo(year, week)` | Elo points | Yes, `week` arg |
| Elo (historical, per game) | `/games` | `cfbd_game_info(year)` | Elo points | Yes. `home_pregame_elo` and `away_pregame_elo` on every game. |
| Games and scores | `/games` | `cfbd_game_info(year)` | margins, `neutral_site` | n/a |
| Closing lines | `/lines` | `cfbd_betting_lines(year)` | spread | n/a |
| Teams | `/teams/fbs` | `cfbd_teams_fbs(year)` | id, colors, logo, abbreviation | n/a |
| Key usage | `/info` | `cfbd_api_key_info()` | calls left | n/a |

API budget: the free tier is 1,000 calls a month, shared with the basketball API. The full history pull is about 50 calls (six seasons times a handful of endpoints). The weekly refresh is about 6. Always pull a whole season in one call, never team by team. Log `cfbd_api_key_info()` at the start and end of every run.

## Architecture

Snapshot files are the source of truth. SQLite is a build artifact. The app reads one small file and never touches the API or the database.

```
CFBD API
   |  R/ingest.R  (weekly, scheduled)
   v
data/snapshots/{source}/{season}_wk{week}.csv   append-only, committed to git
   |  R/build_db.R
   v
cfb.sqlite            derived, gitignored, rebuildable any time
   |  R/fit.R  (once per season, or on demand)
   v
data/params.json      k, h, sigma, weights, fit date, metrics
   |  R/build_app_data.R
   v
data/app_data.rds     current team table + params + this week's slate
   |
   v
Shiny app
```

Notes:

- cfbfastR returns data frames, not raw JSON, so the cache is the returned table written as CSV. A snapshot file that already exists is never re-pulled or overwritten.
- Every snapshot row carries `season`, `week`, `pulled_at` and the CFBD `team_id`.
- `params.json` instead of `.rds` so parameter changes show up as readable git diffs.
- SQL lives in `sql/*.sql` and runs through DBI, so the same queries move to DuckDB or Azure SQL with a connection change.

## Modeling

### 1. Per-model neutral margin

SP+, FPI and SRS are in points. Neutral margin is Team A's rating minus Team B's. Elo is not in points, so divide the Elo gap by k.

### 2. Fit k, h and sigma on Elo (leak-free)

Use every FBS-vs-FBS game from 2021 to 2025 with pregame Elo from `/games`:

```
actual_margin_home = (1/k) * (home_pregame_elo - away_pregame_elo) + h * (1 - neutral_site)
```

One `lm()` with no intercept gives k and h together. Residual SD gives sigma. Because the Elo values are pregame, nothing in this fit has seen the result it predicts.

### 3. Blend

```
margin_A_minus_B = w_sp * dSP + w_fpi * dFPI + w_srs * dSRS + w_elo * (dElo / k) + h * site
```

`site` is +1 when A is home, -1 when B is home, 0 on a neutral field.

**Day one: equal weights (0.25 each).** We can't fit weights honestly yet, because historical SP+, FPI and SRS are end-of-season values that already include the games we would test on. SRS is the worst offender since it is built from results alone.

**Later: fitted weights.** Once we have about 300 snapshot-era games (roughly the end of this season's bowls), fit non-negative weights with `nnls`, shrunk toward equal weights. Switch the app to fitted weights only if they beat equal weights under leave-one-week-out validation. Record the decision in `params.json`.

### 4. Win probability

P(A wins) = pnorm(spread / sigma). Start with the Elo-based sigma, which is slightly conservative for a blend. Refit sigma from snapshot-era blend residuals when weights are refit.

### 5. Validation

- Leave-one-season-out across 2021 to 2025 for the Elo fit. 2026 to date is a final check, looked at once.
- Metrics: MAE against final margin, straight-up win rate, Brier score, and a calibration table (predicted win probability in 10-point bins vs actual win rate).
- Benchmark: closing-line MAE on the same games.
- Leaked diagnostic: also report SP+/FPI/SRS MAE using season-final ratings, clearly labeled as leaked. Useful for catching join or sign bugs. Never used for fitting.

## UI and UX

Principle: answer first, evidence second, method third. The whole thing should work one-handed on a phone.

### Layout

`bslib::page_navbar` with three tabs: **Matchup**, **This week**, **Model report**.

```
+--------------------------------------------------------------+
|  Matchup | This week | Model report      Ratings: wk 11, Nov 10 |
+--------------------------------------------------------------+
|  [logo] Team A  v   ( swap )   [logo] Team B  v              |
|        [ A home ]  [ Neutral ]  [ B home ]                   |
+--------------------------------------------------------------+
|                                                              |
|        Georgia by 6.5 over Texas on a neutral field          |
|                                                              |
|   Georgia 67% |==================|=========| 33% Texas       |
|   Most likely range: Texas by 14 to Georgia by 27            |
|   Market: Georgia -4.5  ·  we're 2 points higher             |
+--------------------------------------------------------------+
|  Where the models land                                       |
|  Texas favored  <----|----o--o---*--o----o---->  Georgia     |
|                      0   Elo SRS BLEND FPI SP+               |
+--------------------------------------------------------------+
|  Model   A rating (rank)   B rating (rank)   Margin   Weight |
|  ...                                                         |
+--------------------------------------------------------------+
```

### Matchup tab

- **Team pickers.** `selectizeInput` with logo and name in each option. Search matches school, mascot and abbreviation ("uga", "dawgs", "Georgia" all work). Teams grouped by conference.
- **Swap button** between the pickers. Site selection follows the teams when swapped.
- **Site** is a three-way segmented control, default Neutral. Labels use the actual team names ("Georgia home").
- **No submit button.** The result updates the moment an input changes. Prediction is arithmetic on an in-memory table, so it should feel instant.
- **Headline in plain English.** "Georgia by 6.5 over Texas on a neutral field." Never show a signed number in the headline. Sign conventions confuse everyone.
- **Win probability bar** split in the two team colors, with percentages as text on both ends.
- **Likely range.** An 80% interval on the margin, so a 6.5-point favorite doesn't read as a sure thing.
- **Market line** shown only when this matchup is on the schedule with a posted line, with the difference from our number. Comparison only, never a model input.
- **Model dot plot.** One horizontal axis, one labeled dot per model, the blend marked distinctly. This shows disagreement faster than a table. The table sits below it for the exact numbers: each team's rating and national rank per model, the margin, and the weight.
- **Flags**, shown as small plain-language notes only when they apply:
  - "Models disagree by more than 7 points."
  - "Early season. Ratings still lean on preseason priors." (weeks 1 to 3)
  - "Ratings are more than 8 days old."
- **Shareable.** Shiny URL bookmarking so `?a=Georgia&b=Texas&site=neutral` reopens the same matchup. A "Copy summary" button puts the headline and win probability on the clipboard.

### This week tab

A sortable table of every FBS game this week: matchup, our spread, market line, difference, win probability. Default sort is biggest difference from the market. Clicking a row opens it in the Matchup tab. This reuses `predict_matchup()` and is cheap to build.

### Model report tab

- Fitted k, h, sigma and current weights, with the fit date and whether weights are equal or fitted.
- MAE table: each model, the blend, the closing line.
- Calibration chart: predicted vs actual win rate.
- Snapshot coverage: which weeks we have, so gaps are obvious.
- Three or four sentences on how the number is made, written for someone who has never heard of SP+.

### Details that make it feel finished

- **First load is never blank.** Open on this week's biggest game by combined rating.
- **Rounding.** Spreads to the nearest half point. Win probability to a whole percent, capped at 1% and 99%. Under half a point shows "Pick'em", never "-0.0".
- **Same team twice** is impossible: the chosen team is removed from the other picker.
- **Team colors.** Check contrast against the background and fall back to the alternate color, then to a neutral, when it fails. If the two teams' colors are too similar, switch Team B to its alternate. Never rely on color alone: every colored element also has a text label.
- **Theme.** `bslib` Bootstrap 5 theme using the Desert Data Labs tokens (navy `#0a1330`, turquoise `#5eead4`) for chrome. Team colors are reserved for team-specific elements.
- **Mobile.** Pickers stack, the dot plot keeps its labels readable at 360px wide, the table scrolls horizontally inside its card.
- **Freshness** always visible in the navbar: rating week and date.
- **Errors in plain words.** If `app_data.rds` is missing or stale, say so and say what to run.

## Stack

| Piece | Choice | Note |
|---|---|---|
| Language | R, pinned with `renv` | Reproducible from a clean clone |
| Data access | `cfbfastR` | One wrapper for every endpoint we need |
| Storage | CSV snapshots + SQLite via `DBI`/`RSQLite` | SQL in `sql/` files, portable to DuckDB or Azure SQL |
| Modeling | base `lm`, `nnls` | Nothing heavier is needed |
| App | Shiny + `bslib`, Shiny modules | One module per tab |
| Tables and charts | `reactable`, `ggplot2` (or `plotly` for the dot plot hover) | |
| Tests | `testthat` | |
| Schedule | GitHub Actions cron, key in repo secrets | Windows Task Scheduler as a fallback |
| Hosting | Local first. shinyapps.io or Posit Connect Cloud later. | App needs only `app_data.rds`, so deploys are trivial |

## Build phases

Each phase has a gate that must pass before the next starts.

**Phase 0. Snapshot now.** Before anything else, write the smallest possible script that pulls current SP+, FPI, SRS, Elo and teams and writes them to `data/snapshots/`. Run it today. Commit.
- Gate: five files on disk for the current week, each with a row for every FBS team. Confirm what the current-season SP+/FPI/SRS calls actually return mid-season and note it in the README.

**Phase 1. Ingest and schedule.** Grow the Phase 0 script into `R/ingest.R`: history for 2021 to 2026 (games, lines, season-final ratings) plus the weekly snapshot. Add `R/build_db.R`. Add the GitHub Action, scheduled for Tuesday morning so all four systems have updated after the weekend.
- Gate: game counts per season look right. Every FBS team in the games table joins to every ratings table by `team_id` with zero unmatched. The Action has completed one scheduled run. Total API calls used are logged and under 100.

**Phase 2. Fit and validate.** `R/fit.R` builds one row per historical FBS-vs-FBS game, fits k, h and sigma on pregame Elo, runs leave-one-season-out, and writes `params.json` with equal blend weights.
- Gate: k, h and sigma are stable across folds (h in a plausible 1.5 to 3.5 point range). Calibration bins are within about 5 points of the diagonal. Closing-line MAE is lower than Elo MAE. If the line loses to Elo, there is a bug.

**Phase 3. Predict function.** `predict_matchup(team_a, team_b, site = "neutral")` returns the blended spread, win probability, interval and per-model rows. Pure function of the team table and params.
- Gate: tests pass. Swapping A and B flips the spread sign exactly and win probabilities sum to 1. Neutral spread equals the midpoint of the A-home and B-home spreads. A team against itself is an error. Unknown team names fail with a clear message.

**Phase 4. App.** Build the three tabs as modules against `app_data.rds`, following the UI and UX section.
- Gate: walk the checklist. First load shows a matchup. Result updates with no button. Swap works. Bookmarked URL restores state. Usable at 360px wide. Text contrast passes WCAG AA on every team color pair tested (try at least ten, including two similar-colored teams). For this week's slate, any game where we differ from the market by more than 7 points has been looked at and explained.

**Phase 5. Refit weights (after the season).** Once snapshot-era games pass about 300, run the shrunken `nnls` fit and compare to equal weights.
- Gate: fitted weights are adopted only if they beat equal weights out of sample. Either way, the result is written to the model report.

## Risks

| Risk | Why it matters | Mitigation |
|---|---|---|
| Look-ahead bias | Season-final SP+/FPI/SRS already include the outcomes | Fit only on pregame Elo. Blend weights stay equal until snapshot data exists. Leaked numbers are labeled as leaked. |
| Missed snapshot week | That week's ratings are gone for good | Scheduled Action, plus a coverage table in the app so a gap is visible right away |
| Upstream revisions | A rating system changes its formula or CFBD restates values | Snapshots are append-only and dated, so we always know what we saw and when |
| API quota | 1,000 calls a month on the free tier | Whole-season pulls, never re-pull an existing snapshot, log usage each run |
| Early-season noise | Ratings are mostly priors before week 4 | Low-confidence flag in the app. Revisit a wider early-season sigma once we have a full snapshot season. |
| FCS opponents | Not all models rate FCS teams | FBS-vs-FBS only in v1 |
| Small sample for weights | 300 games is thin for four correlated inputs | Shrink toward equal weights and require an out-of-sample win before switching |
| Team color accessibility | Some color pairs are unreadable or indistinguishable | Contrast check with fallbacks, text labels on everything |

## Decisions

Closed:

- **Weekly SP+/FPI/SRS history from CFBD?** No. Only Elo. This is why Phase 0 exists.
- **Closing line as a fifth input?** No. Show it next to our number as a comparison. Mixing it in would make the tool a copy of the market.
- **Training seasons?** 2021 to 2025. Skip 2020.

Open:

- [ ] Free tier or the $1 Patreon tier (5,000 calls)? Free is enough on paper. The paid tier is cheap insurance.
- [ ] Local only, or deploy somewhere you can reach from your phone?
- [ ] Is the repo going on GitHub? The scheduled snapshot assumes yes.

## Project layout

```
R/
  ingest.R            pulls and snapshots, never overwrites
  build_db.R          rebuilds cfb.sqlite from snapshots
  fit.R               fits k, h, sigma; validation; writes params.json
  predict.R           predict_matchup()
  build_app_data.R    writes data/app_data.rds
  mod_matchup.R       Shiny module
  mod_slate.R         Shiny module
  mod_report.R        Shiny module
  theme.R             bslib theme and team color helpers
sql/                  queries used by build_db.R and fit.R
data/
  snapshots/          append-only CSVs, committed
  params.json         committed
  app_data.rds        derived
app.R
refresh.R             ingest -> build_db -> build_app_data, one command
tests/testthat/
.github/workflows/snapshot.yml
renv.lock
README.md
```

## Agent handoff prompt

Paste this into a coding agent along with this doc.

```
You are building a neutral-site college football spread predictor in R.

Read PLAN.md in full. Follow the build phases in order, starting with Phase 0.
Do not start a phase until the previous phase's gate passes. Report each gate result.

Stack: R with renv, cfbfastR, DBI + RSQLite, nnls, testthat, Shiny with bslib
and Shiny modules, reactable, ggplot2.

The CFBD API key is in the CFBD_API_KEY environment variable. Never print or
commit it. The free tier allows 1,000 calls a month. Pull whole seasons in one
call, never re-pull a snapshot that already exists on disk, and log
cfbd_api_key_info() at the start and end of each run.

Phase 0 comes first and is urgent: snapshot current SP+, FPI, SRS, Elo and
teams to data/snapshots/ and commit before doing anything else.

Hard rules for modeling:
- SP+, FPI and SRS have no weekly history in the API. Never fit anything on
  season-final values of those ratings. Report them only as a labeled, leaked
  diagnostic.
- Fit k, h and sigma on pregame Elo from the games endpoint, 2021 to 2025,
  with leave-one-season-out validation.
- Blend weights are 0.25 each until Phase 5.

Code style: small focused functions, clear names, comments that explain intent,
SQL kept in sql/ files, no abstraction that isn't needed yet. Someone else will
maintain this.

Build the app to the UI and UX section of the plan. Treat that section as
requirements, not suggestions.

When Phase 2 is done, report: k, h, sigma per fold and overall, Elo MAE,
closing-line MAE, Brier score, and the calibration table.
When Phase 4 is done, report the gate checklist item by item.
```

## References

- cfbfastR function reference: https://cfbfastr.sportsdataverse.org/reference/index.html
- CFBD API docs: https://api.collegefootballdata.com/
- CFBD tiers: https://collegefootballdata.com/api-tiers
