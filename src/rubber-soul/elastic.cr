require "http"
require "habitat"

require "./error"
require "./pool"
require "./types"

module RubberSoul
  class Elastic
    # Settings for elastic client
    Habitat.create do
      setting host : String = ENV["ES_HOST"]? || "127.0.0.1"
      setting port : Int32 = ENV["ES_PORT"]?.try(&.to_i) || 9200
      setting pool_size : Int32 = ENV["ES_CONN_POOL"]?.try(&.to_i) || 10
      setting idle_pool_size : Int32 = ENV["ES_IDLE_POOL"]?.try(&.to_i) || 2
      setting pool_timeout : Float64 = ENV["ES_CONN_POOL_TIMEOUT"]?.try(&.to_f64) || 1.0
    end

    @@pool : Pool(HTTP::Client)?

    # Yield an acquired client from the pool
    #
    def self.client
      unless @@pool
        config = {
          initial_pool:  1,
          max_pool:      settings.pool_size,
          max_idle_pool: settings.idle_pool_size,
          timeout:       settings.pool_timeout,
        }

        @@pool = Pool(HTTP::Client).new(**config) do
          HTTP::Client.new(host: settings.host, port: settings.port)
        end
      end

      @@pool.not_nil!.acquire do |elastic|
        yield elastic
      end
    end

    # Single Document Requests
    #############################################################################################

    # Create a new document in ES from a RethinkORM model
    #
    def self.create_document(index, document, parents = [] of Parent, no_children = true)
      body = Elastic.bulk_save_body(
        action: Elastic::Action::Create,
        index: index,
        document: document,
        parents: parents,
        no_children: no_children,
      )
      self.bulk_operation(body)
    end

    # Update a document in ES from a RethinkORM model
    #
    def self.update_document(index, document, parents = [] of Parent, no_children = true)
      body = Elastic.bulk_save_body(
        action: Elastic::Action::Update,
        index: index,
        document: document,
        parents: parents,
        no_children: no_children,
      )
      self.bulk_operation(body)
    end

    # Delete a document in ES from a RethinkORM model
    #
    def self.delete_document(index, document, parents = [] of Parent)
      body = Elastic.bulk_delete_body(
        index: index,
        document: document,
        parents: parents,
      )
      self.bulk_operation(body)
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

    # Diff the current mapping schema (if any) against provided mapping schema
    #
    def self.mapping_conflict?(index, proposed_schema)
      existing_schema = get_mapping?(index)
      !equivalent_schema?(existing_schema, proposed_schema)
    end

    # Traverse schemas and test equality
    #
    def self.equivalent_schema?(left_schema : String?, right_schema : String?)
      return false unless left_schema && right_schema

      left = JSON.parse(left_schema)["mappings"]["properties"].as_h
      right = JSON.parse(right_schema)["mappings"]["properties"].as_h

      (left.keys.sort == right.keys.sort) && left.all? do |prop, mapping|
        if prop == "join"
          left_relations = mapping["relations"].as_h
          right_relations = right[prop]["relations"].as_h

          (left_relations.keys.sort == right_relations.keys.sort) && left_relations.all? do |k, v|
            # Relations can be an array of join names, or a single join name
            l = v.as_a?.try(&.map(&.as_s)) || v
            r = right_relations[k].as_a?.try(&.map(&.as_s)) || right_relations[k]
            if l.is_a? Array && r.is_a? Array
              l.sort == r.sort
            else
              l == r
            end
          end
        else
          right[prop] == mapping
        end
      end
    end

    # Get the mapping applied to an index
    def self.get_mapping?(index) : String?
      response = client &.get("/#{index}")
      if response.success?
        body = JSON.parse(response.body)
        body[index].as_h?
          .try(&.select("mappings"))
          .try(&.to_json)
      else
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

    # Generates the body of a Bulk request for a RethinkDB document in ES
    # - Creates document in table index
    # - Adds document to all parent table indices, routing by the parent id
    def self.bulk_save_body(action, document, index, parents = [] of Parent, no_children = true)
      doc_type = self.document_type(document)
      attributes = document.attributes
      id = document.id.not_nil!

      # FIXME: Please, I am very slow
      document_any = JSON.parse(document.to_json).as_h

      document_action_header = self.bulk_action_header(action, index, id)
      document_body = self.document_body(
        document: document_any,
        document_type: doc_type,
        no_children: no_children,
      )
      document_action = "#{document_action_header}\n#{document_body}"

      # Create actions to mutate all parent indices
      parent_actions = parents.compact_map do |parent|
        # Get the parents id to route to correct es shard
        parent_id = attributes[parent[:routing_attr]].to_s
        next if parent_id.empty?

        action_header = self.bulk_action_header(
          action: action,
          id: id,
          index: parent[:index],
          routing: parent_id,
        )

        body = self.document_body(
          document: document_any,
          document_type: doc_type,
          parent_id: parent_id
        )

        "#{action_header}\n#{body}"
      end

      {document_action, parent_actions.join('\n')}.join('\n')
    end

    # Generate delete headers for a bulk request
    #
    def self.bulk_delete_body(document, index, parents) : String
      id = document.id.not_nil!
      attributes = document.attributes
      document_action = bulk_action_header(
        action: Action::Delete,
        index: index,
        id: id,
      )

      parent_actions = parents.compact_map do |parent|
        # Get the parents id to route to correct es shard
        parent_id = attributes[parent[:routing_attr]].to_s
        next if parent_id.empty?
        bulk_action_header(
          action: Action::Delete,
          index: parent[:index],
          id: id,
          routing: parent_id,
        )
      end

      {document_action, parent_actions.join('\n')}.join('\n')
    end

    # Generates the header for an es action, preceeds an optional document
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

    # Create a join field for a document body
    # Can set just the document type if document is the parent
    #
    def self.document_join_field(document_type, parent_id = nil)
      parent_id ? {name: document_type, parent: parent_id} : document_type
    end

    # Sets the type and join field, and generates body json
    #
    private def self.document_body(document : Hash(String, JSON::Any), document_type, parent_id = nil, no_children = true) : String
      attributes = {} of String => String | NamedTuple(name: String, parent: String)
      attributes["type"] = document_type

      # Don't set a join field if there are no children on the index
      attributes["join"] = self.document_join_field(document_type, parent_id) unless no_children

      document.merge(attributes).to_json
    end

    # ES API Calls
    #############################################################################################

    # Make a request to the Elasticsearch bulk API endpoint
    #
    # Throws on failure
    def self.bulk_operation(body)
      # Bulk requests must be newline terminated
      body += "\n"
      result = client &.post(
        "_bulk",
        headers: self.headers,
        body: body + "\n"
      )

      unless result.success?
        raise Error.new("ES Bulk: #{result.body}")
      end
    end

    # Delete all indices
    #
    def self.delete_all
      client &.delete("/_all").success?
    end

    # Checks availablity of RethinkDB and Elasticsearch
    #
    def self.ensure_elastic!
      response = client &.get("/")
      raise Error.new("Failed to connect to ES") unless response.success?
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
      headers
    end

    # Constucts the ES path of a document
    #
    def self.document_path(index, id, routing = nil)
      # When routing not specified, route by document id
      routing = id unless routing
      "/#{index}/_doc/#{id}?routing=#{routing}"
    end
  end
end
