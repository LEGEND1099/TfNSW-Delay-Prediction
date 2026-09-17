rate <- function(x) if (length(x)) mean(x) else NA_real_
relationship_counts <- function(x) {
  values <- ifelse(is.na(x), "ABSENT", as.character(x))
  counts <- table(values)
  paste(names(counts), as.integer(counts), sep = ":", collapse = ";")
}
observed_identifiers <- function(x) {
  # Quote identifiers so embedded separators/newlines are distinguishable in a
  # one-cell summary. write_csv supplies the surrounding CSV field escaping.
  values <- sort(unique(as.character(x[!is.na(x)])))
  paste(encodeString(values, quote = '"'), collapse = ";")
}
validate_gtfs <- function(parsed, static, integrated, processed, config) {
  rt <- parsed$trip_updates_df
  ts <- parsed$trip_summary_df
  replacement <- integrated$is_replacement_trip
  stopifnot(nrow(rt) == nrow(integrated),
    sum(replacement) == sum(rt$trip_schedule_relationship %in% 5),
    all(integrated$effective_stop_order[replacement] == rt$realtime_update_order[replacement]),
    identical(as.numeric(integrated$effective_scheduled_arrival_utc[replacement]),
              as.numeric(rt$realtime_arrival_scheduled_time_utc[replacement])),
    identical(as.numeric(integrated$effective_scheduled_departure_utc[replacement]),
              as.numeric(rt$realtime_departure_scheduled_time_utc[replacement])),
    all(processed$mode == config$mode), all(processed$keep_for_project))
  if (config$scope == "train_t1_t9") stopifnot(
    all(processed$route_short_name %in% paste0("T", 1:9)), !any(processed$is_empty_train))
  dup <- attr(integrated, "duplicate_diagnostics")
  summary_trip_lookup <- unique_lookup(ts, static$trips, "trip_id")
  unmatched <- !integrated$static_trip_stop_match
  tibble::tibble(mode = config$mode, source_subfeed = config$subfeed,
    snapshot_time_utc = parsed$snapshot_time_utc, feed_time_utc = parsed$feed_time_utc,
    trip_update_count = nrow(ts), zero_stop_trip_update_count = sum(ts$number_of_stop_updates == 0L),
    stop_level_rows = nrow(rt), unique_trips = dplyr::n_distinct(rt$trip_id, na.rm = TRUE),
    unique_stops = dplyr::n_distinct(rt$stop_id, na.rm = TRUE),
    arrival_delay_coverage = rate(!is.na(rt$arrival_delay_seconds)),
    departure_delay_coverage = rate(!is.na(rt$departure_delay_seconds)),
    trip_schedule_relationship_counts = relationship_counts(ts$trip_schedule_relationship),
    stop_schedule_relationship_counts = relationship_counts(rt$stop_schedule_relationship),
    replacement_rows = sum(replacement), replacement_missing_schedule_rows = sum(integrated$replacement_missing_scheduled_time),
    static_trip_match_rate = rate(integrated$static_trip_match),
    static_trip_summary_match_rate = rate(!is.na(summary_trip_lookup$index)),
    ambiguous_trip_summary_rows = sum(summary_trip_lookup$ambiguous),
    static_stop_match_rate = rate(integrated$static_stop_match),
    static_trip_stop_match_rate = rate(integrated$static_trip_stop_match),
    unmatched_rows = sum(unmatched),
    unmatched_trip_schedule_relationship_counts = relationship_counts(rt$trip_schedule_relationship[unmatched]),
    unmatched_static_trip_rows = sum(!integrated$static_trip_match),
    unmatched_static_stop_rows = sum(!integrated$static_stop_match),
    rows_before_integration = nrow(rt), rows_after_integration = nrow(integrated),
    duplicate_trip_key_rows = unname(dup["trip_rows"]), duplicate_stop_key_rows = unname(dup["stop_rows"]),
    duplicate_route_key_rows = unname(dup["route_rows"]), duplicate_trip_stop_key_rows = unname(dup["trip_stop_rows"]),
    duplicate_trip_sequence_key_rows = unname(dup["trip_sequence_rows"]),
    ambiguous_trip_stop_rows = sum(integrated$static_trip_stop_ambiguous),
    duplicate_realtime_entity_ids = sum(duplicated(ts$entity_id)),
    static_parsing_problems = static$parsing_problem_count,
    observed_realtime_route_ids = observed_identifiers(rt$route_id),
    observed_route_ids = observed_identifiers(integrated$route_id),
    observed_route_short_names = observed_identifiers(integrated$route_short_name),
    processed_route_ids = observed_identifiers(processed$route_id),
    processed_route_short_names = observed_identifiers(processed$route_short_name),
    processed_rows = nrow(processed), processed_columns = ncol(processed))
}
