# Rscript tests/run_tests.R
# All fixtures are synthetic; this runner makes no network/API requests.
test_files <- file.path("tests", c("test_static_reader.R", "test_realtime_integration.R",
                                   "test_scope_validation.R", "test_bus_scope.R",
                                   "test_validation_diagnostics.R", "test_acquisition.R",
                                   "test_feed_config.R", "test_mode_runner.R"))
run_isolated_test <- function(path) {
  test_environment <- new.env(parent = globalenv())
  # Nested source() calls also stay local, so helpers cannot leak between tests.
  test_environment$source <- function(file, local = test_environment, ...) {
    base::source(file, local = local, ...)
  }
  cat("Running", path, "\n")
  sys.source(path, envir = test_environment)
  invisible(TRUE)
}
for (path in test_files) run_isolated_test(path)

# Check ignore rules without creating any secret or generated-data files.
ignored_paths <- c(
  ".Renviron", ".env", "Keys.txt", "data/raw/train/ignore_probe.zip",
  "data/raw/metro/trip_updates/ignore_probe.pb", "ignore_probe.pb",
  "data/interim/by_mode/train/ignore_probe.rds",
  "data/processed/by_mode/train/ignore_probe_20000101T000000Z.csv",
  "data/processed/by_mode/light_rail/ignore_probe_20000101T000000Z.rds",
  "renv/library/ignore_probe", "renv/staging/ignore_probe", "logs/tests/ignore_probe.txt"
)
# system2(input=) writes CRLF on Windows; Git treats the CR as part of a path.
ignore_input <- tempfile()
writeBin(charToRaw(paste0(paste(ignored_paths, collapse = "\n"), "\n")), ignore_input)
ignored_result <- system2("git", c("check-ignore", "--stdin"),
                          stdin = ignore_input, stdout = TRUE, stderr = TRUE)
unlink(ignore_input)
stopifnot(is.null(attr(ignored_result, "status")) || attr(ignored_result, "status") == 0L,
          identical(sort(as.character(ignored_result)), sort(ignored_paths)))
safety_environment <- new.env(parent = globalenv())
sys.source("tests/check_git_safety.R", envir = safety_environment)
stopifnot(isTRUE(safety_environment$check_git_safety(staged = FALSE)))
cat("All", length(test_files), "test scripts and repository safety checks passed.\n")
