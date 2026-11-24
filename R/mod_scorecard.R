# Scorecard tab: how our saved predictions did once the games were played.
# Answer first (a scoreboard: our average miss next to the market's), then
# charts for the figures behind it: week by week, system by system, and the
# biggest calls of any graded week. Tables are folded under each chart. Every number comes from app_data$scorecard (R/predictions.R).

# Hidden sort keys sit after the visible columns (0-based for DT).
SCORECARD_VISIBLE <- c("Matchup", "Our line", "Market", "Final", "Closer")
SCORECARD_KEYS <- c(our = 5, market = 6, final = 7, closer = 8)

#' @param app_data See docs/data-dictionary.md.
mod_scorecard_ui <- function(id, app_data) {
  ns <- shiny::NS(id)
  scorecard <- app_data$scorecard
  season <- scorecard$season

  if (season$games == 0) {
    return(htmltools::div(
      class = "page-wide",
      htmltools::tags$section(
        class = "card report-card", `aria-labelledby` = ns("title"),
        htmltools::div(
          class = "card-body",
          htmltools::tags$h2(id = ns("title"), class = "section-title", "Scorecard"),
          scorecard_empty(scorecard$games)
        )
      )
    ))
  }

  weeks <- sort(scorecard$weeks$week, decreasing = TRUE)
  htmltools::div(
    class = "page-wide",
    htmltools::tags$section(
      class = "scorecard-summary", `aria-labelledby` = ns("title"),
      # The sentence is the heading for screen readers; the scoreboard shows
      # the same two numbers large.
      htmltools::tags$h2(id = ns("title"), class = "visually-hidden", scorecard_headline(season)),
      scoreboard(season, nrow(scorecard$weeks)),
      htmltools::div(class = "ring-row", scorecard_stats(season)),
      htmltools::p(class = "fine-print small-sample", SMALL_SAMPLE_NOTE)
    ),
    report_grid(list(
      report_section("Week by week", scorecard_weeks_block(scorecard$weeks)),
      report_section("All five systems, graded", scorecard_systems_block(scorecard$systems))
    )),
    scorecard_qb_section(app_data),
    report_section("Game by game", htmltools::tagList(
      htmltools::p(class = "section-lede",
                   "Pick a week. The chart shows the games where we and the market were furthest apart ",
                   "in how close we got. Every game is in the table under it."),
      htmltools::div(
        class = "week-pills",
        shiny::radioButtons(ns("week"), label = "Week", inline = TRUE, selected = weeks[1],
                            choiceNames = paste("Week", weeks), choiceValues = weeks)
      ),
      shiny::uiOutput(ns("calls")),
      chart_details("Every game that week",
                    htmltools::div(class = "slate-wrap", DT::DTOutput(ns("games"))))
    ))
  )
}

#' The season's answer as a scoreboard: our average miss against the
#' market's, with who is ahead.
scoreboard <- function(season, n_weeks) {
  side <- function(class, name, miss) {
    htmltools::div(
      class = paste("score", class),
      htmltools::span(class = "score-name", name),
      htmltools::span(class = "score-num", `data-count` = if (!is.na(miss)) "",
                      if (is.na(miss)) "No line" else sprintf("%.1f", miss)),
      htmltools::span(class = "score-unit", "points off a game")
    )
  }
  gap <- season$our_miss - season$market_miss
  verdict <- if (is.na(gap)) NULL else if (abs(gap) < 0.05) "Dead even with the market." else
    sprintf("%s by %.1f. Lower is better.", if (gap < 0) "We lead" else "The market leads", abs(gap))
  htmltools::div(
    class = "scoreboard", `aria-hidden` = "true",
    htmltools::div(
      class = "scoreboard-sides",
      side("is-ours", "Our line", season$our_miss),
      htmltools::span(class = "score-vs", "vs"),
      side("is-theirs", "The market", season$market_miss)
    ),
    htmltools::p(class = "scoreboard-note",
                 if (!is.null(verdict)) htmltools::strong(verdict), " ",
                 scorecard_context(season, n_weeks),
                 " The market is the sportsbook line when our prediction was saved, before kickoff.")
  )
}

