_Generated file: written by scripts/disagreement.R on 2026-11-11. Do not edit by hand; rerun the script._

# When a model and the sportsbooks disagree, which side covers?

This is a record of what happened in past games. It is not betting advice.

## How to read it

Say a model has Utah by 4.5 at Arizona and the sportsbook has Utah by 2.5. The gap is 2 points.
The model's side is Utah giving 2.5. The sportsbook's side is Arizona getting 2.5.
Each table counts how often the sportsbook's side covered in games with a gap that size.

- **Games.** 6,052 FBS games with a closing line, 2018, 2019 and 2021 to 2025 and 2026. Each game is predicted by a model fitted without that game's season (the 2026 season by a fit on the earlier ones), so no number here has seen the result.
- **Closing line.** The median spread across sportsbooks.
- **Break-even.** At the usual price of -110 you need to win 52.4% to break even. "Return per $100" is the average profit or loss per $100 risked at that price.
- **95% interval.** The range the true rate plausibly sits in, given the number of games. If it includes 50%, the result is not distinguishable from a coin flip.
- **Pushes** (the result lands exactly on the line) are left out of the percentages.

## The short answer

When our testable model and the closing line were 3 or more points apart, the sportsbook's side covered 50.9% of the time (2,512 games, 95% interval 48.9% to 52.8%). That is below the 52.4% needed to break even at -110.

## 1. Each model against the closing line

| Model | Gap (points) | Games | Book side W-L-push | Book side covers | 95% interval | Model side covers | Book side return per $100 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Elo and Power average (our testable model) | 2 or more | 3,563 | 1791-1717-55 | 51.1% | 49.4% to 52.7% | 48.9% | -2.5 |
| Elo and Power average (our testable model) | 3 or more | 2,512 | 1257-1214-41 | 50.9% | 48.9% to 52.8% | 49.1% | -2.9 |
| Elo and Power average (our testable model) | 4 or more | 1,713 | 862-823-28 | 51.2% | 48.8% to 53.5% | 48.8% | -2.3 |
| Elo and Power average (our testable model) | 5 or more | 1,139 | 586-532-21 | 52.4% | 49.5% to 55.3% | 47.6% | +0.1 |
| Elo and Power average (our testable model) | 7 or more |   446 | 226-212-8 | 51.6% | 46.9% to 56.2% | 48.4% | -1.5 |
| Elo and Power average (our testable model) | 10 or more |    99 | 56-42-1 | 57.1% | 47.3% to 66.5% | 42.9% | +9.1 |
| Elo | 2 or more | 3,944 | 1965-1917-62 | 50.6% | 49.0% to 52.2% | 49.4% | -3.4 |
| Elo | 3 or more | 3,033 | 1508-1478-47 | 50.5% | 48.7% to 52.3% | 49.5% | -3.6 |
| Elo | 4 or more | 2,261 | 1120-1104-37 | 50.4% | 48.3% to 52.4% | 49.6% | -3.9 |
| Elo | 5 or more | 1,628 | 830-772-26 | 51.8% | 49.4% to 54.2% | 48.2% | -1.1 |
| Elo | 7 or more |   793 | 400-378-15 | 51.4% | 47.9% to 54.9% | 48.6% | -1.8 |
| Elo | 10 or more |   229 | 116-107-6 | 52.0% | 45.5% to 58.5% | 48.0% | -0.7 |
| Power | 2 or more | 3,796 | 1902-1830-64 | 51.0% | 49.4% to 52.6% | 49.0% | -2.7 |
| Power | 3 or more | 2,820 | 1403-1366-51 | 50.7% | 48.8% to 52.5% | 49.3% | -3.3 |
| Power | 4 or more | 2,009 | 1010-964-35 | 51.2% | 49.0% to 53.4% | 48.8% | -2.3 |
| Power | 5 or more | 1,435 | 721-690-24 | 51.1% | 48.5% to 53.7% | 48.9% | -2.4 |
| Power | 7 or more |   670 | 353-307-10 | 53.5% | 49.7% to 57.3% | 46.5% | +2.1 |
| Power | 10 or more |   212 | 105-102-5 | 50.7% | 44.0% to 57.5% | 49.3% | -3.2 |

## 2. The same games in separate bands (our testable model)

Section 1 counts every game at or past each gap. This table splits them so each game is in one row.

