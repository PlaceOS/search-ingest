class RubberSoul::TableManager

  # ES Index => Tables
  @@watching = {} of String => Array(Schema)

  def initialize
  end

  def ensure_tables!
  end

  def apply_mappings
    mappings = @@watching.map { |index, mappings| mapping.generate_mappings }
  end

  def watch_tables
  end

  def backfill_tables
  end

  def reindex_tables
  end
end