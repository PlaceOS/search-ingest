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
    def self.es
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

      @@pool.not_nil!.acquire do |client|
        yield client
      end
    end

    # Indices
    #############################################################################################

    # Check index present in elasticsearch
    def self.check_index?(index)
      es &.head("/#{index}").success?
    end

    # Delete an index elasticsearch
    def self.delete_index(index)
      es &.delete("/#{index}").success?
    end

    # Delete several indices elasticsearch
    def self.delete_indices(indices)
      es &.delete("/#{indices.join(',')}").success?
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

      equivalent_array(left.keys, right.keys) && left.all? do |prop, mapping|
        if prop == "join"
          left_relations = mapping["relations"].as_h
          right_relations = right[prop]["relations"].as_h

          equivalent_array(left_relations.keys, right_relations.keys) && left_relations.all? do |k, v|
            # Relations can be an array of join names, or a single join name
            l = v.as_a?.try(&.map(&.as_s)) || v
            r = right_relations[k].as_a?.try(&.map(&.as_s)) || right_relations[k]
            if l.is_a? Array && r.is_a? Array
              equivalent_array(l, r)
            else
              l == r
            end
          end
        else
          right[prop] == mapping
        end
      end
    end

    # Takes 2 arrays returns whether they contain the same elements (irrespective of order)
    #
    private def self.equivalent_array(l : Array, r : Array)
      l.sort == r.sort
    end

    # Get the mapping applied to an index
    def self.get_mapping?(index) : String?
      response = es &.get("/#{index}")
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
      res = es &.put(
        "/#{index}",
        headers: self.headers,
        body: mapping
      )

      raise Error::MappingFailed.new(index: index, schema: mapping, response: res) unless res.success?
    end

    # # Bulk API calls

    enum Action
      Create
      Update
      Delete
    end

    # Post body to the Elasticsearch bulk API endpoint
    def self.bulk_operation(body)
      # Bulk requests must be newline terminated
      body += "\n"
      res = es &.post(
        "_bulk",
        headers: self.headers,
        body: body+"\n"
      )
      handle_response("save", res)
    end

    def self.generate_bulk_body(action, document, index, no_children = true, parents = [] of Parent)
      case action
      when Action::Create, Action::Update
        bulk_save(action, document, index, no_children, parents)
      when Action::Delete
        bulk_delete(document, index, parents)
      end
    end

    def self.bulk_save(action, document, index, no_children, parents)
      attributes = document.attributes
      id = document.id.not_nil!

      # FIXME: Please fix me, I am slow
      document_any = JSON.parse(document.to_json).as_h

      doc_type = self.document_type(document)
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
    def self.bulk_delete(document, index, parents) : String
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
          :_index   => index,
          :_id      => id,
          :routing => routing,
        },
      }.to_json
    end

    # # Single API calls

    # Saving Documents
    #############################################################################################

    # Replicates a RethinkDB document in ES
    # - Creates document in table index
    # - Adds document to all parent table indices, routing by the parent id
    def self.save_document(document, index, parents = [] of Parent, children = [] of String)
      return if document.nil? # FIXME: Currently, from_trusted_json is nillable, remove once fixed
      no_children = children.empty?
      self.bulk_operation(self.bulk_save(Action::Create, document, index, no_children, parents))
    end

    # Account for joins with parents
    def self.association_save(document, parents)
      id = document.id
      attributes = document.attributes

      # Save document to all parent indices
      parents.each do |parent|
        # Get the parents id to route to correct es shard
        parent_id = attributes[parent[:routing_attr]].to_s
        next if parent_id.empty?

        body = self.generate_body(document: document, parent_id: parent_id)
        self.es_save(index: parent[:index], id: id, body: body, routing: parent_id)
      end
    end

    # Deleting Documents
    #############################################################################################

    # Remove RethinkDB document from all relevant ES
    # - Remove document in the table index
    # - Add document to all parent table indices, routing by association id
    def self.delete_document(document, index, parents = [] of Parent)
      return if document.nil?
      # id = document.id || ""

      # self.association_delete(id, parents, document.attributes)

      # # Remove document from table index
      # self.es_delete(index, id)
      self.bulk_operation(self.bulk_delete(document, index, parents))
    end

    # Remove document from all parent indices
    def self.association_delete(id, parents, attributes)
      parents.each do |parent|
        # Get the parents id to route to correct es shard
        parent_id = attributes[parent[:routing_attr]].to_s
        next if parent_id.empty?

        self.es_delete(parent[:index], id, parent_id)
      end
    end

    # Document Utils
    #############################################################################################

    # Picks off the model type from the class name
    def self.document_type(document)
      document.class.name.split("::")[-1]
    end

    # Create a join field for a document body
    # Can set just the document type if document is the parent
    def self.document_join_field(document_type, parent_id = nil)
      parent_id ? {name: document_type, parent: parent_id} : document_type
    end

    # Sets the type and join field, and generates body json
    private def self.document_body(document : Hash(String, JSON::Any), document_type, parent_id = nil, no_children = true) : String
      attributes = {} of String => String | NamedTuple(name: String, parent: String)
      attributes["type"] = document_type

      # Don't set a join field if there are no children on the index
      attributes["join"] = self.document_join_field(document_type, parent_id) unless no_children

      document.merge(attributes).to_json
    end

    # Sets the type and join field, and generates body json
    private def self.generate_body(document, parent_id = nil, no_children = false) : String
      # FIXME: (SLOW!) Optimize selecting attributes that _respects_ attribute conversion
      body = JSON.parse(document.to_json).as_h

      doc_type = self.document_type(document)
      body["type"] = JSON::Any.new(doc_type)

      # Don't set a join field if there are no children on the index
      unless no_children
        body = body.merge({"join" => self.document_join_field(doc_type, parent_id)})
      end

      body.to_json
    end

    # ES API calls
    #############################################################################################

    # Save document to an elastic search index
    def self.es_save(index, id, body : String, routing : String? = nil)
      url = self.document_path(index, id, routing)
      res = es &.put(
        url,
        headers: self.headers,
        body: body
      )
      handle_response("save", res)
    end

    # Delete document from an elastic search index
    def self.es_delete(index, id, routing = nil)
      url = self.document_path(index, id, routing)
      res = es &.delete(url)
      handle_response("delete", res)
    end

    # Checks the status of a mutation in elasticsearch, ignores not_found responses.
    #
    # Raises `RubberSoul::Error`
    private def self.handle_response(action, result)
      unless result.success? || JSON.parse(result.body)["result"]? == "not_found"
        raise Error.new("ES #{action}: #{result.body}")
      end
    end

    # ES Utils
    #############################################################################################

    # Constucts the ES path
    def self.document_path(index, id, routing = nil)
      # When routing not specified, route by document id
      routing = id unless routing
      "/#{index}/_doc/#{id}?routing=#{routing}"
    end

    # Checks availablity of RethinkDB and Elasticsearch
    def self.ensure_elastic!
      response = es &.get("/")
      raise Error.new("Failed to connect to ES") unless response.success?
    end

    def self.headers
      headers = HTTP::Headers.new
      headers["Content-Type"] = "application/json"
      headers
    end

    # Delete all indices
    def self.delete_all
      es &.delete("/_all").success?
    end

    # Remove documents from indices
    # Removes from _all_ indices if no argument given.
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

      res = es &.post(url,
        headers: self.headers,
        body: query)

      res.success?
    end

    # Yields a raw HTTP client to elasticsearch
    def self.client
      HTTP::Client.new(host: self.settings.host, port: self.settings.port)
    end
  end
end
