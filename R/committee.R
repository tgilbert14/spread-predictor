# Learning how the playoff committee ranks teams, from its own rankings.
#
# Every time the committee releases a ranking, it shows what it values: each
# pair of teams it put in order is a small piece of evidence. This file turns
# those pairs into weights on a handful of inputs, uses the weights to
# predict the next ranking, and puts what was learned into plain words.
#
# The committee's ingredients stay much the same from year to year, but how
# much each one counts can change (it did for 2026). So the weights start
# from what earlier committees did (scripts/committee_prior.R, 2018 to 2025)
# and every ranking of the current season pulls them toward its own
# emphasis. The weights a season ends with are saved
# (data/committee_learned.json) and are where the next season starts.
#
# A prediction for a week only ever learns from rankings released before it.

# What a team's resume says on its own, and what is added once the committee
# has a previous ranking to start from.
RESUME_INPUTS <- c("losses", "record_strength", "power", "tier")
UPDATE_INPUTS <- c(RESUME_INPUTS, "prev_points", "was_ranked", "new_losses", "strength_gain", "held_top", "conf_champ", "ranked_wins")

# How hard the fit is held toward its starting weights. A few rankings are
# not much to learn from, so the start counts until the season's evidence
# is strong. Tested from 3 to 100 on 2026's rankings with little difference.
COMMITTEE_RIDGE <- 10

# Two habits of the committee that a score per team cannot show, applied to
# the order after scoring (committee_order()). Tested a season at a time on
# 2018 to 2025 and 2026: the average miss went from 1.36 to 1.31 places and
# no season got worse (docs/research-log.md, Nov. 22).
COMMITTEE_RULES <- list(
  # A ranked team that played and won since the last ranking drops at most
  # this many places. Of 667 such teams since 2018, 9 dropped 2 or more.
  max_drop_after_win = 1,
  # A team goes above one it beat head to head when it is placed right
  # below it and their scores are this close (about two places).
  head_to_head_gap = 1
)

INPUT_LABELS <- c(
  losses = "total losses", record_strength = "strength of record", power = "how strong the team looks",
  tier = "playing in a power conference", prev_points = "its place in the last ranking",
  was_ranked = "being ranked last time at all", new_losses = "losing since the last ranking",
  strength_gain = "the quality of its wins since the last ranking",
  held_top = "being No. 1 last time and not losing since",
  conf_champ = "winning its conference title game",
  ranked_wins = "wins over teams in the last ranking"
)

