# Shared TfNSW acquisition. Source this file from anywhere inside the repository.
# Credentials exist only in the request's local scope and never enter metadata.

tfnsw_repository_root <- function() {
  candidate <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
  repeat {
    if (file.exists(file.path(candidate, ".git"))) return(candidate)
    parent <- dirname(candidate)
    if (identical(parent, candidate)) {
      stop("Run acquisition from inside the Git repository.", call. = FALSE)
    }
    candidate <- parent
  }
}

tfnsw_project_path <- function(path) {
  if (length(path) != 1L || is.na(path) || !nzchar(path)) {
    stop("An output path must be one nonempty string.", call. = FALSE)
  }
  root <- tfnsw_repository_root()
  path <- gsub("\\\\", "/", path)
  if (!grepl("^(/|[A-Za-z]:/)", path)) path <- file.path(getwd(), path)
  # Resolve an existing ancestor first, including Windows junctions/symlinks.
  ancestor <- path
  suffix <- character()
  while (!file.exists(ancestor)) {
    parent <- dirname(ancestor)
    if (identical(parent, ancestor)) stop("Cannot resolve output path.", call. = FALSE)
    suffix <- c(basename(ancestor), suffix)
    ancestor <- parent
  }
  resolved <- normalizePath(ancestor, winslash = "/", mustWork = TRUE)
  for (part in suffix) {
    if (part == "..") resolved <- dirname(resolved)
    else if (part != ".") resolved <- paste0(sub("/$", "", resolved), "/", part)
  }
  compare <- function(x) if (.Platform$OS.type == "windows") tolower(x) else x
  if (!startsWith(compare(resolved), paste0(compare(root), "/"))) {
    stop("Acquisition output must remain strictly inside the repository.", call. = FALSE)
  }
  resolved
}

tfnsw_create_directory <- function(path) {
  path <- tfnsw_project_path(path)
  if (!dir.exists(path)) dir.create(path, recursive = TRUE, showWarnings = FALSE)
  if (!dir.exists(path)) stop("Could not create acquisition directory.", call. = FALSE)
  tfnsw_project_path(path)
}

tfnsw_latest_file <- function(paths) {
  if (!length(paths)) return(NULL)
  paths[order(file.info(paths)$mtime, paths, decreasing = TRUE, na.last = TRUE)][[1L]]
}

tfnsw_unique_path <- function(directory, stem, extension = "") {
  candidate <- tfnsw_project_path(file.path(directory, paste0(stem, extension)))
  index <- 1L
  while (file.exists(candidate)) {
    index <- index + 1L
    candidate <- tfnsw_project_path(file.path(directory, paste0(stem, "_", index, extension)))
  }
  candidate
}

tfnsw_feed_label <- function(config) {
  label <- paste(config$mode, config$subfeed, sep = "_")
  if (length(label) != 1L || is.na(label) || !grepl("^[A-Za-z0-9_-]+$", label)) {
    stop("Mode and subfeed must be safe filename labels.", call. = FALSE)
  }
  label
}

tfnsw_static_gtfs_dirs <- function(path) {
  required <- c("routes.txt", "trips.txt", "stop_times.txt", "stops.txt")
  if (!dir.exists(path)) return(character())
  candidates <- unique(c(path, dirname(list.files(
    path, pattern = "^stop_times\\.txt$", recursive = TRUE, full.names = TRUE
  ))))
  candidates[vapply(candidates, function(folder) {
    all(file.exists(file.path(folder, required)))
  }, logical(1))]
}

