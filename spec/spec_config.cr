# Application dependencies
require "action-controller"
require "placeos-log-backend"
require "./spec_models"

# stdlib
require "http"

# Application code
require "../src/api"
require "../src/rubber-soul"
require "../src/constants"

# Server required after application controllers
require "action-controller/server"

# Add handlers that should run before your application
ActionController::Server.before(
  HTTP::LogHandler.new,
  HTTP::ErrorHandler.new(RubberSoul.production?),
  HTTP::CompressHandler.new
)

log_level = RubberSoul.production? ? Log::Severity::Info : Log::Severity::Debug

# Configure logging
::Log.setup "*", log_level, PlaceOS::LogBackend.log_backend
::Log.builder.bind "action-controller.*", log_level, PlaceOS::LogBackend.log_backend
::Log.builder.bind "#{RubberSoul::APP_NAME}.*", log_level, PlaceOS::LogBackend.log_backend
