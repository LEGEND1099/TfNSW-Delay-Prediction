library(dplyr)
library(readr)


# ------------------------------------------------------------
# 1. Validate prerequisite objects
# ------------------------------------------------------------

required_objects <- c(
  "train_snapshot_df",
  "snapshot_time_utc"
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
      "\nRun the integration pipeline first."
    )
  )
}


# ------------------------------------------------------------
# 2. Define Sydney Trains metropolitan passenger scope
#
# Sydney Metro is a separate transport mode.
# Here we are keeping Sydney Trains T1-T9 services only.
# ------------------------------------------------------------

sydney_train_lines <- paste0(
  "T",
  1:9
)


# ------------------------------------------------------------
# 3. Create scope-audit version of full integrated dataset
#
# We retain the full feed separately so that excluded services
# are still available for diagnostics and EDA.
# ------------------------------------------------------------

train_scope_audit_df <- train_snapshot_df |>
  mutate(

    # Does this row belong to one of the Sydney Trains
    # metropolitan T-lines?
    in_sydney_trains_scope =
      route_short_name %in%
      sydney_train_lines,


    # Identify obvious non-passenger empty-train movements.
    is_empty_train =
      case_when(

        is.na(trip_headsign) ~ FALSE,

        grepl(
          "empty train",
          trip_headsign,
          ignore.case = TRUE
        ) ~ TRUE,

        TRUE ~ FALSE
      ),


    # Final scope decision
    keep_for_project =
      in_sydney_trains_scope &
      !is_empty_train,


    # Human-readable reason for exclusion
    scope_status =
      case_when(

        keep_for_project ~
          "KEEP",

        is_empty_train ~
          "EXCLUDE_EMPTY_TRAIN",

        !in_sydney_trains_scope ~
          "EXCLUDE_OUTSIDE_T1_T9",

        TRUE ~
          "EXCLUDE_OTHER"
      )
  )


# ------------------------------------------------------------
# 4. Create final Sydney Trains metropolitan snapshot
#
# Important:
# REPLACEMENT services are NOT removed.
#
# If they belong to a T1-T9 trip, they remain in the
# processed dataset even when their trip + stop combination
# does not exist in static stop_times.txt.
# ------------------------------------------------------------

sydney_trains_snapshot_df <- train_scope_audit_df |>
  filter(
    keep_for_project
  )


# ------------------------------------------------------------
# 5. Add convenient Sydney-local display timestamps
#
# UTC POSIXct fields remain untouched for analysis.
#
# These additional character fields are simply easier to read
# when manually inspecting the data.
# ------------------------------------------------------------

sydney_trains_snapshot_df <-
  sydney_trains_snapshot_df |>
  mutate(

    snapshot_time_sydney =
      format(
        snapshot_time_utc,
        "%Y-%m-%d %H:%M:%S",
        tz = "Australia/Sydney"
      ),

    feed_time_sydney =
      if_else(
        is.na(feed_time_utc),
        NA_character_,
        format(
          feed_time_utc,
          "%Y-%m-%d %H:%M:%S",
          tz = "Australia/Sydney"
        )
      ),

    trip_update_time_sydney =
      if_else(
        is.na(trip_update_time_utc),
        NA_character_,
        format(
          trip_update_time_utc,
          "%Y-%m-%d %H:%M:%S",
          tz = "Australia/Sydney"
        )
      )
  )


# ------------------------------------------------------------
# 6. Validation: overall scope
# ------------------------------------------------------------

cat(
  "\n=================================\n",
  "SYDNEY TRAINS SCOPE SUMMARY\n",
  "=================================\n",
  sep = ""
)

cat(
  "Full integrated rows:",
  nrow(train_snapshot_df),
  "\n"
)

cat(
  "Rows retained for T1-T9:",
  nrow(sydney_trains_snapshot_df),
  "\n"
)

cat(
  "Rows excluded:",
  nrow(train_snapshot_df) -
    nrow(sydney_trains_snapshot_df),
  "\n"
)


# ------------------------------------------------------------
# 7. Show exclusion reasons
# ------------------------------------------------------------

scope_summary <-
  train_scope_audit_df |>
  count(
    scope_status,
    name = "rows"
  ) |>
  arrange(
    desc(rows)
  )

cat(
  "\nScope decisions:\n"
)

print(
  scope_summary,
  n = Inf
)


# ------------------------------------------------------------
# 8. Check retained route lines
# ------------------------------------------------------------

