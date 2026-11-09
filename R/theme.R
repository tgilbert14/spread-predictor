# Look and feel: the bslib theme, brand tokens, and the color math that keeps
# team colors readable on the page.
#
# The page itself is quiet (navy ink on a light ground) so the two team colors
# can carry each matchup. Team colors are only used on team-specific elements,
# and always next to a text label so color never carries meaning on its own.

#' Brand tokens. www/styles.css mirrors these as CSS variables.
BRAND <- list(
  navy    = "#0a1330",  # ink: text and the navbar
  page    = "#f4f6f8",  # page background
  surface = "#ffffff",  # inputs and plot grounds; team colors are checked against this
  border  = "#d5dae3",
  text    = "#0a1330",
  muted   = "#566080",
  accent  = "#5eead4",  # turquoise, used on the navy navbar and the blend marker
  neutral = "#64748b"   # stand-in when a team has no usable color
)

# WCAG minimums. Text needs 4.5:1; shapes like bar segments and dots need 3:1.
MIN_TEXT_CONTRAST  <- 4.5
MIN_SHAPE_CONTRAST <- 3

# Below this CIE76 distance two colors are hard to tell apart side by side.
MIN_TEAM_COLOR_DISTANCE <- 30

# Fonts ship with the app in www/fonts/ (both are open-licensed), so nothing
# is downloaded at run time.
FONT_BODY <- "\"Instrument Sans\", system-ui, -apple-system, \"Segoe UI\", Roboto, Arial, sans-serif"

#' The app's Bootstrap 5 theme.
app_theme <- function() {
  bslib::bs_theme(
    version = 5,
    bg = BRAND$page,
    fg = BRAND$text,
    primary = BRAND$navy,
    secondary = BRAND$muted,
    success = "#15803d",
    warning = "#b45309",
    danger = "#b91c1c",
    info = BRAND$navy,
    "font-family-sans-serif" = FONT_BODY,
    "body-secondary-color" = BRAND$muted,
    "border-color" = BRAND$border,
    "card-bg" = "transparent",
    "card-border-color" = "transparent",
    "card-cap-bg" = "transparent",
    "navbar-bg" = BRAND$navy,
    "border-radius" = "0.25rem",
    "link-decoration" = "underline"
  )
}

#' Is x a usable "#rrggbb" or "#rgb" color?
is_hex_color <- function(x) {
  is.character(x) & !is.na(x) & grepl("^#?([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$", x)
}

#' Normalize a hex color to "#RRGGBB", or NA when it is not a color.
#' Team data sometimes arrives without the leading "#" or as shorthand.
normalize_hex <- function(x) {
  out <- rep(NA_character_, length(x))
  ok <- is_hex_color(x)
  hex <- sub("^#", "", x[ok])
  short <- nchar(hex) == 3
  hex[short] <- vapply(strsplit(hex[short], ""), function(ch) paste(rep(ch, each = 2), collapse = ""),
                       character(1))
  out[ok] <- paste0("#", toupper(hex))
  out
}

#' Relative luminance of a color, per WCAG 2.
relative_luminance <- function(hex) {
  rgb <- grDevices::col2rgb(normalize_hex(hex))[, 1] / 255
  linear <- ifelse(rgb <= 0.03928, rgb / 12.92, ((rgb + 0.055) / 1.055)^2.4)
  sum(c(0.2126, 0.7152, 0.0722) * linear)
}

#' WCAG contrast ratio between two colors, from 1 to 21.
contrast_ratio <- function(color_1, color_2) {
  l <- sort(c(relative_luminance(color_1), relative_luminance(color_2)), decreasing = TRUE)
  (l[1] + 0.05) / (l[2] + 0.05)
}

#' Black or white, whichever reads better on top of `background`.
readable_text_color <- function(background) {
  if (contrast_ratio(background, "#000000") >= contrast_ratio(background, "#FFFFFF")) {
    "#000000"
  } else {
    "#FFFFFF"
  }
}

#' First candidate color with enough contrast against `background`.
#'
#' @param candidates Hex colors in order of preference (primary, then alt).
#' @return A hex color. Falls back to the brand neutral when none pass.
usable_team_color <- function(candidates, background = BRAND$surface,
                              min_ratio = MIN_SHAPE_CONTRAST) {
  for (color in normalize_hex(candidates)) {
    if (!is.na(color) && contrast_ratio(color, background) >= min_ratio) return(color)
  }
  BRAND$neutral
}

#' Convert a hex color to CIE Lab, for perceptual distance.
hex_to_lab <- function(hex) {
  rgb <- grDevices::col2rgb(normalize_hex(hex))
  drop(grDevices::convertColor(t(rgb) / 255, from = "sRGB", to = "Lab"))
}

#' Perceptual distance between two colors (CIE76 delta E).
color_distance <- function(color_1, color_2) {
  sqrt(sum((hex_to_lab(color_1) - hex_to_lab(color_2))^2))
}

#' Colors for the two teams in a matchup.
#'
#' Each team gets its first readable color. If the two are too alike to tell
#' apart, Team B switches to its alternate, then to a neutral.
#'
#' @param team_a,team_b One-row data frames with `color` and `alt_color`.
#' @return Named character vector: `a` and `b` hex colors.
pick_team_colors <- function(team_a, team_b, background = BRAND$surface) {
  color_a <- usable_team_color(c(team_a$color, team_a$alt_color), background)
  candidates_b <- c(team_b$color, team_b$alt_color, BRAND$neutral, "#1F2937")

  for (color in normalize_hex(candidates_b)) {
    if (is.na(color) || contrast_ratio(color, background) < MIN_SHAPE_CONTRAST) next
    if (color_distance(color, color_a) >= MIN_TEAM_COLOR_DISTANCE) {
      return(c(a = color_a, b = color))
    }
  }
  # Every option clashes (rare). Keep B readable; the text labels carry meaning.
  c(a = color_a, b = usable_team_color(candidates_b, background))
}
