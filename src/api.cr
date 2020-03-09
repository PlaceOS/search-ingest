require "action-controller"

require "./constants"
require "./rubber-soul/*"

module RubberSoul
  class API < ActionController::Base
    base "/api/rubber-soul/v1"

    @@table_manager : TableManager? = nil

    def self.table_manager
      (@@table_manager ||= TableManager.new(MANAGED_TABLES, backfill: true, watch: true))
    end

    get "/", :root do
      head :ok
    end

    get "/version", :version do
      render :ok, json: {
        version: VERSION.to_s,
      }
    end

    # Reindex all tables, backfills by default
    # /reindex?[backfill=true]
    post "/reindex", :reindex do
      API.table_manager.reindex_all
      API.table_manager.backfill_all if params["backfill"]? == true
    end

    # Backfill all tables
    post "/backfill", :backfill do
      API.table_manager.backfill_all
    end
  end
end
