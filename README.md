# TfNSW Delay Prediction

STAT5003 Computational Statistics group project investigating delay severity across the Sydney metropolitan public transport network.

## Transport modes

- Bus
- Sydney Trains
- Sydney Metro
- Light Rail
- Ferry

## Project objective

Construct an integrated dataset from Transport for NSW static GTFS, GTFS-Realtime, service alerts, and environmental data to investigate and classify public transport delay severity.

## Data pipeline

Static GTFS + GTFS-Realtime + Alerts + Weather
? Mode-specific processing
? Integrated dataset
? Exploratory Data Analysis
? Classification modelling

## Project structure

- `R/` — data acquisition, parsing, processing and integration code
- `data/raw/` — original downloaded/API data
- `data/interim/` — partially processed data
- `data/processed/` — analysis-ready datasets
- `analysis/` — feasibility analysis and EDA
- `report/` — STAT5003 Quarto report
- `config/` — non-secret configuration
- `proto/` — GTFS-Realtime Protocol Buffer definitions
- `docs/` — data source and methodology documentation
- `tests/` — validation and code tests

## Security

API credentials are stored locally in `.Renviron` and are never committed to Git.