#' Everything the fit knows about each team going into a week.
#'
#' @return One row per team with a resume: team_id, the resume inputs,
#'   prev_cfp (its place in the committee's last ranking, NA if unranked or
#'   there was none) and the update inputs (all 0 when there is no previous
#'   ranking). Attribute "previous" is the week of that ranking, or NA.
#'   NULL when no games have been played.
committee_inputs <- function(app_data, week) {
  resumes <- week_resumes(app_data, week)
  if (is.null(resumes)) return(NULL)
  out <- resumes[c("team_id", RESUME_INPUTS)]
  released <- app_data$polls[app_data$polls$poll == "cfp" & app_data$polls$week < week, , drop = FALSE]
  previous <- if (nrow(released) > 0) max(released$week) else NA_integer_
  before <- if (is.na(previous)) NULL else week_resumes(app_data, previous)
  if (is.null(before)) {
    previous <- NA_integer_
    out$prev_cfp <- NA_integer_
    out$new_losses <- 0
    out$strength_gain <- 0
  } else {
    last <- released[released$week == previous, , drop = FALSE]
    out$prev_cfp <- last$rank[match(out$team_id, last$team_id)]
    then <- match(out$team_id, before$team_id)
    out$new_losses <- ifelse(is.na(then), 0, resumes$losses - before$losses[then])
    out$strength_gain <- ifelse(is.na(then), 0, resumes$record_strength - before$record_strength[then])
  }
  # Wins over teams in the committee's last ranking. When two close teams
  # never played each other, the committee says it looks at results against
  # ranked teams.
  games <- app_data$results[app_data$results$week < week, , drop = FALSE]
  home_won <- games$home_points > games$away_points
  winner <- ifelse(home_won, games$home_id, games$away_id)
  loser <- ifelse(home_won, games$away_id, games$home_id)
  if (is.null(before)) {
    out$ranked_wins <- 0
    out$won_since <- 0
  } else {
    beat_ranked <- winner[loser %in% last$team_id]
    out$ranked_wins <- as.numeric(table(factor(beat_ranked, levels = out$team_id)))
    # Not a fit input: committee_order() uses it to keep winners in place.
    out$won_since <- as.numeric(out$team_id %in% winner[games$week >= previous])
  }
  out$prev_points <- ifelse(is.na(out$prev_cfp), 0, 26 - out$prev_cfp)
  out$was_ranked <- as.numeric(!is.na(out$prev_cfp))
  # The committee has kept a No. 1 that keeps winning, even past a team
  # whose resume looked a little better. This lets the fit learn that.
  out$held_top <- as.numeric(out$prev_cfp %in% 1L & out$new_losses == 0)
  # Title games come the weekend before Selection Day, so this only counts
  # in the final ranking. Losing one already shows up in new_losses.
  played <- app_data$results[app_data$results$week < week, , drop = FALSE]
  out$conf_champ <- as.numeric(out$team_id %in% conference_champions(played, app_data$teams)$team_id)
  attr(out, "previous") <- previous
  attr(out, "beat") <- data.frame(winner = winner, loser = loser)
  out
}

#' The pairs one ranking puts in order, as differences in the inputs.
#'
#' Each ranked team is paired with every team ranked below it and with the
#' 25 best unranked teams by record strength. Every row is "the team the
#' committee preferred, minus the other one".
#'
#' @param inputs What committee_inputs() returns for that week.
#' @param ranking Rows of rank and team_id: the committee's ranking.
committee_pairs <- function(inputs, ranking, features) {
  inputs$cfp <- ranking$rank[match(inputs$team_id, ranking$team_id)]
  ranked <- inputs[!is.na(inputs$cfp), , drop = FALSE]
  ranked <- ranked[order(ranked$cfp), , drop = FALSE]
  rest <- inputs[is.na(inputs$cfp), , drop = FALSE]
  rest <- rest[order(-rest$record_strength), , drop = FALSE]
  pool <- rbind(ranked, utils::head(rest, 25))
  n <- nrow(ranked)
  if (n == 0 || nrow(pool) < 2) return(matrix(numeric(), 0, length(features), dimnames = list(NULL, features)))
  better <- rep(seq_len(n), times = nrow(pool) - seq_len(n))
  worse <- unlist(lapply(seq_len(n), function(i) seq_len(nrow(pool))[-seq_len(i)]))
  as.matrix(pool[better, features, drop = FALSE]) - as.matrix(pool[worse, features, drop = FALSE])
}

#' Weights that best put the committee's pairs in its order.
#'
#' A logistic fit on the pair differences, held back by COMMITTEE_RIDGE. It
#' is held toward `prior` when there is one (last season's weights) and
#' toward zero otherwise. Inputs are put on one scale for the fit so the
#' holding back treats them alike. The weights come back in the inputs' own
#' units.
#'
#' @param pairs What committee_pairs() returns, rows from every ranking used.
#' @param prior Named weights in the inputs' own units, or NULL.
fit_committee_weights <- function(pairs, prior = NULL, ridge = COMMITTEE_RIDGE) {
  features <- colnames(pairs)
  scale <- apply(pairs, 2, stats::sd)
  scale[!is.finite(scale) | scale == 0] <- 1
  d <- sweep(pairs, 2, scale, "/")
  toward <- if (is.null(prior)) rep(0, length(features)) else unname(prior[features]) * scale
  toward[is.na(toward)] <- 0  # an input newer than the prior starts at zero
  loss <- function(b) sum(log1p(exp(-drop(d %*% b)))) + ridge * sum((b - toward)^2)
  slope <- function(b) drop(-crossprod(d, 1 / (1 + exp(drop(d %*% b))))) + 2 * ridge * (b - toward)
  fit <- stats::optim(toward, loss, slope, method = "BFGS")
  stats::setNames(fit$par / scale, features)
}

