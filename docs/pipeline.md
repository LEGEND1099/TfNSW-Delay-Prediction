# Pipeline operation and data semantics

This guide describes the implemented repository behavior. [Feed configuration](../config/tfnsw_feeds.R) is the source of truth for selected endpoints and scope rules. [Endpoint research](endpoint-research.md) records supporting TfNSW sources; [the validation report](validation-report.md) records the saved snapshots checked during recovery.

## Research population

The project studies selected Greater Sydney metropolitan public transport: Sydney Trains, Sydney Metro, Sydney Ferries, Sydney Buses and Sydney Light Rail.

| Mode | Implemented selection |
|---|---|
| Train | Static route short name T1–T9; headsigns containing “Empty Train” excluded; missing route metadata excluded |
| Metro | Configured Metro feed; observed route identifiers retained |
| Ferry | `sydneyferries` only; other ferry feed families are not acquired |
| Bus | Combined `/buses` feed, excluding Newcastle Transport, regional route type 701, rail replacement route type 714, PCBC/ReplacementBus catalog membership, non-bus and unclassified rows |
| Light Rail | Exactly `innerwest`, `cbdandsoutheast` and `parramatta`; observed routes retained rather than restricted by a hard-coded row count or route list |

Newcastle Transport buses and Newcastle Light Rail are outside the chosen Greater Sydney population. TfNSW's “outer metropolitan” contract category is not a reason to include Newcastle. Separate regional bus feeds are also excluded. Newcastle bus rows present in the combined feed remain in the complete audit with an explicit exclusion reason; Newcastle Light Rail has no configured acquisition endpoint.

Bus scope uses the combined bundle plus operator/service metadata and two static exclusion catalogs. Catalog membership is checked against trip IDs and static/realtime route IDs. The catalogs classify rows already present in the combined realtime feed; their timetable rows are not appended as observations. School route types 712 and 713 remain eligible and receive `is_school_service = TRUE`. An otherwise excluded service is not restored merely because it is a school service.

These bus rules do not apply a stop-level geographic geofence. They therefore do not demonstrate that every retained outer-metropolitan service lies inside a precise Greater Sydney boundary. Any more exact geographic population needs a separately reviewed definition and validation.

## Shared architecture and configured APIs

`R/pipeline/load_pipeline.R` loads configuration and shared acquisition, parsers, integration, scope and validation functions. `run_modes_once()` orchestrates feeds and complete mode outputs; `run_feed_once()` handles a single configured feed. Existing Train scripts are compatibility entry points, not a separate implementation to extend for each mode.

All endpoint paths below are relative to `https://api.transport.nsw.gov.au` and reflect the repository configuration, not a guarantee of future service availability.

| Feed | Static GTFS | GTFS-Realtime Trip Updates |
|---|---|---|
| Sydney Trains | `/v1/gtfs/schedule/sydneytrains` | `/v2/gtfs/realtime/sydneytrains` |
| Sydney Metro | `/v2/gtfs/schedule/metro` | `/v2/gtfs/realtime/metro` |
| Sydney Ferries | `/v1/gtfs/schedule/ferries/sydneyferries` | `/v1/gtfs/realtime/ferries/sydneyferries` |
| Sydney Buses | `/v1/gtfs/schedule/buses` | `/v1/gtfs/realtime/buses` |
| Inner West Light Rail | `/v1/gtfs/schedule/lightrail/innerwest` | `/v2/gtfs/realtime/lightrail/innerwest` |
| CBD & South East Light Rail | `/v1/gtfs/schedule/lightrail/cbdandsoutheast` | `/v1/gtfs/realtime/lightrail/cbdandsoutheast` |
| Parramatta Light Rail | `/v1/gtfs/schedule/lightrail/parramatta` | `/v1/gtfs/realtime/lightrail/parramatta` |

The bus exclusion catalogs use `/v1/gtfs/schedule/buses/PCBC` and `/v1/gtfs/schedule/buses/ReplacementBus`. API versions are selected per endpoint: a v2 realtime feed does not imply that its static endpoint also uses v2. The endpoint research records the Metro v2 transition and Inner West v1 decommissioning that informed these choices.

## Acquisition and reproducible runs

Run commands from the repository root in the `renv` environment recorded by `renv.lock`. `.Rprofile` activates the project environment. Use `renv::restore()` to install the recorded dependencies when needed; RProtoBuf also needs a working installation for the platform.

