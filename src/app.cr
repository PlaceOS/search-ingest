require "option_parser"
require "habitat"
require "pg-orm"

require "./constants"

# Server defaults
server_host = SearchIngest::HOST
server_port = SearchIngest::PORT

cluster = false
process_count = 1

# Application defaults
backfill = false
reindex = false

# Resource configuration

# Elastic
elastic_host = nil
elastic_port = nil
elastic_tls = false

# Postgres
pg_host = ENV["PG_HOST"]?
pg_port = ENV["PG_PORT"]?.try &.to_i
pg_user = ENV["PG_USER"]?
pg_pwd = ENV["PG_PASSWORD"]?
pg_db = ENV["PG_DB"]? || SearchIngest::PG_DATABASE

# Command line options
OptionParser.parse(ARGV.dup) do |parser|
  parser.banner = "Usage: #{SearchIngest::APP_NAME} [arguments]"

  # SearchIngest Options
  parser.on("--backfill", "Perform backfill") { backfill = true }
  parser.on("--reindex", "Perform reindex") { reindex = true }

  # PostgreSQL Options,
  # Access through models themselves.
  parser.on("--pg-host HOST", "PostgreSQL host") do |host|
    pg_host = host
  end
  parser.on("--pg-port PORT", "PostgreSQL port") do |port|
    pg_port = port.to_i
  end
  parser.on("--pg-user USER", "PostgreSQL database user") do |user|
    pg_user = user
  end
  parser.on("--pg-pwd PASSWORD", "PostgreSQL database password") do |pwd|
    pg_pwd = pwd
  end
  parser.on("--pg-db DB", "PostgreSQL database") do |db|
    pg_db = db
  end

  # Elasticsearch Options
  parser.on("--elastic-host HOST", "Elasticsearch host") do |host|
    elastic_host = host
  end
  parser.on("--elastic-port PORT", "Elasticsearch port") do |port|
    elastic_port = port.to_i
  end
  parser.on("--elastic-tls (true|false)", "Elasticsearch tls") do |tls|
    elastic_tls = tls == "true"
  end

  # Spider-gazelle configuration
  parser.on("-b HOST", "--bind=HOST", "Specifies the server host") { |h| server_host = h }
  parser.on("-p PORT", "--port=PORT", "Specifies the server port") { |p| server_port = p.to_i }

  parser.on("-w COUNT", "--workers=COUNT", "Specifies the number of processes to handle requests") do |w|
    cluster = true
    process_count = w.to_i
  end

  parser.on("-r", "--routes", "List the application routes") do
    ActionController::Server.print_routes
    exit 0
  end

  parser.on("-v", "--version", "Display the application version") do
    puts "#{SearchIngest::APP_NAME} v#{SearchIngest::VERSION}"
    exit 0
  end

  parser.on("-c URL", "--curl=URL", "Perform a basic health check by requesting the URL") do |url|
    begin
      response = HTTP::Client.get url
      exit 0 if (200..499).includes? response.status_code
      puts "health check failed, received response code #{response.status_code}"
      exit 1
    rescue error
      error.inspect_with_backtrace(STDOUT)
      exit 2
    end
  end

  parser.on("-d", "--docs", "Outputs OpenAPI documentation for this service") do
    puts ActionController::OpenAPI.generate_open_api_docs(
      title: SearchIngest::APP_NAME,
      version: SearchIngest::VERSION,
      description: "monitors for changes occuring in the database and sends them to elasticsearch"
    ).to_yaml
    exit 0
  end

  parser.on("-h", "--help", "Show this help") do
    puts parser
    exit 0
  end

  parser.invalid_option do |flag|
    STDERR.puts "ERROR: #{flag} unrecognised"
    puts parser
    exit 1
  end
end

# We must configure the PostgreSQL connection before including the models...
# If PG_DATABASE_URL is set, the take that as a sole source of information to configure DB connection
# else fall down to individual settings configured via either env vars or CLI
if (db_url = ENV["PG_DATABASE_URL"]?)
  PgORM::Database.parse(db_url)
else
  PgORM::Database.configure do |settings|
    pg_host.try { |host| settings.host = host }
    pg_port.try { |port| settings.port = port }
    settings.db = pg_db
    pg_user.try { |user| settings.user = user }
    pg_pwd.try { |pwd| settings.password = pwd }
  end
end

# Application models included in config.
require "./config"
require "./search-ingest"

SearchIngest::Elastic.configure do |settings|
  elastic_host.try { |host| settings.host = host }
  elastic_port.try { |port| settings.port = port }
  elastic_tls.try { |tls| settings.tls = tls }
end

SearchIngest.wait_for_elasticsearch

# DB and table presence ensured by pg-orm, within models
if backfill || reindex
  _schemas, tables = SearchIngest.tables(MANAGED_TABLES)

  # Perform backfill/reindex and then exit
  table_manager = SearchIngest::TableManager.new(
    tables,
    watch: false,
    backfill: false
  )

  # Recreate ES indexes from existing PostgreSQL records
  table_manager.reindex_all if reindex

  # Push all records in PostgreSQL to ES
  table_manager.backfill_all if backfill
else
  # Otherwise, run server

  # Load routes
  server = ActionController::Server.new(port: server_port, host: server_host)
  # Start clustering
  server.cluster(process_count, "-w", "--workers") if cluster

  terminate = Proc(Signal, Nil).new do |signal|
    puts " > terminating gracefully"
    spawn(same_thread: true) { server.close }
    signal.ignore
  end

  # Detect ctrl-c to shutdown gracefully
  Signal::INT.trap &terminate
  # Docker containers use the term signal
  Signal::TERM.trap &terminate

  Log.info { "Launching #{SearchIngest::APP_NAME} v#{SearchIngest::VERSION}" }
  Log.info { "With PostgreSQL Database \"#{pg_db}\" on #{PgORM::Database.settings.host}:#{PgORM::Database.settings.port}" }
  Log.info { "With Elasticsearch on #{SearchIngest::Elastic.settings.host}:#{SearchIngest::Elastic.settings.port}" }
  Log.info { "Mirroring #{SearchIngest::MANAGED_TABLES.map(&.name).sort!.join(", ")}" }

  # Start API's TableManager instance
  SearchIngest::Api.table_manager

  # Start the server
  server.run do
    Log.info { "Listening on #{server.print_addresses}" }
  end
end

# Shutdown message
Log.info { "#{SearchIngest::APP_NAME} signing off" }
