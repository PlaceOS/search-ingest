require "./helper"

describe RubberSoul::Elastic do
  it "routes to correct parent documents" do
    tm = RubberSoul::TableManager.new(SPEC_MODELS, backfill: false, watch: false)
    es = RubberSoul::Elastic.client

    # Ensure no docs in es
    RubberSoul::Elastic.empty_indices([Programmer.table_name, Coffee.table_name])
    sleep 0.5 # Wait for es
    es_document_count("coffee").should eq 0
    es_document_count("programmer").should eq 0

    programmer = Programmer.new(name: "Knuth")
    programmer.id = "programmer-SoM3Th3ing"

    coffee = Coffee.new
    coffee.programmer = programmer
    coffee.id = "coffee-SoM3Th3ing"

    # Save a child document in child and parent indices
    RubberSoul::Elastic.save_document(
      document: coffee,
      index: "coffee",
      parents: tm.parents("Coffee"),
      children: tm.children("Coffee")
    )

    sleep 1 # Check that documents have been placed into ES
    es_document_count("coffee").should eq 1
    es_document_count("programmer").should eq 1

    child_index_url = RubberSoul::Elastic.document_path(index: "coffee", id: coffee.id)
    parent_index_url = RubberSoul::Elastic.document_path(index: "programmer", id: coffee.id, routing: programmer.id)

    parent_doc = JSON.parse(es.get(parent_index_url).body)
    child_doc = JSON.parse(es.get(child_index_url).body)

    # Ensure child is routed via parent in parent table
    parent_doc["_routing"].to_s.should eq coffee.programmer_id
    child_doc["_routing"].to_s.should eq coffee.id

    # Ensure document is the same across indices
    parent_doc["_source"].should eq child_doc["_source"]
  end

  describe "crud operation" do
    pending "deletes a document" do
    end

    it "saves a document" do
      tm = RubberSoul::TableManager.new(SPEC_MODELS, backfill: false, watch: false)
      es = RubberSoul::Elastic.client
      index = Programmer.table_name

      clear_test_indices
      sleep 0.5 # Wait for es
      es_document_count(index).should eq 0

      programmer = Programmer.new(name: "Knuth", id: "programmer-12345hjkl")
      parents = tm.parents("Programmer")
      children = tm.children("Programmer")
      RubberSoul::Elastic.save_document(
        document: programmer,
        index: index,
        parents: parents,
        children: children,
      )

      sleep 1 # Wait for es
      es_document_count(index).should eq 1

      es_doc_url = RubberSoul::Elastic.document_path(index: index, id: programmer.id)
      doc = JSON.parse(es.get(es_doc_url).body)

      # Ensure child is routed via parent in parent table
      doc["_routing"].to_s.should eq programmer.id
      doc["_source"]["type"].should eq "Programmer"

      # Pick off "type" field, convert to any for easy comparison
      es_document = JSON.parse(doc["_source"].as_h.reject("type").to_json)
      local_document = JSON.parse(programmer.attributes.to_json)

      # Ensure local document is replicated in elasticsearch
      es_document.should eq local_document
    end
  end
end
