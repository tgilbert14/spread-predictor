# Model report tab: how the number is made, what was fitted, and how well it
# has done. Every table here may be empty or missing in real data, so each
# section says so plainly instead of breaking.

#' @param app_data See docs/data-dictionary.md.
mod_report_ui <- function(id, app_data) {
  ns <- shiny::NS(id)
  params <- app_data$params

  htmltools::div(
    class = "page-wide report",
    report_section("How the number is made", how_it_works()),
    htmltools::tags$section(
      class = "report-block", `aria-labelledby` = ns("fit-title"),
      htmltools::tags$h2(id = ns("fit-title"), class = "section-title", "What the model learned"),
      htmltools::p(class = "section-lede", fit_caption(params)),
      report_grid(param_cards(params), min_width = "220px")
    ),
    report_grid(list(
      report_section("Accuracy", accuracy_block(params$metrics)),
      report_section("Calibration", calibration_block(ns, params$calibration))
    )),
    report_grid(list(
      report_section("Season by season", folds_block(params$folds)),
      report_section("Leaked check", leaked_block(params$leaked_diagnostic), badge = "Not used for fitting")
    )),
    report_section("Snapshot coverage", coverage_block(app_data$coverage))
  )
}

#' Cards side by side when there is room, stacked on phones.
report_grid <- function(cards, min_width = "420px") {
  htmltools::div(class = "report-grid", style = sprintf("--min-col:%s", min_width), cards)
}

#' A titled card.
report_section <- function(title, body, badge = NULL) {
  htmltools::tags$section(
    class = "card report-card",
    htmltools::div(
      class = "card-body",
      htmltools::tags$h2(class = "section-title", title,
                         if (!is.null(badge)) htmltools::span(class = "pill pill-warn", badge)),
      body
    )
  )
}

#' TRUE when a params table has rows to show.
has_rows <- function(df) is.data.frame(df) && nrow(df) > 0

how_it_works <- function() {
  htmltools::div(
    class = "prose",
    htmltools::p(
      "Four public rating systems (SP+, FPI, SRS and Elo) each score every team by how strong it has played. ",
      "The first three say how many points better a team is than an average one; Elo uses its own scale, ",
      "which we convert to points. ",
      "The gap between two teams' ratings is each system's predicted margin, and we average those margins ",
      "using the weights below. ",
      "If one team is at home, we add a few points for home field. ",
      "Finally, we turn the margin into a win chance using how far real results have landed from our numbers in past seasons."
    )
  )
}

fit_caption <- function(params) {
  seasons <- params$training_seasons
  season_text <- if (length(seasons) > 0) {
    sprintf(" using the %s to %s seasons", min(seasons), max(seasons))
  } else {
    ""
  }
  fit_date <- tryCatch(format_long_date(params$fit_date), error = function(e) NULL)
  if (is.null(fit_date)) return(paste0("Fitted", season_text, "."))
  sprintf("Fitted on %s%s.", fit_date, season_text)
}

#' "Nov 9, 2026".
format_long_date <- function(date) {
  date <- as.Date(date)
  paste0(short_date(date), ", ", format(date, "%Y"))
}

stat_card <- function(label, value, explanation) {
  htmltools::div(
    class = "card stat-card",
    htmltools::div(
      class = "card-body",
      htmltools::p(class = "stat-label", label),
      htmltools::p(class = "stat-value", value),
      htmltools::p(class = "stat-help", explanation)
    )
  )
}

param_cards <- function(params) {
  weights <- unlist(params$weights)[names(MODEL_LABELS)]
  method <- if (identical(params$weights_method, "fitted")) "Fitted weights" else "Equal weights"
  method_help <- if (identical(params$weights_method, "fitted")) {
    "How much each system counts, learned from past games."
  } else {
    "Each system counts the same. Simple and hard to overfit."
  }
  list(
    stat_card("Home field", paste(format_points(params$h), "points"),
              "Added to the home team's side. Nothing on a neutral field."),
    stat_card("Typical miss", paste(format_points(params$sigma), "points"),
              "About two games in three land within this many points of our line."),
    stat_card("Elo conversion", paste(round(params$k, 1), "Elo = 1 point"),
              "Elo is not in points, so we divide an Elo gap by this number."),
    stat_card(
      method,
      htmltools::span(class = "weights", lapply(names(weights), function(m) {
        htmltools::span(class = "weight-chip", MODEL_LABELS[[m]], htmltools::strong(format_weight(weights[[m]])))
      })),
      method_help
    )
  )
}

