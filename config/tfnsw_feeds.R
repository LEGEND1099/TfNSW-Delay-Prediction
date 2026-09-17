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
    "/v2/gtfs/realtime/sydneytrains", "train_t1_t9", raw_subdir = "")
)
