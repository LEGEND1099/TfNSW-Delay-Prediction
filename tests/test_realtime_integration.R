# Run from the repository root: Rscript tests/test_realtime_integration.R
# These synthetic messages exercise presence and integration invariants without API calls.
source(file.path("R", "parsing", "read_trip_updates.R"))
source(file.path("R", "integration", "integrate_gtfs.R"))
load_gtfs_schema()

pb_message <- function(type, ...) {
  result <- RProtoBuf::new(RProtoBuf::P(paste0("transit_realtime.", type)))
  fields <- list(...)
  for (field in names(fields)) result[[field]] <- fields[[field]]
  result
}
event <- function(...) pb_message("TripUpdate.StopTimeEvent", ...)
stop_update <- function(...) pb_message("TripUpdate.StopTimeUpdate", ...)
trip_entity <- function(id, trip_id, relationship = NULL, updates = list(),
                        start_date = "20260918", ...) {
  trip <- pb_message("TripDescriptor", trip_id = trip_id, start_date = start_date)
  if (!is.null(relationship)) trip$schedule_relationship <- relationship
  update <- pb_message("TripUpdate", trip = trip, stop_time_update = updates, ...)
  pb_message("FeedEntity", id = id, trip_update = update)
}
make_feed <- function(entities = list(), timestamp = 1789680000) {
  header <- pb_message("FeedHeader", gtfs_realtime_version = "2.0")
  if (!is.null(timestamp)) header$timestamp <- timestamp
  pb_message("FeedMessage", header = header, entity = entities)
}
same_epoch <- function(actual, expected) {
  stopifnot(inherits(actual, "POSIXct"),
            identical(as.numeric(actual), as.numeric(expected)))
}

# Unset optional scalars have Protobuf default values, but remain missing data.
missing_event <- event()
stopifnot(!missing_event$has("delay"), missing_event$delay == 0,
          is.na(proto_value(missing_event, "delay")))
missing_row <- stop_update_row(stop_update(arrival = missing_event), 1L)
event_columns <- c("arrival_delay_seconds", "departure_delay_seconds",
                   "realtime_arrival_time_utc", "realtime_departure_time_utc",
                   "realtime_arrival_scheduled_time_utc", "realtime_departure_scheduled_time_utc",
                   "arrival_uncertainty_seconds", "departure_uncertainty_seconds")
stopifnot(all(vapply(missing_row[event_columns], function(x) all(is.na(x)), logical(1))),
          is.na(missing_row$realtime_stop_sequence),
          is.na(missing_row$stop_schedule_relationship))

# An explicitly supplied zero is a real scalar value and must survive parsing.
zero_row <- stop_update_row(stop_update(
  stop_id = "A", stop_sequence = 0, schedule_relationship = 0,
  arrival = event(delay = 0, time = 0, scheduled_time = 0, uncertainty = 0),
  departure = event(delay = 0, time = 0, scheduled_time = 0, uncertainty = 0)), 1L)
stopifnot(all(vapply(zero_row[event_columns], function(x) identical(as.numeric(x), 0), logical(1))),
          identical(zero_row$realtime_stop_sequence, 0),
          identical(zero_row$stop_schedule_relationship, 0))
for (column in grep("_utc$", names(zero_row), value = TRUE)) {
  stopifnot(inherits(zero_row[[column]], "POSIXct"),
            identical(attr(zero_row[[column]], "tzone"), "UTC"))
}
same_epoch(utc_epoch(c(0, NA, Inf, 2^54)), c(0, NA_real_, NA_real_, NA_real_))

