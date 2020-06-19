# Engine Models
require "placeos-models"

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
require "./constants"

# Server
require "action-controller"
require "action-controller/server"

# Add handlers that should run before your application
ActionController::Server.before(
  HTTP::ErrorHandler.new(RubberSoul::PROD),
  ActionController::LogHandler.new,
  HTTP::CompressHandler.new
)

log_level = RubberSoul::PROD ? Log::Severity::Info : Log::Severity::Debug

# Configure logging
::Log.setup "*", log_level, RubberSoul::LOG_BACKEND
::Log.builder.bind "action-controller.*", log_level, RubberSoul::LOG_BACKEND
::Log.builder.bind "#{RubberSoul::APP_NAME}.*", log_level, RubberSoul::LOG_BACKEND
