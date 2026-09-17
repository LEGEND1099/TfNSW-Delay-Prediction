# Resolve scope against current official static catalogs, without guessing ID prefixes.
read_bus_scope_catalogs <- function(config, offline = FALSE) {
  catalogs <- lapply(config$scope_catalogs, function(catalog) {
    path <- acquire_static_gtfs(catalog, reuse = TRUE, offline = offline)
    tables <- read_static_gtfs(path)
    if (tables$parsing_problem_count) stop("Bus scope catalog has parsing problems: ", catalog$subfeed)
    list(subfeed = catalog$subfeed, endpoint = catalog$static_endpoint, directory = path,
         trips = tables$trips$trip_id, routes = tables$routes$route_id,
         agencies = tables$agency$agency_id)
  })
  names(catalogs) <- vapply(config$scope_catalogs, `[[`, character(1), "subfeed")
  catalogs
}

classify_bus_scope <- function(x, config) {
  if (is.null(config$bus_scope_catalogs)) stop("Bus scope catalogs must be loaded before processing.")
  x$is_school_service <- x$route_type %in% c(712L, 713L)
  x$scope_catalog <- rep(NA_character_, nrow(x))
  x$scope_catalog_endpoint <- rep(NA_character_, nrow(x))
  # The combined bus feed is restricted to metro/outer-metro contracts. Unknown
  # metadata cannot establish project membership; preserve it in the scope audit.
  x$scope_status[!x$route_type %in% c(3L, 700L:716L)] <- "EXCLUDE_NON_BUS_ROUTE"
  x$scope_status[x$route_type %in% 701L] <- "EXCLUDE_REGIONAL_BUS_ROUTE"
  x$scope_status[is.na(x$route_type) | is.na(x$source_operator)] <- "EXCLUDE_UNCLASSIFIED_BUS"
  x$scope_status[x$source_operator %in% config$excluded_operator_names] <- "EXCLUDE_NEWCASTLE_OPERATOR"
  x$scope_status[x$route_type %in% 714L] <- "EXCLUDE_RAIL_REPLACEMENT_BUS"
  for (catalog in config$bus_scope_catalogs) {
    member <- (!is.na(x$trip_id) & x$trip_id %in% catalog$trips) |
      (!is.na(x$route_id) & x$route_id %in% catalog$routes) |
      (!is.na(x$realtime_route_id) & x$realtime_route_id %in% catalog$routes)
    x$scope_status[member] <- paste0("EXCLUDE_", toupper(catalog$subfeed))
    x$scope_catalog[member] <- catalog$subfeed
    x$scope_catalog_endpoint[member] <- catalog$endpoint
  }
  x
}
