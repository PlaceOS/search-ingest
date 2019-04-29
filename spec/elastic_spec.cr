require "./helper"

describe RubberSoul::Elastic do
  it "routes to correct parent documents" do
    tm = RubberSoul::TableManager.new(MANAGED_TABLES, backfill: false, watch: false)
    es = RubberSoul::Elastic.client

    child_index = Coffee.table_name
    child_name = Coffee.name
    parent_index = Programmer.table_name

    parent = Programmer.new(name: "Knuth")
    parent.id = RethinkORM::IdGenerator.next(parent)

    child = Coffee.new
    child.programmer = parent
    child.id = RethinkORM::IdGenerator.next(child)

    # Save a child document in child and parent indices
    RubberSoul::Elastic.save_document(
      document: child,
      index: child_index,
      parents: tm.parents(child_name),
      children: tm.children(child_name)
    )

    child_index_url = RubberSoul::Elastic.document_path(index: child_index, id: child.id)
    parent_index_url = RubberSoul::Elastic.document_path(index: parent_index, id: child.id, routing: parent.id)

    parent_doc = JSON.parse(es.get(parent_index_url).body)
    child_doc = JSON.parse(es.get(child_index_url).body)

    # Ensure child is routed via parent in parent table
    parent_doc["_routing"].to_s.should eq child.programmer_id
    child_doc["_routing"].to_s.should eq child.id

    # Remove join field
    filtered_source = JSON.parse(parent_doc["_source"].as_h.reject("join").to_json)

    # Ensure document is the same across indices
    filtered_source.should eq child_doc["_source"]
  end

  describe "crud operation" do
    it "deletes a document" do
      index = Broke.table_name

      sleep 0.5 # Wait for es
      model = Broke.new(breaks: "Think")
      model.id = RethinkORM::IdGenerator.next(model)

      # Add a document to es
      RubberSoul::Elastic.save_document(
        document: model,
        index: index,
      )

      es_doc_exists?(index, model.id, routing: model.id).should be_true

      # Delete a document from es
      RubberSoul::Elastic.delete_document(
        document: model,
        index: index,
      )

      es_doc_exists?(index, model.id, routing: model.id).should be_false
    end

    it "deletes documents from associated indices" do
      index = Coffee.table_name
      model_name = Coffee.name

      tm = RubberSoul::TableManager.new(MANAGED_TABLES, backfill: false, watch: false)

      parents = tm.parents(model_name)
      children = tm.children(model_name)
      parent_index = parents[0][:index]

      parent_model = Programmer.new(name: "Isaacs")
      parent_model.id = RethinkORM::IdGenerator.next(parent_model)

      model = Coffee.new(temperature: 50)
      model.id = RethinkORM::IdGenerator.next(model)
      model.programmer = parent_model

      # Add a document to es
      RubberSoul::Elastic.save_document(
        document: model,
        index: index,
        parents: parents,
        children: children,
      )

      sleep 1 # Wait for es
      es_doc_exists?(index, model.id, routing: model.id).should be_true
      es_doc_exists?(parent_index, model.id, routing: parent_model.id).should be_true

      # Add a document to es
      RubberSoul::Elastic.delete_document(
        document: model,
        index: index,
        parents: parents,
        children: children,
      )

      sleep 1 # Wait for es
      es_doc_exists?(index, model.id, routing: model.id).should be_false
      es_doc_exists?(parent_index, model.id, routing: parent_model.id).should be_false
    end

    it "saves a document" do
      tm = RubberSoul::TableManager.new(MANAGED_TABLES, backfill: false, watch: false)
      es = RubberSoul::Elastic.client
      index = Programmer.table_name
      model_name = Programmer.name

      model = Programmer.new(name: "Knuth")
      model.id = RethinkORM::IdGenerator.next(model)

      parents = tm.parents(model_name)
      children = tm.children(model_name)
      RubberSoul::Elastic.save_document(
        document: model,
        index: index,
        parents: parents,
        children: children,
      )

      es_doc_exists?(index, model.id, routing: model.id).should be_true

      es_doc_url = RubberSoul::Elastic.document_path(index: index, id: model.id)
      doc = JSON.parse(es.get(es_doc_url).body)

      # Ensure child is routed via parent in parent table
      doc["_routing"].to_s.should eq model.id
      doc["_source"]["type"].should eq model_name

      # Pick off "type" and "join" fields, convert to any for easy comparison
      es_document = JSON.parse(doc["_source"].as_h.reject("type", "join").to_json)
      local_document = JSON.parse(model.attributes.to_json)

      # Ensure local document is replicated in elasticsearch
      es_document.should eq local_document
    end
  end
end
