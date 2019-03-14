require "./helper"

describe RubberSoul::Table do
  it "creates a mapping of table attributes to es types" do
    table = RubberSoul::Table.new(Programmer)
    mappings = table.properties
    mappings.should eq [{:name, {type: "text"}}]
  end

  describe "indexes with associations" do
    it "finds the child tables" do
      table = RubberSoul::Table.new(Programmer)
      table.children.keys.should eq ["Coffee", "Migraine"]
    end

    it "finds the parent tables" do
      table = RubberSoul::Table.new(Coffee)
      table.parent_tables.keys.should eq ["Programmer"]
    end
  end
end
