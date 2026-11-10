_Generated file: written by scripts/audit.R on 2026-11-09 from cfb.sqlite (802 teams, 5,435 games, 16,096 lines, 3,208 ratings). Do not edit by hand; rerun the script._

# Data audit

Checked on 2026-11-09. Rows checked: 802 teams, 5,435 games, 16,096 lines, 3,208 ratings.

No check that could corrupt the model found anything.
2 other check(s) flagged rows worth a look.

Severity: **error** would corrupt the model, **warning** is worth a look, **info** is a table to read.

## Summary

| Check | What it looks for | Severity | Result | Rows flagged |
|---|---|---|---|---|
| games_duplicate_id | The same game_id stored more than once. | error | Pass | 0 |
| games_same_matchup_same_date | The same two teams meeting twice on one date under different game ids. | error | Pass | 0 |
| games_completed_no_score | Completed games with a missing score. | error | Pass | 0 |
| games_score_not_completed | Games with a score that are not marked completed. | warning | Pass | 0 |
| games_bad_score | Scores below 0 or above 100. | error | Pass | 0 |
| games_completed_in_future | Completed games that start after the newest data pull. | error | Pass | 0 |
| games_team_plays_itself | Games where the home and away team are the same. | error | Pass | 0 |
| games_fbs_team_not_in_teams | Teams marked FBS in a game but missing from that season's teams table. | error | Pass | 0 |
| games_class_vs_teams | Teams in the FBS teams table but marked as another class in a game (left out of the fit). | warning | Pass | 0 |
| games_unexpected_class | Class values other than fbs, fcs, ii or iii. | error | Pass | 0 |
| games_missing_elo | Completed FBS-vs-FBS games missing a pregame Elo (they drop out of the Elo fit). | warning | Pass | 0 |
| games_elo_out_of_range | Pregame Elo below 500 or above 2600. | error | Pass | 0 |
| games_team_twice_same_day | A team listed in two games on the same date. | error | Pass | 0 |
| games_per_team_season | FBS teams with fewer than 8 or more than 16 completed games in a finished season. | warning | Pass | 0 |
| games_bad_week | Regular-season weeks outside 1 to 16, postseason games not in week 1, or an unknown season type. | warning | Pass | 0 |
| games_bad_start_date | Start dates that are missing or cannot be read as a date and time. | error | Pass | 0 |
| games_neutral_by_season | Neutral-site games per season, so a sudden change stands out. | info | For information |  |
| lines_orphan_game | Lines for a game_id that is not in games. | warning | Pass | 0 |
| lines_null_spread | Line rows with no spread (skipped by the pipeline). | info | For information |  |
| lines_absurd_spread | Spreads bigger than 70 points either way. | error | Pass | 0 |
| lines_providers_per_game | How many sportsbooks quote each game, per season. | info | For information |  |
| lines_provider_disagreement | Games where sportsbooks disagree by more than 7 points. | warning | Worth a look | 12 |
| lines_flipped_sign | A provider's spread that matches the other books' line for the other team (home and away swapped). | warning | Worth a look | 10 |
| lines_missing_for_fbs_games | Completed FBS-vs-FBS games with no usable line, per season. | warning | Pass | 0 |
| lines_sign | Seasons where minus the closing spread does not track the home margin (correlation under 0.5). | error | Pass | 0 |
| lines_worst_misses | Games where the closing line missed the final margin by more than 45 points. | info | For information |  |
| lines_provider_accuracy | Average miss of each provider against the final margin, next to the median-of-providers line. | info | For information |  |
| ratings_duplicate | A team rated twice in one snapshot. | error | Pass | 0 |
| ratings_team_not_in_teams | Ratings for a team_id that is not in that season's teams table. | error | Pass | 0 |
| ratings_fbs_team_unrated | FBS teams with no rating in a snapshot from that source. | warning | Pass | 0 |
| ratings_rows_by_snapshot | Rows per snapshot next to the number of FBS teams that season. | info | For information |  |
| ratings_out_of_range | Ratings outside -45 to 45 (SP+, FPI, SRS) or 500 to 2600 (Elo), or an unknown source. | error | Pass | 0 |
| ratings_constant_or_missing | Snapshots where every rating is missing or identical. | error | Pass | 0 |
| ratings_week_over_week | One-week rating changes over 15 points (SP+, FPI, SRS) or 250 (Elo). Needs two weekly snapshots. | warning | Pass | 0 |
| teams_duplicate | A team listed twice in one season. | error | Pass | 0 |
| teams_missing_school | Teams with no school name. | error | Pass | 0 |
| teams_bad_color | Colors that are not a #RRGGBB hex code. | warning | Pass | 0 |
| teams_missing_logo | Teams with no logo. | warning | Pass | 0 |
| teams_conference_change | Teams that changed conference from one season to the next (real realignment). | info | For information |  |
| teams_name_change | A team_id whose school name changes between seasons. | warning | Pass | 0 |

