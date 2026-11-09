# Made-up data so the app runs before you have an API key.
#
# The teams are fictional on purpose. Real team names next to invented
# ratings would look like real predictions, and they would not be.

DEMO_TEAMS <- data.frame(
  school = c(
    "Saguaro State", "Sonoran Tech", "Catalina", "Rincon", "Mogollon",
    "Painted Desert", "Gila Valley", "Cochise A&M",
    "Ironwood", "Mesquite", "Ocotillo State", "Palo Verde", "Agave Tech",
    "Kofa", "Chiricahua", "Tumacacori",
    "Monsoon State", "Arroyo", "Caliche", "Bajada", "Playa Tech",
    "Hohokam", "Sky Island", "Tortolita"
  ),
  mascot = c(
    "Javelinas", "Roadrunners", "Bighorns", "Coatis", "Elk",
    "Collared Lizards", "Monsters", "Scorpions",
    "Owls", "Thrashers", "Hummingbirds", "Beetles", "Longhorned Bats",
    "Pronghorns", "Trogons", "Kingbirds",
    "Thunder", "Toads", "Tortoises", "Ringtails", "Avocets",
    "Canal Builders", "Black Bears", "Quail"
  ),
  abbreviation = c(
    "SAG", "SNT", "CAT", "RIN", "MOG", "PDS", "GIL", "COC",
    "IRN", "MSQ", "OCO", "PLV", "AGV", "KOF", "CHI", "TUM",
    "MON", "ARY", "CAL", "BAJ", "PLY", "HOH", "SKY", "TOR"
  ),
  conference = rep(c("Desert Athletic", "Borderlands", "Basin and Range"), each = 8),
  color = c(
    "#2E7D32", "#B3541E", "#1E3A8A", "#7C2D12", "#14532D", "#C2410C", "#111827", "#92400E",
    "#4C1D95", "#065F46", "#BE123C", "#3F6212", "#0E7490", "#A16207", "#9D174D", "#1D4ED8",
    "#334155", "#166534", "#78716C", "#B45309", "#0369A1", "#7F1D1D", "#0F172A", "#A21CAF"
  ),
  alt_color = c(
    "#FBBF24", "#FDE68A", "#F59E0B", "#FCD34D", "#E5E7EB", "#1F2937", "#84CC16", "#FEF3C7",
    "#FACC15", "#D1FAE5", "#FFE4E6", "#FDE047", "#CFFAFE", "#1C1917", "#FBCFE8", "#F97316",
    "#FDE047", "#BBF7D0", "#292524", "#FFFBEB", "#FDBA74", "#FECACA", "#38BDF8", "#FAE8FF"
  ),
  stringsAsFactors = FALSE
)

#' Build a complete, made-up app_data object.
#'
#' Same shape as the real thing written by build_app_data(), so the app does
#' not need to know the difference. See docs/data-dictionary.md.
#'
#' @param seed Fixed so the demo looks the same on every machine.
demo_app_data <- function(seed = 2026) {
  set.seed(seed)
  n <- nrow(DEMO_TEAMS)

  # One hidden "true strength" per team, in points. Each system sees it with
  # its own noise, which is what makes the models disagree a little.
  strength <- sort(stats::rnorm(n, mean = 0, sd = 10), decreasing = TRUE)[sample(n)]
  k <- 25

  teams <- DEMO_TEAMS
  teams$team_id <- 9000L + seq_len(n)
  teams$logo <- NA_character_
  teams$sp  <- round(strength + stats::rnorm(n, 0, 2.5), 1)
  teams$fpi <- round(strength + stats::rnorm(n, 0, 2.5), 1)
  teams$srs <- round(strength + stats::rnorm(n, 0, 4.0), 1)
  teams$elo <- round(1500 + k * (strength + stats::rnorm(n, 0, 2.5)))
  for (model in c("sp", "fpi", "srs", "elo")) {
    teams[[paste0(model, "_rank")]] <- rank(-teams[[model]], ties.method = "min")
  }

  params <- list(
    fit_date = "2026-11-09",
    training_seasons = 2021:2025,
    k = k,
    h = 2.5,
    sigma = 16,
    weights = list(sp = 0.25, fpi = 0.25, srs = 0.25, elo = 0.25),
    weights_method = "equal",
    metrics = data.frame(
      model = c("elo", "line"),
      label = c("Elo (what we fit on)", "Closing line"),
      n = c(3600L, 3600L),
      mae = c(13.4, 12.2),
      win_rate = c(0.72, 0.75),
      brier = c(0.186, 0.172),
      stringsAsFactors = FALSE
    ),
    calibration = data.frame(
      bin_low   = seq(0.5, 0.9, by = 0.1),
      bin_high  = seq(0.6, 1.0, by = 0.1),
      n         = c(900L, 820L, 740L, 640L, 500L),
      predicted = c(0.55, 0.65, 0.75, 0.85, 0.94),
      actual    = c(0.54, 0.66, 0.74, 0.86, 0.95)
    ),
    folds = data.frame(
      season = 2021:2025,
      k = c(25.4, 24.7, 25.1, 24.9, 25.3),
      h = c(2.6, 2.3, 2.5, 2.4, 2.7),
      sigma = c(16.2, 15.8, 16.1, 15.9, 16.0),
      mae = c(13.5, 13.2, 13.4, 13.3, 13.6)
    ),
    leaked_diagnostic = data.frame(
      model = c("sp", "fpi", "srs"),
      n = rep(3600L, 3),
      mae = c(11.9, 12.0, 11.6)
    )
  )

  # This week's slate: pair teams off, and give most games a market line that
  # sits near our number so the "difference from market" column has variety.
  order_ids <- sample(teams$team_id)
  home_id <- order_ids[seq(1, n, by = 2)]
  away_id <- order_ids[seq(2, n, by = 2)]
  slate <- data.frame(
    game_id = 990000L + seq_along(home_id),
    start_date = format(as.POSIXct("2026-11-14 19:00:00", tz = "UTC") +
                          sample(0:8, length(home_id), replace = TRUE) * 3600,
                        "%Y-%m-%dT%H:%M:%SZ"),
    home_id = home_id,
    away_id = away_id,
    neutral_site = c(TRUE, rep(FALSE, length(home_id) - 1)),
    stringsAsFactors = FALSE
  )
  model_home_margin <- vapply(seq_len(nrow(slate)), function(i) {
    site <- if (slate$neutral_site[i]) "neutral" else "a_home"
    predict_matchup(slate$home_id[i], slate$away_id[i], site, teams, params)$spread
  }, numeric(1))
  # Home-relative, CFBD convention: negative means the home team is favored.
  slate$market_spread_home <- -round_half(model_home_margin + stats::rnorm(nrow(slate), 0, 3))
  slate$market_spread_home[nrow(slate)] <- NA

  coverage <- expand.grid(source = c("sp", "fpi", "srs", "elo"), week = 11L,
                          stringsAsFactors = FALSE)
  coverage$season <- 2026L
  coverage$n_teams <- n
  coverage$pulled_at <- "2026-11-10T13:00:00Z"

  list(
    meta = list(
      season = 2026L,
      week = 11L,
      ratings_date = "2026-11-10",
      built_at = "2026-11-10T13:05:00Z",
      is_demo = TRUE
    ),
    teams = teams,
    params = params,
    slate = slate,
    coverage = coverage[, c("source", "season", "week", "n_teams", "pulled_at")]
  )
}
