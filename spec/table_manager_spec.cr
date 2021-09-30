require "./helper"

module RubberSoul
  describe TableManager do
    self.table_manager_test_suite(bulk: false)
    self.table_manager_test_suite(bulk: true)

    describe "mappings" do
      it "applies new mapping to an index" do
        delete_test_indices
        index = Broke.table_name
        get_schema = ->{
          response = JSON.parse(Elastic.client &.get("/#{index}").body)
          # Pluck the fields of interest
          mappings_field = response.dig(index, "mappings")
          settings_field = response.dig(index, "settings")
          {settings: settings_field, mappings: mappings_field}.to_json
        }

        wrong_schema = {
          settings: {} of Nil => Nil,
          mappings: {
            properties: {
              wrong: {type: "keyword"},
            },
          },
        }.to_json

        # Apply an incorrect schema and check currently applied schema
        Elastic.client &.put("/#{index}", Elastic.headers, body: wrong_schema)
        get_schema.call["mappings"].should eq wrong_schema["mappings"]

        tm = TableManager.new([Broke])

        document_name = TableManager.document_name(Broke)

        schema = JSON.parse(tm.index_schema(document_name))
        updated_schema = JSON.parse(get_schema.call)

        # Check if updated schema applied
        updated_schema.should_not eq JSON.parse(wrong_schema)

        updated_schema["mappings"].should eq schema["mappings"]
        updated_schema.dig("settings", "index", "analysis").as_h.rehash.should eq schema.dig("settings", "analysis").as_h.rehash
      end

      it "generates a schema for a model" do
        tm = TableManager.new([Broke])
        schema = tm.index_schema(Broke)
        schema.should be_a(String)

        # Check that the path to a field mapping exists
        json = JSON.parse(schema)
        json.dig?("mappings", "properties", "_document_type").should_not be_nil
      end

      describe "elasticsearch properties" do
        it "creates a mapping of table attributes to es types" do
          tm = TableManager.new([Broke])
          mappings = tm.properties(Broke).sort_by &.name
          mappings.should eq ([
            TableManager::TYPE_FIELD,
            TableManager::Field.new("breaks", "text", ["keyword"]),
            TableManager::Field.new("hasho", "object"),
            TableManager::Field.new("id", "keyword"),
            TableManager::Field.new("status", "boolean"),
          ])
        end

        it "allows specification of field type" do
          # RayGun ip attribute has an 'es_type' tag
          tm = TableManager.new([RayGun])
          mappings = tm.properties["RayGun"].sort_by &.name
          mappings.should eq ([
            TableManager::TYPE_FIELD,
            TableManager::Field.new("barrel_length", "float"),
            TableManager::Field.new("id", "keyword"),
            TableManager::Field.new("ip", "ip"),
            TableManager::Field.new("laser_colour", "text"),
            TableManager::Field.new("last_shot", "date"),
            TableManager::Field.new("rounds", "integer"),
          ])
        end

        it "collects properties for a model with associations" do
          tm = TableManager.new
          children = tm.children(Programmer)
          mappings = tm.collect_index_properties(Programmer, children).sort_by &.name
          mappings.should eq [
            TableManager::TYPE_FIELD,
            TableManager::Field.new("created_at", "date"),
            TableManager::Field.new("duration", "date"),
            TableManager::Field.new("id", "keyword"),
            TableManager::Field.new("name", "text"),
            TableManager::Field.new("programmer_id", "keyword"),
            TableManager::Field.new("temperature", "integer"),
          ]
        end
      end

      describe "relations" do
        it "finds parent relations of a model" do
          tm = TableManager.new
          parents = tm.parents(Migraine)
          parents.should eq [{
            name:         TableManager.document_name(Programmer),
            index:        Programmer.table_name,
            routing_attr: :programmer_id,
          }]
        end

        it "finds the child relations of a model" do
          tm = TableManager.new
          children = tm.children(Programmer)
          children.should eq [
            TableManager.document_name(Beverage::Coffee),
            TableManager.document_name(Migraine),
          ]
        end
      end
    end
  end

  def self.table_manager_test_suite(bulk : Bool)
    describe "#{bulk ? "bulk" : "single"}" do
      describe "watch" do
        it "creates ES documents from changefeed" do
          Elastic.bulk = bulk
          Programmer.clear
          refresh

          tm = TableManager.new(backfill: true, watch: true)
          index = Programmer.table_name

          refresh

          prog = Programmer.create!(name: "Rob Pike")

          until_expected(true) do
            Programmer.exists?(prog.id.as(String))
          end

          refresh

          until_expected(1) do
            es_document_count(index)
          end.should eq 1

          tm.close
        end
      end

      it "reindexes indices" do
        Elastic.bulk = bulk
        # Start non-watching table_manager
        tm = TableManager.new(backfill: true, watch: false)

        index = Programmer.table_name
        count_before_create = Programmer.count

        # Place some data in rethinkdb
        num_created = 3
        programmers = Array.new(size: num_created) do |n|
          Programmer.create!(name: "Jim the #{n}th")
        end

        # Reindex
        tm.reindex_all
        refresh

        until_expected(0) do
          es_document_count(index)
        end.should eq 0

        tm.backfill_all

        expected = num_created + count_before_create
        # Check number of documents in elastic search
        until_expected(expected) do
          es_document_count(index)
        end.should eq expected

        programmers.each &.destroy
      end

      describe "backfill" do
        it "refills a single es index with existing data in rethinkdb" do
          Elastic.bulk = bulk
          Programmer.clear
          index = Programmer.table_name

          tm = TableManager.new(watch: false, backfill: false)

          # Generate some data in rethinkdb
          num_created = 5
          programmers = Array.new(size: num_created) do |n|
            Programmer.create!(name: "Jim the #{n}th")
          end

          # Remove documents from es
          Elastic.empty_indices([index])

          # Backfill a single index
          tm.backfill(Programmer)

          count = Programmer.count

          until_expected(count) do
            es_document_count(index)
          end.should eq count

          programmers.each &.destroy
        end
      end
    end
  end
end
