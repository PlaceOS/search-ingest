## Unreleased

## v2.1.3 (2022-02-24)

### Refactor

- central build ci ([#57](https://github.com/PlaceOS/search-ingest/pull/57))

## v2.1.2 (2022-01-28)

## v2.1.1 (2022-01-18)

### Feat

- **config**: add Broker model to tables ([#55](https://github.com/PlaceOS/search-ingest/pull/55))
- **config**: add Asset models ([#54](https://github.com/PlaceOS/search-ingest/pull/54))
- **logging**: set log level from environment

## v2.0.3 (2021-11-30)

### Fix

- **schemas**: set string rather than symbol in log

## v2.0.2 (2021-11-30)

### Refactor

- extract model schemas from table manager ([#44](https://github.com/PlaceOS/search-ingest/pull/44))

### Fix

- **elastic**: improve schema diff ([#52](https://github.com/PlaceOS/search-ingest/pull/52))

## v2.0.1 (2021-11-03)

### Fix

- **client**: incorrect type on default arg

## v2.0.0 (2021-10-28)

### Refactor

- rename to `search-ingest` ([#50](https://github.com/PlaceOS/search-ingest/pull/50))

## v1.22.0 (2021-10-14)

### Feat

- **api**: backfill once healthcheck heals ([#48](https://github.com/PlaceOS/search-ingest/pull/48))
- **elastic**: use pool retry ([#46](https://github.com/PlaceOS/search-ingest/pull/46))

### Fix

- **table_manager**: return error code on failure to reindex/backfill ([#47](https://github.com/PlaceOS/search-ingest/pull/47))

## v1.21.0 (2021-09-30)

### Refactor

- use `standard` tokenizer
- **table_manager**: prevent clobbering outer scope
- **constants**: remove redundant logging code

### Fix

- **table_manager**: fields were not merged
- **table_manager**: resolve issues with multi-type fields
- **constants**: ES_DISABLE_BULK preserves previous behaviour

## v1.19.9 (2021-09-10)

### Fix

- **shard.lock**: bump models to include type hints for ApiKey
- typo in dockerfile
- **table_manager**: handle silent changefeed drops
- **table_manager**: use futures for single backfill
- better error logging
- abort on changefeed failure
- **table_manager**: remove subfield
- undefined constant

### Perf

- **table_manager**: sum futures

### Feat

- retry connection to elastic on startup

### Refactor

- messy NoReturn creeping in
- **table_manager**: begin move from NamedTuples

## v1.19.1 (2021-06-08)

### Fix

- **logging**: add rubber_soul namespace
- looser type restriction
- **table_manager**: correct missing mappings
- set Log progname, fix compilation error
- **logging**: register log backend earlier

### Feat

- conform to `PlaceOS::Model::Version`
- add JsonSchema to watched models
- robust healthcheck
- **logging**: use placeos-log-backend

### Refactor

- **logs**: use Log.for(self)

## v1.16.0 (2021-02-16)

### Feat

- add logstash support ([#18](https://github.com/PlaceOS/search-ingest/pull/18))

## v1.15.4 (2021-02-08)

### Fix

- **elastic**: skip duplication to own index
- dev builds
- ignore unmapped relations

## v1.15.1 (2020-12-03)

### Fix

- minor typos
- **table_manager**: use `_document_type` instead of `type`

## v1.14.4 (2020-09-11)

### Fix

- **table-manager**: return counts for bulk_backfill

## v1.14.3 (2020-08-19)

## v1.14.2 (2020-08-14)

### Fix

- **table_manager**: mappings for nilable fields

## v1.14.1 (2020-08-10)

## v1.14.0 (2020-08-10)

### Feat

- **table-manager**: support a single subfield for attributes

### Refactor

- model refresh

## v1.12.3 (2020-07-15)

## v1.12.2 (2020-07-14)

## v1.12.1 (2020-07-08)

### Fix

- **elastic**: include constants

## v1.12.0 (2020-07-02)

### Feat

- add secrets and move ENV vars to constants
- **elastic**: support single requests in addition to the bulk api

### Fix

- use env var directly

## v1.10.5 (2020-06-23)

### Fix

- skip verified tls context

## v1.10.4 (2020-06-22)

### Feat

- **elastic**: support ES_URI env var

## v1.10.3 (2020-06-22)

### Fix

- **api**: correct backfill param check

### Feat

- **elastic**: support tls client

## v1.10.1 (2020-06-19)

### Feat

- **client**: base client implementation
- support Set as a model attribute
- add query analyzer settings to index

### Refactor

- begin migration to promises

### Fix

- **config**: log levels
- **Log**: use `Log#setup`

## v1.8.2 (2020-06-16)

## v1.8.1 (2020-06-02)

### Fix

- correct import for models

## v1.8.0 (2020-06-02)

### Fix

- **LICENSE**: update copyright holder reference

## v1.7.4 (2020-05-13)

## v1.7.3 (2020-05-13)

## v1.7.2 (2020-05-05)

### Fix

- **table_manager**: require "log"

## v1.7.1 (2020-05-01)

## v1.7.0 (2020-04-23)

## v1.6.3 (2020-04-20)

## v1.6.2 (2020-04-20)

## v1.6.1 (2020-04-10)

## v1.6.0 (2020-04-10)

### Fix

- **shard.lock**: bump dependencies
- **table_manager**: resolve type aliases
- **table_manager**: map bools and key-indexed collections

## v1.5.3 (2020-04-06)

### Fix

- **table_manager**: exit watch_table if TableManager has been stopped

## v1.5.2 (2020-03-31)

### Fix

- yield to IO

## v1.5.1 (2020-03-09)

### Refactor

- `ACAEngine` -> `PlaceOS`

## v1.5.0 (2020-02-28)

### Fix

- remove dead require
- **constants**: improved version extraction
- **api**: correct optional param
- **config**: remove redundant imports
- **table_manager**: fiber.yield after spawn

### Feat

- **Dockerfile**: build images using alpine
- **Docker**: create a minimal docker container
- add Settings model
- **version**: grab version from shards.yml
- **logging**: update logging to use action-controller/logger v2.0

### Refactor

- **spawn**: set same_thread in anticipation of multi-threading support
- **config**: update engine models
- Engine -> ACAEngine
