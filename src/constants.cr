require "action-controller/logger"
require "secrets-env"

module RubberSoul
  RETHINK_DATABASE = ENV["RETHINKDB_DB"]? || "test"
  APP_NAME         = "rubber-soul"

  Log           = ::Log.for(APP_NAME)
  LOG_STDOUT    = ActionController.default_backend
  LOGSTASH_HOST = ENV["LOGSTASH_HOST"]?
  LOGSTASH_PORT = ENV["LOGSTASH_PORT"]?

  def self.log_backend
    if !(logstash_host = LOGSTASH_HOST.presence).nil?
      logstash_port = LOGSTAH_PORT.try &.to_i? || abort("LOGSTASH_PORT is either malformed or not present in environment')
      # Logstash UDP Input
      logstash = UDPSocket.new
      logstash.connect logstash_host, logstash_port 
      logstash.sync = false

      # debug at the broadcast backend level, however this will be filtered
      # by the bindings
      backend = ::Log::BroadcastBackend.new
      backend.append(LOG_STDOUT, :trace)
      backend.append(ActionController.default_backend(
        io: logstash,
        formatter: ActionController.json_formatter
      ), :trace)
      backend
    else
      LOG_STDOUT
    end
  end

  # calculate version at compile time
  VERSION = {{ `shards version "#{__DIR__}"`.chomp.stringify.downcase }}
  PROD    = (ENV["ENV"]? || ENV["SG_ENV"]?) == "production"

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
