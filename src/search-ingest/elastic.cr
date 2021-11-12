require "db"
require "habitat"
require "http"
require "json"

require "../constants"
require "./error"
require "./types"

module SearchIngest
  class Elastic
    Log = ::Log.for(self)

    # Whether or not to use the bulk api
    class_property? bulk : Bool = !ES_DISABLE_BULK

    # Settings for elastic client
    Habitat.create do
      setting uri : URI? = ES_URI
      setting host : String = ES_HOST
      setting port : Int32 = ES_PORT
      setting tls : Bool = ES_TLS
      setting pool_size : Int32 = ES_CONN_POOL || SearchIngest::MANAGED_TABLES.size
      setting idle_pool_size : Int32 = ES_IDLE_POOL || (SearchIngest::MANAGED_TABLES.size // 4)
      setting pool_timeout : Float64 = ES_CONN_POOL_TIMEOUT
    end

    forward_missing_to @client

    def initialize(
      host : String = settings.host,
      port : Int32 = settings.port,
      tls : Bool = settings.tls,
      uri : URI? = settings.uri
    )
      if uri.nil?
        @client = HTTP::Client.new(host: host, port: port, tls: tls)
      else
        if ES_TLS
          context = OpenSSL::SSL::Context::Client.new
          context.verify_mode = OpenSSL::SSL::VerifyMode::NONE
        end
        @client = HTTP::Client.new(uri: uri, tls: context)
      end
    end

    @@pool : DB::Pool(Elastic)?

    # Yield an acquired client from the pool
    #
    def self.client
      pool = (@@pool ||= DB::Pool(Elastic).new(
        initial_pool_size: settings.pool_size // 4,
        max_pool_size: settings.pool_size,
        max_idle_pool_size: settings.idle_pool_size,
        checkout_timeout: settings.pool_timeout
      ) { Elastic.new }).as(DB::Pool(Elastic))

      pool.retry do
        client = pool.checkout
        begin
          result = yield client
          pool.release(client)
          result
        rescue error : IO::Error
          Log.warn(exception: error) { "retrying connection" }
          raise DB::PoolResourceLost.new(client)
        rescue error
          # All other errors
          begin
            client.close
          rescue
          end
          pool.delete(client)
          raise error
        end
      end
    end

    # Single Document Requests
    #############################################################################################

    # Create a new document in ES from a RethinkORM model
    #
    def self.create_document(index, document, parents = [] of Parent, no_children = true)
      run_action(action: Action::Create, index: index, document: document, parents: parents, no_children: no_children)
    end

    # Update a document in ES from a RethinkORM model
    #
    def self.update_document(index, document, parents = [] of Parent, no_children = true)
      run_action(action: Action::Update, index: index, document: document, parents: parents, no_children: no_children)
    end

    # Delete a document in ES from a RethinkORM model
    #
    def self.delete_document(index, document, parents = [] of Parent)
      run_action(action: Action::Delete, index: index, document: document, parents: parents)
    end

    private def self.run_action(action, index, document, parents, **args)
      if self.bulk?
        body = self.bulk_action(action, document, index, parents, **args)
        begin
          self.bulk_operation(body)
        rescue e
          Log.error(exception: e) { {message: "failed to mutate document", action: action.to_s.downcase, id: document.id, index: index} }
        end
      else
        self.single_action(action, document, index, parents, **args)
      end
    end

    # Indices
    #############################################################################################

    # Check index present in elasticsearch
    def self.check_index?(index)
      client &.head("/#{index}").success?
    end

    # Delete an index elasticsearch
    def self.delete_index(index)
      client &.delete("/#{index}").success?
    end

    # Delete several indices elasticsearch
    def self.delete_indices(indices)
      client &.delete("/#{indices.join(',')}").success?
    end

    # Mapping
    #############################################################################################

    # Get the mapping applied to an index
    def self.get_mapping?(index) : String?
      response = client &.get("/#{index}")
      if response.success?
        body = JSON.parse(response.body)
        body[index].as_h?
          .try(&.select("mappings"))
          .try(&.to_json)
      else
        Log.error { {message: "failed to get mapping", index: index} }
        nil
      end
    end

    # Applies a mapping to an index in elasticsearch
    def self.apply_index_mapping(index, mapping)
      res = client &.put(
        "/#{index}",
        headers: self.headers,
        body: mapping
      )

      raise Error::MappingFailed.new(index: index, schema: mapping, response: res) unless res.success?
    end

    # Bulk API Body Generation
    #############################################################################################

    enum Action
      Create
      Update
      Delete
    end

    def self.single_request(
      action : Action,
      index : String,
      id : String,
      document_type : String,
      document_any : Hash(String, JSON::Any)? = nil,
      parent_id : String? = nil,
      no_children : Bool = true
    )
      case action
      in .update?, .create?
        body = self.document_body(
          document: document_any.not_nil!,
          document_type: document_type,
          no_children: no_children,
          parent_id: parent_id,
        )

        self.single_upsert(
          index: index,
          id: id,
          document: body,
          routing: parent_id,
        )
      in .delete?
        self.single_delete(
          index: index,
          id: id,
          routing: parent_id,
        )
      end
    end

    # Skip replication to own index if the document type is self-associated and has a parent
    #
    def self.skip_replication?(attributes, index : String, parents : Array(Parent))
      parents.any? do |parent|
        parent[:index] == index && !attributes[parent[:routing_attr]].to_s.empty?
      end
    end

    # Generates the body of a Bulk request for a RethinkDB document in ES
    # - Creates document in table index
    # - Adds document to all parent table indices, routing by the parent id
    def self.single_action(action : Action, document, index : String, parents : Array(Parent) = [] of Parent, no_children : Bool = true)
      id = document.id.as(String)
      doc_type = self.document_type(document)
      attributes = document.attributes

      # FIXME: Please, I am very slow
      doc_any = case action
                in .create? then JSON.parse(document.to_json).as_h
                in .update? then JSON.parse(document.changed_json).as_h
                in .delete? then nil
                end

      args = {
        action:        action,
        document_any:  doc_any,
        document_type: doc_type,
        index:         index,
        id:            id,
        no_children:   no_children,
      }

      unless skip_replication?(attributes, index, parents)
        begin
          self.single_request(**args)
        rescue e
          Log.error(exception: e) { {
            message: "failed to mutate document's index",
            action:  action.to_s,
            index:   index,
            id:      id,
          } }
          return
        end
      end

      # Actions to mutate all parent indices
      parents.each do |parent|
        # Get the parents id to route to correct es shard
        parent_id = attributes[parent[:routing_attr]].to_s

        next if parent_id.empty?

        begin
          self.single_request(
            **args.merge({
              index:       parent[:index],
              parent_id:   parent_id,
              no_children: false,
            })
          )
        rescue e
          Log.error(exception: e) { {
            message:      "failed to mutate document's parent index",
            action:       action.to_s,
            index:        index,
            parent_index: parent[:index],
            id:           id,
            parent_id:    parent_id,
          } }
        end
      end
    end

    # Generates the body of a Bulk request for a RethinkDB document in ES
    # - Creates document in table index
    # - Adds document to all parent table indices, routing by the parent id
    def self.bulk_action(action, document, index, parents = [] of Parent, no_children = true)
      id = document.id.as(String)
      doc_type = self.document_type(document)
      attributes = document.attributes

      # FIXME: Please, I am very slow
      doc_any = case action
                in .create?
                  JSON.parse(document.to_json).as_h
                in .update?
                  JSON.parse(document.changed_json).as_h
                in .delete?
                  nil
                end

      actions = [] of String

      unless skip_replication?(attributes, index, parents)
        actions << self.bulk_request(
          action: action,
          document_any: doc_any,
          document_type: doc_type,
          index: index,
          id: id,
          no_children: no_children
        )
      end

      # Create actions to mutate all parent indices
      parents.each do |parent|
        # Get the parents id to route to correct es shard
        parent_id = attributes[parent[:routing_attr]].to_s

        next if parent_id.empty?

        actions << self.bulk_request(
          action: action,
          document_any: doc_any,
          document_type: doc_type,
          index: parent[:index],
          id: id,
          parent_id: parent_id,
          no_children: false,
        )
      end

      actions.join('\n')
    end

    # Constructs the bulk request for a single ES document
    def self.bulk_request(
      action : Action,
      index : String,
      id : String,
      document_type : String,
      document_any : Hash(String, JSON::Any)? = nil,
      parent_id : String? = nil,
      no_children : Bool = true
    )
      case action
      in .update?
        header = self.bulk_action_header(action: action,
          index: index,
          id: id,
          routing: parent_id
        )

        raise "Missing document_any in bulk request" if document_any.nil?

        body = self.document_body(
          document: document_any,
          document_type: document_type,
          no_children: no_children,
          parent_id: parent_id,
        ).to_json

        "#{header}\n#{self.update_body(body)}"
      in .create?
        header = self.bulk_action_header(
          action: action,
          index: index,
          id: id,
          routing: parent_id,
        )

        raise "Missing document_any in bulk request" if document_any.nil?

        body = self.document_body(
          document: document_any,
          document_type: document_type,
          no_children: no_children,
          parent_id: parent_id
        ).to_json

        "#{header}\n#{body}"
      in .delete?
        self.bulk_action_header(
          action: action,
          index: index,
          id: id,
          routing: parent_id,
        )
      end.not_nil! # Crystal should check for enum exhaustion in case statements.
    end

    # Generates the header for an es action, precedes an optional document
    #
    def self.bulk_action_header(action : Action, index : String, id : String, routing : String? = nil)
      routing = id unless routing
      {
        action.to_s.downcase => {
          :_index  => index,
          :_id     => id,
          :routing => routing,
        },
      }.to_json
    end

    # Document Utils
    #############################################################################################

    # Picks off the model type from the class name
    #
    def self.document_type(document)
      document.class.name.split("::")[-1]
    end

    # Embeds document inside doc field.
    # _the bulk api sucks_
    #
    def self.update_body(document)
      %({"doc": #{document}, "doc_as_upsert": true})
    end

    # Create a join field for a document body
    # Can set just the document type if document is the parent
    #
    def self.document_join_field(document_type, parent_id = nil)
      parent_id ? {name: document_type, parent: parent_id} : document_type
    end

    # Single request upsert
    def self.single_upsert(index : String, id : String, document, routing : String? = nil)
      body = {
        doc:           document,
        doc_as_upsert: true,
      }

      params = HTTP::Params{"routing" => routing || id}
      path = "/#{index}/_update/#{id}?#{params}"

      result = client &.post(
        path,
        headers: self.headers,
        body: body.to_json,
      )

      unless result.success?
        raise Error.new("ES Single request: #{body} #{result.body}")
      end
    end

    # Single request delete
    def self.single_delete(index : String, id : String, routing : String? = nil)
      params = HTTP::Params{"routing" => routing || id}
      path = "/#{index}/_doc/#{id}?#{params}"

      result = client &.delete(
        path,
        headers: self.headers,
      )

      unless result.success?
        raise Error.new("ES single request:##{result.body}")
      end
    end

    # Sets the type and join field, and generates body json
    #
    private def self.document_body(document : Hash(String, JSON::Any), document_type, parent_id = nil, no_children = true)
      attributes = {} of String => String | NamedTuple(name: String, parent: String)
      attributes["_document_type"] = document_type

      # Don't set a join field if there are no children on the index
      attributes["join"] = self.document_join_field(document_type, parent_id) unless no_children

      document.merge(attributes)
    end

    # ES API Calls
    #############################################################################################

    # Make a request to the Elasticsearch bulk API endpoint
    #
    # Throws on failure
    def self.bulk_operation(body)
      # Bulk requests must be newline terminated
      result = client &.post(
        "_bulk",
        headers: self.headers,
        body: body + "\n"
      )

      unless result.success?
        raise Error.new("ES Bulk: #{body.strip} #{result.body}")
      end
    end

    # Delete all indices
    #
    def self.delete_all
      client &.delete("/_all").success?
    end

    # Checks availability of Elasticsearch
    #
    def self.healthy?
      response = client &.get("/_cluster/health")
      if response.success?
        body = ClusterHealth.from_json(response.body)

        # Cluster is functional in yellow -> green states
        case body.status
        in .yellow?, .green? then true
        in .red?
          Log.warn { "cluster is up, but unhealthy" }
          false
        end
      else
        Log.warn { "health request failed: #{response.body}" }
        false
      end
    rescue e
      Log.warn { "failed to get elasticsearch health status: #{e.message}" }
      false
    end

    struct ClusterHealth
      include JSON::Serializable

      enum Status
        Green
        Yellow
        Red
      end

      getter status : Status

      getter cluster_name : String

      getter timed_out : Bool

      getter number_of_nodes : Int32

      getter number_of_data_nodes : Int32

      getter active_primary_shards : Int32

      getter active_shards : Int32

      getter relocating_shards : Int32

      getter initializing_shards : Int32

      getter unassigned_shards : Int32

      getter delayed_unassigned_shards : Int32

      getter number_of_pending_tasks : Int32

      getter number_of_in_flight_fetch : Int32

      getter task_max_waiting_in_queue_millis : Int32

      getter active_shards_percent_as_number : Float32
    end

    # Remove documents from indices
    # Removes from _all_ indices if no argument given.
    #
    def self.empty_indices(indices : Array(String)? = nil)
      query = {
        query: {
          match_all: {} of String => String,
        },
      }.to_json

      url = if indices && !indices.empty?
              "/#{indices.join(',')}/_delete_by_query"
            else
              "/_all/_delete_by_query"
            end

      res = client &.post(url,
        headers: self.headers,
        body: query)

      res.success?
    end

    # ES Utils
    #############################################################################################

    # Generate JSON header for ES requests
    #
    def self.headers
      headers = HTTP::Headers.new
      headers["Content-Type"] = "application/json"
      headers["Accept"] = "application/json"
      headers
    end

    # Constructs the ES path of a document
    #
    def self.document_path(index, id, routing = nil)
      # When routing not specified, route by document id
      routing = id unless routing
      "/#{index}/_doc/#{id}?routing=#{routing}"
    end

    # DB::Pool stubs
    #############################################################################################

    # :nodoc:
    def before_checkout
    end

    # :nodoc:
    def after_release
    end
  end
end
