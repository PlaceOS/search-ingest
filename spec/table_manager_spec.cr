require "./helper"

module SearchIngest
  describe TableManager do
    before_each do
      Elastic.empty_indices
    end

    describe "#reindex_all" do
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

        manager = TableManager.new(tables, backfill: false, watch: false)
        manager.load_success?.should be_true

        schema = JSON.parse(schemas.index_schema(Broke))

        updated_schema = JSON.parse(get_schema.call)

        # Check if updated schema applied
        updated_schema.should_not eq JSON.parse(wrong_schema)

        updated_schema["mappings"].as_h.rehash.should eq schema["mappings"].as_h.rehash

        updated_schema.dig("settings", "index", "analysis").as_h.rehash.should eq schema.dig("settings", "analysis").as_h.rehash
      end
    end
  end
end
