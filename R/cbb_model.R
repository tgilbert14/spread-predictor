# Basketball model: turn T-Rank and Elo into a spread, a win chance and a
# ranking.
#
# Two systems, blended with fitted weights.
#   T-Rank rates teams in points per 100 possessions (offense minus defense)
#     and gives each team's pace. A game's margin is the efficiency gap
#     times the possessions the two teams would play, so pace matters: the
#     same gap is worth more points in a fast game.
#   Elo comes with each game from the API. Its gap is divided by a fitted
#     points scale.
# Home court is fit, in points. Everything is fit on one finished season by
# scripts/cbb_fit.R and saved in data/basketball/params.json.
#
# Sign convention, the same as football: margin is Team A minus Team B.

CBB_MODEL_LABELS <- c(trank = "T-Rank", elo = "Elo")

# ---- Names ---------------------------------------------------------------------

#' A school name boiled down for matching across the two sources:
#' "St. John's" and "Saint Johns" both become "stjohns".
cbb_key <- function(name) {
  # Accents are folded by hand so the answer does not depend on the locale.
  key <- iconv(as.character(name), from = "UTF-8", to = "ASCII", sub = "byte")
  key <- gsub("<c3><a9>", "e", key, fixed = TRUE)
  # A file written where R could not print the accent holds "<U+00E9>" instead.
  key <- gsub("<U+00E9>", "e", key, fixed = TRUE)
  key <- tolower(gsub("<[0-9a-f]{2}>", "", key))
  key <- gsub("&", "and", key, fixed = TRUE)
  key <- gsub("\\bstate\\b", "st", key)
  key <- gsub("\\bsaint\\b", "st", key)
  gsub("[^a-z0-9]", "", key)
}

#' Where each school sits in a T-Rank file.
#'
#' Names are matched by cbb_key(), after swapping in the T-Rank spelling for
#' the schools listed in data/basketball/team_names.csv.
#'
#' @param aliases Rows of school (as the API spells it) and trank (as T-Rank
#'   does), or NULL.
#' @return A row number in `trank_names` per school, NA when there is none.
cbb_match_trank <- function(schools, trank_names, aliases = NULL) {
  keys <- cbb_key(trank_names)
  plain <- match(cbb_key(schools), keys)
  if (is.null(aliases) || nrow(aliases) == 0) return(plain)
  # The lookup's spelling first. If T-Rank has since changed a name to match
  # the API's, the school's own name still finds it.
  listed <- match(cbb_key(aliases$trank[match(schools, aliases$school)]), keys)
  ifelse(is.na(listed), plain, listed)
}

#' The name lookup, or NULL when the file is not there.
cbb_aliases <- function(path = CBB_PATHS$names) {
  if (file.exists(path)) read_snapshot(path) else NULL
}

# ---- Margins --------------------------------------------------------------------

#' T-Rank's expected margin for A over B on a neutral floor, before scaling.
#'
#' Efficiency gap (points per 100 possessions) times the possessions the two
#' would play: the product of their paces over the average pace.
cbb_trank_gap <- function(em_a, tempo_a, em_b, tempo_b, average_tempo) {
  (em_a - em_b) * (tempo_a * tempo_b / average_tempo) / 100
}

#' Each system's margin for A over B, with home court.
#'
#' @param site_sign 1 when A is at home, -1 when B is, 0 on a neutral floor.
#' @return c(trank = , elo = ), NA for a system missing either team.
cbb_margins <- function(a, b, site_sign, params) {
  c(
    trank = params$trank_scale * cbb_trank_gap(a$em, a$tempo, b$em, b$tempo, params$average_tempo) +
      params$home * site_sign,
    elo = (a$elo - b$elo) / params$elo_k + params$home * site_sign
  )
}

