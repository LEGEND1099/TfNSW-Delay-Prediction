# Compatibility wrapper: train population rules are shared with the mode runner.
source("config/tfnsw_feeds.R")
source("R/processing/process_gtfs.R")
scoped_train <- scope_gtfs(train_snapshot_df, tfnsw_feeds$train)
train_scope_audit_df <- scoped_train$audit
sydney_trains_snapshot_df <- scoped_train$processed
snapshot_tag <- format(snapshot_time_utc, "%Y%m%dT%H%M%SZ", tz = "UTC")
interim_dir <- "data/interim/by_mode/train"
processed_dir <- "data/processed/by_mode/train"
dir.create(interim_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(processed_dir, recursive = TRUE, showWarnings = FALSE)
readr::write_csv(train_scope_audit_df, file.path(interim_dir, paste0("train_integrated_all_", snapshot_tag, ".csv")))
readr::write_csv(sydney_trains_snapshot_df, file.path(processed_dir, paste0("sydney_trains_snapshot_", snapshot_tag, ".csv")))
cat("Train passenger T1-T9:", nrow(sydney_trains_snapshot_df), "rows x", ncol(sydney_trains_snapshot_df), "columns\n")
