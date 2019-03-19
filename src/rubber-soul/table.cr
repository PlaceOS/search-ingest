require "rethinkdb-orm"

# Encapsulates table's relations and properties
class RubberSoul::Table
  forward_missing_to klass

  macro finished
    MODEL_METADATA = {} of Nil => Nil
    __generate_field_mapping
  end

  macro __generate_field_mapping
    # Mappings for all RethinkORM models in the scope
     MODEL_METADATA = {
      {% for model, fields in RethinkORM::Base::FIELD_MAPPINGS %}
        {% unless fields.empty? || model.abstract? %}
          {{ model.stringify }} => {
              attributes: {
                {% for attr, options in fields %}
                  {{ attr.symbolize }} => {{ options }},
                {% end %}
              },
              klass: {{ model.id }},
              table_name: {{ model.id }}.table_name
              changes: ->{ {{ model.id }}.changes }
            },
        {% end %}
      {% end %}
      }
  end

  macro __generate_methods(model)
    # Generate required class methods
    {% klass = MODEL_METADATA[model.name][:klass] %}
    def table_name
      { klass.table_name }}
    end

    def changes
      {{ klass.changes }}
    end

    def all
      {{ klass.all }}
    end
  end

  alias Mapping = Tuple(Symbol, String)

  getter name : String
  getter index_name : String

  def initialize(model)
    @name = model.name
    @index_name = MODEL_METADATA[@name][:table_name]
  end

  # Get array of _es_ properties of the table
  def properties
    generate_mappings.map { |name, type| {name, {type: type}} }
  end

  # Get names of all children associated with table
  def children
    child_tables.keys.map(&.to_s)
  end

  alias Parent = NamedTuple(index: String, routing_attr: String)

  # Find parent name of document and routing
  def parents : Array(Parent)
    MODEL_METADATA[@name][:attributes].compact_map do |field, attr|
      parent_name = attr.dig? :tags, :parent
      unless parent_name.nil?
        {
          index:        MODEL_METADATA[parent_name][:table_name],
          routing_attr: field.to_s,
        }
      end
    end
  end

  # Find children of document
  private def child_tables
    MODEL_METADATA.select do |table, metadata|
      # Ignore self
      next if table == @name

      # Do any of the attributes define a parent relationship with current model?
      metadata[:attributes].any? do |_, attr_data|
        options = attr_data[:tags]
        !!(options && options[:parent]?.try { |p| p == @name })
      end
    end
  end

  # Map from crystal types to Elasticsearch field datatypes
  private def generate_mappings : Array(Mapping)
    MODEL_METADATA[@name][:attributes].compact_map do |field, options|
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
