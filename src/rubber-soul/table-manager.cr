class RubberSoul::TableManager

  # ES Index => Tables
  @@watching = {} of String => Array(ElasticModel::Schema)

  def initialize
  end

  def self.ensure_tables!
  end

  def self.apply_mappings
    mappings = @@watching.map { |index, mappings| mapping.generate_mappings }
  end

  def self.watch_tables
  end

  def self.backfill_tables
  end

  def self.reindex_tables
  end
end
