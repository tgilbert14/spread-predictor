# Small charts built from plain HTML and CSS (styles in www/styles.css,
# "Charts").
#
# Why not ggplot: these are a handful of numbers each, and HTML stays sharp
# on a phone, reflows with the page, animates in, and reads out as text to a
# screen reader. Trend lines and the calibration curve still use ggplot.
#
# Every chart puts its numbers on the page as text, so nothing depends on
# reading a position by eye.

#' Where a value sits on a chart's track, as a percentage from the left.
#'
#' The track is zoomed to the values, with room at both ends, because these
#' charts compare numbers that are close together (12.1 against 12.5). The
#' ends of the track are printed under it so the zoom is plain to see.
#'
#' @return list(at = percentages, low, high).
chart_scale <- function(values, pad = 0.25) {
  span <- range(values, na.rm = TRUE)
  room <- max(diff(span) * pad, 0.2)
  low <- floor((span[1] - room) * 10) / 10
  high <- ceiling((span[2] + room) * 10) / 10
  list(at = (values - low) / (high - low) * 100, low = low, high = high)
}

chart_axis <- function(scale, note, digits = 1) {
  htmltools::div(
    class = "chart-axis", `aria-hidden` = "true",
    htmltools::span(formatC(scale$low, format = "f", digits = digits)),
    htmltools::span(class = "chart-axis-note", note),
    htmltools::span(formatC(scale$high, format = "f", digits = digits))
  )
}

#' One dot per row on a shared scale: the quick way to compare a few numbers.
#'
#' @param labels Row names.
#' @param values One number per row.
#' @param highlight TRUE for the rows that are ours (drawn in the accent).
#' @param benchmark TRUE for the one row everything is measured against. Its
#'   value is drawn as a line through every row.
#' @param note Printed under the track, e.g. "Average miss in points. Left is better."
#' @param detail Optional extra text per row, shown small under the label.
dot_chart <- function(labels, values, highlight = rep(FALSE, length(values)),
                      benchmark = rep(FALSE, length(values)), note = "", digits = 1,
                      detail = NULL, benchmark_label = "Benchmark") {
  scale <- chart_scale(values)
  ref <- if (any(benchmark)) scale$at[which(benchmark)[1]] else NA
  rows <- lapply(seq_along(values), function(i) {
    htmltools::div(
      class = paste("chart-row", if (highlight[i]) "is-ours", if (benchmark[i]) "is-benchmark"),
      htmltools::span(
        class = "chart-label", labels[i],
        if (benchmark[i]) htmltools::span(class = "chart-tag", benchmark_label),
        if (!is.null(detail)) htmltools::span(class = "chart-detail", detail[i])
      ),
      htmltools::span(
        class = "chart-track", `aria-hidden` = "true",
        if (!is.na(ref)) htmltools::span(class = "chart-ref", style = sprintf("left:%.1f%%", ref)),
        htmltools::span(class = "chart-dot", style = sprintf("--at:%.1f%%", scale$at[i]))
      ),
      htmltools::span(class = "chart-value", formatC(values[i], format = "f", digits = digits))
    )
  })
  htmltools::div(class = "chart dot-chart", rows, chart_axis(scale, note, digits))
}

#' Two dots per row joined by a line: ours against the market, row by row.
#'
#' @param ours,theirs One number per row. `theirs` may be NA.
dumbbell_chart <- function(labels, ours, theirs, our_name = "Us", their_name = "Market", note = "",
                           digits = 1) {
  scale <- chart_scale(c(ours, theirs))
  at_ours <- scale$at[seq_along(ours)]
  at_theirs <- scale$at[length(ours) + seq_along(theirs)]
  rows <- lapply(seq_along(ours), function(i) {
    both <- !is.na(theirs[i])
    left <- if (both) min(at_ours[i], at_theirs[i]) else at_ours[i]
    width <- if (both) abs(at_ours[i] - at_theirs[i]) else 0
    htmltools::div(
      class = "chart-row",
      htmltools::span(class = "chart-label", labels[i]),
      htmltools::span(
        class = "chart-track", `aria-hidden` = "true",
        if (both) htmltools::span(class = "chart-link", style = sprintf("left:%.1f%%;width:%.1f%%", left, width)),
        if (both) htmltools::span(class = "chart-dot is-theirs", style = sprintf("--at:%.1f%%", at_theirs[i])),
        htmltools::span(class = "chart-dot is-ours", style = sprintf("--at:%.1f%%", at_ours[i]))
      ),
      htmltools::span(
        class = "chart-value chart-value-pair",
        htmltools::span(class = "is-ours", formatC(ours[i], format = "f", digits = digits)),
        if (both) htmltools::span(class = "is-theirs", formatC(theirs[i], format = "f", digits = digits))
      )
    )
  })
  htmltools::div(
    class = "chart dot-chart dumbbell-chart",
    chart_legend(our_name, their_name),
    rows, chart_axis(scale, note, digits)
  )
}

#' The key for a chart with our dots and the market's.
chart_legend <- function(our_name = "Us", their_name = "Market") {
  htmltools::div(
    class = "chart-legend", `aria-hidden` = "true",
    htmltools::span(htmltools::span(class = "chart-key is-ours"), our_name),
    htmltools::span(htmltools::span(class = "chart-key is-theirs"), their_name)
  )
}

