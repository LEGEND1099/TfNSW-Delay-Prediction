source("R/processing/bus_scope.R")
source("R/processing/process_gtfs.R")
source("config/tfnsw_feeds.R")
config <- tfnsw_feeds$bus
config$bus_scope_catalogs <- list(
  PCBC = list(subfeed = "PCBC", endpoint = "/v1/gtfs/schedule/buses/PCBC",
              trips = "contingency_trip", routes = "pcbc_route", agencies = "shared"),
  ReplacementBus = list(subfeed = "ReplacementBus", endpoint = "/v1/gtfs/schedule/buses/ReplacementBus",
                        trips = character(), routes = "replacement_route", agencies = "shared")
)
x <- data.frame(
  trip_id = c("ordinary", "school", "replacement", "contingency_trip", "newcastle", "ferry", "unknown", "regional", "rail_bus", "added"),
  route_id = c("public", "school", "replacement_route", NA, "newcastle", "ferry", NA, "regional", "rail_bus", "added"),
  realtime_route_id = c(rep(NA_character_, 9), "pcbc_route"),
  route_type = c(700L, 712L, 700L, NA, 700L, 4L, NA, 701L, 714L, 700L),
  agency_id = c(rep("shared", 4), "3000", "3000", NA, rep("shared", 3)),
  source_operator = c(rep("Operator", 4), "Newcastle Transport", "Newcastle Transport", NA, rep("Operator", 3)),
  snapshot_time_utc = as.POSIXct("2026-09-18", tz = "UTC")
)
scoped <- scope_gtfs(x, config)
stopifnot(nrow(scoped$audit) == nrow(x), identical(scoped$processed$trip_id, c("ordinary", "school")),
          identical(scoped$processed$is_school_service, c(FALSE, TRUE)),
          all(scoped$processed$source_subfeed == "buses"),
          all(scoped$processed$source_operator == "Operator"),
          scoped$audit$scope_status[3] == "EXCLUDE_REPLACEMENTBUS",
          all(scoped$audit$scope_status[c(4,10)] == "EXCLUDE_PCBC"),
          all(scoped$audit$scope_status[c(5,6)] == "EXCLUDE_NEWCASTLE_OPERATOR"),
          scoped$audit$scope_status[7] == "EXCLUDE_UNCLASSIFIED_BUS",
          scoped$audit$scope_status[8] == "EXCLUDE_REGIONAL_BUS_ROUTE",
          scoped$audit$scope_status[9] == "EXCLUDE_RAIL_REPLACEMENT_BUS")
# Agency names/IDs can overlap catalogs; normal routes of the same agency stay.
stopifnot(scoped$audit$keep_for_project[1])
empty <- scope_gtfs(x[0, ], config)
stopifnot(nrow(empty$processed) == 0L, identical(names(empty$audit), names(scoped$audit)))
cat("Bus scope and contingency provenance tests passed.\n")
