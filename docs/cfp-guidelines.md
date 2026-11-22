# The playoff committee in 2026: rules, metrics and what they mean here

Notes from public reporting, gathered November 22, 2026. The CFP's and
ESPN's own pages could not be read from the machine this was written on,
so everything below comes from search results that quote them. Where
sources disagree, it says so. Check collegefootballplayoff.com before
relying on any one detail.

## The format for 2026-27

- **12 teams, the last 12-team playoff.** The field grows to 24 teams next
  season.
- **Automatic bids changed this year.** The four Power Four champions (ACC,
  Big Ten, Big 12, SEC) get in whatever their ranking. One more bid goes to
  the highest-ranked team from the American, Conference USA, the MAC, the
  Mountain West, the Pac-12 and the Sun Belt (it does not have to be a
  champion). Notre Dame gets in if it ranks in the top 12. The highest-ranked
  remaining teams fill the rest. In 2025 the bids went to the five
  highest-ranked champions instead. Some older articles still describe that.
- **Seeding is straight from the final ranking**, since 2025. Seeds 1 to 4
  get byes, seeds 5 to 8 host 9 to 12, and there is no reseeding.
- **Six rankings:** starting Tuesday, Nov. 3, and ending on Selection Day,
  Sunday, Dec. 6.

## What the committee says it weighs

- A team's whole body of work, judged by 13 people from video, data and
  conference input. No single metric decides it, and the protocol does not
  weight its factors.
- **To separate teams that look comparable:** strength of schedule,
  head-to-head results, results against common opponents, and key players
  or coaches who were unavailable.
- **Scoring margin does come up.** Explaining Alabama at No. 3 this month,
  chair Hunter Yurachek cited its average margin in conference wins (about
  23 points) and its scoring defense, and "consistent play" over Texas.

## The metrics it uses

- **Strength of schedule, reworked in 2025** to give more weight to games
  against strong opponents.
- **Record strength, added in 2025.** It rewards beating good teams and
  goes easy on losing to them. Reporting describes it as codifying what the
  committee already did.
- **Strength of Conference Enhancement, new in 2026.** Pushed for by the SEC
  after it moved to nine conference games. Its formula is not public. The
  Athletic describes it as average conference-opponent strength, used mainly
  to compare teams in the same league. ESPN first described it as a measure
  of conference strength, then clarified.
- The committee has said publishing its roughly 30 metrics "isn't really
  feasible."
- **Reported effect so far:** through the first three 2026 rankings, the
  committee had SEC teams a combined 41 places higher than the AP poll did,
  the largest gap on record. The committee denies a conference bias.

## What this means for our committee prediction

- **Our "record strength" is close to theirs.** Ours is wins minus what a
  top-10 team would expect against the same schedule, so a loss to a strong
  team costs little and a loss to a weak one costs a lot. That matches how
  the CFP's 2025 metric is described.
- **We tested a Strength of Conference input and an SEC input** against this
  season's three rankings (Nov. 22). Both learned weights near zero and did
  not change the predictions. Record strength already reflects tougher
  conference schedules. Worth testing again after the next two rankings.
- **Margin of victory** reaches our model through the Power rating, which is
  built from scores and success rate. Its learned weight is small so far.
- **What we cannot see:** head-to-head, common opponents, injuries, and
  conference titles. Conference titles matter most for the last ranking.

## Ideas for the project

1. **A projected playoff field.** Built Nov. 22: the Rankings tab applies
   the bid rules to our predicted ranking (`R/playoff.R`).
2. **A conference-champion input for Selection Day.** Built Nov. 22. Title
   games are found by date, the winners take the Power Four bids in the
   projected field, and the committee model has a title-game input. Past
   committees gave the title itself little credit beyond the win.
3. **Plan for 24 teams next season.** The bid rules will change again. They
   live in one place, `PLAYOFF` in `R/config.R`.
4. **Keep the "what the committee has done" lessons honest.** If the SEC gap
   or the new conference metric starts to show in our misses, the notes file
   (`docs/committee-notes.md`) will show it first.

## Sources

- [CFP Selection Committee Prepares for 2026-27 Season (CFP)](https://collegefootballplayoff.com/news/2026/8/6/sc-aug-2627)
- [CFP Selection Committee 101 (CFP)](https://collegefootballplayoff.com/news/2026/11/2/cfp-sc-101)
- [CFP Selection Committee Completes Its Third Rankings of 2026 (CFP)](https://collegefootballplayoff.com/news/2026/11/17/rankings)
- [Selection Committee Protocol (CFP)](https://collegefootballplayoff.com/sports/2016/10/24/selection-committee-protocol)
- [CFP selection committee to use enhanced metrics (ESPN)](https://www.espn.com/college-football/story/_/id/46027603/cfp-selection-committee-use-enhanced-metrics)
- [How the College Football Playoff automatic qualifiers work (NCAA.com)](https://www.ncaa.com/news/football/article/2026-02-03/how-college-football-playoff-automatic-qualifiers-work-byes-seeds)
- [How the 12-team College Football Playoff will work (NCAA.com)](https://www.ncaa.com/news/football/article/2026-02-03/how-12-team-college-football-playoff-will-work-teams-schedule-bids)
- [CFP Selection Committee Protocol Explained (Sports Illustrated)](https://www.si.com/fannation/college/cfb-hq/news/cfp-selection-committee-protocol-explained-how-12-team-playoff-field-gets-picked-2026)
- [Data shows the CFP committee is boosting the SEC more than ever (CBS Sports)](https://www.cbssports.com/college-football/news/cfp-committee-boosting-sec/)
- [Heather Dinich clarifies CFP committee's "new metric" (Awful Announcing)](https://awfulannouncing.com/college-football/heather-dinich-clarifies-college-football-playoff-committee-new-metric.html)
- [CFP committee says public release of its 30 metrics "isn't really feasible" (via Fox News)](https://tippahnews.com/mississippi-news/cfp-committee-says-public-release-of-its-30-metrics-isnt-really-feasible-fox-news-reports)
- [Hunter Yurachek explains Alabama staying put at No. 3 (247Sports)](https://247sports.com/college/alabama/article/cfp-committee-chair-hunter-yurachek-explains-alabama-staying-put-at-no-3-in-latest-cfp-ranking-release-292915413/)
