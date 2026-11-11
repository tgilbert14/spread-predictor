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
  # its own noise, which is what makes the models disagree a little. The
  # first conference plays the part of a power conference, and its Elo
  # understates it by the tier edge, as CFBD Elo does with real ones.
  strength <- sort(stats::rnorm(n, mean = 0, sd = 10), decreasing = TRUE)[sample(n)]
  k <- 25
  elo_tier <- 10

  teams <- DEMO_TEAMS
  teams$team_id <- 9000L + seq_len(n)
  teams$logo <- NA_character_
  teams$tier <- as.integer(teams$conference == "Desert Athletic")
  strength <- strength + 4 * teams$tier
  teams$sp  <- round(strength + stats::rnorm(n, 0, 2.5), 1)
  teams$fpi <- round(strength + stats::rnorm(n, 0, 2.5), 1)
  teams$srs <- round(strength + stats::rnorm(n, 0, 4.0), 1)
  teams$elo <- round(1500 + k * (strength - elo_tier * teams$tier + stats::rnorm(n, 0, 2.5)))
  teams$power <- round(strength + stats::rnorm(n, 0, 3.0), 1)
  for (model in names(MODEL_LABELS)) {
    teams[[paste0(model, "_rank")]] <- rank(-teams[[model]], ties.method = "min")
  }
  # Preseason z-scores: stronger teams tend to have more talent.
  teams$talent_z <- round(as.numeric(scale(strength + stats::rnorm(n, 0, 6))), 2)
  teams$returning_z <- round(stats::rnorm(n), 2)

  forecasts <- c("elo", "power", "house", "line")
  forecast_table <- function(n, mae, win_rate, brier) {
    data.frame(model = forecasts, label = unname(FORECAST_LABELS[forecasts]), n = n,
               mae = mae, win_rate = win_rate, brier = brier, stringsAsFactors = FALSE)
  }

  params <- list(
    fit_date = "2026-11-09",
    fit_seasons = c(2018L, 2019L, 2021:2025),
    holdout_season = 2026L,
    k = k,
    elo_tier = elo_tier,
    power_scale = 1,
    h = 2.8,
    h_elo = 2.9,
    h_power = 2.7,
    talent_points = 2.5,
    returning_points = 1.5,
    talent_points_elo = 2.4,
    talent_points_power = 2.6,
    returning_points_elo = 1.4,
    returning_points_power = 1.6,
    sigma = 15.8,
    # Point for point in the demo, so its numbers are easy to check by hand.
    public_scale = data.frame(model = PUBLIC_SYSTEMS, scale = 1, n = 1800L),
    power = POWER_RATING,
    weights = equal_weights(),
    weights_method = "equal",
    weights_note = "Equal weights: these are made-up demo numbers.",
    metrics = forecast_table(5500L, c(12.6, 12.6, 12.5, 12.0), c(0.71, 0.71, 0.72, 0.73),
                             c(0.188, 0.185, 0.185, 0.179)),
    holdout = forecast_table(560L, c(12.4, 12.5, 12.3, 11.5), c(0.73, 0.71, 0.72, 0.76),
                             c(0.183, 0.185, 0.181, 0.171)),
    calibration = data.frame(
      bin_low   = seq(0.5, 0.9, by = 0.1),
      bin_high  = seq(0.6, 1.0, by = 0.1),
      n         = c(860L, 780L, 640L, 520L, 370L),
      predicted = c(0.55, 0.65, 0.75, 0.85, 0.94),
      actual    = c(0.56, 0.66, 0.76, 0.86, 0.95)
    ),
    folds = data.frame(
      season = c(2018L, 2019L, 2021:2025),
      k = c(26.0, 26.8, 26.3, 27.1, 26.4, 27.3, 26.9),
      elo_tier = c(10.1, 10.6, 10.4, 10.8, 10.2, 10.7, 10.5),
      power_scale = c(1.01, 0.98, 1.00, 0.99, 1.00, 0.99, 1.00),
      h = c(3.1, 3.0, 3.0, 2.9, 2.7, 2.6, 2.8),
      sigma = c(15.6, 15.8, 15.7, 15.7, 15.8, 15.9, 15.7),
      mae = c(12.5, 12.7, 12.4, 12.6, 12.6, 12.2, 12.5)
    ),
    leaked_diagnostic = data.frame(
      model = c("sp", "fpi", "srs"),
      n = rep(5500L, 3),
      mae = c(10.8, 10.6, 10.5)
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
    predict_matchup(slate$home_id[i], slate$away_id[i], site, teams, params, week = 11L)$spread
  }, numeric(1))
  # Home-relative, CFBD convention: negative means the home team is favored.
  slate$market_spread_home <- -round_half(model_home_margin + stats::rnorm(nrow(slate), 0, 3))
  slate$market_spread_home[nrow(slate)] <- NA

  # Since our predictions were saved, two lines moved enough to flag and one
  # moved a little. market_move is positive when the market moved toward home.
  slate$market_at_freeze <- slate$market_spread_home
  slate$market_at_freeze[2] <- slate$market_spread_home[2] - 3
  slate$market_at_freeze[3] <- slate$market_spread_home[3] + 0.5
  slate$market_at_freeze[5] <- slate$market_spread_home[5] + 4
  slate$market_move <- slate$market_at_freeze - slate$market_spread_home

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
    coverage = coverage[, c("source", "season", "week", "n_teams", "pulled_at")],
    scorecard = demo_scorecard(teams, params, slate)
  )
}

