require "placeos-log-backend"

module RubberSoul
  # Logging configuration
  log_level = RubberSoul.production? ? ::Log::Severity::Info : ::Log::Severity::Debug
  log_backend = PlaceOS::LogBackend.log_backend
  ::Log.setup "*", :warn, log_backend
  ::Log.builder.bind "action-controller.*", log_level, log_backend
  ::Log.builder.bind "rubber_soul.*", log_level, log_backend
end
