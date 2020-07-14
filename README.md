# rubber-soul

[![Build Status](https://travis-ci.com/placeos/rubber-soul.svg?branch=master)](https://travis-ci.com/placeos/rubber-soul)

A small (one might even say 'micro') service that hooks into [rethinkdb-orm](https://github.com/spider-gazelle/rethinkdb-orm) models and generates elasticsearch indicies.  
`rubber-soul` exposes a REST API to reindex/backfill specific models.

## Usage

- Set the tables to be mirrored in ES through setting `RubberSoul::MANAGED_TABLES` with an array of `(T < RethinkORM::Base).class`
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
- `belongs_to` associations are modelled with ES `join` datatypes, associated documents are replicated in their parent's index. This is necessary for `has_parent` and `has_child` queries.

### RethinkDB Mirroring

`RubberSoul::TableManager` hooks into the changefeed of a table, resolves associations of the model and creates/updates documents in the appropriate ES indices.

## Configuration

- `ENV`: a value of `production` lowers log verbosity
- `ES_HOST`: elasticsearch host
- `ES_PORT`: elasticsearch port
- `ES_TLS`: use elasticsearch https, default is `false`
- `ES_URI`: elasticsearch uri, detects whether to use TLS off schema
- `RUBBER_SOUL_HOST`: host to bind server to
- `RUBBER_SOUL_PORT`: port for server to listen on

## Development

Tested against...

- rethinkdb 2.3.6
- elasticsearch 7.0.0

## Contributing

1. [Fork it](https://github.com/aca-labs/rubber-soul/fork)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Caspian Baska](https://github.com/caspiano) - creator and maintainer