## Details

### games_neutral_by_season (info)

Neutral-site games per season, so a sudden change stands out.
11 row(s).

| season | season_type | n_neutral | n_games |
|---|---|---|---|
| 2021 | postseason | 38 | 38 |
| 2021 | regular | 21 | 849 |
| 2022 | postseason | 42 | 42 |
| 2022 | regular | 20 | 854 |
| 2023 | postseason | 40 | 42 |
| 2023 | regular | 23 | 868 |
| 2024 | postseason | 41 | 46 |
| 2024 | regular | 39 | 874 |
| 2025 | postseason | 41 | 46 |
| 2025 | regular | 23 | 888 |
| 2026 | regular | 11 | 888 |

### lines_null_spread (info)

Line rows with no spread (skipped by the pipeline).
23 row(s).

| game_id | provider | season | home_team | away_team |
|---|---|---|---|---|
| 401309603 | Bovada | 2021 | Louisiana | Nicholls |
| 401520145 | DraftKings | 2023 | Jacksonville State | UTEP |
| 401520190 | DraftKings | 2023 | Florida | McNeese |
| 401532574 | DraftKings | 2023 | Fresno State | Eastern Washington |
| 401628482 | DraftKings | 2024 | Nebraska | Northern Iowa |
| 401635570 | ESPN Bet | 2024 | Georgia Tech | Duke |
| 401643787 | DraftKings | 2024 | Georgia Southern | South Carolina State |
| 401643822 | ESPN Bet | 2024 | Marshall | UL Monroe |
| 401644733 | DraftKings | 2024 | Akron | Colgate |
| 401644734 | DraftKings | 2024 | Ohio | Morgan State |
| 401645327 | DraftKings | 2024 | Charlotte | Gardner-Webb |
| 401645379 | ESPN Bet | 2024 | East Carolina | Navy |
| 401655632 | DraftKings | 2024 | Northwestern | Eastern Illinois |
| 401752701 | ESPN Bet | 2025 | Mississippi State | Alcorn State |
| 401752813 | ESPN Bet | 2025 | Minnesota | Northwestern State |
| 401752836 | ESPN Bet | 2025 | Indiana | Indiana State |
| 401754517 | ESPN Bet | 2025 | Duke | Elon |
| 401754617 | ESPN Bet | 2025 | Virginia Tech | Wofford |
| 401756876 | ESPN Bet | 2025 | Oklahoma State | UT Martin |
| 401756877 | ESPN Bet | 2025 | Texas Tech | Arkansas-Pine Bluff |
| 401756892 | ESPN Bet | 2025 | Cincinnati | Northwestern State |
| 401760357 | ESPN Bet | 2025 | San Diego State | Stony Brook |
| 401777328 | ESPN Bet | 2025 | Virginia | Duke |

### lines_providers_per_game (info)

How many sportsbooks quote each game, per season.
22 row(s).

