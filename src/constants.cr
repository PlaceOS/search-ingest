module RubberSoul
  RETHINK_DATABASE = ENV["RETHINKDB_DB"]? || "test"
  APP_NAME         = "rubber-soul"
  VERSION          = `shards version`
end
