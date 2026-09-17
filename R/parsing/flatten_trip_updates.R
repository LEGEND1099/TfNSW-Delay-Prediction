library(dplyr)
library(purrr)
library(tibble)


# ------------------------------------------------------------
# 1. Validate prerequisite object
# ------------------------------------------------------------

if (!exists("feed")) {
  stop(
    paste(
      "Decoded object 'feed' was not found.",
      "Run decode_gtfs_realtime.R first."
    )
  )
}


# ------------------------------------------------------------
# 2. Helper: safely extract a TripUpdate timestamp
# ------------------------------------------------------------

get_trip_update_time <- function(trip_update) {

  if (trip_update$has("timestamp")) {

    as.POSIXct(
      as.numeric(trip_update$timestamp),
      origin = "1970-01-01",
      tz = "UTC"
    )

  } else {

    as.POSIXct(
      NA,
      tz = "UTC"
    )
  }
}


# ------------------------------------------------------------
# 3. Build one-row-per-trip summary
# ------------------------------------------------------------

extract_trip_summary <- function(entity) {

  if (!entity$has("trip_update")) {
    return(NULL)
  }

  trip_update <- entity$trip_update
  trip <- trip_update$trip

  trip_id <- if (
    trip$has("trip_id")
  ) {
    trip$trip_id
  } else {
    NA_character_
  }

  route_id <- if (
    trip$has("route_id")
  ) {
    trip$route_id
  } else {
    NA_character_
  }

  trip_schedule_relationship <- if (
    trip$has("schedule_relationship")
  ) {
    trip$schedule_relationship
  } else {
    NA_integer_
  }

  trip_update_time_utc <-
    get_trip_update_time(trip_update)

  trip_level_delay_seconds <- if (
    trip_update$has("delay")
  ) {
    trip_update$delay
  } else {
    NA_integer_
  }

  number_of_stop_updates <-
    trip_update$size("stop_time_update")

  tibble(
    entity_id = entity$id,
    trip_id = trip_id,
    route_id = route_id,
    trip_update_time_utc =
      trip_update_time_utc,
    trip_schedule_relationship =
      trip_schedule_relationship,
    trip_level_delay_seconds =
      trip_level_delay_seconds,
    number_of_stop_updates =
      number_of_stop_updates
  )
}


# ------------------------------------------------------------
# 4. Build one-row-per-stop table from one FeedEntity
# ------------------------------------------------------------

extract_trip_entity <- function(entity) {

  if (!entity$has("trip_update")) {
    return(NULL)
  }

  trip_update <- entity$trip_update
  trip <- trip_update$trip

  trip_id <- if (
    trip$has("trip_id")
  ) {
    trip$trip_id
  } else {
    NA_character_
  }

  route_id <- if (
    trip$has("route_id")
  ) {
    trip$route_id
  } else {
    NA_character_
  }

  trip_schedule_relationship <- if (
    trip$has("schedule_relationship")
  ) {
    trip$schedule_relationship
  } else {
    NA_integer_
  }

  trip_update_time_utc <-
    get_trip_update_time(trip_update)

  n_stops <-
    trip_update$size("stop_time_update")

  # Keep zero-stop trips in trip_summary_df,
  # but they cannot contribute stop-level rows here.
  if (n_stops == 0) {
    return(NULL)
  }

  map_dfr(
    seq_along(
      trip_update$stop_time_update
    ),
    function(i) {

      stop_update <-
        trip_update$stop_time_update[[i]]


      # --------------------------------------------------------
      # Stop identifier
      # --------------------------------------------------------

      stop_id <- if (
        stop_update$has("stop_id")
      ) {
        stop_update$stop_id
      } else {
        NA_character_
      }


      # --------------------------------------------------------
      # Official stop_sequence if supplied
      # --------------------------------------------------------

      stop_sequence <- if (
        stop_update$has("stop_sequence")
      ) {
        stop_update$stop_sequence
      } else {
        NA_integer_
      }


      # --------------------------------------------------------
      # Arrival delay
      # --------------------------------------------------------

      arrival_delay <- if (
        stop_update$has("arrival") &&
        stop_update$arrival$has("delay")
      ) {
        stop_update$arrival$delay
      } else {
        NA_integer_
      }


      # --------------------------------------------------------
      # Departure delay
      # --------------------------------------------------------

      departure_delay <- if (
        stop_update$has("departure") &&
        stop_update$departure$has("delay")
      ) {
        stop_update$departure$delay
      } else {
        NA_integer_
      }


      # --------------------------------------------------------
      # Stop schedule relationship
      # --------------------------------------------------------

      stop_schedule_relationship <- if (
        stop_update$has(
          "schedule_relationship"
        )
      ) {
        stop_update$schedule_relationship
      } else {
        NA_integer_
      }


      # --------------------------------------------------------
      # Output one stop-level row
      # --------------------------------------------------------

      tibble(
        entity_id = entity$id,

        trip_id = trip_id,

        route_id = route_id,

        trip_update_time_utc =
          trip_update_time_utc,

        # Position of this StopTimeUpdate in
        # the realtime message.
        #
        # This is NOT the official GTFS
        # stop_sequence.
        update_order = i,

        stop_sequence = stop_sequence,

        stop_id = stop_id,

        arrival_delay_seconds =
          arrival_delay,

        departure_delay_seconds =
          departure_delay,

        trip_schedule_relationship =
          trip_schedule_relationship,

        stop_schedule_relationship =
          stop_schedule_relationship
      )
    }
  )
}


# ------------------------------------------------------------
# 5. Create trip-level summary
# ------------------------------------------------------------

trip_summary_df <- map_dfr(
  feed$entity,
  extract_trip_summary
)


# ------------------------------------------------------------
# 6. Create stop-level realtime table
# ------------------------------------------------------------

trip_updates_df <- map_dfr(
  feed$entity,
  extract_trip_entity
)


# ------------------------------------------------------------
# 7. Validation and summary
# ------------------------------------------------------------

cat(
  "TripUpdates found:",
  nrow(trip_summary_df),
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
  "Stop-level rows created:",
  nrow(trip_updates_df),
  "\n"
)

cat(
  "Stop-level columns created:",
  ncol(trip_updates_df),
  "\n"
)

cat(
  "Replacement stop-level rows:",
  sum(
    trip_updates_df$
      trip_schedule_relationship == 5,
    na.rm = TRUE
  ),
  "\n"
)


# ------------------------------------------------------------
# 8. Preview
# ------------------------------------------------------------

print(
  head(
    trip_updates_df,
    10
  )
)