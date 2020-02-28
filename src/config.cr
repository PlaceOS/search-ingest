# Engine Models
require "engine-models"

# Tables watched by TableManager
# FIXME: This is not ideal. A constant array is required for macro methods
RubberSoul::MANAGED_TABLES = [ # ameba:disable Style/ConstantNames
  ACAEngine::Model::Authority,
  ACAEngine::Model::ControlSystem,
  ACAEngine::Model::Driver,
  ACAEngine::Model::Module,
  ACAEngine::Model::Repository,
  ACAEngine::Model::Settings,
  ACAEngine::Model::Trigger,
  ACAEngine::Model::TriggerInstance,
  ACAEngine::Model::User,
  ACAEngine::Model::Zone,
]

# Application code
require "./api"

# Server
require "action-controller"
require "action-controller/server"

PROD = ENV["SG_ENV"]? == "production"

# Add handlers that should run before your application
ActionController::Server.before(
  HTTP::ErrorHandler.new(!PROD),
  ActionController::LogHandler.new,
  HTTP::CompressHandler.new
)

# Configure logger
logger = ActionController::Base.settings.logger
logger.level = PROD ? Logger::INFO : Logger::DEBUG

RubberSoul::TableManager.configure do |settings|
  settings.logger = logger
end