tfnsw_download_payload <- function(endpoint, output_file, config, kind, timeout) {
  if (length(endpoint) != 1L || is.na(endpoint) ||
      !grepl("^/v[12]/gtfs/(schedule|realtime)/[A-Za-z0-9_/-]+$", endpoint)) {
    stop("Expected an official TfNSW GTFS endpoint path.", call. = FALSE)
  }
  output_file <- tfnsw_project_path(output_file)
  if (file.exists(output_file)) stop("Refusing to overwrite a raw snapshot.", call. = FALSE)
  api_key <- Sys.getenv("TFNSW_API_KEY", unset = "")
  if (!nzchar(api_key)) stop("TFNSW_API_KEY is missing from the R environment.", call. = FALSE)
  partial_file <- tfnsw_unique_path(dirname(output_file), basename(output_file), ".partial")
  started <- as.POSIXct(Sys.time(), tz = "UTC")
  request <- httr2::request(paste0("https://api.transport.nsw.gov.au", endpoint)) |>
    httr2::req_headers(Authorization = paste("apikey", api_key)) |>
    httr2::req_options(followlocation = FALSE) |>
    httr2::req_timeout(seconds = timeout) |>
    httr2::req_retry(max_tries = 3, retry_on_failure = TRUE,
      is_transient = function(response) httr2::resp_status(response) %in% c(429, 500, 502, 503, 504),
      backoff = function(attempt) min(2^attempt, 30)) |>
    httr2::req_error(is_error = function(response) FALSE)
  # Discard the original error condition: it may retain a request or response.
  response <- tryCatch(
    httr2::req_perform(request, path = partial_file, verbosity = 0),
    error = function(error) NULL
  )
  if (is.null(response)) {
    stop("TfNSW request failed after at most three attempts; partial download retained.", call. = FALSE)
  }
  status <- httr2::resp_status(response)
  if (status != 200L) {
    stop(sprintf("TfNSW request returned HTTP %d; response was not published as a snapshot.", status),
         call. = FALSE)
  }
  size <- file.info(partial_file)$size
  if (is.na(size) || size <= 0) stop("TfNSW returned an empty response.", call. = FALSE)
  # Publish only a finished transfer. Partial/error bodies never receive .pb/.zip names.
  if (file.exists(output_file) || !file.rename(partial_file, output_file)) {
    stop("Could not publish raw snapshot without overwriting an existing file.", call. = FALSE)
  }
  finished <- as.POSIXct(Sys.time(), tz = "UTC")
  metadata <- list(
    mode = config$mode, source_subfeed = config$subfeed, endpoint = endpoint,
    payload_kind = kind, snapshot_timestamp_utc = started,
    collection_started_utc = started, collection_finished_utc = finished,
    http_status = status, bytes = unname(size), raw_file = basename(output_file)
  )
  metadata_path <- tfnsw_project_path(paste0(output_file, ".metadata.rds"))
  if (file.exists(metadata_path)) stop("Raw metadata already exists.", call. = FALSE)
  saveRDS(metadata, metadata_path)
  message(sprintf("Saved %s/%s %s: %s bytes (HTTP %d).",
                  config$mode, config$subfeed, kind, format(size, scientific = FALSE), status))
  output_file
}

tfnsw_extract_static <- function(zip_file) {
  zip_file <- tfnsw_project_path(zip_file)
  # Check every member before extracting any of them. Backslashes and colons
  # matter on Windows, including drive paths and NTFS alternate data streams.
  members <- tryCatch(utils::unzip(zip_file, list = TRUE), error = function(error) NULL)
  if (is.null(members) || !nrow(members)) stop("Static response is not a readable nonempty ZIP.", call. = FALSE)
  names <- gsub("\\\\", "/", members$Name)
  unsafe <- is.na(names) | !nzchar(names) | grepl("^/|:|(^|/)\\.\\.(/|$)", names)
  if (any(unsafe)) stop("Static ZIP contains an unsafe extraction path.", call. = FALSE)
  # A duplicate member could overwrite earlier data during extraction.
  file_names <- sub("/$", "", names)
  if (.Platform$OS.type == "windows") file_names <- tolower(file_names)
  if (anyDuplicated(file_names)) stop("Static ZIP contains duplicate member paths.", call. = FALSE)
  stem <- tools::file_path_sans_ext(basename(zip_file))
  existing <- file.path(dirname(zip_file), stem)
  if (length(tfnsw_static_gtfs_dirs(existing))) return(tfnsw_project_path(existing))
  # Incomplete previous extractions remain for diagnosis; start in a fresh folder.
  extract_dir <- tfnsw_unique_path(dirname(zip_file), stem)
  extract_dir <- tfnsw_create_directory(extract_dir)
  invisible(vapply(file.path(extract_dir, names), tfnsw_project_path, character(1)))
  tryCatch(utils::unzip(zip_file, exdir = extract_dir, overwrite = FALSE),
           error = function(error) stop("Static ZIP extraction failed; ZIP retained for reuse.", call. = FALSE))
  folders <- tfnsw_static_gtfs_dirs(extract_dir)
  if (!length(folders)) {
    stop("Static ZIP lacks routes.txt, trips.txt, stop_times.txt or stops.txt in a common folder.", call. = FALSE)
  }
  # A multi-fileset combined bus bundle deliberately returns its common root.
  extract_dir
}