| Gap band (points) | Games | Book side W-L-push | Book side covers | 95% interval | Model side covers | Book side return per $100 |
| --- | --- | --- | --- | --- | --- | --- |
| Under 1 | 1,298 | 657-610-31 | 51.9% | 49.1% to 54.6% | 48.1% | -1.0 |
| 1 to 2 | 1,191 | 567-605-19 | 48.4% | 45.5% to 51.2% | 51.6% | -7.6 |
| 2 to 3 | 1,051 | 534-503-14 | 51.5% | 48.5% to 54.5% | 48.5% | -1.7 |
| 3 to 4 |   799 | 395-391-13 | 50.3% | 46.8% to 53.7% | 49.7% | -4.1 |
| 4 to 5 |   574 | 276-291-7 | 48.7% | 44.6% to 52.8% | 51.3% | -7.1 |
| 5 to 7 |   693 | 360-320-13 | 52.9% | 49.2% to 56.7% | 47.1% | +1.1 |
| 7 or more |   446 | 226-212-8 | 51.6% | 46.9% to 56.2% | 48.4% | -1.5 |

## 3. Against each sportsbook's own closing line (our testable model)

| Sportsbook (seasons) | Gap (points) | Games | Book side W-L-push | Book side covers | 95% interval | Model side covers | Book side return per $100 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DraftKings (2023 to 2026) | 2 or more | 1,634 | 811-794-29 | 50.5% | 48.1% to 53.0% | 49.5% | -3.5 |
| DraftKings (2023 to 2026) | 3 or more | 1,154 | 574-557-23 | 50.8% | 47.8% to 53.7% | 49.2% | -3.1 |
| DraftKings (2023 to 2026) | 4 or more |   777 | 376-384-17 | 49.5% | 45.9% to 53.0% | 50.5% | -5.6 |
| DraftKings (2023 to 2026) | 5 or more |   509 | 250-247-12 | 50.3% | 45.9% to 54.7% | 49.7% | -4.0 |
| Bovada (2019 to 2026) | 2 or more | 2,827 | 1410-1360-57 | 50.9% | 49.0% to 52.8% | 49.1% | -2.8 |
| Bovada (2019 to 2026) | 3 or more | 2,016 | 1000-974-42 | 50.7% | 48.5% to 52.9% | 49.3% | -3.3 |
| Bovada (2019 to 2026) | 4 or more | 1,386 | 703-652-31 | 51.9% | 49.2% to 54.5% | 48.1% | -1.0 |
| Bovada (2019 to 2026) | 5 or more |   926 | 479-428-19 | 52.8% | 49.6% to 56.0% | 47.2% | +0.8 |
| ESPN Bet (2023 to 2025) | 2 or more | 1,063 | 549-514-0 | 51.6% | 48.6% to 54.6% | 48.4% | -1.4 |
| ESPN Bet (2023 to 2025) | 3 or more |   736 | 375-361-0 | 51.0% | 47.3% to 54.5% | 49.0% | -2.7 |
| ESPN Bet (2023 to 2025) | 4 or more |   507 | 254-253-0 | 50.1% | 45.8% to 54.4% | 49.9% | -4.4 |
| ESPN Bet (2023 to 2025) | 5 or more |   332 | 168-164-0 | 50.6% | 45.2% to 55.9% | 49.4% | -3.4 |

## 4. Each model against the opening line

The opening line is the first number a book posted, usually early in the week. Here the bet is graded against that opening number, as if it were placed then. Openers are in the data from 2021 (Bovada), 2023 (DraftKings) and 2024 (ESPN Bet): 4,488 games.

