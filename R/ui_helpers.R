# Shared helpers for the app: loading data, team badges, slate and market
# logic, and small UI pieces used by more than one tab.
#
# Everything that turns numbers into words comes from R/format.R. These
# helpers only decide what to show and where.

# Data loading ----------------------------------------------------------------

REQUIRED_TEAM_COLUMNS <- c(
  "team_id", "school", "conference", "tier",
  names(MODEL_LABELS), paste0(names(MODEL_LABELS), "_rank")
)

#' List the problems that would stop the app from using `x` as app_data.
#'
#' @return Character vector, empty when `x` is usable.
app_data_problems <- function(x) {
  if (!is.list(x)) return("it is not a list")
  missing <- setdiff(c("meta", "teams", "params"), names(x))
  if (length(missing) > 0) {
    return(sprintf("it is missing %s", paste(missing, collapse = ", ")))
  }
  problems <- character()
  if (!is.data.frame(x$teams) || nrow(x$teams) < 2) {
    problems <- c(problems, "the teams table needs at least two teams")
  } else {
    missing_cols <- setdiff(REQUIRED_TEAM_COLUMNS, names(x$teams))
    if (length(missing_cols) > 0) {
      problems <- c(problems, sprintf("the teams table is missing %s",
                                      paste(missing_cols, collapse = ", ")))
    }
  }
  missing_params <- setdiff(c("k", "elo_tier", "power_scale", "h", "sigma", "weights"), names(x$params))
  if (length(missing_params) > 0) {
    problems <- c(problems, sprintf("params is missing %s", paste(missing_params, collapse = ", ")))
  }
  problems
}

#' Fill in optional pieces so the tabs never have to check for NULL.
complete_app_data <- function(x) {
  optional_cols <- c("mascot", "abbreviation", "color", "alt_color", "logo")
  for (col in setdiff(optional_cols, names(x$teams))) x$teams[[col]] <- NA_character_
  if (!is.data.frame(x$slate)) {
    x$slate <- data.frame(game_id = integer(), start_date = character(), home_id = integer(),
                          away_id = integer(), neutral_site = logical(),
                          market_spread_home = numeric())
  }
  # App data built before predictions were saved has no line movement or
  # scorecard. Treat that as nothing saved yet.
  for (col in setdiff(c("market_at_freeze", "market_move"), names(x$slate))) {
    x$slate[[col]] <- rep(NA_real_, nrow(x$slate))
  }
  if (!is_scorecard(x$scorecard)) x$scorecard <- empty_scorecard(x$meta$season)
  if (!is.data.frame(x$coverage)) {
    x$coverage <- data.frame(source = character(), season = integer(), week = integer(),
                             n_teams = integer(), pulled_at = character())
  }
  x$meta$is_demo <- isTRUE(x$meta$is_demo)
  x
}

#' TRUE when `x` has every part of a scorecard.
is_scorecard <- function(x) {
  parts <- c("games", "weeks", "season", "systems")
  is.list(x) && all(parts %in% names(x)) && all(vapply(x[parts], is.data.frame, logical(1)))
}

#' This week's game notes for the slate games: the made-up ones in demo mode,
#' otherwise read straight from data/notes.csv.
app_notes <- function(app_data, path = PATHS$notes) {
  notes <- if (isTRUE(app_data$meta$is_demo)) {
    demo_notes(app_data)
  } else {
    load_notes(path, app_data$meta$season, app_data$meta$week)
  }
  notes[notes$game_id %in% app_data$slate$game_id, , drop = FALSE]
}

#' Load app data, falling back to the demo when the real file is missing or bad.
#'
#' @param path Usually PATHS$app_data.
#' @return A list: `data` (complete app_data) and `error` (what went wrong,
#'   in plain words, or NULL when everything loaded). data_banner() adds
#'   the fix.
load_app_data <- function(path = PATHS$app_data) {
  if (!file.exists(path)) {
    return(list(data = complete_app_data(demo_app_data()), error = NULL))
  }
  x <- tryCatch(readRDS(path), error = function(e) e)
  problems <- if (inherits(x, "error")) "the file could not be read" else app_data_problems(x)
  if (length(problems) > 0) {
    message <- sprintf("We couldn't use %s (%s).", path, paste(problems, collapse = "; "))
    return(list(data = complete_app_data(demo_app_data()), error = message))
  }
  list(data = complete_app_data(x), error = NULL)
}

# Dates and freshness ---------------------------------------------------------

