require "placeos-log-backend"

require "./constants"

module SearchIngest::Logging
  ::Log.progname = APP_NAME

  # Logging configuration
  log_level = SearchIngest.production? ? ::Log::Severity::Info : ::Log::Severity::Debug
  log_backend = PlaceOS::LogBackend.log_backend
  namespaces = ["action-controller.*", "place_os.*", "rethink_elastic_ingest.*"]

  builder = ::Log.builder

  ::Log.setup_from_env(
    default_level: log_level,
    backend: log_backend,
    builder: builder,
  )

  namespaces.each do |namespace|
    builder.bind namespace, log_level, log_backend
  end

  PlaceOS::LogBackend.register_severity_switch_signals(
    production: SearchIngest.production?,
    namespaces: namespaces,
    backend: log_backend,
  )
end
