require "../config"

class RubberSoul::Elastic
  # Settings for elastic client
  Habitat.create do
    setting host : String = ENV["ES_HOST"]? || "127.0.0.1"
    setting port : Int32 = ENV["ES_PORT"]?.try(&.to_i) || 9200
    setting scheme : String = "http"
  end

  BASE = URI.new(host: self.settings.host, port: self.settings.port, scheme: self.settings.scheme).to_s

  # Indices
  def self.check_index?(index)
    HTTP::Client.head("#{BASE}/#{index}").success?
  end

  def self.delete_index(index)
    HTTP::Client.delete("#{BASE}/#{index}").success?
  end

  def self.get_mapping(index)
    response = HTTP::Client.get("#{BASE}/#{index}")
    if response.success?
      JSON.parse(response.body)[index]?.try(&.to_json)
    else
      nil
    end
  end

  def self.apply_index_mapping(index, mapping)
    response = HTTP::Client.put("#{BASE}/#{index}", body: mapping)
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
  def self.es_save(index, id, body, routing = nil)
    url = self.elasticsearch_path(index, id, routing)
    res = HTTP::Client.put(url, body: body)
    raise RubberSoul::Error.new("ES save: #{res.body}") unless res.success?
  end

  # Delete document from an elastic search index
  def self.es_delete(index, id, routing = nil)
    url = self.elasticsearch_path(index, id, routing)
    res = HTTP::Client.delete(url)
    raise RubberSoul::Error.new("ES delete: #{res.body}") unless res.success?
  end

  # ES Utils

  # Constucts the ES path
  def self.elasticsearch_path(table_name, id, routing = nil)
    # When routing not specified, route by document id
    routing = id unless routing
    "#{BASE}/#{table_name}/_doc/#{id}?routing=#{routing}"
  end

  # Checks availablity of RethinkDB and Elasticsearch
  def self.ensure_elastic!
    response = HTTP::Client.get(BASE)
    raise Error.new("Failed to connect to ES") unless response.success?
  end
end
