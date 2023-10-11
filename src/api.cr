require "action-controller"
require "placeos-models/version"

require "./constants"
require "./search-ingest/*"
require "uri"
require "uri/params"

module SearchIngest
  class Api < ActionController::Base
    Log = ::Log.for(self)

    base "/api/search-ingest/v1"

    class_getter table_manager : TableManager do
      _schemas, tables = SearchIngest.tables(MANAGED_TABLES)
      TableManager.new(tables, backfill: true, watch: true)
    end

    # =====================
    # Routes
    # =====================

    # Reindex all tables, backfills by default
    @[AC::Route::POST("/reindex")]
    def reindex(backfill : Bool = true) : Nil
      if self.class.table_manager.reindex_all
        if backfill
          raise "failed to backfill" unless self.class.table_manager.backfill_all
        end
      else
        raise "failed to reindex"
      end
    end

    # Backfill all tables
    @[AC::Route::POST("/backfill")]
    def backfill : Nil
      raise "failed to backfill" unless self.class.table_manager.backfill_all
    end

    # return the version and build details of the service
    @[AC::Route::GET("/version")]
    def version : PlaceOS::Model::Version
      PlaceOS::Model::Version.new(
        version: VERSION,
        build_time: BUILD_TIME,
        commit: BUILD_COMMIT,
        service: APP_NAME
      )
    end

    # Health Check
    ###############################################################################################

    class_property? failed_healthcheck : Bool = false

    # has the service finished loading
    @[AC::Route::GET("/ready")]
    def ready : Nil
      raise Error::NotReady.new("startup has not completed") unless self.class.table_manager.load_complete?
    end

    class Error < Exception
      class NotReady < Error
      end
    end

    @[AC::Route::Exception(Error::NotReady, status_code: HTTP::Status::SERVICE_UNAVAILABLE)]
    def not_ready_error(_error) : Nil
    end

    # health check
    @[AC::Route::GET("/")]
    def index : Nil
      return unless self.class.table_manager.load_complete?

      if self.class.healthcheck?
        if self.class.failed_healthcheck?
          self.class.failed_healthcheck = false
          # Asynchronously backfill after service health restored
          spawn do
            self.class.table_manager.backfill_all
          end
        end
      else
        self.class.failed_healthcheck = true
        raise "health check failed"
      end
    end

    def self.healthcheck? : Bool
      Promise.all(
        Promise.defer {
          check_resource?("elastic") { Elastic.healthy? }
        },
        Promise.defer {
          check_resource?("postgres") { pg_healthcheck }
        },
      ).then(&.all?).get
    end

    private def self.check_resource?(resource, &)
      Log.trace { "healthchecking #{resource}" }
      !!yield
    rescue e
      Log.error(exception: e) { {"connection check to #{resource} failed"} }
      false
    end

    private def self.pg_healthcheck
      ::DB.connect(pg_healthcheck_url) do |db|
        db.query_all("select datname from pg_stat_activity where datname is not null", as: {String}).first?
      end
    end

    @@pg_healthcheck_url : String? = nil

    private def self.pg_healthcheck_url(timeout = 5)
      @@pg_healthcheck_url ||= begin
        url = PgORM::Settings.to_uri
        uri = URI.parse(url)
        if q = uri.query
          params = URI::Params.parse(q)
          unless params["timeout"]?
            params.add("timeout", timeout.to_s)
          end
          uri.query = params.to_s
          uri.to_s
        else
          "#{url}?timeout=#{timeout}"
        end
      end
    end

    ###############################################################################################

    # =====================
    # Error Handling
    # =====================

    # Provides details on available data formats
    struct ContentError
      include JSON::Serializable
      include YAML::Serializable

      getter error : String
      getter accepts : Array(String)? = nil

      def initialize(@error, @accepts = nil)
      end
    end

    # covers no acceptable response format and not an acceptable post format
    @[AC::Route::Exception(AC::Route::NotAcceptable, status_code: HTTP::Status::NOT_ACCEPTABLE)]
    @[AC::Route::Exception(AC::Route::UnsupportedMediaType, status_code: HTTP::Status::UNSUPPORTED_MEDIA_TYPE)]
    def bad_media_type(error) : ContentError
      ContentError.new error: error.message.not_nil!, accepts: error.accepts
    end

    # Provides details on which parameter is missing or invalid
    struct ParameterError
      include JSON::Serializable
      include YAML::Serializable

      getter error : String
      getter parameter : String? = nil
      getter restriction : String? = nil

      def initialize(@error, @parameter = nil, @restriction = nil)
      end
    end

    # handles paramater missing or a bad paramater value / format
    @[AC::Route::Exception(AC::Route::Param::MissingError, status_code: HTTP::Status::UNPROCESSABLE_ENTITY)]
    @[AC::Route::Exception(AC::Route::Param::ValueError, status_code: HTTP::Status::BAD_REQUEST)]
    def invalid_param(error) : ParameterError
      ParameterError.new error: error.message.not_nil!, parameter: error.parameter, restriction: error.restriction
    end
  end
end
