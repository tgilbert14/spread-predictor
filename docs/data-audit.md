_Generated file: written by scripts/audit.R on 2026-11-09 from cfb.sqlite (1,320 teams, 8,651 games, 27,788 lines, 5,225 ratings, 1,318 talent, 1,307 returning_production, 16,866 game_stats). Do not edit by hand; rerun the script._

# Data audit

Checked on 2026-11-09. Rows checked: 1,320 teams, 8,651 games, 27,788 lines, 5,225 ratings, 1,318 talent, 1,307 returning_production, 16,866 game_stats.

No check that could corrupt the model found anything.
6 other check(s) flagged rows worth a look.

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
| games_per_team_season | FBS teams with fewer than 8 or more than 16 completed games in a finished season. | warning | Worth a look | 43 |
| games_bad_week | Regular-season weeks outside 1 to 16, postseason games not in week 1, or an unknown season type. | warning | Worth a look | 2 |
| games_bad_start_date | Start dates that are missing or cannot be read as a date and time. | error | Pass | 0 |
| games_neutral_by_season | Neutral-site games per season, so a sudden change stands out. | info | For information |  |
| lines_orphan_game | Lines for a game_id that is not in games. | warning | Pass | 0 |
| lines_null_spread | Line rows with no spread (skipped by the pipeline). | info | For information |  |
| lines_absurd_spread | Spreads bigger than 70 points either way. | error | Pass | 0 |
| lines_providers_per_game | How many sportsbooks quote each game, per season. | info | For information |  |
| lines_provider_disagreement | Games where sportsbooks disagree by more than 7 points. | warning | Worth a look | 25 |
| lines_flipped_sign | A provider's spread that matches the other books' line for the other team (home and away swapped). | warning | Worth a look | 21 |
| lines_missing_for_fbs_games | Completed FBS-vs-FBS games with no usable line, per season. | warning | Pass | 0 |
| lines_sign | Seasons where minus the closing spread does not track the home margin (correlation under 0.5). | error | Pass | 0 |
| lines_worst_misses | Games where the closing line missed the final margin by more than 45 points. | info | For information |  |
| lines_provider_accuracy | Average miss of each provider against the final margin, next to the median-of-providers line. | info | For information |  |
| ratings_duplicate | A team rated twice in one snapshot. | error | Pass | 0 |
| ratings_team_not_in_teams | Ratings for a team_id that is not in that season's teams table. | error | Pass | 0 |
| ratings_fbs_team_unrated | FBS teams with no rating in a snapshot from that source. | warning | Worth a look | 55 |
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
| talent_duplicate | A team with two talent values in one season. | error | Pass | 0 |
| returning_duplicate | A team with two returning-production values in one season. | error | Pass | 0 |
| returning_out_of_range | Returning-production shares below 0 or above 1 (the model pulls them back into range). | warning | Worth a look | 22 |
| preseason_missing_by_season | FBS teams with no talent or no returning-production value, per season (they count as average). | info | For information |  |
| game_stats_duplicate | A team with two rows of stats for one game. | error | Pass | 0 |
| game_stats_bad_success_rate | Success rates outside 0 to 1. | error | Pass | 0 |
| game_stats_missing_for_fbs_games | Seasons where over 3% of completed FBS-vs-FBS games have no stats for the home team. | warning | Pass | 0 |

## Details

### games_per_team_season (warning)

FBS teams with fewer than 8 or more than 16 completed games in a finished season.
Showing the first 25 of 43 rows.

| season | team_id | school | n_games |
|---|---|---|---|
| 2020 | 2005 | Air Force | 6 |
| 2020 | 2006 | Akron | 6 |
| 2020 | 12 | Arizona | 5 |
| 2020 | 9 | Arizona State | 4 |
| 2020 | 68 | Boise State | 7 |
| 2020 | 189 | Bowling Green | 5 |
| 2020 | 2084 | Buffalo | 7 |
| 2020 | 25 | California | 4 |
| 2020 | 2117 | Central Michigan | 6 |
| 2020 | 2429 | Charlotte | 6 |
| 2020 | 38 | Colorado | 6 |
| 2020 | 36 | Colorado State | 4 |
| 2020 | 2199 | Eastern Michigan | 6 |
| 2020 | 2229 | Florida International | 5 |
| 2020 | 278 | Fresno State | 6 |
| 2020 | 2309 | Kent State | 4 |
| 2020 | 120 | Maryland | 5 |
| 2020 | 113 | Massachusetts | 4 |
| 2020 | 193 | Miami (OH) | 3 |
| 2020 | 130 | Michigan | 6 |
| 2020 | 127 | Michigan State | 7 |
| 2020 | 135 | Minnesota | 7 |
| 2020 | 167 | New Mexico | 7 |
| 2020 | 166 | New Mexico State | 2 |
| 2020 | 2459 | Northern Illinois | 6 |

