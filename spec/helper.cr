require "spec"

# Spec models
require "./spec_models"

# Application config
require "../src/config"
require "../src/rubber-soul"
require "../src/rubber-soul/*"
require "../src/api"

# Helper methods for testing controllers (curl, with_server, context)
require "../lib/action-controller/spec/curl_context"

require "json"

macro table_names
  [{% for klass in SPEC_MODELS %} {{ klass }}.table_name, {% end %}]
end

# Delete all test indices on start up
def delete_test_indices
  RubberSoul::Elastic.delete_indices(table_names)
end

# Remove all documents from an index, retaining index mappings
def clear_test_indices
  RubberSoul::Elastic.empty_indices(table_names)
end

macro clear_test_tables
  {% for klass in SPEC_MODELS %}
  {{ klass.id }}.clear
  {% end %}
end

# Helper to get document count for an es index
def es_document_count(index)
  JSON.parse(RubberSoul::Elastic.client.get("/#{index}/_count").body)["count"]
end

# Remove any of the test indices on start up
delete_test_indices

# Remove any of the test tables in rethinkdb on start up
clear_test_tables
