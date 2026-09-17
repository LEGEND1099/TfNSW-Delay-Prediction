library(dplyr)


# ------------------------------------------------------------
# 1. Validate prerequisite objects
# ------------------------------------------------------------

required_objects <- c(
  "trip_summary_df",
  "trip_updates_df"
)

missing_objects <- required_objects[
  !vapply(
    required_objects,
    exists,
    logical(1)
  )
]

if (length(missing_objects) > 0) {
  stop(
    paste(
      "Missing prerequisite object(s):",
      paste(missing_objects, collapse = ", "),
      "\nRun decode_gtfs_realtime.R and",
      "flatten_trip_updates.R first."
    )
  )
}


# ------------------------------------------------------------
# 2. Overall TripUpdate summary
# ------------------------------------------------------------

cat(
  "\n==============================\n",
  "GTFS-REALTIME TRIP SUMMARY\n",
  "==============================\n",
  sep = ""
)

cat(
  "Total TripUpdates:",
  nrow(trip_summary_df),
  "\n"
)

cat(
  "Trips with at least one stop update:",
  sum(
    trip_summary_df$number_of_stop_updates > 0
  ),
  "\n"
)

cat(
  "Trips with zero stop updates:",
  sum(
    trip_summary_df$number_of_stop_updates == 0
  ),
  "\n"
)

cat(
  "Percentage with zero stop updates:",
  round(
    mean(
      trip_summary_df$number_of_stop_updates == 0
    ) * 100,
    2
  ),
  "%\n"
)


# ------------------------------------------------------------
# 3. Stop-update counts per trip
# ------------------------------------------------------------

cat(
  "\nStop updates per TripUpdate:\n"
)

stop_count_summary <-
  summary(
    trip_summary_df$number_of_stop_updates
  )

print(
  stop_count_summary
)

cat(
  "Average stop updates per TripUpdate:",
  round(
    mean(
      trip_summary_df$number_of_stop_updates
    ),
    2
  ),
  "\n"
)


# ------------------------------------------------------------
# 4. Stop-level dataset size
# ------------------------------------------------------------

cat(
  "\n==============================\n",
  "STOP-LEVEL SUMMARY\n",
  "==============================\n",
  sep = ""
)

cat(
  "Stop-level rows:",
  nrow(trip_updates_df),
  "\n"
)

cat(
  "Stop-level columns:",
  ncol(trip_updates_df),
  "\n"
)

cat(
  "Unique trips represented:",
  n_distinct(
    trip_updates_df$trip_id
  ),
  "\n"
)

cat(
  "Unique stops represented:",
  n_distinct(
    trip_updates_df$stop_id
  ),
  "\n"
)


# ------------------------------------------------------------
# 5. Arrival-delay coverage
# ------------------------------------------------------------

arrival_present <-
  sum(
    !is.na(
      trip_updates_df$arrival_delay_seconds
    )
  )

arrival_missing <-
  sum(
    is.na(
      trip_updates_df$arrival_delay_seconds
    )
  )

cat(
  "\nArrival delay available:",
  arrival_present,
  "of",
  nrow(trip_updates_df),
  "\n"
)

cat(
  "Arrival delay missing:",
  arrival_missing,
  "\n"
)

cat(
  "Arrival delay coverage:",
  round(
    arrival_present /
      nrow(trip_updates_df) *
      100,
    2
  ),
  "%\n"
)


# ------------------------------------------------------------
# 6. Departure-delay coverage
# ------------------------------------------------------------

departure_present <-
  sum(
    !is.na(
      trip_updates_df$departure_delay_seconds
    )
  )

departure_missing <-
  sum(
    is.na(
      trip_updates_df$departure_delay_seconds
    )
  )

cat(
  "\nDeparture delay available:",
  departure_present,
  "of",
  nrow(trip_updates_df),
  "\n"
)

cat(
  "Departure delay missing:",
  departure_missing,
  "\n"
)

cat(
  "Departure delay coverage:",
  round(
    departure_present /
      nrow(trip_updates_df) *
      100,
    2
  ),
  "%\n"
)


# ------------------------------------------------------------
# 7. Delay distributions
# ------------------------------------------------------------

cat(
  "\nArrival delay summary (seconds):\n"
)

print(
  summary(
    trip_updates_df$arrival_delay_seconds
  )
)

