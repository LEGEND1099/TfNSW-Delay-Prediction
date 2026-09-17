# Download/reuse today's train static bundle through the shared acquisition code.
source("config/tfnsw_feeds.R")
source("R/acquisition/tfnsw/acquire_gtfs.R")
gtfs_dir <- acquire_static_gtfs(tfnsw_feeds$train)
