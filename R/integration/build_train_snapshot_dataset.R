library(dplyr)


# ------------------------------------------------------------
# 1. Validate prerequisite objects
# ------------------------------------------------------------

required_objects <- c(
  "trip_updates_df",
  "trips",
  "stop_times",
  "stops",
  "routes",
  "snapshot_time_utc",
  "feed_time_utc"
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
      paste(missing_objects, collapse = ", ")
    )
  )
}


# ------------------------------------------------------------
# 2. Prepare static scheduled stop information
# ------------------------------------------------------------

scheduled_stops <- stop_times |>
  select(
    trip_id,
    stop_id,
    stop_sequence,
    arrival_time,
    departure_time
  ) |>
  mutate(
    static_trip_stop_match = TRUE
  )


# ------------------------------------------------------------
# 3. Prepare trip information
# ------------------------------------------------------------

trip_info <- trips |>
  select(
    any_of(
      c(
        "trip_id",
        "route_id",
        "service_id",
        "trip_headsign",
        "direction_id",
        "shape_id"
      )
    )
  ) |>
  rename(
    scheduled_route_id = route_id
  )


# ------------------------------------------------------------
# 4. Prepare stop / station information
# ------------------------------------------------------------

stop_info <- stops |>
  select(
    any_of(
      c(
        "stop_id",
        "stop_name",
        "stop_lat",
        "stop_lon",
        "location_type",
        "parent_station"
      )
    )
  )


# ------------------------------------------------------------
# 5. Prepare route information
# ------------------------------------------------------------

route_info <- routes |>
  select(
    any_of(
      c(
        "route_id",
        "route_short_name",
        "route_long_name",
        "route_desc",
        "route_type"
      )
    )
  ) |>
  rename(
    scheduled_route_id = route_id
  )


# ------------------------------------------------------------
# 6. Integrate realtime data with static GTFS
# ------------------------------------------------------------

train_snapshot_df <- trip_updates_df |>

  # Keep realtime route separately from scheduled route.
  rename(
    realtime_route_id = route_id
  ) |>

  # The realtime feed did not provide genuine stop_sequence
  # values, so remove that placeholder column before joining
  # the official sequence from static GTFS.
  select(
    -stop_sequence
  ) |>

  # ----------------------------------------------------------
  # Exact trip + stop match
  #
  # Normal scheduled services should usually match here.
  #
  # Replacement services may contain stop combinations that
  # do not exist in the static timetable. Because this is a
  # LEFT JOIN, those realtime rows are preserved.
  # ----------------------------------------------------------

  left_join(
    scheduled_stops,
    by = c(
      "trip_id",
      "stop_id"
    )
  ) |>

  # ----------------------------------------------------------
  # Trip-level static information
  #
  # Join only by trip_id so that replacement services can
  # still inherit the scheduled trip metadata even if their
  # realtime route_id differs from the scheduled route_id.
  # ----------------------------------------------------------

  left_join(
    trip_info,
    by = "trip_id"
  ) |>

  # ----------------------------------------------------------
  # Stop information
  #
  # This is joined independently by stop_id. Therefore a
  # replacement stop can still receive its readable station
  # name and coordinates even when trip + stop does not match
  # the static stop_times table.
  # ----------------------------------------------------------

  left_join(
    stop_info,
    by = "stop_id"
  ) |>

  # ----------------------------------------------------------
  # Route information
  # ----------------------------------------------------------

  left_join(
    route_info,
    by = "scheduled_route_id"
  ) |>

  # ----------------------------------------------------------
  # Derived / human-readable fields
  # ----------------------------------------------------------

  mutate(

    # When we collected the entire realtime snapshot.
    snapshot_time_utc =
      .env$snapshot_time_utc,

    # Timestamp supplied in the GTFS-Realtime feed header.
    feed_time_utc =
      .env$feed_time_utc,


    # --------------------------------------------------------
    # Static matching status
    # --------------------------------------------------------

    static_trip_stop_match =
      coalesce(
        static_trip_stop_match,
        FALSE
      ),


    # --------------------------------------------------------
    # Delay expressed in minutes
    # --------------------------------------------------------

    arrival_delay_minutes =
      arrival_delay_seconds / 60,

    departure_delay_minutes =
      departure_delay_seconds / 60,


    # --------------------------------------------------------
    # Age of each TripUpdate when we captured the snapshot
    # --------------------------------------------------------

    trip_update_age_seconds =
      as.numeric(
        difftime(
          snapshot_time_utc,
          trip_update_time_utc,
          units = "secs"
        )
      ),


    # --------------------------------------------------------
    # Human-readable TripDescriptor schedule relationship
    # --------------------------------------------------------

    trip_schedule_relationship_label =
      case_when(

        is.na(
          trip_schedule_relationship
        ) ~ NA_character_,

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
      ),


    # --------------------------------------------------------
    # Human-readable StopTimeUpdate schedule relationship
    # --------------------------------------------------------

    stop_schedule_relationship_label =
      case_when(

        is.na(
          stop_schedule_relationship
        ) ~ NA_character_,

        stop_schedule_relationship == 0 ~
          "SCHEDULED",

        stop_schedule_relationship == 1 ~
          "SKIPPED",

        stop_schedule_relationship == 2 ~
          "NO_DATA",

        stop_schedule_relationship == 3 ~
          "UNSCHEDULED",

        TRUE ~
          "UNKNOWN"
      ),


    # --------------------------------------------------------
    # Easy flag for replacement/substitute services
    # --------------------------------------------------------

    is_replacement_trip =
      trip_schedule_relationship == 5
  )


# ------------------------------------------------------------
# 7. Validation
# ------------------------------------------------------------

cat(
  "Original realtime rows:",
  nrow(trip_updates_df),
  "\n"
)

cat(
  "Integrated rows:",
  nrow(train_snapshot_df),
  "\n"
)

cat(
  "Integrated columns:",
  ncol(train_snapshot_df),
  "\n"
)

cat(
  "Rows with station name:",
  sum(
    !is.na(
      train_snapshot_df$stop_name
    )
  ),
  "of",
  nrow(train_snapshot_df),
  "\n"
)

cat(
  "Rows with exact static trip-stop match:",
  sum(
    train_snapshot_df$
      static_trip_stop_match
  ),
  "of",
  nrow(train_snapshot_df),
  "\n"
)

cat(
  "Rows without exact static trip-stop match:",
  sum(
    !train_snapshot_df$
      static_trip_stop_match
  ),
  "\n"
)

cat(
  "Rows with true static stop sequence:",
  sum(
    !is.na(
      train_snapshot_df$stop_sequence
    )
  ),
  "of",
  nrow(train_snapshot_df),
  "\n"
)

cat(
  "Replacement stop-level rows retained:",
  sum(
    train_snapshot_df$
      is_replacement_trip,
    na.rm = TRUE
  ),
  "\n"
)


# ------------------------------------------------------------
# 8. Safety check against accidental row duplication
# ------------------------------------------------------------

if (
  nrow(train_snapshot_df) !=
    nrow(trip_updates_df)
) {

  warning(
    paste(
      "Integrated row count differs from realtime row count.",
      "Check joins for duplicate keys."
    )
  )
}