#' "Nov 10" style date. Uses month.abb so it does not depend on the locale.
short_date <- function(date) {
  date <- as.Date(date)
  paste(month.abb[as.integer(format(date, "%m"))], as.integer(format(date, "%d")))
}

#' Navbar text such as "Ratings through week 11, Nov 10".
freshness_label <- function(meta) {
  date <- tryCatch(short_date(meta$ratings_date), error = function(e) NA)
  parts <- c(if (!is.null(meta$week)) paste("week", meta$week), if (!is.na(date)) date)
  if (length(parts) == 0) return("Ratings date unknown")
  paste("Ratings through", paste(parts, collapse = ", "))
}

#' Notes about the data itself (not the matchup) that apply right now.
data_notes <- function(meta, today = Sys.Date()) {
  notes <- character()
  if (!is.null(meta$week) && meta$week <= EARLY_SEASON_LAST_WEEK) {
    notes <- c(notes, "Early season. Ratings still lean on preseason priors.")
  }
  age <- tryCatch(as.numeric(as.Date(today) - as.Date(meta$ratings_date)), error = function(e) NA)
  if (!isTRUE(meta$is_demo) && !is.na(age) && age > STALE_AFTER_DAYS) {
    notes <- c(notes, sprintf("Ratings are more than %d days old.", STALE_AFTER_DAYS))
  }
  notes
}

# Teams -------------------------------------------------------------------------

#' Up to three letters for a badge: abbreviation if known, else initials.
team_initials <- function(school, abbreviation = NA) {
  ifelse(
    !is.na(abbreviation) & nzchar(abbreviation),
    substr(abbreviation, 1, 3),
    vapply(strsplit(school, "[^A-Za-z0-9]+"), function(words) {
      toupper(paste(substr(words[nzchar(words)], 1, 1), collapse = ""))
    }, character(1))
  )
}

#' Badge colors: the team's own primary, with black or white text on top.
badge_colors <- function(color) {
  bg <- normalize_hex(color)
  if (is.na(bg)) bg <- "#334155"
  c(bg = bg, fg = readable_text_color(bg))
}

#' A team logo, or a colored initials badge when there is no logo.
#' If the logo fails to load, www/app.js swaps in the initials.
#'
#' @param team One-row data frame from the teams table.
#' @param size "sm", "md" or "lg".
team_badge <- function(team, size = "md") {
  colors <- badge_colors(team$color)
  has_logo <- !is.na(team$logo) && nzchar(team$logo)
  htmltools::tags$span(
    class = paste("team-badge", paste0("team-badge-", size), if (has_logo) "has-logo"),
    style = sprintf("--badge-bg:%s;--badge-fg:%s", colors[["bg"]], colors[["fg"]]),
    htmltools::tags$span(class = "team-initials", `aria-hidden` = "true",
                         team_initials(team$school, team$abbreviation)),
    if (has_logo) htmltools::tags$img(src = team$logo, alt = paste(team$school, "logo"),
                                      loading = "lazy", class = "team-logo")
  )
}

#' Team rows as selectize options: the fields the picker renders and searches.
team_options <- function(teams) {
  teams <- teams[order(teams$conference, teams$school), , drop = FALSE]
  lapply(seq_len(nrow(teams)), function(i) {
    team <- teams[i, , drop = FALSE]
    colors <- badge_colors(team$color)
    list(
      value = as.character(team$team_id),
      school = team$school,
      mascot = if (is.na(team$mascot)) "" else team$mascot,
      abbreviation = if (is.na(team$abbreviation)) "" else team$abbreviation,
      conference = if (is.na(team$conference)) "Other" else team$conference,
      initials = team_initials(team$school, team$abbreviation),
      logo = if (is.na(team$logo)) "" else team$logo,
      bg = colors[["bg"]],
      fg = colors[["fg"]]
    )
  })
}

#' Grouped choices for the underlying <select>, so it works before JS loads.
team_choices <- function(teams) {
  teams <- teams[order(teams$conference, teams$school), , drop = FALSE]
  groups <- split(teams, teams$conference)
  lapply(groups, function(g) stats::setNames(as.character(g$team_id), g$school))
}

#' A rough strength score per team, used only to pick the opening matchup.
#' Average rank across the rating systems; lower rank means stronger.
team_strength <- function(teams) {
  ranks <- as.matrix(teams[paste0(names(MODEL_LABELS), "_rank")])
  -rowMeans(ranks, na.rm = TRUE)
}

# Slate and market --------------------------------------------------------------

#' The matchup for a slate game: away team as A, home team as B.
#' This reads naturally as "A at B" and keeps the real site.
slate_matchup <- function(game) {
  list(
    a = game$away_id,
    b = game$home_id,
    site = if (isTRUE(game$neutral_site)) "neutral" else "b_home"
  )
}