| season | n_providers | n_games |
|---|---|---|
| 2021 | 1 | 12 |
| 2021 | 2 | 8 |
| 2021 | 3 | 99 |
| 2021 | 4 | 625 |
| 2021 | 5 | 143 |
| 2022 | 1 | 11 |
| 2022 | 2 | 67 |
| 2022 | 3 | 49 |
| 2022 | 4 | 765 |
| 2023 | 1 | 59 |
| 2023 | 2 | 132 |
| 2023 | 3 | 665 |
| 2023 | 4 | 22 |
| 2023 | 5 | 29 |
| 2024 | 1 | 81 |
| 2024 | 2 | 42 |
| 2024 | 3 | 781 |
| 2025 | 1 | 10 |
| 2025 | 2 | 170 |
| 2025 | 3 | 754 |
| 2026 | 1 | 32 |
| 2026 | 2 | 739 |

### lines_provider_disagreement (warning)

Games where sportsbooks disagree by more than 7 points.
12 row(s).

| game_id | season | season_type | week | neutral_site | home_team | away_team | n_providers | lowest_spread | highest_spread | gap |
|---|---|---|---|---|---|---|---|---|---|---|
| 401677085 | 2024 | postseason | 1 | 0 | UTSA | Coastal Carolina | 3 | -12.5 | 13.5 | 26 |
| 401331447 | 2021 | regular | 14 | 1 | Iowa | Michigan | 4 | -12 | 12 | 24 |
| 401761589 | 2025 | regular | 1 | 1 | Charlotte | App State | 3 | 3 | 19.5 | 16.5 |
| 401301056 | 2021 | regular | 15 | 0 | Army | Navy | 4 | -7 | 7 | 14 |
| 401331219 | 2021 | postseason | 1 | 1 | Nevada | Western Michigan | 4 | -6.5 | 7 | 13.5 |
| 401645331 | 2024 | regular | 5 | 0 | Temple | Army | 3 | 11 | 21.5 | 10.5 |
| 401551773 | 2023 | postseason | 1 | 1 | Florida State | Georgia | 3 | 13.5 | 23.5 | 10 |
| 401628374 | 2024 | regular | 5 | 0 | Alabama | Georgia | 3 | -7.5 | 2 | 9.5 |
| 401551749 | 2023 | postseason | 1 | 1 | Oklahoma State | Texas A&M | 3 | -4.5 | 4.5 | 9 |
| 401331239 | 2021 | postseason | 1 | 1 | Ohio State | Utah | 4 | -4.5 | 4 | 8.5 |
| 401643701 | 2024 | regular | 1 | 0 | Troy | Nevada | 3 | -15.5 | -7.5 | 8 |
| 401778316 | 2025 | postseason | 1 | 1 | East Carolina | Pittsburgh | 2 | 6 | 13.5 | 7.5 |

### lines_flipped_sign (warning)

A provider's spread that matches the other books' line for the other team (home and away swapped).
10 row(s).

| game_id | season | season_type | week | neutral_site | home_team | away_team | home_points | away_points | provider | spread | others_median | closing_line |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 401301056 | 2021 | regular | 15 | 0 | Army | Navy | 13 | 17 | Bovada | -7 | 7 | 7 |
| 401331219 | 2021 | postseason | 1 | 1 | Nevada | Western Michigan | 24 | 52 | consensus | -6.5 | 6.5 | 6.5 |
| 401331239 | 2021 | postseason | 1 | 1 | Ohio State | Utah | 48 | 45 | consensus | 4 | -4 | -4 |
| 401331447 | 2021 | regular | 14 | 1 | Iowa | Michigan | 3 | 42 | Bovada | -12 | 12 | 12 |
| 401404106 | 2022 | regular | 10 | 0 | Kansas | Oklahoma State | 37 | 16 | Bovada | 2 | -3 | -3 |
| 401441994 | 2022 | postseason | 1 | 1 | Troy | UTSA | 18 | 12 | Bovada | -2 | 3 | 3 |
| 401551749 | 2023 | postseason | 1 | 1 | Oklahoma State | Texas A&M | 31 | 23 | DraftKings | 4.5 | -4.25 | -4 |
| 401677085 | 2024 | postseason | 1 | 0 | UTSA | Coastal Carolina | 44 | 15 | ESPN Bet | 13.5 | -12.5 | -12.5 |
| 401677093 | 2024 | postseason | 1 | 1 | USC | Texas A&M | 35 | 31 | ESPN Bet | -3.5 | 3.5 | 3.5 |
| 401777325 | 2025 | regular | 15 | 0 | Jacksonville State | Kennesaw State | 15 | 19 | ESPN Bet | -1.5 | 3 | 3 |