### games_bad_week (warning)

Regular-season weeks outside 1 to 16, postseason games not in week 1, or an unknown season type.
2 row(s).

| game_id | season | season_type | week | start_date | home_team | away_team |
|---|---|---|---|---|---|---|
| 401302348 | 2020 | spring_regular | 3 | 2021-02-21T22:00:00.000Z | New Mexico State | Tarleton State |
| 401279078 | 2020 | spring_regular | 5 | 2021-03-07T22:00:00.000Z | New Mexico State | Utah Tech |

### games_neutral_by_season (info)

Neutral-site games per season, so a sudden change stands out.
20 row(s).

| season | season_type | n_neutral | n_games |
|---|---|---|---|
| 2017 | postseason | 36 | 40 |
| 2017 | regular | 27 | 834 |
| 2018 | postseason | 38 | 39 |
| 2018 | regular | 24 | 845 |
| 2019 | postseason | 39 | 40 |
| 2019 | regular | 20 | 848 |
| 2020 | postseason | 26 | 26 |
| 2020 | regular | 9 | 542 |
| 2020 | spring_regular | 2 | 2 |
| 2021 | postseason | 38 | 38 |
| 2021 | regular | 22 | 849 |
| 2022 | postseason | 42 | 42 |
| 2022 | regular | 20 | 854 |
| 2023 | postseason | 40 | 42 |
| 2023 | regular | 23 | 868 |
| 2024 | postseason | 41 | 46 |
| 2024 | regular | 28 | 874 |
| 2025 | postseason | 41 | 46 |
| 2025 | regular | 23 | 888 |
| 2026 | regular | 11 | 888 |

### lines_null_spread (info)

Line rows with no spread (skipped by the pipeline).
Showing the first 25 of 56 rows.

| game_id | provider | season | home_team | away_team |
|---|---|---|---|---|
| 400935282 | consensus | 2017 | Colorado State | Oregon State |
| 400935305 | teamrankings | 2017 | Arizona | Washington State |
| 400935405 | teamrankings | 2017 | Minnesota | Nebraska |
| 400937453 | teamrankings | 2017 | Boston College | Wake Forest |
| 400938669 | teamrankings | 2017 | Louisiana Tech | UTSA |
| 400938887 | consensus | 2017 | Massachusetts | Hawai'i |
| 400941786 | consensus | 2017 | San José State | South Florida |
| 400941824 | teamrankings | 2017 | Houston | Memphis |
| 400945031 | consensus | 2017 | BYU | Portland State |
| 400945299 | teamrankings | 2017 | UNLV | BYU |
| 401012282 | numberfire | 2018 | Texas A&M | UL Monroe |
| 401012293 | numberfire | 2018 | Texas A&M | Arkansas |
| 401012296 | teamrankings | 2018 | Kentucky | South Carolina |
| 401012306 | numberfire | 2018 | Texas A&M | Kentucky |
| 401012337 | numberfire | 2018 | Texas A&M | Ole Miss |
| 401012347 | numberfire | 2018 | Texas A&M | UAB |
| 401012356 | numberfire | 2018 | Texas A&M | LSU |
| 401012887 | Caesars | 2018 | Nebraska | Michigan State |
| 401013036 | consensus | 2018 | Baylor | TCU |
| 401013036 | teamrankings | 2018 | Baylor | TCU |
| 401013323 | teamrankings | 2018 | Texas Tech | Houston |
| 401013329 | teamrankings | 2018 | Minnesota | Fresno State |
| 401013365 | Caesars | 2018 | Massachusetts | Liberty |
| 401013444 | teamrankings | 2018 | Texas State | New Mexico State |
| 401016407 | teamrankings | 2018 | BYU | Utah State |

### lines_providers_per_game (info)

How many sportsbooks quote each game, per season.
Showing the first 25 of 40 rows.

