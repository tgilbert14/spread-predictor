test_that("normalize_hex accepts common forms and rejects junk", {
  expect_equal(normalize_hex(c("#abc", "1e3a8a", "#1E3A8A")), c("#AABBCC", "#1E3A8A", "#1E3A8A"))
  expect_true(all(is.na(normalize_hex(c(NA, "", "red", "#12345")))))
})

test_that("contrast_ratio matches the WCAG reference values", {
  expect_equal(contrast_ratio("#000000", "#FFFFFF"), 21)
  expect_equal(contrast_ratio("#777777", "#777777"), 1)
  # Order does not matter.
  expect_equal(contrast_ratio("#5EEAD4", BRAND$navy), contrast_ratio(BRAND$navy, "#5EEAD4"))
})

test_that("brand text colors pass AA on the brand backgrounds", {
  for (bg in c(BRAND$page, BRAND$surface)) {
    expect_gte(contrast_ratio(BRAND$text, bg), MIN_TEXT_CONTRAST)
    expect_gte(contrast_ratio(BRAND$muted, bg), MIN_TEXT_CONTRAST)
  }
  # Turquoise is only used on the navy navbar, never as text on the light page.
  expect_gte(contrast_ratio(BRAND$accent, BRAND$navy), MIN_TEXT_CONTRAST)
})

test_that("readable_text_color picks the stronger of black and white", {
  expect_equal(readable_text_color("#FFFFFF"), "#000000")
  expect_equal(readable_text_color("#0A1330"), "#FFFFFF")
  expect_equal(readable_text_color("#FBBF24"), "#000000")
  for (bg in c("#BE123C", "#5EEAD4", "#78716C", "#1D4ED8")) {
    expect_gte(contrast_ratio(readable_text_color(bg), bg), MIN_TEXT_CONTRAST)
  }
})

test_that("usable_team_color falls back from primary to alt to neutral", {
  blue <- "#1D4ED8"
  expect_equal(usable_team_color(c(blue, "#000000")), blue)
  # A pale primary would vanish on the light page, so the alt is used.
  expect_equal(usable_team_color(c("#FDE047", blue)), blue)
  expect_equal(usable_team_color(c("#FDE047", "#FEF3C7")), BRAND$neutral)
  expect_equal(usable_team_color(c(NA, "not a color")), BRAND$neutral)
})

test_that("color_distance separates alike and different colors", {
  expect_equal(color_distance("#123456", "#123456"), 0)
  expect_lt(color_distance("#38BDF8", "#3AB8F5"), MIN_TEAM_COLOR_DISTANCE)
  expect_gt(color_distance("#38BDF8", "#FBBF24"), MIN_TEAM_COLOR_DISTANCE)
})

test_that("pick_team_colors keeps distinct colors and fixes clashes", {
  team <- function(color, alt) data.frame(color = color, alt_color = alt, stringsAsFactors = FALSE)

  distinct <- pick_team_colors(team("#1D4ED8", "#000000"), team("#BE123C", "#000000"))
  expect_equal(unname(distinct), c("#1D4ED8", "#BE123C"))

  # Same primary: B moves to its alternate.
  clash <- pick_team_colors(team("#1D4ED8", "#BE123C"), team("#1D4ED8", "#166534"))
  expect_equal(clash[["b"]], "#166534")

  # B's primary is too pale to see, so its alt is used.
  pale <- pick_team_colors(team("#BE123C", NA), team("#FDE047", "#1D4ED8"))
  expect_equal(pale[["b"]], "#1D4ED8")

  # Whatever happens, both colors stay visible on the page.
  for (cols in list(distinct, clash, pale)) {
    expect_true(all(vapply(cols, contrast_ratio, numeric(1), BRAND$surface) >= MIN_SHAPE_CONTRAST))
  }
})

test_that("every demo team pairing gets visible, distinguishable colors", {
  teams <- demo_app_data()$teams
  for (i in seq_len(nrow(teams))) for (j in seq_len(nrow(teams))) {
    if (i == j) next
    cols <- pick_team_colors(teams[i, ], teams[j, ])
    expect_gte(contrast_ratio(cols[["a"]], BRAND$surface), MIN_SHAPE_CONTRAST)
    expect_gte(contrast_ratio(cols[["b"]], BRAND$surface), MIN_SHAPE_CONTRAST)
  }
})

test_that("app_theme builds a Bootstrap 5 theme", {
  theme <- app_theme()
  expect_true(bslib::is_bs_theme(theme))
  expect_equal(bslib::theme_version(theme), "5")
})
