require "action-controller"

require "../rubber-soul"

class RubberSoul::API < ActionController::Base
  base "/api"

  @@table_manager : RubberSoul::TableManager | Nil

  def table_manager
    @@table_manager ||= RubberSoul::TableManager.new(RubberSoul::MANAGED_TABLES, watch: true)
  end

  get "/healthz", :healthz do
    head :ok
  end

  # Reindex all tables
  # Backfills by default
  post "/reindex", :reindex_all do
    backfill = params[:backfill]? || true
    table_manager.reindex_all
    table_manager.backfill_all if backfill
  end

  # Backfill all tables
  post "/backfill", :backfill_all do
    table_manager.backfill_all
  end
end
