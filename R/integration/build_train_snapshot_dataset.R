source("R/parsing/read_trip_updates.R")
source("R/integration/integrate_gtfs.R")
train_snapshot_df <- integrate_gtfs(trip_updates_df, list(trips = trips, stops = stops, stop_times = stop_times, routes = routes), snapshot_time_utc, feed_time_utc)
cat("Realtime rows:", nrow(trip_updates_df), "integrated:", nrow(train_snapshot_df), "replacement:", sum(train_snapshot_df$is_replacement_trip), "static trip-stop matches:", sum(train_snapshot_df$static_trip_stop_match), "\n")
