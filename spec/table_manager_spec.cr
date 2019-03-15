require "./helper"

describe RubberSoul::TableManager do
  describe "mapping schema" do
    it "generates a schema for specs" do
      tm = RubberSoul::TableManager.new(SPEC_MODELS)
      programmer = tm.tables.find { |t| t.name == "Programmer" }

      programmer.should_not be_nil
      unless programmer.nil?
        schema = tm.create_schema(programmer)
        schema.should be_a(String)
      end
    end
  end
end
