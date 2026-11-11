# Data dictionary

What every file and table holds, and which way the signs point. If you are
changing the pipeline or the app, this is the contract between them.

## Sign conventions

Get these wrong and every number flips, so they are stated once, here.

| Where | Convention |
|---|---|
| `predict_matchup()` and the app | `margin = Team A points - Team B points`. Positive means A is favored. |
| `games` table and fitting | Home-relative. `home_points - away_points`. |
| `lines.spread` and `slate.market_spread_home` | Home-relative, sportsbook style (the CFBD convention). `-7` means the home team is favored by 7. Expected home margin is `-spread`. |
| Predictions files and the scorecard | Margins (`sp` ... `blend`, `final_margin`) are home-relative: home points minus away points. `market_spread_home` and `market_at_freeze` are sportsbook style, as above. |
| `slate.market_move` | Points of expected home margin. Positive means the market moved toward the home team. |

## Snapshot files (`data/snapshots/`)

CSV, UTF-8, committed to git. These are the source of truth. Everything else
can be rebuilt from them.

| Path | One row per | Written |
|---|---|---|
| `ratings/{source}/{season}_wk{WW}.csv` | team | Weekly. Never overwritten. |
| `ratings/{source}/{season}_final.csv` | team | Once per past season. Never overwritten. |
| `teams/{season}.csv` | team | Once per season. |
| `games/{season}.csv` | game | Past seasons once. Current season is rewritten each run, because games get played. |
| `lines/{season}.csv` | game and sportsbook | Same rule as games. |
| `extras/talent/{season}.csv` | team | Once per season. |
| `extras/returning/{season}.csv` | team | Once per season. |
| `extras/advanced/{season}.csv` | team per game | Same rule as games. |
| `extras/lines_full/{season}.csv` | game and sportsbook | Research only. Past seasons once; current season on each `extras` run. |
| `extras/locations/{season}.csv` | team | Research only. Same rule. |
| `predictions/{season}_wk{WW}.csv` | game | Once per week, before the week's first kickoff. Never overwritten. |

`{source}` is one of `sp`, `fpi`, `srs`, `elo`. The fifth system, Power, is
computed from game results (`R/power_rating.R`), so it has no snapshot files. `{WW}` is the zero-padded
CFBD week, for example `2026_wk11.csv`.

**Postseason.** CFBD restarts week numbers at 1 for the postseason, so a
postseason ratings file would collide with a regular-season one. Ratings are
not snapshotted during the postseason. Games and lines still refresh. Blend
weights are fit on regular-season games only.

**Weekly vs final.** A `_wk` file is what a rating system said *before* that
week's games. It is safe to fit on. A `_final` file was pulled after the
season and already includes every result. It is only used for a diagnostic
that is labeled as leaked.

### Ratings files

| Column | Type | Notes |
|---|---|---|
| `season` | int | |
| `week` | int | Empty in `_final` files |
| `team_id` | int | CFBD team id. The join key everywhere. |
| `team` | chr | School name, for reading the file by eye |
| `rating` | num | Points vs an average team for `sp`, `fpi`, `srs`. Elo points for `elo`. |
| `pulled_at` | chr | ISO 8601 UTC time of the API call |

### Teams files

`team_id`, `school`, `mascot`, `abbreviation`, `conference`, `color`,
`alt_color`, `logo`. Colors are hex strings with a leading `#`. `logo` is a
URL and may be empty.

### Games files

`game_id`, `season`, `week`, `season_type`, `start_date`, `completed`,
`neutral_site`, `home_id`, `home_team`, `home_class`, `home_points`,
`home_pregame_elo`, `away_id`, `away_team`, `away_class`, `away_points`,
`away_pregame_elo`.

`home_class` and `away_class` are `fbs`, `fcs` and so on. Only games where
both are `fbs` are used for fitting.

### Lines files

`game_id`, `provider`, `spread`, `pulled_at`. One row per sportsbook. The
pipeline uses the median across sportsbooks as the closing line.

### Extras (`data/snapshots/extras/`)

