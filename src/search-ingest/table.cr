require "placeos-resource"
require "promise"

require "./elastic"
require "./schemas"

module SearchIngest
  class Table(T) < ::PlaceOS::Resource(T)
    module Interface
      abstract def start
      abstract def backfill
      abstract def reindex
      abstract def consistent_index?
      abstract def stop
    end

    include Interface

    getter schema_data : Schemas

    def initialize(@schema_data : Schemas, **args)
      super(**args)
    end

    def process_resource(action : PlaceOS::Resource::Action, resource model : T) : PlaceOS::Resource::Result
      index = schema_data.index_name(T)
      parents = schema_data.parents(T)
      no_children = schema_data.children(T).empty?

      Log.debug { {method: "process_resource", action: action.to_json, model: model.to_s, document_id: model.id, parents: parents} }

      args = {index: index, parents: parents, document: model}

      case action
      in .deleted? then Elastic.delete_document(**args)
      in .created? then Elastic.create_document(**args.merge(no_children: no_children))
      in .updated? then Elastic.update_document(**args.merge(no_children: no_children))
      end

      Fiber.yield

      PlaceOS::Resource::Result::Success
    rescue e
      Log.warn(exception: e) { {message: "when replicating to elasticsearch", action: action.to_json} }
      PlaceOS::Resource::Result::Error
    end

    def on_reconnect
      Log.warn { {message: "backfilling after changefeed error", table: T.table_name} }
      backfill
    end

    # Override `load_resources` in favour of the batching provided by `backfill`
    #
    def load_resources
      backfill
    end

    # Clear, update mapping an ES index and refill with rethinkdb documents
    #
    def reindex : Bool
      Log.info { {method: "reindex", table: T.table_name} }
      index = schema_data.index_name(T)

      # Delete index
      Elastic.delete_index(index)

      # Apply current mapping
      create_index

      true
    rescue e
      Log.error(exception: e) { {method: "reindex", message: "failed to reindex", table: T.table_name} }

      false
    end

    # Backfills from a table to all relevent indices
    #
    def backfill : Bool
      Log.with_context(table: T.table_name) do
        Log.debug { "backfilling" }
        count = Elastic.bulk? ? bulk_backfill : single_requests_backfill

        if count.nil?
          Log.warn { "failed to backfill" }
          false
        else
          Log.debug { {method: "backfill", count: count} }
          true
        end
      end
    end

    # Backfill via the bulk Elasticsearch API
    #
    protected def backfill_batch
      errored = false
      promises = [] of Promise(Int32)
      T.all.in_groups_of(100, reuse: true) do |docs|
        batch = docs.compact
        Log.with_context(method: "backfill", table: T.table_name) do
          promise = yield batch

          if promise.is_a? Array
            promise.map &.catch do |error|
              Log.error(exception: error) { {missed: batch.size} }
              errored = true
              0
            end

            promises.concat promise
          else
            promise.catch do |error|
              Log.error(exception: error) { {missed: batch.size} }
              errored = true
              0
            end

            promises << promise
          end
        end
      end

      total = promises.sum(0, &.get)
      total unless errored
    end

    # Backfill via the standard Elasticsearch API
    #
    protected def single_requests_backfill : Int32?
      backfill_batch do |docs|
        index = schema_data.index_name(T)
        parents = schema_data.parents(T)
        no_children = schema_data.children(T).empty?

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

    # Backfill via the Elasticsearch Bulk API
    #
    protected def bulk_backfill : Int32?
      backfill_batch do |docs|
        index = schema_data.index_name(T)
        parents = schema_data.parents(T)
        no_children = schema_data.children(T).empty?

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
          Log.debug { {subcount: actions.size} }
          actions.size
        }
      end
    end

    # Elasticsearch Index
    ###############################################################################################

    # Applies a schema to an index in elasticsearch
    #
    def create_index
      index = schema_data.index_name(T)
      mapping = schema_data.index_schema(T)

      Elastic.apply_index_mapping(index, mapping)
    end

    def consistent_index?
      Elastic.check_index?(schema_data.index_name(T)) && !mapping_conflict?
    end

    # Diff the current mapping schema (if any) against provided mapping schema
    #
    def mapping_conflict?
      proposed = schema_data.index_schema(T)
      existing = Elastic.get_mapping?(schema_data.index_name(T))

      equivalent = Schemas.equivalent_schema?(existing, proposed)
      Log.warn { {table: T.table_name, proposed: proposed, existing: existing, message: "index mapping conflict"} } unless equivalent

      !equivalent
    end
  end
end
