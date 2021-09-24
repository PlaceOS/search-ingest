require "./helper"

module SearchIngest
  describe TableManager do
    self.table_manager_test_suite(bulk: false)
    self.table_manager_test_suite(bulk: true)

    before_each do
      Elastic.empty_indices
    end

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

        tm = TableManager.new([Broke], backfill: false, watch: false)
        schemas = tm.schema_data
        schema = JSON.parse(schemas.index_schema(Broke))

        updated_schema = JSON.parse(get_schema.call)

        # Check if updated schema applied
        updated_schema.should_not eq JSON.parse(wrong_schema)

        updated_schema["mappings"].should eq schema["mappings"]

        updated_schema.dig("settings", "index", "analysis").as_h.rehash.should eq schema.dig("settings", "analysis").as_h.rehash
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
