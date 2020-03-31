require "action-controller/logger"
require "habitat"
require "rethinkdb-orm"
require "retriable"

require "./elastic"
require "./types"

# Class to manage rethinkdb models sync with elasticsearch
module RubberSoul
  class TableManager
    alias Property = Tuple(Symbol, NamedTuple(type: String))

    Habitat.create do
      setting logger : Logger = ActionController::Logger.new(STDOUT)
    end

    # Map class name to model properties
    getter properties : Hash(String, Array(Property))

    # Map from class name to schema
    getter index_schemas : Hash(String, String)

    # Class names of managed tables
    getter models : Array(String)

    private getter coordination : Channel(Nil) = Channel(Nil).new

    macro finished
      # All RethinkORM models with abstract and empty classes removed
      # :nodoc:
      MODELS = {} of Nil => Nil
      __create_model_metadata
      __generate_methods([:changes, :all])
    end

    macro __create_model_metadata
      {% for model, fields in RethinkORM::Base::FIELD_MAPPINGS %}
        {% unless model.abstract? || fields.empty? %}
          {% if MANAGED_TABLES.map(&.resolve).includes?(model) %}
            {% MODELS[model] = fields %}
          {% end %}
        {% end %}
      {% end %}

      # Extracted metadata from ORM classes
      MODEL_METADATA = {
        {% for klass, fields in MODELS %}
          {{ klass.stringify.split("::").last }} => {
              attributes: {
              {% for attr, options in fields %}
                {% options[:klass] = options[:klass].stringify unless options[:klass].is_a?(StringLiteral) %}
                {{ attr.symbolize }} => {{ options }},
              {% end %}
              },
              table_name: {{ klass.id }}.table_name
            },
        {% end %}
      } {% if MODELS.empty? %} of Nil => Nil {% end %}
    end

    # TODO: Move away from String backed stores, use Class

    macro __generate_methods(methods)
      {% for method in methods %}
        __generate_method({{ method }})
      {% end %}
    end

    macro __generate_method(method)
      # Dispatcher for {{ method.id }}
      def {{ method.id }}(model)
        document_name = TableManager.document_name(model)
        # Generate {{ method.id }} method calls
        case document_name
        {% for klass in MODELS.keys %}
        when {{ klass.stringify.split("::").last }}
          {{ klass.id }}.{{ method.id }}(runopts: {"read_mode" => "majority"})
        {% end %}
        else
          raise "No #{ {{ method.stringify }} } for '#{model}'"
        end
      end
    end

    # Look up model schema by class
    def index_schema(model : Class | String) : String
      document_name = TableManager.document_name(model)
      index_schemas[TableManager.document_name(model)]
    end

    # Look up index name by class
    def index_name(model) : String
      MODEL_METADATA[TableManager.document_name(model)][:table_name]
    end

    # Initialisation
    #############################################################################################

    def initialize(klasses = MANAGED_TABLES, backfill = false, watch = false)
      @models = klasses.map { |klass| TableManager.document_name(klass) }

      # Collate model properties
      @properties = generate_properties(models)

      # Generate schemas
      @index_schemas = generate_schemas(models)

      # Initialise indices to a consistent state
      initialise_indices(backfill)

      # Begin rethinkdb sync
      watch_tables(models) if watch
    end

    # Currently a reindex is triggered if...
    # - a single index does not exist
    # - a single mapping is different
    def initialise_indices(backfill : Bool = false)
      unless consistent_indices?
        logger.info { "action=initialise_indices event=\"reindex to consistency\"" }
        reindex_all
      end

      backfill_all if backfill
    end

    # Backfill
    #############################################################################################

    # Save all documents in all tables to the correct indices
    def backfill_all
      models.map do |model|
        future { backfill(model) }
      end.each &.get
      Fiber.yield
    end

    # Backfills from a model to all relevant indices
    def backfill(model)
      logger.info { "action=backfill model=#{model}" }

      index = index_name(model)
      parents = parents(model)
      no_children = children(model).empty?

      backfill_count = 0

      # NOTE: remove `#to_a` when this Map iterator type issue resolves
      # TODO: fix the memory overhead of the `#to_a`
      all(model).in_groups_of(100).to_a.map do |docs|
        actions = docs.compact_map do |d|
          next unless d

          backfill_count += 1
          Elastic.document_request(
            action: Elastic::Action::Create,
            document: d,
            index: index,
            parents: parents,
            no_children: no_children,
          )
        end

        future {
          Elastic.bulk_operation(actions.join('\n'))
          logger.info { "action=backfill model=#{model} count=#{backfill_count}" }
        }
      end.each &.get
      Fiber.yield
    end

    # Reindex
    #############################################################################################

    # Clear and update all index mappings
    def reindex_all
      models.map do |model|
        future { reindex(model) }
      end.each &.get
      Fiber.yield
    end

    # Clear, update mapping an ES index and refill with rethinkdb documents
    def reindex(model : String | Class)
      logger.info("action=reindex model=#{model}")
      name = TableManager.document_name(model)

      index = index_name(name)
      # Delete index
      Elastic.delete_index(index)
      # Apply current mapping
      create_index(name)
    end

    # Watch
    #############################################################################################

    def watch_tables(models)
      models.each do |model|
        spawn do
          watch_table(model)
        rescue e
          logger.error { "action=watch_table model=#{model} error=#{e.inspect}" }
          # Fatal error
          exit 1
        end
      end
    end

    def stop
      coordination.close
    end

    def watch_table(model : String | Class)
      name = TableManager.document_name(model)

      index = index_name(name)
      parents = parents(name)
      no_children = children(name).empty?

      retry_handler = ->(ex : Exception, _attempt : Int32, _elapsed_time : Time::Span, _next_interval : Time::Span) {
        logger.warn { "action=watch_table model=#{model} error=#{ex.message} message=backfilling after changefeed error" }
        begin
          backfill(model)
        rescue e
          logger.error { "action=watch_table model=#{model} error=#{ex.message} message=failed to backfill after changefeed dropped" }
        end
      }

      changefeed = nil
      spawn do
        coordination.receive?
        changefeed.try &.stop
      end

      # NOTE: in the event of losing connection, the table is backfilled.
      Retriable.retry(on_retry: retry_handler) do
        begin
          changefeed = changes(name)
          logger.info { "action=changes model=#{model}" }
          changefeed.not_nil!.each do |change|
            event = change[:event]
            document = change[:value]
            next if document.nil?

            logger.debug { "action=watch_table event=#{event.to_s.downcase} model=#{model} document_id=#{document.id} parents=#{parents}" }

            # Asynchronously mutate Elasticsearch
            spawn do
              case event
              when RethinkORM::Changefeed::Event::Deleted
                Elastic.delete_document(
                  index: index,
                  document: document.not_nil!,
                  parents: parents,
                )
              when RethinkORM::Changefeed::Event::Created
                Elastic.create_document(
                  index: index,
                  document: document.not_nil!,
                  parents: parents,
                  no_children: no_children,
                )
              when RethinkORM::Changefeed::Event::Updated
                Elastic.update_document(
                  index: index,
                  document: document.not_nil!,
                  parents: parents,
                  no_children: no_children,
                )
              else raise Error.new
              end
            rescue e
              logger.warn { "action=watch_table event=#{event.to_s.downcase} error=#{e.class} message=#{e.message}" }
            end
          rescue e
            logger.error { "action=watch_table error=#{e.inspect_with_backtrace}" }
            changefeed.try &.stop
            raise e
          end
        end

        Fiber.yield
      end
    end

    # Elasticsearch mapping
    #############################################################################################

    # Applies a schema to an index in elasticsearch
    #
    def create_index(model : String | Class)
      index = index_name(model)
      mapping = index_schema(model)

      Elastic.apply_index_mapping(index, mapping)
    end

    # Checks if any index does not exist or has a different mapping
    #
    def consistent_indices?
      models.all? do |model|
        Elastic.check_index?(index_name(model)) && !mapping_conflict?(model)
      end
    end

    # Diff the current mapping schema (if any) against provided mapping schema
    #
    def mapping_conflict?(model)
      proposed = index_schema(model)
      existing = Elastic.get_mapping?(index_name(model))

      equivalent = Elastic.equivalent_schema?(existing, proposed)
      logger.warn { "action=mapping_conflict? model=#{model} proposed=#{proposed} existing=#{existing}" } unless equivalent

      !equivalent
    end

    # Schema Generation
    #############################################################################################

    # Generate a map of models to schemas
    def generate_schemas(models)
      schemas = {} of String => String
      models.each do |model|
        name = TableManager.document_name(model)
        schemas[name] = construct_document_schema(name)
      end
      schemas
    end

    # Generate the index type mapping structure
    def construct_document_schema(model) : String
      name = TableManager.document_name(model)
      children = children(name)
      properties = collect_index_properties(name, children)
      # Only include join if model has children
      properties = properties.merge(join_field(name, children)) unless children.empty?
      {
        mappings: {
          properties: properties,
        },
      }.to_json
    end

    # Property Generation
    #############################################################################################

    # Now that we are generating joins on the parent_id, we need to specify if we are generating
    # a child or a single document
    # Maps from crystal types to Elasticsearch field datatypes
    def generate_index_properties(model, child = false) : Array(Property)
      document_name = TableManager.document_name(model)
      properties = MODEL_METADATA[document_name][:attributes].compact_map do |field, options|
        type_tag = options.dig?(:tags, :es_type)
        if type_tag
          if !type_tag.is_a?(String) || !valid_es_type?(type_tag)
            raise Error.new("Invalid ES type '#{type_tag}' for #{field} of #{model}")
          end
          {field, {type: type_tag}}
        else
          # Map the klass of field to es_type
          es_type = klass_to_es_type(options[:klass])
          # Could the klass be mapped?
          es_type ? {field, {"type": es_type}} : nil
        end
      end
      properties << TYPE_PROPERTY
    end

    # Collects all properties relevant to an index and collapse them into a schema
    def collect_index_properties(model : String | Class, children : Array(String)? = [] of String)
      name = TableManager.document_name(model)
      index_models = children.dup << name
      # Get the properties of all relevent tables, create flat index properties
      properties.select(index_models).values.flatten.uniq.to_h
    end

    # Construct properties for given models
    def generate_properties(models)
      models.reduce({} of String => Array(Property)) do |props, model|
        name = TableManager.document_name(model)
        props[name] = generate_index_properties(name)
        props
      end
    end

    # Generate join fields for parent relations
    def join_field(model, children)
      relations = children.size == 1 ? children.first : children.sort
      {
        :join => {
          type:      "join",
          relations: {
            # Use types for defining the parent-child relation
            model => relations,
          },
        },
      }
    end

    # Allows several document types beneath a single index
    TYPE_PROPERTY = {:type, {type: "keyword"}}

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
    private def valid_es_type?(es_type)
      ES_TYPES.includes?(es_type)
    end

    # Map from a class type to an es type
    private def klass_to_es_type(klass_name) : String | Nil
      case klass_name
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
      when .starts_with?("Array(")
        # Arrays allowed as long as they are homogeneous
        klass_to_es_type(klass_name.lchop("Array(").rstrip(')'))
      else
        nil
      end
    end

    # Relations
    #############################################################################################

    # Find name and ES routing of document's parents
    def parents(model : Class | String) : Array(Parent)
      document_name = TableManager.document_name(model)
      MODEL_METADATA[document_name][:attributes].compact_map do |field, attr|
        parent_name = attr.dig? :tags, :parent
        if !parent_name.nil? && parent_name.is_a?(String)
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
      document_name = TableManager.document_name(model)
      MODEL_METADATA.compact_map do |name, metadata|
        # Ignore self
        next if name == document_name
        # Do any of the attributes define a parent relationship with current model?
        is_child = metadata[:attributes].any? do |_, attr_data|
          options = attr_data[:tags]
          !!(options && options[:parent]?.try { |p| p == document_name })
        end
        name if is_child
      end
    end

    # Property accessors via class

    def properties(klass : Class | String)
      properties[TableManager.document_name(klass)]
    end

    def index_schemas(klass : Class | String)
      index_schemas[TableManager.document_name(klass)]
    end

    # Utils
    #############################################################################################

    def cancel!
      raise Error.new("TableManager cancelled")
    end

    # Strips the namespace from the model
    def self.document_name(model)
      name = model.is_a?(Class) ? model.name : model
      name.split("::").last
    end

    def logger
      self.settings.logger
    end
  end
end
