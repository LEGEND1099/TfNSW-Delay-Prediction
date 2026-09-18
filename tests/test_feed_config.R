# Guard project population and decommissioned API choices without network calls.
source("config/tfnsw_feeds.R")
feed_modes <- vapply(tfnsw_feeds, `[[`, character(1), "mode")
stopifnot(setequal(unique(feed_modes), c("train", "metro", "ferry", "bus", "light_rail")))
subfeeds <- function(mode) vapply(tfnsw_feeds[feed_modes == mode], `[[`, character(1), "subfeed")
stopifnot(identical(subfeeds("ferry") |> unname(), "sydneyferries"),
          setequal(subfeeds("light_rail"), c("innerwest", "cbdandsoutheast", "parramatta")),
          all(!grepl("regionbuses|newcastle|ferries/MFF", vapply(tfnsw_feeds, `[[`, character(1), "static_endpoint"))),
          tfnsw_feeds$metro$static_api_version == "v2",
          tfnsw_feeds$metro$realtime_api_version == "v2",
          tfnsw_feeds$innerwest$realtime_api_version == "v2")
cat("Five-mode configuration and Sydney subfeed scope tests passed.\n")