```sh
# One selected mode using saved inputs
Rscript R/pipeline/run_all_modes_once.R train --offline

# All five modes using saved inputs
Rscript R/pipeline/run_all_modes_once.R all --offline

# Multiple selected modes in one run
Rscript R/pipeline/run_all_modes_once.R metro ferry --offline

# Intentional online acquisition
Rscript R/pipeline/run_all_modes_once.R light_rail

# Prefer an existing realtime payload, with online fallback
Rscript R/pipeline/run_all_modes_once.R bus --reuse-realtime
```

With no mode argument, the CLI selects all configured modes. It returns a nonzero exit status when a feed or mode combination fails.

| Option | Static input | Realtime input | Network behavior |
|---|---|---|---|
| Default | Reuse today's saved static extraction/ZIP if available; otherwise acquire | Acquire a new snapshot | Requires `TFNSW_API_KEY` for requests |
| `--reuse-realtime` | Same as default | Reuse latest nonempty saved `.pb` if available; otherwise acquire | Requests remain possible |
| `--offline` | Reuse saved extraction/ZIP without today's-date restriction | Reuse latest nonempty saved `.pb` | Never download; missing inputs fail the feed |

Cache selection uses filesystem modification time, with the path as a tie-breaker. Offline mode prefers a usable extracted static directory over an archive. It is a convenience selection rule, not a static/realtime version compatibility guarantee. Record the selected `static_directory` and `raw_realtime_path` from validation when reproducing a run. Bus runs also require saved exclusion catalogs in offline mode.

Set `TFNSW_API_KEY` through the process environment or an ignored local `.Renviron`; do not put it in scripts, command history, logs or version control. Requests use an authorization header. The acquisition code sanitizes HTTP errors, bounds retries, disallows redirects and publishes only nonempty successful transfers. It retains failed partial transfers for diagnosis rather than presenting them as valid snapshots.

Acquired raw payloads are never overwritten. Filename collisions get unique names; ZIP extraction checks unsafe or duplicate paths before extracting. Reusing raw files is preferred for debugging. Rebuilding derived outputs for the same snapshot can overwrite those derived files; raw immutability does not imply immutable interim or processed outputs.

## Raw, interim and processed artifacts

Raw paths are configured under `data/raw/<mode>/<subfeed>/`, with Train retaining its existing `data/raw/train/` layout. Static GTFS is stored as ZIPs/extractions; realtime payloads are `.pb` files with UTC collection timestamps in their names. New acquisitions also write metadata with endpoint, timestamps, HTTP status and byte count, without credentials.

The static parser requires `routes.txt`, `trips.txt`, `stop_times.txt` and `stops.txt`. It also reads `agency`, `calendar`, `calendar_dates` and `frequencies` when available. It uses header-aware types, preserves identifiers as strings, retains GTFS time strings including hours beyond 24, and records parsing problems. Missing required data fails parsing. Genuine value parsing problems are reported rather than silently suppressed.

The realtime parser decodes the local [Protobuf schema](../proto/gtfs-realtime.proto) and creates two different tables:

| Table | Unit of observation | Purpose |
|---|---|---|
| TripUpdate summary | One row per entity containing a TripUpdate | Trip descriptor, timestamp, trip-level delay and number of stop updates; retains zero-stop TripUpdates |
| Stop updates | One row per supplied StopTimeUpdate | Stop identity/order, schedule relationship, arrival/departure delays, event times, `scheduled_time` and uncertainty |

Zero-stop TripUpdates do not become artificial stop rows. Entities without TripUpdates do not enter these tables. The runner supports full datasets; differential feeds fail explicitly because they require state reconciliation.

Each feed writes to `data/interim/by_mode/<mode>/<subfeed>/`:

- `<subfeed>_<UTC tag>_trip_summary.rds`: all TripUpdate summaries, with mode, subfeed and snapshot/feed timestamps.
- `<subfeed>_<UTC tag>_stop_updates.rds`: all parsed realtime stop rows before integration.
- `<subfeed>_<UTC tag>_scope_audit.rds`: all integrated realtime stop rows, including unmatched and excluded services, match flags and scope reasons.
- `<subfeed>_<UTC tag>_parsing_problems.rds`: static parsing diagnostics when present.

Processed RDS/CSV files are written to `data/processed/by_mode/<mode>/<subfeed>_snapshot_<UTC tag>.*`. They contain rows with `keep_for_project = TRUE`. A row is not removed merely because its static trip-stop match is absent. Scope rules may exclude an unclassified row, while its full integrated record remains in the audit.

