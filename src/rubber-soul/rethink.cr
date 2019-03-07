require "../config"

class RubberSoul::Rethink
  include RethinkDB::Shortcuts

  Habitat.create do
    setting host : String = ENV["RETHINK_HOST"]? || "127.0.0.1"
    setting port : Int32 = ENV["RETHINK_PORT"]?.try(&.to_i) || 28015
  end

  def self.raw
    query = yield r
    query.run(conn)
  end

  def self.connected?
    !conn.nil?
  end

  def self.has_db?(db : String)
    self.raw { |q| q.db_list.contains(db) }
  end

  def self.db_tables(db : String)
    raise Error.new("db '#{db}' is not present") unless self.has_db?
    self.raw { |q| q.db(db).table_list }
  end

  def self.ensure_tables!(tables : Array(Table))
    # Batch tables by db to reduce RethinkDB queries
    batched_tables = tables.reduce({} of String => Array(String)) do |batch, table|
      if batch[table.db]
        batch[table.db] << table.name
      else
        batch[table.db] = [table.name]
      end
      batch
    end

    # Determine any missing tables
    missing_tables = [] of Table
    batched_tables.map do |db, table_batch|
      table_list = self.db_tables(db)

      table_batch.each do |table|
        missing_tables << {name: table, db: db} unless table_list.contains(table)
      end
    end

    unless missing_tables.empty?
      missing_table_names = missing_tables.map { |t| "#{t.db}/#{t.name}" }.join(", ")
      raise Error.new("Missing #{missing_table_names} in RethinkDB")
    end
  end

  private def conn
    @@conn ||= r.connect(host: setting.host, port: setting.port)
  end
end