### lines_worst_misses (info)

Games where the closing line missed the final margin by more than 45 points.
17 row(s).

| game_id | season | week | home_team | away_team | home_points | away_points | n_providers | median_spread | home_margin | miss |
|---|---|---|---|---|---|---|---|---|---|---|
| 401404166 | 2022 | 13 | Liberty | New Mexico State | 14 | 49 | 4 | -24 | -35 | -59 |
| 401760413 | 2025 | 12 | Nevada | San José State | 55 | 10 | 3 | 9.5 | 45 | 54.5 |
| 401628978 | 2024 | 3 | Purdue | Notre Dame | 7 | 66 | 3 | 7.5 | -59 | -51.5 |
| 401531919 | 2023 | 12 | Arkansas State | Texas State | 77 | 31 | 2 | 3.25 | 46 | 49.25 |
| 401551737 | 2023 | 1 | Syracuse | South Florida | 0 | 45 | 2 | -4.25 | -45 | -49.25 |
| 401858462 | 2026 | 4 | Maryland | UCLA | 3 | 54 | 2 | 2.5 | -51 | -48.5 |
| 401426593 | 2022 | 9 | Rice | Charlotte | 23 | 56 | 4 | -15 | -33 | -48 |
| 401645380 | 2024 | 14 | Tulsa | Florida Atlantic | 16 | 63 | 3 | -1 | -47 | -48 |
| 401754540 | 2025 | 4 | San Diego State | California | 34 | 0 | 3 | 14 | 34 | 48 |
| 401403953 | 2022 | 12 | South Carolina | Tennessee | 63 | 38 | 4 | 22.5 | 25 | 47.5 |
| 401643760 | 2024 | 12 | Utah State | Hawai'i | 55 | 10 | 3 | 2.5 | 45 | 47.5 |
| 401862822 | 2026 | 10 | Tulane | Tulsa | 10 | 60 | 2 | 3 | -50 | -47 |
| 401520404 | 2023 | 12 | Auburn | New Mexico State | 10 | 31 | 3 | -25 | -21 | -46 |
| 401752843 | 2025 | 4 | Indiana | Illinois | 63 | 10 | 3 | -7 | 53 | 46 |
| 401404102 | 2022 | 9 | Kansas State | Oklahoma State | 48 | 0 | 4 | -2.5 | 48 | 45.5 |
| 401524030 | 2023 | 7 | Washington State | Arizona | 6 | 44 | 3 | -7.5 | -38 | -45.5 |
| 401858423 | 2026 | 1 | Rutgers | Massachusetts | 21 | 37 | 2 | -29.25 | -16 | -45.25 |

### lines_provider_accuracy (info)

Average miss of each provider against the final margin, next to the median-of-providers line.
9 row(s).

| provider | n_games | mae | consensus_mae | vs_consensus |
|---|---|---|---|---|
| Caesars Sportsbook (Colorado) | 33 | 11.7 | 11.67 | 0.03 |
| DraftKings | 2837 | 11.91 | 11.89 | 0.02 |
| Bovada | 4506 | 12.05 | 12.04 | 0.01 |
| ESPN Bet | 1838 | 12.06 | 12.04 | 0.03 |
| William Hill (New Jersey) | 1969 | 12.13 | 12.13 | 0 |
| teamrankings | 1587 | 12.24 | 12.25 | -0.01 |
| consensus | 1562 | 12.27 | 12.26 | 0.01 |
| numberfire | 145 | 12.52 | 12.52 | 0 |
| Caesars (Pennsylvania) | 15 | 19.4 | 19.45 | -0.05 |

### ratings_rows_by_snapshot (info)

Rows per snapshot next to the number of FBS teams that season.
24 row(s).

