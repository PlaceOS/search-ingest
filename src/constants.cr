require "action-controller/logger"

require "secrets-env"

module SearchIngest
  APP_NAME = "search-ingest"
  # calculate version at compile time
  VERSION = {{ `shards version "#{__DIR__}"`.chomp.stringify.downcase }}

  BUILD_TIME   = {{ system("date -u").stringify }}
  BUILD_COMMIT = {{ env("PLACE_COMMIT") || "DEV" }}

  Log = ::Log.for(self)

  RETHINK_DATABASE = ENV["RETHINKDB_DB"]? || "test"

  class_getter? production : Bool = (ENV["ENV"]? || ENV["SG_ENV"]?).try(&.downcase) == "production"

  # server defaults in `./app.cr`
  HOST = ENV["RETHINKDB_ELASTICSEARCH_INGEST_HOST"]?.presence || "127.0.0.1"
  PORT = ENV["RETHINKDB_ELASTICSEARCH_INGEST_PORT"]?.presence.try(&.to_i) || 3000

  # ES config used in `./search-ingest/elastic.cr`
  ES_DISABLE_BULK      = !!(ENV["ES_DISABLE_BULK"]?.presence.try &.downcase.in?("1", "true"))
  ES_URI               = ENV["ES_URI"]?.try(&->URI.parse(String))
  ES_HOST              = ENV["ES_HOST"]? || "localhost"
  ES_PORT              = ENV["ES_PORT"]?.try(&.to_i) || 9200
  ES_TLS               = ENV["ES_TLS"]? == "true"
  ES_CONN_POOL         = ENV["ES_CONN_POOL"]?.try(&.to_i)
  ES_IDLE_POOL         = ENV["ES_IDLE_POOL"]?.try(&.to_i)
  ES_CONN_POOL_TIMEOUT = ENV["ES_CONN_POOL_TIMEOUT"]?.try(&.to_f64) || 5.0

  # NOTE:: `./search-ingest/client.cr` implements
  # ENV["RETHINKDB_ELASTICSEARCH_INGEST_URI"]? || "http://search-ingest:3000"
  # it is included in other projects
end