accuracy_block <- function(metrics) {
  if (!has_rows(metrics)) return(empty_state("No accuracy results yet.", "They appear after the model is fitted."))
  is_line <- metrics$model == "line"
  rows <- data.frame(
    label = metrics$label,
    n = format(metrics$n, big.mark = ","),
    mae = sprintf("%.1f", metrics$mae),
    win_rate = sprintf("%.0f%%", metrics$win_rate * 100),
    brier = sprintf("%.3f", metrics$brier),
    stringsAsFactors = FALSE
  )
  htmltools::tagList(
    htmltools::p(class = "section-lede",
                 "The closing line is the benchmark. It is the betting market's final number and the ",
                 "hardest public forecast to beat, so getting close to it is the goal."),
    simple_table(rows, c("Forecast", "Games", "Avg miss (pts)", "Picked winner", "Brier"),
                 numeric = c(FALSE, TRUE, TRUE, TRUE, TRUE),
                 row_class = ifelse(is_line, "is-benchmark", "")),
    htmltools::p(class = "fine-print",
                 "Avg miss: average gap between predicted and real margin. Brier: error in the win chances, lower is better.")
  )
}

calibration_block <- function(ns, calibration) {
  if (!has_rows(calibration)) return(empty_state("No calibration results yet.", "They appear after the model is fitted."))
  htmltools::tagList(
    htmltools::p(class = "section-lede",
                 "Dots on the dashed line mean that when we give a team a 70% chance, it wins about 70% of the time. ",
                 "Bigger dots stand for more games."),
    shiny::plotOutput(ns("calibration"), height = "300px")
  )
}

#' Calibration chart, styled for the dark theme.
calibration_plot <- function(calibration) {
  # Favorites can win less than half the time in a small bin. Stretch the
  # axis down to fit, so no point is silently dropped.
  y_low <- min(0.5, floor(min(calibration$actual) * 10) / 10)
  ggplot2::ggplot(calibration, ggplot2::aes(x = predicted, y = actual)) +
    ggplot2::geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = BRAND$muted, linewidth = 0.7) +
    ggplot2::geom_line(color = BRAND$text, linewidth = 1) +
    ggplot2::geom_point(ggplot2::aes(size = n), color = BRAND$text, fill = BRAND$accent,
                        shape = 21, stroke = 1.8) +
    ggplot2::scale_x_continuous("Our win chance", limits = c(0.5, 1), labels = percent_label) +
    ggplot2::scale_y_continuous("How often they won", limits = c(y_low, 1), labels = percent_label) +
    ggplot2::scale_size_area(max_size = 8, guide = "none") +
    ggplot2::theme_minimal(base_size = 16) +
    ggplot2::theme(
      text = ggplot2::element_text(color = BRAND$text),
      axis.text = ggplot2::element_text(color = BRAND$muted),
      axis.title = ggplot2::element_text(color = BRAND$muted, size = 14),
      panel.grid.major = ggplot2::element_line(color = BRAND$border, linewidth = 0.5),
      panel.grid.minor = ggplot2::element_blank(),
      plot.background = ggplot2::element_rect(fill = "transparent", color = NA),
      panel.background = ggplot2::element_rect(fill = "transparent", color = NA)
    )
}

percent_label <- function(x) paste0(round(x * 100), "%")

#' Text alternative for the calibration chart.
calibration_alt <- function(calibration) {
  paste0("Calibration chart. Our win chance versus how often teams won: ",
         paste(sprintf("%.0f%% predicted, %.0f%% actual", calibration$predicted * 100,
                       calibration$actual * 100), collapse = "; "), ".")
}

folds_block <- function(folds) {
  if (!has_rows(folds)) return(empty_state("No season-by-season results yet.", "They appear after the model is fitted."))
  rows <- data.frame(
    season = as.character(folds$season),
    k = sprintf("%.1f", folds$k), h = sprintf("%.1f", folds$h),
    sigma = sprintf("%.1f", folds$sigma), mae = sprintf("%.1f", folds$mae)
  )
  htmltools::tagList(
    htmltools::p(class = "section-lede",
                 "Each row fits on every other season and tests on this one. Steady numbers mean the fit is not a fluke."),
    simple_table(rows, c("Held-out season", "Elo per point", "Home field", "Typical miss", "Avg miss"),
                 numeric = c(FALSE, TRUE, TRUE, TRUE, TRUE))
  )
}