cat(
  "\nDeparture delay summary (seconds):\n"
)

print(
  summary(
    trip_updates_df$departure_delay_seconds
  )
)


# ------------------------------------------------------------
# 8. Trip schedule relationships
# ------------------------------------------------------------

cat(
  "\n==============================\n",
  "TRIP SCHEDULE RELATIONSHIPS\n",
  "==============================\n",
  sep = ""
)

trip_relationship_counts <-
  trip_summary_df |>
  mutate(
    relationship_label =
      case_when(
        is.na(
          trip_schedule_relationship
        ) ~ "NOT_SUPPLIED",

        trip_schedule_relationship == 0 ~
          "SCHEDULED",

        trip_schedule_relationship == 1 ~
          "ADDED",

        trip_schedule_relationship == 2 ~
          "UNSCHEDULED",

        trip_schedule_relationship == 3 ~
          "CANCELED",

        trip_schedule_relationship == 5 ~
          "REPLACEMENT",

        trip_schedule_relationship == 6 ~
          "DUPLICATED",

        trip_schedule_relationship == 7 ~
          "DELETED",

        trip_schedule_relationship == 8 ~
          "NEW",

        TRUE ~
          "UNKNOWN"
      )
  ) |>
  count(
    trip_schedule_relationship,
    relationship_label,
    name = "trip_count"
  ) |>
  arrange(
    trip_schedule_relationship
  )

print(
  trip_relationship_counts,
  n = Inf
)


# ------------------------------------------------------------
# 9. Replacement-service diagnostics
# ------------------------------------------------------------

replacement_trips <-
  trip_summary_df |>
  filter(
    trip_schedule_relationship == 5
  )

replacement_stop_rows <-
  trip_updates_df |>
  filter(
    trip_schedule_relationship == 5
  )

cat(
  "\nReplacement TripUpdates:",
  nrow(replacement_trips),
  "\n"
)

cat(
  "Replacement stop-level rows:",
  nrow(replacement_stop_rows),
  "\n"
)


# ------------------------------------------------------------
# 10. Missing stop_sequence check
# ------------------------------------------------------------

cat(
  "\n==============================\n",
  "STOP SEQUENCE CHECK\n",
  "==============================\n",
  sep = ""
)

cat(
  "Realtime rows with supplied stop_sequence:",
  sum(
    !is.na(
      trip_updates_df$stop_sequence
    )
  ),
  "of",
  nrow(trip_updates_df),
  "\n"
)

cat(
  "Realtime rows without supplied stop_sequence:",
  sum(
    is.na(
      trip_updates_df$stop_sequence
    )
  ),
  "\n"
)

cat(
  "\nNote: update_order records the order in which",
  " StopTimeUpdates appear in the realtime feed.\n",
  "It is not treated as the official GTFS stop_sequence.\n",
  sep = ""
)


# ------------------------------------------------------------
# 11. TripUpdate timestamp coverage
# ------------------------------------------------------------

cat(
  "\n==============================\n",
  "TIMESTAMP COVERAGE\n",
  "==============================\n",
  sep = ""
)

cat(
  "Trips with TripUpdate timestamp:",
  sum(
    !is.na(
      trip_summary_df$trip_update_time_utc
    )
  ),
  "of",
  nrow(trip_summary_df),
  "\n"
)

cat(
  "Trips without TripUpdate timestamp:",
  sum(
    is.na(
      trip_summary_df$trip_update_time_utc
    )
  ),
  "\n"
)


# ------------------------------------------------------------
# 12. Preview zero-stop TripUpdates
# ------------------------------------------------------------

zero_stop_preview <-
  trip_summary_df |>
  filter(
    number_of_stop_updates == 0
  ) |>
  select(
    entity_id,
    trip_id,
    route_id,
    trip_update_time_utc,
    trip_schedule_relationship,
    trip_level_delay_seconds,
    number_of_stop_updates
  ) |>
  head(10)

cat(
  "\n==============================\n",
  "ZERO-STOP TRIP PREVIEW\n",
  "==============================\n",
  sep = ""
)

print(
  zero_stop_preview,
  width = Inf
)


# ------------------------------------------------------------
# 13. Final diagnostic message
# ------------------------------------------------------------

cat(
  "\nRealtime TripUpdate inspection completed.\n"
)