# require "engine-models"

module RubberSoul::ElasticModel(T)
  # Constructs a schema
  class Schema
    def initialize(@mappings : Array(Tuples(String, String)), @parent_tables : Array(Tuple(String, String)))
    end

    # Creates a stringified JSON subschema
    def to_s
    end
  end

  # Map from crystal types to Elasticsearch field datatypes
  def generate_mappings(model : T) : Array(Tuple(String, String))
    mappings = model.attributes.map do |attribute|
      name, value = attribute
      if map_es_type(value).empty?
        nil
      else
        {name, value}
      end
    end
    mappings.compact
  end

  def map_es_type(value) : String
    es_type = case value
              when String
                "text"
              when Time
                "date"
              when Int64
                "long"
              when Int32
                "integer"
              when Int16
                "short"
              when Int8
                "byte"
              when Float64
                "double"
              when Float32
                "float"
              else
                ""
              end
  end

  # Associations are placed under the parents
  # `belongs_to` relations embed the child document under the parent index, and creates a join relation
end