#' A made-up scorecard: three graded weeks (8 to 10) and this week's saved,
#' unplayed predictions. Graded with the same code as the real one.
#'
#' The made-up market sees a little more than we do (its expected margin sits
#' closer to the truth), so it misses by a bit less, as the real one does.
demo_scorecard <- function(teams, params, slate) {
  saved_at <- function(week) format_utc(as.POSIXct("2026-11-10 13:05:00", tz = "UTC") - (11 - week) * 7 * 86400)
  weeks <- lapply(8:10, function(week) {
    ids <- sample(teams$team_id)
    games <- data.frame(
      game_id = 980000L + week * 100L + seq_len(length(ids) / 2),
      start_date = format_utc(as.POSIXct(saved_at(week), tz = "UTC") + 4 * 86400 +
                                sample(0:8, length(ids) / 2, replace = TRUE) * 3600),
      home_id = ids[c(TRUE, FALSE)], away_id = ids[c(FALSE, TRUE)], neutral_site = FALSE,
      market_spread_home = NA_real_
    )
    saved <- prediction_rows(games, teams, params, 2026L, week, frozen_at = saved_at(week))
    truth <- saved$blend + stats::rnorm(nrow(saved), 0, 5)
    saved$market_spread_home <- -round_half(truth + stats::rnorm(nrow(saved), 0, 2))
    margin <- round(truth + stats::rnorm(nrow(saved), 0, 13))
    margin[margin == 0] <- 1  # no ties in college football
    base <- sample(10:24, nrow(saved), replace = TRUE)
    list(saved = saved, results = data.frame(
      game_id = saved$game_id, completed = 1L,
      home_points = base + pmax(margin, 0), away_points = base + pmax(-margin, 0)
    ))
  })

  this_week <- slate
  this_week$market_spread_home <- slate$market_at_freeze
  saved <- rbind(do.call(rbind, lapply(weeks, `[[`, "saved")),
                 prediction_rows(this_week, teams, params, 2026L, 11L, frozen_at = saved_at(11)))
  build_scorecard(saved, do.call(rbind, lapply(weeks, `[[`, "results")), 2026L)
}

#' Made-up game notes for the demo slate, in the shape load_notes() returns.
#' The links point at example.com, a domain reserved for examples.
demo_notes <- function(app_data) {
  slate <- app_data$slate
  school <- function(team_id) app_data$teams$school[match(team_id, app_data$teams$team_id)]
  data.frame(
    season = 2026L, week = 11L,
    game_id = slate$game_id[c(2, 5, 5)],
    team = c(school(slate$home_id[2]), NA, NA),
    category = c("availability", "weather", "other"),
    note = c("Starting quarterback listed as out with an ankle injury.",
             "Wind gusts near 30 mph are forecast for kickoff.",
             "Kickoff moved three hours earlier because of the forecast."),
    source = c("Team injury report (demo)", "Weather service (demo)", "Conference office (demo)"),
    source_url = c("https://example.com/injury-report", "https://example.com/forecast", NA),
    checked_at = c("2026-11-12", "2026-11-13", "2026-11-13"),
    stringsAsFactors = FALSE
  )
}
