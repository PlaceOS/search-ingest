require "action-controller/logger"

require "secrets-env"

module SearchIngest
  APP_NAME = "search-ingest"

  # Calculate version at compile time
  {% begin %}
    VERSION = {{ `shards version "#{__DIR__}"`.chomp.stringify.downcase }}
  {% end %}

  BUILD_TIME   = {{ system("date -u").stringify }}
  BUILD_COMMIT = {{ env("PLACE_COMMIT") || "DEV" }}

  Log = ::Log.for(self)

  PG_DATABASE = ENV["PG_DATABASE"]? || "test"

  class_getter? production : Bool = (ENV["ENV"]? || ENV["SG_ENV"]?).try(&.downcase) == "production"

  # Server defaults in `./app.cr`
  HOST = self.env_with_deprecation("PLACE_SEARCH_INGEST_HOST", "RUBBER_SOUL_HOST") || "127.0.0.1"
  PORT = self.env_with_deprecation("PLACE_SEARCH_INGEST_PORT", "RUBBER_SOUL_PORT").try(&.to_i) || 3000

  # ES config used in `./search-ingest/elastic.cr`
  ES_DISABLE_BULK      = self.boolean_string(self.env_with_deprecation("ELASTIC_DISABLE_BULK", "ES_DISABLE_BULK"))
  ES_TLS               = self.boolean_string(self.env_with_deprecation("ELASTIC_TLS", "ES_TLS"))
  ES_URI               = self.env_with_deprecation("ELASTIC_URI", "ES_URI").try(&->URI.parse(String))
  ES_HOST              = self.env_with_deprecation("ELASTIC_HOST", "ES_HOST") || "localhost"
  ES_PORT              = self.env_with_deprecation("ELASTIC_PORT", "ES_PORT").try(&.to_i) || 9200
  ES_CONN_POOL         = self.env_with_deprecation("ELASTIC_CONN_POOL", "ES_CONN_POOL").try(&.to_i)
  ES_IDLE_POOL         = self.env_with_deprecation("ELASTIC_IDLE_POOL", "ES_IDLE_POOL").try(&.to_i)
  ES_CONN_POOL_TIMEOUT = self.env_with_deprecation("ELASTIC_CONN_POOL_TIMEOUT", "ES_CONN_POOL_TIMEOUT").try(&.to_f64) || 5.0

  # NOTE:: `./search-ingest/client.cr` implements
  # It is included in other projects.
  CLIENT_URI = self.env_with_deprecation("PLACE_SEARCH_INGEST_URI", "RUBBER_SOUL_URI") || "http://search-ingest:3000"

  protected def self.boolean_string(value) : Bool
    !!value.try(&.downcase.in?("1", "true"))
  end

  # The first argument will be treated as the correct environment variable.
  # Presence of follwoing vars will produce warnings.
  protected def self.env_with_deprecation(*args) : String?
    if correct_env = ENV[args.first]?.presence
      return correct_env
    end

    args[1..].each do |env|
      if found = ENV[env]?.presence
        Log.warn { "using deprecated env var #{env}, please use #{args.first}" }
        return found
      end
    end
  end
end
