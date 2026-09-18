# Invalid text bytes cannot bypass credential scanning or disclose scanned text.
# Mock Git and the environment; no real credentials, files, or index mutations.
safety_environment <- new.env(parent = environment())
sys.source("tests/check_git_safety.R", envir = safety_environment)
fixture_content <- character()
fixture_key <- ""
git_calls <- 0L
safety_environment$system2 <- function(command, args, stdout) {
  stopifnot(command == "git", isTRUE(stdout))
  git_calls <<- git_calls + 1L
  if (identical(args, "ls-files") || identical(args,
      c("diff", "--cached", "--name-only", "--diff-filter=ACMR"))) return("synthetic.txt")
  stopifnot(length(args) == 2L, args[1] == "show")
  fixture_content
}
safety_environment$Sys.getenv <- function(x) {
  stopifnot(identical(x, "TFNSW_API_KEY"))
  fixture_key
}
invalid_utf8 <- function(text) {
  result <- rawToChar(c(as.raw(c(255L, 254L)), charToRaw(text)))
  Encoding(result) <- "UTF-8"
  result
}
run_check <- function(staged) {
  warnings <- character()
  messages <- character()
  output <- capture.output(result <- withCallingHandlers(
    tryCatch(safety_environment$check_git_safety(staged = staged), error = function(e) e),
    warning = function(w) {
      warnings <<- c(warnings, conditionMessage(w))
      invokeRestart("muffleWarning")
    },
    message = function(m) {
      messages <<- c(messages, conditionMessage(m))
      invokeRestart("muffleMessage")
    }))
  stopifnot(length(warnings) == 0L, length(messages) == 0L)
  list(result = result, output = output)
}

# Construct a recognizable fake pattern without placing one in tracked source.
synthetic_credential <- paste0("ghp_", strrep("X", 36L))
fixture_content <- invalid_utf8(paste0(" synthetic credential: ", synthetic_credential))
failed <- run_check(staged = TRUE)
stopifnot(inherits(failed$result, "error"), length(failed$output) == 0L,
  identical(conditionMessage(failed$result), "Credential pattern detected; content withheld."),
  !grepl(synthetic_credential, conditionMessage(failed$result), fixed = TRUE, useBytes = TRUE))

# Exact configured-key detection also survives invalid bytes in the same line.
fixture_key <- "synthetic-configured-key-for-testing"
fixture_content <- invalid_utf8(paste0(" synthetic key: ", fixture_key))
failed <- run_check(staged = FALSE)
stopifnot(inherits(failed$result, "error"), length(failed$output) == 0L,
  identical(conditionMessage(failed$result), "Secret detected in Git content; content withheld."),
  !grepl(fixture_key, conditionMessage(failed$result), fixed = TRUE, useBytes = TRUE))

# Harmless content is accepted, including legacy bytes and normal UTF-8 text.
fixture_key <- ""
for (fixture_content in list(invalid_utf8(" harmless legacy text"), "ordinary source text")) {
  accepted <- run_check(staged = FALSE)
  stopifnot(isTRUE(accepted$result), length(accepted$output) == 1L,
    identical(accepted$output, "Git safety check passed: 1 tracked files"))
}
stopifnot(git_calls == 8L)
cat("Git safety byte-safe scanning tests passed.\n")
