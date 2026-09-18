# Public configuration only; API keys belong in TFNSW_API_KEY, never here.
tfnsw_feed <- function(mode, subfeed, static_endpoint, realtime_endpoint,
                       scope = "feed", raw_subdir = subfeed) {
  root <- file.path("data", "raw", mode)
  if (nzchar(raw_subdir)) root <- file.path(root, raw_subdir)
  list(mode = mode, subfeed = subfeed, static_endpoint = static_endpoint,
    realtime_endpoint = realtime_endpoint, static_api_version = strsplit(static_endpoint, "/")[[1]][2],
    realtime_api_version = strsplit(realtime_endpoint, "/")[[1]][2],
    raw_static_dir = file.path(root, "static_gtfs"), raw_realtime_dir = file.path(root, "trip_updates"),
    interim_dir = file.path("data", "interim", "by_mode", mode, subfeed),
    processed_dir = file.path("data", "processed", "by_mode", mode),
    timezone = "Australia/Sydney", scope = scope)
}
tfnsw_feeds <- list(
  train = tfnsw_feed("train", "sydneytrains", "/v1/gtfs/schedule/sydneytrains",
    "/v2/gtfs/realtime/sydneytrains", "train_t1_t9", raw_subdir = ""),
  metro = tfnsw_feed("metro", "metro", "/v2/gtfs/schedule/metro", "/v2/gtfs/realtime/metro"),
  ferry = tfnsw_feed("ferry", "sydneyferries", "/v1/gtfs/schedule/ferries/sydneyferries",
    "/v1/gtfs/realtime/ferries/sydneyferries"),
  bus = tfnsw_feed("bus", "buses", "/v1/gtfs/schedule/buses",
    "/v1/gtfs/realtime/buses", "sydney_bus"),
  innerwest = tfnsw_feed("light_rail", "innerwest", "/v1/gtfs/schedule/lightrail/innerwest",
    "/v2/gtfs/realtime/lightrail/innerwest"),
  cbdandsoutheast = tfnsw_feed("light_rail", "cbdandsoutheast", "/v1/gtfs/schedule/lightrail/cbdandsoutheast",
    "/v1/gtfs/realtime/lightrail/cbdandsoutheast"),
  parramatta = tfnsw_feed("light_rail", "parramatta", "/v1/gtfs/schedule/lightrail/parramatta",
    "/v1/gtfs/realtime/lightrail/parramatta")
)
# Static-only catalogs identify contingency rows sharing the /buses realtime feed.
# Their data is used for exclusion/provenance, never appended to project rows.
tfnsw_feeds$bus$scope_catalogs <- lapply(c("PCBC", "ReplacementBus"), function(subfeed) {
  tfnsw_feed("bus", subfeed, paste0("/v1/gtfs/schedule/buses/", subfeed),
             "/v1/gtfs/realtime/buses")
})
tfnsw_feeds$bus$excluded_operator_names <- "Newcastle Transport"
