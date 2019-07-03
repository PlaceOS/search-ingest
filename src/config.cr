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
  Engine::Model::Authority,
  Engine::Model::ControlSystem,
  Engine::Model::Driver,
  Engine::Model::Module,
  Engine::Model::Repository,
  Engine::Model::Trigger,
  Engine::Model::TriggerInstance,
  Engine::Model::User,
  Engine::Model::Zone,
]

# Configure logger
RubberSoul::TableManager.configure do |settings|
  settings.logger = ActionController::Base.settings.logger
end

# Log level
unless ENV["SG_ENV"]? == "production"
  ActionController::Base.settings.logger.level = Logger::DEBUG
end
