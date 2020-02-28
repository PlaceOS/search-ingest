require "spec"

# Application config
require "./spec_config"

require "../src/rubber-soul/*"
require "../src/api"

# Helper methods for testing controllers (curl, with_server, context)
require "../lib/action-controller/spec/curl_context"

require "json"

macro table_names
  [{% for klass in RubberSoul::MANAGED_TABLES %} {{ klass }}.table_name, {% end %}]
end

# Delete all test indices on start up
def delete_test_indices
  table_names.each do |name|
    RubberSoul::Elastic.delete_index(name)
  end
end

Spec.before_suite &->cleanup
Spec.after_suite &->cleanup

def cleanup
  # Empty rethinkdb test tables
  clear_test_tables
  # Remove any of the test indices
  delete_test_indices
end

def drop_tables
  RethinkORM::Connection.raw do |q|
    q.db("test").table_list.for_each do |t|
      q.db("test").table(t).delete
    end
  end
end

# Remove all documents from an index, retaining index mappings
def clear_test_indices
  table_names.each do |name|
    RubberSoul::Elastic.empty_indices([name])
  end
end

macro clear_test_tables
  {% for klass in RubberSoul::MANAGED_TABLES %}
  {{ klass.id }}.clear
  {% end %}
end

# Helper to get document count for an es index
def es_document_count(index)
  response_body = JSON.parse(RubberSoul::Elastic.client &.get("/#{index}/_count").body)
  response_body["count"].as_i
end

def es_doc_exists?(index, id, routing)
  RubberSoul::Elastic.client &.get("/#{index}/_doc/#{id}").success?
end
