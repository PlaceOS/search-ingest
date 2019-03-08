class RubberSoul::Table
  macro finished
    __generate_field_mapping
  end

  macro __generate_field_mapping
    # Mappings for all RethinkORM models in the scope
    ATTRIBUTE_MAPPINGS = {
      {% for model, fields in RethinkORM::Base::FIELD_MAPPINGS %}
        {{ model.stringify }} => {
          {% for attr, options in fields %}
            {{ attr.symbolize }} => {{ options }},
          {% end %}
        },
      {% end %}
      }
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

  # Field -> ES_Type -> Mapping
  alias Mapping = Tuple(Symbol, String)

  # Field -> Index -> Child
  alias Child = Tuple(Symbol, String)

  # Constructs an elasticsearch (sub-)schema
  class Schema
    def initialize(@mappings : Array(Mapping), @children : Array(Child))
    end

    # Creates a stringified JSON subschema
    def to_json
    end
  end

  def initialize(@model : RethinkORM::Base.class)
  end

  def children
  end

  def child_tables
    ATTRIBUTE_MAPPINGS.select do |table, attribute_mapping|
      # Ignore self
      next if table == @model.name

      # Do any of the attributes define a parent relationship with current model?
      attribute_mapping.any? do |_, metadata|
        options = metadata[:tags]
        !!(options && options[:parent]?.try { |p| p == @model.name })
      end
    end
  end

  # Determine if type tag is a valid Elasticsearch field datatype
  def valid_es_type?(es_type)
    ES_TYPES.includes?(es_type)
  end

  # Map from crystal types to Elasticsearch field datatypes
  def generate_mappings : Array(Mapping)
    mappings = ATTRIBUTE_MAPPINGS[@model.name].map do |field, options|
      tags = options[:tags]
      if tags && tags.has_key?(:es_type)
        # Try to pick out a es_type tag
        type_tag = tags.dig?(:es_type) || ""
        raise Error.new("Invalid ES type '#{type_tag}' for #{field} of #{@model.name}") unless valid_es_type?(type_tag)

        {field, type_tag}
      else
        # Map the klass of field to es_type
        es_type = map_es_type(options[:klass])

        # Could the klass be mapped?
        es_type ? {field, es_type} : nil
      end
    end
    mappings.compact
  end

  def map_es_type(value : Class) : String | Nil
    case value.name
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

  # `belongs_to` relations embed the child document under the parent index, and creates a join relation
  # Place all children's schemas into master parent schema
  # for each of the children tables, place the join relation after???
  # Do we want each table to be under its own? or nah

  # For children, create a join
  #
end
