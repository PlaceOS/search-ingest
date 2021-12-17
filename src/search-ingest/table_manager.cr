require "habitat"
require "log"
require "promise"
require "rethinkdb-orm"
require "retriable"

require "./elastic"
require "./types"
require "./schemas"

# Class to manage rethinkdb models sync with elasticsearch
module SearchIngest
  class TableManager
    Log = ::Log.for(self)

    macro finished
      __generate_methods([:changes, :all])
    end

    macro __generate_methods(methods)
      {% for method in methods %}
        # Dispatcher for {{ method.id }}
        def {{ method.id }}(model)
          Log.trace { "{{ method.id }} for #{model}" }
          # Generate {{ method.id }} method calls
          case SearchIngest::Schemas.document_name(model)
          {% for klass in SearchIngest::Schemas::MODELS.keys %}
          when SearchIngest::Schemas.document_name({{ klass.id }})
            {{ klass.id }}.{{ method.id }}(runopts: {"read_mode" => "majority"})
          {% end %}
          else
            raise "No {{ method.id }} for '#{model}'"
          end
        end
      {% end %}
    end

    # Initialisation
    #############################################################################################

    # Metadata related to elasticsearch extracted from `active-model` classes
    getter schema_data : Schemas

    delegate models, to: schema_data

    def initialize(
      models = MANAGED_TABLES,
      backfill : Bool = false,
      watch : Bool = false
    )
      Log.debug { {bulk_api: Elastic.bulk?, backfill: backfill, watch: watch, message: "starting TableManager"} }

      @schema_data = Schemas.new(models)

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
    def backfill_all : Bool
      Promise.map(models) { |m| backfill(m) }.get.all?
    end

    # Backfills from a model to all relevent indices
    def backfill(model) : Bool
      Log.info { {message: "backfilling", model: model.to_s} }
      count = Elastic.bulk? ? bulk_backfill(model) : single_requests_backfill(model)

      if count
        Log.info { {method: "backfill", model: model.to_s, count: count} }
        true
      else
        Log.warn { {method: "failed to backfill", model: model.to_s} }
        false
      end
    end

    # Backfill via the Elasticsearch Bulk API
    protected def bulk_backfill(model) : Int32?
      backfill_batch(model) do |docs|
        index = schema_data.index_name(model)
        parents = schema_data.parents(model)
        no_children = schema_data.children(model).empty?

        actions = docs.map do |doc|
          Elastic.bulk_action(
            action: Elastic::Action::Create,
            document: doc,
            index: index,
            parents: parents,
            no_children: no_children,
          )
        end

        Promise.defer {
          Elastic.bulk_operation(actions.join('\n'))
          Log.debug { {method: "backfill", model: model.to_s, subcount: actions.size} }
          actions.size
        }
      end
    end

    # Backfill via the standard Elasticsearch API
    protected def single_requests_backfill(model) : Int32?
      backfill_batch(model) do |docs|
        index = schema_data.index_name(model)
        parents = schema_data.parents(model)
        no_children = schema_data.children(model).empty?

        docs.map do |doc|
          Promise.defer {
            Elastic.single_action(
              action: Elastic::Action::Create,
              document: doc,
              index: index,
              parents: parents,
              no_children: no_children,
            )
            1
          }
        end
      end
    end

    protected def backfill_batch(model)
      errored = false
      promises = [] of Promise(Int32)
      all(model).in_groups_of(100, reuse: true) do |docs|
        batch = docs.compact
        promise = yield batch

        if promise.is_a? Array
          promise.map &.catch do |error|
            Log.error(exception: error) { {method: "backfill", model: model.to_s, missed: batch.size} }
            errored = true
            0
          end

          promises.concat promise
        else
          promise.catch do |error|
            Log.error(exception: error) { {message: "backfill", model: model.to_s, missed: batch.size} }
            errored = true
            0
          end

          promises << promise
        end
      end

      total = promises.sum(0, &.get)
      total unless errored
    end

    # Reindex
    #############################################################################################

    # Clear and update all index mappings
    def reindex_all : Bool
      Promise.map(models) { |m| reindex(m) }.get.all?
    end

    # Clear, update mapping an ES index and refill with rethinkdb documents
    def reindex(model : String | Class) : Bool
      Log.info { {method: "reindex", model: model.to_s} }
      index = schema_data.index_name(model)
      # Delete index
      Elastic.delete_index(index)

      # Apply current mapping
      create_index(model)

      true
    rescue e
      Log.error(exception: e) { {method: "reindex", message: "failed to reindex", model: model.to_s} }

      false
    end

    # Watch
    #############################################################################################

    private getter coordination : Channel(Nil) = Channel(Nil).new

    delegate close, to: coordination

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

    def watch_table(model)
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
          changefeed = changes(model)
          changefeed.not_nil!.each do |change|
            return if stopped?(model)
            spawn do
              process_event(model, change)
            end
          end
          raise "Premature changefeed closure" unless stopped?(model)
        rescue e
          Log.error(exception: e) { "in watch_table" }
          changefeed.try &.stop
          raise e
        end
      end
    end

    private def process_event(model, change)
      index = schema_data.index_name(model)
      parents = schema_data.parents(model)
      no_children = schema_data.children(model).empty?

      event, document = change.event, change.value
      Log.debug { {method: "process_event", event: event.to_s.downcase, model: model.to_s, document_id: document.id, parents: parents} }

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

    private def stopped?(model)
      coordination.closed?.tap do |closed|
        Log.debug { {message: "unwatching table", model: model.to_s} } if closed
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
      index = schema_data.index_name(model)
      mapping = schema_data.index_schema(model)

      Elastic.apply_index_mapping(index, mapping)
    end

    # Checks if any index does not exist or has a different mapping
    #
    def consistent_indices?
      models.all? do |model|
        Elastic.check_index?(schema_data.index_name(model)) && !mapping_conflict?(model)
      end
    end

    # Diff the current mapping schema (if any) against provided mapping schema
    #
    def mapping_conflict?(model)
      proposed = schema_data.index_schema(model)
      existing = Elastic.get_mapping?(schema_data.index_name(model))

      equivalent = Schemas.equivalent_schema?(existing, proposed)
      Log.warn { {model: model.to_s, proposed: proposed, existing: existing, message: "index mapping conflict"} } unless equivalent

      !equivalent
    end

    # Utils
    #############################################################################################

    def cancel!
      raise Error.new("TableManager cancelled")
    end
  end
end
