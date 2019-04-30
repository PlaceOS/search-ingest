# Application dependencies
require "action-controller"
require "engine-models"

# stdlib
require "http"
require "logger"

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
# FIXME: This is not ideal, however a constant array is required for macro methods

RubberSoul::MANAGED_TABLES = [ # ameba:disable Style/ConstantNames
  Engine::Model::ControlSystem,
  Engine::Model::Dependency,
  Engine::Model::DriverRepo,
  Engine::Model::Module,
  Engine::Model::Trigger,
  Engine::Model::TriggerInstance,
  Engine::Model::Zone,
]

RubberSoul::TableManager.configure do |settings|
  settings.logger = ActionController::Base.settings.logger
end

# ACA engine configuration... necessary if using models?
ACA_ENGINE_DB = "engine"

APP_NAME = "rubber-soul"
VERSION  = "1.0.0"
