require "action-controller"

require "../rubber-soul"

class RubberSoul::API < ActionController::Base
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
      version: RubberSoul::VERSION,
    }
  end

  # Reindex all tables
  # Backfills by default
  post "/reindex", :reindex do
    backfill = params[:backfill]? || true
    table_manager.reindex_all
    table_manager.backfill_all if backfill
  end

  # Backfill all tables
  post "/backfill", :backfill do
    table_manager.backfill_all
  end
end
