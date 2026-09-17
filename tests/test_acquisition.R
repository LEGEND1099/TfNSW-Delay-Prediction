# Synthetic acquisition checks. No credentials are inspected and no API calls occur.
source("R/acquisition/tfnsw/acquire_gtfs.R")

expect_acquisition_error <- function(expression, pattern) {
  result <- tryCatch(force(expression), error = function(e) e)
  stopifnot(inherits(result, "error"), grepl(pattern, conditionMessage(result)))
}
fixture_parent <- tfnsw_create_directory(file.path("logs", "tests", "acquisition"))
fixture_root <- tfnsw_create_directory(tempfile("run_", tmpdir = fixture_parent))
repository <- tfnsw_repository_root()
config <- list(mode = "test", subfeed = "synthetic", timezone = "Australia/Sydney",
               static_endpoint = "/v1/gtfs/schedule/test",
               realtime_endpoint = "/v1/gtfs/realtime/test",
               raw_static_dir = file.path(fixture_root, "static"),
               raw_realtime_dir = file.path(fixture_root, "realtime"))

# Containment applies to existing paths and to paths with nonexistent ancestors.
stopifnot(identical(tfnsw_project_path(fixture_root), fixture_root))
expect_acquisition_error(tfnsw_project_path(repository), "strictly inside")
expect_acquisition_error(tfnsw_project_path(dirname(repository)), "strictly inside")
expect_acquisition_error(tfnsw_project_path(file.path(repository, "..", "outside_probe", "new.pb")),
                         "strictly inside")
expect_acquisition_error(tfnsw_project_path(character()), "one nonempty string")
expect_acquisition_error(tfnsw_project_path(NA_character_), "one nonempty string")
unsafe_config <- config
unsafe_config$subfeed <- "../elsewhere"
expect_acquisition_error(tfnsw_feed_label(unsafe_config), "safe filename labels")

# Offline reuse chooses an existing nonempty payload and leaves its bytes and
# modification time unchanged. Empty and partial downloads are not snapshots.
realtime_dir <- tfnsw_create_directory(config$raw_realtime_dir)
older_path <- file.path(realtime_dir, "test_synthetic_trip_updates_20000101T000000Z.pb")
latest_path <- file.path(realtime_dir, "test_synthetic_trip_updates_20000101T000001Z.pb")
empty_path <- file.path(realtime_dir, "test_synthetic_trip_updates_20000101T000002Z.pb")
partial_path <- paste0(latest_path, ".partial")
writeBin(as.raw(c(1, 2)), older_path)
writeBin(as.raw(c(3, 4, 5)), latest_path)
writeBin(raw(), empty_path)
writeBin(as.raw(c(6, 7)), partial_path)
Sys.setFileTime(older_path, as.POSIXct("2000-01-01 00:00:00", tz = "UTC"))
Sys.setFileTime(latest_path, as.POSIXct("2000-01-01 00:00:01", tz = "UTC"))
raw_paths <- c(older_path, latest_path, empty_path, partial_path)
before_hash <- tools::md5sum(raw_paths)
before_time <- file.info(raw_paths)$mtime
cached <- acquire_trip_updates(config, offline = TRUE)
stopifnot(identical(cached, tfnsw_project_path(latest_path)),
          identical(tools::md5sum(raw_paths), before_hash),
          identical(file.info(raw_paths)$mtime, before_time))

# Overwrite refusal runs before credential access or request construction.
expect_acquisition_error(tfnsw_download_payload(config$realtime_endpoint, latest_path,
                                                config, "trip_updates", 1),
                         "Refusing to overwrite")
expect_acquisition_error(tfnsw_download_payload("https://example.invalid/feed", latest_path,
                                                config, "trip_updates", 1),
                         "official TfNSW GTFS endpoint")
stopifnot(identical(tools::md5sum(raw_paths), before_hash),
          identical(file.info(raw_paths)$mtime, before_time),
          tfnsw_unique_path(realtime_dir, basename(latest_path)) != latest_path)

# A combined archive can contain several complete operator filesets. Discovery
# excludes incomplete folders and offline acquisition returns their common root.
static_dir <- tfnsw_create_directory(config$raw_static_dir)
bundle <- tfnsw_create_directory(file.path(static_dir, "test_static_gtfs_20000101"))
required <- c("routes", "trips", "stop_times", "stops")
operators <- c("operator_a", "operator_b")
for (operator in operators) {
  folder <- tfnsw_create_directory(file.path(bundle, operator))
  for (table in required) writeLines("fixture", file.path(folder, paste0(table, ".txt")))
}
incomplete <- tfnsw_create_directory(file.path(bundle, "incomplete"))
writeLines("fixture", file.path(incomplete, "stop_times.txt"))
discovered <- tfnsw_static_gtfs_dirs(bundle)
stopifnot(identical(sort(basename(discovered)), operators),
          identical(acquire_static_gtfs(config, offline = TRUE), tfnsw_project_path(bundle)),
          !tfnsw_static_is_today(bundle, config$timezone))

missing_config <- config
missing_config$raw_realtime_dir <- file.path(fixture_root, "missing_realtime")
missing_config$raw_static_dir <- file.path(fixture_root, "missing_static")
expect_acquisition_error(acquire_trip_updates(missing_config, offline = TRUE), "No saved Trip Updates")
expect_acquisition_error(acquire_static_gtfs(missing_config, offline = TRUE), "No saved static GTFS")
stopifnot(!dir.exists(missing_config$raw_realtime_dir), !dir.exists(missing_config$raw_static_dir))
cat("Acquisition path safety, offline reuse, and raw immutability tests passed.\n")
