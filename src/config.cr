# Engine Models
require "models"

# Tables watched by TableManager
# FIXME: This is not ideal. A constant array is required for macro methods
RubberSoul::MANAGED_TABLES = [
  PlaceOS::Model::Authority,
  PlaceOS::Model::ControlSystem,
  PlaceOS::Model::DoorkeeperApplication,
  PlaceOS::Model::Driver,
  PlaceOS::Model::LdapAuthentication,
  PlaceOS::Model::Module,
  PlaceOS::Model::OAuthAuthentication,
  PlaceOS::Model::Repository,
  PlaceOS::Model::SamlAuthentication,
  PlaceOS::Model::Settings,
  PlaceOS::Model::Trigger,
  PlaceOS::Model::TriggerInstance,
  PlaceOS::Model::User,
  PlaceOS::Model::Zone,
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

log_level = PROD ? Log::Severity::Info : Log::Severity::Debug

# Configure logging
Log.builder.bind "*", :warning, RubberSoul::LOG_BACKEND
Log.builder.bind "action-controller.*", log_level, RubberSoul::LOG_BACKEND
Log.builder.bind "#{RubberSoul::APP_NAME}.*", log_level, RubberSoul::LOG_BACKEND
