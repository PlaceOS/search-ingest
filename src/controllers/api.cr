require "./base"
require "../config"

class RubberSoul::Controller::API < RubberSoul::Controller::Base
  base "/api"

  # TODO: Model names currently hardcoded
  # TODO: Change once models export the model names
  @@table_manager = RubberSoul::TableManager.new([ControlSystem, Module, Dependency, Zone])

  get "/healthz", :healthz do
    head :ok
  end

  # Reindex all tables
  post "/reindex", :reindex_tables do
    head :not_implemented
  end

  # Allow specific tables to be reindexed
  #   ensure all dependencies reindexed?
  post "/reindex/:table", :reindex_table do
    head :not_implemented
  end

  # Backfill all tables
  post "/backfill", :backfill_tables do
    head :not_implemented
  end

  # Backfill specific table,
  #   as in reindex, ensure all dependencies backfilled?
  post "/backfill/:table", :backfill_table do
    head :not_implemented
  end
end