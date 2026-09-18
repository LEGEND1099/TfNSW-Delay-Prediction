# TfNSW endpoint verification

Research notes recovered from the interrupted session, dated 18 September 2026. This continuation rechecked the official Metro and Inner West version-transition notices and reproduced all configured feeds from saved payloads without new authenticated TfNSW requests. Other catalog notes below preserve the earlier dated research; they are not a guarantee of present endpoint availability. The earlier research reported that some portal pages returned HTTP 403, with documentation visible through the public search index. See the [offline validation report](validation-report.md) for measured compatibility and scope results.

All paths below use `https://api.transport.nsw.gov.au`.

| Feed | Static GTFS path | Trip Updates path |
|---|---|---|
| Sydney Trains | `/v1/gtfs/schedule/sydneytrains` | `/v2/gtfs/realtime/sydneytrains` |
| Sydney Metro | `/v2/gtfs/schedule/metro` | `/v2/gtfs/realtime/metro` |
| Sydney Ferries | `/v1/gtfs/schedule/ferries/sydneyferries` | `/v1/gtfs/realtime/ferries/sydneyferries` |
| Combined buses | `/v1/gtfs/schedule/buses` | `/v1/gtfs/realtime/buses` |
| Inner West Light Rail | `/v1/gtfs/schedule/lightrail/innerwest` | `/v2/gtfs/realtime/lightrail/innerwest` |
| CBD and South East Light Rail | `/v1/gtfs/schedule/lightrail/cbdandsoutheast` | `/v1/gtfs/realtime/lightrail/cbdandsoutheast` |
| Parramatta Light Rail | `/v1/gtfs/schedule/lightrail/parramatta` | `/v1/gtfs/realtime/lightrail/parramatta` |

