# rubber-soul

A small service that hooks into [rethinkdb-orm](https://github.com/spider-gazelle/rethinkdb-orm) models and generates elasticsearch indicies.
Exposes a REST API to reindex/backfill specific models

## Usage

Set the tables to be mirrored in ES through setting `RubberSoul::MANAGED_TABLES` with an array of `(T < RethinkORM::Base).class`

## Implementation

- Each rethinkdb table receives an index mapping.
- `belongs_to` association are modelled with `join` datatypes, associated documents are mirrored beneath the parent document.
- Hooks into the changefeed of a table, resolves associations and places the document into the correct document indices.

## Development

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
