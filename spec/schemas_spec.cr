require "./helper"

module SearchIngest
  describe Schemas do
    describe "#parents" do
      it "finds parent relations of a model" do
        schemas = Schemas.new
        parents = schemas.parents(Migraine)
        parents.should eq [{
          name:         Schemas.document_name(Programmer),
          index:        Programmer.table_name,
          routing_attr: :programmer_id,
        }]
      end
    end

    describe "#children" do
      it "finds the child relations of a model" do
        schemas = Schemas.new
        children = schemas.children(Programmer)
        children.should eq [
          Schemas.document_name(Beverage::Coffee),
          Schemas.document_name(Migraine),
        ]
      end
    end

    describe "#index_schema" do
      it "generates a schema for a model" do
        schemas = Schemas.new([Broke])
        schema = schemas.index_schema(Broke)
        schema.should be_a(String)

        # Check that the path to a field mapping exists
        json = JSON.parse(schema)
        json.dig?("mappings", "properties", "_document_type").should_not be_nil
      end
    end

    describe "#properties" do
      it "creates a mapping of table attributes to es types" do
        schemas = Schemas.new([Broke])
        mappings = schemas.properties(Broke).sort_by &.name
        mappings.should eq ([
          Schemas::TYPE_FIELD,
          Schemas::Field.new("breaks", "text", ["keyword"]),
          Schemas::Field.new("hasho", "object"),
          Schemas::Field.new("id", "keyword"),
          Schemas::Field.new("status", "boolean"),
        ])
      end

      it "allows specification of field type" do
        # RayGun ip attribute has an 'es_type' tag
        schemas = Schemas.new([RayGun])
        mappings = schemas.properties["RayGun"].sort_by &.name
        mappings.should eq ([
          Schemas::TYPE_FIELD,
          Schemas::Field.new("barrel_length", "float"),
          Schemas::Field.new("id", "keyword"),
          Schemas::Field.new("ip", "ip"),
          Schemas::Field.new("laser_colour", "text"),
          Schemas::Field.new("last_shot", "date"),
          Schemas::Field.new("rounds", "integer"),
        ])
      end

      it "collects properties for a model with associations" do
        schemas = Schemas.new
        children = schemas.children(Programmer)
        mappings = schemas.collect_index_properties(Programmer, children).sort_by &.name
        mappings.should eq [
          Schemas::TYPE_FIELD,
          Schemas::Field.new("created_at", "date"),
          Schemas::Field.new("duration", "date"),
          Schemas::Field.new("id", "keyword"),
          Schemas::Field.new("name", "text"),
          Schemas::Field.new("programmer_id", "keyword"),
          Schemas::Field.new("temperature", "integer"),
        ]
      end
    end
  end
end
