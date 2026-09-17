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
# 2. Define Sydney Trains static GTFS endpoint
# ------------------------------------------------------------

url <- paste0(
  "https://api.transport.nsw.gov.au",
  "/v1/gtfs/schedule/sydneytrains"
)


# ------------------------------------------------------------
# 3. Request static GTFS bundle from TfNSW
# ------------------------------------------------------------

response <- request(url) |>
  req_headers(
    Authorization = paste(
      "apikey",
      api_key
    )
  ) |>
  req_perform()


# Stop if TfNSW returned an HTTP error
resp_check_status(response)


# ------------------------------------------------------------
# 4. Extract downloaded binary ZIP payload
# ------------------------------------------------------------

raw_payload <- resp_body_raw(response)

if (length(raw_payload) == 0) {
  stop(
    "TfNSW returned an empty static GTFS response."
  )
}

cat(
  "HTTP status:",
  resp_status(response),
  "\n"
)

cat(
  "Content type:",
  resp_header(
    response,
    "content-type"
  ),
  "\n"
)

cat(
  "Downloaded size:",
  length(raw_payload),
  "bytes\n"
)


# ------------------------------------------------------------
# 5. Create raw-data storage directory
# ------------------------------------------------------------

output_dir <- file.path(
  "data",
  "raw",
  "train",
  "static_gtfs"
)

dir.create(
  output_dir,
  recursive = TRUE,
  showWarnings = FALSE
)


# ------------------------------------------------------------
# 6. Create date label
#
# Use Sydney local date because the dataset represents the
# Sydney transport network.
# ------------------------------------------------------------

date_tag <- format(
  Sys.time(),
  format = "%Y%m%d",
  tz = "Australia/Sydney"
)


# ------------------------------------------------------------
# 7. Save original GTFS ZIP exactly as downloaded
# ------------------------------------------------------------

zip_file <- file.path(
  output_dir,
  paste0(
    "sydneytrains_static_gtfs_",
    date_tag,
    ".zip"
  )
)

writeBin(
  raw_payload,
  zip_file
)

cat(
  "Saved ZIP:",
  zip_file,
  "\n"
)


# ------------------------------------------------------------
# 8. Create extraction directory
# ------------------------------------------------------------

extract_dir <- file.path(
  output_dir,
  paste0(
    "sydneytrains_static_gtfs_",
    date_tag
  )
)


# If the script is rerun on the same day,
# remove the previous extracted copy first.
#
# This prevents old files remaining in the folder if
# the contents of the TfNSW bundle change.
if (dir.exists(extract_dir)) {

  unlink(
    extract_dir,
    recursive = TRUE,
    force = TRUE
  )
}

dir.create(
  extract_dir,
  recursive = TRUE,
  showWarnings = FALSE
)


# ------------------------------------------------------------
# 9. Extract GTFS ZIP
# ------------------------------------------------------------

unzip(
  zipfile = zip_file,
  exdir = extract_dir
)


# ------------------------------------------------------------
# 10. Verify important GTFS files were extracted
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
      extract_dir,
      required_files
    )
  )
]

if (length(missing_files) > 0) {

  stop(
    paste(
      "Static GTFS download succeeded,",
      "but required file(s) were missing:",
      paste(
        missing_files,
        collapse = ", "
      )
    )
  )
}


# ------------------------------------------------------------
# 11. Print extracted file list
# ------------------------------------------------------------

extracted_files <- list.files(
  extract_dir
)

cat(
  "Extracted to:",
  extract_dir,
  "\n"
)

cat(
  "\nFiles extracted:\n"
)

print(
  extracted_files
)


# ------------------------------------------------------------
# 12. Final confirmation
# ------------------------------------------------------------

cat(
  "\nStatic Sydney Trains GTFS download completed successfully.\n"
)