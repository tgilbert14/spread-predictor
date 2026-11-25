_Generated file: written by scripts/refresh.R on 2026-11-25. Do not edit by hand; it is rewritten on every refresh._

# What we have learned about the playoff committee

Season 2026. The weights below start from what earlier committees did and are pulled toward this season's emphasis by its rankings (4 so far). The lessons come from this season's rankings alone.

## What it has done this season

- **A loss costs about 5 places.** 23 ranked teams have lost between rankings. The biggest fall: Kentucky, from No. 16 to unranked in week 13. 7 dropped out of the 25.
- **A close loss to a top team can cost nothing.** Arizona lost to No. 2 Utah by 1 and went from No. 23 to No. 19 in week 12.
- **Teams that do not lose move up about 2 places on average, mostly into gaps left by teams that lost.** The biggest climb without a loss: Oregon, from No. 23 to No. 16 in week 11.
- **A No. 1 that wins has stayed No. 1.** Georgia won and kept the top spot in week 12. Miami lost as No. 1 and fell to No. 7.
- **An unbeaten record does not settle it.** In week 13, unbeaten Utah is No. 2, behind 1 team with a loss, including Georgia.
- **Looking strong is not enough without the record.** We rate Ohio State No. 6 on who would win. With 4 losses, the committee has it No. 21 in week 13.
- **Head-to-head does not always decide it.** In week 13, No. 19 Louisville is ahead of No. 22 Ole Miss, which beat it.
- **Most ranked teams move 3 places or fewer from one ranking to the next.** Of the teams ranked in back-to-back rankings, 41 of 68 did. In week 13, Georgia, Utah and Miami kept the exact same spot.

## The weights behind the prediction

A positive weight moves a team up. They are in each input's own units, so sizes do not compare directly.

### Week to week (once the committee has ranked)

Learned from 3 rankings.

| Input | Weight |
|---|---|
| total losses | -1.186 |
| strength of record | +0.576 |
| how strong the team looks | +0.093 |
| playing in a power conference | +2.370 |
| its place in the last ranking | +0.448 |
| being ranked last time at all | +2.308 |
| losing since the last ranking | -1.681 |
| the quality of its wins since the last ranking | +3.409 |
| being No. 1 last time and not losing since | +1.951 |
| winning its conference title game | -0.136 |
| wins over teams in the last ranking | +0.463 |

### From resumes alone (before its first ranking)

Learned from 4 rankings.

| Input | Weight |
|---|---|
| total losses | -1.167 |
| strength of record | +2.360 |
| how strong the team looks | +0.223 |
| playing in a power conference | +3.014 |

## Rules applied after the scores

- **Head-to-head in small groups.** A team goes above one it beat when both are within 3 places of each other and their scores are within 2.
- **Winners stay close to where they were.** A ranked team that played and won since the last ranking drops at most 1 place. A team on a bye can still drop.

## How our predictions have done

| Week | Places off | Exactly right | Their 25 | Their top 12 | Made |
|---|---|---|---|---|---|
| 10 | 2.6 | 2 | 22 of 25 | 10 of 12 | after the release |
| 11 | 1.8 | 4 | 24 of 25 | 11 of 12 | after the release |
| 12 | 1.6 | 6 | 23 of 25 | 12 of 12 | after the release |
| 13 | 1.2 | 9 | 23 of 25 | 12 of 12 | before the release |

**Week 10, biggest misses:** Texas (we said 14, they said 7); South Carolina (we said 27, they said 21); Oregon (we said 29, they said 23).

**Week 11, biggest misses:** South Carolina (we said 22, they said 17); Ole Miss (we said 14, they said 19); Indiana (we said 5, they said 9).

**Week 12, biggest misses:** Arizona (we said 27, they said 19); Oklahoma (we said 28, they said 22); Ole Miss (we said 20, they said 25).

**Week 13, biggest misses:** Washington (we said 29, they said 24); Texas Tech (we said 8, they said 11); Missouri (we said 26, they said 23).

