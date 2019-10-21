require "action-controller"

require "./constants"
require "./rubber-soul/*"

module RubberSoul
  class API < ActionController::Base
    base "/api/rubber-soul/v1"

    @@table_manager = RubberSoul::TableManager.new(RubberSoul::MANAGED_TABLES, watch: true)

    get "/healthz", :root do
      head :ok
    end

    get "/version", :version do
      render :ok, json: {
        version: RubberSoul::VERSION.to_s,
      }
    end

    # Reindex all tables, backfills by default
    # /reindex?[backfill=true]
    post "/reindex", :reindex do
      @@table_manager.reindex_all
      @@table_manager.backfill_all if params["backfill"] == true
    end

    # Backfill all tables
    post "/backfill", :backfill do
      @@table_manager.backfill_all
    end
  end
end