| season | n_providers | n_games |
|---|---|---|
| 2017 | 1 | 97 |
| 2017 | 2 | 35 |
| 2017 | 3 | 741 |
| 2018 | 1 | 94 |
| 2018 | 2 | 67 |
| 2018 | 3 | 44 |
| 2018 | 4 | 664 |
| 2019 | 1 | 107 |
| 2019 | 2 | 4 |
| 2019 | 3 | 8 |
| 2019 | 4 | 447 |
| 2019 | 5 | 315 |
| 2020 | 1 | 19 |
| 2020 | 2 | 14 |
| 2020 | 3 | 1 |
| 2020 | 4 | 49 |
| 2020 | 5 | 399 |
| 2020 | 6 | 85 |
| 2021 | 1 | 12 |
| 2021 | 2 | 8 |
| 2021 | 3 | 99 |
| 2021 | 4 | 625 |
| 2021 | 5 | 143 |
| 2022 | 1 | 11 |
| 2022 | 2 | 67 |

### lines_provider_disagreement (warning)

Games where sportsbooks disagree by more than 7 points.
25 row(s).

| game_id | season | season_type | week | neutral_site | home_team | away_team | n_providers | lowest_spread | highest_spread | gap |
|---|---|---|---|---|---|---|---|---|---|---|
| 401237105 | 2020 | regular | 6 | 0 | LSU | Missouri | 5 | -20.5 | 14 | 34.5 |
| 401677085 | 2024 | postseason | 1 | 0 | UTSA | Coastal Carolina | 3 | -12.5 | 13.5 | 26 |
| 401331447 | 2021 | regular | 14 | 1 | Iowa | Michigan | 4 | -12 | 12 | 24 |
| 401249003 | 2020 | regular | 9 | 0 | New Mexico | San José State | 6 | -13.5 | 9.5 | 23 |
| 401237514 | 2020 | regular | 14 | 0 | Coastal Carolina | BYU | 5 | -11 | 10.5 | 21.5 |
| 401257816 | 2020 | regular | 15 | 0 | UTEP | North Texas | 4 | -10 | 10.5 | 20.5 |
| 401256108 | 2020 | postseason | 1 | 1 | Georgia | Cincinnati | 5 | -9.5 | 9 | 18.5 |
| 401256194 | 2020 | postseason | 1 | 1 | Oklahoma | Florida | 5 | -8.5 | 8.5 | 17 |
| 401237143 | 2020 | regular | 13 | 0 | Missouri | Vanderbilt | 5 | -14.5 | 2 | 16.5 |
| 401761589 | 2025 | regular | 1 | 1 | Charlotte | App State | 3 | 3 | 19.5 | 16.5 |
| 400933837 | 2017 | regular | 1 | 1 | South Carolina | NC State | 3 | -7.5 | 7.5 | 15 |
| 401012680 | 2018 | regular | 1 | 1 | Colorado State | Colorado | 4 | -7 | 7 | 14 |
| 401301056 | 2021 | regular | 15 | 1 | Army | Navy | 4 | -7 | 7 | 14 |
| 401331219 | 2021 | postseason | 1 | 1 | Nevada | Western Michigan | 4 | -6.5 | 7 | 13.5 |
| 400953409 | 2017 | postseason | 1 | 1 | Georgia State | Western Kentucky | 3 | -5 | 7 | 12 |
| 401645331 | 2024 | regular | 5 | 0 | Temple | Army | 3 | 11 | 21.5 | 10.5 |
| 401013117 | 2018 | regular | 3 | 0 | Virginia | Ohio | 4 | -5 | 5 | 10 |
| 401551773 | 2023 | postseason | 1 | 1 | Florida State | Georgia | 3 | 13.5 | 23.5 | 10 |
| 400966332 | 2017 | postseason | 1 | 1 | Utah State | New Mexico State | 3 | -5.5 | 4 | 9.5 |
| 401628374 | 2024 | regular | 5 | 0 | Alabama | Georgia | 3 | -7.5 | 2 | 9.5 |
| 401249033 | 2020 | regular | 14 | 0 | San José State | Hawai'i | 5 | -6 | 3 | 9 |
| 401551749 | 2023 | postseason | 1 | 1 | Oklahoma State | Texas A&M | 3 | -4.5 | 4.5 | 9 |
| 401331239 | 2021 | postseason | 1 | 1 | Ohio State | Utah | 4 | -4.5 | 4 | 8.5 |
| 401643701 | 2024 | regular | 1 | 0 | Troy | Nevada | 3 | -15.5 | -7.5 | 8 |
| 401778316 | 2025 | postseason | 1 | 1 | East Carolina | Pittsburgh | 2 | 6 | 13.5 | 7.5 |

### lines_flipped_sign (warning)

