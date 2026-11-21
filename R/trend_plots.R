# The two "through the season" charts on the Matchup tab: how each system's
# line for this matchup has moved week to week, and how each team's rating
# has moved in every system. Both read the snapshot history (R/snapshot.R).

# One fixed color per rating system, so a system keeps its color whichever
# others are on the chart. Checked for color-blind separation as a set. The
# three lightest fall under 3:1 against the page, so the chart is never the
# only place a value is shown: the table above it and the readout under it
# carry the same numbers. The blend is drawn in ink.
MODEL_COLORS <- c(sp = "#2a78d6", fpi = "#eb6834", srs = "#1baf7a", elo = "#eda100", power = "#e87ba4")

#' Shared look for the trend charts: quiet grid, muted axes, clear ground.
trend_theme <- function() {
  ggplot2::theme_minimal(base_size = 15) +
    ggplot2::theme(
      text = ggplot2::element_text(color = BRAND$text),
      axis.text = ggplot2::element_text(color = BRAND$muted),
      axis.title = ggplot2::element_text(color = BRAND$muted, size = 13),
      panel.grid.major = ggplot2::element_line(color = BRAND$border, linewidth = 0.4),
      panel.grid.minor = ggplot2::element_blank(),
      legend.position = "top",
      legend.justification = "left",
      legend.title = ggplot2::element_blank(),
      legend.text = ggplot2::element_text(color = BRAND$text, size = 13),
      legend.margin = ggplot2::margin(0, 0, 0, 0),
      strip.text = ggplot2::element_text(color = BRAND$text, face = "bold", hjust = 0, size = 13),
      plot.background = ggplot2::element_rect(fill = "transparent", color = NA),
      panel.background = ggplot2::element_rect(fill = "transparent", color = NA)
    )
}

#' Whole-week axis breaks that never crowd: every week up to 8, then every other.
week_breaks <- function(weeks) {
  all <- seq(min(weeks), max(weeks))
  if (length(all) <= 8) all else all[all %% 2 == max(weeks) %% 2]
}

#' Axis labels for a margin: "UTAH by 7", "ARIZ by 7" or "Even".
margin_labels <- function(team_a, team_b) {
  function(margins) {
    vapply(margins, function(margin) {
      if (is.na(margin)) "" else short_favorite(margin, team_a, team_b)
    }, character(1))
  }
}

#' How each system's line for this matchup moved from week to week.
#'
#' @param trend What matchup_trend() returns.
#' @param pred The prediction on show, for the team names.
#' @param selected_week The snapshot week on show, marked on the chart.
#' @param narrow TRUE on a phone: the legend wraps and the end label gets
#'   more room.
matchup_trend_plot <- function(trend, pred, selected_week, narrow = FALSE) {
  systems <- trend[trend$model != "blend", , drop = FALSE]
  systems$label <- factor(systems$label, levels = unname(MODEL_LABELS))
  blend <- trend[trend$model == "blend", , drop = FALSE]
  colors <- stats::setNames(unname(MODEL_COLORS[names(MODEL_LABELS)]), unname(MODEL_LABELS))

  ggplot2::ggplot(systems, ggplot2::aes(x = week, y = margin)) +
    ggplot2::geom_hline(yintercept = 0, color = BRAND$muted, linewidth = 0.5) +
    ggplot2::geom_vline(xintercept = selected_week, color = BRAND$muted, linetype = "dotted", linewidth = 0.6) +
    ggplot2::geom_line(ggplot2::aes(color = label, group = label), linewidth = 0.9) +
    ggplot2::geom_point(ggplot2::aes(color = label), size = 2.4) +
    # The blend is dashed through the weeks where it is missing a system and
    # solid where all five are in it.
    ggplot2::geom_line(data = blend, color = BRAND$text, linewidth = 1.1, linetype = "22") +
    ggplot2::geom_line(data = blend[blend$complete, , drop = FALSE], color = BRAND$text, linewidth = 1.6) +
    ggplot2::geom_point(data = blend, color = BRAND$text, fill = BRAND$accent, shape = 21, size = 3.4, stroke = 1.3) +
    ggplot2::annotate("text", x = max(trend$week), y = blend$margin[which.max(blend$week)],
                      label = "Blend", hjust = -0.35, color = BRAND$text, fontface = "bold",
                      size = if (narrow) 3.8 else 4.4) +
    ggplot2::scale_color_manual(values = colors, drop = TRUE) +
    ggplot2::scale_x_continuous("Week", breaks = week_breaks(trend$week),
                                expand = ggplot2::expansion(mult = c(0.03, if (narrow) 0.24 else 0.13))) +
    ggplot2::scale_y_continuous(NULL, labels = margin_labels(pred$team_a, pred$team_b),
                                expand = ggplot2::expansion(mult = 0.12)) +
    ggplot2::guides(color = ggplot2::guide_legend(nrow = if (narrow) 2 else 1, override.aes = list(linewidth = 1.2, size = 2.6))) +
    trend_theme()
}

