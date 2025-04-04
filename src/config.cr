require "./logging"

# Engine Models
require "placeos-models"

# Tables watched by TableManager
# FIXME: This is not ideal. A constant array is required for macro methods
SearchIngest::MANAGED_TABLES = [
  PlaceOS::Model::ApiKey,
  PlaceOS::Model::Authority,
  PlaceOS::Model::Broker,
  PlaceOS::Model::ControlSystem,
  PlaceOS::Model::DoorkeeperApplication,
  PlaceOS::Model::Driver,
  PlaceOS::Model::Edge,
  PlaceOS::Model::JsonSchema,
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
  PlaceOS::Model::AssetCategory,
  PlaceOS::Model::AssetType,
  PlaceOS::Model::Asset,
  PlaceOS::Model::AssetPurchaseOrder,
  PlaceOS::Model::Shortener,
  PlaceOS::Model::Playlist,
  PlaceOS::Model::Playlist::Item,
]

# Application code
require "./api"
require "./constants"
require "action-controller"

# Server
require "action-controller/server"

# Add handlers that should run before your application
ActionController::Server.before(
  HTTP::ErrorHandler.new(SearchIngest.production?),
  ActionController::LogHandler.new(ms: true),
  HTTP::CompressHandler.new
)
