source("config/tfnsw_feeds.R")
source("R/acquisition/tfnsw/acquire_gtfs.R")
output_file <- acquire_trip_updates(tfnsw_feeds$train)