Integrated/audit/processed rows include `mode`, `source_subfeed` and `source_operator`. Operator names come from joined static route/agency metadata and may remain missing when unresolved; the pipeline does not invent attribution. Combined Light Rail requires populated operator attribution for every row. The summary and pre-integration stop tables carry subfeed attribution but do not infer an operator. `source_feed` in parsed stop updates identifies the realtime endpoint; in scoped integrated rows it identifies the static endpoint. Keep that distinction when interpreting provenance.

`snapshot_time_utc` comes from the realtime filename's collection timestamp; `feed_time_utc` comes from the feed header; `trip_update_time_utc` comes from the individual TripUpdate. They describe different times. `snapshot_time_sydney` provides a local display value, while UTC columns retain time values.

## Static linkage, ordering and schedule interpretation

Integration begins with realtime stop rows and preserves their number and order. It uses indexed unique lookups rather than expanding joins. Missing and ambiguous keys remain unresolved, with diagnostic flags; an arbitrary first match is not used to hide duplicate keys.

For scheduled trips, a supplied realtime `stop_sequence` is matched with `trip_id` to the static stop sequence, checking agreement with a supplied `stop_id`. This distinguishes repeated visits to the same stop. Without a supplied scheduled sequence, trip-stop matching requires a unique `trip_id`/`stop_id` pair. A supplied sequence that fails to match is left unresolved. Non-scheduled trips use that diagnostic pair lookup; repeated ambiguous pairs remain unmatched. Duplicate trip, stop, route, trip-stop and trip-sequence keys are reported separately.

Static and realtime route IDs and stop sequences are retained separately. The integrated `route_id` prefers matched static trip metadata and falls back to the realtime route ID. Validation reports both original realtime and integrated/processed route identifiers.

Three kinds of time must remain distinct:

| Concept | Fields/behavior |
|---|---|
| Original static timetable | `static_arrival_time`, `static_departure_time`, `static_stop_sequence`; diagnostic context for non-scheduled journeys |
| Realtime information | Arrival/departure event times, delay fields, uncertainty and optional realtime `scheduled_time` |
| Effective schedule | Explicit `effective_scheduled_*_utc`, `effective_stop_order`, `effective_schedule_source` and missingness flags |

For scheduled trips (explicit schedule relationship 0, or absent relationship interpreted using its default), effective times come from static GTFS plus the realtime service date. GTFS service-time conversion uses local noon minus 12 hours in `Australia/Sydney`, including times after midnight and daylight-saving transitions. Effective order prefers static sequence, then realtime sequence, then supplied update order.

For `REPLACEMENT` trips, the supplied StopTimeUpdate order defines the replacement journey. Static scheduled times remain diagnostic and are never silently adopted as its effective schedule. The effective arrival/departure schedule uses the respective realtime `scheduled_time`. If one is absent, that effective time stays `NA`; `replacement_missing_scheduled_time` identifies rows missing either value. Other non-scheduled relationships likewise do not inherit the original static timetable as an effective baseline.

Absent Protobuf scalar fields remain `NA` and differ from explicitly supplied zero. This includes delay, uncertainty, sequence and schedule relationship fields. Interpreting the default relationship for scheduling does not rewrite the raw absent enum to zero. Missing delays are not imputed, and an event time is not automatically converted into a delay measurement.

`ADDED`, `UNSCHEDULED` and replacement services can legitimately lack a static trip or trip-stop match. The audit retains them with their original relationships. Sydney Ferries' unmatched added/replacement rows remain in processed output when inside its feed scope. A missing-ID unclassified bus update remains auditable even when it cannot establish membership in the processed bus population.

## Complete Sydney Light Rail outputs

`light_rail` always selects the three configured Sydney subfeeds. After all succeed, the runner reads their processed results, checks attribution and dimensions, and binds their rows without deduplicating across subfeeds. Identifiers can overlap between feeds, so retain `source_subfeed` when constructing keys.

The combined RDS/CSV name is `light_rail_snapshot_<UTC tag>.*`, using the latest constituent collection timestamp. Each row keeps its original collection/feed timestamps; the name does not imply simultaneous collection.

If any required subfeed fails, the runner keeps successful constituent outputs and diagnostics but does not write a combined Light Rail result for that run. Its successful constituent validation rows receive `mode_processed_path = NA`; `mode_outputs` has no Light Rail entry. A combination/provenance failure is also recorded as a failure. Historical combined files remain on disk and must not be substituted for the failed run. The CLI exits unsuccessfully.

