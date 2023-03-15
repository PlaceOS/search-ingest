# PostgreSQL Elasticsearch Ingest Service

[![Build](https://github.com/PlaceOS/search-ingest/actions/workflows/build.yml/badge.svg)](https://github.com/PlaceOS/search-ingest/actions/workflows/build.yml)
[![CI](https://github.com/PlaceOS/search-ingest/actions/workflows/ci.yml/badge.svg)](https://github.com/PlaceOS/search-ingest/actions/workflows/ci.yml)
[![Changelog](https://img.shields.io/badge/Changelog-available-github.svg)](/CHANGELOG.md)

A small (one might even say 'micro') service that hooks into [pg-orm](https://github.com/spider-gazelle/pg-orm) models and generates elasticsearch indices.
`search-ingest` exposes a REST API to reindex/backfill specific models.

## Usage

- Set the tables to be mirrored in ES through setting `SearchIngest::MANAGED_TABLES` with an array of `(T < PgORM::Base).class`
- Configure Elastic client through `ELASTIC_HOST` and `ELASTIC_PORT` env vars, or through switches on the command line
- Configure PostgreSQL connection `PG_DATABASE_URL` env var

### **POST** /api/v1/reindex[?backfill=true]

Deletes indexes and recreates index mappings.
Backfills the indices by default (toggle with backfill boolean).

### **POST** /api/v1/backfill

Backfills all indexes with data from PostgreSQL.

### **GET** /api/v1/healthz

Healthcheck.

### Index Schema

- Each PostgreSQL table receives an ES index, with a mapping generated from the attributes of a [PgORM model](https://github.com/spider-gazelle/pg-orm).
- PgORM attributes can accept a tag `es_type` to specify the correct field datatype for the index schema.
- `belongs_to` associations are modeled with ES `join` datatypes, associated documents are replicated in their parent's index. This is necessary for `has_parent` and `has_child` queries.

### PostgreSQL Mirroring

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
- `PG_DATABASE`: DB to mirror to Elasticsearch, defaults to `"test"`
- `PG_HOST`: Host of PostgreSQL, defaults to `localhost`
- `PG_PORT`: Port of PostgreSQL, defaults to `5432`
- `PG_USER`: PostgreSQL database user, defaults to `postgres`
- `PG_PWD`: PostgreSQL database password, defaults to `""`
- `PLACE_SEARCH_INGEST_HOST`: Host to bind server to
- `PLACE_SEARCH_INGEST_PORT`: Port for server to listen on

## Contributing

See [`CONTRIBUTING.md`](./CONTRIBUTING.md).

## Contributors

- [Caspian Baska](https://github.com/caspiano) - creator and maintainer
