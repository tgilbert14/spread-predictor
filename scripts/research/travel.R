# Does travel hurt the visiting team more than home field already covers?
#
# Distance is stadium to stadium for true home games. Neutral-site games
# count as no travel edge, since neither stadium is the venue. Coordinates
# come from data/snapshots/extras/locations/ (the `extras` task of the
# Weekly snapshot workflow pulls them).
#
# Result (Nov 2026): every sign points the expected way and nothing passes.
# See docs/research-log.md.

source(file.path("scripts", "research", "common.R"))
games <- load_research_data()$games

locations <- do.call(rbind, lapply(sort(unique(games$season)), function(season) {
  rows <- utils::read.csv(extra_path("locations", season), stringsAsFactors = FALSE)
  data.frame(season = season, team_id = rows$team_id, lat = rows$latitude, lon = rows$longitude,
             timezone = rows$timezone, elevation_m = suppressWarnings(as.numeric(rows$elevation)))
}))
at_team <- function(column, team_id) {
  locations[[column]][match(paste(games$season, team_id), paste(locations$season, locations$team_id))]
}

#' Great-circle distance in miles.
miles_between <- function(lat1, lon1, lat2, lon2) {
  rad <- pi / 180
  a <- sin((lat2 - lat1) * rad / 2)^2 +
    cos(lat1 * rad) * cos(lat2 * rad) * sin((lon2 - lon1) * rad / 2)^2
  3958.8 * 2 * asin(sqrt(a))
}

#' Hours from UTC in mid-October, for each time zone name.
utc_offset <- function(timezone) {
  noon <- as.POSIXct("2024-10-15 12:00", tz = "UTC")
  vapply(timezone, function(tz) {
    if (is.na(tz) || tz == "") NA_real_ else as.numeric(format(noon, "%z", tz = tz)) / 100
  }, numeric(1))
}

miles <- miles_between(at_team("lat", games$home_id), at_team("lon", games$home_id),
                       at_team("lat", games$away_id), at_team("lon", games$away_id))
# Positive when the home team's clock is ahead, so the visitor came east.
hours_east <- utc_offset(at_team("timezone", games$home_id)) - utc_offset(at_team("timezone", games$away_id))
true_home <- games$home == 1 & !is.na(miles)
# A factor only applies to true home games; everywhere else it is 0.
at_home <- function(x) ifelse(true_home & !is.na(x), x, 0)

# Centered, so the home-field term keeps meaning "an average trip".
games$log_miles <- at_home(log1p(miles) - mean(log1p(miles[true_home])))
games$far <- at_home(as.integer(miles > 1000))
games$very_far <- at_home(as.integer(miles > 1500))
games$close_by <- at_home(as.integer(miles < 150))
games$zones <- at_home(abs(hours_east))
games$east_trip <- at_home(as.integer(hours_east >= 2))
games$west_trip <- at_home(as.integer(hours_east <= -2))
games$altitude <- at_home(as.integer(at_team("elevation_m", games$home_id) > 1200 &
                                       at_team("elevation_m", games$away_id) < 600))

cat(sprintf("%d games, %d true home games with both stadiums located.\n", nrow(games), sum(true_home)))
print_verdicts(games, c(
  log_miles = "Travel distance (log miles)",
  far = "Visitor travels more than 1,000 miles",
  very_far = "Visitor travels more than 1,500 miles",
  close_by = "Visitor travels under 150 miles",
  zones = "Time zones crossed",
  east_trip = "Visitor travels east 2 or more time zones",
  west_trip = "Visitor travels west 2 or more time zones",
  altitude = "Low-elevation visitor at a high-elevation home"
))