SMALL_SAMPLE_NOTE <- paste(
  "A few weeks is too little to judge a model. One game can swing by two touchdowns",
  "either way, so these averages take a full season or more to settle."
)

#' Before anything is graded: what is saved, and when results appear.
#'
#' @param games scorecard$games (saved predictions, none graded yet).
scorecard_empty <- function(games) {
  if (nrow(games) == 0) {
    return(empty_state(
      "No predictions saved yet.",
      htmltools::p("Each week, the data refresh saves our line for every game before the first ",
                   "kickoff. Once those games are played, this page grades them against the final ",
                   "scores and against the market.")
    ))
  }
  week <- max(games$week)
  n <- sum(games$week == week)
  empty_state(
    "No games graded yet.",
    htmltools::p(sprintf("We saved %d %s for week %d before the first kickoff.",
                         n, if (n == 1) "prediction" else "predictions", week),
                 " Results show up here once those games are final, at the next data refresh."),
    htmltools::p("Then this page shows how far our lines landed from the final scores, ",
                 "next to the market's.")
  )
}

#' "Off by 12.4 points a game. The market: 11.9."
scorecard_headline <- function(season) {
  ours <- sprintf("Off by %.1f points a game.", season$our_miss)
  if (is.na(season$market_miss)) return(ours)
  sprintf("%s The market: %.1f.", ours, season$market_miss)
}

#' "2026 season to date, 36 games over 3 weeks."
scorecard_context <- function(season, n_weeks) {
  sprintf("%d season to date, %d %s over %d %s.", season$season,
          season$games, if (season$games == 1) "game" else "games",
          n_weeks, if (n_weeks == 1) "week" else "weeks")
}

#' "7 of 19", or "None" when there were no games to count.
format_record <- function(wins, total) {
  ifelse(total == 0, "None", sprintf("%d of %d", as.integer(wins), as.integer(total)))
}

#' "46%", or "None" when there was nothing to count.
format_share <- function(wins, total) if (total == 0) "None" else sprintf("%.0f%%", wins / total * 100)

#' The row of rings under the scoreboard.
scorecard_stats <- function(season) {
  market_closer <- season$market_games - season$closer - season$ties
  share <- function(wins, total) if (total == 0) NA else wins / total
  list(
    ring_stat("Winners picked", season$winner_share, sprintf("%.0f%%", season$winner_share * 100),
              sprintf("%s games. Games graded: %s, every one saved before kickoff.",
                      format_record(season$winners, season$games), format(season$games, big.mark = ","))),
    ring_stat("Closer than the market", share(season$closer, season$market_games),
              format_share(season$closer, season$market_games),
              sprintf("Our line landed nearer the final margin in %s games. The market was closer in %d%s.",
                      format_record(season$closer, season$market_games), market_closer,
                      if (season$ties > 0) sprintf(", and %d were even" , season$ties) else "")),
    ring_stat(sprintf("When we disagreed by %d or more", DISAGREE_POINTS),
              share(season$disagree_our_side, season$disagree_games),
              format_share(season$disagree_our_side, season$disagree_games),
              sprintf(paste("%s games where our line and the market's were %d or more points apart",
                            "landed on our side of the market line. Pushes are left out."),
                      format_record(season$disagree_our_side, season$disagree_games), DISAGREE_POINTS))
  )
}

#' Average miss as shown in tables: one decimal, or "No line" when unknown.
format_miss <- function(x) ifelse(is.na(x), "No line", sprintf("%.1f", x))

#' Our miss against the market's, week by week, with the table behind it.
scorecard_weeks_block <- function(weeks) {
  weeks <- weeks[order(weeks$week), , drop = FALSE]
  closer_market <- weeks$market_games - weeks$closer - weeks$ties
  htmltools::tagList(
    htmltools::p(class = "section-lede", "Average points off the final margin. Further left is better."),
    dumbbell_chart(paste("Week", weeks$week), weeks$our_miss, weeks$market_miss,
                   note = "Average miss in points"),
    htmltools::p(class = "chart-subhead", "Games where each was closer"),
    htmltools::div(class = "versus-list", lapply(seq_len(nrow(weeks)), function(i) {
      htmltools::div(
        class = "versus-row",
        htmltools::span(class = "chart-label", paste("Week", weeks$week[i])),
        versus_bar(weeks$closer[i], closer_market[i], weeks$ties[i])
      )
    })),
    chart_details("See the numbers", htmltools::div(class = "scorecard-weeks", scorecard_weeks_table(weeks)))
  )
}

