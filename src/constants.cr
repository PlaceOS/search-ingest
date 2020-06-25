require "action-controller/logger"
require "secrets-env"

module RubberSoul
  RETHINK_DATABASE = ENV["RETHINKDB_DB"]? || "test"
  APP_NAME         = "rubber-soul"

  Log         = ::Log.for(APP_NAME)
  LOG_BACKEND = ActionController.default_backend

  # calculate version at compile time
  VERSION = {{ `shards version "#{__DIR__}"`.chomp.stringify.downcase }}
  PROD    = ENV["ENV"]? == "production"

  # server defaults in `./app.cr`
  HOST = ENV["RUBBER_SOUL_HOST"]? || "127.0.0.1"
  PORT = ENV["RUBBER_SOUL_PORT"]?.try(&.to_i) || 3000

  # ES config used in `./rubber-soul/elastic.cr`
  ES_DISABLE_BULK      = !(ENV["ES_DISABLE_BULK"]? == "true")
  ES_URI               = ENV["ES_URI"]?.try(&->URI.parse(String))
  ES_HOST              = ENV["ES_HOST"]? || "localhost"
  ES_PORT              = ENV["ES_PORT"]?.try(&.to_i) || 9200
  ES_TLS               = ENV["ES_TLS"]? == "true"
  ES_CONN_POOL         = ENV["ES_CONN_POOL"]?.try(&.to_i)
  ES_IDLE_POOL         = ENV["ES_IDLE_POOL"]?.try(&.to_i)
  ES_CONN_POOL_TIMEOUT = ENV["ES_CONN_POOL_TIMEOUT"]?.try(&.to_f64) || 5.0

  # NOTE:: `./rubber-soul/client.cr` implements
  # ENV["RUBBER_SOUL_URI"]? || "http://rubber-soul:3000"
  # it is included in other projects
end
