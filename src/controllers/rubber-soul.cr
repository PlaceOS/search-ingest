class RubberSoul < Application
  base "/api"

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
