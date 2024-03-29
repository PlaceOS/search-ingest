require "json"
require "placeos-log-backend"
require "promise"
require "retriable"

# Application config
require "./spec_config"

require "../src/search-ingest"
require "../src/api"

# Helper methods for testing controllers
require "action-controller/spec_helper"

require "spec"

macro table_names
  [{% for klass in SearchIngest::MANAGED_TABLES %} {{ klass }}.table_name, {% end %}]
end

alias SpecConnection = PgORM::Database

Spec.before_suite do
  PgORM::Database.parse(ENV["PG_DATABASE_URL"])
  ::Log.setup "*", :info, PlaceOS::LogBackend.log_backend
  SearchIngest.wait_for_elasticsearch
  cleanup
  setup
end

Spec.after_suite &->cleanup

def setup
  SpecConnection.connection do |db|
    db.exec <<-SQL
    CREATE TABLE ray_gun (
      id TEXT NOT NULL PRIMARY KEY,
      laser_colour TEXT NOT NULL,
      barrel_length FLOAT NOT NULL,
      rounds INT NOT NULL,
      ip TEXT NOT NULL,
      last_shot TIMESTAMP NOT NULL
    );
    SQL

    db.exec <<-SQL
    CREATE TABLE programmer (
      id TEXT NOT NULL PRIMARY KEY,
      name TEXT NOT NULL
    );
    SQL

    db.exec <<-SQL
    CREATE TABLE broke (
      id TEXT NOT NULL PRIMARY KEY,
      breaks TEXT NOT NULL,
      status BOOL NOT NULL,
      hasho JSONB NOT NULL
    );
    SQL

    db.exec <<-SQL
    CREATE TABLE beverage_coffee (
      id TEXT NOT NULL PRIMARY KEY,
      temperature INT NOT NULL,
      created_at TIMESTAMP NOT NULL
    );
    SQL

    db.exec <<-SQL
    CREATE TABLE ouch (
      id TEXT NOT NULL PRIMARY KEY,
      created_at TIMESTAMP NOT NULL
    );
    SQL

    db.exec <<-SQL
    CREATE TABLE selfref (
      id TEXT NOT NULL PRIMARY KEY,
      name TEXT NOT NULL
    );
    SQL
  end
end

def refresh
  SearchIngest::Elastic.client &.post("/_refresh")
end

def until_expected(expected, &)
  refresh
  before = Time.utc
  result = nil
  begin
    Retriable.retry(
      base_interval: 100.milliseconds,
      max_interval: 500.milliseconds,
      max_elapsed_time: 10.seconds,
      retry_on: Exception
    ) do
      (result = yield).tap do
        if result != expected
          Log.error { "retry: expected #{expected}, got #{result}" }
          raise Exception.new("retry")
        end
      end
    end
  rescue e
    raise e unless e.message == "retry"
  ensure
    after = Time.utc
    Log.info { "took #{(after - before).total_milliseconds}ms" }
  end

  result
end

def cleanup
  # Empty postgresql test tables
  drop_tables
  # Remove any of the test indices
  clear_test_indices
  delete_test_indices
  refresh
end

def drop_tables
  SpecConnection.connection do |db|
    table_names.each do |table|
      db.exec "DROP TABLE IF EXISTS #{table}"
    end
  end
end

# Remove all documents from an index, retaining index mappings
def clear_test_indices
  Promise.map(table_names) do |name|
    SearchIngest::Elastic.empty_indices([name])
  end.get
  Fiber.yield
end

# Delete all test indices on start up
def delete_test_indices
  Promise.map(table_names) do |name|
    SearchIngest::Elastic.delete_index(name)
  end.get
  Fiber.yield
end

macro clear_test_tables
  {% for klass in SearchIngest::MANAGED_TABLES %}
  {{ klass.id }}.clear
  {% end %}
end

# Helper to get document count for an es index
def es_document_count(index)
  response_body = JSON.parse(SearchIngest::Elastic.client &.get("/#{index}/_count").body)
  response_body["count"].as_i
end

def es_doc_exists?(index, id, routing = nil)
  params = HTTP::Params.new
  params["routing"] = routing unless routing.nil?
  SearchIngest::Elastic.client &.get("/#{index}/_doc/#{id}?#{params}").success?
end

def tables
  SearchIngest.tables(SearchIngest::MANAGED_TABLES).last
end

def schemas
  SearchIngest.tables(SearchIngest::MANAGED_TABLES).first
end
