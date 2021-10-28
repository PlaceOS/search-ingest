require "placeos-log-backend"

require "./constants"

module SearchIngest::Logging
  ::Log.progname = APP_NAME

  # Logging configuration
  log_level = SearchIngest.production? ? ::Log::Severity::Info : ::Log::Severity::Debug
  log_backend = PlaceOS::LogBackend.log_backend
  namespaces = ["action-controller.*", "place_os.*", "rethink_elastic_ingest.*"]

  ::Log.setup do |config|
    config.bind "*", :warn, log_backend
    namespaces.each do |namespace|
      config.bind namespace, log_level, log_backend
    end
  end

  PlaceOS::LogBackend.register_severity_switch_signals(
    production: SearchIngest.production?,
    namespaces: namespaces,
    backend: log_backend,
  )
end
