# rubber-soul

A small service that hooks into [rethinkdb-orm](https://github.com/spider-gazelle/rethinkdb-orm) models and generates elasticsearch indicies.
Exposes a REST API to reindex/backfill specific models

## Implementation

Each rethinkdb table receives an index
Belongs to association are modelled with _type mappings.  

flow
1. include the mappings manager with your models
1. start spider-gazelle service
1. generates mappings, reindexes es by default (hmm)
1. when document event from rethinkdb occurs, place in document index first then all parents


## Development

Will require rethinkdb and elasticsearch services

## Contributing

1. [Fork it](https://github.com/aca-labs/rubber-soul/fork)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Caspian Baska](https://github.com/Caspiano) - creator and maintainer
