# Five-mode saved-snapshot validation

Recorded on 18 September 2026 using the existing local raw snapshots. All five modes completed offline; no new TfNSW API payload was acquired. These are measured snapshot results, not fixed expected counts, service-frequency estimates, or universal linkage thresholds. Raw/interim/processed artifacts remain local and ignored by Git.

## Processed outputs and linkage

Match rates below use **all realtime stop-level rows before project-scope filtering**. A match is a unique static lookup, not evidence that a realtime update became an observed final outcome.

| Mode / subfeed | Realtime = integrated rows | Processed rows x columns | Static trip match | Static stop match | Static trip-stop match | Unmatched rows |
|---|---:|---:|---:|---:|---:|---:|
| Sydney Trains | 1,330 | 436 x 71 | 100% | 100% | 96.0150% | 53 |
| Sydney Metro | 64 | 64 x 69 | 100% | 100% | 100% | 0 |
| Sydney Ferries | 84 | 84 x 69 | 88.0952% | 100% | 86.9048% | 11 |
| Sydney Buses | 160,705 | 154,450 x 72 | 99.999378% | 100% | 99.999378% | 1 |
| Light Rail: Inner West | 575 | 575 x 69 | 100% | 100% | 100% | 0 |
| Light Rail: CBD & South East | 725 | 725 x 69 | 100% | 100% | 100% | 0 |
| Light Rail: Parramatta | 453 | 453 x 69 | 100% | 100% | 100% | 0 |
| **Combined Sydney Light Rail** | **1,753** | **1,753 x 69** | **100%** | **100%** | **100%** | **0** |

Every static parser reported zero problems. Integration preserved every realtime stop row and its order; no mode experienced join multiplication. The combined Light Rail output is the concatenation of the three required Sydney subfeeds and retains their original collection/feed timestamps.

## Time, table grain, and coverage

All timestamps below are UTC on **17 September 2026** (18 September in Sydney). Collection times differ between modes, so this is not a simultaneous cross-mode sample.

| Subfeed | Collection time | Feed time | TripUpdates | Zero-stop TripUpdates | Unique trips / stops in stop rows | Arrival / departure delay coverage |
|---|---|---|---:|---:|---:|---:|
| sydneytrains | 14:38:41 | 14:38:35 | 404 | 195 | 209 / 409 | 78.3459% / 74.8872% |
| metro | 15:21:15 | 15:21:12 | 4 | 0 | 4 / 21 | 95.3125% / 93.7500% |
| sydneyferries | 15:21:16 | 15:21:01 | 18 | 0 | 18 / 35 | 77.3810% / 78.5714% |
| buses | 20:19:17 | 20:19:15 | 4,501 | 101 | 4,399 / 29,381 | 100% / 100% |
| innerwest | 20:30:44 | 20:30:35 | 25 | 0 | 25 / 44 | 72.0000% / 72.0000% |
| cbdandsoutheast | 20:30:47 | 20:30:38 | 50 | 0 | 50 / 38 | 93.1034% / 93.1034% |
| parramatta | 20:30:49 | 20:30:41 | 30 | 0 | 30 / 32 | 93.3775% / 93.3775% |

Combined Light Rail arrival and departure coverage are both 86.2521%, weighted by stop-row count. Zero-stop updates survive in the TripUpdate summaries and do not create synthetic stop rows. Bus unique-trip counts omit its unmatched update without a trip ID.

| Subfeed | Trip relationship counts | Stop relationship counts |
|---|---|---|
| sydneytrains | SCHEDULED 272; CANCELED 34; REPLACEMENT 92; absent 6 | SCHEDULED 858; absent 472 |
| metro | SCHEDULED 4 | SCHEDULED 64 |
| sydneyferries | SCHEDULED 13; ADDED 3; REPLACEMENT 2 | SCHEDULED 82; SKIPPED 1; NO_DATA 1 |
| buses | SCHEDULED 4,399; UNSCHEDULED 1; CANCELED 101 | SCHEDULED 91,252; SKIPPED 92; NO_DATA 69,361 |
| innerwest | SCHEDULED 25 | SCHEDULED 575 |
| cbdandsoutheast | SCHEDULED 50 | SCHEDULED 725 |
| parramatta | SCHEDULED 30 | SCHEDULED 453 |

Counts describe raw field presence. An absent relationship remains absent in the decoded data even where integration interprets the documented scheduled default. Delay coverage reports field presence; it does not override `NO_DATA`, `SKIPPED`, uncertainty, or other semantics when assessing suitability for later analysis.

## Scope, attribution, and unresolved rows

