# Compatibility wrapper: use the latest saved Sydney Trains static bundle.
source(file.path("R", "parsing", "read_static_gtfs.R"))

static_root <- file.path("data", "raw", "train", "static_gtfs")
if (!dir.exists(static_root)) {
  stop("Static GTFS directory was not found. Download the static GTFS first.")
}
candidate_dirs <- list.dirs(static_root, recursive = FALSE, full.names = TRUE)
candidate_dirs <- candidate_dirs[
  grepl("sydneytrains_static_gtfs_[0-9]{8}$", candidate_dirs)
]
if (!length(candidate_dirs)) stop("No extracted Sydney Trains GTFS directory was found.")
gtfs_dir <- candidate_dirs[which.max(file.info(candidate_dirs)$mtime)]
cat("Using GTFS directory:", gtfs_dir, "\n")

static_gtfs <- read_static_gtfs(gtfs_dir)
routes <- static_gtfs$routes
trips <- static_gtfs$trips
stop_times <- static_gtfs$stop_times
stops <- static_gtfs$stops
route_problems <- readr::problems(routes)
trip_problems <- readr::problems(trips)
stop_time_problems <- readr::problems(stop_times)
stop_problems <- readr::problems(stops)
total_parsing_problems <- static_gtfs$parsing_problem_count

cat("\nStatic GTFS summary:\n")
for (table in c("routes", "trips", "stop_times", "stops")) {
  cat(" ", table, ": ", nrow(static_gtfs[[table]]), " rows; ",
      nrow(readr::problems(static_gtfs[[table]])), " parsing problems\n", sep = "")
}
cat("  Total parsing problems:", total_parsing_problems, "\n")