| Model | Gap (points) | Games | Book side W-L-push | Book side covers | 95% interval | Model side covers | Book side return per $100 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Elo and Power average (our testable model) | 2 or more | 2,495 | 1212-1250-33 | 49.2% | 47.3% to 51.2% | 50.8% | -6.0 |
| Elo and Power average (our testable model) | 3 or more | 1,785 | 874-892-19 | 49.5% | 47.2% to 51.8% | 50.5% | -5.5 |
| Elo and Power average (our testable model) | 4 or more | 1,186 | 563-610-13 | 48.0% | 45.1% to 50.9% | 52.0% | -8.4 |
| Elo and Power average (our testable model) | 5 or more |   775 | 369-397-9 | 48.2% | 44.7% to 51.7% | 51.8% | -8.0 |
| Elo | 2 or more | 2,891 | 1412-1442-37 | 49.5% | 47.6% to 51.3% | 50.5% | -5.5 |
| Elo | 3 or more | 2,162 | 1058-1072-32 | 49.7% | 47.6% to 51.8% | 50.3% | -5.2 |
| Elo | 4 or more | 1,560 | 762-777-21 | 49.5% | 47.0% to 52.0% | 50.5% | -5.5 |
| Elo | 5 or more | 1,123 | 554-558-11 | 49.8% | 46.9% to 52.8% | 50.2% | -4.9 |
| Power | 2 or more | 2,706 | 1327-1335-44 | 49.8% | 48.0% to 51.7% | 50.2% | -4.8 |
| Power | 3 or more | 2,007 | 967-1005-35 | 49.0% | 46.8% to 51.2% | 51.0% | -6.4 |
| Power | 4 or more | 1,455 | 707-724-24 | 49.4% | 46.8% to 52.0% | 50.6% | -5.7 |
| Power | 5 or more | 1,032 | 501-514-17 | 49.4% | 46.3% to 52.4% | 50.6% | -5.8 |

## 5. Does the line move toward the model?

If a model knows something the opening line does not, the line should drift toward the model by kickoff.

| Gap from the opening line (points) | Games | Lines that moved toward the model, of those that moved | Average move toward the model (points) |
| --- | --- | --- | --- |
| 2 or more | 2,495 | 59.0% | +0.42 |
| 3 or more | 1,785 | 60.6% | +0.50 |
| 4 or more | 1,186 | 60.9% | +0.59 |
| 5 or more |   775 | 63.7% | +0.73 |

## 6. Gaps of 3 or more, sliced (our testable model, closing line)

| Slice | Games | Book side W-L-push | Book side covers | 95% interval | Model side covers | Book side return per $100 |
| --- | --- | --- | --- | --- | --- | --- |
| All games | 2,512 | 1257-1214-41 | 50.9% | 48.9% to 52.8% | 49.1% | -2.9 |
| Weeks 1 to 4 |   808 | 406-389-13 | 51.1% | 47.6% to 54.5% | 48.9% | -2.5 |
| Week 5 on, and bowls | 1,704 | 851-825-28 | 50.8% | 48.4% to 53.2% | 49.2% | -3.1 |
| Model likes the favorite more than the book does |   751 | 379-360-12 | 51.3% | 47.7% to 54.9% | 48.7% | -2.1 |
| Model likes the underdog more than the book does | 1,761 | 878-854-29 | 50.7% | 48.3% to 53.0% | 49.3% | -3.2 |
| Model likes the home team more | 1,292 | 633-634-25 | 50.0% | 47.2% to 52.7% | 50.0% | -4.6 |
| Model likes the away team more | 1,220 | 624-580-16 | 51.8% | 49.0% to 54.6% | 48.2% | -1.1 |
| Elo and Power both 3 or more off, same side | 1,363 | 693-649-21 | 51.6% | 49.0% to 54.3% | 48.4% | -1.4 |
| 2018 |   303 | 154-145-4 | 51.5% | 45.9% to 57.1% | 48.5% | -1.7 |
| 2019 |   347 | 175-167-5 | 51.2% | 45.9% to 56.4% | 48.8% | -2.3 |
| 2021 |   305 | 153-147-5 | 51.0% | 45.4% to 56.6% | 49.0% | -2.6 |
| 2022 |   326 | 151-171-4 | 46.9% | 41.5% to 52.3% | 53.1% | -10.5 |
| 2023 |   332 | 173-153-6 | 53.1% | 47.6% to 58.4% | 46.9% | +1.3 |
| 2024 |   337 | 160-170-7 | 48.5% | 43.1% to 53.9% | 51.5% | -7.4 |
| 2025 |   307 | 167-134-6 | 55.5% | 49.8% to 61.0% | 44.5% | +5.9 |
| 2026 |   255 | 124-127-4 | 49.4% | 43.3% to 55.5% | 50.6% | -5.7 |

## 7. All five systems, from the predictions saved each week

SP+, FPI and SRS cannot be tested on past seasons: the only past ratings available are end-of-season ones, which already include the results. So they are graded from the predictions the app saves every week before kickoff, against the line saved with them. This table grows through the season.

No saved predictions have been played yet (67 waiting for results).
