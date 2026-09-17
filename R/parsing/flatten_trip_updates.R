# Compatibility wrapper for the interactive train workflow.
source("R/parsing/read_trip_updates.R")
if (!exists("feed")) stop("Run decode_gtfs_realtime.R first.")
parsed_realtime <- flatten_gtfs_feed(feed)
trip_summary_df <- parsed_realtime$trip_summary_df
trip_updates_df <- parsed_realtime$trip_updates_df
trip_updates_df$update_order <- trip_updates_df$realtime_update_order
cat("TripUpdates:", nrow(trip_summary_df), "zero-stop:", sum(trip_summary_df$number_of_stop_updates == 0L), "stop rows:", nrow(trip_updates_df), "\n")
