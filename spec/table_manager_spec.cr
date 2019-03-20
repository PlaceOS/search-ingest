require "./helper"

describe RubberSoul::TableManager do
  it "generates a schema for a model" do
    tm = RubberSoul::TableManager.new([Programmer])
    schema = tm.index_schema("Programmer")
    schema.should be_a(String)

    # Check that the path to a field mapping exists
    json = JSON.parse(schema)
    json.dig?("mappings", "_doc", "properties", "name", "type").should_not be_nil
  end

  describe "elasticsearch properties" do
    it "creates a mapping of table attributes to es types" do
      tm = RubberSoul::TableManager.new([Programmer])
      mappings = tm.properties["Programmer"]
      mappings.should eq ([
        {:id, {type: "keyword"}},
        {:name, {type: "text"}},
        RubberSoul::TableManager::TYPE_PROPERTY,
      ])
    end

    it "allows specification of field type" do
      # RayGun ip attribute has an 'es_type' tag
      tm = RubberSoul::TableManager.new([RayGun])
      mappings = tm.properties["RayGun"].sort_by { |p| p[0] }
      mappings.should eq ([
        {:barrel_length, {type: "float"}},
        {:id, {type: "keyword"}},
        {:ip, {type: "ip"}},
        {:laser_colour, {type: "text"}},
        {:last_shot, {type: "date"}},
        {:rounds, {type: "integer"}},
        RubberSoul::TableManager::TYPE_PROPERTY,
      ])
    end

    it "collects properties for a model with associations" do
      tm = RubberSoul::TableManager.new(SPEC_MODELS)
      children = tm.children("Programmer")
      mappings = tm.collect_index_properties("Programmer", children).sort_by { |p| p[0] }
      mappings.should eq ([
        {:created_at, {type: "date"}},
        {:duration, {type: "date"}},
        {:id, {type: "keyword"}},
        {:name, {type: "text"}},
        {:programmer_id, {type: "keyword"}},
        {:temperature, {type: "integer"}},
        RubberSoul::TableManager::TYPE_PROPERTY,
      ])
    end
  end

  describe "relations" do
    it "finds parent relations of a model" do
      tm = RubberSoul::TableManager.new(SPEC_MODELS)
      parents = tm.parents("Migraine")
      parents.should eq [{name: "Programmer", index: "programmer", routing_attr: "programmer_id"}]
    end

    it "finds the child relations of a model" do
      tm = RubberSoul::TableManager.new(SPEC_MODELS)
      children = tm.children("Programmer")
      children.should eq ["Coffee", "Migraine"]
    end
  end

  pending "RethinkDB syncing" do
    it "creates ES documents from changefeed" do
      clear_test_indices
      p "here"
      RubberSoul::TableManager.new(SPEC_MODELS, backfill: false, watch: true)
      p "here now"

      es_document_count("programmer").should eq 0
      Programmer.create(name: "Rob Pike")
      sleep 0.5 # Wait for change to propagate to es
      es_document_count("programmer").should eq 1
    end
  end

  it "applies new mapping to an index" do
    delete_test_indices
    es = RubberSoul::Elastic.client

    get_schema = ->{ {mappings: JSON.parse(es.get("/programmer").body)["programmer"]["mappings"]}.to_json }
    wrong_schema = {
      mappings: {
        _doc: {
          properties: {
            wrong: {type: "keyword"},
          },
        },
      },
    }.to_json

    # Apply an incorrect schema and check currently applied schema
    es.put("/programmer", RubberSoul::Elastic.headers, body: wrong_schema)
    get_schema.call.should eq wrong_schema

    tm = RubberSoul::TableManager.new([Programmer])

    schema = JSON.parse(tm.index_schema("Programmer"))
    updated_schema = JSON.parse(get_schema.call)

    # Check if updated schema applied
    updated_schema.should_not eq JSON.parse(wrong_schema)
    updated_schema.should eq schema
  end

  it "reindexes indices" do
    clear_test_tables
    RubberSoul::Elastic.empty_indices(["programmer"])

    num_docs = 5

    # Place some data in rethinkdb
    num_docs.times do |n|
      Programmer.create(name: "Jim the #{n}th")
    end

    # Start e non-watching table_manager
    tm = RubberSoul::TableManager.new(SPEC_MODELS, backfill: true, watch: false)

    sleep 0.5
    # Check number of documents in elastic search
    es_document_count("programmer").should eq 5

    # Clear the rethinkdb tables
    clear_test_tables
    sleep 0.1

    # Reindex
    tm.reindex_all

    sleep 0.1
    # Check number of documents in elastic search
    es_document_count("programmer").should eq 0
  end

  describe "backfill" do
    it "refills a single es index with existing data in rethinkdb" do
      # Empty rethinkdb tables
      clear_test_tables

      # Generate some data in rethinkdb
      (1..5).each do |n|
        Programmer.create(name: "Tim the #{n}th")
      end

      tm = RubberSoul::TableManager.new(SPEC_MODELS)

      # Remove documents from es
      clear_test_indices

      # Backfill all documents in rethinkdb
      tm.backfill_all
      sleep 0.5 # Wait for es
      es_document_count("programmer").should eq 5
    end
  end
end