#' Predict a basketball matchup. The result has the same shape as football's
#' predict_matchup(), so the same headline, band and dot plot can show it.
#'
#' @param teams The basketball teams table (cbb_team_table()).
#' @param params data/basketball/params.json.
cbb_predict <- function(team_a, team_b, site = "neutral", teams, params) {
  site <- match.arg(site, SITE_CHOICES)
  a <- find_team(team_a, teams)
  b <- find_team(team_b, teams)
  if (a$team_id == b$team_id) stop("Pick two different teams.", call. = FALSE)
  site_sign <- c(neutral = 0, a_home = 1, b_home = -1)[[site]]

  ids <- names(CBB_MODEL_LABELS)
  rating <- function(team, id) if (id == "trank") team$em else team$elo
  models <- data.frame(
    model = ids, label = unname(CBB_MODEL_LABELS),
    rating_a = vapply(ids, function(id) as.numeric(rating(a, id)), numeric(1)),
    rank_a = vapply(ids, function(id) as.numeric(a[[paste0(id, "_rank")]]), numeric(1)),
    rating_b = vapply(ids, function(id) as.numeric(rating(b, id)), numeric(1)),
    rank_b = vapply(ids, function(id) as.numeric(b[[paste0(id, "_rank")]]), numeric(1)),
    weight = vapply(ids, function(id) as.numeric(params$weights[[id]]), numeric(1)),
    margin = unname(cbb_margins(a, b, site_sign, params)[ids]),
    stringsAsFactors = FALSE, row.names = NULL
  )
  usable <- !is.na(models$margin) & models$weight > 0
  if (!any(usable)) stop("Neither rating system has both teams, so there is nothing to blend.", call. = FALSE)
  models$weight[!usable] <- 0
  models$weight <- models$weight / sum(models$weight)
  spread <- sum(models$weight[usable] * models$margin[usable])
  z <- stats::qnorm(1 - (1 - INTERVAL_COVERAGE) / 2)

  flags <- character()
  if (any(is.na(models$margin))) flags <- missing_models_flag(models$label[is.na(models$margin)])
  list(team_a = a, team_b = b, site = site, spread = spread,
       win_prob_a = stats::pnorm(spread / params$sigma),
       interval = c(low = spread - z * params$sigma, high = spread + z * params$sigma),
       models = models, flags = flags)
}

# ---- Teams and rankings -----------------------------------------------------------

#' The teams table the app predicts from: every team with its T-Rank
#' efficiency margin and pace, its Elo, and a rank in each.
#'
#' @param ratings One T-Rank file (cbb_ratings_before()).
#' @param elo Named by team id: each team's current Elo.
cbb_team_table <- function(teams, ratings, elo, aliases = NULL) {
  at <- cbb_match_trank(teams$school, ratings$team, aliases)
  teams$em <- ratings$adj_o[at] - ratings$adj_d[at]
  teams$tempo <- ratings$tempo[at]
  teams$elo <- unname(elo[as.character(teams$team_id)])
  ranked <- function(x) as.integer(rank(-x, ties.method = "min", na.last = "keep"))
  teams$trank_rank <- ranked(teams$em)
  teams$elo_rank <- ranked(teams$elo)
  teams
}

#' Each team's latest Elo: what it takes into its next game, or what it left
#' its last one with.
#'
#' @return Elo named by team id.
cbb_current_elo <- function(games) {
  games <- games[order(games$start_date), , drop = FALSE]
  played <- !is.na(games$home_elo_end) & !is.na(games$away_elo_end)
  after <- c(stats::setNames(games$home_elo_end[played], games$home_id[played]),
             stats::setNames(games$away_elo_end[played], games$away_id[played]))
  # The last entry per team wins: rev() puts the newest first for duplicated().
  after <- rev(after)
  after[!duplicated(names(after))]
}

