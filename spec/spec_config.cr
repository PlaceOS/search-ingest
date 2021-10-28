# Application dependencies
require "action-controller"
require "placeos-log-backend"
require "./spec_models"

# stdlib
require "http"

# Application code
require "../src/api"
require "../src/search-ingest"
require "../src/constants"

# Server required after application controllers
require "action-controller/server"

# Add handlers that should run before your application
ActionController::Server.before(
  HTTP::LogHandler.new,
  HTTP::ErrorHandler.new(SearchIngest.production?),
  HTTP::CompressHandler.new
)

log_level = SearchIngest.production? ? Log::Severity::Info : Log::Severity::Debug

# Configure logging
::Log.setup "*", log_level, PlaceOS::LogBackend.log_backend
::Log.builder.bind "action-controller.*", log_level, PlaceOS::LogBackend.log_backend
::Log.builder.bind "#{SearchIngest::APP_NAME}.*", log_level, PlaceOS::LogBackend.log_backend
