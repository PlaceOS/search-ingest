require "./helper"

describe RubberSoul::TableManager do
  describe "mapping schema" do
    it "generates a schema for specs" do
      tm = TableManager.new(SPEC_MODELS)
      schema = tm.create_schema(Progammer)
      schema.should be_a(String)
    end
  end
end
