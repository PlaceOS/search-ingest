require "./helper"

module SearchIngest
  @@schemas = Schemas.new
  class_getter schemas

  describe Elastic do
    before_each do
      Elastic.empty_indices
    end

    describe "skip_replication?" do
      it "does not skip a document on the same index without a parent" do
        Elastic.skip_replication?({parent_id: nil, index: "same"}, "same", [{name: "mum", index: "same", routing_attr: :parent_id}]).should be_false
      end

      it "skips a documents on the same index with a parent" do
        Elastic.skip_replication?({parent_id: "123", index: "same"}, "same", [{name: "mum", index: "same", routing_attr: :parent_id}]).should be_true
      end
    end

    describe ".equivalent_schema?" do
      it "does not fail on malformed schemas" do
        broken_schema = {error: "malformed"}.to_json
        Elastic.equivalent_schema?(broken_schema, broken_schema).should be_false
      end
    end

    describe "single" do
      test_crud(bulk: false)

      describe "assocations" do
        it "does not requests on self-associated index" do
          Elastic.bulk = false

          index = SelfReferential.table_name

          parent = SelfReferential.new(name: "GNU")
          parent.id = RethinkORM::IdGenerator.next(parent)

          child = SelfReferential.new(name: "GNU's Not Unix")
          child.parent = parent
          child.id = RethinkORM::IdGenerator.next(child)

          # Save a child document in child and parent indices
          Elastic.single_action(
            action: Elastic::Action::Create,
            document: child,
            index: index,
            parents: schemas.parents(child.class),
            no_children: schemas.children(child.class).empty?,
          )

          until_expected(true) do
            es_doc_exists?(index, child.id)
          end.should be_true

          parent_index_path = Elastic.document_path(index: index, id: child.id)
          parent_index_doc = JSON.parse(Elastic.client &.get(parent_index_path).body)

          # Ensure child is routed via parent in parent table
          parent_index_doc["_routing"].to_s.should eq child.parent_id
          parent_index_doc["_source"]["_document_type"].should eq Schemas.document_name(child.class)

          # Pick off "_document_type" and "join" fields, convert to any for easy comparison
          es_document = JSON.parse(parent_index_doc["_source"].as_h.reject("_document_type", "join").to_json)
          local_document = JSON.parse(child.to_json)

          # Ensure document is the same across indices
          es_document.should eq local_document
          es_document_count(index).should eq 1
        end

        it "routes to correct parent documents" do
          Elastic.bulk = false

          child_index = Beverage::Coffee.table_name
          parent_index = Programmer.table_name

          parent = Programmer.new(name: "Knuth")
          parent.id = RethinkORM::IdGenerator.next(parent)

          child = Beverage::Coffee.new
          child.programmer = parent
          child.id = RethinkORM::IdGenerator.next(child)

          # Save a child document in child and parent indices
          Elastic.single_action(
            action: Elastic::Action::Create,
            document: child,
            index: child_index,
            parents: schemas.parents(child.class),
            no_children: schemas.children(child.class).empty?,
          )

          until_expected(true) do
            es_doc_exists?(parent_index, child.id)
          end

          parent_index_path = Elastic.document_path(index: parent_index, id: child.id)
          parent_index_doc = JSON.parse(Elastic.client &.get(parent_index_path).body)

          # Ensure child is routed via parent in parent table
          parent_index_doc["_routing"].to_s.should eq child.programmer_id
          parent_index_doc["_source"]["_document_type"].should eq Schemas.document_name(child.class)

          # Pick off "_document_type" and "join" fields, convert to any for easy comparison
          es_document = JSON.parse(parent_index_doc["_source"].as_h.reject("_document_type", "join").to_json)
          local_document = JSON.parse(child.to_json)

          # Ensure document is the same across indices
          es_document.should eq local_document
        end
      end
    end

    describe "bulk" do
      test_crud(bulk: true)

      describe "associations" do
        it "does not requests on self-associated index" do
          Elastic.bulk = true

          index = SelfReferential.table_name

          parent = SelfReferential.new(name: "GNU")
          parent.id = RethinkORM::IdGenerator.next(parent)

          child = SelfReferential.new(name: "GNU's Not Unix")
          child.parent = parent
          child.id = RethinkORM::IdGenerator.next(child)

          # Save a child document in child and parent indices
          bulk_request = Elastic.bulk_action(
            action: Elastic::Action::Create,
            document: child,
            index: index,
            parents: schemas.parents(parent.class),
            no_children: schemas.children(parent.class).empty?,
          )

          Elastic.bulk_operation(bulk_request)

          header, source = bulk_request.split('\n')
          header = JSON.parse(header)["create"]

          index_routing = JSON.parse(source)["join"]

          name_field = index_routing.not_nil!["name"]
          parent_field = index_routing.not_nil!["parent"]

          # Ensure correct join field

          name_field.should eq Schemas.document_name(child.class)
          parent_field.should eq parent.id

          # Ensure child is routed via parent in parent table
          header["routing"].to_s.should eq child.parent_id

          index_path = Elastic.document_path(index: index, id: child.id)
          index_doc = JSON.parse(Elastic.client &.get(index_path).body)

          # Ensure child is routed via parent in parent table
          index_doc["_routing"].to_s.should eq child.parent_id
          index_doc["_source"]["_document_type"].should eq Schemas.document_name(parent.class)

          # Pick off "_document_type" and "join" fields, convert to any for easy comparison
          es_document = JSON.parse(index_doc["_source"].as_h.reject("_document_type", "join").to_json)
          local_document = JSON.parse(child.to_json)

          # Ensure document is the same across indices
          es_document.should eq local_document
        end

        it "routes to correct parent documents" do
          Elastic.bulk = true

          child_index = Beverage::Coffee.table_name
          parent_index = Programmer.table_name

          parent = Programmer.new(name: "Knuth")
          parent.id = RethinkORM::IdGenerator.next(parent)

          child = Beverage::Coffee.new
          child.programmer = parent
          child.id = RethinkORM::IdGenerator.next(child)

          # Save a child document in child and parent indices
          bulk_request = Elastic.bulk_action(
            action: Elastic::Action::Create,
            document: child,
            index: child_index,
            parents: schemas.parents(child.class),
            no_children: schemas.children(child.class).empty?,
          )

          Elastic.bulk_operation(bulk_request)

          headers, sources = bulk_request.split('\n').in_groups_of(2).transpose
          child_header, parent_header = headers.compact.map { |h| JSON.parse(h)["create"] }

          child_index_routing, parent_index_routing = sources.compact.map { |h| JSON.parse(h)["join"]? }

          child_index_routing.should be_nil

          name_field = parent_index_routing.not_nil!["name"]
          parent_field = parent_index_routing.not_nil!["parent"]

          # Ensure correct join field

          name_field.should eq Schemas.document_name(child.class)
          parent_field.should eq parent.id

          # Ensure child is routed via parent in parent table
          parent_header["routing"].to_s.should eq child.programmer_id
          child_header["routing"].to_s.should eq child.id

          parent_index_path = Elastic.document_path(index: parent_index, id: child.id)
          parent_index_doc = JSON.parse(Elastic.client &.get(parent_index_path).body)

          # Ensure child is routed via parent in parent table
          parent_index_doc["_routing"].to_s.should eq child.programmer_id
          parent_index_doc["_source"]["_document_type"].should eq Schemas.document_name(child.class)

          # Pick off "_document_type" and "join" fields, convert to any for easy comparison
          es_document = JSON.parse(parent_index_doc["_source"].as_h.reject("_document_type", "join").to_json)
          local_document = JSON.parse(child.to_json)

          # Ensure document is the same across indices
          es_document.should eq local_document
        end
      end
    end
  end

  def self.test_crud(bulk : Bool)
    describe "CRUD" do
      it "deletes a document" do
        Elastic.bulk = bulk
        index = Broke.table_name

        model = Broke.new(breaks: "Think")
        model.id = RethinkORM::IdGenerator.next(model)

        # Add a document to es
        Elastic.create_document(
          document: model,
          index: index,
        )

        until_expected(true) do
          es_doc_exists?(index, model.id, routing: model.id)
        end

        # Delete a document from es
        Elastic.delete_document(
          document: model,
          index: index,
        )

        es_doc_exists?(index, model.id, routing: model.id).should be_false
      end

      it "deletes documents from associated indices" do
        Elastic.bulk = bulk
        index = Beverage::Coffee.table_name

        parents = schemas.parents(Beverage::Coffee)
        parent_index = parents[0][:index]

        parent_model = Programmer.new(name: "Isaacs")
        parent_model.id = RethinkORM::IdGenerator.next(parent_model)

        model = Beverage::Coffee.new(temperature: 50)
        model.id = RethinkORM::IdGenerator.next(model)
        model.programmer = parent_model

        # Add document to es
        Elastic.create_document(
          document: model,
          index: index,
          parents: parents,
          no_children: schemas.children(model.class).empty?,
        )

        until_expected(true) do
          es_doc_exists?(index, model.id, routing: model.id) && es_doc_exists?(parent_index, model.id, routing: parent_model.id)
        end

        # Remove document from es
        Elastic.delete_document(
          document: model,
          index: index,
          parents: parents,
        )

        until_expected(false) do
          es_doc_exists?(index, model.id, routing: model.id) || es_doc_exists?(parent_index, model.id, routing: parent_model.id)
        end
      end

      describe ".create_document" do
        it "saves a document" do
          Elastic.bulk = bulk
          index = Programmer.table_name

          model = Programmer.new(name: "tenderlove")
          model.id = RethinkORM::IdGenerator.next(model)

          parents = schemas.parents(model.class)
          no_children = schemas.children(model.class).empty?

          Elastic.create_document(
            document: model,
            index: index,
            parents: parents,
            no_children: no_children,
          )

          until_expected(true) do
            es_doc_exists?(index, model.id, routing: model.id)
          end

          es_doc_url = Elastic.document_path(index: index, id: model.id)
          doc = JSON.parse(Elastic.client &.get(es_doc_url).body)

          # Ensure child is routed via parent in parent table
          doc["_routing"].to_s.should eq model.id
          doc["_source"]["_document_type"].should eq Schemas.document_name(model.class)
          # Pick off "_document_type" and "join" fields, convert to any for easy comparison
          es_document = JSON.parse(doc["_source"].as_h.reject("_document_type", "join").to_json)
          local_document = JSON.parse(model.attributes.to_json)

          # Ensure local document is replicated in elasticsearch
          es_document.should eq local_document
        end
      end
    end
  end
end
