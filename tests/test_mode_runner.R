# Exercise orchestration with synthetic saved results; no API or raw feed reads.
run_mode_runner_tests <- function() {
  runner <- new.env(parent = environment())
  sys.source("R/pipeline/run_pipeline.R", envir = runner)
  fixture_parent <- file.path("logs", "tests", "mode_runner")
  dir.create(fixture_parent, recursive = TRUE, showWarnings = FALSE)
  fixture_root <- tempfile("run_", tmpdir = normalizePath(fixture_parent, winslash = "/"))
  dir.create(fixture_root)
  previous_directory <- getwd()
  on.exit(setwd(previous_directory), add = TRUE)
  setwd(fixture_root)
  subfeeds <- c("innerwest", "cbdandsoutheast", "parramatta")
  runner$tfnsw_feeds <- stats::setNames(lapply(subfeeds, function(subfeed) {
    list(mode = "light_rail", subfeed = subfeed, processed_dir = "processed/light_rail")
  }), subfeeds)
  runner$tfnsw_feeds$train <- list(mode = "train", subfeed = "train", processed_dir = "processed/train")
  snapshots <- stats::setNames(as.POSIXct(1789680000 + c(0, 60, 120, 180),
                                         origin = "1970-01-01", tz = "UTC"), c(subfeeds, "train"))
  counts <- stats::setNames(c(2L, 1L, 0L, 1L), c(subfeeds, "train"))
  failures <- character()
  wrong_subfeed <- FALSE
  missing_operator <- NULL
  calls <- character()
  runner$run_feed_once <- function(config, offline = FALSE, reuse_realtime = FALSE) {
    stopifnot(offline, reuse_realtime)
    subfeed <- config$subfeed
    calls <<- c(calls, subfeed)
    if (subfeed %in% failures) stop("Synthetic saved feed is unavailable.")
    n <- counts[[subfeed]]
    value <- tibble::tibble(mode = rep(config$mode, n), source_subfeed = rep(subfeed, n),
      source_operator = rep(paste("Operator", subfeed), n), trip_id = rep("same_trip_id", n),
      entity_id = rep("same_entity_id", n), snapshot_time_utc = rep(snapshots[[subfeed]], n),
      feed_time_utc = rep(snapshots[[subfeed]] - 30, n))
    if (subfeed == "cbdandsoutheast") value$extra_column <- rep(7L, n)
    if (wrong_subfeed && subfeed == "innerwest") value$source_subfeed <- rep("unexpected", n)
    if (!is.null(missing_operator) && subfeed == "innerwest") value$source_operator <- rep(missing_operator, n)
    dir.create(config$processed_dir, recursive = TRUE, showWarnings = FALSE)
    path <- file.path(config$processed_dir, paste0(subfeed, ".rds"))
    saveRDS(value, path)
    validation <- tibble::tibble(mode = config$mode, source_subfeed = subfeed,
      snapshot_time_utc = snapshots[[subfeed]], processed_rows = n,
      processed_columns = ncol(value), processed_path = path)
    list(validation = validation, processed_path = path)
  }
  run <- function(modes = "light_rail") runner$run_modes_once(modes, offline = TRUE, reuse_realtime = TRUE)

  first <- run()
  output <- first$mode_outputs$light_rail
  combined <- readRDS(output$processed_path)
  expected_name <- paste0("light_rail_snapshot_", format(max(snapshots[subfeeds]),
                                                       "%Y%m%dT%H%M%SZ", tz = "UTC"), ".rds")
  stopifnot(!length(first$failures), identical(calls, subfeeds),
            basename(output$processed_path) == expected_name,
            output$processed_rows == 3L, output$processed_columns == ncol(combined),
            nrow(combined) == 3L, length(unique(combined$trip_id)) == 1L,
            identical(combined$source_subfeed, c("innerwest", "innerwest", "cbdandsoutheast")),
            identical(combined$source_operator, paste("Operator", combined$source_subfeed)),
            identical(as.numeric(combined$snapshot_time_utc), as.numeric(snapshots[c(1, 1, 2)])),
            identical(combined$extra_column, c(NA_integer_, NA_integer_, 7L)),
            all(first$validation$mode_processed_path == output$processed_path),
            identical(readRDS("logs/validation/latest_run.rds")$mode_outputs, first$mode_outputs),
            file.exists(sub("\\.rds$", ".csv", output$processed_path)))
  historical_path <- output$processed_path
  historical_hash <- tools::md5sum(historical_path)

  # A single mode exposes its existing per-feed output without a second copy.
  single <- run("train")
  stopifnot(single$mode_outputs$train$processed_path == single$results$train$processed_path,
            single$validation$mode_processed_path == single$results$train$processed_path)

  # All-empty feeds still produce an empty aggregate with the union of columns.
  counts[subfeeds] <- 0L
  snapshots[subfeeds] <- snapshots[subfeeds] + 300
  empty <- run()
  empty_data <- readRDS(empty$mode_outputs$light_rail$processed_path)
  stopifnot(empty$mode_outputs$light_rail$processed_rows == 0L, nrow(empty_data) == 0L,
            "extra_column" %in% names(empty_data), inherits(empty_data$snapshot_time_utc, "POSIXct"))

  # Partial failure preserves successful constituent outputs, creates no new
  # aggregate, and never links to an older successful combined snapshot.
  counts[subfeeds] <- c(1L, 1L, 1L)
  snapshots[subfeeds] <- snapshots[subfeeds] + 300
  failures <- "parramatta"
  files_before <- list.files("processed/light_rail", pattern = "^light_rail_snapshot_")
  partial <- run()
  stopifnot(identical(names(partial$failures), "parramatta"),
            identical(names(partial$results), subfeeds[1:2]), !length(partial$mode_outputs),
            all(is.na(partial$validation$mode_processed_path)),
            all(file.exists(vapply(partial$results, `[[`, character(1), "processed_path"))),
            identical(list.files("processed/light_rail", pattern = "^light_rail_snapshot_"), files_before),
            identical(tools::md5sum(historical_path), historical_hash))
  current_failures <- readr::read_csv("logs/validation/latest_failures.csv", show_col_types = FALSE)
  stopifnot(current_failures$feed == "parramatta",
            current_failures$error == "Synthetic saved feed is unavailable.")

  # An all-feed failure must replace old CSV rows with an explicit empty header.
  failures <- subfeeds
  failed <- run()
  empty_report <- readr::read_csv("logs/validation/latest_run.csv", show_col_types = FALSE)
  stopifnot(!nrow(failed$validation), !nrow(empty_report), "mode_processed_path" %in% names(empty_report),
            length(failed$failures) == 3L, !length(failed$mode_outputs),
            nrow(readr::read_csv("logs/validation/latest_failures.csv", show_col_types = FALSE)) == 3L)

  # Invalid constituent provenance fails combination without losing feed results.
  failures <- character()
  wrong_subfeed <- TRUE
  malformed <- run()
  stopifnot("mode:light_rail" %in% names(malformed$failures),
            length(malformed$results) == 3L, !length(malformed$mode_outputs),
            all(is.na(malformed$validation$mode_processed_path)))
  wrong_subfeed <- FALSE
  # A column alone does not establish attribution: absent/blank operators fail.
  for (missing in c(NA_character_, "", " ")) {
    missing_operator <- missing
    malformed_operator <- run()
    stopifnot("mode:light_rail" %in% names(malformed_operator$failures),
              !length(malformed_operator$mode_outputs),
              all(is.na(malformed_operator$validation$mode_processed_path)),
              identical(list.files("processed/light_rail", pattern = "^light_rail_snapshot_"), files_before))
  }
  missing_operator <- NULL
  recovered <- run()
  stopifnot(!length(recovered$failures), recovered$mode_outputs$light_rail$processed_rows == 3L,
            nrow(readr::read_csv("logs/validation/latest_failures.csv", show_col_types = FALSE)) == 0L)
  cat("Mode runner combination, provenance, empty snapshots, and failure reporting tests passed.\n")
}
run_mode_runner_tests()
