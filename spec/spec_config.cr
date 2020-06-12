# Application dependencies
require "action-controller"
require "./spec_models"

# stdlib
require "http"
require "logger"

# Application code
require "../src/api"

# Server required after application controllers
require "action-controller/server"

# Add handlers that should run before your application
ActionController::Server.before(
  HTTP::LogHandler.new,
  HTTP::ErrorHandler.new(ENV["SG_ENV"]? != "production"),
  HTTP::CompressHandler.new
)

APP_NAME = "rubber-soul"
VERSION  = "1.0.0"
