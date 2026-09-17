library(httr2)

# Read TfNSW API key from .Renviron
api_key <- Sys.getenv("TFNSW_API_KEY")

if (!nzchar(api_key)) {
  stop("TFNSW_API_KEY was not found.")
}

url <- "https://api.transport.nsw.gov.au/v2/gtfs/realtime/sydneytrains"

response <- request(url) |>
  req_headers(
    Authorization = paste("apikey", api_key)
  ) |>
  req_perform()

cat("HTTP status:", resp_status(response), "\n")
cat("Content type:", resp_header(response, "content-type"), "\n")
cat("Response size:", length(resp_body_raw(response)), "bytes\n")