# TfNSW Greater Sydney GTFS research pipeline

STAT5003 Computational Statistics project. This repository acquires, parses, integrates and validates static GTFS timetables and GTFS-Realtime Trip Updates for five selected Greater Sydney public transport modes:

| Mode | Project population |
|---|---|
| Sydney Trains | Passenger T1–T9 services; Empty Train services excluded |
| Sydney Metro | Configured Metro feed |
| Sydney Ferries | Sydney Ferries feed |
| Sydney Buses | Combined bus feed with explicit operator and service exclusions; eligible school services included and flagged |
| Sydney Light Rail | Inner West, CBD & South East, and Parramatta subfeeds |

Newcastle Transport buses, Newcastle Light Rail, regional bus feeds, and replacement/contingency bus services are outside this project population. TfNSW's administrative term “outer metropolitan” does not establish project membership. Excluded bus rows remain in audit outputs with reasons. The current bus rules use feed, operator and service metadata; they do not implement a geographic stop boundary.

The implemented pipeline is:

```text
Saved static GTFS + saved GTFS-Realtime Trip Updates
  -> static tables + TripUpdate summaries + stop-level updates
  -> row-preserving integration and scope audit
  -> processed datasets by mode + validation reports
```

All modes share the same pipeline, driven by [config/tfnsw_feeds.R](config/tfnsw_feeds.R). Sydney Light Rail is published as a combined mode only after all three required subfeeds succeed. Every combined row retains its subfeed, operator and original timestamps.

GTFS-Realtime delay fields are realtime updates/estimates, not guaranteed final realised arrival delays. Replacement journeys use realtime stop order and realtime `scheduled_time` when available; the original static timetable remains diagnostic. Missing values remain missing, including missing previous-stop delays. Apparent persistence between previous/current stop delays may partly reflect GTFS-R propagation.

## Run from the repository root

Use the R environment recorded in `renv.lock` (R 4.6.1). Start R normally so `.Rprofile` activates `renv`; restore dependencies if needed:

```r
renv::restore()
```

Run a single mode or all five using existing saved raw snapshots:

```sh
Rscript R/pipeline/run_all_modes_once.R light_rail --offline
Rscript R/pipeline/run_all_modes_once.R all --offline
```

`--offline` never downloads missing inputs and fails the affected feed if its saved inputs are unavailable. Saved raw files are intentionally excluded from Git, so a fresh clone needs local inputs or an initial acquisition.

For an intentional online run, provide `TFNSW_API_KEY` in the R process environment or an ignored local `.Renviron`, then run:

```sh
Rscript R/pipeline/run_all_modes_once.R train
```

The default reuses today's static data where available and downloads a new realtime snapshot. `--reuse-realtime` reuses saved realtime data if available but can still make API requests; only `--offline` disables acquisition. See [the pipeline guide](docs/pipeline.md) for cache selection, outputs and failure handling.

## Validate

```sh
Rscript tests/run_tests.R
Rscript tests/run_offline_regression.R
```

The first command runs ten synthetic test scripts and repository safety checks without API calls. The second rebuilds all five modes from saved raw inputs and checks the resulting reports and artifacts. To check existing saved outputs against the latest full five-mode report without rebuilding them:

```sh
Rscript tests/run_offline_regression.R --check-existing
```

Current run results are in `logs/validation/latest_run.rds`, `latest_run.csv` and `latest_failures.csv`. Use the report's `mode_processed_path` to select a complete mode output; an older combined file on disk does not establish that the latest run succeeded. See [the recorded validation report](docs/validation-report.md) for the checked snapshots and measured results.

## Repository layout and security

| Path | Purpose |
|---|---|
| `R/acquisition/tfnsw/` | Shared acquisition and thin Train compatibility scripts |
| `R/parsing/`, `R/integration/`, `R/processing/` | Decode, join and scope all modes |
| `R/pipeline/`, `R/utils/` | Orchestration and validation |
| `config/`, `proto/` | Public feed configuration and Protobuf schema |
| `data/raw/` | Immutable acquired payloads, metadata and extracted static data; ignored |
| `data/interim/` | Trip summaries, stop updates and complete scope audits; ignored |
| `data/processed/by_mode/` | Generated RDS/CSV snapshots; ignored |
| `logs/validation/` | Generated validation and failure reports; ignored |
| `tests/`, `docs/` | Synthetic tests, offline regression and methodology notes |

Never commit credentials, `.Renviron`, `.env`, raw payloads, generated snapshots, logs or local `renv` libraries. Before a commit, stage explicit source/documentation paths, run the tests, and run `Rscript tests/check_git_safety.R` to inspect staged files. The safety check reports failures without printing matched secret content.

Read [pipeline semantics and limitations](docs/pipeline.md), [endpoint research](docs/endpoint-research.md), and [validated results](docs/validation-report.md). This stage provides a reproducible snapshot pipeline; it does not implement continuous collection or establish a realised delay outcome.