#' "Quarterback adjustments, graded": how the line adjusted for a starter
#' listed out did against ours and the market's. NULL until a game has one.
scorecard_qb_section <- function(app_data) {
  games <- app_data$scorecard$games
  graded <- grade_qb_adjustment(games[!is.na(games$final_margin), , drop = FALSE], app_data$qb_games,
                                app_data$qb_status, app_data$teams)
  if (nrow(graded) == 0) return(NULL)
  n <- nrow(graded)
  rows <- data.frame(
    week = graded$week,
    game = paste(graded$away_team, "at", graded$home_team),
    out = graded$out,
    ours = format_miss(graded$our_miss),
    adjusted = format_miss(graded$adjusted_miss),
    market = format_miss(graded$market_miss),
    stringsAsFactors = FALSE
  )
  lined <- !is.na(graded$market_miss)
  report_section("Quarterback adjustments, graded", htmltools::tagList(
    htmltools::p(
      class = "section-lede",
      sprintf("When a report lists an established starting quarterback out before kickoff, we also show a line with %s points taken off his team.",
              format_points(QB_OUT_POINTS)),
      sprintf("This grades that adjusted line on the %d %s it has applied to. It is far too few to judge yet.",
              n, if (n == 1) "game" else "games")
    ),
    dot_chart(c("Our line", "Adjusted for the QB", "Market"),
              c(mean(graded$our_miss), mean(graded$adjusted_miss),
                if (any(lined)) mean(graded$market_miss[lined]) else mean(graded$our_miss)),
              highlight = c(FALSE, TRUE, FALSE), benchmark = c(FALSE, FALSE, any(lined)),
              note = "Average miss in points on these games. Left is better.", benchmark_label = "Sportsbooks"),
    chart_details("See the games",
                  simple_table(rows, headers = list("Week", "Game", "Starter out", "Our miss", "Adjusted miss", "Market miss"),
                               numeric = c(TRUE, FALSE, FALSE, TRUE, TRUE, TRUE)))
  ))
}

#' Every system's average miss on one scale, best at the top.
scorecard_systems_block <- function(systems) {
  ranked <- systems[order(systems$avg_miss), , drop = FALSE]
  htmltools::tagList(
    htmltools::p(class = "section-lede",
                 "The first honest look at all five systems: every line here was saved before ",
                 "kickoff, so none of them had seen the result. Best at the top."),
    dot_chart(ranked$label, ranked$avg_miss, highlight = ranked$system == "blend",
              benchmark = ranked$system == "market", note = "Average miss in points. Left is better.",
              benchmark_label = "Sportsbooks"),
    htmltools::p(class = "fine-print",
                 "Blend is the line the app shows. Market is the sportsbook line when we saved ours. ",
                 sprintf("%s games each.", format(max(systems$games), big.mark = ",")))
  )
}

scorecard_weeks_table <- function(weeks) {
  # No games column: the winners record ("9 of 12") already says how many,
  # and one column fewer keeps the table inside a phone screen.
  rows <- data.frame(
    week = as.character(weeks$week),
    ours = format_miss(weeks$our_miss),
    market = format_miss(weeks$market_miss),
    winners = format_record(weeks$winners, weeks$games),
    closer = format_record(weeks$closer, weeks$market_games),
    disagree = format_record(weeks$disagree_our_side, weeks$disagree_games),
    stringsAsFactors = FALSE
  )
  simple_table(
    rows,
    headers = list("Week", "Our miss", "Market miss", "Winners picked",
                   "Closer than market", sprintf("Disagreed by %d+", DISAGREE_POINTS)),
    numeric = c(FALSE, rep(TRUE, 5)),
    caption = sprintf(paste("Misses are average points from the final margin. Disagreed by %d+:",
                            "of the games where we were %d or more points off the market line,",
                            "how many landed on our side of it."), DISAGREE_POINTS, DISAGREE_POINTS)
  )
}