leaked_block <- function(leaked) {
  if (!has_rows(leaked)) return(empty_state("No leaked check yet.", "It appears after the model is fitted."))
  label <- ifelse(leaked$model %in% names(MODEL_LABELS), MODEL_LABELS[leaked$model], leaked$model)
  rows <- data.frame(model = label, n = format(leaked$n, big.mark = ","), mae = sprintf("%.1f", leaked$mae))
  htmltools::tagList(
    htmltools::p(class = "section-lede",
                 "These use end-of-season ratings that already know how every game turned out, so they look ",
                 "better than any real forecast can. We keep them only to catch bugs."),
    simple_table(rows, c("Rating system", "Games", "Avg miss (pts)"), numeric = c(FALSE, TRUE, TRUE))
  )
}

#' One row per season and week, one column per rating system.
#' Weeks with no snapshot at all are added as rows so a gap stands out.
#' Season-final snapshots have no week; they sort after the last week as "Final".
coverage_grid <- function(coverage) {
  coverage$week_key <- ifelse(is.na(coverage$week), 99L, as.integer(coverage$week))
  weeks <- do.call(rbind, lapply(split(coverage, coverage$season), function(s) {
    in_season <- s$week_key[s$week_key != 99L]
    keys <- if (length(in_season) > 0) seq(min(in_season), max(in_season)) else integer()
    data.frame(season = s$season[1], week_key = sort(unique(c(keys, s$week_key))))
  }))
  weeks <- weeks[order(-weeks$season, -weeks$week_key), , drop = FALSE]

  grid <- data.frame(
    season = as.character(weeks$season),
    week = ifelse(weeks$week_key == 99L, "Final", as.character(weeks$week_key)),
    stringsAsFactors = FALSE
  )
  missing <- matrix(FALSE, nrow(weeks), length(MODEL_LABELS))
  for (j in seq_along(MODEL_LABELS)) {
    src <- names(MODEL_LABELS)[j]
    n <- vapply(seq_len(nrow(weeks)), function(i) {
      hit <- coverage$source == src & coverage$season == weeks$season[i] & coverage$week_key == weeks$week_key[i]
      if (any(hit)) as.integer(coverage$n_teams[which(hit)[1]]) else NA_integer_
    }, integer(1))
    missing[, j] <- is.na(n)
    grid[[src]] <- ifelse(is.na(n), "Missing", paste(n, "teams"))
  }
  list(grid = grid, missing = missing)
}

coverage_block <- function(coverage) {
  if (!has_rows(coverage)) return(empty_state("No snapshots yet.", "Run the data refresh to start collecting them."))
  cov <- coverage_grid(coverage)
  any_missing <- any(cov$missing)
  # Mark missing cells so they read as a problem, in words as well as color.
  grid <- cov$grid
  for (j in seq_along(MODEL_LABELS)) {
    col <- names(MODEL_LABELS)[j]
    grid[[col]] <- lapply(seq_len(nrow(grid)), function(i) {
      if (cov$missing[i, j]) htmltools::span(class = "pill pill-warn", "Missing") else grid[[col]][i]
    })
  }
  htmltools::tagList(
    htmltools::p(class = "section-lede",
                 if (any_missing) "Some weekly snapshots are missing. They are marked below."
                 else "Every week has a snapshot from every rating system."),
    simple_table(grid, c("Season", "Week", unname(MODEL_LABELS)),
                 numeric = c(FALSE, FALSE, rep(TRUE, length(MODEL_LABELS))),
                 row_class = ifelse(rowSums(cov$missing) > 0, "has-missing", ""))
  )
}

mod_report_server <- function(id, app_data) {
  shiny::moduleServer(id, function(input, output, session) {
    # Bins with no games have nothing to plot.
    calibration <- app_data$params$calibration
    if (has_rows(calibration)) calibration <- calibration[!is.na(calibration$actual), , drop = FALSE]
    if (has_rows(calibration)) {
      output$calibration <- shiny::renderPlot(
        calibration_plot(calibration),
        bg = "transparent", alt = calibration_alt(calibration)
      )
    }
  })
}