#' What the committee's rankings before a week have taught us.
#'
#' @param prior list(resume = , update = ): last season's weights, or NULL.
#' @return list(resume, update): weights, or NULL for a model with nothing
#'   to learn from yet and no prior. n_resume and n_update count the
#'   rankings each was learned from.
learn_committee <- function(app_data, before_week, prior = app_data$committee_prior) {
  released <- app_data$polls[app_data$polls$poll == "cfp" & app_data$polls$week < before_week, , drop = FALSE]
  resume_pairs <- list()
  update_pairs <- list()
  for (week in sort(unique(released$week))) {
    inputs <- committee_inputs(app_data, week)
    if (is.null(inputs)) next
    ranking <- released[released$week == week, , drop = FALSE]
    resume_pairs[[length(resume_pairs) + 1]] <- committee_pairs(inputs, ranking, RESUME_INPUTS)
    if (!is.na(attr(inputs, "previous"))) {
      update_pairs[[length(update_pairs) + 1]] <- committee_pairs(inputs, ranking, UPDATE_INPUTS)
    }
  }
  learned <- function(pairs, old) {
    if (length(pairs) == 0) return(old)
    fit_committee_weights(do.call(rbind, pairs), old)
  }
  list(resume = learned(resume_pairs, prior$resume), update = learned(update_pairs, prior$update),
       n_resume = length(resume_pairs), n_update = length(update_pairs))
}

#' Our prediction of the committee's ranking for one week.
#'
#' Three stages, depending on what there is to go on:
#'   "update"  the committee has a previous ranking this season and we have
#'             learned how it moves teams week to week: start from that
#'             ranking and adjust.
#'   "resume"  we have learned what it rewards, but there is no previous
#'             ranking to start from (or no week-to-week lesson yet).
#'   "record"  nothing learned yet: teams in order of record strength.
#'
#' @return Every team with a resume, best first: rank, team_id, score,
#'   prev_cfp and method. No rows when no games have been played.
committee_forecast <- function(app_data, week = app_data$meta$forecast_week,
                               prior = app_data$committee_prior) {
  empty <- data.frame(rank = integer(), team_id = integer(), score = numeric(), prev_cfp = integer(),
                      method = character(), stringsAsFactors = FALSE)
  if (length(week) != 1 || is.na(week)) return(empty)
  inputs <- committee_inputs(app_data, week)
  if (is.null(inputs)) return(empty)
  learned <- learn_committee(app_data, week, prior)
  if (!is.na(attr(inputs, "previous")) && !is.null(learned$update)) {
    score <- committee_score(inputs, learned$update)
    method <- "update"
  } else if (!is.null(learned$resume)) {
    score <- committee_score(inputs, learned$resume)
    method <- "resume"
  } else {
    score <- inputs$record_strength
    method <- "record"
  }
  order <- if (method == "update") committee_order(inputs, score) else order(-score)
  out <- data.frame(rank = match(seq_along(score), order), team_id = inputs$team_id,
                    score = score, prev_cfp = as.integer(inputs$prev_cfp), method = method,
                    stringsAsFactors = FALSE)
  out <- out[order(out$rank), , drop = FALSE]
  rownames(out) <- NULL
  out
}

