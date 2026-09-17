run_feed_once <- function(config, offline = FALSE, reuse_realtime = FALSE) {
  static_dir <- acquire_static_gtfs(config, reuse = TRUE, offline = offline)
  realtime_path <- acquire_trip_updates(config, reuse = reuse_realtime, offline = offline)
  cat("Parsing", config$mode, config$subfeed, "from saved files\n")
  static <- read_static_gtfs(static_dir)
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
  saveRDS(parsed$trip_updates_df, paste0(prefix, "_stop_updates.rds"))
  saveRDS(scoped$audit, paste0(prefix, "_scope_audit.rds"))
  if (static$parsing_problem_count > 0L) saveRDS(static$parsing_problems, paste0(prefix, "_parsing_problems.rds"))
  processed_path <- file.path(config$processed_dir, paste0(config$subfeed, "_snapshot_", tag, ".rds"))
  saveRDS(scoped$processed, processed_path)
  readr::write_csv(scoped$processed, sub("\\.rds$", ".csv", processed_path), na = "")
  validation$static_directory <- static_dir
  validation$raw_realtime_path <- realtime_path
  validation$processed_path <- processed_path
  readr::write_csv(validation, file.path("logs/validation", paste0(config$subfeed, "_", tag, ".csv")))
  print(validation[, c("mode", "source_subfeed", "stop_level_rows", "processed_rows",
    "static_trip_match_rate", "static_stop_match_rate", "static_trip_stop_match_rate")], width = Inf)
  list(validation = validation, processed_path = processed_path)
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
  report <- dplyr::bind_rows(lapply(results, `[[`, "validation"))
  dir.create("logs/validation", recursive = TRUE, showWarnings = FALSE)
  saveRDS(list(validation = report, failures = failures), "logs/validation/latest_run.rds")
  if (nrow(report)) readr::write_csv(report, "logs/validation/latest_run.csv")
  invisible(list(results = results, validation = report, failures = failures))
}