This is a completeness gate before combining subfeeds. It is not a filesystem transaction across the final RDS and CSV writes. All-empty successful constituents are permitted and produce an empty aggregate with its schema; the mode manifest records the required subfeeds even when they contribute no rows.

## Validation reports and tests

Each successful feed writes a timestamped CSV in `logs/validation/`. Every invocation also replaces:

- `latest_run.rds`: a list of `validation`, `failures` and `mode_outputs`.
- `latest_run.csv`: validation rows for feeds that succeeded in this invocation, including the complete mode path when available.
- `latest_failures.csv`: failed feed/combination names and error messages; header only on success.

A one-mode invocation replaces the latest report with that selected mode's results. An all-feed failure replaces old successful CSV rows with an empty report. Consult the current failures and mode manifest together, not merely the presence of a file from an earlier run.

Reports include mode/subfeed, observed operator names and missing attribution, snapshot/feed timestamps, TripUpdate and zero-stop counts, stop rows, unique trips/stops, arrival/departure delay coverage, trip/stop schedule relationship counts, replacement/missing-schedule counts, static parsing problems, static trip/stop/trip-stop match rates, unmatched counts and relationships, integration row counts, duplicate/ambiguous keys, observed route identifiers, scope exclusion counts, processed dimensions and paths. Trip-summary linkage is reported separately from stop-row linkage.

Match rates and delay coverage are proportions over their respective rows; an empty denominator yields `NA`. Stop-level match rates refer to all integrated rows before scope filtering. Duplicate-key counts describe static rows belonging to duplicate keys, not necessarily multiplied output rows. No universal linkage threshold is imposed: unmatched services and poor coverage must be interpreted and reported honestly. Core validation asserts row preservation and replacement semantics; the saved-snapshot regression additionally requires zero static parsing problems for the selected snapshots.

```sh
# Ten synthetic test scripts plus tracked-file safety checks; no API requests
Rscript tests/run_tests.R

# Rebuild all modes from saved raw inputs and verify outputs/reports
Rscript tests/run_offline_regression.R

# Verify saved outputs against the existing latest full five-mode report
Rscript tests/run_offline_regression.R --check-existing

# Inspect explicitly staged files before a commit
Rscript tests/check_git_safety.R
```

The synthetic suite covers absent fields versus explicit zero, replacement schedules and realtime `scheduled_time`, zero-stop updates, duplicate/repeated stops, row preservation, static parsing, acquisition reuse/immutability, mode scope, Ferry unmatched preservation, Bus Newcastle/contingency exclusions and school flags, Light Rail attribution/configuration, and Git safety. Controlled Light Rail failures assert that successful constituents survive while no partial combined output is published or linked as a current success. Recovery, empty feeds and invalid provenance are also exercised.

The offline regression compares saved summaries, stop updates, audits, processed datasets and mode aggregates with their reports, and checks scope and replacement invariants without fixed snapshot row counts. Its download helper is disabled. `--check-existing` checks artifacts rather than reparsing raw inputs, and requires the latest report to contain all five modes. Results are written to `offline_regression.rds` and `offline_regression.csv` in `logs/validation/`.

## Interpretation and limitations

GTFS-Realtime arrival/departure delay fields are realtime updates or estimates. This pipeline does not establish that they are final realised arrival delays. Missing previous-stop delay is not zero delay. Previous/current stop delay persistence may partly reflect GTFS-R propagation, so repeated or similar values are not automatically independent observations of realised performance. No previous-stop imputation or realised-outcome definition is implemented here.

Saved snapshots from different modes/subfeeds need not be simultaneous. Static and realtime versions may differ; cache reuse alone does not establish compatibility. Missing/ambiguous static links, missing effective replacement schedules and missing operator attribution remain visible. The current parser does not reconcile differential feeds or reconstruct journeys across snapshots. Static calendars/frequencies can be read, but the pipeline does not expand a complete service schedule or synthesise omitted StopTimeUpdates.

Scope is the stated feed/operator/service selection, with the geographic bus limitation above. Output row counts are snapshot dependent, and an empty successful feed is not proof of service coverage. General acquisition validation and synthetic tests do not replace checking current parsing, linkage, timestamps and scope reports.

Raw files, interim data, generated processed snapshots, logs, `.Renviron`, `.env`, and `renv/library/`/`renv/staging/` are ignored. A clean clone cannot reproduce local snapshot counts without the corresponding saved inputs. This stage stops at a validated snapshot pipeline; continuous collection, other data sources and statistical outcome construction remain separate project work.