#' The order of teams from their scores, with the committee's habits
#' (COMMITTEE_RULES) applied: head-to-head between neighbors with close
#' scores, then winners kept near where they were.
#'
#' @param inputs What committee_inputs() returns, with a previous ranking.
#' @param score One score per row of `inputs`.
#' @return Row numbers of `inputs`, best first.
committee_order <- function(inputs, score, rules = COMMITTEE_RULES) {
  order <- order(-score)
  beat <- attr(inputs, "beat")
  beat <- if (is.null(beat)) character() else paste(beat$winner, beat$loser)
  ids <- inputs$team_id
  for (pass in 1:3) {
    for (i in seq_len(min(40, length(order)) - 1)) {
      above <- order[i]
      below <- order[i + 1]
      below_won <- paste(ids[below], ids[above]) %in% beat && !paste(ids[above], ids[below]) %in% beat
      if (below_won && score[above] - score[below] < rules$head_to_head_gap) order[c(i, i + 1)] <- c(below, above)
    }
  }
  kept <- which(!is.na(inputs$prev_cfp) & inputs$new_losses == 0 & inputs$won_since == 1)
  kept <- kept[order(inputs$prev_cfp[kept])]
  for (pass in 1:3) {
    for (k in kept) {
      limit <- inputs$prev_cfp[k] + rules$max_drop_after_win
      at <- which(order == k)
      if (at > limit) order <- append(order[-at], k, after = limit - 1)
    }
  }
  order
}

#' Our guess at the committee for one week: the one worked out when the app
#' data was built when there is one, otherwise worked out now.
committee_guess <- function(app_data, week) {
  stored <- app_data$committee_guesses
  if (is.data.frame(stored) && week %in% stored$week) return(stored[stored$week == week, , drop = FALSE])
  committee_forecast(app_data, week)
}

#' Our guess at the committee for every week so far, each made only from
#' rankings released before it. Worked out once when the app data is built.
#'
#' @return Rows of week, rank, team_id, score, prev_cfp and method.
committee_guesses <- function(app_data, weeks = sort(unique(app_data$history$week))) {
  rows <- lapply(weeks, function(week) {
    guess <- committee_forecast(app_data, week)
    if (nrow(guess) == 0) return(NULL)
    cbind(week = as.integer(week), guess)
  })
  rows <- do.call(rbind, rows)
  if (is.null(rows)) return(cbind(week = integer(), committee_forecast(app_data, NA_integer_)))
  rows
}

# ---- Carrying what was learned from one season to the next -----------------------

#' Read the saved weights and work out where this season starts from.
#'
#' @return list(resume, update), or NULL when nothing carries over: the file
#'   is missing, or it was written during the first season we learn from.
committee_prior <- function(path, season) {
  if (!file.exists(path)) return(NULL)
  saved <- tryCatch(jsonlite::read_json(path, simplifyVector = TRUE), error = function(e) NULL)
  if (is.null(saved)) return(NULL)
  # A file from an earlier season: what it learned is this season's start.
  # A file from this season: keep the start it recorded.
  carried <- if (isTRUE(saved$season < season)) saved$learned else saved$prior
  if (is.null(carried) || length(carried) == 0) return(NULL)
  weights <- function(x) if (is.null(x) || length(x) == 0) NULL else unlist(x)
  prior <- list(resume = weights(carried$resume), update = weights(carried$update))
  if (is.null(prior$resume) && is.null(prior$update)) NULL else prior
}

#' Save what this season's rankings have taught so far.
write_committee_learned <- function(app_data, path) {
  learned <- learn_committee(app_data, Inf)
  as_list <- function(w) if (is.null(w)) NULL else as.list(round(w, 5))
  saved <- list(
    season = app_data$meta$season, written = format(Sys.Date()),
    rankings_used = list(resume = learned$n_resume, update = learned$n_update),
    learned = list(resume = as_list(learned$resume), update = as_list(learned$update)),
    prior = list(resume = as_list(app_data$committee_prior$resume), update = as_list(app_data$committee_prior$update))
  )
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  jsonlite::write_json(saved, path, auto_unbox = TRUE, pretty = TRUE, null = "null", digits = NA)
  invisible(learned)
}

