require "action-controller"
require "placeos-models/version"

require "./constants"
require "./search-ingest/*"

module SearchIngest
  class Api < ActionController::Base
    Log = ::Log.for(self)

    base "/api/search-ingest/v1"

    class_getter table_manager : TableManager { TableManager.new(MANAGED_TABLES, backfill: true, watch: true) }

    getter? backfill : Bool do
      params["backfill"]?.presence.try(&.downcase).in?("1", "true")
    end

    protected def backfill_all
      if self.class.table_manager.backfill_all
        head :ok
      else
        head :internal_server_error
      end
    end

    # Reindex all tables, backfills by default
    # /reindex?[backfill=true]
    post "/reindex", :reindex do
      if self.class.table_manager.reindex_all
        if backfill?
          backfill_all
        else
          head :ok
        end
      else
        head :internal_server_error
      end
    end

    # Backfill all tables
    post "/backfill", :backfill do
      backfill_all
    end

    # Health Check
    ###############################################################################################

    class_property? failed_healthcheck : Bool = false

    def index
      if self.class.healthcheck?
        if self.class.failed_healthcheck?
          self.class.failed_healthcheck = false
          # Asynchronously backfill after service health restored
          spawn do
            self.class.table_manager.backfill_all
          end
        end

        head :ok
      else
        self.class.failed_healthcheck = true
        head :internal_server_error
      end
    end

    def self.healthcheck? : Bool
      Promise.all(
        Promise.defer {
          check_resource?("elastic") { Elastic.healthy? }
        },
        Promise.defer {
          check_resource?("rethinkdb") { rethinkdb_healthcheck }
        },
      ).then(&.all?).get
    end

    private def self.check_resource?(resource)
      Log.trace { "healthchecking #{resource}" }
      !!yield
    rescue e
      Log.error(exception: e) { {"connection check to #{resource} failed"} }
      false
    end

    private class_getter rethinkdb_admin_connection : RethinkDB::Connection do
      RethinkDB.connect(
        host: RethinkORM.settings.host,
        port: RethinkORM.settings.port,
        db: "rethinkdb",
        user: RethinkORM.settings.user,
        password: RethinkORM.settings.password,
        max_retry_attempts: 1,
      )
    end

    private def self.rethinkdb_healthcheck
      RethinkDB
        .table("server_status")
        .pluck("id", "name")
        .run(rethinkdb_admin_connection)
        .first?
    end

    ###############################################################################################

    get "/version", :version do
      render :ok, json: PlaceOS::Model::Version.new(
        version: VERSION,
        build_time: BUILD_TIME,
        commit: BUILD_COMMIT,
        service: APP_NAME
      )
    end
  end
end
