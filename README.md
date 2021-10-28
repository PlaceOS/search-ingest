# RethinkDB Elasticsearch Ingest Service

[![CI](https://github.com/PlaceOS/search-ingest/actions/workflows/ci.yml/badge.svg)](https://github.com/PlaceOS/search-ingest/actions/workflows/ci.yml)
[![Build Dev Image](https://github.com/PlaceOS/search-ingest/actions/workflows/build-dev-image.yml/badge.svg)](https://github.com/PlaceOS/search-ingest/actions/workflows/build-dev-image.yml)

A small (one might even say 'micro') service that hooks into [rethinkdb-orm](https://github.com/spider-gazelle/rethinkdb-orm) models and generates elasticsearch indices.
`search-ingest` exposes a REST API to reindex/backfill specific models.

## Usage

- Set the tables to be mirrored in ES through setting `SearchIngest::MANAGED_TABLES` with an array of `(T < RethinkORM::Base).class`
- Configure Elastic client through `ES_HOST` and `ES_PORT` env vars, or through switches on the command line
- Configure RethinkDB connection `RETHINKDB_HOST` and `RETHINKDB_PORT` env vars

### **POST** /api/v1/reindex[?backfill=true]

Deletes indexes and recreates index mappings.
Backfills the indices by default (toggle with backfill boolean).

### **POST** /api/v1/backfill

Backfills all indexes with data from RethinkDB.

### **GET** /api/v1/healthz

Healthcheck.

### Index Schema

- Each RethinkDB table receives an ES index, with a mapping generated from the attributes of a [RethinkORM model](https://github.com/spider-gazelle/rethinkdb-orm).
- RethinkORM attributes can accept a tag `es_type` to specify the correct field datatype for the index schema.
- `belongs_to` associations are modeled with ES `join` datatypes, associated documents are replicated in their parent's index. This is necessary for `has_parent` and `has_child` queries.

### RethinkDB Mirroring

`SearchIngest::TableManager` hooks into the changefeed of a table, resolves associations of the model and creates/updates documents in the appropriate ES indices.

## Configuration

- `ENV`: A value of `production` lowers log verbosity
- `ES_HOST`: Elasticsearch host
- `ES_PORT`: Elasticsearch port
- `ES_TLS`: Use Elasticsearch https, default is `false`
- `ES_URI`: Elasticsearch uri, detects whether to use TLS off schema
- `ES_DISABLE_BULK`: Use single requests to Elasticsearch instead of the bulk API. Defaults to `false`
- `ES_CONN_POOL_TIMEOUT`: Timeout when checking a connection out of the Elasticsearch connection pool
- `ES_CONN_POOL`: Size of the Elasticsearch connection pool
- `ES_IDLE_POOL`: Maximum number of idle connections in the Elasticsearch connection pool
- `UDP_LOG_HOST`: Host for sending JSON formatted logs to
- `UDP_LOG_PORT`: Port that UDP input service is listening on
- `RETHINKDB_DB`: DB to mirror to Elasticsearch, defaults to `"test"`
- `RETHINKDB_HOST`: Host of RethinkDB, defaults to `localhost`
- `RETHINKDB_PORT`: Port of RethinkDB, defaults to `28015`
- `RETHINKDB_ELASTICSEARCH_INGEST_HOST`: Host to bind server to
- `RETHINKDB_ELASTICSEARCH_INGEST_PORT`: Port for server to listen on

## Development

Tested against...

- RethinkDB 2.4.0
- Elasticsearch 7.6.2

### Environment

- `$ ./test` (run tests and tear down the test environment on exit)
- `$ ./test --watch` (run test suite on change)

## Contributors

- [Caspian Baska](https://github.com/caspiano) - creator and maintainer
