require "spec"

# Spec models
require "./spec_models"

# Application config
require "../src/config"
require "../src/rubber-soul"
require "../src/rubber-soul/*"

# Helper methods for testing controllers (curl, with_server, context)
require "../lib/action-controller/spec/curl_context"

require "json"

# Delete all test indices on start up
def delete_test_indices
  RubberSoul::Elastic.delete_indices(SPEC_MODELS.map(&.table_name))
end

# Remove all documents from an index, retaining index mappings
def clear_test_indices
  RubberSoul::Elastic.empty_indices(SPEC_MODELS.map(&.table_name))
end

def clear_test_tables
  SPEC_MODELS.each { |klass| klass.clear }
end

# Helper to get document count for an es index
def es_document_count(index)
  JSON.parse(RubberSoul::Elastic.client.get("/#{index}/_count").body)["count"]
end

# Remove any of the test indices on start up
# delete_test_indices
