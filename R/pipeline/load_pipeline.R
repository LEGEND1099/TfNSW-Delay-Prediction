# Source from the repository root in a renv-activated R session.
for (script in c("config/tfnsw_feeds.R", "R/parsing/read_static_gtfs.R",
                 "R/parsing/read_trip_updates.R", "R/integration/integrate_gtfs.R",
                 "R/processing/process_gtfs.R", "R/utils/validate_gtfs.R",
                 "R/acquisition/tfnsw/acquire_gtfs.R", "R/pipeline/run_pipeline.R")) {
  source(script)
}
