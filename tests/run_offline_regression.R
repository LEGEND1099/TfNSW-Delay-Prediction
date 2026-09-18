# Saved-snapshot integration regression, separate from synthetic unit tests.
# Rscript tests/run_offline_regression.R [--check-existing]
# Missing saved feeds are failures; this script never downloads replacements.
source("R/pipeline/load_pipeline.R")
args <- commandArgs(trailingOnly = TRUE)
stopifnot(all(args %in% "--check-existing"))
tfnsw_download_payload <- function(...) stop("Network acquisition is disabled during offline regression.")
expected_modes <- c("train", "metro", "ferry", "bus", "light_rail")
run <- if ("--check-existing" %in% args) readRDS("logs/validation/latest_run.rds") else {
  run_modes_once(expected_modes, offline = TRUE)
}
stopifnot(!length(run$failures), setequal(names(run$mode_outputs), expected_modes))
report <- run$validation
stopifnot(nrow(report) == length(tfnsw_feeds),
          setequal(report$source_subfeed, vapply(tfnsw_feeds, `[[`, character(1), "subfeed")),
          all(report$static_parsing_problems == 0L),
          all(report$rows_before_integration == report$rows_after_integration))
required_report_fields <- c("mode", "source_subfeed", "source_operator", "snapshot_time_utc",
  "feed_time_utc", "trip_update_count", "zero_stop_trip_update_count", "stop_level_rows",
  "unique_trips", "unique_stops", "arrival_delay_coverage", "departure_delay_coverage",
  "trip_schedule_relationship_counts", "stop_schedule_relationship_counts", "replacement_rows",
  "static_trip_match_rate", "static_stop_match_rate", "static_trip_stop_match_rate",
  "unmatched_rows", "duplicate_trip_key_rows", "duplicate_stop_key_rows", "duplicate_route_key_rows",
  "duplicate_trip_stop_key_rows", "duplicate_trip_sequence_key_rows", "processed_rows",
  "processed_columns", "processed_path", "mode_processed_path")
