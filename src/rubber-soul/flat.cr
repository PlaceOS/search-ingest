require "rethinkdb-orm"
require "./elastic"

class RubberSoul::TableManager
  alias Property = Tuple(String, NamedTuple(type: String))

  # Map class name to model properties
  @@properties = {} of String => Array(Property)

  # Map class name to index name
  @@index_names = {} of String => String

  # Map from class name to schema
  @@index_schemas = {} of String => String

  macro finished
    # All RethinkORM models with abstract and empty classes removed
    MODELS = {} of Nil => Nil
    __create_model_metadata
    __generate_methods(["changes", "all", "table_name"])
  end

  macro __create_model_metadata
    {% for model, fields in RethinkORM::Base::FIELD_MAPPINGS %}
      {% unless model.abstract? || fields.empty? %}
      {% MODELS[model] = fields %}
      {% end %}
    {% end %}
    # Extracted metadata from ORM classes
    MODEL_METADATA = {
      {% for model, fields in MODELS %}
          model.stringify => {
            {% for attr, options in fields %}
              {{ attr.symbolize }} => {{ options }},
            {% end %}
          }
      {% end %}
    }
  end

  macro __generate_methods(methods)
    {% for method in methods %}
      __generate_method({{ method }})
    {% end %}
  end

  macro __generate_method(method)
    # Dispatcher for {{ method.id }}
    def {{ method }}(model)
      case model
        {% for klass in MODELS.keys %}
          {{ klass.id }}_{{ method }}
        {% end %}
      else
        raise "No #{{{ method.id }}} for '#{model}'"
      end
    end

    # Generate {{ method.id }} method calls
    {% for klass in MODELS.keys %}
    def {{ klass.id }}_{{ method }}
      {{ klass.id }}.{{ method }}
    end
    {% end %}
  end

  def initialize(klasses : Array(Class))
    @models = klasses.map(&.name)
    @properties = generate_properties(@models)
    @index_schemas = generate_schemas(@models)
  end

  # Look up table schema
  def index_schema(table) : String
    @index_schemas[table]
  end

  # Look up index name
  def index_name(table)
    table_name(table) # Alias generated method function
  end

  # Initialisation
  #############################################################################################

  def initialize(models, backfill = true, watch = true)
    # Create tables
    @tables = models.map { |model| RubberSoul::Table.new(model) }
    # Generate schemas
    @tables.each { |t| @index_mappings[t.index_name] = create_schema(t) }
    initialise_indices(backfill)
    # Begin rethinkdb sync
    watch_tables if watch
  end

  # Currently a reindex is triggered if...
  # - a single index does not exist
  # - a single mapping is different
  def initialise_indices(backfill = false)
    if !consistent_indices?
      # reindex and backfill to a consistent state
      reindex_all
      backfill_all
    elsif backfill
      backfill_all
    end
  end

  # Backfill
  #############################################################################################

  # Backfills from a table to all relevant indices
  def backfill(table : RubberSoul::Table)
    table.all.each do |d|
      RubberSoul::Elastic.save_document(table, d)
    end
  end

  # Save all documents in all tables to the correct indices
  def backfill_all
    # @tables.each { |t| backfill(t) }
    @tables.each do |table|
      backfill(table)
    end
  end

  # Reindex
  #############################################################################################

  # Clear and update all index mappings
  def reindex_all
    @tables.each { |table| reindex(table) }
  end

  def reindex_all
    @tables.each { |table| reindex(table) }
  end

  # Clear, update mapping an ES index and refill with rethinkdb documents
  def reindex(table : String)
    index = index_name(table)
    # Delete index
    RubberSoul::Elastic.delete_index(index)
    # Apply current mapping
    apply_mapping(table)
  end

  # Watch
  #############################################################################################

  def watch_tables(tables)
    tables.each do |table|
      spawn do
        watch_table(table)
      rescue e
        LOG.error "while watching #{table.name}"
        raise e
      end
    end
  end

  def watch_table(table)
    changes(table).each do |change|
      document = change[:value]
      next if document.nil?
      if change[:event] == RethinkORM::Changefeed::Event::Deleted
        RubberSoul::Elastic.delete_document(table, document)
      else
        RubberSoul::Elastic.save_document(table, document)
      end
    end
  end

  # Elasticsearch mapping
  #############################################################################################

  # Checks if any index does not exist or has a different mapping
  def consistent_indices?
    @tables.all? do |index_table|
      index = index_table.index_name
      index_exists = RubberSoul::Elastic.check_index? index
      !!(index_exists && diff_mapping(index))
    end
  end

  # Diff the current mapping schema (if any) against generated schema
  def same_mapping?(table)
    index = @@index_names[table]
    existing_schema = RubberSoul::Elastic.get_mapping(index)
    generated_schema = index_schema(table)
    if exisiting_schema
      # Convert to JSON::Any for comparison
      JSON.parse(existing_schema) == JSON.parse(generated_schema)
    else
      false
    end
  end

  def apply_mapping(table)
    index_name = index_name(table)
    schema = index_schema(table)
    unless RubberSoul::Elastic.apply_index_mapping(index_name, schema)
      raise RubberSoul::Error.new("Failed to create mapping for #{index_name}")
    end
  end

  # Schema Generation
  #############################################################################################

  # Generate a map of models to schemas
  def generate_schemas(models)
    schemas = {} of String => String
    models.each do |model|
      schemas[model] = construct_document_schema(model)
    end
    schemas
  end

  # Generate the index type mapping structure
  def construct_document_schema(model) : String
    {
      mappings: {
        _doc: {
          properties: collect_index_properties(table, children(table)),
        },
      },
    }.to_json
  end

  # Property Generation
  #############################################################################################

  # Collects all properties relevant to an index and collapse them into a schema
  def collect_index_properties(table : String, children : Array(String)? = [] of String)
    index_tables = children << table
    # Get the properties of all relevent tables, create flat index properties
    @@properties.select(index_tables).values.flatten.to_h
  end

  def generate_properties(models)
    models.reduce({} of String => Array(Property)) do |props, model|
      props[model] = generate_table_properties(model)
      props
    end
  end

  # Map from crystal types to Elasticsearch field datatypes
  def generate_table_properties(model) : Array(Property)
    MODEL_METADATA[model][:attributes].compact_map do |field, options|
      type_tag = options.dig?(:tags, :es_type)
      if type_tag
        unless valid_es_type?(type_tag)
          raise Error.new("Invalid ES type '#{type_tag}' for #{field} of #{model}")
        end
        {field, {type: type_tag}}
      else
        # Map the klass of field to es_type
        es_type = klass_to_es_type(options[:klass])
        # Could the klass be mapped?
        es_type ? {field, {type: es_type}} : nil
      end
    end
  end

  # Valid elasticsearch field datatypes
  private ES_TYPES = {
    # String
    "text", "keyword",
    # Numeric
    "long", "integer", "short", "byte", "double", "float", "half_float", "scaled_float",
    # Other
    "boolean", "date", "binary",
    # Special
    "ip", "completion",
    # Spacial
    "geo_point", "geo_shape",
  }

  # Determine if type tag is a valid Elasticsearch field datatype
  private def valid_es_type?(es_type)
    ES_TYPES.includes?(es_type)
  end

  # Map from a class type to an es type
  private def klass_to_es_type(klass) : String | Nil
    case klass.name
    when "String"
      "text"
    when "Time"
      "date"
    when "Int64"
      "long"
    when "Int32"
      "integer"
    when "Int16"
      "short"
    when "Int8"
      "byte"
    when "Float64"
      "double"
    when "Float32"
      "float"
    else
      nil
    end
  end

  # Relations
  #############################################################################################

  alias Parent = NamedTuple(name: String, routing_attr: String)

  # Find name and ES routing of document's parents
  def parents(model) : Array(Parent)
    MODEL_METADATA[model].compact_map do |field, attr|
      parent_name = attr.dig? :tags, :parent
      unless parent_name.nil?
        {
          name:         parent_name,
          routing_attr: field.to_s,
        }
      end
    end
  end

  # Get names of all children associated with table
  def children(model)
    MODEL_METADATA.compact_map do |table, metadata|
      # Ignore self
      next if table == model
      # Do any of the attributes define a parent relationship with current model?
      is_child = metadata[:attributes].any? do |_, attr_data|
        options = attr_data[:tags]
        !!(options && options[:parent]?.try { |p| p == model })
      end
      table if is_child
    end
  end
end
