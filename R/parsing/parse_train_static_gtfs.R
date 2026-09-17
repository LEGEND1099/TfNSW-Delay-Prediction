library(readr)
library(dplyr)


# ------------------------------------------------------------
# 1. Locate the latest extracted Sydney Trains static GTFS
# ------------------------------------------------------------

static_root <- file.path(
  "data",
  "raw",
  "train",
  "static_gtfs"
)

if (!dir.exists(static_root)) {
  stop(
    "Static GTFS directory was not found. Download the static GTFS first."
  )
}

candidate_dirs <- list.dirs(
  static_root,
  recursive = FALSE,
  full.names = TRUE
)

candidate_dirs <- candidate_dirs[
  grepl(
    "sydneytrains_static_gtfs_[0-9]{8}$",
    candidate_dirs
  )
]

if (length(candidate_dirs) == 0) {
  stop(
    "No extracted Sydney Trains GTFS directory was found."
  )
}

gtfs_dir <- candidate_dirs[
  which.max(
    file.info(candidate_dirs)$mtime
  )
]

cat(
  "Using GTFS directory:",
  gtfs_dir,
  "\n"
)


# ------------------------------------------------------------
# 2. Check that required GTFS files exist
# ------------------------------------------------------------

required_files <- c(
  "routes.txt",
  "trips.txt",
  "stop_times.txt",
  "stops.txt"
)

missing_files <- required_files[
  !file.exists(
    file.path(
      gtfs_dir,
      required_files
    )
  )
]

if (length(missing_files) > 0) {
  stop(
    paste(
      "Missing required GTFS file(s):",
      paste(
        missing_files,
        collapse = ", "
      )
    )
  )
}


# ------------------------------------------------------------
# 3. Read routes.txt
#
# GTFS IDs are identifiers, not numeric measurements.
# Therefore route_id is deliberately stored as character.
# ------------------------------------------------------------

routes <- read_csv(
  file.path(
    gtfs_dir,
    "routes.txt"
  ),

  col_types = cols(
    route_id = col_character(),
    agency_id = col_character(),
    route_short_name = col_character(),
    route_long_name = col_character(),
    route_desc = col_character(),
    route_type = col_integer(),
    route_url = col_character(),
    route_color = col_character(),
    route_text_color = col_character(),

    .default = col_guess()
  ),

  show_col_types = FALSE
)


# ------------------------------------------------------------
# 4. Read trips.txt
#
# Important identifiers are explicitly read as character so
# they remain compatible with GTFS-Realtime identifiers.
# ------------------------------------------------------------

trips <- read_csv(
  file.path(
    gtfs_dir,
    "trips.txt"
  ),

  col_types = cols(
    route_id = col_character(),
    service_id = col_character(),
    trip_id = col_character(),
    trip_headsign = col_character(),
    trip_short_name = col_character(),
    direction_id = col_integer(),
    block_id = col_character(),
    shape_id = col_character(),

    .default = col_guess()
  ),

  show_col_types = FALSE
)


# ------------------------------------------------------------
# 5. Read stop_times.txt
#
# GTFS arrival/departure times remain character strings.
#
# This is intentional because GTFS can contain times such as:
# 24:15:00
# 25:03:00
#
# which are valid GTFS service times but not normal clock
# times.
# ------------------------------------------------------------

stop_times <- read_csv(
  file.path(
    gtfs_dir,
    "stop_times.txt"
  ),

  col_types = cols(
    trip_id = col_character(),
    arrival_time = col_character(),
    departure_time = col_character(),
    stop_id = col_character(),
    stop_sequence = col_integer(),
    stop_headsign = col_character(),
    pickup_type = col_integer(),
    drop_off_type = col_integer(),
    shape_dist_traveled = col_double(),
    timepoint = col_integer(),

    .default = col_guess()
  ),

  show_col_types = FALSE
)


# ------------------------------------------------------------
# 6. Read stops.txt
# ------------------------------------------------------------

stops <- read_csv(
  file.path(
    gtfs_dir,
    "stops.txt"
  ),

  col_types = cols(
    stop_id = col_character(),
    stop_code = col_character(),
    stop_name = col_character(),
    stop_desc = col_character(),
    stop_lat = col_double(),
    stop_lon = col_double(),
    zone_id = col_character(),
    stop_url = col_character(),
    location_type = col_integer(),
    parent_station = col_character(),
    platform_code = col_character(),

    .default = col_guess()
  ),

  show_col_types = FALSE
)


# ------------------------------------------------------------
# 7. Check for parsing problems
# ------------------------------------------------------------

route_problems <- problems(routes)
trip_problems <- problems(trips)
stop_time_problems <- problems(stop_times)
stop_problems <- problems(stops)

cat(
  "\nParsing problems:\n"
)

cat(
  "  routes:",
  nrow(route_problems),
  "\n"
)

cat(
  "  trips:",
  nrow(trip_problems),
  "\n"
)

cat(
  "  stop_times:",
  nrow(stop_time_problems),
  "\n"
)

cat(
  "  stops:",
  nrow(stop_problems),
  "\n"
)


# ------------------------------------------------------------
# 8. Stop if parsing problems remain
#
# We do not silently continue with malformed static GTFS.
# ------------------------------------------------------------

total_parsing_problems <-
  nrow(route_problems) +
  nrow(trip_problems) +
  nrow(stop_time_problems) +
  nrow(stop_problems)

if (total_parsing_problems > 0) {

  warning(
    paste(
      total_parsing_problems,
      "GTFS parsing problem(s) remain.",
      "Inspect the relevant problems() object before modelling."
    )
  )
}


# ------------------------------------------------------------
# 9. Basic dataset summary
# ------------------------------------------------------------

cat(
  "\nStatic GTFS summary:\n"
)

cat(
  "  Routes:",
  nrow(routes),
  "\n"
)

cat(
  "  Trips:",
  nrow(trips),
  "\n"
)

cat(
  "  Stop times:",
  nrow(stop_times),
  "\n"
)

cat(
  "  Stops:",
  nrow(stops),
  "\n"
)


# ------------------------------------------------------------
# 10. Key-type validation
# ------------------------------------------------------------

cat(
  "\nGTFS identifier types:\n"
)

cat(
  "  routes$route_id:",
  class(routes$route_id)[1],
  "\n"
)

cat(
  "  trips$trip_id:",
  class(trips$trip_id)[1],
  "\n"
)

cat(
  "  trips$route_id:",
  class(trips$route_id)[1],
  "\n"
)

cat(
  "  stop_times$trip_id:",
  class(stop_times$trip_id)[1],
  "\n"
)

cat(
  "  stop_times$stop_id:",
  class(stop_times$stop_id)[1],
  "\n"
)

cat(
  "  stops$stop_id:",
  class(stops$stop_id)[1],
  "\n"
)