#' The first game to show: the slate game between the two strongest teams.
#' With no slate, the top two teams on a neutral field.
default_matchup <- function(app_data) {
  teams <- app_data$teams
  strength <- stats::setNames(team_strength(teams), teams$team_id)
  slate <- app_data$slate
  known <- as.character(slate$home_id) %in% names(strength) &
    as.character(slate$away_id) %in% names(strength)
  slate <- slate[known, , drop = FALSE]

  if (nrow(slate) > 0) {
    combined <- strength[as.character(slate$home_id)] + strength[as.character(slate$away_id)]
    return(slate_matchup(slate[which.max(combined), , drop = FALSE]))
  }
  top <- teams$team_id[order(-strength)][1:2]
  list(a = top[1], b = top[2], site = "neutral")
}

#' Read a matchup from the address bar, e.g. "?a=Ironwood&b=Kofa&site=a_home".
#'
#' Anything missing or unrecognized falls back to `fallback` without fuss, so
#' an old or hand-edited link still opens something sensible.
#'
#' @param query The raw query string, with or without the leading "?".
#' @param fallback list(a, b, site), usually from default_matchup().
matchup_from_query <- function(query, teams, fallback) {
  params <- if (is.null(query) || !nzchar(query)) list() else shiny::parseQueryString(query)
  lookup <- function(school) {
    if (is.null(school)) return(NA)
    hit <- teams$team_id[tolower(teams$school) == tolower(trimws(school))]
    if (length(hit) == 1) hit else NA
  }
  a <- lookup(params$a)
  b <- lookup(params$b)
  if (is.na(a) && is.na(b)) {
    site <- if (isTRUE(params$site %in% SITE_CHOICES)) params$site else fallback$site
    return(list(a = fallback$a, b = fallback$b, site = site))
  }
  if (is.na(a)) a <- if (b != fallback$a) fallback$a else fallback$b
  if (is.na(b) || b == a) b <- if (a != fallback$b) fallback$b else fallback$a
  site <- if (isTRUE(params$site %in% SITE_CHOICES)) params$site else "neutral"
  list(a = a, b = b, site = site)
}

#' The slate game between two teams, in either order, or NULL.
find_slate_game <- function(slate, a_id, b_id) {
  hit <- (slate$home_id == a_id & slate$away_id == b_id) |
    (slate$home_id == b_id & slate$away_id == a_id)
  if (!any(hit)) return(NULL)
  slate[which(hit)[1], , drop = FALSE]
}

#' Does the picked site match where the game is really played?
site_matches_game <- function(site, game, a_id) {
  if (isTRUE(game$neutral_site)) return(site == "neutral")
  home_is_a <- game$home_id == a_id
  (home_is_a && site == "a_home") || (!home_is_a && site == "b_home")
}

#' The market's expected margin for Team A (A minus B).
#'
#' market_spread_home is sportsbook style: -7 means the home team is favored
#' by 7, so the home margin is its negative.
market_margin_for_a <- function(game, a_id) {
  home_margin <- -game$market_spread_home
  if (game$home_id == a_id) home_margin else -home_margin
}

#' "we're 2 points higher on Ironwood", or agreement when it rounds to zero.
#'
#' @param gap Our margin minus the market margin, both A minus B.
market_gap_phrase <- function(gap, name_a, name_b) {
  points <- format_points(gap)
  if (points == "0") return("we agree")
  unit <- if (points == "1") "point" else "points"
  sprintf("we're %s %s higher on %s", points, unit, if (gap > 0) name_a else name_b)
}

#' The market line in words for this prediction, or NULL when there is none.
#'
#' Only shown when the pair is on the slate, has a line, and the picked site
#' is the real one. A line for a different site would be misleading.
describe_market <- function(pred, slate) {
  a_id <- pred$team_a$team_id
  game <- find_slate_game(slate, a_id, pred$team_b$team_id)
  if (is.null(game) || is.na(game$market_spread_home)) return(NULL)
  if (!site_matches_game(pred$site, game, a_id)) return(NULL)

  name_a <- pred$team_a$school
  name_b <- pred$team_b$school
  market <- market_margin_for_a(game, a_id)
  market_line <- format_favorite(market, name_a, name_b)
  gap <- market_gap_phrase(pred$spread - market, name_a, name_b)
  sprintf("%s %s%s.",
          if (market_line == "Pick'em") "The market calls it a pick'em." else sprintf("The market has %s.", market_line),
          toupper(substr(gap, 1, 1)), substr(gap, 2, nchar(gap)))
}

