# Engine Models
require "placeos-models"

# Tables watched by TableManager
# FIXME: This is not ideal. A constant array is required for macro methods
RubberSoul::MANAGED_TABLES = [
  PlaceOS::Model::Authority,
  PlaceOS::Model::ControlSystem,
  PlaceOS::Model::DoorkeeperApplication,
  PlaceOS::Model::Driver,
  PlaceOS::Model::Edge,
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
  ActionController::LogHandler.new(ms: true),
  HTTP::CompressHandler.new
)

log_level = RubberSoul::PROD ? Log::Severity::Info : Log::Severity::Debug
log_backend = RubberSoul.log_backend

# Configure logging
::Log.setup "*", :warn, log_backend
::Log.builder.bind "action-controller.*", log_level, log_backend
::Log.builder.bind "#{RubberSoul::APP_NAME}.*", log_level, log_backend
