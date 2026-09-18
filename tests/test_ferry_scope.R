# Sydney Ferries unmatched ADDED/REPLACEMENT observations remain in both outputs.
# Synthetic Protobuf only: no API request or dependency on saved feed snapshots.
source("config/tfnsw_feeds.R")
source("R/parsing/read_trip_updates.R")
source("R/integration/integrate_gtfs.R")
source("R/processing/process_gtfs.R")
source("R/utils/validate_gtfs.R")
load_gtfs_schema()

pb_message <- function(type, ...) {
  result <- RProtoBuf::new(RProtoBuf::P(paste0("transit_realtime.", type)))
  fields <- list(...)
  for (field in names(fields)) result[[field]] <- fields[[field]]
  result
}
event <- function(...) pb_message("TripUpdate.StopTimeEvent", ...)
stop_update <- function(...) pb_message("TripUpdate.StopTimeUpdate", ...)
entity <- function(id, relationship, updates) {
  descriptor <- pb_message("TripDescriptor", trip_id = id, route_id = "ferry_f1",
    start_date = "20260918", schedule_relationship = relationship)
  update <- pb_message("TripUpdate", trip = descriptor, stop_time_update = updates)
  pb_message("FeedEntity", id = id, trip_update = update)
}
scheduled_arrival <- 1789690000
scheduled_departure <- scheduled_arrival + 30
feed <- pb_message("FeedMessage",
  header = pb_message("FeedHeader", gtfs_realtime_version = "2.0", timestamp = 1789680000),
  entity = list(
    entity("scheduled", 0, list(stop_update(stop_id = "A", stop_sequence = 1,
      arrival = event(delay = 0)))),
    entity("added", 1, list(stop_update(stop_id = "B", stop_sequence = 1,
      arrival = event(time = 1789690100)))),
    entity("replacement", 5, list(
      # Original sequence 1 belongs to A. The extra stop cannot inherit that match.
      stop_update(stop_id = "EXTRA", stop_sequence = 1),
      stop_update(stop_id = "A", stop_sequence = 2),
      stop_update(stop_id = "B", stop_sequence = 3,
        arrival = event(time = scheduled_arrival + 40, scheduled_time = scheduled_arrival),
        departure = event(time = scheduled_departure + 40, scheduled_time = scheduled_departure))
    ))
  ))
parsed <- flatten_gtfs_feed(feed)
parsed$snapshot_time_utc <- utc_epoch(1789680200)
parsed$feed_time_utc <- utc_epoch(1789680000)
static <- list(
  routes = tibble::tibble(route_id = "ferry_f1", route_short_name = "F1", route_type = 4L),
  trips = tibble::tibble(trip_id = c("scheduled", "replacement"),
    route_id = "ferry_f1", service_id = "service"),
  stops = tibble::tibble(stop_id = c("A", "B"), stop_name = c("Wharf A", "Wharf B")),
  stop_times = tibble::tibble(trip_id = c("scheduled", "replacement"),
    stop_id = "A", stop_sequence = 1L, arrival_time = "10:00:00", departure_time = "10:01:00"),
  parsing_problem_count = 0L
)
config <- tfnsw_feeds$ferry
stopifnot(config$mode == "ferry", config$subfeed == "sydneyferries", config$scope == "feed",
  grepl("/ferries/sydneyferries$", config$static_endpoint),
  grepl("/ferries/sydneyferries$", config$realtime_endpoint))
rt <- parsed$trip_updates_df
integrated <- integrate_gtfs(rt, static, parsed$snapshot_time_utc, parsed$feed_time_utc)
scoped <- scope_gtfs(integrated, config)
stopifnot(nrow(rt) == 5L, nrow(integrated) == nrow(rt),
  nrow(scoped$audit) == nrow(rt), nrow(scoped$processed) == nrow(rt))

# Check identities and linkage in both tables, including the genuinely unknown stop.
for (output in list(scoped$audit, scoped$processed)) {
  stopifnot(identical(output$entity_id, rt$entity_id),
    identical(output$stop_id, rt$stop_id), all(output$keep_for_project),
    all(output$source_subfeed == "sydneyferries"),
    identical(output$static_trip_stop_match, c(TRUE, FALSE, FALSE, TRUE, FALSE)))
  added <- output[output$entity_id == "added", ]
  stopifnot(!added$static_trip_match, added$static_stop_match,
    !added$static_trip_stop_match, added$trip_schedule_relationship_label == "ADDED",
    added$route_id == "ferry_f1", !added$uses_static_scheduled_baseline,
    is.na(added$static_arrival_time), is.na(added$effective_scheduled_arrival_utc))
  replacement <- output[output$entity_id == "replacement", ]
  stopifnot(all(replacement$static_trip_match),
    identical(replacement$static_stop_match, c(FALSE, TRUE, TRUE)),
    identical(replacement$effective_stop_order, c(1, 2, 3)),
    identical(replacement$static_stop_sequence, c(NA_integer_, 1L, NA_integer_)),
    all(replacement$trip_schedule_relationship_label == "REPLACEMENT"),
    !any(replacement$uses_static_scheduled_baseline),
    all(replacement$effective_schedule_source == "realtime_scheduled_time"),
    !is.na(replacement$static_arrival_time[2]),
    identical(as.numeric(replacement$effective_scheduled_arrival_utc),
      c(NA_real_, NA_real_, scheduled_arrival)),
    identical(as.numeric(replacement$effective_scheduled_departure_utc),
      c(NA_real_, NA_real_, scheduled_departure)),
    identical(replacement$replacement_missing_scheduled_time, c(TRUE, TRUE, FALSE)))
}
report <- validate_gtfs(parsed, static, integrated, scoped$processed, config)
stopifnot(report$mode == "ferry", report$source_subfeed == "sydneyferries",
  report$rows_before_integration == 5L, report$rows_after_integration == 5L,
  report$processed_rows == 5L, report$unmatched_rows == 3L,
  report$static_trip_match_rate == 4 / 5, report$static_stop_match_rate == 4 / 5,
  report$static_trip_stop_match_rate == 2 / 5, report$replacement_rows == 3L,
  report$replacement_missing_schedule_rows == 2L,
  grepl("1:1", report$unmatched_trip_schedule_relationship_counts, fixed = TRUE),
  grepl("5:2", report$unmatched_trip_schedule_relationship_counts, fixed = TRUE))
cat("Sydney Ferries unmatched observation preservation tests passed.\n")