scorecard_systems_table <- function(systems) {
  rows <- data.frame(
    system = systems$label,
    games = as.character(systems$games),
    miss = format_miss(systems$avg_miss),
    stringsAsFactors = FALSE
  )
  simple_table(
    rows, headers = list("System", "Games", "Avg miss (pts)"),
    numeric = c(FALSE, TRUE, TRUE),
    row_class = ifelse(systems$system == "blend", "is-blend",
                       ifelse(systems$system == "market", "is-market", "")),
    caption = "Blend is the line the app shows. Market is the sportsbook line when we saved ours. Lower is better."
  )
}

#' "Kofa 31, Ironwood 17", winner first.
format_final <- function(home, away, home_points, away_points) {
  home_first <- home_points >= away_points
  ifelse(home_first,
         sprintf("%s %d, %s %d", home, home_points, away, away_points),
         sprintf("%s %d, %s %d", away, away_points, home, home_points))
}

#' "Us, by 2.5", "Market, by 4" or "Even".
format_closer <- function(closer, our_error, market_error) {
  by <- format_points(abs(market_error - our_error))
  ifelse(is.na(closer), "No line",
         ifelse(closer == "us", paste("Us, by", by),
                ifelse(closer == "market", paste("Market, by", by), "Even")))
}

#' One display row per graded game, plus numeric keys for sorting. Lines and
#' finals read away first, the same way the This week tab does.
#'
#' @param teams The teams table, for the small logo beside each name. NULL
#'   shows the names alone.
#' @param ranks Ranks named by team id, shown beside the names, or NULL.
scorecard_game_rows <- function(games, teams = NULL, ranks = NULL) {
  esc <- htmltools::htmlEscape
  cell <- function(label, html) sprintf('<span class="cell-label">%s</span>%s', label, html)
  away <- games$away_team
  home <- games$home_team
  joiner <- ifelse(games$neutral_site == 1, "vs", "at")
  # Saved margins are home minus away; the words read with the away team as A.
  in_words <- function(home_margin) {
    vapply(seq_along(home_margin), function(i) {
      if (is.na(home_margin[i])) return('<span class="muted">No line</span>')
      esc(format_favorite(-home_margin[i], away[i], home[i]))
    }, character(1))
  }
  name_html <- function(team_id, school) {
    vapply(seq_along(school), function(i) {
      team <- if (is.null(teams)) NULL else teams[teams$team_id %in% team_id[i], , drop = FALSE]
      team_name_html(team, school[i], if (is.null(ranks)) NA else rank_of(ranks, team_id[i]))
    }, character(1))
  }
  data.frame(
    matchup = matchup_html(name_html(games$away_id, away), joiner, name_html(games$home_id, home)),
    our = cell("Our line", in_words(games$blend)),
    market = cell("Market", in_words(-games$market_spread_home)),
    final = cell("Final", esc(format_final(home, away, games$home_points, games$away_points))),
    closer = cell("Closer", esc(format_closer(games$closer, games$our_error, games$market_error))),
    our_key = abs(games$blend),
    market_key = ifelse(is.na(games$market_spread_home), -1, abs(games$market_spread_home)),
    final_key = abs(games$final_margin),
    # Our biggest wins over the market sort first when descending.
    closer_key = ifelse(is.na(games$market_error), -999, games$market_error - games$our_error),
    stringsAsFactors = FALSE
  )
}

#' The graded games as a sortable DT that matches the This week table.
scorecard_games_table <- function(rows) {
  DT::datatable(
    rows,
    colnames = c(SCORECARD_VISIBLE, names(SCORECARD_KEYS)),
    rownames = FALSE, escape = FALSE, selection = "none",
    style = "default", class = "slate-table scorecard-table",
    options = list(
      dom = "<'slate-search'f>t",
      paging = FALSE, info = FALSE, autoWidth = FALSE,
      order = list(),  # kickoff order until someone sorts
      language = list(search = "", searchPlaceholder = "Find a team",
                      zeroRecords = "No games match that search."),
      columnDefs = list(
        list(targets = unname(SCORECARD_KEYS), visible = FALSE, searchable = FALSE),
        list(targets = 1, orderData = SCORECARD_KEYS[["our"]]),
        list(targets = 2, orderData = SCORECARD_KEYS[["market"]]),
        list(targets = 3, orderData = SCORECARD_KEYS[["final"]]),
        list(targets = 4, orderData = SCORECARD_KEYS[["closer"]], orderSequence = list("desc", "asc"))
      )
    )
  )
}