Model inputs from three more endpoints, one file per season, saved exactly
as the API returns them (every column, the API's names). They carry school
names, not ids. `build_db()` matches each name to that season's teams
(exactly, then with `team_key()` for spellings like "San Jose State") and
drops rows for teams we do not track, with one count per table.

| Folder | Columns used | Becomes |
|---|---|---|
| `talent/` | `year`, `school`, `talent` (247Sports roster talent composite) | `talent` table |
| `returning/` | `season`, `team`, `percent_ppa` (share of last season's production returning, usually 0 to 1) | `returning_production` table |
| `advanced/` | `game_id`, `team`, `off_success_rate`, `def_success_rate` | `game_stats` table |

Talent and returning production feed the house models early in the season.
Success rates feed the Power rating. `scripts/pull_extras.R` pulls past
seasons once; the weekly snapshot keeps the current season up to date.

Two more folders are research only. The model, the database and the app
never read them. They feed the analysis scripts.

| Folder | What it holds | Used by |
|---|---|---|
| `lines_full/` | Every sportsbook's line per game as the API returns it, including `spread_open`, the opening spread | `scripts/disagreement.R` |
| `locations/` | Each FBS team's home stadium with `latitude` and `longitude` | The travel-distance test in `docs/research-log.md` |

### Predictions files

Written by `freeze_predictions()` (`R/predictions.R`) on the first refresh of
the week, for every game on the slate, with the ratings and parameters the app
was using. Nothing is written if any game of that week has kicked off. Columns,
in this order:

| Column | Type | Notes |
|---|---|---|
| `game_id`, `season`, `week`, `start_date` | | As in the games file |
| `home_id`, `home_team`, `away_id`, `away_team` | | As in the games file |
| `neutral_site` | int | 0 or 1 |
| `sp`, `fpi`, `srs`, `elo`, `power` | num | Each system's home margin, rounded to 0.01. Empty when that system had no rating for one of the teams. |
| `blend` | num | Our line: the home margin the app showed |
| `win_prob_home` | num | Home team's chance to win, 0 to 1 |
| `sigma` | num | Typical miss used for the win chance |
| `market_spread_home` | num | Median sportsbook spread at the time of saving, sportsbook style. Empty when there was no line. |
| `fit_date` | chr | `fit_date` from `params.json` |
| `frozen_at` | chr | ISO 8601 UTC time the file was written |

## Game notes (`data/notes.csv`)

Short, sourced notes about this week's games. A separate weekly check outside
this code appends rows on Thursdays and Fridays. The app reads this file
directly at startup (it is not part of `app_data.rds`), and shows a note only
for a game on this week's slate. Notes never change a prediction.

| Column | Notes |
|---|---|
| `season`, `week`, `game_id` | Which game. Rows without a `game_id` are ignored. |
| `team` | The team the note is about. May be empty. |
| `category` | `availability`, `weather` or `other`. Anything else is read as `other`. |
| `note` | The note, in plain words. Rows without one are ignored. |
| `source`, `source_url` | Where it came from. The url may be empty; only http and https links are clickable. |
| `checked_at` | When it was checked, ISO 8601 date or time |

The reader (`load_notes()` in `R/notes.R`) tolerates a missing or empty file
and stray whitespace.

## Corrections (`data/overrides/`)

Snapshot files are never edited. When the source has something wrong, the fix
goes in a small hand-kept file that is applied when the database is built.

| File | Columns | Purpose |
|---|---|---|
| `neutral_site.csv` | `game_id`, `neutral_site` (0 or 1), `reason` | Corrects a neutral-site flag. Every row says why. |

Two other clean-ups happen at build time, with a message each time: a team
listed twice in one ratings file is averaged, and betting lines for games we
do not track are dropped. When three or more sportsbooks quote a game and one
has the spread on the wrong team, that one is left out of the closing line.

## Database (`cfb.sqlite`)

A build artifact, not committed. Tables `teams`, `games`, `lines` and
`ratings` mirror the snapshot files. Three more come from the extras, with
team ids instead of names:

| Table | Key | Columns |
|---|---|---|
| `talent` | `season`, `team_id` | `talent` |
| `returning_production` | `season`, `team_id` | `percent_ppa` |
| `game_stats` | `game_id`, `team_id` | `off_success_rate`, `def_success_rate` (0 to 1) |

`returning_production` is not called `returning` because RETURNING is a
reserved word in SQLite. The full definition, with comments, is in
[`sql/schema.sql`](../sql/schema.sql).

## Fitted parameters (`data/params.json`)

Written by `scripts/fit.R`. Committed, so changes show up in git history.

| Field | Meaning |
|---|---|
| `fit_date` | Date of the fit |
| `fit_seasons` | Seasons the model was fit and cross-validated on (`FIT_SEASONS`). The burn-in season before them only warms up the Power rating. |
| `holdout_season` | Season scored in `holdout`, never used to fit anything |
| `k` | Elo points per point of margin. Elo gap divided by `k` is a margin. |
| `elo_tier` | Points added to the Elo margin per tier step (power team vs non-power team) |
| `power_scale` | Points of margin per point of Power rating gap |
| `h` | Home-field advantage in points, used by every model in the app: the mean of `h_elo` and `h_power` |
| `h_elo`, `h_power` | Home field as fitted by the Elo model and the Power model. Reported so you can see they agree. |
| `talent_points`, `returning_points` | Week 1 points added to the Elo and Power margins per z-score of roster talent gap and of returning production gap. Each is the mean of the two models' estimates. They fade to 0 by week 7. |
| `talent_points_elo`, `talent_points_power`, `returning_points_elo`, `returning_points_power` | Each model's own estimate, for the gate report |
| `sigma` | Standard deviation of the real margin around the house blend (the Elo and Power average), out of fold |
| `public_scale` | Rows of `model` (`sp`, `fpi`, `srs`), `scale`, `n`. Points of spread per point of rating gap, fitted against closing lines on `n` late-season games. A missing row means 1. |
| `power` | The Power rating settings used (`POWER_RATING` in `R/config.R`), including `success_share` and `success_points` |
| `weights` | One number per system (`sp`, `fpi`, `srs`, `elo`, `power`). They sum to 1. |
| `weights_method` | `"equal"` or `"fitted"` |
| `weights_note` | One sentence on why that method was chosen |
| `metrics` | Out-of-fold accuracy on the fit seasons. Rows of `model` (`elo`, `power`, `house`, `line`), `label`, `n`, `mae`, `win_rate`, `brier`, all on the same games (those with a closing line) |
| `holdout` | Same columns, for the holdout season, using parameters fitted on the fit seasons only |
| `calibration` | House blend, out of fold. Rows of `bin_low`, `bin_high`, `n`, `predicted`, `actual` |
| `folds` | One row per held-out season: `season`, `k`, `elo_tier`, `power_scale`, `h`, `sigma` (from that fold's training games), `mae` (house blend) |
| `leaked_diagnostic` | Rows of `model`, `n`, `mae` using season-final ratings. For catching bugs only. |

## App data (`data/app_data.rds`)

What the app shows. A named list written by `build_app_data()`, committed so
the hosted app has it. The app also reads `data/notes.csv`. When the app data
is missing, the app uses `demo_app_data()`, which returns the same shape with
made-up teams, a made-up scorecard and made-up notes. An older file without
`scorecard` or the line-movement columns loads as if nothing had been saved.

| Element | Type | Contents |
|---|---|---|
| `meta` | list | `season`, `week`, `ratings_date`, `built_at`, `is_demo` |
| `teams` | data frame | One row per FBS team: the teams columns above, plus `sp`, `fpi`, `srs`, `elo`, `power`, their ranks (`sp_rank` and so on), and `tier` (1 for a power team, 0 otherwise, from `is_power_team()`), and `talent_z` and `returning_z` (this season's preseason z-scores among FBS teams, 0 when missing). `power` is centered so the average team is 0. A rating can be `NA`. |
| `params` | list | The contents of `params.json`. Table-like fields are data frames. |
| `slate` | data frame | This week's FBS games: `game_id`, `start_date`, `home_id`, `away_id`, `neutral_site` (logical), `market_spread_home` (can be `NA`), `market_at_freeze` (the line saved with this week's predictions, `NA` when none), `market_move` (`market_at_freeze - market_spread_home`: points the expected home margin has moved since, positive toward the home team) |
| `coverage` | data frame | Which snapshots exist: `source`, `season`, `week`, `n_teams`, `pulled_at` |
| `scorecard` | list | Saved predictions for this season, graded. See below. |

### Scorecard (`app_data$scorecard`)

Built by `build_scorecard()` in `R/predictions.R`.

| Element | Contents |
|---|---|
| `games` | One row per saved prediction this season: every predictions-file column, plus `home_points`, `away_points`, `final_margin`, `our_error` (`abs(blend - final_margin)`), `market_error` (`abs(-market_spread_home - final_margin)`), `picked_winner`, `closer` (`"us"`, `"market"` or `"tie"`), `disagreed` (our line and the market's at least `DISAGREE_POINTS` apart) and `our_side` (for a disagreement, did the result land on our side of the market line; `NA` for a push). Games not yet played have `NA` in all of these. |
| `weeks` | One row per week with a graded game: `season`, `week`, then the summary columns below |
| `season` | One row: `season`, then the summary columns. `games` is 0 before anything is graded. |
| `systems` | One row per system (`sp`, `fpi`, `srs`, `elo`, `power`, `blend`, `market`): `system`, `label`, `games`, `avg_miss` |

Summary columns: `games` (graded), `our_miss` (average), `market_games` (graded
games with a line), `market_miss` (average over those), `winners`,
`winner_share`, `closer` (games where we beat the market), `ties`,
`disagree_games` (graded disagreements, pushes left out) and
`disagree_our_side`.

## Prediction result

`predict_matchup(team_a, team_b, site, teams, params, week = NULL)` returns a
list. `week` is the regular-season week; the app passes `meta$week`. With
`NULL`, or from week 7 on, no preseason points are added.

| Element | Contents |
|---|---|
| `team_a`, `team_b` | One-row data frames from `teams` |
| `site` | `"neutral"`, `"a_home"` or `"b_home"` |
| `spread` | Blended margin, A minus B |
| `win_prob_a` | Chance A wins, 0 to 1 |
| `interval` | `low` and `high`: the middle 80% of likely margins |
| `models` | One row per rating system: `model`, `label`, `rating_a`, `rank_a`, `rating_b`, `rank_b`, `weight`, `margin`. Early in the season the Elo and Power margins include preseason points. |
| `flags` | Plain-language notes, possibly none |
