# Synthetic scope and report checks; no network access or saved feed dependency.
source("R/parsing/read_trip_updates.R")
source("R/integration/integrate_gtfs.R")
source("R/processing/process_gtfs.R")
source("R/utils/validate_gtfs.R")

expect_failure <- function(expression) {
  result <- tryCatch(force(expression), error = function(e) e)
  stopifnot(inherits(result, "error"))
}
trip_ids <- c("passenger", "empty", "outside", "unknown", "replacement")
rt <- tibble::tibble(
  entity_id = paste0("entity_", trip_ids), entity_order = seq_along(trip_ids),
  trip_id = trip_ids, route_id = NA_character_, direction_id = NA_real_,
  start_date = "20260918", start_time = NA_character_,
  trip_schedule_relationship = c(0, 0, 0, 0, 5),
  trip_update_time_utc = utc_epoch(rep(1789680000, 5)),
  trip_level_delay_seconds = NA_real_, number_of_stop_updates = 1L,
  realtime_update_order = 1L, realtime_stop_sequence = 1,
  stop_id = c("S", "S", "S", "UNKNOWN", "S"), stop_schedule_relationship = 0,
  arrival_delay_seconds = c(0, NA_real_, 60, NA_real_, 0),
  departure_delay_seconds = c(0, 20, NA_real_, NA_real_, NA_real_),
  realtime_arrival_time_utc = utc_epoch(rep(NA_real_, 5)),
  realtime_departure_time_utc = utc_epoch(rep(NA_real_, 5)),
  realtime_arrival_scheduled_time_utc = utc_epoch(rep(NA_real_, 5)),
  realtime_departure_scheduled_time_utc = utc_epoch(rep(NA_real_, 5)),
  arrival_uncertainty_seconds = NA_real_, departure_uncertainty_seconds = NA_real_
)
trip_summary <- rt[, seq_len(11)]
zero_summary <- trip_summary[1, ]
zero_summary$entity_id <- "entity_zero"
zero_summary$trip_id <- "zero"
zero_summary$number_of_stop_updates <- 0L
trip_summary <- dplyr::bind_rows(trip_summary, zero_summary)
static <- list(
  routes = tibble::tibble(route_id = c("route_t1", "route_t2", "route_xpt"),
                          route_short_name = c("T1", "T2", "XPT"), route_type = 2L),
  trips = tibble::tibble(trip_id = c("passenger", "empty", "outside", "replacement", "zero"),
                         route_id = c("route_t1", "route_t2", "route_xpt", "route_t1", "route_t1"),
                         service_id = "service", trip_headsign = c("Central", "EmPtY Train to depot", "Dubbo", "Central", "Central")),
  stops = tibble::tibble(stop_id = "S", stop_name = "Station"),
  stop_times = tibble::tibble(trip_id = c("passenger", "empty", "outside", "replacement"),
                              stop_id = "S", stop_sequence = 1L,
                              arrival_time = "10:00:00", departure_time = "10:01:00"),
  parsing_problem_count = 0L
)
parsed <- list(trip_updates_df = rt, trip_summary_df = trip_summary,
               snapshot_time_utc = utc_epoch(1789680200), feed_time_utc = utc_epoch(1789680000))
integrated <- integrate_gtfs(rt, static, parsed$snapshot_time_utc, parsed$feed_time_utc)
train_config <- list(mode = "train", subfeed = "sydneytrains", scope = "train_t1_t9",
                     static_endpoint = "/v1/gtfs/schedule/sydneytrains", timezone = "Australia/Sydney")
scoped <- scope_gtfs(integrated, train_config)
stopifnot(nrow(scoped$audit) == nrow(integrated), nrow(scoped$processed) == 2L,
          identical(scoped$processed$trip_id, c("passenger", "replacement")),
          all(scoped$processed$route_short_name == "T1"),
          all(scoped$processed$keep_for_project), !any(scoped$processed$is_empty_train),
          all(scoped$processed$mode == "train"),
          all(scoped$processed$source_subfeed == "sydneytrains"),
          all(scoped$processed$source_feed == train_config$static_endpoint))
reason <- stats::setNames(scoped$audit$scope_status, scoped$audit$trip_id)
stopifnot(reason[["empty"]] == "EXCLUDE_EMPTY_TRAIN",
          reason[["outside"]] == "EXCLUDE_OUTSIDE_T1_T9",
          reason[["unknown"]] == "EXCLUDE_MISSING_ROUTE_METADATA",
          reason[["replacement"]] == "KEEP")

