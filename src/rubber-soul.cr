require "option_parser"

require "./config"
require "./server"

# Server defaults
server_host = ENV["RUBBER_SOUL_HOST"]? || "127.0.0.1"
server_port = ENV["RUBBER_SOUL_PORT"]?.try(&.to_i) || 3000

cluster = false
process_count = 1

# Application defaults
backfill = false
reindex = true
watch = true

# Command line options
OptionParser.parse(ARGV.dup) do |parser|
  parser.banner = "Usage: #{APP_NAME} [arguments]"

  # RubberSoul Options
  parser.on("--backfill", "Perform backfill") { backfill = true }
  parser.on("--reindex", "Perform reindex") { reindex = true }

  # Rethinkdb Options
  parser.on("--rethink-host HOST", "RethinkDB host") do |host|
    RubberSoul::Rethink.settings.host = host
  end
  parser.on("--rethink-port PORT", "RethinkDB port") do |port|
    RubberSoul::Rethink.settings.port = port.to_i
  end

  # Elasticsearch Options
  parser.on("--elastic-host HOST", "Elasticsearch host") do |host|
    RubberSoul::Elastic.settings.host = host
  end
  parser.on("--elastic-port PORT", "Elasticsearch port") do |port|
    RubberSoul::Elastic.settings.port = port.to_i
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
    puts "#{APP_NAME} v#{VERSION}"
    exit 0
  end

  parser.on("-h", "--help", "Show this help") do
    puts parser
    exit 0
  end
end

raise RubberSoul::Error.new("Cannot reindex and backfill tables") if reindex && backfill

puts "Launching #{APP_NAME} v#{VERSION}"

# Ensure services are available
RubberSoul::Elastic.ensure_elastic!
RubberSoul::TableManager.ensure_tables!

# Synchronise ES with RethinkDB changefeeds
RubberSoul::TableManager.watch_tables if watch

# Push all documents in RethinkDB to ES
RubberSoul::TableManager.backfill_tables if backfill

# Recreate ES indexes from existing RethinkDB documents
RubberSoul::TableManager.reindex_tables if reindex

# Run server
RubberSoul::Server.start(server_host, server_port, cluster, process_count)

# Shutdown message
puts "#{APP_NAME} signing off :}\n"
