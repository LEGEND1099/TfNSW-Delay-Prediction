library(dplyr)


# ------------------------------------------------------------
# 1. Validate prerequisite object
# ------------------------------------------------------------

if (!exists("trip_updates_df")) {
  stop(
    paste(
      "Object 'trip_updates_df' was not found.",
      "Run decode_gtfs_realtime.R and",
      "flatten_trip_updates.R first."
    )
  )
}


# ------------------------------------------------------------
# 2. Create consecutive-stop delay data
#
# update_order is the order in which StopTimeUpdates appeared
# in the realtime message.
#
# We use it only for exploratory analysis here.
# ------------------------------------------------------------

delay_lag_df <- trip_updates_df |>

  arrange(
    trip_id,
    update_order
  ) |>

  group_by(
    trip_id
  ) |>

  mutate(

    previous_arrival_delay_seconds =
      lag(arrival_delay_seconds),

    previous_departure_delay_seconds =
      lag(departure_delay_seconds),

    arrival_delay_change_seconds =
      arrival_delay_seconds -
      previous_arrival_delay_seconds,

    departure_delay_change_seconds =
      departure_delay_seconds -
      previous_departure_delay_seconds

  ) |>

  ungroup()


# ------------------------------------------------------------
# 3. Arrival-delay persistence
# ------------------------------------------------------------

arrival_complete <- delay_lag_df |>
  filter(
    !is.na(previous_arrival_delay_seconds),
    !is.na(arrival_delay_seconds)
  )


if (nrow(arrival_complete) >= 2) {

  arrival_previous_next_correlation <- cor(
    arrival_complete$
      previous_arrival_delay_seconds,

    arrival_complete$
      arrival_delay_seconds
  )

} else {

  arrival_previous_next_correlation <- NA_real_
}


cat(
  "\n=================================\n",
  "ARRIVAL DELAY PERSISTENCE\n",
  "=================================\n",
  sep = ""
)

cat(
  "Complete consecutive-stop pairs:",
  nrow(arrival_complete),
  "\n"
)

cat(
  "Correlation between previous and current",
  " arrival delay:",
  round(
    arrival_previous_next_correlation,
    3
  ),
  "\n"
)


# ------------------------------------------------------------
# 4. How often is the arrival delay exactly unchanged?
# ------------------------------------------------------------

arrival_same_delay_count <- sum(
  arrival_complete$
    arrival_delay_change_seconds == 0,
  na.rm = TRUE
)

arrival_same_delay_percent <- if (
  nrow(arrival_complete) > 0
) {

  arrival_same_delay_count /
    nrow(arrival_complete) *
    100

} else {

  NA_real_
}


cat(
  "Pairs with exactly the same arrival delay:",
  arrival_same_delay_count,
  "of",
  nrow(arrival_complete),
  "\n"
)

cat(
  "Percentage unchanged:",
  round(
    arrival_same_delay_percent,
    2
  ),
  "%\n"
)


# ------------------------------------------------------------
# 5. Distribution of change in arrival delay
# ------------------------------------------------------------

cat(
  "\nChange in arrival delay between consecutive",
  " realtime stop updates (seconds):\n"
)

print(
  summary(
    arrival_complete$
      arrival_delay_change_seconds
  )
)


# ------------------------------------------------------------
# 6. Departure-delay persistence
# ------------------------------------------------------------

departure_complete <- delay_lag_df |>
  filter(
    !is.na(previous_departure_delay_seconds),
    !is.na(departure_delay_seconds)
  )


if (nrow(departure_complete) >= 2) {

  departure_previous_next_correlation <- cor(
    departure_complete$
      previous_departure_delay_seconds,

    departure_complete$
      departure_delay_seconds
  )

} else {

  departure_previous_next_correlation <- NA_real_
}


cat(
  "\n=================================\n",
  "DEPARTURE DELAY PERSISTENCE\n",
  "=================================\n",
  sep = ""
)

cat(
  "Complete consecutive-stop pairs:",
  nrow(departure_complete),
  "\n"
)

cat(
  "Correlation between previous and current",
  " departure delay:",
  round(
    departure_previous_next_correlation,
    3
  ),
  "\n"
)


# ------------------------------------------------------------
# 7. How often is departure delay exactly unchanged?
# ------------------------------------------------------------

departure_same_delay_count <- sum(
  departure_complete$
    departure_delay_change_seconds == 0,
  na.rm = TRUE
)

departure_same_delay_percent <- if (
  nrow(departure_complete) > 0
) {

  departure_same_delay_count /
    nrow(departure_complete) *
    100

} else {

  NA_real_
}


cat(
  "Pairs with exactly the same departure delay:",
  departure_same_delay_count,
  "of",
  nrow(departure_complete),
  "\n"
)

cat(
  "Percentage unchanged:",
  round(
    departure_same_delay_percent,
    2
  ),
  "%\n"
)


# ------------------------------------------------------------
# 8. Distribution of change in departure delay
# ------------------------------------------------------------

cat(
  "\nChange in departure delay between consecutive",
  " realtime stop updates (seconds):\n"
)

print(
  summary(
    departure_complete$
      departure_delay_change_seconds
  )
)


# ------------------------------------------------------------
# 9. Trip-level persistence summary
#
# This helps show whether the very high overall correlation is
# widespread across trips rather than being driven by only a
# small number of services.
# ------------------------------------------------------------

trip_delay_persistence <- delay_lag_df |>

  group_by(
    trip_id
  ) |>

  summarise(

    route_id =
      first(route_id),

    number_of_stop_updates =
      n(),

    usable_arrival_pairs =
      sum(
        !is.na(previous_arrival_delay_seconds) &
        !is.na(arrival_delay_seconds)
      ),

    unchanged_arrival_pairs =
      sum(
        arrival_delay_change_seconds == 0,
        na.rm = TRUE
      ),

    mean_absolute_arrival_change_seconds =
      if (
        any(
          !is.na(arrival_delay_change_seconds)
        )
      ) {
        mean(
          abs(arrival_delay_change_seconds),
          na.rm = TRUE
        )
      } else {
        NA_real_
      },

    .groups = "drop"
  ) |>

  mutate(

    unchanged_arrival_percent =
      if_else(
        usable_arrival_pairs > 0,

        unchanged_arrival_pairs /
          usable_arrival_pairs *
          100,

        NA_real_
      )
  )


# ------------------------------------------------------------
# 10. Diagnostic summary
# ------------------------------------------------------------

cat(
  "\n=================================\n",
  "INTERPRETATION CHECK\n",
  "=================================\n",
  sep = ""
)

cat(
  "Trips represented:",
  n_distinct(
    delay_lag_df$trip_id
  ),
  "\n"
)

cat(
  paste(
    "Important:",
    "this analysis is exploratory only.",
    "A high previous/current delay correlation may partly",
    "reflect GTFS-Realtime propagation of the same delay",
    "estimate across downstream stops.",
    "\n"
  )
)

cat(
  paste(
    "Previous-stop delay should therefore NOT yet be used",
    "as a modelling predictor, and missing previous delay",
    "must NOT be replaced with zero.",
    "\n"
  )
)