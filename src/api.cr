require "action-controller"
require "active-model"

require "../rubber-soul"

module RubberSoul
  class API < ActionController::Base
    base "/api/v1"

    @@table_manager = RubberSoul::TableManager.new(RubberSoul::MANAGED_TABLES, watch: true)

    def table_manager
      @@table_manager
    end

    get "/", :root do
      head :ok
    end

    get "/healthz", :healthz do
      head :ok
    end

    get "/version", :version do
      render :ok, json: {
        version: RubberSoul::VERSION.to_s,
      }
    end

    class ReindexParams < ActiveModel::Model
      attribute backfill : Bool = true
    end

    # Reindex all tables
    # Backfills by default
    post "/reindex", :reindex do
      args = ReindexParams.new(params)
      table_manager.reindex_all
      table_manager.backfill_all if args.backfill
    end

    # Backfill all tables
    post "/backfill", :backfill do
      table_manager.backfill_all
    end
  end
end