#' One bar split in two: how a count divides between us and the market.
#'
#' @param ours,theirs Counts. `even` is drawn between them when above zero.
versus_bar <- function(ours, theirs, even = 0, our_name = "Us", their_name = "Market") {
  total <- ours + theirs + even
  if (total == 0) return(NULL)
  part <- function(n, class, name) {
    if (n == 0) return(NULL)
    htmltools::span(
      class = paste("versus-part", class), style = sprintf("--share:%.2f%%", n / total * 100),
      htmltools::span(class = "versus-count", n), htmltools::span(class = "versus-name", name)
    )
  }
  htmltools::div(
    class = "versus-bar",
    part(ours, "is-ours", our_name), part(even, "is-even", "Even"), part(theirs, "is-theirs", their_name)
  )
}

#' A share drawn as a ring with the number in the middle.
#'
#' @param share 0 to 1, or NA when there is nothing to count.
#' @param help One or two plain sentences under it.
ring_stat <- function(label, share, value, help) {
  around <- 2 * pi * 42
  filled <- if (is.na(share)) 0 else max(0, min(1, share)) * around
  htmltools::div(
    class = "ring-stat",
    htmltools::div(
      class = "ring",
      htmltools::tags$svg(
        viewBox = "0 0 100 100", `aria-hidden` = "true", focusable = "false",
        htmltools::tags$circle(class = "ring-track", cx = 50, cy = 50, r = 42),
        htmltools::tags$circle(class = "ring-fill", cx = 50, cy = 50, r = 42,
                               style = sprintf("--filled:%.1f;--around:%.1f", filled, around))
      ),
      htmltools::span(class = "ring-value", `data-count` = if (!is.na(share)) "", value)
    ),
    htmltools::div(
      class = "ring-text",
      htmltools::p(class = "stat-label", label),
      htmltools::p(class = "stat-help", help)
    )
  )
}

#' Bars that grow left or right from a center line: who was closer, and by
#' how much.
#'
#' @param labels One per row; may be HTML (pass htmltools::HTML()).
#' @param values Positive grows right (ours), negative grows left (theirs).
#' @param text What to print beside each bar, e.g. "Us, by 9.5".
#' @param hover A longer line per row, shown when the row is tapped or clicked.
swing_chart <- function(labels, values, text, hover = NULL, our_name = "We were closer",
                        their_name = "Market was closer") {
  if (length(values) == 0) return(NULL)
  longest <- max(abs(values), 1)
  rows <- lapply(seq_along(values), function(i) {
    ours <- values[i] >= 0
    # With a longer line to show, the row is a button: tap it to open the line.
    htmltools::tag(if (is.null(hover)) "div" else "button", list(
      class = paste("chart-row swing-row", if (ours) "is-ours" else "is-theirs"),
      type = if (!is.null(hover)) "button", `aria-expanded` = if (!is.null(hover)) "false",
      htmltools::span(class = "chart-label", labels[[i]]),
      htmltools::span(
        class = "swing-track", `aria-hidden` = "true",
        htmltools::span(class = "swing-bar", style = sprintf("--size:%.1f%%", abs(values[i]) / longest * 50))
      ),
      htmltools::span(class = "chart-value", text[i]),
      if (!is.null(hover)) htmltools::span(class = "swing-more", hover[i])
    ))
  })
  htmltools::div(
    class = "chart swing-chart",
    htmltools::div(class = "swing-heads", `aria-hidden` = "true",
                   htmltools::span(their_name), htmltools::span(our_name)),
    rows
  )
}

#' One strip cut into shares, each labeled: how the blend is made up.
#'
#' @param shares Numbers that add to 1.
share_strip <- function(labels, shares) {
  htmltools::div(
    class = "share-strip",
    lapply(seq_along(shares), function(i) {
      htmltools::span(
        class = "share-part", style = sprintf("--share:%.2f%%", shares[i] * 100),
        htmltools::span(class = "share-name", labels[i]),
        htmltools::span(class = "share-value", sprintf("%.0f%%", shares[i] * 100))
      )
    })
  )
}

#' A grid of small tiles, one per cell, for "is everything here?" tables.
#'
#' @param row_labels,col_labels Names down the side and across the top.
#' @param ok Logical matrix: TRUE draws a filled tile, FALSE a marked gap.
#' @param hover Character matrix of the same shape, shown on hover.
tile_grid <- function(row_labels, col_labels, ok, hover = NULL) {
  header <- htmltools::tags$tr(
    htmltools::tags$th(scope = "col", class = "tile-corner", ""),
    lapply(col_labels, function(label) htmltools::tags$th(scope = "col", label))
  )
  body <- lapply(seq_along(row_labels), function(i) {
    htmltools::tags$tr(
      htmltools::tags$th(scope = "row", row_labels[i]),
      lapply(seq_along(col_labels), function(j) {
        htmltools::tags$td(htmltools::span(
          class = paste("tile", if (ok[i, j]) "is-ok" else "is-missing"),
          title = if (!is.null(hover)) hover[i, j],
          htmltools::span(class = "visually-hidden", if (ok[i, j]) "Saved" else "Missing")
        ))
      })
    )
  })
  htmltools::tags$table(class = "tile-grid", htmltools::tags$thead(header), htmltools::tags$tbody(body))
}

#' The numbers behind a chart, folded away until someone wants them.
chart_details <- function(summary, ...) {
  htmltools::tags$details(class = "chart-details", htmltools::tags$summary(summary), ...)
}
