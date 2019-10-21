require "option_parser"
require "habitat"
require "rethinkdb-orm"

require "./constants"

# Server defaults
server_host = ENV["RUBBER_SOUL_HOST"]? || "127.0.0.1"
server_port = ENV["RUBBER_SOUL_PORT"]?.try(&.to_i) || 3000

cluster = false
process_count = 1

# Application defaults
backfill = false
reindex = false

# Resource configuration

# Elastic
elastic_host = nil
elastic_port = nil

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
RethinkORM::Connection.configure do |settings|
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
end

# Ensure elastic is available
RubberSoul::Elastic.ensure_elastic!

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
  puts "Launching #{RubberSoul::APP_NAME} v#{RubberSoul::VERSION}"
  # Load routes
  server = ActionController::Server.new(port: server_port, host: server_host)
  # Start clustering
  server.cluster(process_count, "-w", "--workers") if cluster

  terminate = Proc(Signal, Nil).new do |signal|
    puts " > terminating gracefully"
    spawn { server.close }
    signal.ignore
  end

  # Detect ctr-c to shutdown gracefully
  Signal::INT.trap &terminate
  # Docker containers use the term signal
  Signal::TERM.trap &terminate

  # Start the server
  server.run do
    puts "With RethinkDB \"#{rethink_db}\" on #{RethinkORM::Connection.settings.host}:#{RethinkORM::Connection.settings.port}"
    puts "With Elasticsearch on #{RubberSoul::Elastic.settings.host}:#{RubberSoul::Elastic.settings.port}"
    puts "Listening on #{server.print_addresses}"
  end
end

# Application models included in config.
require "./config"
require "./rubber-soul"

# Shutdown message
puts "#{RubberSoul::APP_NAME} signing off :}\n"
