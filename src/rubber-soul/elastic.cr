require "./error"

class RubberSoul::Elastic
  # Settings for elastic client
  Habitat.create do
    setting host : String = ENV["ES_HOST"]? || "127.0.0.1"
    setting port : Int32 = ENV["ES_PORT"]?.try(&.to_i) || 9200
  end

  @@client = HTTP::Client.new(
    host: self.settings.host,
    port: self.settings.port
  )

  # Indices
  def self.check_index?(index)
    @@client.head("/#{index}").success?
  end

  def self.delete_index(index)
    @@client.delete("/#{index}").success?
  end

  def self.delete_indices(indices)
    @@client.delete("/#{indices.join(',')}").success?
  end

  def self.get_mapping(index)
    response = @@client.get("/#{index}")
    if response.success?
      JSON.parse(response.body)[index]?.try(&.to_json)
    else
      nil
    end
  end

  def self.apply_index_mapping(index, mapping)
    response = @@client.put(
      "/#{index}",
      headers: self.headers,
      body: mapping
    )
    response.success?
  end

  # Documents
  # Remove RethinkDB document from all relevant ES
  # - Remove document in the table index
  # - Add document to all parent table indices, routing by association id
  def self.delete_document(table, document)
    attrs = document.attributes
    id = document.id

    # Remove document from all parent indices
    table.parents.each do |parent|
      # Get the parents id to route to correct es shard
      routing = attrs[parent[:routing_attr]]
      self.es_delete(parent[:index], id, routing)
    end

    # Remove document from table index
    self.es_delete(table.name, id)
  end

  # Replicate a RethinkDB document in ES
  # - Creates document in table index
  # - Adds docuement to all parent table indices, routing by association id
  def self.save_document(table, document)
    return if document.nil? # FIXME: Currently, from_trusted_json is nillable, remove once fixed
    body = document.to_json
    id = document.id
    attrs = document.attributes

    # Save document to all parent indices
    table.parents.each do |parent|
      # Get the parents id to route to correct es shard
      routing = attrs[parent[:routing_attr]]
      self.es_save(parent[:index], id, body, routing)
    end

    # Save document to table index
    self.es_save(table.name, id, body)
  end

  # ES api calls

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
    res = HTTP::Client.delete(url)
    raise RubberSoul::Error.new("ES delete: #{res.body}") unless res.success?
  end

  # ES Utils

  # Constucts the ES path
  def self.document_path(table_name, id, routing = nil)
    # When routing not specified, route by document id
    routing = id unless routing
    "/#{table_name}/_doc/#{id}?routing=#{routing}"
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
            "/#{indices.join(',')}/_query"
          else
            "/_all/_query"
          end
    @@client.delete(url, body: query).success?
  end

  def self.client
    @@client
  end
end
