library(httr2)


# ------------------------------------------------------------
# 1. Read TfNSW API key securely
# ------------------------------------------------------------

api_key <- Sys.getenv("TFNSW_API_KEY")

if (!nzchar(api_key)) {
  stop(
    paste(
      "TFNSW_API_KEY was not found.",
      "Check that .Renviron exists and restart the R session."
    )
  )
}


# ------------------------------------------------------------
# 2. Define Sydney Trains GTFS-Realtime endpoint
# ------------------------------------------------------------

url <- paste0(
  "https://api.transport.nsw.gov.au",
  "/v2/gtfs/realtime/sydneytrains"
)


# ------------------------------------------------------------
# 3. Request realtime Trip Updates
# ------------------------------------------------------------

response <- request(url) |>
  req_headers(
    Authorization = paste(
      "apikey",
      api_key
    )
  ) |>
  req_timeout(
    seconds = 30
  ) |>
  req_retry(
    max_tries = 3
  ) |>
  req_perform()


# Stop immediately if TfNSW returned an HTTP error
resp_check_status(response)


# ------------------------------------------------------------
# 4. Extract raw Protobuf payload
# ------------------------------------------------------------

raw_payload <- resp_body_raw(response)

if (length(raw_payload) == 0) {
  stop(
    "TfNSW returned an empty realtime response."
  )
}


# ------------------------------------------------------------
# 5. Inspect response metadata
# ------------------------------------------------------------

http_status <- resp_status(response)

content_type <- resp_header(
  response,
  "content-type"
)

cat(
  "HTTP status:",
  http_status,
  "\n"
)

cat(
  "Content type:",
  content_type,
  "\n"
)

cat(
  "Response size:",
  length(raw_payload),
  "bytes\n"
)


# ------------------------------------------------------------
# 6. Create raw snapshot directory
# ------------------------------------------------------------

output_dir <- file.path(
  "data",
  "raw",
  "train",
  "trip_updates"
)

dir.create(
  output_dir,
  recursive = TRUE,
  showWarnings = FALSE
)


# ------------------------------------------------------------
# 7. Create UTC snapshot timestamp
#
# UTC is used because GTFS-Realtime timestamps are Unix-based
# and storing raw snapshots in UTC avoids daylight-saving and
# timezone ambiguity.
# ------------------------------------------------------------

snapshot_time_utc <- Sys.time()

attr(
  snapshot_time_utc,
  "tzone"
) <- "UTC"

timestamp_tag <- format(
  snapshot_time_utc,
  format = "%Y%m%dT%H%M%SZ",
  tz = "UTC"
)


# ------------------------------------------------------------
# 8. Construct snapshot filename
# ------------------------------------------------------------

output_file <- file.path(
  output_dir,
  paste0(
    "sydneytrains_trip_updates_",
    timestamp_tag,
    ".pb"
  )
)


# ------------------------------------------------------------
# 9. Save exact raw Protobuf bytes
# ------------------------------------------------------------

writeBin(
  raw_payload,
  output_file
)


# ------------------------------------------------------------
# 10. Verify the snapshot was written successfully
# ------------------------------------------------------------

if (!file.exists(output_file)) {
  stop(
    "Realtime snapshot could not be saved."
  )
}

saved_size <- file.info(
  output_file
)$size

if (
  is.na(saved_size) ||
  saved_size == 0
) {
  stop(
    "Realtime snapshot was created but is empty."
  )
}


# ------------------------------------------------------------
# 11. Final confirmation
# ------------------------------------------------------------

cat(
  "\nSydney Trains realtime snapshot saved successfully.\n"
)

cat(
  "Snapshot time (UTC):",
  format(
    snapshot_time_utc,
    "%Y-%m-%d %H:%M:%S",
    tz = "UTC"
  ),
  "\n"
)

cat(
  "Saved file:",
  output_file,
  "\n"
)

cat(
  "Saved size:",
  saved_size,
  "bytes\n"
)