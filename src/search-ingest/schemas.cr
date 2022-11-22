module SearchIngest
  class Schemas
    # Map class name to model properties
    getter properties : Hash(String, Array(Field))

    # Map from class name to schema
    getter index_schemas : Hash(String, String)

    # Class names of managed tables
    getter models : Array(String)

    def initialize(models : Array(Class) = MANAGED_TABLES)
      @models = models.map { |m| self.class.document_name(m) }
      @properties = generate_properties(models)
      @index_schemas = generate_schemas(models)
    end

    # Strips the namespace from the model
    def self.document_name(model : Class | String)
      model = model.name unless model.is_a? String
      model.split("::").last
    end

    # Look up model schema by class
    def index_schema(model : Class | String) : String
      index_schemas[self.class.document_name(model)]
    end

    # Look up index name by class
    def index_name(model) : String
      MODEL_METADATA[self.class.document_name(model)].table_name
    end

    # Schema Generation
    #############################################################################################

    # Generate a map of models to schemas
    def generate_schemas(models)
      models.each_with_object(Hash(String, String).new(initial_capacity: models.size)) do |model, schemas|
        name = Schemas.document_name(model)
        schemas[name] = construct_document_schema(name)
      end
    end

    # Generate the index type mapping structure
    def construct_document_schema(model) : String
      name = self.class.document_name(model)
      children = children(name)
      properties = collect_index_properties(name, children)

      # Generate property mapping
      property_mapping = properties.map { |field| {field.name, field.field_mapping} }.to_h

      # Only include join if model has children
      property_mapping = property_mapping.merge(join_field(name, children)) unless children.empty?

      {
        settings: {
          analysis: {
            analyzer: {
              default: {
                tokenizer: "standard",
                filter:    ["lowercase", "preserved_ascii_folding"],
              },
            },
            filter: {
              preserved_ascii_folding: {
                type:              "asciifolding",
                preserve_original: true,
              },
            },
          },
        },
        mappings: {
          properties: property_mapping,
        },
      }.to_json
    end

    # Traverse schemas and test equality
    #
    # ameba:disable Metrics/CyclomaticComplexity
    def self.equivalent_schema?(existing_schema : String?, proposed_schema : String?) : Bool
      return false unless existing_schema && proposed_schema

      begin
        proposed = Schema.extract(proposed_schema)
        existing = Schema.extract(existing_schema)
      rescue e : JSON::SerializableError
        Log.warn(exception: e) { "malformed schema: #{proposed_schema}" }
        return false
      end

      (existing.keys.sort! == proposed.keys.sort!) && existing.all? do |prop, mapping|
        if prop == "join"
          existing_relations = mapping["relations"]?.try &.as_h?
          proposed_relations = proposed[prop]?.try(&.["relations"]?.try(&.as_h?))

          existing_relations && proposed_relations && (existing_relations.keys.sort! == proposed_relations.keys.sort!) && existing_relations.all? do |k, v|
            # Relations can be an array of join names, or a single join name
            l = v.as_a?.try(&.map(&.as_s)) || v
            r = proposed_relations[k]?.try &.as_a?.try(&.map(&.as_s)) || proposed_relations[k]?
            if l.is_a? Array && r.is_a? Array
              l.sort == r.sort
            else
              l == r
            end
          end
        else
          proposed[prop]? == mapping
        end
      end
    end

    # Model for extracting the schema of an index
    #
    private struct Schema
      include JSON::Serializable

      @[JSON::Field(root: "properties")]
      getter mappings : Hash(String, JSON::Any)

      def self.extract(json) : Hash(String, JSON::Any)
        from_json(json).mappings
      end
    end

    # Property Generation
    #############################################################################################

    def validate_tag(tag)
      return unless tag.is_a? String
      if valid_es_type?(tag)
        tag
      else
        Log.warn { "invalid tag `#{tag}` encountered" }
        nil
      end
    end

    # Now that we are generating joins on the parent_id, we need to specify if we are generating
    # a child or a single document
    # Maps from crystal types to Elasticsearch field datatypes
    def generate_index_properties(model, child = false) : Array(Field)
      document_name = self.class.document_name(model)

      properties = MODEL_METADATA[document_name].attributes.compact_map do |field, options|
        ::Log.with_context do
          Log.context.set(model: document_name, field: field.to_s)

          type_tag = validate_tag(options.tags[:es_type]?)
          subfield = validate_tag(options.tags[:es_subfield]?).try { |v| [v] }

          field_type = type_tag || klass_to_es_type(options.klass)

          Field.new(field.to_s, field_type, subfield) unless field_type.nil?
        end
      end

      properties << TYPE_FIELD
    end

    # Collects all properties relevant to an index and collapse them into a schema
    def collect_index_properties(
      model : String | Class,
      children : Array(String)? = nil
    ) : Array(Field)
      name = self.class.document_name(model)
      if !children || children.empty?
        properties[model]
      else
        index_models = children.dup << name
        # Get the properties of all relevent tables
        properties.select(index_models).values.flatten.uniq!
      end
    end

    # Construct properties for given models
    def generate_properties(models)
      models.each_with_object({} of String => Array(Field)) do |model, props|
        name = self.class.document_name(model)
        props[name] = generate_index_properties(name)
      end
    end

    # Generate join fields for parent relations
    def join_field(model, children)
      relations = children.size == 1 ? children.first : children.sort
      {
        "join" => {
          type:      "join",
          relations: {
            # Use types for defining the parent-child relation
            model => relations,
          },
        },
      }
    end

    # Allows several document types beneath a single index
    TYPE_FIELD = Field.new("_document_type", "keyword")

    # Valid elasticsearch field datatypes
    private ES_TYPES = {
      # String
      "text", "keyword",
      # Numeric
      "long", "integer", "short", "byte", "double", "float", "half_float", "scaled_float",
      # Other
      "boolean", "date", "binary", "object",
      # Special
      "ip", "completion",
      # Spacial
      "geo_point", "geo_shape",
    }

    # Determine if type tag is a valid Elasticsearch field datatype
    private def valid_es_type?(es_type : String)
      es_type.in? ES_TYPES
    end

    private ES_MAPPINGS = {
      "Bool":    "boolean",
      "Float32": "float",
      "Float64": "double",
      "Int16":   "short",
      "Int32":   "integer",
      "Int64":   "long",
      "Int8":    "byte",
      "String":  "text",
      "Time":    "date",
    }

    # Map from a class type to an es type
    private def klass_to_es_type(klass_name) : String | Nil
      if klass_name.starts_with?("Array")
        collection_type(klass_name, "Array")
      elsif klass_name.starts_with?("Set")
        collection_type(klass_name, "Set")
      elsif klass_name == "JSON::Any" || klass_name.starts_with?("Hash") || klass_name.starts_with?("NamedTuple")
        "object"
      else
        ES_MAPPINGS[klass_name]?.tap do |es_type|
          Log.warn { "no ES mapping for #{klass_name}" } if es_type.nil?
        end
      end
    end

    # Collections allowed as long as they are homogeneous
    private def collection_type(klass_name : String, collection_type : String)
      klass_to_es_type(klass_name.lchop("#{collection_type}(").rstrip(')'))
    end

    # Relations
    #############################################################################################

    # Find name and ES routing of document's parents
    def parents(model : Class | String) : Array(Parent)
      document_name = self.class.document_name(model)
      MODEL_METADATA[document_name].attributes.compact_map do |field, options|
        parent_name = options.tags[:parent]?
        unless parent_name.nil?
          {
            name:         parent_name,
            index:        index_name(parent_name),
            routing_attr: field,
          }
        end
      end
    end

    # Get names of all children associated with model
    def children(model : Class | String)
      document_name = self.class.document_name(model)
      MODEL_METADATA.compact_map do |name, metadata|
        # Ignore self
        next if name == document_name
        # Do any of the attributes define a parent relationship with current model?
        is_child = metadata.attributes.any? do |_, field|
          !!field.tags[:parent]?.try(&.==(document_name))
        end
        name if is_child
      end
    end

    # Accessors for data via class (or class name)
    ###############################################################################################

    def properties(klass : Class | String)
      properties[self.class.document_name(klass)]
    end

    def index_schemas(klass : Class | String)
      index_schemas[self.class.document_name(klass)]
    end

    # Data structs
    ###############################################################################################

    record Field, name : String, type : String, fields : Array(String)? = nil do
      def_equals name, type, fields

      # Represents the mapping of this field in an Elasticsearch schema
      def field_mapping
        if (field_mappings = fields)
          {
            "type"   => type,
            "fields" => field_mappings.map { |subtype| {subtype, {type: subtype}} }.to_h,
          }
        else
          {"type" => type}
        end
      end
    end

    private record(Metadata,
      table_name : String,
      attributes : Hash(Symbol, Options),
    ) do
      record(Options,
        klass : String,
        tags : Hash(Symbol, String),
      ) do
        # Extract required options from active-model attribute options
        def self.from_active_model(options)
          case tags = options[:tags]?.try &.to_h
          when Hash(NoReturn, NoReturn), Nil
            tags = {} of Symbol => String
          else
            tags = tags.each_with_object({} of Symbol => String) do |(k, v), object|
              case v
              when String then object[k] = v
              when Symbol then object[k] = v.to_s
              end
            end
          end
          new(options[:klass], tags)
        end
      end
    end

    # Metadata extraction from `active-model` classes
    ###############################################################################################

    macro finished
      # All PgORM models with abstract and empty classes removed
      # :nodoc:
      MODELS = {} of Nil => Nil
      __create_model_metadata
    end

    macro __create_model_metadata
      {% for model, fields in PgORM::Base::FIELD_MAPPINGS %}
        {% unless model.abstract? || fields.empty? %}
          {% if MANAGED_TABLES.map(&.resolve).includes?(model) %}
            {% MODELS[model] = fields %}
          {% end %}
        {% end %}
      {% end %}

      # Extracted metadata from ORM classes
      MODEL_METADATA = {
        {% for klass, fields in MODELS %}
          {{ klass.stringify.split("::").last }} => Metadata.new(
              attributes: {
              {% for attr, options in fields %}
                {% options[:klass] = options[:klass].resolve if options[:klass].is_a?(Path) %}
                {% options[:klass] = options[:klass].union_types.reject(&.nilable?).first if !options[:klass].is_a?(StringLiteral) && options[:klass].union? %}
                {% options[:klass] = options[:klass].stringify unless options[:klass].is_a?(StringLiteral) %}
                {{ attr.symbolize }} => Metadata::Options.from_active_model({{ options }}),
              {% end %}
              },
              table_name: {{ klass.id }}.table_name,
            ),
        {% end %}
      } {% if MODELS.empty? %} of Nil => Nil {% end %}
    end
  end
end
