module RubberSoul::Constants
  RETHINK_DATABASE = ENV["RETHINKDB_DB"]? || "test"
  APP_NAME         = "rubber-soul"
end