#' The games of one week where we and the market differed most in how close
#' we got: our best calls and theirs.
#'
#' @param games Graded games of one week (scorecard$games rows).
#' @param each How many to show on each side.
#' @param teams,ranks For the logo and ranking beside each name; NULL for
#'   names alone.
scorecard_calls <- function(games, each = 5, teams = NULL, ranks = NULL) {
  games <- games[!is.na(games$market_error), , drop = FALSE]
  if (nrow(games) == 0) return(empty_state("No market line was saved for these games.",
                                           "There is nothing to compare our line against."))
  games$edge <- games$market_error - games$our_error  # positive: we were closer
  ours <- games[games$edge > 0, , drop = FALSE]
  theirs <- games[games$edge < 0, , drop = FALSE]
  shown <- rbind(utils::head(ours[order(-ours$edge), , drop = FALSE], each),
                 utils::head(theirs[order(theirs$edge), , drop = FALSE], each))
  if (nrow(shown) == 0) return(empty_state("Even all week.", "Our line and the market's landed equally close."))
  joiner <- ifelse(shown$neutral_site == 1, "vs", "at")
  in_words <- function(home_margin, i) format_favorite(-home_margin, shown$away_team[i], shown$home_team[i])
  hover <- vapply(seq_len(nrow(shown)), function(i) {
    sprintf("Our line: %s. Market: %s. Final: %s.", in_words(shown$blend[i], i),
            in_words(-shown$market_spread_home[i], i),
            format_final(shown$home_team[i], shown$away_team[i], shown$home_points[i], shown$away_points[i]))
  }, character(1))
  htmltools::tagList(
    htmltools::div(class = "versus-row versus-total",
                   versus_bar(nrow(ours), nrow(theirs), sum(games$edge == 0), "We were closer", "Market was closer")),
    htmltools::p(class = "chart-subhead", "The biggest swings each way, in points closer to the final margin"),
    swing_chart(lapply(seq_len(nrow(shown)), function(i) {
      name <- function(id, school) {
        team <- if (is.null(teams)) NULL else teams[teams$team_id %in% id, , drop = FALSE]
        team_name_html(team, school, if (is.null(ranks)) NA else rank_of(ranks, id))
      }
      htmltools::HTML(sprintf('%s <span class="game-where">%s</span> %s', name(shown$away_id[i], shown$away_team[i]),
                              joiner[i], name(shown$home_id[i], shown$home_team[i])))
    }), shown$edge,
                text = format_points(abs(shown$edge)), hover = hover),
    htmltools::p(class = "fine-print", "Tap a game for both lines and the final score.",
                 if (!is.null(ranks)) rank_note(ranks))
  )
}

#' @param app_data See docs/data-dictionary.md.
mod_scorecard_server <- function(id, app_data) {
  shiny::moduleServer(id, function(input, output, session) {
    scorecard <- app_data$scorecard
    if (scorecard$season$games == 0) return(invisible(NULL))
    graded <- scorecard$games[!is.na(scorecard$games$final_margin), , drop = FALSE]
    picked <- shiny::reactive({
      week <- suppressWarnings(as.integer(input$week))
      if (length(week) != 1 || is.na(week) || !week %in% graded$week) week <- max(graded$week)
      graded[graded$week == week, , drop = FALSE]
    })
    # Rankings as they stood going into that week's games.
    ranks <- shiny::reactive(team_ranks(app_data, picked()$week[1]))
    output$calls <- shiny::renderUI(scorecard_calls(picked(), teams = app_data$teams, ranks = ranks()))
    output$games <- DT::renderDT(scorecard_games_table(scorecard_game_rows(picked(), app_data$teams, ranks())))
    # The table sits in a folded section; draw it anyway so it is there on opening.
    shiny::outputOptions(output, "games", suspendWhenHidden = FALSE)
  })
}
