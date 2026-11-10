# Scorecard tab: how our saved predictions did once the games were played.
# Answer first (the season's average miss next to the market's), then the
# figures behind it, week by week, system by system, and the latest week's
# games. Every number comes from app_data$scorecard (R/predictions.R).

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

  latest_week <- max(scorecard$weeks$week)
  htmltools::div(
    class = "page-wide",
    htmltools::tags$section(
      class = "scorecard-summary", `aria-label` = "Season to date",
      htmltools::tags$h2(
        class = "scorecard-headline",
        htmltools::span(class = "scorecard-answer", scorecard_headline(season)),
        " ",
        htmltools::span(class = "headline-context", scorecard_context(season, nrow(scorecard$weeks)))
      ),
      htmltools::p(class = "section-lede",
                   "Miss is how many points our line landed from the final margin. ",
                   "The market is the sportsbook line when our prediction was saved, before kickoff."),
      report_grid(scorecard_stats(season), min_width = "200px"),
      htmltools::p(class = "fine-print small-sample", SMALL_SAMPLE_NOTE)
    ),
    report_section("Week by week",
                   htmltools::div(class = "scorecard-weeks", scorecard_weeks_table(scorecard$weeks))),
    report_section("All five systems, graded", htmltools::tagList(
      htmltools::p(class = "section-lede",
                   "The first honest look at all five systems: every line here was saved before ",
                   "kickoff, so none of them had seen the result."),
      scorecard_systems_table(scorecard$systems)
    )),
    report_section(sprintf("Week %s games", latest_week), htmltools::tagList(
      htmltools::p(class = "section-lede",
                   sprintf("Every game we saved for week %s, and how it finished.", latest_week)),
      htmltools::div(class = "slate-wrap", DT::DTOutput(ns("games")))
    ))
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

#' The row of figures under the headline.
scorecard_stats <- function(season) {
  market_closer <- season$market_games - season$closer - season$ties
  list(
    stat_card("Games graded", format(season$games, big.mark = ","),
              "Every one was saved before kickoff."),
    stat_card("Winners picked", sprintf("%.0f%%", season$winner_share * 100),
              sprintf("%s games.", format_record(season$winners, season$games))),
    stat_card("Closer than the market", format_record(season$closer, season$market_games),
              sprintf("Games where our line landed nearer the final margin. The market was closer in %d%s.",
                      market_closer, if (season$ties > 0) sprintf(", and %d were even", season$ties) else "")),
    stat_card(sprintf("When we disagreed by %d or more", DISAGREE_POINTS),
              format_record(season$disagree_our_side, season$disagree_games),
              sprintf(paste("Games where our line and the market's were %d or more points apart",
                            "and the result landed on our side of the market line. Pushes are left out."),
                      DISAGREE_POINTS))
  )
}

#' Average miss as shown in tables: one decimal, or "No line" when unknown.
format_miss <- function(x) ifelse(is.na(x), "No line", sprintf("%.1f", x))

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
scorecard_game_rows <- function(games) {
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
  data.frame(
    matchup = sprintf('<span class="slate-team">%s</span> <span class="slate-at">%s</span> <span class="slate-team">%s</span>',
                      esc(away), joiner, esc(home)),
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

#' @param app_data See docs/data-dictionary.md.
mod_scorecard_server <- function(id, app_data) {
  shiny::moduleServer(id, function(input, output, session) {
    scorecard <- app_data$scorecard
    if (scorecard$season$games == 0) return(invisible(NULL))
    graded <- scorecard$games[!is.na(scorecard$games$final_margin), , drop = FALSE]
    latest <- graded[graded$week == max(graded$week), , drop = FALSE]
    output$games <- DT::renderDT(scorecard_games_table(scorecard_game_rows(latest)))
  })
}
