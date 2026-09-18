# Run after explicit git add and before every commit. Never prints matched text.
check_git_safety <- function(staged = TRUE) {
  paths <- system2("git", if (staged) c("diff", "--cached", "--name-only", "--diff-filter=ACMR") else "ls-files", stdout = TRUE)
  forbidden <- "(^|/)(\\.Renviron|\\.env|Keys\\.txt)$|\\.(pb|pbf|zip)$|^data/(raw|interim)/|^data/processed/.*\\.(csv|rds|RData)$|^renv/(library|staging)/|^logs/"
  if (any(grepl(forbidden, paths, ignore.case = TRUE, useBytes = TRUE))) stop("Unsafe generated or secret path is versioned/staged.")
  key <- Sys.getenv("TFNSW_API_KEY")
  for (path in paths) {
    content <- system2("git", c("show", shQuote(paste0(":", path))), stdout = TRUE)
    if (!is.null(attr(content, "status")) && attr(content, "status") != 0L) stop("Could not inspect Git content.")
    # Scan bytes: legacy text encodings must neither skip credentials nor cause
    # grepl to echo the inspected content in an invalid-encoding warning.
    if (nzchar(key) && any(grepl(key, content, fixed = TRUE, useBytes = TRUE))) stop("Secret detected in Git content; content withheld.")
    if (any(grepl("^-----BEGIN [A-Z ]*PRIVATE KEY-----$|gh[pousr]_[A-Za-z0-9]{30,}|sk-[A-Za-z0-9]{30,}", content, useBytes = TRUE))) {
      stop("Credential pattern detected; content withheld.")
    }
  }
  cat("Git safety check passed:", length(paths), if (staged) "staged files\n" else "tracked files\n")
  invisible(TRUE)
}
if (sys.nframe() == 0L) check_git_safety()