replacement_arrival <- 1789690000
replacement_departure <- replacement_arrival + 30
entities <- list(
  trip_entity("ordinary", "ordinary", 0, list(
    stop_update(stop_id = "A", stop_sequence = 11,
                arrival = event(delay = 60, time = 1789699000),
                departure = event(delay = -10, time = 1789699010))
  ), timestamp = 1789680100),
  trip_entity("replacement", "replacement", 5, list(
    stop_update(stop_id = "B", stop_sequence = 999, arrival = event(time = 1789691000)),
    stop_update(stop_id = "A", stop_sequence = 998,
                arrival = event(time = replacement_arrival + 40,
                                scheduled_time = replacement_arrival, uncertainty = 12),
                departure = event(time = replacement_departure + 40,
                                  scheduled_time = replacement_departure, uncertainty = 9)),
    stop_update(stop_id = "EXTRA", stop_sequence = 997,
                arrival = event(scheduled_time = replacement_arrival + 100))
  )),
  # Deliberate static identifier collision proves NEW cannot inherit its old schedule.
  trip_entity("new", "new", 8, list(stop_update(stop_id = "A", stop_sequence = 50))),
  trip_entity("loop_sequence", "loop", 0, list(stop_update(stop_id = "A", stop_sequence = 3))),
  trip_entity("loop_ambiguous", "loop", 0, list(stop_update(stop_id = "A"))),
  trip_entity("loop_replacement", "loop", 5, list(stop_update(stop_id = "A", stop_sequence = 3))),
  trip_entity("loop_no_id", "loop", 0, list(stop_update(stop_sequence = 2))),
  trip_entity("loop_wrong_id", "loop", 0, list(stop_update(stop_id = "WRONG", stop_sequence = 2))),
  trip_entity("default_scheduled", "ordinary", NULL, list(stop_update(stop_id = "A"))),
  trip_entity("zero_stops", "zero_stops", 0, timestamp = 0, delay = 0),
  pb_message("FeedEntity", id = "non_trip_entity")
)
feed <- make_feed(entities)
flat <- flatten_gtfs_feed(feed)
summary <- flat$trip_summary_df
realtime <- flat$trip_updates_df
stopifnot(nrow(summary) == 10L, nrow(realtime) == 11L,
          sum(summary$number_of_stop_updates == 0L) == 1L,
          "zero_stops" %in% summary$trip_id,
          !"zero_stops" %in% realtime$trip_id,
          !"non_trip_entity" %in% summary$entity_id)
zero_trip <- summary[summary$entity_id == "zero_stops", ]
stopifnot(identical(zero_trip$trip_level_delay_seconds, 0),
          is.na(zero_trip$direction_id), is.na(zero_trip$route_id), is.na(zero_trip$start_time))
same_epoch(zero_trip$trip_update_time_utc, 0)
stopifnot(is.na(summary$trip_update_time_utc[summary$entity_id == "replacement"]),
          is.na(summary$trip_schedule_relationship[summary$entity_id == "default_scheduled"]))
replacement_raw <- realtime[realtime$entity_id == "replacement", ]
stopifnot(identical(replacement_raw$realtime_update_order, 1:3),
          identical(replacement_raw$stop_id, c("B", "A", "EXTRA")),
          identical(replacement_raw$arrival_uncertainty_seconds, c(NA_real_, 12, NA_real_)),
          identical(replacement_raw$departure_uncertainty_seconds, c(NA_real_, 9, NA_real_)))

static <- list(
  routes = data.frame(route_id = "T1", route_short_name = "T1", route_type = 2L),
  trips = data.frame(trip_id = c("ordinary", "replacement", "new", "loop"),
                     route_id = "T1", service_id = "service"),
  stops = data.frame(stop_id = c("A", "B", "EXTRA"), stop_name = c("Alpha", "Beta", "Extra")),
  stop_times = data.frame(
    trip_id = c("ordinary", "replacement", "replacement", "new", "loop", "loop", "loop"),
    stop_id = c("A", "A", "B", "A", "A", "B", "A"),
    stop_sequence = c(11L, 10L, 20L, 50L, 1L, 2L, 3L),
    arrival_time = c("25:03:00", "10:00:00", "10:10:00", "12:00:00", "14:00:00", "14:10:00", "14:20:00"),
    departure_time = c("25:04:00", "10:01:00", "10:11:00", "12:01:00", "14:01:00", "14:11:00", "14:21:00")),
  parsing_problem_count = 0L
)
integrated <- integrate_gtfs(realtime, static, utc_epoch(1789680200), utc_epoch(1789680000))
stopifnot(nrow(integrated) == nrow(realtime),
          identical(integrated$entity_id, realtime$entity_id),
          sum(integrated$is_replacement_trip) == sum(realtime$trip_schedule_relationship == 5, na.rm = TRUE))
replacement <- integrated[integrated$entity_id == "replacement", ]
stopifnot(identical(replacement$effective_stop_order, c(1, 2, 3)),
          identical(replacement$static_stop_sequence, c(20L, 10L, NA_integer_)),
          identical(replacement$static_trip_stop_match, c(TRUE, TRUE, FALSE)),
          identical(replacement$replacement_missing_scheduled_time, c(TRUE, FALSE, TRUE)),
          !any(replacement$uses_static_scheduled_baseline),
          all(replacement$effective_schedule_source == "realtime_scheduled_time"))
same_epoch(replacement$effective_scheduled_arrival_utc,
           c(NA_real_, replacement_arrival, replacement_arrival + 100))
same_epoch(replacement$effective_scheduled_departure_utc,
           c(NA_real_, replacement_departure, NA_real_))
