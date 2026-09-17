# Run from the repository root: Rscript tests/test_static_reader.R
source(file.path("R", "parsing", "read_static_gtfs.R"))
fixture_root <- file.path("logs", "tests", "static_reader")
dir.create(fixture_root, recursive = TRUE, showWarnings = FALSE)

write_fixture <- function(table, lines) {
  path <- file.path(fixture_root, paste0(table, ".txt"))
  writeLines(lines, path, useBytes = TRUE)
  path
}
expect_error <- function(expression, pattern) {
  result <- tryCatch(force(expression), error = function(e) e)
  stopifnot(inherits(result, "error"), grepl(pattern, conditionMessage(result)))
}
write_fixture("routes", c("route_id,route_short_name,route_type", "001,01,2"))
write_fixture("trips", c("trip_id,route_id,service_id,shape_id,direction_id,block_id",
                         "00001,001,00002,00003,0,00004"))
write_fixture("stop_times", c("trip_id,stop_id,stop_sequence,arrival_time,departure_time",
                              "00001,00005,1,25:03:00,25:04:00"))
write_fixture("stops", c("stop_id,stop_code,stop_name,parent_station,stop_lat,stop_lon",
                         "00005,00006,01,00007,-33.87,151.21"))
write_fixture("calendar", "service_id,monday,tuesday,wednesday,thursday,friday,saturday,sunday,start_date,end_date")
warnings <- character()
parsed <- withCallingHandlers(read_static_gtfs(fixture_root), warning = function(w) {
  warnings <<- c(warnings, conditionMessage(w))
})
stopifnot(
  length(warnings) == 0L,
  parsed$parsing_problem_count == 0L,
  identical(parsed$routes$route_id, "001"),
  identical(parsed$routes$route_short_name, "01"),
  identical(parsed$trips$trip_id, "00001"),
  identical(parsed$trips$service_id, "00002"),
  identical(parsed$trips$shape_id, "00003"),
  identical(parsed$trips$block_id, "00004"),
  identical(parsed$trips$direction_id, 0L),
  identical(parsed$stops$parent_station, "00007"),
  identical(parsed$stops$stop_name, "01"),
  identical(parsed$stop_times$arrival_time, "25:03:00"),
  identical(parsed$stop_times$departure_time, "25:04:00"),
  is.double(parsed$stops$stop_lat),
  is.integer(parsed$stop_times$stop_sequence),
  is.null(parsed$agency),
  nrow(parsed$calendar) == 0L
)
bad_path <- write_fixture("bad_numeric", c("stop_id,stop_lat", "001,not_a_number"))
bad <- withCallingHandlers(read_gtfs_table(bad_path), warning = function(w) {
  warnings <<- c(warnings, conditionMessage(w))
})
stopifnot(nrow(readr::problems(bad)) == 1L, is.na(bad$stop_lat), length(warnings) > 0L)

# A complete bundle retains diagnostics rather than silently hiding errors.
write_fixture("stops", c("stop_id,stop_lat", "00005,not_a_number"))
bad_bundle <- read_static_gtfs(fixture_root)
stopifnot(bad_bundle$parsing_problem_count == 1L,
          identical(bad_bundle$parsing_problems$table, "stops"))
write_fixture("stops", "stop_id,stop_lat")
expect_error(read_static_gtfs(fixture_root), "no data rows")
write_fixture("stops", c("stop_name", "Example"))
expect_error(read_static_gtfs(fixture_root), "missing required column")
empty_path <- write_fixture("empty", character())
expect_error(read_gtfs_table(empty_path), "empty")
expect_error(read_static_gtfs(file.path(fixture_root, "absent")), "Missing required GTFS")
cat("Static GTFS reader tests passed (malformed fixtures intentionally warn).\n")
