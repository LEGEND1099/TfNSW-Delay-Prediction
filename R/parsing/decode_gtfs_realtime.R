# Decode the latest saved train snapshot without acquiring another payload.
source("config/tfnsw_feeds.R")
source("R/acquisition/tfnsw/acquire_gtfs.R")
source("R/parsing/read_trip_updates.R")
input_file <- acquire_trip_updates(tfnsw_feeds$train, offline = TRUE)
parsed_realtime <- read_trip_updates(input_file)
feed <- parsed_realtime$feed
snapshot_time_utc <- parsed_realtime$snapshot_time_utc
feed_time_utc <- parsed_realtime$feed_time_utc