stopifnot(!is.na(replacement$static_arrival_time[1]),
          is.na(replacement$effective_scheduled_arrival_utc[1]))
new_trip <- integrated[integrated$entity_id == "new", ]
stopifnot(new_trip$static_trip_stop_match, !new_trip$uses_static_scheduled_baseline,
          new_trip$effective_schedule_missing, is.na(new_trip$effective_scheduled_arrival_utc),
          is.na(new_trip$effective_scheduled_departure_utc), new_trip$effective_stop_order == 1)

ordinary <- integrated[integrated$entity_id %in% c("ordinary", "default_scheduled"), ]
stopifnot(all(ordinary$uses_static_scheduled_baseline),
          all(ordinary$effective_stop_order == 11),
          all(ordinary$effective_schedule_source == "static_service_date"))
same_epoch(ordinary$effective_scheduled_arrival_utc,
           rep(as.POSIXct("2026-09-18 15:03:00", tz = "UTC"), 2))
same_epoch(ordinary$effective_scheduled_departure_utc,
           rep(as.POSIXct("2026-09-18 15:04:00", tz = "UTC"), 2))

sequence_row <- integrated[integrated$entity_id == "loop_sequence", ]
ambiguous_row <- integrated[integrated$entity_id == "loop_ambiguous", ]
replacement_loop <- integrated[integrated$entity_id == "loop_replacement", ]
no_id_row <- integrated[integrated$entity_id == "loop_no_id", ]
wrong_id_row <- integrated[integrated$entity_id == "loop_wrong_id", ]
stopifnot(sequence_row$static_trip_stop_match, sequence_row$static_stop_sequence == 3,
          sequence_row$static_arrival_time == "14:20:00",
          !ambiguous_row$static_trip_stop_match, ambiguous_row$static_trip_stop_ambiguous,
          !replacement_loop$static_trip_stop_match, replacement_loop$static_trip_stop_ambiguous,
          replacement_loop$effective_stop_order == 1,
          no_id_row$static_trip_stop_match, no_id_row$resolved_stop_id == "B",
          !wrong_id_row$static_trip_stop_match,
          attr(integrated, "duplicate_diagnostics")[["trip_stop_rows"]] == 2L)

# Duplicate metadata and sequence keys likewise cannot expand the observations.
duplicated_static <- static
for (table in c("routes", "trips", "stops", "stop_times")) {
  duplicated_static[[table]] <- rbind(static[[table]], static[[table]][1, , drop = FALSE])
}
duplicated_result <- integrate_gtfs(realtime, duplicated_static, utc_epoch(1789680200), utc_epoch(1789680000))
stopifnot(nrow(duplicated_result) == nrow(realtime),
          all(attr(duplicated_result, "duplicate_diagnostics") > 0))

empty <- flatten_gtfs_feed(make_feed())
stopifnot(nrow(empty$trip_summary_df) == 0L, nrow(empty$trip_updates_df) == 0L,
          identical(names(empty$trip_summary_df), names(summary)),
          identical(names(empty$trip_updates_df), names(realtime)),
          identical(lapply(empty$trip_summary_df, class), lapply(summary, class)),
          identical(lapply(empty$trip_updates_df, class), lapply(realtime, class)))
empty_integrated <- integrate_gtfs(empty$trip_updates_df, static, utc_epoch(1789680200), utc_epoch(1789680000))
stopifnot(nrow(empty_integrated) == 0L,
          inherits(empty_integrated$effective_scheduled_arrival_utc, "POSIXct"))

# Exercise the binary reader, collection timestamp, and absent feed timestamp.
fixture_dir <- file.path("logs", "tests", "realtime_integration")
dir.create(fixture_dir, recursive = TRUE, showWarnings = FALSE)
fixture_path <- file.path(fixture_dir, "fixture_20260918T000000Z.pb")
writeBin(RProtoBuf::serialize(feed, NULL), fixture_path)
read_result <- read_trip_updates(fixture_path)
stopifnot(nrow(read_result$trip_updates_df) == nrow(realtime))
same_epoch(read_result$snapshot_time_utc, as.POSIXct("2026-09-18 00:00:00", tz = "UTC"))
same_epoch(read_result$feed_time_utc, 1789680000)
missing_timestamp_path <- file.path(fixture_dir, "empty_20260918T000001Z.pb")
writeBin(RProtoBuf::serialize(make_feed(timestamp = NULL), NULL), missing_timestamp_path)
missing_timestamp <- read_trip_updates(missing_timestamp_path)
stopifnot(is.na(missing_timestamp$feed_time_utc), nrow(missing_timestamp$trip_summary_df) == 0L)
cat("Realtime parsing and GTFS integration tests passed.\n")