- **Train:** processed observations contain T1, T2, T4, T5, T6, T8, and T9 in this snapshot. The rule accepts passenger T1-T9; it does not require every line to appear. Empty Train is excluded. All 53 unmatched stop rows are REPLACEMENT updates. Across the full audit, 467 replacement rows have missing realtime scheduled arrival and/or departure fields; the original static timetable remains diagnostic and is not substituted as the replacement schedule.
- **Metro:** M1 is preserved as observed, with full static linkage.
- **Ferry:** only the Sydney Ferries feed is selected. All 84 rows remain processed, including ten unmatched ADDED rows and one REPLACEMENT stop absent from its original static trip. There are 22 replacement rows with missing realtime scheduled arrival and/or departure fields. Observed routes are F1, F3, F4, F5, F6, F8, and F9.
- **Bus:** the audit retains 5,736 `EXCLUDE_NEWCASTLE_OPERATOR` rows, 518 `EXCLUDE_REPLACEMENTBUS` rows, and one `EXCLUDE_UNCLASSIFIED_BUS` row. The last is UNSCHEDULED and has no trip ID; its match remains unresolved. The 154,450 processed rows include 13,505 flagged school-service rows. PCBC and ReplacementBus static catalogs were both reused offline; no additional PCBC exclusion occurred in this snapshot. Regional and rail-replacement route types are excluded by the tested rules.
- **Light Rail:** L1, L2, L3, and L4 are present. Every row retains `source_subfeed` and a populated `source_operator`: Sydney Light Rail for Inner West/CBD & South East, and Parramatta Light Rail for Parramatta. Newcastle Light Rail is outside the configured three-subfeed population. There are no replacement or unmatched rows in these saved Light Rail snapshots.

Bus static stop times include **19,807 rows belonging to repeated trip-stop pairs**, while trip plus stop-sequence keys are unique. The integration uses sequence-aware matching for scheduled services. Other feeds have no duplicate static keys in the reported trip, route, stop, trip-stop, or trip-sequence diagnostics. Ambiguous matches remain unresolved rather than multiplying observations.

The Greater Sydney research population is narrower than TfNSW's administrative outer-metropolitan feed category. The implemented Bus rules explicitly exclude Newcastle and designated non-project services, but are not a geographic stop-coordinate boundary test. See [scope and limitations](pipeline.md) before treating retained rows as a geographic census.

## Validation artifacts and reproducibility

Run from the repository root with the project R environment:

```sh
Rscript tests/run_tests.R
Rscript tests/check_git_safety.R
Rscript tests/run_offline_regression.R
```

The synthetic suite contains ten scripts. It covers optional Protobuf presence versus explicit zero; replacement order and effective schedules; zero-stop summaries; repeated/duplicate keys; static parsing; scope; Ferry unmatched retention; Bus exclusions and school flags; acquisition reuse/immutability; Light Rail provenance and complete-mode output; and byte-safe secret scanning. Malformed-static fixtures intentionally emit parser warnings. This Windows environment also emits locale startup warnings; actual saved static feeds have zero parser problems. `renv::status()` reports a consistent environment; no package or lockfile change was required.

The saved-output regression reprocesses existing raw data with network acquisition disabled, then compares interim summaries, stop rows, full audits, processed tables, schemas, and combined outputs. It tests invariants and scope decisions instead of fixing historical row counts or imposing linkage-rate thresholds. `Rscript tests/run_offline_regression.R --check-existing` checks the latest completed five-mode outputs without decoding raw payloads again.

Synthetic Light Rail orchestration tests deliberately fail one required subfeed, fail all feeds, and corrupt attribution. They confirm no new partial mode output is published as successful, existing historical aggregates are unchanged, and current aggregate references are absent on failure. Successfully empty subfeeds remain represented in the mode manifest.

Machine-readable local evidence is in `logs/validation/latest_run.rds`, `latest_run.csv`, `latest_failures.csv`, and the per-subfeed timestamped CSVs. `latest_run.rds` includes mode output paths and combined dimensions; the CSV reports all seven constituents. Reports include observed operators, missing attribution counts, timestamps, update counts, zero-stop counts, unique IDs, delay coverage, relationships, replacement diagnostics, parsing problems, all three match rates, unmatched counts, pre/post-integration rows, duplicate-key diagnostics, observed route identifiers, dimensions, exclusions, and output paths. The saved-output checker additionally writes `offline_regression.rds` and `offline_regression.csv`.

The combined file for this saved run is `data/processed/by_mode/light_rail/light_rail_snapshot_20260917T203049Z.rds` (with a CSV companion). Per-mode and per-subfeed paths are recorded in the machine-readable report rather than inferred from directory order. A later failed run must be assessed from its current failure report; an older file's presence is not evidence of current success.

GTFS-Realtime delay fields are updates/estimates, not guaranteed final realised arrival delays. Missing previous-stop delay is not zero delay, and apparent previous/current stop persistence may partly reflect GTFS-R propagation. This validation establishes software and snapshot consistency; it does not establish a longitudinal outcome, target, or modelling method.