#' Every team's rating in points against an average team on a neutral
#' floor, per system, and the blend.
#'
#' The T-Rank part uses each team's own pace against an average-paced
#' opponent, so unlike football the gap between two teams here is close to
#' our neutral line for them but not exactly it.
cbb_team_points <- function(teams, params) {
  center <- function(x) x - mean(x, na.rm = TRUE)
  trank <- params$trank_scale * center(teams$em) * teams$tempo / 100
  elo <- center(teams$elo) / params$elo_k
  values <- cbind(trank = trank, elo = elo)
  weights <- c(params$weights$trank, params$weights$elo)
  used <- sweep(!is.na(values), 2, weights, `*`)
  blend <- rowSums(ifelse(is.na(values), 0, values) * used) / rowSums(used)
  data.frame(team_id = teams$team_id, trank = trank, elo = elo,
             blend = ifelse(is.finite(blend), blend, NA_real_))
}

# ---- Fitting ----------------------------------------------------------------------

#' The rows a fit or a backtest needs: finished games between two rated
#' teams, with each system's unscaled gap going into the game.
#'
#' @param games One season's games file.
#' @param ratings_root data/basketball/ratings.
cbb_fit_rows <- function(games, season, ratings_root = CBB_PATHS$ratings, aliases = NULL) {
  games <- games[games$status == "final" & !is.na(games$home_points) & !is.na(games$away_points), , drop = FALSE]
  games$day <- cbb_game_day(games$start_date)
  rows <- lapply(split(games, games$day), function(day_games) {
    ratings <- cbb_ratings_before(season, day_games$day[1], ratings_root)
    if (is.null(ratings)) return(NULL)
    home <- cbb_match_trank(day_games$home_team, ratings$team, aliases)
    away <- cbb_match_trank(day_games$away_team, ratings$team, aliases)
    em <- ratings$adj_o - ratings$adj_d
    data.frame(
      game_id = day_games$game_id, day = day_games$day,
      margin = day_games$home_points - day_games$away_points,
      home = 1 - day_games$neutral_site,
      trank_gap = cbb_trank_gap(em[home], ratings$tempo[home], em[away], ratings$tempo[away], mean(ratings$tempo)),
      elo_gap = day_games$home_elo - day_games$away_elo,
      market = -day_games$spread,
      average_tempo = mean(ratings$tempo)
    )
  })
  rows <- do.call(rbind, rows)
  rows[!is.na(rows$trank_gap) & !is.na(rows$elo_gap), , drop = FALSE]
}

#' Fit the basketball parameters on one season's rows.
#'
#' Each system's scale is fit on its own, so each one's line is the best it
#' can do alone. Then one weight says how much of the T-Rank line to use,
#' with the rest going to Elo, and home court is fit alongside it.
#'
#' @return The params list written to data/basketball/params.json.
cbb_fit <- function(rows, season) {
  trank_scale <- stats::coef(stats::lm(margin ~ 0 + trank_gap + home, data = rows))[["trank_gap"]]
  elo_slope <- stats::coef(stats::lm(margin ~ 0 + elo_gap + home, data = rows))[["elo_gap"]]
  rows$trank_points <- trank_scale * rows$trank_gap
  rows$elo_points <- elo_slope * rows$elo_gap
  # margin = w * trank + (1 - w) * elo + home, rearranged so w is one slope.
  share <- stats::coef(stats::lm(I(margin - elo_points) ~ 0 + I(trank_points - elo_points) + home, data = rows))
  weight <- min(max(share[[1]], 0), 1)
  home <- share[["home"]]
  blend <- weight * rows$trank_points + (1 - weight) * rows$elo_points + home * rows$home
  lined <- !is.na(rows$market)
  list(
    fit_date = format(Sys.Date()), fit_season = as.integer(season), n_games = nrow(rows),
    trank_scale = trank_scale, elo_k = 1 / elo_slope, home = home,
    average_tempo = mean(rows$average_tempo),
    sigma = stats::sd(rows$margin - blend),
    weights = list(trank = weight, elo = 1 - weight),
    avg_miss = mean(abs(rows$margin - blend)),
    avg_miss_lined = mean(abs(rows$margin[lined] - blend[lined])),
    market_avg_miss = mean(abs(rows$margin[lined] - rows$market[lined])),
    n_lined = sum(lined)
  )
}