A provider's spread that matches the other books' line for the other team (home and away swapped).
21 row(s).

| game_id | season | season_type | week | neutral_site | home_team | away_team | home_points | away_points | provider | spread | others_median | closing_line |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 400933837 | 2017 | regular | 1 | 1 | South Carolina | NC State | 35 | 28 | consensus | -7.5 | 7.25 | 7 |
| 400953409 | 2017 | postseason | 1 | 1 | Georgia State | Western Kentucky | 27 | 17 | consensus | -5 | 5.75 | 4.5 |
| 400966332 | 2017 | postseason | 1 | 1 | Utah State | New Mexico State | 20 | 26 | consensus | 4 | -5 | -4.5 |
| 401012680 | 2018 | regular | 1 | 1 | Colorado State | Colorado | 13 | 45 | consensus | -7 | 7 | 7 |
| 401013117 | 2018 | regular | 3 | 0 | Virginia | Ohio | 45 | 31 | numberfire | 5 | -5 | -4.75 |
| 401022531 | 2018 | regular | 6 | 0 | Hawai'i | Wyoming | 17 | 13 | numberfire | -2 | 3.5 | 1.25 |
| 401237514 | 2020 | regular | 14 | 0 | Coastal Carolina | BYU | 22 | 17 | Bovada | -11 | 10.5 | 10.5 |
| 401256108 | 2020 | postseason | 1 | 1 | Georgia | Cincinnati | 24 | 21 | Bovada | -7 | 8 | 7.5 |
| 401256108 | 2020 | postseason | 1 | 1 | Georgia | Cincinnati | 24 | 21 | consensus | -9.5 | 8 | 7.5 |
| 401256194 | 2020 | postseason | 1 | 1 | Oklahoma | Florida | 55 | 20 | consensus | 8.5 | -8 | -7.5 |
| 401257816 | 2020 | regular | 15 | 0 | UTEP | North Texas | 43 | 45 | consensus | -10 | 10 | 10 |
| 401301056 | 2021 | regular | 15 | 1 | Army | Navy | 13 | 17 | Bovada | -7 | 7 | 7 |
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
Showing the first 25 of 33 rows.

| game_id | season | week | home_team | away_team | home_points | away_points | n_providers | median_spread | home_margin | miss |
|---|---|---|---|---|---|---|---|---|---|---|
| 401013185 | 2018 | 13 | Duke | Wake Forest | 7 | 59 | 4 | -9.75 | -52 | -61.75 |
| 401404166 | 2022 | 13 | Liberty | New Mexico State | 14 | 49 | 4 | -24 | -35 | -59 |
| 400944877 | 2017 | 12 | Georgia Southern | South Alabama | 52 | 0 | 3 | 6 | 52 | 58 |
| 401760413 | 2025 | 12 | Nevada | San José State | 55 | 10 | 3 | 9.5 | 45 | 54.5 |
| 401249429 | 2020 | 15 | Arizona | Arizona State | 7 | 70 | 5 | 9 | -63 | -54 |
| 401117515 | 2019 | 5 | Nevada | Hawai'i | 3 | 54 | 4 | -2 | -51 | -53 |
| 401112204 | 2019 | 5 | Maryland | Penn State | 0 | 59 | 4 | 6.5 | -59 | -52.5 |
| 400935397 | 2017 | 10 | Iowa | Ohio State | 55 | 24 | 3 | 21 | 31 | 52 |
| 401112509 | 2019 | 12 | Duke | Syracuse | 6 | 49 | 5 | -9 | -43 | -52 |
| 401628978 | 2024 | 3 | Purdue | Notre Dame | 7 | 66 | 3 | 7.5 | -59 | -51.5 |
| 401234576 | 2020 | 1 | Navy | BYU | 3 | 55 | 5 | 1 | -52 | -51 |
| 400935294 | 2017 | 7 | California | Washington State | 37 | 3 | 3 | 16.5 | 34 | 50.5 |
| 400945260 | 2017 | 4 | San José State | Utah State | 10 | 61 | 3 | 1.5 | -51 | -49.5 |
| 401032064 | 2018 | 1 | Army | Houston | 70 | 14 | 4 | -6.5 | 56 | 49.5 |
| 401531919 | 2023 | 12 | Arkansas State | Texas State | 77 | 31 | 2 | 3.25 | 46 | 49.25 |
| 401551737 | 2023 | 1 | Syracuse | South Florida | 0 | 45 | 2 | -4.25 | -45 | -49.25 |
| 401858462 | 2026 | 4 | Maryland | UCLA | 3 | 54 | 2 | 2.5 | -51 | -48.5 |
| 401426593 | 2022 | 9 | Rice | Charlotte | 23 | 56 | 4 | -15 | -33 | -48 |
| 401645380 | 2024 | 14 | Tulsa | Florida Atlantic | 16 | 63 | 3 | -1 | -47 | -48 |
| 401754540 | 2025 | 4 | San Diego State | California | 34 | 0 | 3 | 14 | 34 | 48 |
| 401012814 | 2018 | 12 | Illinois | Iowa | 0 | 63 | 4 | 15.25 | -63 | -47.75 |
| 401215318 | 2020 | 9 | Georgia State | Coastal Carolina | 0 | 51 | 6 | 3.5 | -51 | -47.5 |
| 401403953 | 2022 | 12 | South Carolina | Tennessee | 63 | 38 | 4 | 22.5 | 25 | 47.5 |
| 401643760 | 2024 | 12 | Utah State | Hawai'i | 55 | 10 | 3 | 2.5 | 45 | 47.5 |
| 401013448 | 2018 | 1 | Liberty | Old Dominion | 52 | 10 | 4 | 5 | 42 | 47 |

