require "option_parser"
require "habitat"
require "rethinkdb-orm"

require "./constants"

# Server defaults
server_host = RubberSoul::HOST
server_port = RubberSoul::PORT

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

# Rethink
rethink_host = nil
rethink_port = nil
rethink_db = RubberSoul::RETHINK_DATABASE

# Command line options
OptionParser.parse(ARGV.dup) do |parser|
  parser.banner = "Usage: #{RubberSoul::APP_NAME} [arguments]"

  # RubberSoul Options
  parser.on("--backfill", "Perform backfill") { backfill = true }
  parser.on("--reindex", "Perform reindex") { reindex = true }

  # Rethinkdb Options,
  # Access through models themselves.
  parser.on("--rethink-host HOST", "RethinkDB host") do |host|
    rethink_host = host
  end
  parser.on("--rethink-port PORT", "RethinkDB port") do |port|
    rethink_port = port.to_i
  end
  parser.on("--rethink-db DB", "RethinkDB database") do |db|
    rethink_db = db
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
    puts "#{RubberSoul::APP_NAME} v#{RubberSoul::VERSION}"
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

# We must configure the RethinkDB connection before including the models...
RethinkORM.configure do |settings|
  rethink_host.try { |host| settings.host = host }
  rethink_port.try { |port| settings.port = port }
  settings.db = rethink_db
end

# Application models included in config.
require "./config"
require "./rubber-soul"

RubberSoul::Elastic.configure do |settings|
  elastic_host.try { |host| settings.host = host }
  elastic_port.try { |port| settings.port = port }
  elastic_tls.try { |tls| settings.tls = tls }
end

begin
  Retriable.retry(
    max_elapsed_time: 1.minutes,
    on_retry: ->(_e : Exception, n : Int32, _t : Time::Span, _i : Time::Span) {
      Log.warn { "attempt #{n} connecting to #{RubberSoul::Elastic.settings.host}:#{RubberSoul::Elastic.settings.port}" }
    }
  ) do
    # Ensure elastic is available
    raise "retry" unless RubberSoul::Elastic.healthy?
  end
rescue
  abort("Failed to connect to Elasticsearch on #{RubberSoul::Elastic.settings.host}:#{RubberSoul::Elastic.settings.port}")
end

# DB and table presence ensured by rethinkdb-orm, within models
if backfill || reindex
  # Perform backfill/reindex and then exit
  table_manager = RubberSoul::TableManager.new(
    watch: false,
    backfill: false
  )

  # Recreate ES indexes from existing RethinkDB documents
  table_manager.reindex_all if reindex

  # Push all documents in RethinkDB to ES
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

  # Start API's TableManager instance
  RubberSoul::Api.table_manager

  # Start the server
  server.run do
    Log.info { "Launching #{RubberSoul::APP_NAME} v#{RubberSoul::VERSION}" }
    Log.info { "With RethinkDB \"#{rethink_db}\" on #{RethinkORM::Connection.settings.host}:#{RethinkORM::Connection.settings.port}" }
    Log.info { "With Elasticsearch on #{RubberSoul::Elastic.settings.host}:#{RubberSoul::Elastic.settings.port}" }
    Log.info { "Mirroring #{RubberSoul::MANAGED_TABLES.map(&.name).sort!.join(", ")}" }
    Log.info { "Listening on #{server.print_addresses}" }
  end
end

# Shutdown message
Log.info { "#{RubberSoul::APP_NAME} signing off" }