# ---- What the committee has done, in plain words ---------------------------------

#' How every team moved from one committee ranking to the next this season.
#'
#' @return One row per team ranked in either of two back-to-back rankings:
#'   week, team_id, from and to (ranks, NA when unranked), lost (losses in
#'   between) and, for a team that lost, the opponent's rank in the earlier
#'   ranking (beaten_by_rank) and the margin.
committee_moves <- function(app_data) {
  cfp <- app_data$polls[app_data$polls$poll == "cfp", , drop = FALSE]
  weeks <- sort(unique(cfp$week))
  if (length(weeks) < 2) return(NULL)
  results <- app_data$results
  rows <- lapply(seq_along(weeks)[-1], function(i) {
    before <- cfp[cfp$week == weeks[i - 1], , drop = FALSE]
    after <- cfp[cfp$week == weeks[i], , drop = FALSE]
    ids <- union(before$team_id, after$team_id)
    played <- results[results$week >= weeks[i - 1] & results$week < weeks[i], , drop = FALSE]
    home_won <- played$home_points > played$away_points
    loser <- ifelse(home_won, played$away_id, played$home_id)
    winner <- ifelse(home_won, played$home_id, played$away_id)
    at <- match(ids, loser)
    data.frame(week = weeks[i], team_id = ids,
               from = before$rank[match(ids, before$team_id)], to = after$rank[match(ids, after$team_id)],
               lost = as.integer(table(factor(loser, levels = ids))),
               beaten_by = winner[at], beaten_by_rank = before$rank[match(winner[at], before$team_id)],
               margin = abs(played$home_points - played$away_points)[at])
  })
  do.call(rbind, rows)
}

