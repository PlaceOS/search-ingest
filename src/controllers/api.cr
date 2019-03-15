require "./base"
require "../rubber-soul/*"

class RubberSoul::Controller::API < RubberSoul::Controller::Base
  base "/api"

  # TODO: Model names currently hardcoded
  # TODO: Change once models export the model names
  @@table_manager : RubberSoul::TableManager | Nil

  def table_manager
    @@table_manager ||= RubberSoul::TableManager.new([
      Engine::Model::ControlSystem,
      Engine::Model::Module,
      Engine::Model::Dependency,
      Engine::Model::Zone,
    ])
  end

  get "/healthz", :healthz do
    head :ok
  end

  # Reindex all tables
  post "/reindex", :reindex_tables do
    table_manager.reindex_all
  end

  # Allow specific tables to be reindexed
  #   ensure all dependencies reindexed?
  post "/reindex/:table", :reindex_table do
    head :not_implemented
  end

  # Backfill all tables
  post "/backfill", :backfill_tables do
    table_manager.backfill_all
  end

  # Backfill specific table,
  #   as in reindex, ensure all dependencies backfilled?
  post "/backfill/:table", :backfill_table do
    head :not_implemented
  end
end