stopifnot(all(required_report_fields %in% names(report)))
same_data <- function(a, b) {
  if (is.data.frame(a) || is.data.frame(b)) {
    if (!is.data.frame(a) || !is.data.frame(b) || !identical(names(a), names(b))) return(FALSE)
  }
  isTRUE(all.equal(a, b, check.attributes = FALSE))
}
parts <- list()
details <- list()
for (name in names(tfnsw_feeds)) {
  config <- tfnsw_feeds[[name]]
  row <- report[report$source_subfeed == config$subfeed & report$mode == config$mode, ]
  stopifnot(nrow(row) == 1L)
  tag <- format(row$snapshot_time_utc, "%Y%m%dT%H%M%SZ", tz = "UTC")
  prefix <- file.path(config$interim_dir, paste0(config$subfeed, "_", tag))
  summary <- readRDS(paste0(prefix, "_trip_summary.rds"))
  stops <- readRDS(paste0(prefix, "_stop_updates.rds"))
  audit <- readRDS(paste0(prefix, "_scope_audit.rds"))
  processed <- readRDS(row$processed_path)
  stopifnot(nrow(summary) == row$trip_update_count,
    sum(summary$number_of_stop_updates == 0L) == row$zero_stop_trip_update_count,
    sum(summary$number_of_stop_updates) == nrow(stops),
    nrow(stops) == row$stop_level_rows, nrow(audit) == nrow(stops),
    nrow(processed) == row$processed_rows, ncol(processed) == row$processed_columns,
    identical(stops$entity_order, audit$entity_order),
    identical(stops$realtime_update_order, audit$realtime_update_order),
    identical(stops$trip_id, audit$trip_id), identical(stops$stop_id, audit$stop_id),
    identical(stops$arrival_delay_seconds, audit$arrival_delay_seconds),
    identical(stops$departure_delay_seconds, audit$departure_delay_seconds),
    same_data(processed, audit[audit$keep_for_project, ]),
    all(audit$mode == config$mode), all(audit$source_subfeed == config$subfeed),
    sum(!audit$static_trip_stop_match) == row$unmatched_rows,
    same_data(rate(audit$static_trip_match), row$static_trip_match_rate),
    same_data(rate(audit$static_stop_match), row$static_stop_match_rate),
    same_data(rate(audit$static_trip_stop_match), row$static_trip_stop_match_rate),
    row$mode_processed_path == run$mode_outputs[[config$mode]]$processed_path)
  replacement <- audit$is_replacement_trip
  stopifnot(sum(replacement) == row$replacement_rows,
    all(!audit$uses_static_scheduled_baseline[replacement]),
    same_data(audit$effective_stop_order[replacement], audit$realtime_update_order[replacement]),
    identical(audit$effective_scheduled_arrival_utc[replacement], audit$realtime_arrival_scheduled_time_utc[replacement]),
    identical(audit$effective_scheduled_departure_utc[replacement], audit$realtime_departure_scheduled_time_utc[replacement]))
  if (config$mode == "train") stopifnot(
    all(processed$route_short_name %in% paste0("T", 1:9)), !any(processed$is_empty_train))
  if (config$mode %in% c("metro", "ferry", "light_rail")) stopifnot(
    nrow(processed) == nrow(audit), identical(processed$route_id, audit$route_id))
  if (config$mode == "ferry") stopifnot(config$subfeed == "sydneyferries",
    sum(!processed$static_trip_stop_match) == row$unmatched_rows)
  if (config$mode == "bus") {
    newcastle <- audit$source_operator %in% config$excluded_operator_names
    contingency <- !is.na(audit$scope_catalog)
    eligible_school <- audit$route_type %in% c(712L, 713L) &
      !is.na(audit$source_operator) & !newcastle & !contingency
    stopifnot(!any(processed$source_operator %in% config$excluded_operator_names),
      !any(processed$route_type %in% c(701L, 714L)), all(is.na(processed$scope_catalog)),
      all(processed$is_school_service == (processed$route_type %in% c(712L, 713L))),
      all(!audit$keep_for_project[newcastle | contingency | audit$route_type %in% c(701L, 714L)]),
      all(grepl("^EXCLUDE_", audit$scope_status[newcastle | contingency])),
      all(audit$keep_for_project[eligible_school]),
      sum(processed$is_school_service) == sum(audit$is_school_service & audit$keep_for_project))
  }
  if (config$mode == "light_rail") stopifnot(
    all(!is.na(processed$source_operator) & nzchar(trimws(processed$source_operator))),
    !any(grepl("newcastle", processed$source_operator, ignore.case = TRUE)))
  parts[[name]] <- processed
  details[[name]] <- tibble::tibble(mode = config$mode, source_subfeed = config$subfeed,
    status = "PASS", processed_rows = nrow(processed), processed_columns = ncol(processed),
    unmatched_audit_rows = sum(!audit$static_trip_stop_match), excluded_audit_rows = sum(!audit$keep_for_project),
    school_processed_rows = if (config$mode == "bus") sum(processed$is_school_service) else NA_integer_)
  cat("Verified saved outputs:", config$mode, config$subfeed, nrow(processed), "x", ncol(processed), "\n")
}
lr_configs <- Filter(function(config) config$mode == "light_rail", tfnsw_feeds)
stopifnot(setequal(vapply(lr_configs, `[[`, character(1), "subfeed"),
                  c("innerwest", "cbdandsoutheast", "parramatta")))
for (mode in expected_modes) {
  configs <- Filter(function(config) config$mode == mode, tfnsw_feeds)
  output <- run$mode_outputs[[mode]]
  expected <- dplyr::bind_rows(parts[names(configs)])
  actual <- readRDS(output$processed_path)
  stopifnot(setequal(output$source_subfeeds, vapply(configs, `[[`, character(1), "subfeed")),
    same_data(actual, expected), nrow(actual) == output$processed_rows,
    ncol(actual) == output$processed_columns,
    file.exists(sub("\\.rds$", ".csv", output$processed_path)))
}
checks <- dplyr::bind_rows(details)
saveRDS(list(checked_at_utc = as.POSIXct(Sys.time(), tz = "UTC"), checks = checks,
             validation = report, mode_outputs = run$mode_outputs), "logs/validation/offline_regression.rds")
readr::write_csv(checks, "logs/validation/offline_regression.csv")
cat("Five-mode offline regression passed. Match rates are reported without arbitrary thresholds.\n")
