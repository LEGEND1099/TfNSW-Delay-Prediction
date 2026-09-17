# Optional Protobuf scalar defaults are never observations.
utc_epoch <- function(x) {
  x <- as.numeric(x)
  x[!is.finite(x) | abs(x) > 2^53] <- NA_real_
  as.POSIXct(x, origin = "1970-01-01", tz = "UTC")
}
proto_value <- function(message, field, missing = NA_real_) {
  if (is.null(message) || !message$has(field)) return(missing)
  value <- message[[field]]
  if (is.character(missing)) as.character(value) else as.numeric(value)
}
load_gtfs_schema <- function() {
  descriptor <- tryCatch(RProtoBuf::P("transit_realtime.FeedMessage"), error = function(e) NULL)
  if (is.null(descriptor)) RProtoBuf::readProtoFiles("proto/gtfs-realtime.proto")
  RProtoBuf::P("transit_realtime.FeedMessage")
}
read_trip_updates <- function(path) {
  descriptor <- load_gtfs_schema()
  feed <- RProtoBuf::read(descriptor, readBin(path, "raw", n = file.info(path)$size))
  if (proto_value(feed$header, "incrementality") %in% 1) {
    stop("Differential GTFS-R feeds need state reconciliation; this runner supports FULL_DATASET only.")
  }
  stamp <- sub("^.*_(\\d{8}T\\d{6}Z)\\.pb$", "\\1", basename(path))
  snapshot_time <- as.POSIXct(stamp, format = "%Y%m%dT%H%M%SZ", tz = "UTC")
  if (is.na(snapshot_time)) stop("Snapshot filename has no valid UTC collection timestamp.")
  c(flatten_gtfs_feed(feed), list(feed = feed, snapshot_time_utc = snapshot_time,
    feed_time_utc = utc_epoch(proto_value(feed$header, "timestamp"))))
}
trip_summary_row <- function(entity, entity_order) {
  tu <- entity$trip_update
  trip <- tu$trip
  tibble::tibble(
    entity_id = proto_value(entity, "id", NA_character_),
    entity_order = as.integer(entity_order),
    trip_id = proto_value(trip, "trip_id", NA_character_),
    route_id = proto_value(trip, "route_id", NA_character_),
    direction_id = proto_value(trip, "direction_id"),
    start_date = proto_value(trip, "start_date", NA_character_),
    start_time = proto_value(trip, "start_time", NA_character_),
    trip_schedule_relationship = proto_value(trip, "schedule_relationship"),
    trip_update_time_utc = utc_epoch(proto_value(tu, "timestamp")),
    trip_level_delay_seconds = proto_value(tu, "delay"),
    number_of_stop_updates = as.integer(tu$size("stop_time_update")))
}
stop_update_row <- function(stu, i) {
  arrival <- if (!is.null(stu) && stu$has("arrival")) stu$arrival else NULL
  departure <- if (!is.null(stu) && stu$has("departure")) stu$departure else NULL
  tibble::tibble(
    realtime_update_order = as.integer(i),
    realtime_stop_sequence = proto_value(stu, "stop_sequence"),
    stop_id = proto_value(stu, "stop_id", NA_character_),
    stop_schedule_relationship = proto_value(stu, "schedule_relationship"),
    arrival_delay_seconds = proto_value(arrival, "delay"),
    departure_delay_seconds = proto_value(departure, "delay"),
    realtime_arrival_time_utc = utc_epoch(proto_value(arrival, "time")),
    realtime_departure_time_utc = utc_epoch(proto_value(departure, "time")),
    realtime_arrival_scheduled_time_utc = utc_epoch(proto_value(arrival, "scheduled_time")),
    realtime_departure_scheduled_time_utc = utc_epoch(proto_value(departure, "scheduled_time")),
    arrival_uncertainty_seconds = proto_value(arrival, "uncertainty"),
    departure_uncertainty_seconds = proto_value(departure, "uncertainty"))
}
flatten_gtfs_feed <- function(feed) {
  empty_entity <- RProtoBuf::new(RProtoBuf::P("transit_realtime.FeedEntity"))
  empty_summary <- trip_summary_row(empty_entity, 0L)[0, ]
  summaries <- list(empty_summary)
  updates <- list(dplyr::bind_cols(empty_summary, stop_update_row(NULL, 0L)[0, ]))
  # Materialize repeated Protobuf fields once, especially for large bus feeds.
  entities <- feed$entity
  for (i in seq_along(entities)) {
    entity <- entities[[i]]
    if (!entity$has("trip_update")) next
    summary <- trip_summary_row(entity, i)
    summaries[[length(summaries) + 1L]] <- summary
    n <- summary$number_of_stop_updates
    if (n == 0L) next
    stop_updates <- entity$trip_update$stop_time_update
    rows <- dplyr::bind_rows(lapply(seq_len(n), function(j) {
      stop_update_row(stop_updates[[j]], j)
    }))
    updates[[length(updates) + 1L]] <- dplyr::bind_cols(summary[rep(1L, n), ], rows)
    if (length(entities) >= 1000L && i %% 1000L == 0L) {
      message("Parsed ", i, "/", length(entities), " realtime entities.")
    }
  }
  list(trip_summary_df = dplyr::bind_rows(summaries), trip_updates_df = dplyr::bind_rows(updates))
}
