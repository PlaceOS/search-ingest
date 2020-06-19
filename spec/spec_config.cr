# Application dependencies
require "action-controller"
require "./spec_models"

# stdlib
require "http"
require "logger"

# Application code
require "../src/api"
require "../src/rubber-soul"
require "../src/constants"

# Server required after application controllers
require "action-controller/server"

# Add handlers that should run before your application
ActionController::Server.before(
  HTTP::LogHandler.new,
  HTTP::ErrorHandler.new(RubberSoul::PROD),
  HTTP::CompressHandler.new
)

log_level = RubberSoul::PROD ? Log::Severity::Info : Log::Severity::Debug

# Configure logging
::Log.setup "*", log_level, RubberSoul::LOG_BACKEND
