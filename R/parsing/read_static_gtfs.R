# Shared, header-aware GTFS CSV reading. Optional columns get a parser only
# when they exist, so absent timepoint/platform_code columns do not warn.

read_gtfs_table <- function(path) {
  if (!file.exists(path)) stop("GTFS file does not exist: ", path)
  if (is.na(file.info(path)$size) || file.info(path)$size == 0) {
    stop("GTFS file is empty (no header): ", path)
  }
  header <- readr::read_csv(
    path, n_max = 0, col_types = readr::cols(.default = readr::col_character()),
    name_repair = "check_unique", show_col_types = FALSE,
    progress = FALSE, lazy = FALSE
  )
  column_names <- names(header)
  if (!length(column_names)) stop("GTFS file has no columns: ", path)

  # direction_id is an enumeration, unlike GTFS identifier columns.
  integer_columns <- c(
    "direction_id", "route_type", "route_sort_order", "stop_sequence",
    "shape_pt_sequence", "pickup_type", "drop_off_type", "continuous_pickup",
    "continuous_drop_off", "timepoint", "location_type", "wheelchair_boarding",
    "wheelchair_accessible", "bikes_allowed", "headway_secs", "exact_times",
    "exception_type", "monday", "tuesday", "wednesday", "thursday", "friday",
    "saturday", "sunday", "transfer_type", "min_transfer_time", "payment_method",
    "transfers", "transfer_duration"
  )
  double_columns <- c(
    "stop_lat", "stop_lon", "shape_pt_lat", "shape_pt_lon",
    "shape_dist_traveled", "price", "length", "traversal_time", "level_index"
  )
  character_columns <- c(
    "parent_station", "stop_code", "platform_code", "start_date", "end_date",
    "date", "arrival_time", "departure_time", "start_time", "end_time"
  )
  types <- lapply(column_names, function(column) {
    if (column %in% integer_columns) return(readr::col_integer())
    if (column %in% double_columns) return(readr::col_double())
    if (column %in% character_columns ||
        grepl("(_id|_name|_headsign|_desc|_url|_color|_timezone|_time|_date)$", column)) {
      return(readr::col_character())
    }
    readr::col_guess()
  })
  names(types) <- column_names
  specification <- do.call(readr::cols, c(types, list(.default = readr::col_guess())))

  # Eager reading makes problems() complete before this function returns.
  # readr's genuine parsing warnings remain visible to callers.
  readr::read_csv(
    path, col_types = specification, name_repair = "check_unique",
    show_col_types = FALSE, progress = FALSE, lazy = FALSE
  )
}

read_static_gtfs <- function(gtfs_dir) {
  required <- c("routes", "trips", "stop_times", "stops")
  optional <- c("agency", "calendar", "calendar_dates", "frequencies")
  required_paths <- file.path(gtfs_dir, paste0(required, ".txt"))
  missing_files <- required[!file.exists(required_paths)]
  if (length(missing_files)) {
    stop("Missing required GTFS file(s): ", paste0(missing_files, ".txt", collapse = ", "))
  }
  required_columns <- list(
    routes = "route_id",
    trips = c("trip_id", "route_id", "service_id"),
    stop_times = c("trip_id", "stop_id", "stop_sequence"),
    stops = "stop_id"
  )
  tables <- stats::setNames(vector("list", length(c(required, optional))), c(required, optional))
  problem_tables <- list()
  for (table in names(tables)) {
    path <- file.path(gtfs_dir, paste0(table, ".txt"))
    if (!file.exists(path)) next
    value <- read_gtfs_table(path)
    if (table %in% required) {
      absent <- setdiff(required_columns[[table]], names(value))
      if (length(absent)) {
        stop(table, ".txt is missing required column(s): ", paste(absent, collapse = ", "))
      }
      if (!nrow(value)) stop(table, ".txt has a header but no data rows.")
    }
    tables[[table]] <- value
    issues <- readr::problems(value)
    if (nrow(issues)) {
      issues$table <- table
      problem_tables[[table]] <- issues
    }
  }
  tables$parsing_problems <- if (length(problem_tables)) {
    dplyr::bind_rows(problem_tables)
  } else {
    data.frame(row = integer(), col = integer(), expected = character(),
               actual = character(), file = character(), table = character())
  }
  tables$parsing_problem_count <- nrow(tables$parsing_problems)
  if (tables$parsing_problem_count > 0L) {
    warning(tables$parsing_problem_count,
            " GTFS parsing problem(s); inspect static_gtfs$parsing_problems.",
            call. = FALSE)
    print(tables$parsing_problems)
  }
  tables
}
