# Rscript R/pipeline/run_all_modes_once.R [all|train|metro|ferry|bus|light_rail] [--offline|--reuse-realtime]
source("R/pipeline/load_pipeline.R")
args <- commandArgs(trailingOnly = TRUE)
requested <- args[!grepl("^--", args)]
if (!length(requested) || identical(requested, "all")) requested <- unique(vapply(tfnsw_feeds, `[[`, character(1), "mode"))
unknown <- setdiff(args[grepl("^--", args)], c("--offline", "--reuse-realtime"))
if (length(unknown)) stop("Unknown option: ", paste(unknown, collapse = ", "))
result <- run_modes_once(requested, offline = "--offline" %in% args, reuse_realtime = "--reuse-realtime" %in% args)
if (length(result$failures)) quit(status = 1L)