| source | season | week | is_final | n_rows | n_distinct_teams | n_fbs_teams |
|---|---|---|---|---|---|---|
| elo | 2021 |  | 1 | 130 | 130 | 130 |
| elo | 2022 |  | 1 | 131 | 131 | 131 |
| elo | 2023 |  | 1 | 133 | 133 | 133 |
| elo | 2024 |  | 1 | 134 | 134 | 134 |
| elo | 2025 |  | 1 | 136 | 136 | 136 |
| elo | 2026 | 11 | 0 | 138 | 138 | 138 |
| fpi | 2021 |  | 1 | 130 | 130 | 130 |
| fpi | 2022 |  | 1 | 131 | 131 | 131 |
| fpi | 2023 |  | 1 | 133 | 133 | 133 |
| fpi | 2024 |  | 1 | 134 | 134 | 134 |
| fpi | 2025 |  | 1 | 136 | 136 | 136 |
| fpi | 2026 | 11 | 0 | 138 | 138 | 138 |
| sp | 2021 |  | 1 | 130 | 130 | 130 |
| sp | 2022 |  | 1 | 131 | 131 | 131 |
| sp | 2023 |  | 1 | 133 | 133 | 133 |
| sp | 2024 |  | 1 | 134 | 134 | 134 |
| sp | 2025 |  | 1 | 136 | 136 | 136 |
| sp | 2026 | 11 | 0 | 138 | 138 | 138 |
| srs | 2021 |  | 1 | 130 | 130 | 130 |
| srs | 2022 |  | 1 | 131 | 131 | 131 |
| srs | 2023 |  | 1 | 133 | 133 | 133 |
| srs | 2024 |  | 1 | 134 | 134 | 134 |
| srs | 2025 |  | 1 | 136 | 136 | 136 |
| srs | 2026 | 11 | 0 | 138 | 138 | 138 |

### teams_conference_change (info)

Teams that changed conference from one season to the next (real realignment).
Showing the first 25 of 39 rows.

| team_id | school | from_season | from_conference | to_season | to_conference |
|---|---|---|---|---|---|
| 276 | Marshall | 2021 | Conference USA | 2022 | Sun Belt |
| 295 | Old Dominion | 2021 | Conference USA | 2022 | Sun Belt |
| 2572 | Southern Miss | 2021 | Conference USA | 2022 | Sun Belt |
| 252 | BYU | 2022 | FBS Independents | 2023 | Big 12 |
| 2429 | Charlotte | 2022 | Conference USA | 2023 | American Athletic |
| 2132 | Cincinnati | 2022 | American Athletic | 2023 | Big 12 |
| 2226 | Florida Atlantic | 2022 | Conference USA | 2023 | American Athletic |
| 248 | Houston | 2022 | American Athletic | 2023 | Big 12 |
| 2335 | Liberty | 2022 | FBS Independents | 2023 | Conference USA |
| 166 | New Mexico State | 2022 | FBS Independents | 2023 | Conference USA |
| 249 | North Texas | 2022 | Conference USA | 2023 | American Athletic |
| 242 | Rice | 2022 | Conference USA | 2023 | American Athletic |
| 5 | UAB | 2022 | Conference USA | 2023 | American Athletic |
| 2116 | UCF | 2022 | American Athletic | 2023 | Big 12 |
| 2636 | UTSA | 2022 | Conference USA | 2023 | American Athletic |
| 12 | Arizona | 2023 | Pac-12 | 2024 | Big 12 |
| 9 | Arizona State | 2023 | Pac-12 | 2024 | Big 12 |
| 349 | Army | 2023 | FBS Independents | 2024 | American Athletic |
| 25 | California | 2023 | Pac-12 | 2024 | ACC |
| 38 | Colorado | 2023 | Pac-12 | 2024 | Big 12 |
| 201 | Oklahoma | 2023 | Big 12 | 2024 | SEC |
| 2483 | Oregon | 2023 | Pac-12 | 2024 | Big Ten |
| 2567 | SMU | 2023 | American Athletic | 2024 | ACC |
| 24 | Stanford | 2023 | Pac-12 | 2024 | ACC |
| 251 | Texas | 2023 | Big 12 | 2024 | SEC |

