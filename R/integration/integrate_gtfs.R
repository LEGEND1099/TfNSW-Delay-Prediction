# Ambiguous keys are reported and left unresolved; joins cannot multiply rows.
gtfs_key <- function(df, columns) {
  if (!nrow(df)) return(character())
  values <- lapply(df[columns], as.character)
  if (any(vapply(values, function(x) any(grepl("\r", x), na.rm = TRUE), logical(1)))) {
    stop("Invalid carriage return in GTFS identifier.")
  }
  key <- do.call(paste, c(values, sep = "\r"))
  key[!stats::complete.cases(df[columns])] <- NA_character_
  key
}
unique_lookup <- function(query, table, columns) {
  keys <- gtfs_key(table, columns)
  duplicates <- duplicated(keys) | duplicated(keys, fromLast = TRUE)
  query_keys <- gtfs_key(query, columns)
  index <- match(query_keys, keys)
  ambiguous <- !is.na(index) & duplicates[index]
  index[ambiguous | is.na(query_keys)] <- NA_integer_
  list(index = index, ambiguous = ambiguous, duplicate_rows = sum(duplicates & !is.na(keys)))
}
gtfs_service_time_utc <- function(date, time, timezone = "Australia/Sydney") {
  # GTFS origin is local noon minus 12 hours, including DST transition dates.
  valid <- !is.na(date) & grepl("^[0-9]{8}$", date) & !is.na(time) &
    grepl("^[0-9]{2,}:[0-5][0-9]:[0-5][0-9]$", time)
  seconds <- rep(NA_real_, length(time))
  parts <- strsplit(time[valid], ":", fixed = TRUE)
  seconds[valid] <- vapply(parts, function(x) sum(as.numeric(x) * c(3600, 60, 1)), numeric(1))
  noon <- as.POSIXct(paste(date, "12:00:00"), format = "%Y%m%d %H:%M:%S", tz = timezone)
  utc_epoch(as.numeric(noon) - 12 * 3600 + seconds)
}
integrate_gtfs <- function(realtime, static, snapshot_time_utc, feed_time_utc,
                           timezone = "Australia/Sydney") {
  x <- realtime
  names(x)[names(x) == "route_id"] <- "realtime_route_id"
  names(x)[names(x) == "direction_id"] <- "realtime_direction_id"
  st <- static$stop_times
  pair <- unique_lookup(x, st, c("trip_id", "stop_id"))
  sq <- data.frame(trip_id = x$trip_id, stop_sequence = x$realtime_stop_sequence)
  seq_match <- unique_lookup(sq, st, c("trip_id", "stop_sequence"))
  is_scheduled <- is.na(x$trip_schedule_relationship) | x$trip_schedule_relationship == 0
  use_seq <- is_scheduled & !is.na(x$realtime_stop_sequence)
  same_stop <- is.na(x$stop_id) | (!is.na(seq_match$index) & x$stop_id == st$stop_id[seq_match$index])
  si <- pair$index
  si[use_seq] <- seq_match$index[use_seq]
  si[use_seq & !same_stop] <- NA_integer_
  x$static_trip_stop_ambiguous <- ifelse(use_seq, seq_match$ambiguous, pair$ambiguous)
  x$static_trip_stop_match <- !is.na(si)
  x$static_stop_sequence <- st$stop_sequence[si]
  x$static_arrival_time <- st$arrival_time[si]
  x$static_departure_time <- st$departure_time[si]
  x$resolved_stop_id <- dplyr::coalesce(x$stop_id, st$stop_id[si])
  ti <- unique_lookup(x, static$trips, "trip_id")
  x$static_trip_match <- !is.na(ti$index)
  x$static_trip_ambiguous <- ti$ambiguous
  for (field in c("route_id", "service_id", "trip_headsign", "direction_id", "shape_id")) {
    value <- static$trips[[field]]
    if (is.null(value)) value <- rep(NA_character_, nrow(static$trips))
    name <- switch(field, route_id = "static_route_id", direction_id = "static_direction_id", field)
    x[[name]] <- value[ti$index]
  }
  # Keep both route identifiers. Original trip metadata classifies replacements.
  x$route_id <- dplyr::coalesce(x$static_route_id, x$realtime_route_id)
  ri <- unique_lookup(x, static$routes, "route_id")
  for (field in c("agency_id", "route_short_name", "route_long_name", "route_desc", "route_type")) {
    value <- static$routes[[field]]
    if (is.null(value)) value <- rep(NA_character_, nrow(static$routes))
    x[[field]] <- value[ri$index]
  }
  pi <- unique_lookup(data.frame(stop_id = x$resolved_stop_id), static$stops, "stop_id")
  x$static_stop_match <- !is.na(pi$index)
  for (field in c("stop_name", "stop_lat", "stop_lon", "location_type", "parent_station")) {
    value <- static$stops[[field]]
    if (is.null(value)) value <- rep(NA_character_, nrow(static$stops))
    x[[field]] <- value[pi$index]
  }
  x$snapshot_time_utc <- rep(snapshot_time_utc, nrow(x))
  x$feed_time_utc <- rep(feed_time_utc, nrow(x))
  x$is_replacement_trip <- x$trip_schedule_relationship %in% 5
  labels <- c("0" = "SCHEDULED", "1" = "ADDED", "2" = "UNSCHEDULED", "3" = "CANCELED",
              "5" = "REPLACEMENT", "6" = "DUPLICATED", "7" = "DELETED", "8" = "NEW")
  x$trip_schedule_relationship_label <- unname(labels[as.character(x$trip_schedule_relationship)])
  # Raw absent enum stays NA. Interpret the documented default separately.
  x$uses_static_scheduled_baseline <- is_scheduled
  x$effective_stop_order <- as.numeric(x$realtime_update_order)
  x$effective_stop_order[is_scheduled] <- dplyr::coalesce(x$static_stop_sequence[is_scheduled],
    x$realtime_stop_sequence[is_scheduled], as.numeric(x$realtime_update_order[is_scheduled]))
  x$effective_scheduled_arrival_utc <- x$realtime_arrival_scheduled_time_utc
  x$effective_scheduled_departure_utc <- x$realtime_departure_scheduled_time_utc
  x$effective_scheduled_arrival_utc[is_scheduled] <- gtfs_service_time_utc(
    x$start_date[is_scheduled], x$static_arrival_time[is_scheduled], timezone)
  x$effective_scheduled_departure_utc[is_scheduled] <- gtfs_service_time_utc(
    x$start_date[is_scheduled], x$static_departure_time[is_scheduled], timezone)
  x$effective_schedule_source <- ifelse(is_scheduled, "static_service_date", "realtime_scheduled_time")
  x$replacement_missing_scheduled_time <- x$is_replacement_trip & (
    is.na(x$realtime_arrival_scheduled_time_utc) | is.na(x$realtime_departure_scheduled_time_utc))
  x$effective_schedule_missing <- is.na(x$effective_scheduled_arrival_utc) | is.na(x$effective_scheduled_departure_utc)
  x$arrival_delay_minutes <- x$arrival_delay_seconds / 60
  x$departure_delay_minutes <- x$departure_delay_seconds / 60
  x$trip_update_age_seconds <- as.numeric(difftime(x$snapshot_time_utc, x$trip_update_time_utc, units = "secs"))
  stopifnot(nrow(x) == nrow(realtime), sum(x$is_replacement_trip) == sum(realtime$trip_schedule_relationship %in% 5),
    all(x$effective_stop_order[x$is_replacement_trip] == x$realtime_update_order[x$is_replacement_trip]))
  attr(x, "duplicate_diagnostics") <- c(trip_rows = ti$duplicate_rows, stop_rows = pi$duplicate_rows,
    route_rows = ri$duplicate_rows, trip_stop_rows = pair$duplicate_rows, trip_sequence_rows = seq_match$duplicate_rows)
  x
}
