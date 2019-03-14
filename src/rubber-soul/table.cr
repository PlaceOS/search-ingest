require "rethink-orm"

# Encapsulates table's relations and properties
class RubberSoul::Table
  macro finished
    __generate_field_mapping
  end

  macro __generate_field_mapping
    # Mappings for all RethinkORM models in the scope
    private ATTRIBUTE_MAPPINGS = {
      {% for model, fields in RethinkORM::Base::FIELD_MAPPINGS %}
        {{ model.stringify }} => {
          {% for attr, options in fields %}
            {{ attr.symbolize }} => {{ options }},
          {% end %}
        },
      {% end %}
      }
    private CLASS_DISPATCH = {
      {% for model in RethinkORM::Base::FIELD_MAPPINGS.keys %}
        {{ model.stringify }} => {{ model.id }},
      {% end %}
      }
    private TABLE_MAPPING = {
      {% for model in RethinkORM::Base::FIELD_MAPPINGS.keys %}
        {{ model.stringify }} => {{ model.id }}.table_name,
      {% end %}
    }
  end

  alias Mapping = Tuple(Symbol, String)
  alias Child = Tuple(Symbol, String)

  getter name
  getter index_name

  def initialize(@model : RethinkORM::Base.class)
    @name = @model.name
    @klass = CLASS_DISPATCH[@name]
    @index_name = @klass.table_name
  end

  # Get array of _es_ properties of the table
  def properties
    @properties ||= generate_mappings.map { |name, type| {name, {type: type}} }
  end

  # Get names of all children associated with table
  def children
    @children ||= child_tables.keys
  end

  # Set up changefeed on table
  def watch
    @klass.watch
  end

  alias Parent = NamedTuple(index: String, routing_attr: String)

  # Find parent name of document and routing
  def parents : Array(Parent)
    ATTRIBUTE_MAPPINGS[@name].compact_map do |field, attr|
      parent_name = attr.dig? :tags, :parent
      unless parent_name.nil?
        {
          index:        TABLE_MAPPING[parent_name],
          routing_attr: field,
        }
      end
    end
  end

  # Find children of document
  private def child_tables
    ATTRIBUTE_MAPPINGS.select do |table, attribute_mapping|
      # Ignore self
      next if table == @name

      # Do any of the attributes define a parent relationship with current model?
      attribute_mapping.any? do |_, metadata|
        options = metadata[:tags]
        !!(options && options[:parent]?.try { |p| p == @name })
      end
    end
  end

  # Map from crystal types to Elasticsearch field datatypes
  private def generate_mappings : Array(Mapping)
    ATTRIBUTE_MAPPINGS[@name].compact_map do |field, options|
      tags = options[:tags]

      if tags && tags.has_key?(:es_type)
        # Try to pick out a es_type tag
        type_tag = tags.dig?(:es_type) || ""

        unless valid_es_type?(type_tag)
          raise Error.new("Invalid ES type '#{type_tag}' for #{field} of #{@name}")
        end

        {field, type_tag}
      else
        # Map the klass of field to es_type
        es_type = klass_to_es_type(options[:klass])

        # Could the klass be mapped?
        es_type ? {field, es_type} : nil
      end
    end
  end

  # Valid elasticsearch field datatypes
  ES_TYPES = {
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
end
