library(RProtoBuf)

# ------------------------------------------------------------
# 1. Load GTFS-Realtime schema
# ------------------------------------------------------------

schema_file <- "proto/gtfs-realtime.proto"

if (!file.exists(schema_file)) {
  stop("GTFS-Realtime schema was not found.")
}

readProtoFiles(schema_file)

# Obtain the definition of the top-level GTFS-Realtime message
FeedMessage <- P("transit_realtime.FeedMessage")


# ------------------------------------------------------------
# 2. Find the most recent saved Sydney Trains snapshot
# ------------------------------------------------------------

snapshot_dir <- file.path(
  "data",
  "raw",
  "train",
  "trip_updates"
)

snapshot_files <- list.files(
  snapshot_dir,
  pattern = "\\.pb$",
  full.names = TRUE
)

if (length(snapshot_files) == 0) {
  stop("No saved Sydney Trains snapshots were found.")
}

file_times <- file.info(snapshot_files)$mtime

input_file <- snapshot_files[
  which.max(file_times)
]

cat("Reading:", input_file, "\n")


# ------------------------------------------------------------
# 3. Extract snapshot collection time from filename
# ------------------------------------------------------------

snapshot_string <- sub(
  "^.*_(\\d{8}T\\d{6}Z)\\.pb$",
  "\\1",
  basename(input_file)
)

snapshot_time_utc <- as.POSIXct(
  snapshot_string,
  format = "%Y%m%dT%H%M%SZ",
  tz = "UTC"
)

if (is.na(snapshot_time_utc)) {
  stop("Could not extract snapshot timestamp from filename.")
}

cat(
  "Snapshot time (UTC):",
  format(
    snapshot_time_utc,
    "%Y-%m-%d %H:%M:%S",
    tz = "UTC"
  ),
  "\n"
)


# ------------------------------------------------------------
# 4. Read the saved binary payload
# ------------------------------------------------------------

file_size <- file.info(input_file)$size

raw_payload <- readBin(
  input_file,
  what = "raw",
  n = file_size
)

cat(
  "Raw payload size:",
  length(raw_payload),
  "bytes\n"
)


# ------------------------------------------------------------
# 5. Decode the binary payload
# ------------------------------------------------------------

feed <- read(
  FeedMessage,
  raw_payload
)


# ------------------------------------------------------------
# 6. Extract feed-level timestamp
# ------------------------------------------------------------

feed_time_utc <- if (
  feed$header$has("timestamp")
) {
  as.POSIXct(
    as.numeric(feed$header$timestamp),
    origin = "1970-01-01",
    tz = "UTC"
  )
} else {
  as.POSIXct(
    NA,
    tz = "UTC"
  )
}


# ------------------------------------------------------------
# 7. Basic feed validation
# ------------------------------------------------------------

cat(
  "GTFS-Realtime version:",
  feed$header$gtfs_realtime_version,
  "\n"
)

cat(
  "Number of FeedEntities:",
  feed$size("entity"),
  "\n"
)

cat(
  "Feed timestamp (UTC):",
  ifelse(
    is.na(feed_time_utc),
    "Not supplied",
    format(
      feed_time_utc,
      "%Y-%m-%d %H:%M:%S",
      tz = "UTC"
    )
  ),
  "\n"
)