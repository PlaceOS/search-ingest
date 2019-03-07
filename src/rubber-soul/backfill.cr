require "../config"
require "./rethink"

module RubberSoul::Rethinker
  # Fill contents of ES index with contents of RethinkDB table containing
  # rethinkdb-orm models
  def backfill_table(db, table, es_type = nil, **opts)
    # Get a stream of documents from a table
    table_cursor = Rethink.raw { |r| r.db(db).table(table) }

    # Pump all RethinkDB documents from a table to ES
    table_cursor.each do |doc|
      begin
        save_document(db, doc, es_type || table, **opts)
      rescue e
        LOG.error("ES Error: #{e}")
      end
    end
  end
end
