require "action-controller"

require "./constants"
require "./rubber-soul/*"

module RubberSoul
  class Api < ActionController::Base
    Log = ::Log.for(self)

    base "/api/rubber-soul/v1"

    class_getter table_manager : TableManager { TableManager.new(MANAGED_TABLES, backfill: true, watch: true) }

    # Reindex all tables, backfills by default
    # /reindex?[backfill=true]
    post "/reindex", :reindex do
      self.class.table_manager.reindex_all
      self.class.table_manager.backfill_all if params["backfill"]?.try(&.downcase) == "true"
    end

    # Backfill all tables
    post "/backfill", :backfill do
      self.class.table_manager.backfill_all
    end

    # Health Check
    ###############################################################################################

    def index
      head self.class.healthcheck? ? HTTP::Status::OK : HTTP::Status::INTERNAL_SERVER_ERROR
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
      render :ok, json: {
        version: VERSION,
      }
    end
  end
end
