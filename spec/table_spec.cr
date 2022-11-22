require "./helper"

module SearchIngest
  describe Table do
    before_each do
      Elastic.empty_indices
    end

    {true, false}.each { |bulk| table_test_suite(bulk) }
  end

  def self.table_test_suite(bulk : Bool)
    describe "#{bulk ? "bulk" : "single"}" do
      describe "#start" do
        it "creates ES documents from changefeed" do
          Elastic.bulk = bulk
          Programmer.clear
          refresh

          table = Table(Programmer).new(schemas)
          table.start

          sleep 500.milliseconds

          index = Programmer.table_name

          refresh

          sleep 500.milliseconds

          prog = Programmer.create!(name: "Rob Pike")

          until_expected(true) do
            Programmer.exists?(prog.id.as(String))
          end

          refresh

          until_expected(1) do
            es_document_count(index)
          end.should eq 1

          table.stop
        end
      end

      it "#reindex" do
        Elastic.bulk = bulk
        # Start non-watching table_manager
        table = Table(Programmer).new(schemas)
        table.backfill

        index = Programmer.table_name
        count_before_create = Programmer.count

        # Place some data in postgres
        num_created = 3
        programmers = Array.new(size: num_created) do |n|
          Programmer.create!(name: "Jim the #{n}th")
        end

        # Reindex
        table.reindex
        refresh

        until_expected(0) do
          es_document_count(index)
        end.should eq 0

        table.backfill

        expected = num_created + count_before_create
        # Check number of documents in elastic search
        until_expected(expected) do
          es_document_count(index)
        end.should eq expected

        programmers.each &.destroy
      end

      describe "#backfill" do
        it "refills a single es index with existing data in postgres" do
          Elastic.bulk = bulk
          Programmer.clear
          index = Programmer.table_name

          table = Table(Programmer).new(schemas)

          # Generate some data in postgres
          num_created = 5
          programmers = Array.new(size: num_created) do |n|
            Programmer.create!(name: "Jim the #{n}th")
          end

          # Remove documents from es
          Elastic.empty_indices([index])

          sleep 100.milliseconds

          # Backfill a single index
          table.backfill

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