# Line movement and notes --------------------------------------------------------

#' The weekday a prediction was saved, such as "Tuesday", or NA.
#' Uses fixed English names so it does not depend on the locale.
weekday_name <- function(time) {
  day <- suppressWarnings(as.integer(format(parse_utc(time), "%u", tz = "UTC")))
  if (length(day) != 1 || is.na(day)) return(NA_character_)
  c("Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday")[day]
}

#' Has this slate game's line moved enough to mention?
line_moved <- function(move) !is.na(move) & abs(move) >= LINE_MOVE_POINTS

#' A plain note when a slate game's line has moved LINE_MOVE_POINTS or more
#' since our prediction was saved, or NULL.
#'
#' @param game One slate row, with market_move (positive = toward home).
#' @param frozen_at When the prediction was saved, or NA.
line_move_note <- function(game, home_name, away_name, frozen_at = NA) {
  if (is.null(game) || !isTRUE(line_moved(game$market_move))) return(NULL)
  day <- weekday_name(frozen_at)
  sprintf("The line has moved %s points toward %s since %s. That usually means news.",
          format_points(game$market_move), if (game$market_move > 0) home_name else away_name,
          if (is.na(day)) "our prediction was saved" else day)
}

#' Compact text markers for a slate row, such as "Line moved 3" and "2 notes".
#' Returns HTML for the DT cell, or "" when there is nothing to mark.
slate_markers <- function(move, n_notes) {
  parts <- c(
    if (isTRUE(line_moved(move))) paste("Line moved", format_points(move)),
    if (n_notes > 0) sprintf("%d %s", n_notes, if (n_notes == 1) "note" else "notes")
  )
  if (length(parts) == 0) return("")
  sprintf('<span class="slate-markers">%s</span>',
          paste(sprintf('<span class="slate-marker">%s</span>', parts), collapse = " "))
}

NOTE_LABELS <- c(availability = "Availability", weather = "Weather")

#' "ESPN, checked Nov 12": the source as a link that opens in a new tab.
#' Only http and https links are made clickable.
note_source <- function(note) {
  url <- note$source_url
  name <- if (is.na(note$source)) NA_character_ else note$source
  linkable <- !is.na(url) && grepl("^https?://", url, ignore.case = TRUE)
  if (linkable && is.na(name)) name <- sub("^https?://(www\\.)?([^/]+).*$", "\\2", url, ignore.case = TRUE)
  checked <- tryCatch(short_date(substr(note$checked_at, 1, 10)), error = function(e) NA)
  if (is.na(name) && is.na(checked)) return(NULL)

  checked_text <- if (is.na(checked)) NULL else paste0(if (!is.na(name)) ", checked " else "Checked ", checked)
  # .noWS keeps the comma right after the link instead of a space before it.
  if (!linkable) {
    return(htmltools::span(class = "note-source", paste0(if (!is.na(name)) name, checked_text)))
  }
  link <- htmltools::tags$a(href = url, target = "_blank", rel = "noopener", name, .noWS = "outside")
  htmltools::span(class = "note-source", link, checked_text, .noWS = "inside")
}

#' The "Notes for this game" section, or NULL when there are none.
#'
#' @param notes Rows from load_notes() for one game.
#' @param title_id Id for the heading, so the section is labeled by it.
game_notes <- function(notes, title_id) {
  if (is.null(notes) || nrow(notes) == 0) return(NULL)
  items <- lapply(seq_len(nrow(notes)), function(i) {
    note <- notes[i, , drop = FALSE]
    kind <- c(unname(NOTE_LABELS[note$category]), note$team)
    kind <- kind[!is.na(kind)]
    htmltools::tags$li(
      if (length(kind) > 0) htmltools::span(class = "note-kind", paste(kind, collapse = ", ")),
      htmltools::span(class = "note-text", note$note),
      note_source(note)
    )
  })
  htmltools::tags$section(
    class = "game-notes", `aria-labelledby` = title_id,
    htmltools::tags$h3(id = title_id, class = "game-notes-title", "Notes for this game"),
    htmltools::tags$ul(class = "game-notes-list", items)
  )
}

# Numbers in tables ------------------------------------------------------------

#' A rating as shown in tables. Elo is a whole number; the rest are points.
#' Uses a real minus sign so negative ratings line up and read cleanly.
format_rating <- function(rating, model) {
  if (is.na(rating)) return("No rating")
  text <- if (model == "elo") sprintf("%d", as.integer(round(rating))) else sprintf("%.1f", abs(rating))
  if (model != "elo" && rating < 0) text <- paste0("−", text)
  text
}

