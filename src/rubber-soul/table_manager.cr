require "future"
require "habitat"
require "log"
require "promise"
require "rethinkdb-orm"
require "retriable"

require "./elastic"
require "./types"

# Class to manage rethinkdb models sync with elasticsearch
module RubberSoul
  class TableManager
    Log = ::Log.for(self)

    alias Property = Tuple(Symbol, NamedTuple(type: String) | NamedTuple(type: String, fields: Hash(String, NamedTuple(type: String))))

    # Map class name to model properties
    getter properties : Hash(String, Array(Property)) = {} of String => Array(Property)

    # Map from class name to schema
    getter index_schemas : Hash(String, String) = {} of String => String

    # Class names of managed tables
    getter models : Array(String) = [] of String

    private getter coordination : Channel(Nil) = Channel(Nil).new

    macro finished
      # All RethinkORM models with abstract and empty classes removed
      # :nodoc:
      MODELS = {} of Nil => Nil
      __create_model_metadata
      __generate_methods([:changes, :all])
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
      MODEL_METADATA[TableManager.document_name(model)].table_name
    end

    # Initialisation
    #############################################################################################

    def initialize(
      klasses : Array(Class) = MANAGED_TABLES,
      backfill : Bool = false,
      watch : Bool = false
    )
      Log.debug { {bulk_api: Elastic.bulk?, backfill: backfill, watch: watch, message: "starting TableManager"} }

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
        Log.info { "reindexing all indices to consistency" }
        reindex_all
      end

      backfill_all if backfill
    end

    # Backfill
    #############################################################################################

    # Save all documents in all tables to the correct indices
    def backfill_all
      Promise.map(models) { |m| backfill(m) }.get
      Fiber.yield
    end

    protected def bulk_backfill(model)
      index = index_name(model)
      parents = parents(model)
      no_children = children(model).empty?

      futures = [] of Future::Compute(Int32)
      all(model).in_groups_of(100, reuse: true) do |docs|
        actions = docs.compact_map do |doc|
          next if doc.nil?
          Elastic.bulk_action(
            action: Elastic::Action::Create,
            document: doc,
            index: index,
            parents: parents,
            no_children: no_children,
          )
        end

        futures << future {
          begin
            Elastic.bulk_operation(actions.join('\n'))
            Log.debug { {method: "backfill", model: model.to_s, subcount: actions.size} }
            actions.size
          rescue e
            Log.error(exception: e) { {method: "backfill", model: model.to_s, missed: actions.size} }
            0
          end
        }
      end

      futures.sum(0, &.get)
    end

    protected def single_requests_backfill(model)
      index = index_name(model)
      parents = parents(model)
      no_children = children(model).empty?

      futures = [] of Future::Compute(Int32)
      all(model).in_groups_of(100, reuse: true) do |docs|
        docs.each do |doc|
          next if doc.nil?
          futures << future {
            begin
              Elastic.single_action(
                action: Elastic::Action::Create,
                document: doc,
                index: index,
                parents: parents,
                no_children: no_children,
              )
              1
            rescue e
              Log.error(exception: e) { {method: "backfill", model: model.to_s} }
              0
            end
          }
        end
      end
      futures.sum(0, &.get)
    end

    # Backfills from a model to all relevent indices
    def backfill(model)
      Log.info { {message: "backfilling", model: model.to_s} }
      count = Elastic.bulk? ? bulk_backfill(model) : single_requests_backfill(model)
      Log.info { {method: "backfill", model: model.to_s, count: count} }
    end

    # Reindex
    #############################################################################################

    # Clear and update all index mappings
    def reindex_all
      Promise.map(models) { |m| reindex(m) }.get
      Fiber.yield
    end

    # Clear, update mapping an ES index and refill with rethinkdb documents
    def reindex(model : String | Class)
      Log.info { {method: "reindex", model: model.to_s} }
      name = TableManager.document_name(model)

      index = index_name(name)
      # Delete index
      Elastic.delete_index(index)
      # Apply current mapping
      create_index(name)
    rescue e
      Log.error(exception: e) { {method: "reindex", model: model.to_s} }
    end

    # Watch
    #############################################################################################

    def watch_tables(models)
      models.each do |model|
        spawn do
          begin
            watch_table(model)
          rescue e
            Log.error(exception: e) { {method: "watch_table", model: model.to_s} }
            # Fatal error
            abort("Failure while watching #{model}'s table")
          end
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

      changefeed = nil
      spawn do
        coordination.receive?
        Log.warn { {method: "watch_table", message: "table_manager stopped"} }
        changefeed.try &.stop
      end

      # NOTE: in the event of losing connection, the table is backfilled.
      Retriable.retry(
        base_interval: 50.milliseconds,
        max_elapsed_time: 2.minutes,
        on_retry: ->(e : Exception, _n : Int32, _t : Time::Span, _i : Time::Span) { handle_retry(model, e) },
      ) do
        begin
          return if stopped?(model)
          changefeed = changes(name)
          Log.info { {method: "changes", model: model.to_s} }
          changefeed.not_nil!.each do |change|
            return if stopped?(model)

            event, document = change.event, change.value
            Log.debug { {method: "watch_table", event: event.to_s.downcase, model: model.to_s, document_id: document.id, parents: parents} }
            spawn do
              begin
                case event
                in .deleted?
                  Elastic.delete_document(
                    index: index,
                    document: document,
                    parents: parents,
                  )
                in .created?
                  Elastic.create_document(
                    index: index,
                    document: document,
                    parents: parents,
                    no_children: no_children,
                  )
                in .updated?
                  Elastic.update_document(
                    index: index,
                    document: document,
                    parents: parents,
                    no_children: no_children,
                  )
                end
                Fiber.yield
              rescue e
                Log.warn(exception: e) { {message: "when replicating to elasticsearch", event: event.to_s.downcase} }
              end
            end
          rescue e
            Log.error(exception: e) { "in watch_table" }
            changefeed.try &.stop
            raise e
          end
        end

        Fiber.yield
      end
    end

    private def stopped?(model)
      coordination.closed?.tap do |closed|
        Log.debug { {message: "unwatching table", table: model.to_s} } if closed
      end
    end

    private def handle_retry(model, exception : Exception?)
      if exception
        Log.warn(exception: exception) { {model: model.to_s, message: "backfilling after changefeed error"} }
        backfill(model)
      end
    rescue e
      Log.error(exception: e) { {model: model.to_s, message: "failed to backfill after changefeed dropped"} }
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
      Log.warn { {model: model.to_s, proposed: proposed, existing: existing, message: "index mapping conflict"} } unless equivalent

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

    private INDEX_SETTINGS = {
      analysis: {
        analyzer: {
          default: {
            tokenizer: "whitespace",
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
    }

    # Generate the index type mapping structure
    def construct_document_schema(model) : String
      name = TableManager.document_name(model)
      children = children(name)
      properties = collect_index_properties(name, children)
      # Only include join if model has children
      properties = properties.merge(join_field(name, children)) unless children.empty?
      {
        settings: INDEX_SETTINGS,
        mappings: {
          properties: properties,
        },
      }.to_json
    end

    # Property Generation
    #############################################################################################

    def parse_attribute_type(klass, tag) : {type: String}?
      return unless tag.is_a? String?
      type = tag || klass_to_es_type(klass)
      {type: type} if type && valid_es_type?(type)
    end

    def parse_subfield(subfield : String)
      {fields: {subfield => {type: subfield}}} if valid_es_type?(subfield)
    end

    # Now that we are generating joins on the parent_id, we need to specify if we are generating
    # a child or a single document
    # Maps from crystal types to Elasticsearch field datatypes
    def generate_index_properties(model, child = false) : Array(Property)
      document_name = TableManager.document_name(model)

      properties = MODEL_METADATA[document_name].attributes.compact_map do |field, options|
        type_tag = options.tags[:es_type]?
        subfield = options.tags[:es_subfield]?

        type_mapping = parse_attribute_type(options.klass, type_tag)
        if type_mapping.nil?
          Log.error { "Invalid ES type '#{type_tag}' for #{field} of #{model}" }
          nil
        else
          if subfield.is_a? String
            subfield_mapping = parse_subfield(subfield)
            if subfield_mapping.nil?
              Log.error { "Invalid ES subfield type '#{subfield}' for #{subfield} of #{model}" }
            else
              # Merge the subfield mapping
              type_mapping = type_mapping.merge(subfield_mapping)
            end
          end

          {field, type_mapping}
        end
      end

      properties << TYPE_PROPERTY
    end

    # Collects all properties relevant to an index and collapse them into a schema
    def collect_index_properties(model : String | Class, children : Array(String)? = [] of String)
      name = TableManager.document_name(model)
      index_models = children.dup << name
      # Get the properties of all relevent tables, create flat index properties
      properties.select(index_models).values.flatten.uniq!.to_h
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
    TYPE_PROPERTY = {:_document_type, {type: "keyword"}}

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
      return false unless es_type.is_a?(String)
      ES_TYPES.includes?(es_type)
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
      document_name = TableManager.document_name(model)
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
      document_name = TableManager.document_name(model)
      MODEL_METADATA.compact_map do |name, metadata|
        # Ignore self
        next if name == document_name
        # Do any of the attributes define a parent relationship with current model?
        is_child = metadata.attributes.any? do |_, metadata|
          !!metadata.tags[:parent]?.try(&.==(document_name))
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
  end
end
