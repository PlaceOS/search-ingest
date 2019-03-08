require "rethinkdb-orm"

class RubberSoul::TableManager
  # ES Index => Tables
  # @watching = {} of String => Array(RubberSoul::Table::Schema)

  def initialize(models : Array(RethinkORM::Base.class))
    @models = models.map { |model| RubberSoul::Table.new(model) }
    # Generate the table and schema
    # Fill out the watching
    #
  end

  def ensure_tables!
  end

  def apply_mappings
    # mappings = @watching.map { |index, mappings| mapping.generate_mappings }
  end

  def watch_tables
    # Spawn the watch process on each table
  end

  def backfill_tables
  end

  def reindex_tables
  end
end
