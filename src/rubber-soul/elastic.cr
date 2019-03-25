require "http"

require "./error"
require "./types"

class RubberSoul::Elastic
  # Settings for elastic client
  Habitat.create do
    setting host : String = ENV["ES_HOST"]? || "127.0.0.1"
    setting port : Int32 = ENV["ES_PORT"]?.try(&.to_i) || 9200
  end

  @@client = HTTP::Client.new(
    host: self.settings.host,
    port: self.settings.port,
  )

  # Indices
  #############################################################################################

  # Check index present in elasticsearch
  def self.check_index?(index)
    @@client.head("/#{index}").success?
  end

  # Delete an index elasticsearch
  def self.delete_index(index)
    @@client.delete("/#{index}").success?
  end

  # Delete several indices elasticsearch
  def self.delete_indices(indices)
    @@client.delete("/#{indices.join(',')}").success?
  end

  # Mapping
  #############################################################################################

  # Diff the current mapping schema (if any) against provided mapping schema
  def self.same_mapping?(index, mapping)
    existing_mapping = get_mapping?(index)
    # Convert to JSON::Any for comparison
    existing_mapping && JSON.parse(existing_mapping) == JSON.parse(mapping)
  end

  # Get the mapping applied to an index
  def self.get_mapping?(index) : String?
    response = @@client.get("/#{index}")
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
    response = @@client.put(
      "/#{index}",
      headers: self.headers,
      body: mapping
    )
    response.success?
  end

  # Saving Documents
  #############################################################################################

  # Replicates a RethinkDB document in ES
  # - Creates document in table index
  # - Adds document to all parent table indices, routing by the parent id
  def self.save_document(document, index, parents = [] of Parent, children = [] of String)
    return if document.nil? # FIXME: Currently, from_trusted_json is nillable, remove once fixed
    document.id ||= ""      # Will never be nil, this is just to collapse the nillable union

    # Saving to parent indices
    self.association_save(document, parents)

    # Saving to own index
    type = self.document_type(document)
    body = self.generate_body(type, document.attributes, no_children: children.empty?)
    self.es_save(index, document.id, body)
  end

  # Account for joins with parents
  def self.association_save(document, parents)
    type = self.document_type(document)
    attributes = document.attributes
    id = document.id

    # Save document to all parent indices
    parents.each do |parent|
      # Get the parents id to route to correct es shard
      parent_id = attributes[parent[:routing_attr]].to_s
      body = self.generate_body(type, attributes, parent_id)
      self.es_save(parent[:index], id, body, parent_id)
    end
  end

  # Deleting Documents
  #############################################################################################

  # Remove RethinkDB document from all relevant ES
  # - Remove document in the table index
  # - Add document to all parent table indices, routing by association id
  def self.delete_document(document, index, parents = [] of Parent, children = [] of String)
    return if document.nil?
    id = document.id || ""

    self.association_delete(id, parents, document.attributes)

    # Remove document from table index
    self.es_delete(index, id)
  end

  # Remove document from all parent indices
  def self.association_delete(id, parents, attributes)
    parents.each do |parent|
      # Get the parents id to route to correct es shard
      parent_id = attributes[parent[:routing_attr]].to_s
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
  def self.document_join_field(type, parent_id = nil)
    parent_id ? {name: type, parent: parent_id} : type
  end

  # Sets the type and join field, and generates body json
  private def self.generate_body(type, attributes, parent_id = nil, no_children = false) : String
    body = attributes.dup
    body[:type] = type

    # Don't set a join field if there are no children on the index
    unless no_children
      body = body.merge({:join => self.document_join_field(type, parent_id)})
    end
    body.to_json
  end

  # ES API calls
  #############################################################################################

  # Save document to an elastic search index
  def self.es_save(index, id, body : String, routing : String? = nil)
    url = self.document_path(index, id, routing)
    res = @@client.put(
      url,
      headers: self.headers,
      body: body
    )
    raise RubberSoul::Error.new("ES save: #{res.body}") unless res.success?
  end

  # Delete document from an elastic search index
  def self.es_delete(index, id, routing = nil)
    url = self.document_path(index, id, routing)
    res = @@client.delete(url)
    raise RubberSoul::Error.new("ES delete: #{res.body}") unless res.success?
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
    response = @@client.get("/")
    raise Error.new("Failed to connect to ES") unless response.success?
  end

  def self.headers
    headers = HTTP::Headers.new
    headers["Content-Type"] = "application/json"
    headers
  end

  # Delete all indices
  def self.delete_all
    @@client.delete("/_all").success?
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

    res = @@client.post(url,
      headers: self.headers,
      body: query)

    res.success?
  end

  # Yields the raw HTTP client to elasticsearch
  def self.client
    @@client
  end
end