tfnsw_static_is_today <- function(path, timezone) {
  today <- format(Sys.time(), "%Y%m%d", tz = timezone)
  label <- basename(path)
  if (grepl("static_gtfs_[0-9]{8}", label)) {
    return(sub(".*static_gtfs_([0-9]{8}).*", "\\1", label) == today)
  }
  format(file.info(path)$mtime, "%Y%m%d", tz = timezone) == today
}

acquire_static_gtfs <- function(config, reuse = TRUE, offline = FALSE) {
  directory <- tfnsw_project_path(config$raw_static_dir)
  timezone <- if (is.null(config$timezone)) "Australia/Sydney" else config$timezone
  if (reuse || offline) {
    candidates <- if (dir.exists(directory)) list.dirs(directory, recursive = FALSE, full.names = TRUE) else character()
    candidates <- candidates[vapply(candidates, function(path) length(tfnsw_static_gtfs_dirs(path)) > 0L, logical(1))]
    if (!offline && length(candidates)) {
      candidates <- candidates[vapply(candidates, tfnsw_static_is_today, logical(1), timezone = timezone)]
    }
    cached <- tfnsw_latest_file(candidates)
    if (!is.null(cached)) {
      message(sprintf("Reusing saved static GTFS for %s/%s.", config$mode, config$subfeed))
      return(tfnsw_project_path(cached))
    }
    archives <- if (dir.exists(directory)) list.files(directory, pattern = "\\.zip$", full.names = TRUE) else character()
    if (!offline && length(archives)) {
      archives <- archives[vapply(archives, tfnsw_static_is_today, logical(1), timezone = timezone)]
    }
    cached_zip <- tfnsw_latest_file(archives)
    if (!is.null(cached_zip)) return(tfnsw_extract_static(cached_zip))
  }
  if (offline) stop("No saved static GTFS is available for this feed.", call. = FALSE)
  directory <- tfnsw_create_directory(directory)
  now <- Sys.time()
  stem <- paste(tfnsw_feed_label(config), "static_gtfs", format(now, "%Y%m%d", tz = timezone),
                format(now, "%Y%m%dT%H%M%SZ", tz = "UTC"), sep = "_")
  zip_file <- tfnsw_unique_path(directory, stem, ".zip")
  tfnsw_download_payload(config$static_endpoint, zip_file, config, "static_gtfs", timeout = 180)
  tfnsw_extract_static(zip_file)
}

acquire_trip_updates <- function(config, reuse = FALSE, offline = FALSE) {
  directory <- tfnsw_project_path(config$raw_realtime_dir)
  if (reuse || offline) {
    paths <- if (dir.exists(directory)) list.files(directory, pattern = "\\.pb$", full.names = TRUE) else character()
    paths <- paths[!is.na(file.info(paths)$size) & file.info(paths)$size > 0]
    cached <- tfnsw_latest_file(paths)
    if (!is.null(cached)) {
      message(sprintf("Reusing saved Trip Updates for %s/%s.", config$mode, config$subfeed))
      return(tfnsw_project_path(cached))
    }
  }
  if (offline) stop("No saved Trip Updates snapshot is available for this feed.", call. = FALSE)
  directory <- tfnsw_create_directory(directory)
  # Keep the UTC timestamp at the end for downstream snapshot-time parsing.
  stem <- paste(tfnsw_feed_label(config), "trip_updates", sep = "_")
  timestamp <- format(Sys.time(), "%Y%m%dT%H%M%SZ", tz = "UTC")
  output_file <- tfnsw_project_path(file.path(directory, paste0(stem, "_", timestamp, ".pb")))
  if (file.exists(output_file)) {
    # Collision suffix precedes the timestamp; no existing raw payload is changed.
    index <- 2L
    repeat {
      output_file <- tfnsw_project_path(file.path(directory, paste0(stem, "_", index, "_", timestamp, ".pb")))
      if (!file.exists(output_file)) break
      index <- index + 1L
    }
  }
  tfnsw_download_payload(config$realtime_endpoint, output_file, config, "trip_updates", timeout = 45)
}
