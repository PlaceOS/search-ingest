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

# Configure logging
::Log.setup "*", log_level, RubberSoul::LOG_BACKEND
