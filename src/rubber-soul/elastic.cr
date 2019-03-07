require "../config"

class RubberSoul::Elastic
  Habitat.create do
    setting host : String = ENV["ES_HOST"]? || "127.0.0.1"
    setting port : Int32 = ENV["ES_PORT"]?.try(&.to_i) || 9200
    setting scheme : String = "http"
  end

  BASE = URI.new(host: self.settings.host, port: self.settings.port, scheme: self.settings.scheme).to_s

  # Replicate a RethinkDB document in ES
  def self.save_document(
    db,
    table,
    id = nil,
    es_type = nil,
    document = nil,
    old_document = nil
  )
    if document.nil?
      push_document(db, doc, id: id, table: es_type || table, delete: true)
    else
    end
    # Document null if deleted in rethink
    save_document = if document.nil?
                      old_document[:delete] = true
                      old_document
                    else
                      document
                    end

    # Finally, push document/s to ES
    if save_document.is_a? Array
      save_document.map do |doc|
        push_document(db: db, document: doc, id: id, table: es_type || table)
      end
    else
      push_document(db: db, document: save_document, id: id, table: es_type || table)
    end
  end

  def self.push_document(db, document, id, table, delete = false)
    return if doc.nil? || doc.keys.size == 0

    path = elasticsearch_path(db, id, table)
    url = {BASE, path}.join('/')

    if delete
      HTTP::Client.delete(url, doc)
    elsif id
      HTTP::Client.put(url, doc)
    else
      HTTP::Client.post(url, doc)
    end
  end

  # Constucts the ES path from rethink object properties
  def self.elasticsearch_path(db = "", id = "", table = "")
    return "/" if db.empty? && table.empty?

    if table.empty?
      "/#{db}"
    else
      "/#{db}_#{table}/#{table}/#{id}"
    end
  end

  # Checks availablity of RethinkDB and Elasticsearch
  def self.ensure_elastic!
    response = HTTP::Client.get(BASE)
    raise Error.new("Failed to connect to ES") unless response.success?
  end
end
