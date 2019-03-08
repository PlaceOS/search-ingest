require "./helper"

# Temporary specs until I (Caspian) figure out a good way to make all this model level macro business generic to RethinkORM models
# Perhaps through includes??
describe RubberSoul::Table do
  it "finds the child table mappings" do
    table = RubberSoul::Table.new(Programmer)
    table.child_tables.keys.should eq ["Coffee", "Migraine"]
  end

  it "creates a mapping of table attributes to es types" do
    table = RubberSoul::Table.new(Programmer)
    table.generate_mappings.should eq [{:name, "text"}]
  end
end
