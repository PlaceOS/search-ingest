require "json"
require "rethinkdb-orm"

require "./elastic"
require "./table"
require "./error"

class RubberSoul::TableManager
  @tables : Array(RubberSoul::Table)
  getter tables

  # Maps from index name to mapping schma
  @index_mappings = {} of String => String

  def initialize(models)
    # Create tables
    @tables = models.map { |model| RubberSoul::Table.new(model) }

    # Generate schemas
    @tables.each { |t| @index_mappings[t.index_name] = create_schema(t) }

    # Set up ES indices
    initialise_indices
  end

  # Backfills from a table to all relevant indices
  def backfill(table : RubberSoul::Table)
    table.all.each { |d| RubberSoul::Elastic.save_document(table, d) }
  end

  # Save all documents in all tables to the correct indices
  def backfill_all
    @tables.each { |t| backfill(t) }
  end

  def reindex_all
    # Clear and update all index mappings
    @tables.each do |table|
      # Delete index
      RubberSoul::Elastic.delete_index(table.index_name)
      # Apply current mapping
      apply_mapping(table)
    end
    # Backfill all indices
    backfill_all
  end

  # Clear, update mapping an ES index and refill with rethinkdb documents
  def reindex(table)
    # Delete index
    RubberSoul::Elastic.delete_index(table.index_name)
    # Apply current mapping
    apply_mapping(table)
    # Backfill
    backfill(table)
  end

  def apply_mapping(table)
    schema = create_schema(table)
    unless RubberSoul::Elastic.apply_index_mapping(table.index_name, schema)
      raise RubberSoul::Error.new("Failed to create mapping for #{table.index_name}")
    end
  end

  def watch_tables
    @tables.each do |table|
      spawn do
        table.watch do |change|
          document = change[:value]
          if change[:event] == RethinkORM::Changefeed::Event::Deleted?
            RubberSoul::Elastic.delete_document(table, document)
          else
            RubberSoul::Elastic.save_document(table, document)
          end
        end
      rescue e
        LOG.error "while watching #{table.name}"
        raise e
      end
    end
  end

  # Checks if any index does not exist or has a different mapping
  def consistent_indices?
    @tables.all? do |index_table|
      index = index_table.index_name
      index_exists = RubberSoul::Elastic.check_index? index
      !!(index_exists && diff_mapping(index))
    end
  end

  # Currently a reindex is triggered if...
  # - a single index does not exist
  # - a single mapping is different
  # TODO: Intelligentify
  def initialise_indices
    # Delete and backfill to a consistent state
    reindex_all unless consistent_indices?
  end

  # Diff the current mapping schema (if any) against generated schema
  def diff_mapping(index)
    current_mapping = RubberSoul::Elastic.get_mapping index

    # Mapping exists and is the same
    !!(current_mapping && current_mapping == @index_mappings[index])
  end

  # Collects all properties relevant to an index and collapse them into a schema
  def create_schema(table : Table)
    index_tables = table.children << table.name

    # Get the properties of all relevent tables, create index
    index_properties = @tables.compact_map { |t| t.properties if index_tables.includes? t.name }.flatten

    # Construct the mapping schema
    {
      mappings: {
        _doc: {
          properties: index_properties.to_h,
        },
      },
    }.to_json
  end
end