#' The chart in words, for screen readers: where the blend started and ended.
matchup_trend_alt <- function(trend, pred) {
  blend <- trend[trend$model == "blend", , drop = FALSE]
  blend <- blend[order(blend$week), , drop = FALSE]
  line <- function(i) format_favorite(blend$margin[i], pred$team_a$school, pred$team_b$school)
  if (nrow(blend) == 1) {
    return(sprintf("Line chart with one week so far. Week %d blend: %s.", blend$week, line(1)))
  }
  sprintf("Line chart of each rating system's margin by week. The blend went from %s in week %d to %s in week %d.",
          line(1), blend$week[1], line(nrow(blend)), blend$week[nrow(blend)])
}

#' One week of the matchup chart in words: "Week 9: Elo UTAH by 2, ...".
#' Shown under the chart for the week being hovered or tapped.
matchup_trend_readout <- function(trend, week, pred) {
  rows <- trend[trend$week == week, , drop = FALSE]
  if (nrow(rows) == 0) return(NULL)
  rows <- rows[match(c(names(MODEL_LABELS), "blend"), rows$model, nomatch = 0), , drop = FALSE]
  values <- vapply(rows$margin, short_favorite, character(1), team_a = pred$team_a, team_b = pred$team_b)
  sprintf("Week %d: %s.", week, paste(rows$label, values, collapse = ", "))
}

#' Each team's rating by week, one small panel per system.
#'
#' The systems sit in separate panels because Elo runs on its own scale.
#'
#' @param ratings What rating_trend() returns for the two teams.
#' @param colors c(a = , b = ) from pick_team_colors().
#' @param columns Panels per row: fewer on a narrow screen.
rating_trend_plot <- function(ratings, pred, colors, selected_week, columns = 3) {
  ratings$label <- factor(ratings$label, levels = unname(MODEL_LABELS))
  ratings$team <- factor(ifelse(ratings$team_id == pred$team_a$team_id,
                                pred$team_a$school, pred$team_b$school),
                         levels = c(pred$team_a$school, pred$team_b$school))
  team_colors <- stats::setNames(unname(colors[c("a", "b")]), levels(ratings$team))
  weeks <- range(ratings$week)

  ggplot2::ggplot(ratings, ggplot2::aes(x = week, y = rating, color = team, group = team)) +
    ggplot2::geom_vline(xintercept = selected_week, color = BRAND$muted, linetype = "dotted", linewidth = 0.6) +
    ggplot2::geom_line(linewidth = 0.9) +
    ggplot2::geom_point(size = 2.2) +
    ggplot2::facet_wrap(~label, scales = "free_y", ncol = columns) +
    ggplot2::scale_color_manual(values = team_colors) +
    ggplot2::scale_x_continuous("Week", breaks = week_breaks(weeks), limits = weeks + c(-0.3, 0.3)) +
    ggplot2::scale_y_continuous(NULL) +
    trend_theme() +
    ggplot2::theme(panel.spacing = ggplot2::unit(1.1, "lines"))
}

#' The ratings chart in words: each team's first and latest Power rating.
rating_trend_alt <- function(ratings, pred) {
  describe <- function(team) {
    rows <- ratings[ratings$team_id == team$team_id & ratings$model == "power", , drop = FALSE]
    rows <- rows[order(rows$week), , drop = FALSE]
    if (nrow(rows) == 0) return(NULL)
    sprintf("%s's Power rating went from %s in week %d to %s in week %d.", team$school,
            format_rating(rows$rating[1], "power"), rows$week[1],
            format_rating(rows$rating[nrow(rows)], "power"), rows$week[nrow(rows)])
  }
  paste(c("Line charts of each team's rating by week, one panel per rating system.",
          describe(pred$team_a), describe(pred$team_b)), collapse = " ")
}