The [official static API Swagger](https://opendata.transport.nsw.gov.au/dataset/public-transport-timetables-realtime/resource/9b3bfa13-0053-4008-8575-e30151f05d54/view/2c71bc94-97cd-457c-ba6e-4e5758bc0ecd) documents the v1 static paths. Its linked specification is [getschedule-busextension_2.5.json](https://opendata.transport.nsw.gov.au/data/dataset/b4b3601a-93f8-4ab8-8482-f73029a59f53/resource/9b3bfa13-0053-4008-8575-e30151f05d54/download/getschedule-busextension_2.5.json).

## Version and population decisions

- Metro v2 static and realtime paths are explicitly announced in the [PTMS Metro transition notice](https://opendataforum.transport.nsw.gov.au/t/ptms-sydney-metro-v2-gtfs-feed/4075). Metro v1 is a legacy interface. Route identifiers and names must come from the current data.
- Inner West realtime moved to v2, with v1 decommissioning on 30 October 2025. The change covered Trip Updates and Vehicle Positions; the current static Swagger still documents the v1 static path. See the [official realtime v2 announcement](https://opendataforum.transport.nsw.gov.au/t/public-transport-realtime-trip-update-v2/2549).
- Sydney Ferries has its own static/realtime family, confirmed by the [completed Sydney Ferries transition](https://opendataforum.transport.nsw.gov.au/t/sydney-ferries-realtime-feed-transition/1851). The static Swagger lists Manly Fast Ferry separately as `ferries/MFF`; it is outside this project's selected feed.
- The [CBD/South East announcement](https://opendataforum.transport.nsw.gov.au/t/cbd-and-south-east-light-rail-real-time-data-now-available/2290) confirms both paths and historically mentions L2/L3/LX. This supports keeping actual route metadata rather than filtering only hard-coded L2/L3 values. Its extra protobuf extension concerns vehicle information; that feature is outside this task.
- The [Parramatta production announcement](https://opendataforum.transport.nsw.gov.au/t/parramatta-light-rail-go-live-date/4795) confirms both production paths and live service from 20 December 2024. Combine only these three Sydney light-rail subfeeds; retain `source_subfeed`. Newcastle Light Rail is a separate endpoint and is excluded.

## Buses: current feeds and scope cautions

TfNSW's [general documentation](https://opendata.transport.nsw.gov.au/developers/documentation) identifies the bus timetable population as metropolitan and outer-metropolitan contracts plus NightRide and Olympic Park event contracts. It describes a combined bus bundle as well as individual operator bundles. Use the timetable-for-realtime bundle for realtime trip matching; the complete all-mode GTFS is a different product.

The current [API status inventory](https://opendata.transport.nsw.gov.au/tfnsw-apistatus), corroborated by the static Swagger, lists these operator timetable suffixes under `/v1/gtfs/schedule/buses/`:

| Family | Current documented suffixes |
|---|---|
| Greater Sydney | `GSBC001`, `GSBC002`, `GSBC003`, `GSBC004`, `SBSC006`, `GSBC007`, `GSBC008`, `GSBC009`, `GSBC010`, `GSBC014` |
| Outer metropolitan | `OSMBSC001`, `OSMBSC002`, `OSMBSC003`, `OSMBSC004`, `OMBSC006`, `OMBSC007`, `OSMBSC008`, `OSMBSC009`, `OSMBSC010`, `OSMBSC011`, `OSMBSC012` |
| Other explicitly listed bus bundles | `NISC001`, `ReplacementBus` |

In particular, do not restore an old `SMBSC001`/`SMBSC002`/`SMBSC004`/`SMBSC013`/`SMBSC015` list or old `OSMBSC006`/`OSMBSC007` names. Current inventories use the suffixes above. The [Outer Metro region 6 transition notice](https://opendataforum.transport.nsw.gov.au/t/new-bus-contract-and-gtfs-data-for-outer-metro-region-6-from-28-july-2024/4433) explicitly identifies `OMBSC006`, agency `2606`, and confirms its inclusion in the combined bundle.

Two important scope complications remain:

1. On 10 September 2026 TfNSW announced `/v1/gtfs/schedule/buses/PCBC` for planned contingency buses. Those services share `/v1/gtfs/realtime/buses`. This is newer than the indexed static Swagger, so the Swagger inventory alone is insufficient. The project's implemented decision excludes PCBC and ReplacementBus catalog matches from processed data while preserving them in the audit with explicit reasons. These catalogs are static-only scope references, not extra passenger feeds. See the [official PCBC announcement](https://opendataforum.transport.nsw.gov.au/t/new-schedule-endpoint-for-planned-contingency-bus-services/10471).
2. TfNSW explicitly confirms that Newcastle Transport buses are in the combined realtime `/buses` feed in its [Newcastle bus reply](https://opendataforum.transport.nsw.gov.au/t/transport-nsw-newcastle-buses-real-time-data/2807). `NISC001` is listed alongside outer metropolitan operators in the [older bus technical document](https://opendata.transport.nsw.gov.au/sites/default/files/2023-08/TfNSW_Realtime_Bus_Technical_Doc_v3.9.pdf). The project population is Greater Sydney: Newcastle Transport buses and Newcastle Light Rail are explicitly excluded. “Outer metropolitan” is an administrative feed category, not permission to include Newcastle. Bus rows remain in the audit as `EXCLUDE_NEWCASTLE_OPERATOR`; the separate Newcastle Light Rail and regional `regionbuses/newcastlehunter` feeds are not acquired.

Regional TCB services have distinct `/regionbuses/...` timetable and realtime families. Do not acquire these to fill unmatched metropolitan records.

The current bus scope is implemented through feed, operator, route-type, and contingency-catalog rules. It does not perform a stop-coordinate geofence; these rules alone are not proof that every retained outer-metropolitan service lies inside a formal Greater Sydney boundary.

The [agency reference table](https://opendata.transport.nsw.gov.au/dataset/reference-tables-tfnsw-gtfs-feeds) was updated on 14 September 2026 for PCBC. Its CSV download requires a portal login in the indexed public page, so this research did not obtain or infer the latest complete agency-ID mapping. Read operator identity from the actual `agency.txt`/`routes.txt` data and retain that provenance. The current status page supplies operator names when interpreting contract suffixes.

## Join and interpretation checks

- Start with one combined bus static download and one realtime snapshot. Measure trip, stop and trip-stop match rates before deciding that operator downloads are needed. A poor rate is evidence to investigate, not permission to transform IDs heuristically.
- Inspect the bundle structure. If multiple contract filesets are combined, preserve `source_feed` and agency/operator metadata. Local identifiers such as `service_id` may be unique only within a contract fileset, so joining or deduplicating solely on such an identifier can corrupt schedules.
- Realtime can contain added, replacement or other unmatched trips. Preserve these and report them; a complete static match is not a defensible universal success threshold.
- Inspect duplicate keys before joining. Repeated stops on a trip require sequence-aware matching, and repeated trips can represent distinct dates or start times. Any join must preserve the realtime row count.
- The official [reference-table guidance](https://opendata.transport.nsw.gov.au/dataset/reference-tables-tfnsw-gtfs-feeds) explains that frequency services may adjust to headway despite an operational timetable. Delay fields remain realtime updates and should not be described as independently observed final arrival delays.

This document verifies feed selection and records decisions to validate. It is not an end-to-end API validation report; generated pipeline reports provide snapshot counts, parsing problems, match rates and scope exclusions.