#' "12.4 (#3)" style cell.
format_rating_rank <- function(rating, rank, model) {
  if (is.na(rating)) return("No rating")
  rank_text <- if (is.na(rank)) "" else sprintf(" (#%d)", as.integer(rank))
  paste0(format_rating(rating, model), rank_text)
}

#' A weight as a whole percent.
format_weight <- function(weight) {
  ifelse(is.na(weight) | weight == 0, "Left out", paste0(round(weight * 100), "%"))
}

# Small UI pieces ----------------------------------------------------------------

#' Inline SVG icon. A handful of simple shapes, so we need no icon font.
svg_icon <- function(name, class = NULL) {
  paths <- list(
    swap    = "M7 4 3 8l4 4M3 8h14M17 20l4-4-4-4M21 16H7",
    copy    = "M9 9h11v11H9zM5 15H4V4h11v1",
    check   = "M4 12l5 5L20 6",
    info    = "M12 8h.01M11 12h1v5h1M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18z",
    chevron = "M9 6l6 6-6 6",
    alert   = "M12 9v4M12 17h.01M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z"
  )
  htmltools::tags$svg(
    class = paste("icon", class), viewBox = "0 0 24 24", width = "1em", height = "1em",
    fill = "none", stroke = "currentColor", `stroke-width` = "2",
    `stroke-linecap` = "round", `stroke-linejoin` = "round", `aria-hidden` = "true",
    focusable = "false",
    htmltools::tags$path(d = paths[[name]])
  )
}

#' Plain-language notes, one per line, or nothing when there are none.
flag_list <- function(flags) {
  if (length(flags) == 0) return(NULL)
  htmltools::tags$ul(
    class = "flag-list", `aria-label` = "Notes about this prediction",
    lapply(flags, function(flag) htmltools::tags$li(svg_icon("info"), htmltools::tags$span(flag)))
  )
}

#' A friendly "nothing here yet" panel.
empty_state <- function(title, ...) {
  htmltools::div(
    class = "empty-state",
    htmltools::tags$p(class = "empty-state-title", title),
    htmltools::div(class = "empty-state-body", ...)
  )
}

#' A small, plain HTML table that scrolls sideways inside its card on phones.
#'
#' @param df Data frame whose values are already formatted for display.
#' @param headers Column labels (strings or tags), same length as ncol(df).
#' @param numeric Logical per column; numeric columns are right-aligned.
#' @param row_class Optional CSS class per row.
simple_table <- function(df, headers = names(df), numeric = rep(FALSE, ncol(df)),
                         row_class = NULL, caption = NULL) {
  cell_class <- ifelse(numeric, "num", "")
  rows <- lapply(seq_len(nrow(df)), function(i) {
    htmltools::tags$tr(
      class = row_class[i],
      lapply(seq_along(df), function(j) htmltools::tags$td(class = cell_class[j], df[[j]][i]))
    )
  })
  htmltools::div(
    class = "table-scroll",
    htmltools::tags$table(
      class = "table table-sm data-table",
      if (!is.null(caption)) htmltools::tags$caption(caption),
      htmltools::tags$thead(htmltools::tags$tr(
        lapply(seq_along(headers), function(j) {
          htmltools::tags$th(scope = "col", class = cell_class[j], headers[[j]])
        })
      )),
      htmltools::tags$tbody(rows)
    )
  )
}

#' The slim notice shown in demo mode or when real data failed to load.
data_banner <- function(meta, load_error = NULL) {
  if (!is.null(load_error)) {
    return(htmltools::div(
      class = "data-banner data-banner-error", role = "alert",
      svg_icon("alert"),
      htmltools::tags$span(
        load_error, " Rebuild it with ", htmltools::tags$code("Rscript scripts/refresh.R", .noWS = "outside"),
        ". Showing made-up demo data until then."
      )
    ))
  }
  if (!isTRUE(meta$is_demo)) return(NULL)
  htmltools::div(
    class = "data-banner", role = "note",
    svg_icon("info"),
    htmltools::tags$span(
      htmltools::tags$strong("Demo mode."),
      " These teams and ratings are made up. To load real teams, follow \"Use real data\" in the README."
    )
  )
}

#' Footer text, small and out of the way.
app_footer <- function() {
  htmltools::tags$footer(
    class = "app-footer",
    "Data from CollegeFootballData.com via cfbfastR. Not betting advice. ",
    "Made in collaboration with AI (Claude by Anthropic)."
  )
}