#' What this season's rankings show about the committee, each with a real
#' example. Built fresh from the rankings and results, so it grows as the
#' season goes on.
#'
#' @return A list of list(rule, example). Empty before the committee has
#'   released two rankings.
committee_lessons <- function(app_data) {
  moves <- committee_moves(app_data)
  if (is.null(moves)) return(list())
  school <- function(id) app_data$teams$school[match(id, app_data$teams$team_id)]
  place <- function(rank) ifelse(is.na(rank), "unranked", paste0("No. ", rank))
  spot <- function(rank) ifelse(is.na(rank), 26, rank)
  moves$change <- spot(moves$from) - spot(moves$to)  # places gained
  ranked_before <- moves[!is.na(moves$from), , drop = FALSE]
  lessons <- list()
  add <- function(rule, example) lessons[[length(lessons) + 1]] <<- list(rule = rule, example = example)

  lost <- ranked_before[ranked_before$lost > 0, , drop = FALSE]
  if (nrow(lost) > 0) {
    worst <- lost[which.min(lost$change), , drop = FALSE]
    out <- sum(is.na(lost$to))
    add(sprintf("A loss costs about %.0f places.", -mean(lost$change)),
        sprintf("%d ranked teams have lost between rankings. The biggest fall: %s, from %s to %s in week %d.%s",
                nrow(lost), school(worst$team_id), place(worst$from), place(worst$to), worst$week,
                if (out > 0) sprintf(" %d dropped out of the 25.", out) else ""))
    forgiven <- lost[lost$change >= 0 & !is.na(lost$to), , drop = FALSE]
    if (nrow(forgiven) > 0) {
      f <- forgiven[which.max(forgiven$change), , drop = FALSE]
      to_whom <- if (is.na(f$beaten_by_rank)) school(f$beaten_by) else sprintf("No. %d %s", f$beaten_by_rank, school(f$beaten_by))
      add("A close loss to a top team can cost nothing.",
          sprintf("%s lost to %s by %d and went from %s to %s in week %d.",
                  school(f$team_id), to_whom, f$margin, place(f$from), place(f$to), f$week))
    }
  }
  held <- ranked_before[ranked_before$lost == 0, , drop = FALSE]
  if (nrow(held) > 0) {
    climb <- held[which.max(held$change), , drop = FALSE]
    add(sprintf("Teams that do not lose move up about %.0f %s on average, mostly into gaps left by teams that lost.",
                max(mean(held$change), 0), if (round(mean(held$change)) == 1) "place" else "places"),
        sprintf("The biggest climb without a loss: %s, from %s to %s in week %d.",
                school(climb$team_id), place(climb$from), place(climb$to), climb$week))
  }
  top <- ranked_before[ranked_before$from == 1, , drop = FALSE]
  if (nrow(top) > 0) {
    kept <- top[top$lost == 0, , drop = FALSE]
    fell <- top[top$lost > 0, , drop = FALSE]
    if (nrow(kept) > 0 && all(kept$to %in% 1)) {
      add("A No. 1 that wins has stayed No. 1.",
          sprintf("%s won and kept the top spot in week %d.%s", school(kept$team_id[1]), kept$week[1],
                  if (nrow(fell) > 0) sprintf(" %s lost as No. 1 and fell to %s.", school(fell$team_id[1]), place(fell$to[1])) else ""))
    } else if (nrow(kept) > 0) {
      k <- kept[!kept$to %in% 1, , drop = FALSE][1, ]
      add("Winning has not always been enough to stay No. 1.",
          sprintf("%s won as No. 1 and was moved to %s in week %d.", school(k$team_id), place(k$to), k$week))
    }
  }

  cfp <- app_data$polls[app_data$polls$poll == "cfp", , drop = FALSE]
  latest <- max(cfp$week)
  now <- cfp[cfp$week == latest, , drop = FALSE]
  resumes <- week_resumes(app_data, latest)
  if (!is.null(resumes)) {
    now$losses <- resumes$losses[match(now$team_id, resumes$team_id)]
    unbeaten <- now[now$losses %in% 0, , drop = FALSE]
    if (nrow(unbeaten) > 0) {
      u <- unbeaten[which.max(unbeaten$rank), , drop = FALSE]
      ahead <- now[now$rank < u$rank & now$losses > 0, , drop = FALSE]
      if (nrow(ahead) > 0) {
        add("An unbeaten record does not settle it.",
            sprintf("In week %d, unbeaten %s is No. %d, behind %d %s with a loss, including %s.", latest,
                    school(u$team_id), u$rank, nrow(ahead), if (nrow(ahead) == 1) "team" else "teams",
                    school(ahead$team_id[1])))
      }
    }
    strong <- ranking_strength(app_data, latest)
    snubbed <- strong[strong$rank <= 10 & !(strong$team_id %in% now$team_id[now$rank <= 15]), , drop = FALSE]
    if (nrow(snubbed) > 0) {
      s <- snubbed[1, , drop = FALSE]
      theirs <- now$rank[match(s$team_id, now$team_id)]
      add("Looking strong is not enough without the record.",
          sprintf("We rate %s No. %d on who would win. With %d losses, the committee has it %s in week %d.",
                  school(s$team_id), s$rank, resumes$losses[match(s$team_id, resumes$team_id)],
                  place(theirs), latest))
    }
  }
  steady <- moves[!is.na(moves$from) & !is.na(moves$to), , drop = FALSE]
  if (nrow(steady) > 0) {
    close <- sum(abs(steady$change) <= 2)
    latest_moves <- steady[steady$week == max(steady$week), , drop = FALSE]
    held_spot <- latest_moves[latest_moves$change == 0, , drop = FALSE]
    add("It mostly keeps its own order from week to week.",
        sprintf("Of the teams ranked in back-to-back rankings, %d of %d moved 2 places or fewer.%s",
                close, nrow(steady),
                if (nrow(held_spot) > 0) sprintf(" In week %d, %s kept the exact same spot.", max(steady$week),
                                                 format_list(school(utils::head(held_spot$team_id[order(held_spot$to)], 3)))) else ""))
  }
  lessons
}

