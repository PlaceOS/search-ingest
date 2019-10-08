require "http"
require "logger"

# Engine Models
require "engine-rest-api/models"

# Application code
require "./api"

# Server required after application controllers
require "action-controller/server"

# Add handlers that should run before your application
ActionController::Server.before(
  HTTP::LogHandler.new(STDOUT),
  HTTP::ErrorHandler.new(ENV["SG_ENV"]? != "production"),
  HTTP::CompressHandler.new
)

# Tables watched by TableManager
# FIXME: This is not ideal. A constant array is required for macro methods
RubberSoul::MANAGED_TABLES = [ # ameba:disable Style/ConstantNames
  ACAEngine::Model::Authority,
  ACAEngine::Model::ControlSystem,
  ACAEngine::Model::Driver,
  ACAEngine::Model::Module,
  ACAEngine::Model::Repository,
  ACAEngine::Model::Trigger,
  ACAEngine::Model::TriggerInstance,
  ACAEngine::Model::User,
  ACAEngine::Model::Zone,
]

# Configure logger
RubberSoul::TableManager.configure do |settings|
  settings.logger = ActionController::Base.settings.logger
end

# Log level
unless ENV["SG_ENV"]? == "production"
  ActionController::Base.settings.logger.level = Logger::DEBUG
end
