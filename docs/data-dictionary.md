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

### Research data (`data/snapshots/extras/`)

`extras/talent/`, `extras/returning/` and `extras/advanced/`, one file per
season, saved exactly as the API returns them. They exist to test ideas in
the backtest. The app and the fit do not read them.

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
`ratings` mirror the snapshot files. The full definition, with comments, is in
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
| `sigma` | Standard deviation of the real margin around the house blend (the Elo and Power average), out of fold |
| `power` | The Power rating settings used (`POWER_RATING` in `R/config.R`) |
| `weights` | One number per system (`sp`, `fpi`, `srs`, `elo`, `power`). They sum to 1. |
| `weights_method` | `"equal"` or `"fitted"` |
| `weights_note` | One sentence on why that method was chosen |
| `metrics` | Out-of-fold accuracy on the fit seasons. Rows of `model` (`elo`, `power`, `house`, `line`), `label`, `n`, `mae`, `win_rate`, `brier`, all on the same games (those with a closing line) |
| `holdout` | Same columns, for the holdout season, using parameters fitted on the fit seasons only |
| `calibration` | House blend, out of fold. Rows of `bin_low`, `bin_high`, `n`, `predicted`, `actual` |
| `folds` | One row per held-out season: `season`, `k`, `elo_tier`, `power_scale`, `h`, `sigma` (from that fold's training games), `mae` (house blend) |
| `leaked_diagnostic` | Rows of `model`, `n`, `mae` using season-final ratings. For catching bugs only. |

## App data (`data/app_data.rds`)

The only file the app reads. A named list written by `build_app_data()`. When
it is missing, the app uses `demo_app_data()`, which returns the same shape
with made-up teams.

| Element | Type | Contents |
|---|---|---|
| `meta` | list | `season`, `week`, `ratings_date`, `built_at`, `is_demo` |
| `teams` | data frame | One row per FBS team: the teams columns above, plus `sp`, `fpi`, `srs`, `elo`, `power`, their ranks (`sp_rank` and so on), and `tier` (1 for a power team, 0 otherwise, from `is_power_team()`). `power` is centered so the average team is 0. A rating can be `NA`. |
| `params` | list | The contents of `params.json`. Table-like fields are data frames. |
| `slate` | data frame | This week's FBS games: `game_id`, `start_date`, `home_id`, `away_id`, `neutral_site` (logical), `market_spread_home` (can be `NA`) |
| `coverage` | data frame | Which snapshots exist: `source`, `season`, `week`, `n_teams`, `pulled_at` |

## Prediction result

`predict_matchup(team_a, team_b, site, teams, params)` returns a list:

| Element | Contents |
|---|---|
| `team_a`, `team_b` | One-row data frames from `teams` |
| `site` | `"neutral"`, `"a_home"` or `"b_home"` |
| `spread` | Blended margin, A minus B |
| `win_prob_a` | Chance A wins, 0 to 1 |
| `interval` | `low` and `high`: the middle 80% of likely margins |
| `models` | One row per rating system: `model`, `label`, `rating_a`, `rank_a`, `rating_b`, `rank_b`, `weight`, `margin` |
| `flags` | Plain-language notes, possibly none |
