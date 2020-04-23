require "action-controller/logger"

module RubberSoul
  RETHINK_DATABASE = ENV["RETHINKDB_DB"]? || "test"
  APP_NAME         = "rubber-soul"
  # calculate version at compile time
  VERSION = {{ `shards version "#{__DIR__}"`.chomp.stringify.downcase }}
end