#' Every team's place on who would win, for one week: rank and team_id.
ranking_strength <- function(app_data, week) {
  teams <- snapshot_teams(app_data, min(week, app_data$meta$week))
  blend <- team_points(teams, app_data$params, week)$blend
  out <- data.frame(team_id = teams$team_id, rank = as.integer(rank(-blend, ties.method = "min", na.last = "keep")))
  out[order(out$rank), , drop = FALSE]
}

#' The notes file: what we have learned, the weights, and how each
#' prediction did. Written on every refresh so the reasoning is on record.
committee_notes_markdown <- function(app_data, date = Sys.Date()) {
  school <- function(id) app_data$teams$school[match(id, app_data$teams$team_id)]
  lessons <- committee_lessons(app_data)
  learned <- learn_committee(app_data, Inf)
  record <- forecast_record(app_data$forecasts, app_data$polls)
  cfp <- app_data$polls[app_data$polls$poll == "cfp", , drop = FALSE]
  lines <- c(
    sprintf("_Generated file: written by scripts/refresh.R on %s. Do not edit by hand; it is rewritten on every refresh._", format(date)),
    "", "# What we have learned about the playoff committee", "",
    sprintf("Season %d. The weights below start from what earlier committees did and are pulled toward this season's emphasis by its rankings (%d so far). The lessons come from this season's rankings alone.",
            app_data$meta$season, length(unique(cfp$week))),
    "", "## What it has done this season", ""
  )
  lines <- c(lines, if (length(lessons) == 0) "Nothing yet. The committee needs two rankings before patterns show." else
    unlist(lapply(lessons, function(l) c(sprintf("- **%s** %s", l$rule, l$example)))))
  weights_table <- function(title, weights, n) {
    if (is.null(weights)) return(c("", sprintf("### %s", title), "", "Not learned yet."))
    c("", sprintf("### %s", title), "", sprintf("Learned from %d ranking%s.", n, if (n == 1) "" else "s"), "",
      "| Input | Weight |", "|---|---|",
      sprintf("| %s | %+.3f |", unname(INPUT_LABELS[names(weights)]), weights))
  }
  lines <- c(lines, "", "## The weights behind the prediction", "",
             "A positive weight moves a team up. They are in each input's own units, so sizes do not compare directly.",
             weights_table("Week to week (once the committee has ranked)", learned$update, learned$n_update),
             weights_table("From resumes alone (before its first ranking)", learned$resume, learned$n_resume))
  lines <- c(lines, "", "## How our predictions have done", "")
  if (nrow(record) == 0) {
    lines <- c(lines, "No prediction has been graded yet.")
  } else {
    lines <- c(lines, "| Week | Places off | Exactly right | Their 25 | Their top 12 | Made |", "|---|---|---|---|---|---|",
               sprintf("| %d | %.1f | %d | %d of 25 | %d of 12 | %s the release |", record$week, record$places_off,
                       record$exact, record$in_25, record$top12, record$made))
    for (week in record$week) {
      ours <- app_data$forecasts[app_data$forecasts$week == week, , drop = FALSE]
      theirs <- cfp[cfp$week == week, , drop = FALSE]
      predicted <- ours$rank[match(theirs$team_id, ours$team_id)]
      predicted[is.na(predicted)] <- max(ours$rank) + 1L
      miss <- order(-abs(predicted - theirs$rank))[1:3]
      lines <- c(lines, "", sprintf("**Week %d, biggest misses:** %s.", week,
                                    paste(sprintf("%s (we said %d, they said %d)", school(theirs$team_id[miss]),
                                                  predicted[miss], theirs$rank[miss]), collapse = "; ")))
    }
  }
  c(lines, "")
}
