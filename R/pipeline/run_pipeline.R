run_feed_once <- function(config, offline = FALSE, reuse_realtime = FALSE) {
  static_dir <- acquire_static_gtfs(config, reuse = TRUE, offline = offline)
  realtime_path <- acquire_trip_updates(config, reuse = reuse_realtime, offline = offline)
  cat("Parsing", config$mode, config$subfeed, "from saved files\n")
  static <- read_static_gtfs(static_dir)
  if (config$scope == "sydney_bus") config$bus_scope_catalogs <- read_bus_scope_catalogs(config, offline)
  parsed <- read_trip_updates(realtime_path)
  integrated <- integrate_gtfs(parsed$trip_updates_df, static,
    parsed$snapshot_time_utc, parsed$feed_time_utc, config$timezone)
  integrated$source_operator <- rep(NA_character_, nrow(integrated))
  if (!is.null(static$agency) && "agency_id" %in% names(static$agency)) {
    ai <- unique_lookup(integrated, static$agency, "agency_id")
    integrated$source_operator <- static$agency$agency_name[ai$index]
  }
  scoped <- scope_gtfs(integrated, config)
  validation <- validate_gtfs(parsed, static, integrated, scoped$processed, config)
  tag <- format(parsed$snapshot_time_utc, "%Y%m%dT%H%M%SZ", tz = "UTC")
  dir.create(config$interim_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(config$processed_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create("logs/validation", recursive = TRUE, showWarnings = FALSE)
  prefix <- file.path(config$interim_dir, paste0(config$subfeed, "_", tag))
  summary <- parsed$trip_summary_df
  summary$mode <- rep(config$mode, nrow(summary))
  summary$source_subfeed <- rep(config$subfeed, nrow(summary))
  summary$snapshot_time_utc <- rep(parsed$snapshot_time_utc, nrow(summary))
  summary$feed_time_utc <- rep(parsed$feed_time_utc, nrow(summary))
  saveRDS(summary, paste0(prefix, "_trip_summary.rds"))
  stops <- parsed$trip_updates_df
  stops$mode <- rep(config$mode, nrow(stops))
  stops$source_subfeed <- rep(config$subfeed, nrow(stops))
  stops$source_feed <- rep(config$realtime_endpoint, nrow(stops))
  stops$snapshot_time_utc <- rep(parsed$snapshot_time_utc, nrow(stops))
  stops$feed_time_utc <- rep(parsed$feed_time_utc, nrow(stops))
  saveRDS(stops, paste0(prefix, "_stop_updates.rds"))
  saveRDS(scoped$audit, paste0(prefix, "_scope_audit.rds"))
  if (static$parsing_problem_count > 0L) saveRDS(static$parsing_problems, paste0(prefix, "_parsing_problems.rds"))
  processed_path <- file.path(config$processed_dir, paste0(config$subfeed, "_snapshot_", tag, ".rds"))
  saveRDS(scoped$processed, processed_path)
  readr::write_csv(scoped$processed, sub("\\.rds$", ".csv", processed_path), na = "")
  validation$static_directory <- static_dir
  validation$raw_realtime_path <- realtime_path
  validation$processed_path <- processed_path
  validation$scope_exclusion_counts <- relationship_counts(scoped$audit$scope_status[!scoped$audit$keep_for_project])
  validation$scope_excluded_rows <- sum(!scoped$audit$keep_for_project)
  validation$scope_catalog_directories <- paste(vapply(config$bus_scope_catalogs,
    `[[`, character(1), "directory"), collapse = ";")
  readr::write_csv(validation, file.path("logs/validation", paste0(config$subfeed, "_", tag, ".csv")))
  print(validation[, c("mode", "source_subfeed", "stop_level_rows", "processed_rows",
    "static_trip_match_rate", "static_stop_match_rate", "static_trip_stop_match_rate")], width = Inf)
  list(validation = validation, processed_path = processed_path)
}

complete_mode_output <- function(configs, results) {
  stopifnot(length(configs) > 0L, all(names(configs) %in% names(results)))
  results <- results[names(configs)]
  mode <- configs[[1]]$mode
  subfeeds <- vapply(configs, `[[`, character(1), "subfeed")
  snapshot <- as.POSIXct(max(vapply(results, function(result) {
    as.numeric(result$validation$snapshot_time_utc)
  }, numeric(1))), origin = "1970-01-01", tz = "UTC")
  stopifnot(!is.na(snapshot), !anyDuplicated(subfeeds))
  if (length(configs) == 1L) {
    result <- results[[1]]
    return(list(mode = mode, source_subfeeds = subfeeds, snapshot_time_utc = snapshot,
                processed_path = result$processed_path,
                processed_rows = result$validation$processed_rows,
                processed_columns = result$validation$processed_columns))
  }
  directories <- unique(vapply(configs, `[[`, character(1), "processed_dir"))
  if (length(directories) != 1L) stop("Mode subfeeds must share a processed output directory.")
  parts <- lapply(results, function(result) readRDS(result$processed_path))
  required <- c("mode", "source_subfeed", "source_operator", "snapshot_time_utc", "feed_time_utc")
  for (i in seq_along(parts)) {
    stopifnot(all(required %in% names(parts[[i]])),
              all(parts[[i]]$mode == mode), all(parts[[i]]$source_subfeed == subfeeds[[i]]),
              all(!is.na(parts[[i]]$source_operator) & nzchar(trimws(parts[[i]]$source_operator))),
              nrow(parts[[i]]) == results[[i]]$validation$processed_rows)
  }
  combined <- dplyr::bind_rows(parts)
  stopifnot(nrow(combined) == sum(vapply(parts, nrow, integer(1))),
            all(combined$source_subfeed %in% subfeeds), all(combined$mode == mode),
            setequal(names(combined), unique(unlist(lapply(parts, names), use.names = FALSE))))
  tag <- format(snapshot, "%Y%m%dT%H%M%SZ", tz = "UTC")
  path <- file.path(directories, paste0(mode, "_snapshot_", tag, ".rds"))
  dir.create(directories, recursive = TRUE, showWarnings = FALSE)
  saveRDS(combined, path)
  readr::write_csv(combined, sub("\\.rds$", ".csv", path), na = "")
  list(mode = mode, source_subfeeds = subfeeds, snapshot_time_utc = snapshot,
       processed_path = path, processed_rows = nrow(combined), processed_columns = ncol(combined))
}

run_modes_once <- function(modes = unique(vapply(tfnsw_feeds, `[[`, character(1), "mode")),
                           offline = FALSE, reuse_realtime = FALSE) {
  known <- unique(vapply(tfnsw_feeds, `[[`, character(1), "mode"))
  if (any(!modes %in% known)) stop("Unknown mode. Choose: ", paste(known, collapse = ", "))
  selected <- Filter(function(x) x$mode %in% modes, tfnsw_feeds)
  results <- list()
  failures <- list()
  for (name in names(selected)) {
    result <- tryCatch(run_feed_once(selected[[name]], offline, reuse_realtime),
      error = function(e) {
        # Request helpers sanitize HTTP errors before they reach this layer.
        message("Feed failed: ", name, ": ", conditionMessage(e))
        failures[[name]] <<- conditionMessage(e)
        NULL
      })
    if (!is.null(result)) results[[name]] <- result
    gc(verbose = FALSE)
  }
  mode_outputs <- list()
  for (mode in unique(vapply(selected, `[[`, character(1), "mode"))) {
    configs <- Filter(function(config) config$mode == mode, selected)
    # Existing combined files remain historical artifacts. A failed constituent
    # never produces, or gets linked to, a partial aggregate for this run.
    if (!all(names(configs) %in% names(results))) next
    output <- tryCatch(complete_mode_output(configs, results), error = function(e) {
      message("Mode combination failed: ", mode, ": ", conditionMessage(e))
      failures[[paste0("mode:", mode)]] <<- conditionMessage(e)
      NULL
    })
    if (!is.null(output)) mode_outputs[[mode]] <- output
  }
  dir.create("logs/validation", recursive = TRUE, showWarnings = FALSE)
  for (name in names(results)) {
    mode <- selected[[name]]$mode
    output <- mode_outputs[[mode]]
    results[[name]]$validation$mode_processed_path <- if (is.null(output)) NA_character_ else output$processed_path
    tag <- format(results[[name]]$validation$snapshot_time_utc, "%Y%m%dT%H%M%SZ", tz = "UTC")
    readr::write_csv(results[[name]]$validation,
      file.path("logs/validation", paste0(selected[[name]]$subfeed, "_", tag, ".csv")))
  }
  report <- dplyr::bind_rows(lapply(results, `[[`, "validation"))
  if (!nrow(report)) report <- tibble::tibble(mode = character(), source_subfeed = character(),
    processed_rows = integer(), processed_columns = integer(), processed_path = character(),
    mode_processed_path = character())
  saveRDS(list(validation = report, failures = failures, mode_outputs = mode_outputs),
          "logs/validation/latest_run.rds")
  # Always replace current reports, including runs in which every feed failed.
  readr::write_csv(report, "logs/validation/latest_run.csv")
  failure_report <- tibble::tibble(feed = as.character(names(failures)),
    error = as.character(unlist(failures, use.names = FALSE)))
  readr::write_csv(failure_report, "logs/validation/latest_failures.csv")
  invisible(list(results = results, validation = report, failures = failures, mode_outputs = mode_outputs))
}