# A quiet snapshot containing only T1 must remain valid; absent lines are not failures.
report <- validate_gtfs(parsed, static, integrated, scoped$processed, train_config)
expected_fields <- c(
  "snapshot_time_utc", "feed_time_utc", "trip_update_count", "zero_stop_trip_update_count",
  "stop_level_rows", "unique_trips", "unique_stops", "arrival_delay_coverage",
  "departure_delay_coverage", "trip_schedule_relationship_counts", "stop_schedule_relationship_counts",
  "replacement_rows", "replacement_missing_schedule_rows", "static_trip_match_rate",
  "static_stop_match_rate", "static_trip_stop_match_rate", "unmatched_rows",
  "rows_before_integration", "rows_after_integration", "duplicate_trip_key_rows",
  "duplicate_stop_key_rows", "duplicate_route_key_rows", "duplicate_trip_stop_key_rows",
  "duplicate_trip_sequence_key_rows", "static_parsing_problems", "processed_rows", "processed_columns"
)
stopifnot(nrow(report) == 1L, all(expected_fields %in% names(report)),
          report$trip_update_count == 6L, report$zero_stop_trip_update_count == 1L,
          report$stop_level_rows == 5L, report$unique_trips == 5L, report$unique_stops == 2L,
          report$arrival_delay_coverage == 3 / 5, report$departure_delay_coverage == 2 / 5,
          report$replacement_rows == 1L, report$replacement_missing_schedule_rows == 1L,
          report$static_trip_match_rate == 4 / 5, report$static_trip_summary_match_rate == 5 / 6,
          report$static_stop_match_rate == 4 / 5, report$static_trip_stop_match_rate == 4 / 5,
          report$unmatched_rows == 1L, report$rows_before_integration == 5L,
          report$rows_after_integration == 5L, report$processed_rows == 2L,
          report$processed_columns == ncol(scoped$processed), report$static_parsing_problems == 0L,
          grepl("5:1", report$trip_schedule_relationship_counts, fixed = TRUE),
          all(unlist(report[grep("^duplicate_.*_key_rows$", names(report))]) == 0))

# Feed-scoped modes preserve the identifiers actually supplied by their feed.
metro_config <- list(mode = "metro", subfeed = "metro", scope = "feed",
                     static_endpoint = "/v2/gtfs/schedule/metro", timezone = "Australia/Sydney")
metro_input <- integrated
metro_input$route_short_name <- c("M", "M1", "M", NA_character_, "M1")
metro <- scope_gtfs(metro_input, metro_config)
stopifnot(nrow(metro$processed) == nrow(metro_input),
          identical(metro$processed$route_short_name, metro_input$route_short_name),
          all(metro$processed$mode == "metro"), all(metro$processed$source_subfeed == "metro"),
          all(metro$processed$source_feed == metro_config$static_endpoint))
metro_report <- validate_gtfs(parsed, static, metro_input, metro$processed, metro_config)
stopifnot(metro_report$mode == "metro", metro_report$processed_rows == 5L)

# Validation must reject mixed modes, excluded observations, and changed row counts.
bad_processed <- scoped$processed
bad_processed$mode[1] <- "ferry"
expect_failure(validate_gtfs(parsed, static, integrated, bad_processed, train_config))
bad_processed <- scoped$processed
bad_processed$keep_for_project[1] <- FALSE
expect_failure(validate_gtfs(parsed, static, integrated, bad_processed, train_config))
expect_failure(validate_gtfs(parsed, static, integrated[c(seq_len(nrow(integrated)), 1L), ],
                             scoped$processed, train_config))
bad_replacement <- integrated
bad_replacement$effective_scheduled_arrival_utc[bad_replacement$is_replacement_trip] <- utc_epoch(1789690000)
expect_failure(validate_gtfs(parsed, static, bad_replacement, scoped$processed, train_config))

# Empty snapshots are valid, and coverage denominators are reported as NA.
empty_parsed <- parsed
empty_parsed$trip_updates_df <- rt[0, ]
empty_parsed$trip_summary_df <- trip_summary[0, ]
empty_integrated <- integrate_gtfs(rt[0, ], static, parsed$snapshot_time_utc, parsed$feed_time_utc)
empty_scope <- scope_gtfs(empty_integrated, train_config)
empty_report <- validate_gtfs(empty_parsed, static, empty_integrated, empty_scope$processed, train_config)
stopifnot(empty_report$trip_update_count == 0L, empty_report$processed_rows == 0L,
          is.na(empty_report$arrival_delay_coverage), is.na(empty_report$departure_delay_coverage),
          is.na(empty_report$static_trip_match_rate), is.na(empty_report$static_stop_match_rate),
          is.na(empty_report$static_trip_stop_match_rate))
cat("Scope and validation report tests passed.\n")