route_summary <-
  sydney_trains_snapshot_df |>
  count(
    route_short_name,
    name = "rows"
  ) |>
  arrange(
    route_short_name
  )

cat(
  "\nRetained Sydney Trains lines:\n"
)

print(
  route_summary,
  n = Inf
)


# ------------------------------------------------------------
# 9. Validate replacement services
# ------------------------------------------------------------

replacement_rows_all <-
  sum(
    train_snapshot_df$is_replacement_trip,
    na.rm = TRUE
  )

replacement_rows_retained <-
  sum(
    sydney_trains_snapshot_df$
      is_replacement_trip,
    na.rm = TRUE
  )

cat(
  "\nReplacement rows in full feed:",
  replacement_rows_all,
  "\n"
)

cat(
  "Replacement rows retained in T1-T9 dataset:",
  replacement_rows_retained,
  "\n"
)


# ------------------------------------------------------------
# 10. Validate static-trip-stop matching
# ------------------------------------------------------------

cat(
  "\nExact static trip-stop matches:",
  sum(
    sydney_trains_snapshot_df$
      static_trip_stop_match,
    na.rm = TRUE
  ),
  "of",
  nrow(sydney_trains_snapshot_df),
  "\n"
)

cat(
  "Rows retained without exact static trip-stop match:",
  sum(
    !sydney_trains_snapshot_df$
      static_trip_stop_match,
    na.rm = TRUE
  ),
  "\n"
)


# ------------------------------------------------------------
# 11. Validate delays
# ------------------------------------------------------------

cat(
  "\nRows with arrival delay:",
  sum(
    !is.na(
      sydney_trains_snapshot_df$
        arrival_delay_seconds
    )
  ),
  "of",
  nrow(sydney_trains_snapshot_df),
  "\n"
)

cat(
  "Rows with departure delay:",
  sum(
    !is.na(
      sydney_trains_snapshot_df$
        departure_delay_seconds
    )
  ),
  "of",
  nrow(sydney_trains_snapshot_df),
  "\n"
)


# ------------------------------------------------------------
# 12. Create timestamp tag for output filenames
# ------------------------------------------------------------

snapshot_tag <- format(
  snapshot_time_utc,
  format = "%Y%m%dT%H%M%SZ",
  tz = "UTC"
)


# ------------------------------------------------------------
# 13. Save complete integrated feed to interim
#
# This includes:
# - T1-T9
# - Intercity services
# - empty train movements
# - replacement services
#
# Nothing is discarded from the analytical workflow.
# ------------------------------------------------------------

interim_dir <- file.path(
  "data",
  "interim",
  "by_mode",
  "train"
)

dir.create(
  interim_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

interim_file <- file.path(
  interim_dir,
  paste0(
    "train_integrated_all_",
    snapshot_tag,
    ".csv"
  )
)

write_csv(
  train_scope_audit_df,
  interim_file,
  na = ""
)


# ------------------------------------------------------------
# 14. Save project-scope Sydney Trains dataset
# ------------------------------------------------------------

processed_dir <- file.path(
  "data",
  "processed",
  "by_mode",
  "train"
)

dir.create(
  processed_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

processed_file <- file.path(
  processed_dir,
  paste0(
    "sydney_trains_snapshot_",
    snapshot_tag,
    ".csv"
  )
)

write_csv(
  sydney_trains_snapshot_df,
  processed_file,
  na = ""
)


# ------------------------------------------------------------
# 15. Verify saved files
# ------------------------------------------------------------

if (!file.exists(interim_file)) {
  stop(
    "Full integrated interim dataset was not saved."
  )
}

if (!file.exists(processed_file)) {
  stop(
    "Processed Sydney Trains dataset was not saved."
  )
}


# ------------------------------------------------------------
# 16. Final output summary
# ------------------------------------------------------------

cat(
  "\n=================================\n",
  "FILES SAVED\n",
  "=================================\n",
  sep = ""
)

cat(
  "Full integrated feed:\n",
  interim_file,
  "\n\n"
)

cat(
  "Sydney Trains T1-T9 dataset:\n",
  processed_file,
  "\n"
)

cat(
  "\nProcessed dataset dimensions:",
  nrow(sydney_trains_snapshot_df),
  "rows x",
  ncol(sydney_trains_snapshot_df),
  "columns\n"
)

cat(
  "\nSydney Trains processing completed successfully.\n"
)