### lines_provider_accuracy (info)

Average miss of each provider against the final margin, next to the median-of-providers line.
11 row(s).

| provider | n_games | mae | consensus_mae | vs_consensus |
|---|---|---|---|---|
| Caesars Sportsbook (Colorado) | 33 | 11.7 | 11.67 | 0.03 |
| DraftKings | 2837 | 11.91 | 11.89 | 0.02 |
| ESPN Bet | 1838 | 12.06 | 12.04 | 0.03 |
| Bovada | 5326 | 12.15 | 12.14 | 0.01 |
| William Hill (New Jersey) | 2049 | 12.15 | 12.15 | 0 |
| consensus | 4334 | 12.37 | 12.36 | 0 |
| teamrankings | 4401 | 12.37 | 12.37 | 0 |
| numberfire | 2973 | 12.44 | 12.43 | 0.01 |
| Caesars | 1899 | 12.5 | 12.5 | 0 |
| SugarHouse | 92 | 13.14 | 13.16 | -0.02 |
| Caesars (Pennsylvania) | 17 | 17.5 | 17.54 | -0.04 |

### ratings_fbs_team_unrated (warning)

FBS teams with no rating in a snapshot from that source.
Showing the first 25 of 55 rows.

| source | season | week | is_final | team_id | school |
|---|---|---|---|---|---|
| elo | 2020 |  | 1 | 166 | New Mexico State |
| fpi | 2020 |  | 1 | 166 | New Mexico State |
| sp | 2017 |  | 1 | 324 | Coastal Carolina |
| sp | 2017 |  | 1 | 5 | UAB |
| srs | 2020 |  | 1 | 2006 | Akron |
| srs | 2020 |  | 1 | 12 | Arizona |
| srs | 2020 |  | 1 | 9 | Arizona State |
| srs | 2020 |  | 1 | 2050 | Ball State |
| srs | 2020 |  | 1 | 103 | Boston College |
| srs | 2020 |  | 1 | 189 | Bowling Green |
| srs | 2020 |  | 1 | 2084 | Buffalo |
| srs | 2020 |  | 1 | 25 | California |
| srs | 2020 |  | 1 | 2117 | Central Michigan |
| srs | 2020 |  | 1 | 2132 | Cincinnati |
| srs | 2020 |  | 1 | 228 | Clemson |
| srs | 2020 |  | 1 | 38 | Colorado |
| srs | 2020 |  | 1 | 150 | Duke |
| srs | 2020 |  | 1 | 151 | East Carolina |
| srs | 2020 |  | 1 | 2199 | Eastern Michigan |
| srs | 2020 |  | 1 | 52 | Florida State |
| srs | 2020 |  | 1 | 59 | Georgia Tech |
| srs | 2020 |  | 1 | 248 | Houston |
| srs | 2020 |  | 1 | 2309 | Kent State |
| srs | 2020 |  | 1 | 97 | Louisville |
| srs | 2020 |  | 1 | 235 | Memphis |

### ratings_rows_by_snapshot (info)

Rows per snapshot next to the number of FBS teams that season.
Showing the first 25 of 40 rows.

