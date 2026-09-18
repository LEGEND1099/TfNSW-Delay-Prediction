# Synthetic ambiguity and report checks, including zero-stop trip summaries.
source("R/parsing/read_trip_updates.R")
source("R/integration/integrate_gtfs.R")
source("R/utils/validate_gtfs.R")

rt <- tibble::tibble(
  entity_id = c("matched", "ambiguous", "replacement"),
  trip_id = c("unique_trip", "duplicate_trip", "unknown_trip"),
  route_id = c("realtime_route", "R2", "R3"), direction_id = NA_real_,
  start_date = "20260918", trip_schedule_relationship = c(0, 0, 5),
  trip_update_time_utc = utc_epoch(rep(1789680000, 3)),
  number_of_stop_updates = 1L, realtime_update_order = 1L,
  realtime_stop_sequence = 1, stop_id = c("S", "S", "UNKNOWN"),
  stop_schedule_relationship = 0,
  arrival_delay_seconds = c(0, NA_real_, 60), departure_delay_seconds = NA_real_,
  realtime_arrival_scheduled_time_utc = utc_epoch(rep(NA_real_, 3)),
  realtime_departure_scheduled_time_utc = utc_epoch(rep(NA_real_, 3))
)
summary <- rt[, c("entity_id", "trip_id", "number_of_stop_updates", "trip_schedule_relationship")]
zero_summary <- summary[2, ]
zero_summary$entity_id <- "ambiguous_zero_stop"
zero_summary$number_of_stop_updates <- 0L
summary <- dplyr::bind_rows(summary, zero_summary)
static <- list(
  trips = tibble::tibble(trip_id = c("unique_trip", "duplicate_trip", "duplicate_trip"),
                         route_id = c("R;quoted", "R2", "R2"), service_id = "service"),
  stop_times = tibble::tibble(trip_id = c("unique_trip", "duplicate_trip", "duplicate_trip"),
                              stop_id = "S", stop_sequence = 1L,
                              arrival_time = "10:00:00", departure_time = "10:01:00"),
  routes = tibble::tibble(route_id = c("R;quoted", "R2"),
                          route_short_name = c("01", "two\nlines")),
  stops = tibble::tibble(stop_id = "S", stop_name = "Stop"),
  parsing_problem_count = 0L
)
parsed <- list(trip_updates_df = rt, trip_summary_df = summary,
               snapshot_time_utc = utc_epoch(1789680200), feed_time_utc = utc_epoch(1789680000))
integrated <- integrate_gtfs(rt, static, parsed$snapshot_time_utc, parsed$feed_time_utc)
integrated$source_operator <- c("Transit;\"North\"\nDivision", NA_character_, " \t ")
processed <- integrated
processed$mode <- "synthetic"
processed$keep_for_project <- TRUE
config <- list(mode = "synthetic", subfeed = "synthetic", scope = "feed")
report <- validate_gtfs(parsed, static, integrated, processed, config)

# Membership in static$trips alone is not sufficient: both duplicate trip keys,
# including the zero-stop update, must remain unresolved in the summary metric.
stopifnot(report$trip_update_count == 4L, report$zero_stop_trip_update_count == 1L,
          report$static_trip_match_rate == 1 / 3,
          report$static_trip_summary_match_rate == 1 / 4,
          report$ambiguous_trip_summary_rows == 2L,
          report$static_trip_stop_match_rate == 1 / 3,
          report$unmatched_rows == 2L,
          report$unmatched_static_trip_rows == 2L,
          report$unmatched_static_stop_rows == 1L,
          report$unmatched_trip_schedule_relationship_counts == "0:1;5:1",
          report$duplicate_trip_key_rows == 2L,
          report$duplicate_trip_stop_key_rows == 2L,
          report$ambiguous_trip_stop_rows == 1L,
          report$rows_before_integration == report$rows_after_integration,
          report$observed_realtime_route_ids == observed_identifiers(rt$route_id),
          report$observed_route_ids == observed_identifiers(c("R;quoted", "R2", "R3")),
          report$observed_route_short_names == observed_identifiers(c("01", "two\nlines")),
          !grepl("\n", report$observed_route_short_names, fixed = TRUE),
          report$processed_route_ids == report$observed_route_ids,
          report$source_operator == observed_identifiers(integrated$source_operator[1]),
          report$missing_source_operator_rows == 2L,
          report$processed_source_operator == report$source_operator,
          report$processed_missing_source_operator_rows == 2L)

# Missing attribution remains explicit, including for rows outside the processed
# population. Validation must neither fill operators nor remove unmatched rows.
processed_subset <- processed[1:2, ]
subset_report <- validate_gtfs(parsed, static, integrated, processed_subset, config)
stopifnot(subset_report$missing_source_operator_rows == 2L,
          subset_report$processed_missing_source_operator_rows == 1L,
          subset_report$unmatched_rows == 2L,
          identical(integrated$source_operator, c("Transit;\"North\"\nDivision", NA_character_, " \t ")),
          is.na(processed_subset$source_operator[2]))
blank_operator <- integrated
blank_operator$source_operator[3] <- ""
blank_report <- validate_gtfs(parsed, static, blank_operator, processed, config)
stopifnot(blank_report$missing_source_operator_rows == 2L)

# Callers without an attribution column report all rows as unattributed; empty
# snapshots correctly have no observed operators and zero missing rows.
without_operators <- integrated
without_operators$source_operator <- NULL
processed_without_operators <- processed
processed_without_operators$source_operator <- NULL
missing_report <- validate_gtfs(parsed, static, without_operators, processed_without_operators, config)
stopifnot(missing_report$source_operator == "", missing_report$processed_source_operator == "",
          missing_report$missing_source_operator_rows == nrow(integrated),
          missing_report$processed_missing_source_operator_rows == nrow(processed))
empty_parsed <- parsed
empty_parsed$trip_updates_df <- rt[0, ]
empty_parsed$trip_summary_df <- summary[0, ]
empty_integrated <- integrate_gtfs(rt[0, ], static, parsed$snapshot_time_utc, parsed$feed_time_utc)
empty_report <- validate_gtfs(empty_parsed, static, empty_integrated, processed[0, ], config)
stopifnot(empty_report$source_operator == "", empty_report$processed_source_operator == "",
          empty_report$missing_source_operator_rows == 0L,
          empty_report$processed_missing_source_operator_rows == 0L)

# Summaries with delimiter-bearing identifiers survive a CSV write/read intact.
fixture_dir <- file.path("logs", "tests", "validation_diagnostics")
dir.create(fixture_dir, recursive = TRUE, showWarnings = FALSE)
csv_path <- tempfile("report_", tmpdir = fixture_dir, fileext = ".csv")
readr::write_csv(report, csv_path)
roundtrip <- readr::read_csv(csv_path, col_types = readr::cols(.default = readr::col_character()),
                           show_col_types = FALSE)
summary_fields <- c("observed_realtime_route_ids", "observed_route_ids", "observed_route_short_names",
                    "processed_route_ids", "processed_route_short_names",
                    "source_operator", "processed_source_operator",
                    "unmatched_trip_schedule_relationship_counts")
for (field in summary_fields) stopifnot(identical(roundtrip[[field]], report[[field]]))
stopifnot(identical(observed_identifiers(c(NA_character_, NA_character_)), ""),
          identical(observed_identifiers(character()), ""))
cat("Ambiguous trip-summary linkage and validation diagnostics tests passed.\n")
