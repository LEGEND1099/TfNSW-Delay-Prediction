scope_gtfs <- function(x, config) {
  x$mode <- rep(config$mode, nrow(x))
  x$source_subfeed <- rep(config$subfeed, nrow(x))
  x$source_feed <- rep(config$static_endpoint, nrow(x))
  x$keep_for_project <- rep(TRUE, nrow(x))
  x$scope_status <- rep("KEEP", nrow(x))
  if (config$scope == "train_t1_t9") {
    x$in_sydney_trains_scope <- x$route_short_name %in% paste0("T", 1:9)
    x$is_empty_train <- !is.na(x$trip_headsign) & grepl("empty train", x$trip_headsign, ignore.case = TRUE)
    x$scope_status[!x$in_sydney_trains_scope] <- "EXCLUDE_OUTSIDE_T1_T9"
    x$scope_status[is.na(x$route_short_name)] <- "EXCLUDE_MISSING_ROUTE_METADATA"
    x$scope_status[x$is_empty_train] <- "EXCLUDE_EMPTY_TRAIN"
  }
  if (config$scope == "sydney_bus") x <- classify_bus_scope(x, config)
  x$keep_for_project <- x$scope_status == "KEEP"
  x$snapshot_time_sydney <- format(x$snapshot_time_utc, "%Y-%m-%d %H:%M:%S", tz = config$timezone)
  list(audit = x, processed = x[x$keep_for_project, ])
}