| source | season | week | is_final | n_rows | n_distinct_teams | n_fbs_teams |
|---|---|---|---|---|---|---|
| elo | 2017 |  | 1 | 130 | 130 | 130 |
| elo | 2018 |  | 1 | 130 | 130 | 130 |
| elo | 2019 |  | 1 | 130 | 130 | 130 |
| elo | 2020 |  | 1 | 127 | 127 | 128 |
| elo | 2021 |  | 1 | 130 | 130 | 130 |
| elo | 2022 |  | 1 | 131 | 131 | 131 |
| elo | 2023 |  | 1 | 133 | 133 | 133 |
| elo | 2024 |  | 1 | 134 | 134 | 134 |
| elo | 2025 |  | 1 | 136 | 136 | 136 |
| elo | 2026 | 11 | 0 | 138 | 138 | 138 |
| fpi | 2017 |  | 1 | 130 | 130 | 130 |
| fpi | 2018 |  | 1 | 130 | 130 | 130 |
| fpi | 2019 |  | 1 | 130 | 130 | 130 |
| fpi | 2020 |  | 1 | 127 | 127 | 128 |
| fpi | 2021 |  | 1 | 130 | 130 | 130 |
| fpi | 2022 |  | 1 | 131 | 131 | 131 |
| fpi | 2023 |  | 1 | 133 | 133 | 133 |
| fpi | 2024 |  | 1 | 134 | 134 | 134 |
| fpi | 2025 |  | 1 | 136 | 136 | 136 |
| fpi | 2026 | 11 | 0 | 138 | 138 | 138 |
| sp | 2017 |  | 1 | 128 | 128 | 130 |
| sp | 2018 |  | 1 | 130 | 130 | 130 |
| sp | 2019 |  | 1 | 130 | 130 | 130 |
| sp | 2020 |  | 1 | 128 | 128 | 128 |
| sp | 2021 |  | 1 | 130 | 130 | 130 |

### teams_conference_change (info)

Teams that changed conference from one season to the next (real realignment).
Showing the first 25 of 42 rows.

| team_id | school | from_season | from_conference | to_season | to_conference |
|---|---|---|---|---|---|
| 166 | New Mexico State | 2017 | Sun Belt | 2018 | FBS Independents |
| 87 | Notre Dame | 2019 | FBS Independents | 2020 | ACC |
| 87 | Notre Dame | 2020 | ACC | 2021 | FBS Independents |
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

### returning_out_of_range (warning)

Returning-production shares below 0 or above 1 (the model pulls them back into range).
22 row(s).

| season | team_id | school | percent_ppa |
|---|---|---|---|
| 2017 | 2628 | TCU | 1.014 |
| 2017 | 154 | Wake Forest | 1.094 |
| 2018 | 2429 | Charlotte | 1.194 |
| 2018 | 2050 | Ball State | 1.271 |
| 2019 | 135 | Minnesota | 1.004 |
| 2019 | 2572 | Southern Miss | 1.042 |
| 2020 | 113 | Massachusetts | -0.056 |
| 2020 | 151 | East Carolina | 1.001 |
| 2020 | 2006 | Akron | 1.511 |
| 2021 | 113 | Massachusetts | -3.1 |
| 2021 | 151 | East Carolina | 1.001 |
| 2021 | 2247 | Georgia State | 1.002 |
| 2021 | 2638 | UTEP | 1.051 |
| 2021 | 238 | Vanderbilt | 1.056 |
| 2021 | 2229 | Florida International | 1.6 |
| 2021 | 166 | New Mexico State | 1.7 |
| 2022 | 189 | Bowling Green | 1.038 |
| 2023 | 2305 | Kansas | 1.003 |
| 2026 | 113 | Massachusetts | -0.567 |
| 2026 | 189 | Bowling Green | -0.062 |
| 2026 | 2638 | UTEP | -0.011 |
| 2026 | 2084 | Buffalo | -0.008 |

### preseason_missing_by_season (info)

FBS teams with no talent or no returning-production value, per season (they count as average).
10 row(s).

| season | n_fbs_teams | n_no_talent | n_no_returning |
|---|---|---|---|
| 2017 | 130 | 0 | 2 |
| 2018 | 130 | 0 | 1 |
| 2019 | 130 | 0 | 0 |
| 2020 | 128 | 0 | 0 |
| 2021 | 130 | 0 | 2 |
| 2022 | 131 | 0 | 1 |
| 2023 | 133 | 0 | 2 |
| 2024 | 134 | 0 | 1 |
| 2025 | 136 | 2 | 2 |
| 2026 | 138 | 0 | 2 |

