require "./helper"

describe RubberSoul::TableManager do
  pending "watch" do
    it "creates ES documents from changefeed" do
      tm = RubberSoul::TableManager.new(backfill: false, watch: true)
      index = Programmer.table_name

      count_before_create = es_document_count(index)
      Programmer.create(name: "Rob Pike")

      sleep 1 # Wait for change to propagate to es
      es_document_count(index).should eq (count_before_create + 1)

      expect_raises(RubberSoul::Error, message: "TableManager cancelled") do
        tm.cancel!
      end
    end
  end

  it "applies new mapping to an index" do
    delete_test_indices
    es = RubberSoul::Elastic.client
    index = Broke.table_name
    get_schema = ->{ {mappings: JSON.parse(es.get("/#{index}").body)[index]["mappings"]}.to_json }
    wrong_schema = {
      mappings: {
        properties: {
          wrong: {type: "keyword"},
        },
      },
    }.to_json

    # Apply an incorrect schema and check currently applied schema
    es.put("/#{index}", RubberSoul::Elastic.headers, body: wrong_schema)
    get_schema.call.should eq wrong_schema

    tm = RubberSoul::TableManager.new([Broke])

    schema = JSON.parse(tm.index_schema(Broke.name))
    updated_schema = JSON.parse(get_schema.call)

    # Check if updated schema applied
    updated_schema.should_not eq JSON.parse(wrong_schema)
    updated_schema.should eq schema
  end

  it "generates a schema for a model" do
    tm = RubberSoul::TableManager.new([Broke])
    schema = tm.index_schema(Broke.name)
    schema.should be_a(String)

    # Check that the path to a field mapping exists
    json = JSON.parse(schema)
    json.dig?("mappings", "properties", "breaks", "type").should_not be_nil
  end

  describe "elasticsearch properties" do
    it "creates a mapping of table attributes to es types" do
      tm = RubberSoul::TableManager.new([Broke])
      mappings = tm.properties[Broke.name]
      mappings.should eq ([
        {:id, {type: "keyword"}},
        {:breaks, {type: "text"}},
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
      tm = RubberSoul::TableManager.new
      name = Programmer.name
      children = tm.children(name)
      mappings = tm.collect_index_properties(name, children)
      mappings.should eq ({
        :created_at    => {type: "date"},
        :duration      => {type: "date"},
        :id            => {type: "keyword"},
        :name          => {type: "text"},
        :programmer_id => {type: "keyword"},
        :temperature   => {type: "integer"},
        :type          => {type: "keyword"},
      })
    end
  end

  describe "relations" do
    it "finds parent relations of a model" do
      tm = RubberSoul::TableManager.new
      parents = tm.parents(Migraine.name)
      parents.should eq [{
        name:         Programmer.name,
        index:        Programmer.table_name,
        routing_attr: :programmer_id,
      }]
    end

    it "finds the child relations of a model" do
      tm = RubberSoul::TableManager.new
      children = tm.children(Programmer.name)
      children.should eq [Coffee.name, Migraine.name]
    end
  end

  it "reindexes indices" do
    # Start non-watching table_manager
    tm = RubberSoul::TableManager.new

    index = Programmer.table_name
    count_before_create = es_document_count(index)

    # Place some data in rethinkdb
    num_created = 5
    num_created.times do |n|
      Programmer.create(name: "Jim the #{n}th")
    end

    # Reindex
    tm.reindex_all
    sleep 1
    es_document_count(index).should eq 0

    tm.backfill_all
    sleep 1
    # Check number of documents in elastic search
    es_document_count(index).should eq (num_created + count_before_create)
  end

  describe "backfill" do
    it "refills a single es index with existing data in rethinkdb" do
      tm = RubberSoul::TableManager.new(watch: false, backfill: false)

      index = Programmer.table_name

      Programmer.clear

      # Generate some data in rethinkdb
      5.times do |n|
        Programmer.create(name: "Tim the #{n}th")
      end

      # Remove documents from es
      RubberSoul::Elastic.empty_indices([index])

      # Backfill a single index
      tm.backfill(Programmer.name)

      sleep 1 # Wait for es
      es_document_count(index).should eq Programmer.count
    end
  end
end
